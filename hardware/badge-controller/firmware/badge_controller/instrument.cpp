/* SPECTRE badge flight instrument, protocols 1 and 2.
 * ESP32-C3; USB CDC only. GPIO20/21 are shift-register pins, never UART0.
 * Preserves buttons 0x17f, BLE UUIDs 0000/0001/0002 and conservative LEDs.
 * New 0003 accepts bounded CRC-checked telemetry fragments; 0004 reports health.
 * Palette framebuffer: 76,800 bytes + 5,120-byte transfer stripe, no video stream.
 */
#include <Arduino.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>
#include <Adafruit_NeoPixel.h>
#include <NimBLEDevice.h>
#include <SPI.h>
#include <math.h>
#include "motion_palette.h"
#include <Fonts/FreeSans9pt7b.h>
#include <Fonts/FreeSansBold12pt7b.h>
#include <Fonts/FreeSansBold18pt7b.h>
#include <Fonts/FreeSansBold24pt7b.h>

const int TFT_SCLK=1,TFT_MOSI=10,TFT_CS=2,TFT_DC=0,TFT_RST=4;
const int PIN_LOAD=20,PIN_CLOCK=21,PIN_DATA=7,PIN_START=9;
const uint16_t PHYSICAL_MASK=0x17f;
const int LED_PIN=3,LED_COUNT=6;
const uint8_t RAINBOW_LEVEL=48;
const unsigned long LED_STEP_MS=40,SEQUENCE_X_MS=3000;
const float ROTATIONS_PER_SEC=.30f;
#define SERVICE_UUID "5f1d0000-9c2b-4e7a-a3d6-0b8e1c4f2a71"
#define BUTTON_UUID "5f1d0001-9c2b-4e7a-a3d6-0b8e1c4f2a71"
#define PHASE_UUID "5f1d0002-9c2b-4e7a-a3d6-0b8e1c4f2a71"
#define INSTRUMENT_UUID "5f1d0003-9c2b-4e7a-a3d6-0b8e1c4f2a71"
#define INFO_UUID "5f1d0004-9c2b-4e7a-a3d6-0b8e1c4f2a71"
Adafruit_ST7789 tft(&SPI,TFT_CS,TFT_DC,TFT_RST);
Adafruit_NeoPixel strip(LED_COUNT,LED_PIN,NEO_GRB+NEO_KHZ800);
GFXcanvas8 canvas(320,240);
uint16_t stripe[320*8];
enum Ink {BG,PANEL,SKY,GROUND,WHITE,CYAN,GREEN,AMBER,RED,DIM,SKY2};
const uint16_t palette[]={0x0843,0x1085,0x2b57,0x18e4,0xef7e,0x2e9e,0x4f32,0xfd88,0xf986,0x7c31,0x3c3a,0x116d,0x118e,0x11ae,0x11cf,0x11ef,0x120f,0x1230,0x1250,0x1271,0x1291,0x12b2,0x12d2,0x12f3,0x1313,0x1334,0x1354,0x42,0x63,0x84,0xa5,0xc6,0xe7,0x108,0x129,0x14a,0x16b,0x18c,0x1ad,0x1cd,0x1ee,0x20f,0x230,0x251,0x272,0xa93,0xab4,0xad5,0x1356,0x23b7,0x3438,0x4499,0x551a,0x657b,0x75fc,0x865d,0x96de,0xa73e,0xb7bf};
NimBLECharacteristic *buttonChar,*phaseChar;
volatile bool clientConnected=false,telemetryFresh=false;
volatile uint8_t currentPhase=0;
volatile uint32_t phaseAt=0,buttonSequenceUntil=0,lastPacketAt=0;
volatile uint32_t goodPackets=0,badPackets=0,renderFrames=0;
volatile uint16_t heldMask=0,fps10=0;
portMUX_TYPE stateMux=portMUX_INITIALIZER_UNLOCKED;
struct Contact {int16_t x,y;uint8_t kind,selected;int16_t vx=0,vy=0,altitude=0;};
struct Telemetry {
 uint8_t mode=4,flags=0,count=0,landing=0,detail=0;
 uint16_t sequence=0,speed=0,heading=0,kills=0,pilot=1,range=0;
 int16_t roll=0,pitch=0;int32_t altitude=0;uint32_t score=0;
 bool extended=false;uint8_t engine=0,systems=0,accuracy=255,throttle=0;
 int16_t fpaYaw=0,fpaPitch=0,aimYaw=0,aimPitch=0,climb=0,gLoad=100;uint16_t seconds=0;int32_t worldX=0,worldZ=0;
 char name[13]="PILOT";Contact contacts[12]{};
};
Telemetry latest;

struct Presentation {uint8_t mode=4,launch=0;uint16_t pilot=0;bool firing=false;uint32_t resultAt=0,fireAt=0,launchAt=0,goUntil=0;};
Presentation show;
struct TrackPoint {int32_t x,z;uint16_t kills;};
TrackPoint track[160];uint16_t trackCount=0;uint32_t trackAt=0;int16_t peakG=100;
void recordTrack(const Telemetry&t,uint32_t now){
 if(!t.extended)return;
 peakG=max(peakG,t.gLoad);
 if(t.mode==1&&!((t.detail>>5)&3)&&now-trackAt>=1000){
  if(trackCount>=160){memmove(track,track+1,sizeof(TrackPoint)*159);trackCount=159;}
  track[trackCount++]={t.worldX,t.worldZ,t.kills};trackAt=now;
 }
}
int nearestThreat(const Telemetry&t){
 int found=-1;float nearest=1e20f;
 for(int i=0;i<t.count;i++)if(t.contacts[i].kind==4){float d=float(t.contacts[i].x)*t.contacts[i].x+float(t.contacts[i].y)*t.contacts[i].y+float(t.contacts[i].altitude)*t.contacts[i].altitude;if(d<nearest){nearest=d;found=i;}}
 return found;
}
int threatHour(const Contact&c){int hour=int(roundf(atan2f(c.x,c.y)*6/PI));return (hour+12)%12==0?12:(hour+12)%12;}
void presentationTick(uint32_t now){
 Telemetry t;bool fresh;portENTER_CRITICAL(&stateMux);t=latest;fresh=telemetryFresh;portEXIT_CRITICAL(&stateMux);
 if(!fresh||!clientConnected)return;
 uint8_t stage=t.mode==2?0:(t.detail>>5)&3;
 if(t.pilot!=show.pilot){show=Presentation();show.pilot=t.pilot;trackCount=0;peakG=100;trackAt=now;}
 if(t.mode==1&&(show.mode==0||show.mode==2||show.mode==4)){trackCount=0;peakG=100;trackAt=now;if(t.extended)track[trackCount++]={t.worldX,t.worldZ,t.kills};}
 if(t.mode==2&&show.mode!=2)show.resultAt=now;
 if(stage&&!show.launch){show.launchAt=now;trackCount=0;peakG=100;}
 recordTrack(t,now);
 if(!stage&&show.launch&&t.mode==1)show.goUntil=now+650;
 bool firing=t.mode==1&&(t.flags&128);
 if(firing&&!show.firing)show.fireAt=now;
 show.mode=t.mode;show.launch=stage;show.firing=firing;
}

