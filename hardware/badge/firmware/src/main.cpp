// Hack the North 2026 badge: optional replacement USB bridge.
// Pin map was independently recovered and tested through USB/JTAG.
// This firmware is a separate build artifact; see verification.md for flash status.
#include <Arduino.h>
#include <ArduinoJson.h>
#include <SPI.h>
#include <Wire.h>
#include <WiFi.h>
#include <BLEDevice.h>
#include <BLEScan.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>
#include <Adafruit_NeoPixel.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

namespace Pins {
constexpr int lcdDC=0, lcdClock=1, lcdCS=2, leds=3, lcdReset=4;
constexpr int sda=5, scl=6, buttonData=7, start=9, lcdMosi=10;
constexpr int buttonLoad=20, buttonClock=21;
}
constexpr uint8_t ACCEL=0x19, NFC=0x26;
Adafruit_ST7789 lcd(Pins::lcdCS, Pins::lcdDC, Pins::lcdReset);
Adafruit_NeoPixel leds(6, Pins::leds, NEO_GRB+NEO_KHZ800);
uint32_t sequence=0, nextState=0, nextMotion=0;
uint16_t streamHz=50;
bool sensorReady=false, wifiScanning=false, bleScanning=false;
volatile bool bleDone=false;
int16_t motion[3]={0,0,0};
uint32_t motionAt=0;
char commandLine[2048];
size_t commandLength=0;
bool discardLine=false;

struct BLEObservation { uint8_t address[6]; int rssi; char name[33]; };
QueueHandle_t bleQueue=nullptr;
class ScanCallbacks: public BLEAdvertisedDeviceCallbacks {
  void onResult(BLEAdvertisedDevice device) override {
    BLEObservation sample{};
    memcpy(sample.address, device.getAddress().getNative(), 6);
    sample.rssi=device.getRSSI();
    if (device.haveName()) {
      auto name=device.getName();
      size_t n=name.size()<32 ? name.size() : 32;
      memcpy(sample.name, name.data(), n);
    }
    if (bleQueue) xQueueSend(bleQueue, &sample, 0);
  }
};
ScanCallbacks bleCallbacks;

