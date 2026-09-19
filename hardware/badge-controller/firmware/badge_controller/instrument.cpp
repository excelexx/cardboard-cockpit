/* SPECTRE badge flight instrument, protocol 1.
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
const uint16_t palette[]={0x0843,0x1085,0x2b57,0x18e4,0xef7e,0x2e9e,0x4f32,0xfd88,0xf986,0x428b,0x3c3a,0x116d,0x118e,0x11ae,0x11cf,0x11ef,0x120f,0x1230,0x1250,0x1271,0x1291,0x12b2,0x12d2,0x12f3,0x1313,0x1334,0x1354};
NimBLECharacteristic *buttonChar,*phaseChar;
volatile bool clientConnected=false,telemetryFresh=false;
volatile uint8_t currentPhase=0;
volatile uint32_t phaseAt=0,buttonSequenceUntil=0,lastPacketAt=0;
volatile uint32_t goodPackets=0,badPackets=0,renderFrames=0;
volatile uint16_t heldMask=0,fps10=0;
portMUX_TYPE stateMux=portMUX_INITIALIZER_UNLOCKED;
struct Contact {int16_t x,y;uint8_t kind,selected;};
struct Telemetry {
 uint8_t mode=4,flags=0,count=0,landing=0;
 uint16_t sequence=0,speed=0,heading=0,kills=0,pilot=1,range=0;
 int16_t roll=0,pitch=0;int32_t altitude=0;uint32_t score=0;
 char name[13]="PILOT";Contact contacts[12]{};
};
Telemetry latest;
uint16_t u16(const uint8_t*p){return uint16_t(p[0])|(uint16_t(p[1])<<8);}
uint32_t u32(const uint8_t*p){return uint32_t(u16(p))|(uint32_t(u16(p+2))<<16);}
uint16_t crc16(const uint8_t*p,size_t n){uint16_t c=0xffff;while(n--){c^=uint16_t(*p++)<<8;for(int k=0;k<8;k++)c=(c&0x8000)?(c<<1)^0x1021:c<<1;}return c;}
bool acceptFrame(const uint8_t*p,size_t n){
 if(n<46||n>118||p[0]!='S'||p[1]!='I'||p[2]!=1||p[3]>4||p[5]>12||n!=46+6*p[5]||crc16(p,n-2)!=u16(p+n-2))return false;
 Telemetry t;t.mode=p[3];t.flags=p[4];t.count=p[5];t.sequence=u16(p+6);
 t.roll=(int16_t)u16(p+8);t.pitch=(int16_t)u16(p+10);t.heading=u16(p+12);t.speed=u16(p+14);
 t.altitude=(int32_t)u32(p+16);t.score=u32(p+20);t.kills=u16(p+24);t.pilot=u16(p+26);t.landing=p[28];t.range=u16(p+41);
 if(abs(int(t.roll))>18000||abs(int(t.pitch))>9000||t.heading>36000||t.speed>2000||t.altitude< -2000||t.altitude>1000000||t.pilot<1||t.pilot>9999||t.landing>4)return false;
 memcpy(t.name,p+29,12);t.name[12]=0;
 for(int i=0;i<12&&t.name[i];i++)if(!((t.name[i]>='A'&&t.name[i]<='Z')||(t.name[i]>='0'&&t.name[i]<='9')||t.name[i]==' '||t.name[i]=='-'))return false;
 for(int i=0;i<t.count;i++){
  const uint8_t*q=p+44+i*6;t.contacts[i]={(int16_t)u16(q),(int16_t)u16(q+2),q[4],q[5]};
  if(q[4]<1||q[4]>4||q[5]>1)return false;
 }
 portENTER_CRITICAL(&stateMux);
 telemetryFresh=t.mode!=4; if(telemetryFresh)latest=t;
 lastPacketAt=millis();goodPackets++;
 portEXIT_CRITICAL(&stateMux);return true;
}
class InstrumentCallbacks:public NimBLECharacteristicCallbacks {
 uint8_t assembly[118],frame=0,total=0,received=0;uint32_t began=0;
 void onWrite(NimBLECharacteristic*c,NimBLEConnInfo&) override {
  auto v=c->getValue();const uint8_t*p=v.data();size_t n=v.size();
  if(n<5||n>184||p[0]!=0xa7||p[3]<46||p[3]>118||p[2]+n-4>p[3]){badPackets++;return;}
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
  char b[220];Telemetry t;portENTER_CRITICAL(&stateMux);t=latest;portEXIT_CRITICAL(&stateMux);
  snprintf(b,sizeof(b),"{\"fw\":\"instrument-2.1\",\"packets\":%lu,\"bad\":%lu,\"frames\":%lu,\"fps10\":%u,\"heap\":%lu,\"seq\":%u,\"age\":%lu,\"buttons\":%u,\"mode\":%u,\"roll\":%d,\"pitch\":%d}",(unsigned long)goodPackets,(unsigned long)badPackets,(unsigned long)renderFrames,fps10,(unsigned long)ESP.getFreeHeap(),t.sequence,(unsigned long)(millis()-lastPacketAt),heldMask,t.mode,t.roll,t.pitch);
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
  // Three red lights alternate across the panel; a threat is never decorative.
  int half=(now/250)%2;for(int i=0;i<6;i++)if(i/3==half)strip.setPixelColor(i,64,2,0);
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
  int head=constrain(3+t.roll/1800,0,5);
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
void txt(int x,int y,const char*s,int size=1,Ink color=WHITE){canvas.setTextSize(size);canvas.setTextColor(color);canvas.setCursor(x,y);canvas.print(s);}
void number(int x,int y,long v,int size=2,Ink color=WHITE){char b[24];snprintf(b,sizeof(b),"%ld",v);txt(x,y,b,size,color);}
void identity(const Telemetry&t){char b[24];txt(8,7,t.name,1,CYAN);snprintf(b,sizeof(b),"SPECTRE-%02u",t.pilot);txt(226,7,b,1,WHITE);canvas.drawFastHLine(8,23,304,DIM);canvas.fillCircle(207,10,2,clientConnected&&telemetryFresh?GREEN:AMBER);}
void jet(int cx,int cy,float angle){
 const int8_t points[][2]={{0,-32},{5,-7},{29,13},{6,9},{6,23},{14,30},{0,25},{-14,30},{-6,23},{-6,9},{-29,13},{-5,-7},{0,-32}};
 float s=sinf(angle),c=cosf(angle);for(int i=1;i<13;i++)canvas.drawLine(cx+points[i-1][0]*c-points[i-1][1]*s,cy+points[i-1][0]*s+points[i-1][1]*c,cx+points[i][0]*c-points[i][1]*s,cy+points[i][0]*s+points[i][1]*c,CYAN);
}
void ready(const Telemetry&t,bool linked,uint32_t now){
 txt(22,43,"PILOT",2,DIM);txt(22,66,t.name,3,WHITE);jet(260,88,now*.00065f);
 canvas.drawRoundRect(14,138,292,65,8,DIM);txt(37,152,linked?"READY FOR TAKEOFF":"WAITING FOR COCKPIT",2,linked?GREEN:AMBER);
 txt(57,184,linked?"START TO LAUNCH":"BLUETOOTH LINK",1,DIM);txt(69,220,"SPECTRE FLIGHT INSTRUMENT",1,CYAN);
}
void horizon(const Telemetry&t,float bank,float pitch){
 const int x0=8,y0=37,w=196,h=144,cx=106,cy=109;
 int sn=(int)(sinf(bank*PI/180)*1024),cs=(int)(cosf(bank*PI/180)*1024),offset=(int)(pitch*1.4f*1024);
 uint8_t*buf=canvas.getBuffer();
 for(int y=y0;y<y0+h;y++){int v=(y-cy)*cs+(x0-cx)*sn-offset;for(int x=x0;x<x0+w;x++){buf[y*320+x]=v>=0?GROUND:SKY;v+=sn;}}
 float s=sinf(bank*PI/180),c=cosf(bank*PI/180);
 for(int deg=-30;deg<=30;deg+=10){float d=(pitch-deg)*1.4;int half=deg==0?72:18;uint16_t ink=deg==0?WHITE:DIM;
  int ax=cx-half*c+d*s,ay=cy+half*s+d*c,bx=cx+half*c+d*s,by=cy-half*s+d*c;
  // Keep ladder inside the instrument viewport by clipping to its bounds.
  if(ax>=x0&&ax<x0+w&&bx>=x0&&bx<x0+w&&ay>=y0&&ay<y0+h&&by>=y0&&by<y0+h)canvas.drawLine(ax,ay,bx,by,ink);
 }
 canvas.drawRect(x0,y0,w,h,DIM);canvas.drawLine(cx-36,cy,cx-12,cy,AMBER);canvas.drawLine(cx+12,cy,cx+36,cy,AMBER);canvas.drawLine(cx-12,cy,cx,cy+8,AMBER);canvas.drawLine(cx,cy+8,cx+12,cy,AMBER);
 // Fixed bank scale and moving bank pointer, deliberately separate from pitch.
 for(int mark=-60;mark<=60;mark+=15){float a=mark*PI/180;int outer=61,inner=(mark%30==0)?54:57;canvas.drawLine(cx+sinf(a)*inner,cy-cosf(a)*inner,cx+sinf(a)*outer,cy-cosf(a)*outer,WHITE);}
 float a=constrain(bank,-65.f,65.f)*PI/180;int px=cx+sinf(a)*49,py=cy-cosf(a)*49;canvas.fillTriangle(px,py-3,px-3,py+3,px+3,py+3,CYAN);
 canvas.fillRect(12,155,188,20,PANEL);char data[32];snprintf(data,sizeof(data),"BANK %02d   PITCH %+03d",(int)roundf(fabsf(bank)),(int)roundf(pitch));txt(17,161,data,1,CYAN);
 txt(12,190,"KTS",1,DIM);number(12,202,t.speed,2);txt(118,190,"ALT FT",1,DIM);number(118,202,t.altitude,2);
}
void radar(const Telemetry&t,uint32_t now){
 const int cx=263,cy=99,r=44;
 canvas.fillRect(213,32,104,180,PANEL);canvas.drawCircle(cx,cy,r,DIM);canvas.drawCircle(cx,cy,22,DIM);
 canvas.drawLine(cx-r,cy,cx+r,cy,DIM);canvas.drawLine(cx,cy-r,cx,cy+r,DIM);
 float sweep=now*.0017f;canvas.drawLine(cx,cy,cx+sinf(sweep)*r,cy-cosf(sweep)*r,SKY2);
 for(int i=0;i<t.count;i++){Contact b=t.contacts[i];float x=b.x*(r/3000.f),y=-b.y*(r/3000.f);float d=sqrtf(x*x+y*y);if(d>r-3){x*=float(r-3)/d;y*=float(r-3)/d;}
  int px=cx+(int)x,py=cy+(int)y;Ink ink=b.kind==4?RED:b.kind==3?WHITE:b.kind==2?AMBER:GREEN;
  if(b.kind==2){canvas.drawLine(px,py-4,px+4,py,ink);canvas.drawLine(px+4,py,px,py+4,ink);canvas.drawLine(px,py+4,px-4,py,ink);canvas.drawLine(px-4,py,px,py-4,ink);}else if(b.kind==4){canvas.fillTriangle(px,py-4,px-3,py+3,px+3,py+3,ink);}else canvas.fillCircle(px,py,b.kind==3?1:2,ink);
  if(b.selected){canvas.drawRect(px-6,py-6,13,13,CYAN);}
 }
 canvas.fillTriangle(cx,cy-4,cx-3,cy+3,cx+3,cy+3,WHITE);
 txt(236,148,"RADAR 3KM",1,CYAN);
 txt(218,39,"TAC",1,DIM);txt(289,39,"FWD",1,CYAN);char b[24];snprintf(b,sizeof(b),"HDG %03u",(t.heading/100)%360);txt(235,165,b,1,WHITE);
 snprintf(b,sizeof(b),"CONTACTS %u",t.count);txt(223,181,b,1,DIM);
 if(t.range){snprintf(b,sizeof(b),"LOCK %uM",t.range);txt(221,197,b,1,AMBER);}
}
void result(const Telemetry&t){
 bool success=t.flags&64;txt(22,43,success?"MISSION COMPLETE":"MISSION INCOMPLETE",2,success?GREEN:AMBER);
 txt(22,79,"SCORE",1,DIM);number(20,94,t.score,4,WHITE);txt(22,144,"GEESE CLEARED",1,DIM);number(226,141,t.kills,2,CYAN);
 txt(22,180,t.landing==1?"LANDING: SAFE / STOPPED":"LANDING: NOT COMPLETED",1,t.landing==1?GREEN:AMBER);
 txt(22,213,"START: REPLAY   NEXT PILOT: LAPTOP",1,DIM);
}
void render(uint32_t now){
 static float bank=0,pitch=0;static uint32_t prior=0,lockUntil=0;static bool wasLocked=false;static uint16_t lastPilot=0;
 Telemetry t;uint32_t received;portENTER_CRITICAL(&stateMux);t=latest;received=lastPacketAt;portEXIT_CRITICAL(&stateMux);
 bool linked=clientConnected&&goodPackets>0&&now-received<1500&&telemetryFresh;
 // Keep the last valid instrument page during a link interruption.
 // Freshness is explicitly annunciated; never invent a mission transition.
 float dt=min(.1f,(now-prior)*.001f);prior=now;
 float difference=t.roll*.01f-bank;while(difference>180)difference-=360;while(difference< -180)difference+=360;
 bank+=difference*(1-expf(-dt*18));pitch+=(t.pitch*.01f-pitch)*(1-expf(-dt*18));
 if(lastPilot!=t.pilot){lastPilot=t.pilot;lockUntil=0;wasLocked=false;}
 bool locked=t.flags&1;if(locked&&!wasLocked)lockUntil=now+1600;wasLocked=locked;
 canvas.fillScreen(BG);identity(t);
 if(t.mode==0||t.mode==4)ready(t,linked,now);
 else if(t.mode==2)result(t);
 else{
  horizon(t,bank,pitch);radar(t,now);
  const char*status=t.mode==3?"FLIGHT PAUSED":(t.flags&2)?"MISSILE WARNING":(t.flags&4)?(t.landing==2?"LANDING ASSIST":"B - LAND AT SFO"):(now<lockUntil)?"TARGET LOCKED":(t.flags&128)?"WEAPONS ACTIVE":(t.flags&32)?"FLIGHT ASSIST":"MANUAL FLIGHT";
  Ink ink=(t.flags&2)?RED:(t.flags&4)?AMBER:GREEN;
  canvas.fillRect(0,223,320,17,((t.flags&2)&&(now/250)%2)?RED:BG);txt(12,227,status,1,ink==RED?WHITE:ink);
 }
 if(!linked&&t.mode!=4){canvas.fillRect(0,223,320,17,AMBER);txt(38,227,"LINK LOST - DATA HELD",1,BG);}
 // Opaque machined-navy bezel; matching corner values keep the frame continuous.
 // The modest cobalt highlight peaks midway along each rail, never at a join.
 for(int y=0;y<240;y++){uint8_t edge=11+15*(119-abs(y-119))/119;canvas.drawFastHLine(0,y,3,edge);canvas.drawFastHLine(317,y,3,edge);}
 for(int x=0;x<320;x++){uint8_t edge=11+15*(159-abs(x-159))/159;canvas.drawFastVLine(x,0,3,edge);canvas.drawFastVLine(x,237,3,edge);}
 for(int corner=0;corner<4;corner++){int x=corner&1?315:4,y=corner&2?235:4,dx=corner&1?-1:1,dy=corner&2?-1:1;canvas.drawLine(x,y,x+dx*12,y,CYAN);canvas.drawLine(x,y,x,y+dy*12,CYAN);}
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
 auto info=service->createCharacteristic(INFO_UUID,NIMBLE_PROPERTY::READ,220);info->setCallbacks(new InfoCallbacks());
 service->start();auto adv=NimBLEDevice::getAdvertising();adv->addServiceUUID(SERVICE_UUID);adv->enableScanResponse(true);NimBLEDevice::startAdvertising();
 xTaskCreate(buttonTask,"buttons",3072,nullptr,2,nullptr);
 Serial.printf("SPECTRE instrument-2.1 ready; heap=%u framebuffer=%s\n",ESP.getFreeHeap(),canvas.getBuffer()?"OK":"FAILED");
}
void loop(){
 static uint32_t last=0,fpsAt=0,lastCount=0;uint32_t now=millis();ledTick(now);
 if(canvas.getBuffer()&&now-last>=67){last=now;render(now);}
 if(now-fpsAt>=1000){fps10=(renderFrames-lastCount)*10000/(now-fpsAt);fpsAt=now;lastCount=renderFrames;}
 delay(1);
}