uint16_t u16(const uint8_t*p){return uint16_t(p[0])|(uint16_t(p[1])<<8);}
uint32_t u32(const uint8_t*p){return uint32_t(u16(p))|(uint32_t(u16(p+2))<<16);}
uint16_t crc16(const uint8_t*p,size_t n){uint16_t c=0xffff;while(n--){c^=uint16_t(*p++)<<8;for(int k=0;k<8;k++)c=(c&0x8000)?(c<<1)^0x1021:c<<1;}return c;}
bool acceptFrame(const uint8_t*p,size_t n){
 if(n<46||n>216||p[0]!='S'||p[1]!='I'||(p[2]!=1&&p[2]!=2)||p[3]>4||p[5]>12||n!=(p[2]==2?72+12*p[5]:46+6*p[5])||crc16(p,n-2)!=u16(p+n-2))return false;
 Telemetry t;t.mode=p[3];t.flags=p[4];t.count=p[5];t.sequence=u16(p+6);
 t.roll=(int16_t)u16(p+8);t.pitch=(int16_t)u16(p+10);t.heading=u16(p+12);t.speed=u16(p+14);
 t.altitude=(int32_t)u32(p+16);t.score=u32(p+20);t.kills=u16(p+24);t.pilot=u16(p+26);t.landing=p[28];t.range=u16(p+41);t.detail=p[43];
 if(abs(int(t.roll))>18000||abs(int(t.pitch))>9000||t.heading>36000||t.speed>2000||t.altitude< -2000||t.altitude>1000000||t.pilot<1||t.pilot>9999||t.landing>4)return false;
 if(p[2]==2){t.extended=true;t.engine=p[44];t.systems=p[45];t.fpaYaw=(int16_t)u16(p+46);t.fpaPitch=(int16_t)u16(p+48);t.climb=(int16_t)u16(p+50);t.seconds=u16(p+52);t.accuracy=p[54];t.throttle=p[55];t.worldX=(int32_t)u32(p+56);t.worldZ=(int32_t)u32(p+60);t.gLoad=(int16_t)u16(p+64);t.aimYaw=(int16_t)u16(p+66);t.aimPitch=(int16_t)u16(p+68);
  if(abs(int(t.aimYaw))>18000||abs(int(t.aimPitch))>9000||t.engine>100||t.systems>7||abs(int(t.fpaYaw))>18000||abs(int(t.fpaPitch))>9000||t.throttle>100||(t.accuracy>100&&t.accuracy!=255)||abs(int(t.gLoad))>2000||t.worldX< -10000000||t.worldX>10000000||t.worldZ< -10000000||t.worldZ>10000000)return false;
 }
 memcpy(t.name,p+29,12);t.name[12]=0;
 for(int i=0;i<12&&t.name[i];i++)if(!((t.name[i]>='A'&&t.name[i]<='Z')||(t.name[i]>='0'&&t.name[i]<='9')||t.name[i]==' '||t.name[i]=='-'))return false;
 for(int i=0;i<t.count;i++){
  const uint8_t*q=p+(t.extended?70+i*12:44+i*6);t.contacts[i]={(int16_t)u16(q),(int16_t)u16(q+2),q[4],q[5]};
  if(q[4]<1||q[4]>4||q[5]>1)return false;
  if(t.extended){t.contacts[i].vx=(int16_t)u16(q+6);t.contacts[i].vy=(int16_t)u16(q+8);t.contacts[i].altitude=(int16_t)u16(q+10);}
 }
 portENTER_CRITICAL(&stateMux);
 telemetryFresh=t.mode!=4; if(telemetryFresh)latest=t;
 lastPacketAt=millis();goodPackets++;
 portEXIT_CRITICAL(&stateMux);return true;
}
class InstrumentCallbacks:public NimBLECharacteristicCallbacks {
 uint8_t assembly[216],frame=0,total=0,received=0;uint32_t began=0;
 void onWrite(NimBLECharacteristic*c,NimBLEConnInfo&) override {
  auto v=c->getValue();const uint8_t*p=v.data();size_t n=v.size();
  if(n<5||n>184||p[0]!=0xa7||p[3]<46||p[3]>216||p[2]+n-4>p[3]){badPackets++;return;}
  if(p[2]==0){frame=p[1];total=p[3];received=0;began=millis();}
  if(p[1]!=frame||p[3]!=total||p[2]!=received||millis()-began>500){received=0;badPackets++;return;}
  memcpy(assembly+received,p+4,n-4);received+=n-4;
  if(received==total){if(!acceptFrame(assembly,total))badPackets++;received=0;}
 }
};
class PhaseCallbacks:public NimBLECharacteristicCallbacks {
 void onWrite(NimBLECharacteristic*c,NimBLEConnInfo&) override {auto v=c->getValue();if(v.size()==1&&v[0]<=3){currentPhase=v[0];phaseAt=millis();}}
 void onRead(NimBLECharacteristic*c,NimBLEConnInfo&) override {uint8_t p=millis()-phaseAt<5000?currentPhase:0;c->setValue(&p,1);}
};
class InfoCallbacks:public NimBLECharacteristicCallbacks {
 void onRead(NimBLECharacteristic*c,NimBLEConnInfo&) override {
  char b[288];Telemetry t;portENTER_CRITICAL(&stateMux);t=latest;portEXIT_CRITICAL(&stateMux);
  snprintf(b,sizeof(b),"{\"fw\":\"instrument-6\",\"protocol\":2,\"extension\":26,\"packets\":%lu,\"bad\":%lu,\"frames\":%lu,\"fps10\":%u,\"heap\":%lu,\"seq\":%u,\"age\":%lu,\"buttons\":%u,\"mode\":%u,\"roll\":%d,\"pitch\":%d,\"detail\":%u,\"tracks\":%u,\"engine\":%u}",(unsigned long)goodPackets,(unsigned long)badPackets,(unsigned long)renderFrames,fps10,(unsigned long)ESP.getFreeHeap(),t.sequence,(unsigned long)(millis()-lastPacketAt),heldMask,t.mode,t.roll,t.pitch,t.detail,t.count,t.engine);
  c->setValue((uint8_t*)b,strlen(b));
 }
};
class ServerCallbacks:public NimBLEServerCallbacks {
 void onConnect(NimBLEServer*,NimBLEConnInfo&) override{clientConnected=true;}
 void onDisconnect(NimBLEServer*,NimBLEConnInfo&,int) override{clientConnected=false;NimBLEDevice::startAdvertising();}
};
uint8_t readShiftByte(){
 digitalWrite(PIN_CLOCK,LOW);digitalWrite(PIN_LOAD,LOW);delayMicroseconds(5);digitalWrite(PIN_LOAD,HIGH);delayMicroseconds(5);
 uint8_t v=0;for(int i=0;i<8;i++){v<<=1;if(digitalRead(PIN_DATA))v|=1;digitalWrite(PIN_CLOCK,HIGH);delayMicroseconds(5);digitalWrite(PIN_CLOCK,LOW);delayMicroseconds(5);}return v;
}
uint16_t decodeButtons(uint8_t raw,bool start){uint16_t m=0;for(int i=0;i<7;i++)if(!(raw&(1<<(7-i))))m|=1<<i;if(start)m|=0x100;return m&PHYSICAL_MASK;}
void buttonTask(void*){
 uint16_t candidate=0,reported=0;int stable=0;
 while(true){uint8_t raw=readShiftByte();uint16_t m=decodeButtons(raw,digitalRead(PIN_START)==LOW);
  if(m==candidate){if(stable<3)stable++;}else{candidate=m;stable=1;}
  if(stable>=3&&candidate!=reported){if(candidate&~reported)buttonSequenceUntil=millis()+SEQUENCE_X_MS;reported=candidate;heldMask=reported;
   uint8_t b[3]={(uint8_t)reported,(uint8_t)(reported>>8),raw};buttonChar->setValue(b,3);if(clientConnected)buttonChar->notify();
  }vTaskDelay(pdMS_TO_TICKS(5));
 }
}
// Sum of the 18 raw channel values, not a measured electrical current limit.
// Concentrated highlights can be brighter without making all six LEDs full-on.
const uint16_t LED_CHANNEL_BUDGET=240;
void ledTick(uint32_t now){
 static uint32_t last=0,lockedUntil=0;static bool wasLocked=false;
 if(now-last<LED_STEP_MS)return;last=now;
 Telemetry t;uint32_t received;bool fresh;
 portENTER_CRITICAL(&stateMux);t=latest;received=lastPacketAt;fresh=telemetryFresh;portEXIT_CRITICAL(&stateMux);
 bool live=clientConnected&&fresh&&goodPackets>0&&now-received<1500;
 bool flying=live&&(t.mode==1||t.mode==3),locked=flying&&(t.flags&1);
 if(locked&&!wasLocked)lockedUntil=now+1600;wasLocked=locked;
 uint8_t phase=(now-phaseAt<5000)?currentPhase:0;
 strip.clear();
 if(flying&&(t.flags&2)){
  // Maker front-view LED order: UL, UR, MR, BR, BL, ML.
  int threat=nearestThreat(t);int sector=threat<0?-1:((threatHour(t.contacts[threat])+1)/2)%6;
  int pixels[6]={0,1,2,3,4,5};
  if(sector<0){for(int i=0;i<6;i++)strip.setPixelColor(i,(now/250)%2?30:5,0,0);}
  else{int head=pixels[sector];strip.setPixelColor(head,(now/150)%2?64:24,2,0);strip.setPixelColor((head+5)%6,20,0,0);strip.setPixelColor((head+1)%6,20,0,0);}
 }else if(live&&show.launch){
  int lit=show.launch*2;for(int i=0;i<6;i++)strip.setPixelColor(i,0,i<lit?24:2,i<lit?42:5);
 }else if(flying&&show.goUntil>now){
  for(int i=0;i<6;i++)strip.setPixelColor(i,8,28,32);
 }else if(flying&&show.firing&&now-show.fireAt<350){
  int v=48*(350-(now-show.fireAt))/350;for(int i=0;i<6;i++)strip.setPixelColor(i,v/3,v,v);
 }else if(flying&&(t.detail&15)>0&&(t.detail&15)<15){
  int lit=((t.detail&15)*6+14)/15;for(int i=0;i<6;i++)strip.setPixelColor(i,0,i<lit?24:1,i<lit?36:4);
 }else if(flying&&now<lockedUntil){
  int v=24+int(16*(.5f+.5f*sinf(now*.010f)));
  for(int i=0;i<6;i++)strip.setPixelColor(i,0,v/2,v);
 }else if(live&&t.mode==2){
  int head=(now/180)%6;
  for(int i=0;i<6;i++)strip.setPixelColor(i,(t.flags&64)?0:10,(t.flags&64)?(i==head?48:18):5,(t.flags&64)?4:0);
 }else if(phase==1||phase==3){
  int head=(now/115)%6;
  for(int i=0;i<6;i++){int trail=(head-i+6)%6;strip.setPixelColor(i,trail==0?64:trail==1?24:4,0,0);}
 }else if(phase==2){
  // A brighter cyan highlight follows bank across the six blue cruise lights.
  int head=t.roll< -1200?5:t.roll>1200?2:0;
  for(int i=0;i<6;i++)strip.setPixelColor(i,0,i==head?22:4,i==head?44:24);
 }else if((int32_t)(buttonSequenceUntil-now)>0){
  for(int i=0;i<6;i++){uint16_t h=(uint16_t)(now*19.66f+i*10922);strip.setPixelColor(i,strip.ColorHSV(h,255,RAINBOW_LEVEL));}
 }else{
  int glow=8+int(8*(.5f+.5f*sinf(now*.0018f)));
  for(int i=0;i<6;i++)strip.setPixelColor(i,0,live?glow/3:0,glow);
 }
 uint16_t total=0;
 for(int i=0;i<6;i++){uint32_t c=strip.getPixelColor(i);total+=((c>>16)&255)+((c>>8)&255)+(c&255);}
 if(total>LED_CHANNEL_BUDGET)for(int i=0;i<6;i++){uint32_t c=strip.getPixelColor(i);strip.setPixelColor(i,((c>>16)&255)*LED_CHANNEL_BUDGET/total,((c>>8)&255)*LED_CHANNEL_BUDGET/total,(c&255)*LED_CHANNEL_BUDGET/total);}
 strip.show();
}
void txt(int x,int y,const char*s,int size=1,Ink color=WHITE){canvas.setFont(nullptr);canvas.setTextSize(size);canvas.setTextColor(color);canvas.setCursor(x,y);canvas.print(s);}
const GFXfont* face(int rank){return rank>=4?&FreeSansBold24pt7b:rank==3?&FreeSansBold18pt7b:rank==2?&FreeSansBold12pt7b:&FreeSans9pt7b;}
// Runtime measuring keeps every string inside its lane; no guessed widths.
int textW(const char*s,int rank){int16_t x1,y1;uint16_t w,h;canvas.setFont(face(rank));canvas.setTextSize(1);canvas.getTextBounds(s,0,0,&x1,&y1,&w,&h);canvas.setFont(nullptr);return w;}
void type(int x,int y,const char*s,int rank=1,Ink ink=WHITE){canvas.setFont(face(rank));canvas.setTextSize(1);canvas.setTextColor(ink);canvas.setCursor(x,y+(rank>=4?35:rank==3?26:rank==2?18:13));canvas.print(s);canvas.setFont(nullptr);}
void typeR(int x,int y,const char*s,int rank=1,Ink ink=WHITE){type(x-textW(s,rank),y,s,rank,ink);}
void typeC(int cx,int y,const char*s,int rank=1,Ink ink=WHITE){type(cx-textW(s,rank)/2,y,s,rank,ink);}
void value(int x,int y,long n,int rank=2,Ink ink=WHITE){char b[24];snprintf(b,sizeof(b),"%ld",n);type(x,y,b,rank,ink);}
void valueR(int x,int y,long n,int rank=2,Ink ink=WHITE){char b[24];snprintf(b,sizeof(b),"%ld",n);typeR(x,y,b,rank,ink);}
void small(int x,int y,const char*s,Ink ink=DIM){txt(x,y,s,1,ink);}
void smallR(int x,int y,const char*s,Ink ink=DIM){txt(x-int(strlen(s))*6,y,s,1,ink);}
// Subtle vertical wash between neighbouring dark-ramp indices; depth without panels.
void wash(int x,int y,int w,int h,uint8_t top,uint8_t bottom){
 for(int i=0;i<h;i+=2){uint8_t ink=uint8_t(int(top)+(int(bottom)-int(top))*i/max(1,h-1));canvas.drawFastHLine(x,y+i,w,ink);if(i+1<h)canvas.drawFastHLine(x,y+i+1,w,ink);}
}
// Bayer-dissolved shadow band: warnings dim the world softly instead of drawing a box.
void fadeBand(int x,int y,int w,int h,uint8_t ink){
 static const uint8_t dither[4][4]={{0,8,2,10},{12,4,14,6},{3,11,1,9},{15,7,13,5}};
 uint8_t*buf=canvas.getBuffer();
 for(int j=0;j<h;j++){int density=j<h-8?16:(h-j)*2;if(density<=0)break;for(int i=0;i<w;i++)if(dither[(y+j)&3][(x+i)&3]<density)buf[(y+j)*320+x+i]=ink;}
}
// Stepped radial glow from the dark blue ramp, drawn behind the airframe.
void halo(int cx,int cy,int r){
 uint8_t*buf=canvas.getBuffer();int r2=r*r;uint32_t gain=(uint32_t(80)<<16)/max(1,r2);
 static const uint8_t dither[4][4]={{0,8,2,10},{12,4,14,6},{3,11,1,9},{15,7,13,5}};
 for(int y=max(1,cy-r);y<min(239,cy+r);y++)for(int x=max(1,cx-r);x<min(319,cx+r);x++){int dx=x-cx,dy=y-cy,d2=dx*dx+dy*dy;if(d2<r2){uint32_t e=(uint32_t(r2-d2)*gain)>>16;uint8_t ink=27+(e>>4)+((e&15)>dither[y&3][x&3]);buf[y*320+x]=max(buf[y*320+x],ink);}}
}
void brackets(int x,int y,int r,Ink color){for(int sx=-1;sx<=1;sx+=2)for(int sy=-1;sy<=1;sy+=2){canvas.drawLine(x+sx*r,y+sy*r,x+sx*(r-5),y+sy*r,color);canvas.drawLine(x+sx*r,y+sy*r,x+sx*r,y+sy*(r-5),color);}}
void jet(int cx,int cy,float angle,float scale=1){
 const int8_t vertices[][3]={{0,0,-38},{-5,0,-8},{5,0,-8},{-32,0,13},{32,0,13},{-7,0,8},{7,0,8},{-6,0,25},{6,0,25},{-15,0,31},{15,0,31},{0,0,27},{0,-14,23},{0,-5,-14},{-3,-3,-4},{3,-3,-4}};
 const uint8_t edges[][2]={{0,1},{0,2},{1,3},{3,5},{5,7},{7,9},{9,11},{11,10},{10,8},{8,6},{6,4},{4,2},{1,5},{2,6},{0,11},{11,12},{12,7},{12,8},{0,13},{13,14},{14,15},{15,13}};
 const uint8_t faces[][3]={{0,1,2},{1,3,5},{2,4,6},{1,5,11},{2,6,11},{5,7,11},{6,8,11},{7,9,11},{8,10,11},{11,12,7},{11,12,8}};
 int x[16],y[16];float depth[16];float tilt=.66f;
 for(int i=0;i<16;i++){float vx=vertices[i][0]*cosf(angle)+vertices[i][2]*sinf(angle),vz=vertices[i][2]*cosf(angle)-vertices[i][0]*sinf(angle);float vy=vertices[i][1]*cosf(tilt)-vz*sinf(tilt);depth[i]=vz*cosf(tilt)+vertices[i][1]*sinf(tilt);float perspective=110/(110+depth[i])*scale;x[i]=cx+vx*perspective;y[i]=cy+vy*perspective;}
 uint8_t order[11];for(int i=0;i<11;i++)order[i]=i;
 for(int a=0;a<10;a++)for(int b=a+1;b<11;b++){float da=0,db=0;for(int k=0;k<3;k++){da+=depth[faces[order[a]][k]];db+=depth[faces[order[b]][k]];}if(db>da){uint8_t swap=order[a];order[a]=order[b];order[b]=swap;}}
 for(int k=0;k<11;k++){auto f=faces[order[k]];uint8_t ink=11+(order[k]*3)%9;canvas.fillTriangle(x[f[0]],y[f[0]],x[f[1]],y[f[1]],x[f[2]],y[f[2]],ink);}
 for(const auto&e:edges)canvas.drawLine(x[e[0]],y[e[0]],x[e[1]],y[e[1]],depth[e[0]]+depth[e[1]]>0?SKY2:CYAN);
 canvas.drawLine(x[13],y[13],x[14],y[14],WHITE);canvas.drawLine(x[13],y[13],x[15],y[15],WHITE);
 int edge=int(angle*30+3000)%22;canvas.drawLine(x[edges[edge][0]],y[edges[edge][0]],x[edges[edge][1]],y[edges[edge][1]],WHITE);
}
void bloom(uint32_t elapsed,int cx=170,int cy=120){
 const auto light=Cinematic::prepareBloom(elapsed,cx,cy);uint8_t*buf=canvas.getBuffer();
 for(int y=1;y<239;y++)for(int x=1;x<319;x++)buf[y*320+x]=light.sample(x,y);
}
void ready(const Telemetry&t,bool linked,uint32_t now){
 // Gradient ground, halo, hairline grid: the airframe floats in space, not in panels.
 wash(0,0,320,240,27,31);
 halo(150,120,64);
 for(int x=16;x<310;x+=24)canvas.drawFastVLine(x,52,108,11);
 // Leader lines first so the jet draws over them.
 canvas.drawLine(60,80,106,98,DIM);canvas.drawLine(82,122,108,122,DIM);
 canvas.drawLine(248,86,198,104,DIM);canvas.drawLine(254,146,200,138,DIM);
 jet(150,120,.45f+.6f*sinf(now*.0003f),2.35f);
 canvas.drawFastHLine(100,190,100,27);canvas.drawFastHLine(110,193,80,28);canvas.drawFastHLine(122,196,56,29);
 int scan=70+int((now/11)%110);uint8_t*scanPixels=canvas.getBuffer();for(int y=scan-1;y<=scan;y++)for(int x=70;x<245;x++){uint8_t ink=scanPixels[y*320+x];if((ink>=11&&ink<=26)||ink==CYAN||ink==SKY2)scanPixels[y*320+x]=y==scan?CYAN:SKY2;}
 type(16,9,"SPECTRE",3,WHITE);
 small(18,42,t.name,DIM);
 char b[24];snprintf(b,sizeof(b),"X-26 / %02u",t.pilot);smallR(304,20,b,CYAN);
 canvas.drawFastHLine(16,50,170,33);
 small(16,74,"ENGINE",DIM);if(t.extended)snprintf(b,sizeof(b),"%u%%",t.engine);else snprintf(b,sizeof(b),"--");small(16,85,b,CYAN);
 small(16,116,"FLIGHT CTL",DIM);small(16,127,linked?"LINKED":"WAIT",linked?CYAN:AMBER);
 smallR(304,80,"DATALINK",DIM);smallR(304,91,linked?"LIVE":"SEARCH",linked?CYAN:AMBER);
 smallR(304,140,"WEAPONS",DIM);smallR(304,151,!t.extended?"--":t.systems&4?"HOT":"SAFE",t.systems&4?AMBER:CYAN);
 type(16,182,linked?"Ready.":"Standby",3,linked?WHITE:AMBER);
 small(18,222,linked?"START / BEGIN SORTIE":"WAITING FOR BLUETOOTH",CYAN);
}
void launchCard(const Telemetry&t,uint32_t now){
 uint32_t elapsed=now-show.launchAt;bloom(min(elapsed,uint32_t(1650)),240,110);
 // Stylized perspective runway, not a streamed or fabricated terrain map.
 for(int i=-4;i<=4;i++)canvas.drawLine(218+i*5,73,218+i*74,239,11);
 float travel=Cinematic::launchTravel(elapsed*(100+t.engine)/100);for(int i=0;i<7;i++){float z=(i+travel)/7;int y=76+z*z*163;canvas.drawLine(218-int(z*280),y,218+int(z*280),y,SKY2);}
 type(16,12,"LAUNCH",2,WHITE);
 char b[24];
 // Count carries depth: two dark-ramp echoes drop-shadow the live digit.
 snprintf(b,sizeof(b),"0%u",4-show.launch);
 canvas.setFont(&FreeSansBold24pt7b);canvas.setTextSize(2);
 canvas.setTextColor(27);canvas.setCursor(23,152);canvas.print(b);
 canvas.setTextColor(30);canvas.setCursor(18,149);canvas.print(b);
 canvas.setTextColor(WHITE);canvas.setCursor(14,146);canvas.print(b);
 canvas.setTextSize(1);canvas.setFont(nullptr);
 small(18,174,show.launch==1?"CONTROL LINKED":show.launch==2?"FLIGHT SYSTEMS READY":"DEPARTURE",CYAN);
 char engine[22];snprintf(engine,sizeof(engine),"ENGINE %u%%",t.engine);type(18,192,t.extended?engine:"SYSTEMS ONLINE",1,WHITE);
 for(int i=0;i<6;i++)canvas.drawFastHLine(18+i*47,227,38,i<show.launch*2?CYAN:33);
}
void compass(const Telemetry&t){
 float heading=t.heading*.01f;for(int i=-4;i<=4;i++){int tick=(int(heading/15)+i)*15;int x=160+int((tick-heading)*2.2f);if(x<22||x>298)continue;int bearing=(tick%360+360)%360;char b[5];if(bearing%90==0)snprintf(b,sizeof(b),"%s",bearing==0?"N":bearing==90?"E":bearing==180?"S":"W");else snprintf(b,sizeof(b),"%03d",bearing);small(x-int(strlen(b))*3,8,b,bearing%90==0?CYAN:DIM);canvas.drawFastVLine(x,19,3,DIM);}
 canvas.fillTriangle(156,24,164,24,160,20,WHITE);
}
void contactGlyph(int x,int y,const Contact&c,int scale=1){
 Ink ink=c.kind==4?RED:c.kind==2?AMBER:c.kind==3?WHITE:CYAN;
 if(c.kind==4||c.kind==3)canvas.fillTriangle(x,y-3*scale,x-2*scale,y+2*scale,x+2*scale,y+2*scale,ink);
 else{canvas.drawLine(x,y-3*scale,x+3*scale,y,ink);canvas.drawLine(x+3*scale,y,x,y+3*scale,ink);canvas.drawLine(x,y+3*scale,x-3*scale,y,ink);canvas.drawLine(x-3*scale,y,x,y-3*scale,ink);}
}
void sensor(const Telemetry&t,uint32_t now,int cx,int cy,int radius,bool expanded){
 canvas.drawCircle(cx,cy,radius,DIM);if(expanded)canvas.drawCircle(cx,cy,radius/2,11);
 canvas.drawFastHLine(cx-radius,cy,radius*2,11);canvas.drawFastVLine(cx,cy-radius,radius*2,11);
 float sweep=now*.0009f;canvas.drawLine(cx,cy,cx+sinf(sweep)*radius,cy-cosf(sweep)*radius,SKY2);
 canvas.drawLine(cx,cy,cx+sinf(sweep-.13f)*radius,cy-cosf(sweep-.13f)*radius,33);
 canvas.drawLine(cx,cy,cx+sinf(sweep-.26f)*radius,cy-cosf(sweep-.26f)*radius,30);
 for(int i=0;i<t.count;i++){const Contact&c=t.contacts[i];float x=c.x*(radius/3000.f),y=-c.y*(radius/3000.f),d=sqrtf(x*x+y*y);if(d>radius-8){x*=float(radius-8)/d;y*=float(radius-8)/d;}int px=cx+x,py=cy+y;
  if(expanded&&t.extended){int vx=constrain(int(c.vx*radius/3000.f*2),-23,23),vy=constrain(int(-c.vy*radius/3000.f*2),-23,23);canvas.drawLine(px,py,px+vx,py+vy,c.kind==4?RED:DIM);if(abs(vx)+abs(vy)>2)canvas.fillCircle(px+vx,py+vy,1,c.kind==4?RED:DIM);}
  // Inbound missiles carry a short red dart pointing at ownship, not just a dot.
  if(expanded&&c.kind==4){float hx=cx-px,hy=cy-py,hd=sqrtf(hx*hx+hy*hy);if(hd>4)canvas.drawLine(px,py,px+int(hx*14/hd),py+int(hy*14/hd),RED);}
  contactGlyph(px,py,c,1);
  if(c.selected){brackets(px,py,5+(15-(t.detail&15))/3,CYAN);if(expanded){canvas.drawLine(cx,cy,px,py,SKY2);char alt[12];snprintf(alt,sizeof(alt),"%+dM",c.altitude);small(px+10,constrain(py-8,(t.flags&2)?83:40,218),alt,CYAN);}}
 }
 canvas.fillTriangle(cx,cy-5,cx-3,cy+3,cx+3,cy+3,WHITE);
}
void flight(const Telemetry&t,float bank,float pitch,uint32_t now){
 // Horizon lives in the center lane; speed/altitude tapes float on a quiet side wash.
 const int cx=160,cy=109;float s=sinf(bank*PI/180),c=cosf(bank*PI/180);int sn=s*1024,cs=c*1024,offset=pitch*2*1024;
 uint8_t*buf=canvas.getBuffer();for(int y=25;y<180;y++){int v=(y-cy)*cs+(1-cx)*sn-offset;for(int x=1;x<319;x++){int sky=constrain(7+(-v)/18000,7,14);int edge=min(72,min(x,319-x));buf[y*320+x]=v>=0?BG:27+sky*edge/72;v+=sn;}}
 compass(t);
 for(int deg=-30;deg<=30;deg+=10){float d=(pitch-deg)*2;int half=deg==0?72:22;int ax=cx-half*c+d*s,ay=cy+half*s+d*c,bx=cx+half*c+d*s,by=cy-half*s+d*c;if(ay>27&&ay<178&&by>27&&by<178){canvas.drawLine(ax,ay,bx,by,deg==0?SKY2:DIM);if(deg)small(min(bx+4,206),by-3,abs(deg)==10?"10":abs(deg)==20?"20":"30",DIM);}}
 // Flight-path marker follows the actual velocity vector, separate from the nose.
 int fx=cx+constrain(int(t.fpaYaw*.018f),-67,67),fy=cy-constrain(int(t.fpaPitch*.018f),-45,45);
 canvas.drawCircle(fx,fy,6,CYAN);canvas.drawLine(fx-14,fy,fx-6,fy,CYAN);canvas.drawLine(fx+6,fy,fx+14,fy,CYAN);canvas.drawLine(fx,fy-6,fx,fy-11,CYAN);
 canvas.drawLine(cx-28,cy,cx-11,cy,WHITE);canvas.drawLine(cx+11,cy,cx+28,cy,WHITE);canvas.drawLine(cx-11,cy,cx,cy+5,WHITE);canvas.drawLine(cx,cy+5,cx+11,cy,WHITE);
 for(int i=0;i<t.count;i++)if(t.contacts[i].selected){const Contact&target=t.contacts[i];float bearing=atan2f(target.x,target.y)*180/PI;float elevation=atan2f(target.altitude,sqrtf(float(target.x)*target.x+float(target.y)*target.y))*180/PI-pitch;int tx=constrain(cx+int(bearing*2),86,222),ty=constrain(cy-int(elevation*2),45,159);int size=10+(15-(t.detail&15));brackets(tx,ty,size,t.flags&1?AMBER:CYAN);if(t.extended){int leadX=constrain(cx+int(t.aimYaw*.02f),80,228),leadY=constrain(cy-int(t.aimPitch*.02f),45,159);canvas.drawCircle(leadX,leadY,2,DIM);canvas.drawLine(tx,ty,leadX,leadY,DIM);}char range[16];snprintf(range,sizeof(range),"%u M",t.range);small(tx-18,constrain(ty+size+6,40,171),range,CYAN);break;}
 for(int i=-2;i<=2;i++){canvas.drawFastHLine(58,100+i*16,5,33);canvas.drawFastHLine(236,100+i*16,5,33);}
 small(10,80,"KTS",DIM);valueR(60,94,t.speed,2,WHITE);
 smallR(310,80,"ALT FT",DIM);if(t.altitude>=100000){char altitude[16];snprintf(altitude,sizeof(altitude),"%ldK",(long)(t.altitude/1000));typeR(310,94,altitude,2,WHITE);}else valueR(310,94,t.altitude,2,WHITE);
 if(t.extended){int h=t.throttle*44/100;canvas.drawFastVLine(6,186,44,33);canvas.drawFastVLine(6,230-h,h,t.systems&1?AMBER:CYAN);}
 char g[16];snprintf(g,sizeof(g),"%.1f G",t.gLoad*.01f);type(13,184,t.extended?g:"FLIGHT",2,WHITE);
 char eng[20];snprintf(eng,sizeof(eng),"ENG %u%% %s",t.engine,t.systems&1?"AB":"");small(14,208,t.extended?eng:"LINK LIVE",t.systems&1?AMBER:DIM);
 smallR(308,182,t.flags&1?"TARGET":"LOCK QUALITY",DIM);
 char lock[16];snprintf(lock,sizeof(lock),"%u%%",(t.detail&15)*100/15);typeR(308,192,t.flags&1?"LOCK":lock,2,t.flags&1?AMBER:CYAN);
 smallR(308,214,t.flags&128?"FIRING":!t.extended?"MSL --":t.systems&4?"MSL READY":"STANDBY",t.flags&128?WHITE:DIM);
 sensor(t,now,160,211,23,false);
 small(13,231,t.mode==3?"PAUSED":t.flags&32?"ASSIST":"MANUAL",DIM);smallR(306,231,t.flags&8?"GEAR DOWN":"GEAR UP",DIM);
}
void threatOverlay(const Telemetry&t,uint32_t now){
 // The threat overthrows hierarchy: the world dissolves into shadow behind the call.
 int index=nearestThreat(t);fadeBand(0,28,320,50,BG);type(13,30,"MISSILE",3,RED);
 char b[28];if(index>=0){const Contact&c=t.contacts[index];snprintf(b,sizeof(b),"%d O'CLOCK",threatHour(c));typeR(304,36,b,2,WHITE);
  float range=sqrtf(float(c.x)*c.x+float(c.y)*c.y),closing=range>1?-(float(c.x)*c.vx+float(c.y)*c.vy)/range:0;
  if(t.extended&&closing>1&&range/closing<100)snprintf(b,sizeof(b),"CLOSE ~%.1f S",range/closing);else snprintf(b,sizeof(b),"RANGE %.1f KM",range*.001f);smallR(304,62,b,RED);
  float a=atan2f(c.x,c.y),ux=sinf(a),uy=-cosf(a),px=-uy,py=ux;
  int cx=t.detail&16?116:160,cy=t.detail&16?130:119;
  canvas.drawLine(cx+int(ux*92),cy+int(uy*76),cx+int(ux*44),cy+int(uy*36),RED);
  // Three chevrons march inward along the bearing; motion reads as approach.
  for(int k=0;k<3;k++){int d=84-int((now/7+k*29)%40);int qx=cx+int(ux*d),qy=cy+int(uy*d*.83f);int bx=qx-int(ux*7),by=qy-int(uy*7);canvas.drawLine(bx+int(px*4),by+int(py*4),qx,qy,RED);canvas.drawLine(bx-int(px*4),by-int(py*4),qx,qy,RED);}
 }else typeR(304,36,"BEARING --",2,WHITE);
 small(13,64,t.systems&2?"COUNTERMEASURES READY":"COUNTERMEASURES RECHARGING",RED);
}
void tactical(const Telemetry&t,uint32_t now){
 type(15,9,"Tactical",2,WHITE);char b[32];snprintf(b,sizeof(b),"3 KM / %u TRACKS",t.count);smallR(304,22,b,CYAN);
 sensor(t,now,116,130,89,true);
 int selected=-1;for(int i=0;i<t.count;i++)if(t.contacts[i].selected){selected=i;break;}
 small(216,60,"SELECTED",DIM);
 if(selected>=0){const Contact&c=t.contacts[selected];
  type(215,74,c.kind==4?"MISSILE":c.kind==2?"BOSS":c.kind==3?"CONTACT":"TRACK",1,c.kind==4?RED:c.kind==2?AMBER:CYAN);
  snprintf(b,sizeof(b),"%.2f KM",sqrtf(float(c.x)*c.x+float(c.y)*c.y)*.001f);type(215,99,b,1,WHITE);
  if(t.extended)snprintf(b,sizeof(b),"ALT %+d M",c.altitude);else snprintf(b,sizeof(b),"ALT --");small(216,124,b,DIM);
  float range=sqrtf(float(c.x)*c.x+float(c.y)*c.y),closing=range>1?-(float(c.x)*c.vx+float(c.y)*c.vy)/range:0;
  if(t.extended)snprintf(b,sizeof(b),"%s %.0f M/S",closing>=0?"CLOSING":"OPENING",fabsf(closing));else snprintf(b,sizeof(b),"REL VEL --");small(216,140,b,closing>1?AMBER:DIM);
  small(216,160,t.flags&1?"LOCK STABLE":"ACQUIRING",t.flags&1?AMBER:CYAN);
 }
 else{type(216,76,"Scanning",1,CYAN);small(216,100,"NO SELECTION",DIM);}
 int m=nearestThreat(t);if(m>=0){snprintf(b,sizeof(b),"MSL %d OCLOCK",threatHour(t.contacts[m]));small(216,186,b,RED);}
 small(15,230,"HOLD DOWN / FLIGHT",DIM);
}
void result(const Telemetry&t,uint32_t now){
 uint32_t elapsed=now-show.resultAt;float progress=min(1.f,elapsed/2200.f);bool success=t.flags&64;
 if(elapsed<1700)bloom(elapsed,276,165);
 small(16,13,"POST-FLIGHT / TELEMETRY",CYAN);
 const char*title=success?"Mission complete":"Sortie ended";type(15,31,title,2,WHITE);
 canvas.drawFastHLine(15,58,textW(title,2),33);
 uint32_t shown=elapsed>=2200?t.score:uint32_t(double(t.score)*(1-pow(1-progress,3)));char b[32];snprintf(b,sizeof(b),"%lu",(unsigned long)shown);type(13,67,b,t.score>9999999?3:4,WHITE);small(16,111,"SORTIE SCORE",DIM);
 small(16,130,"RECORDED ROUTE",DIM);
 // Actual sampled flight path; amber ticks mark increments in cleared targets.
 if(trackCount>1){int32_t minX=track[0].x,maxX=minX,minZ=track[0].z,maxZ=minZ;for(int i=1;i<trackCount;i++){minX=min(minX,track[i].x);maxX=max(maxX,track[i].x);minZ=min(minZ,track[i].z);maxZ=max(maxZ,track[i].z);}float scale=min(130.f/max(1,int(maxX-minX)),58.f/max(1,int(maxZ-minZ)));int count=max(2,int(trackCount*progress));int lastX=17,lastY=142;for(int i=0;i<min(count,int(trackCount));i++){int x=18+(track[i].x-minX)*scale,y=143+(track[i].z-minZ)*scale;if(i){canvas.drawLine(lastX,lastY,x,y,SKY2);if(track[i].kills>track[i-1].kills)canvas.fillCircle(x,y,2,AMBER);}lastX=x;lastY=y;}canvas.fillCircle(lastX,lastY,2,CYAN);}
 else small(17,157,"TRACE UNAVAILABLE",DIM);
 snprintf(b,sizeof(b),"%u CLEARED",t.kills);small(16,212,b,CYAN);if(t.extended)snprintf(b,sizeof(b),"%02u:%02u",t.seconds/60,t.seconds%60);else snprintf(b,sizeof(b),"--:--");small(145,212,b,DIM);
 small(217,117,"LANDING",DIM);const char*grade=t.landing!=1?"--":t.detail>=90?"S":t.detail>=80?"A":t.detail>=65?"B":t.detail>=50?"C":"D";
 // The grade arrives with a shadow echo, then a materializing scanline pass.
 float arrival=Cinematic::gradeArrival(elapsed);if(arrival>0){type(225,137,grade,4,Ink(34));type(222,134,grade,4,t.landing==1?GREEN:DIM);if(arrival<1){int scan=134+int(arrival*40);canvas.drawFastHLine(215,scan,73,WHITE);}}
 if(t.accuracy==255)snprintf(b,sizeof(b),"GUN ACC --");else snprintf(b,sizeof(b),"GUN ACC %u%%",t.accuracy);small(216,190,b,DIM);
 if(t.extended)snprintf(b,sizeof(b),"PEAK %.1f G",peakG*.01f);else snprintf(b,sizeof(b),"PEAK --");small(216,212,b,DIM);
 small(16,231,"START / REPLAY",DIM);smallR(304,231,"NEXT PILOT / LAPTOP",DIM);
}
void render(uint32_t now){
 static float bank=0,pitch=0;static uint32_t prior=0;
 Telemetry t;uint32_t received;bool fresh;portENTER_CRITICAL(&stateMux);t=latest;received=lastPacketAt;fresh=telemetryFresh;portEXIT_CRITICAL(&stateMux);
 bool linked=clientConnected&&goodPackets>0&&now-received<1500&&fresh;
 float dt=min(.1f,(now-prior)*.001f);prior=now;float difference=t.roll*.01f-bank;while(difference>180)difference-=360;while(difference< -180)difference+=360;bank+=difference*(1-expf(-dt*18));while(bank>180)bank-=360;while(bank< -180)bank+=360;pitch+=(t.pitch*.01f-pitch)*(1-expf(-dt*18));
 canvas.fillScreen(BG);
 if(show.launch&&linked)launchCard(t,now);
 else if(t.mode==0||t.mode==4)ready(t,linked,now);
 else if(t.mode==2)result(t,now);
 else{
  if(t.detail&16)tactical(t,now);else flight(t,bank,pitch,now);
  if(show.goUntil>now){int x=constrain(int((show.goUntil-now)*320/650),0,319);canvas.drawFastVLine(x,26,150,CYAN);}
  if(show.firing&&now-show.fireAt<300){uint8_t*buf=canvas.getBuffer();for(int x=1;x<319;x++){int energy=Cinematic::dischargeIndex(x,now-show.fireAt)-27;for(int y=25;y<46;y++){int level=energy*(46-y)/21;uint8_t old=buf[y*320+x];if(level>7&&(old==BG||old>=11))buf[y*320+x]=27+level;}}}
  if(t.flags&2)threatOverlay(t,now);
 }
 if(t.mode==1&&t.landing>=3){fadeBand(0,71,320,60,BG);typeC(160,79,t.landing==3?"AIRFRAME LOST":"PILOT RECOVERY",2,AMBER);}
 if(!linked&&t.mode!=4){canvas.fillRect(0,218,320,22,BG);typeC(160,220,"LINK LOST / DATA HELD",1,AMBER);}
 // Reticle corner ticks frame the scene; no full border box.
 canvas.drawFastHLine(2,2,12,33);canvas.drawFastVLine(2,2,12,33);
 canvas.drawFastHLine(306,2,12,33);canvas.drawFastVLine(317,2,12,33);
 canvas.drawFastHLine(2,237,9,33);canvas.drawFastVLine(2,226,12,33);
 canvas.drawFastHLine(309,237,9,33);canvas.drawFastVLine(317,226,12,33);
 canvas.drawRect(0,0,320,240,12);
 // Hash small tiles, then transfer only each stripe's changed span. No LCD
 // clear between frames, no second framebuffer, one SPI bulk write per span.
 static uint32_t hashes[30][10]{};static bool first=true;
 const uint8_t* pixels=canvas.getBuffer();
 for(int row=0;row<30;row++){
  int left=10,right=-1;
  for(int tile=0;tile<10;tile++){
   uint32_t hash=2166136261u;
   for(int dy=0;dy<8;dy++)for(int dx=0;dx<32;dx++){hash^=pixels[(row*8+dy)*320+tile*32+dx];hash*=16777619u;}
   if(first||hashes[row][tile]!=hash){left=min(left,tile);right=tile;hashes[row][tile]=hash;}
  }
  if(right<left)continue;
  int width=(right-left+1)*32,index=0;
  for(int dy=0;dy<8;dy++)for(int dx=0;dx<width;dx++){uint8_t ink=pixels[(row*8+dy)*320+left*32+dx];stripe[index++]=palette[ink<sizeof(palette)/sizeof(palette[0])?ink:BG];}
  tft.startWrite();tft.setAddrWindow(left*32,row*8,width,8);tft.writePixels(stripe,index);tft.endWrite();taskYIELD();
 }
 first=false;
 renderFrames++;
}
void setup(){
 Serial.begin(115200);
 pinMode(PIN_LOAD,OUTPUT);pinMode(PIN_CLOCK,OUTPUT);pinMode(PIN_DATA,INPUT);pinMode(PIN_START,INPUT_PULLUP);digitalWrite(PIN_CLOCK,LOW);digitalWrite(PIN_LOAD,HIGH);
 strip.begin();strip.clear();strip.show();SPI.begin(TFT_SCLK,-1,TFT_MOSI,TFT_CS);
 tft.init(240,320);tft.setRotation(3);tft.invertDisplay(true);tft.setSPISpeed(40000000);tft.fillScreen(ST77XX_BLACK);
 if(!canvas.getBuffer()){tft.setCursor(10,20);tft.setTextColor(ST77XX_WHITE);tft.print("DISPLAY MEMORY LOW");}
 canvas.setTextWrap(false);
 NimBLEDevice::init("HTN Badge Buttons");NimBLEDevice::setPower(-12);NimBLEDevice::setMTU(185);
 NimBLEServer*server=NimBLEDevice::createServer();server->setCallbacks(new ServerCallbacks());
 NimBLEService*service=server->createService(SERVICE_UUID);
 buttonChar=service->createCharacteristic(BUTTON_UUID,NIMBLE_PROPERTY::READ|NIMBLE_PROPERTY::NOTIFY);
 uint8_t zero[3]={0,0,0xfe};buttonChar->setValue(zero,3);
 phaseChar=service->createCharacteristic(PHASE_UUID,NIMBLE_PROPERTY::READ|NIMBLE_PROPERTY::WRITE|NIMBLE_PROPERTY::WRITE_NR);phaseChar->setCallbacks(new PhaseCallbacks());uint8_t idle=0;phaseChar->setValue(&idle,1);
 auto instrument=service->createCharacteristic(INSTRUMENT_UUID,NIMBLE_PROPERTY::WRITE|NIMBLE_PROPERTY::WRITE_NR,184);instrument->setCallbacks(new InstrumentCallbacks());
 auto info=service->createCharacteristic(INFO_UUID,NIMBLE_PROPERTY::READ,288);info->setCallbacks(new InfoCallbacks());
 service->start();auto adv=NimBLEDevice::getAdvertising();adv->addServiceUUID(SERVICE_UUID);adv->enableScanResponse(true);NimBLEDevice::startAdvertising();
 xTaskCreate(buttonTask,"buttons",3072,nullptr,2,nullptr);
 Serial.printf("SPECTRE instrument-6 ready; heap=%u framebuffer=%s\n",ESP.getFreeHeap(),canvas.getBuffer()?"OK":"FAILED");
}
void loop(){
 static uint32_t last=0,fpsAt=0,lastCount=0;uint32_t now=millis();presentationTick(now);ledTick(now);
 if(canvas.getBuffer()&&now-last>=67){last=now;render(now);}
 if(now-fpsAt>=1000){fps10=(renderFrames-lastCount)*10000/(now-fpsAt);fpsAt=now;lastCount=renderFrames;}
 delay(1);
}