void emit(JsonDocument &doc) { serializeJson(doc, Serial); Serial.write('\n'); }
bool readReg(uint8_t address, uint8_t reg, uint8_t *data, size_t n) {
  Wire.beginTransmission(address); Wire.write(reg);
  if (Wire.endTransmission(false)!=0) return false;
  size_t received=Wire.requestFrom(address, n, true);
  if (received!=n) { while (Wire.available()) Wire.read(); return false; }
  for (size_t i=0;i<n;i++) data[i]=Wire.read();
  return true;
}
bool writeReg(uint8_t address, uint8_t reg, const uint8_t *data, size_t n) {
  Wire.beginTransmission(address); Wire.write(reg); Wire.write(data,n);
  return Wire.endTransmission()==0;
}
bool writeByte(uint8_t address, uint8_t reg, uint8_t data) {
  return writeReg(address,reg,&data,1);
}
uint8_t rawButtons() {
  digitalWrite(Pins::buttonClock,LOW);
  digitalWrite(Pins::buttonLoad,LOW); delayMicroseconds(1);
  digitalWrite(Pins::buttonLoad,HIGH); delayMicroseconds(1);
  uint8_t value=0;
  for (int i=0;i<8;i++) {
    value=(value<<1) | digitalRead(Pins::buttonData);
    digitalWrite(Pins::buttonClock,HIGH); delayMicroseconds(1);
    digitalWrite(Pins::buttonClock,LOW); delayMicroseconds(1);
  }
  return value;
}
uint16_t buttonMask(uint8_t raw) {
  uint16_t mask=0;
  for (int i=0;i<7;i++) if (!(raw & (1<<(7-i)))) mask|=1<<i;
  if (!digitalRead(Pins::start)) mask|=1<<8;
  return mask;
}
void sampleMotion() {
  uint8_t bytes[6];
  if (sensorReady && readReg(ACCEL,0xa8,bytes,6)) {
    for (int i=0;i<3;i++) motion[i]=int16_t(uint16_t(bytes[i*2]) | (uint16_t(bytes[i*2+1])<<8)) >> 4;
    motionAt=millis();
  }
}
void appendState(JsonDocument &doc) {
  uint8_t raw=rawButtons();
  doc["version"]=1; doc["sequence"]=sequence++; doc["uptime_ms"]=millis();
  doc["shift_raw"]=raw; doc["held_mask"]=buttonMask(raw);
  doc["motion_ok"]=sensorReady && millis()-motionAt<250;
  JsonArray values=doc.createNestedArray("accel_mg");
  for (int i=0;i<3;i++) values.add(motion[i]);
}
bool integer(JsonVariant value, int minimum, int maximum) {
  return value.is<int>() && value.as<int>()>=minimum && value.as<int>()<=maximum;
}
bool rgb(JsonVariantConst pixel) {
  if (!pixel.is<JsonArrayConst>() || pixel.size()!=3) return false;
  for (JsonVariantConst channel:pixel.as<JsonArrayConst>())
    if (!channel.is<int>() || channel.as<int>()<0 || channel.as<int>()>255) return false;
  return true;
}
void command(const char *line) {
  DynamicJsonDocument request(4096), reply(4096);
  auto error=deserializeJson(request,line);
  reply["type"]="result"; reply["ok"]=false;
  if (error || !request.is<JsonObject>()) { reply["error"]="invalid_json"; emit(reply); return; }
  if (!request["id"].isNull()) reply["id"]=request["id"];
  const char *cmd=request["cmd"] | "";
  if (!strcmp(cmd,"info")) {
    reply["board"]="HTN2026 ESP32-C3"; reply["firmware"]="badge-control-bridge-1";
    reply["cpu_mhz"]=ESP.getCpuFreqMHz(); reply["flash_bytes"]=ESP.getFlashChipSize();
    reply["free_heap"]=ESP.getFreeHeap(); reply["sdk"]=ESP.getSdkVersion();
    reply["accel_ready"]=sensorReady; reply["led_count"]=6;
    reply["display_width"]=320; reply["display_height"]=240;
    reply["ok"]=true;
  } else if (!strcmp(cmd,"buttons") || !strcmp(cmd,"state")) {
    appendState(reply); reply["ok"]=true;
  } else if (!strcmp(cmd,"stream") && integer(request["hz"],0,100)) {
    streamHz=request["hz"]; reply["hz"]=streamHz; reply["ok"]=true;
  } else if (!strcmp(cmd,"led") && request["pixels"].is<JsonArray>() && request["pixels"].size()==6) {
    bool valid=true;
    for (JsonVariant pixel:request["pixels"].as<JsonArray>()) valid &= rgb(pixel);
    if (valid) {
      for (int i=0;i<6;i++) {
        auto pixel=request["pixels"][i]; leds.setPixelColor(i,leds.Color(pixel[0],pixel[1],pixel[2]));
      }
      leds.show(); reply["ok"]=true;
    }
  } else if (!strcmp(cmd,"fill") && integer(request["color"],0,65535)) {
    lcd.fillScreen(request["color"]); reply["ok"]=true;
  } else if (!strcmp(cmd,"rect") && integer(request["x"],0,319) && integer(request["y"],0,239)
             && integer(request["w"],1,320) && integer(request["h"],1,240) && integer(request["color"],0,65535)) {
    int x=request["x"],y=request["y"],w=request["w"],h=request["h"];
    if (x+w<=320 && y+h<=240) { lcd.fillRect(x,y,w,h,request["color"]); reply["ok"]=true; }
  } else if (!strcmp(cmd,"text") && request["text"].is<const char*>()
             && integer(request["x"],0,319) && integer(request["y"],0,239)
             && integer(request["color"],0,65535) && integer(request["size"],1,4)) {
    const char *text=request["text"];
    if (strlen(text)<=80) {
      lcd.setCursor(request["x"],request["y"]); lcd.setTextColor(request["color"]);
      lcd.setTextSize(request["size"]); lcd.print(text); reply["ok"]=true;
    }
  } else if (!strcmp(cmd,"accel")) {
    sampleMotion(); appendState(reply); reply["ok"]=sensorReady;
  } else if (!strcmp(cmd,"i2c.read") && integer(request["address"],8,119)
             && integer(request["register"],0,255) && integer(request["count"],1,64)) {
    uint8_t data[64]; size_t count=request["count"];
    bool ok=readReg(request["address"],request["register"],data,count);
    reply["ok"]=ok;
    if (ok) { auto array=reply.createNestedArray("data"); for(size_t i=0;i<count;i++) array.add(data[i]); }
  } else if (!strcmp(cmd,"i2c.write") && integer(request["address"],8,119)
             && integer(request["register"],0,255) && request["data"].is<JsonArray>()
             && request["data"].size()>0 && request["data"].size()<=64) {
    uint8_t data[64]; size_t n=0; bool valid=true;
    for (JsonVariant item:request["data"].as<JsonArray>()) {
      if (!integer(item,0,255)) { valid=false; break; } data[n++]=item;
    }
    if (valid) reply["ok"]=writeReg(request["address"],request["register"],data,n);
  } else if (!strcmp(cmd,"nfc.info")) {
    uint8_t version=0; bool ok=readReg(NFC,0x37,&version,1);
    reply["ok"]=ok; reply["address"]=NFC; reply["version_register"]=version;
    reply["tag_reading_verified"]=false;
  } else if (!strcmp(cmd,"wifi.scan") && !wifiScanning && !bleScanning) {
    WiFi.persistent(false); WiFi.setAutoReconnect(false); WiFi.mode(WIFI_STA);
    WiFi.disconnect(false,false);
    int status=WiFi.scanNetworks(true,true);
    wifiScanning=status==WIFI_SCAN_RUNNING; reply["ok"]=wifiScanning;
  } else if (!strcmp(cmd,"ble.scan") && !bleScanning && !wifiScanning && integer(request["seconds"],1,10)) {
    if (!bleQueue) {
      bleQueue=xQueueCreate(16,sizeof(BLEObservation));
      BLEDevice::init("HTNBadgeLab");
      BLEDevice::getScan()->setAdvertisedDeviceCallbacks(&bleCallbacks);
      BLEDevice::getScan()->setActiveScan(false);
      BLEDevice::getScan()->setInterval(100); BLEDevice::getScan()->setWindow(80);
    }
    bleDone=false;
    bleScanning=bleQueue && BLEDevice::getScan()->start(request["seconds"].as<int>(),
      [](BLEScanResults){bleDone=true;},false);
    reply["ok"]=bleScanning;
  } else if (!strcmp(cmd,"radio.stop")) {
    if (bleScanning) BLEDevice::getScan()->stop();
    WiFi.scanDelete(); WiFi.mode(WIFI_OFF); wifiScanning=false;
    reply["ok"]=true;
  }
  if (!reply["ok"].as<bool>() && !reply.containsKey("error")) reply["error"]="unsupported_busy_or_invalid_arguments";
  emit(reply);
}
void radioEvents() {
  if (wifiScanning && WiFi.scanComplete()!=WIFI_SCAN_RUNNING) {
    int n=WiFi.scanComplete(); DynamicJsonDocument event(6144);
    event["type"]="wifi.scan"; event["ok"]=n>=0;
    auto networks=event.createNestedArray("networks");
    for (int i=0;i<n && i<20;i++) {
      auto item=networks.createNestedObject();
      item["ssid"]=WiFi.SSID(i); item["rssi"]=WiFi.RSSI(i); item["channel"]=WiFi.channel(i);
    }
    emit(event); WiFi.scanDelete(); WiFi.mode(WIFI_OFF); wifiScanning=false;
  }
  BLEObservation sample;
  for (int i=0;bleQueue && i<4 && xQueueReceive(bleQueue,&sample,0)==pdTRUE;i++) {
    DynamicJsonDocument event(512); char address[18];
    snprintf(address,sizeof(address),"%02X:%02X:%02X:%02X:%02X:%02X",sample.address[0],sample.address[1],sample.address[2],sample.address[3],sample.address[4],sample.address[5]);
    event["type"]="ble.observation"; event["address"]=address;
    event["rssi"]=sample.rssi; event["name"]=sample.name; emit(event);
  }
  if (bleDone) {
    bleDone=false; bleScanning=false; BLEDevice::getScan()->clearResults();
    DynamicJsonDocument event(128); event["type"]="ble.complete"; emit(event);
  }
}
void setup() {
  Serial.begin(115200); // Native USB CDC; UART0 GPIO20/21 belong to the buttons.
  pinMode(Pins::buttonLoad,OUTPUT); digitalWrite(Pins::buttonLoad,HIGH);
  pinMode(Pins::buttonClock,OUTPUT); digitalWrite(Pins::buttonClock,LOW);
  pinMode(Pins::buttonData,INPUT); pinMode(Pins::start,INPUT_PULLUP);
  Wire.begin(Pins::sda,Pins::scl,100000); Wire.setTimeOut(20);
  uint8_t who=0;
  sensorReady=readReg(ACCEL,0x0f,&who,1) && who==0x11;
  if (sensorReady) sensorReady=writeByte(ACCEL,0x23,0x88) && writeByte(ACCEL,0x20,0x57);
  SPI.begin(Pins::lcdClock,-1,Pins::lcdMosi,Pins::lcdCS);
  lcd.init(240,320); lcd.setRotation(1); lcd.invertDisplay(true);
  lcd.fillScreen(ST77XX_BLACK); lcd.setTextSize(2); lcd.setTextColor(ST77XX_WHITE);
  lcd.setCursor(12,16); lcd.print("Badge Control Lab");
  lcd.setCursor(12,44); lcd.print("USB badge bridge");
  leds.begin(); leds.clear(); leds.show();
}
void loop() {
  // Bounded command processing keeps continuous input from starving.
  for (int budget=0;budget<256 && Serial.available();budget++) {
    int c=Serial.read();
    if (c=='\n') {
      if (!discardLine && commandLength) { commandLine[commandLength]=0; command(commandLine); }
      commandLength=0; discardLine=false;
    } else if (c!='\r' && !discardLine) {
      if (commandLength+1<sizeof(commandLine)) commandLine[commandLength++]=char(c);
      else { commandLength=0; discardLine=true; }
    }
  }
  uint32_t now=millis();
  if (int32_t(now-nextMotion)>=0) { sampleMotion(); nextMotion=now+20; }
  if (streamHz && int32_t(now-nextState)>=0 && Serial) {
    DynamicJsonDocument event(512); event["type"]="state"; appendState(event); emit(event);
    nextState=now+1000/streamHz;
  }
  radioEvents(); delay(1);
}
