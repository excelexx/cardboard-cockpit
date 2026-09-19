/*
 * Hack the North badge (ESP32-C3) - final build.
 *
 *   - Pixel-art fighter held on the LCD.
 *   - "Sequence X": the rotating rainbow, unchanged, but only for ~3 s
 *     after a button press. Dark the rest of the time.
 *   - Buttons reported over BLE (NimBLE) for the web tester.
 *
 * Pins from hardware/badge/docs/:
 *   LCD (ST7789 320x240): SCLK=1 MOSI=10 CS=2 DC=0 RESET=4, landscape,
 *       inversion on. No MISO, so the panel cannot be read back.
 *   LEDs: six WS2812-style pixels on GPIO3, GRB order.
 *   Buttons: 74HC165 shift register PL=20 CP=21 Q7=7; START direct on
 *       GPIO9. Rest byte is 0xfe because raw bit 0 is an unused input.
 *
 * An earlier build with Bluedroid + a permanently lit strip reset in a
 * loop. This uses NimBLE (far less RAM), minimum TX power, and leaves the
 * LEDs dark unless a button was just pressed. docs/subsystems.md warns the
 * 500 mA USB figure does not guarantee LED + radio + display together.
 *
 * Board: ESP32C3 Dev Module, USB CDC On Boot = Enabled.
 * UART0 must stay unused: its pins ARE the button load/clock lines.
 */

#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>
#include <Adafruit_NeoPixel.h>
#include <NimBLEDevice.h>
#include <SPI.h>
#include "jet_image.h"

// ---- Display ---------------------------------------------------------------
const int TFT_SCLK = 1, TFT_MOSI = 10, TFT_CS = 2, TFT_DC = 0, TFT_RST = 4;
Adafruit_ST7789 tft = Adafruit_ST7789(&SPI, TFT_CS, TFT_DC, TFT_RST);

// ---- Buttons ---------------------------------------------------------------
const int PIN_LOAD = 20, PIN_CLOCK = 21, PIN_DATA = 7, PIN_START = 9;
const uint16_t PHYSICAL_MASK = 0x17f;   // drop code 7, the unused input

// ---- Sequence X ------------------------------------------------------------
// Exactly the rainbow that looked right: same level, same rate, same fps.
// Only the *when* has changed.
const int LED_PIN = 3, LED_COUNT = 6;
const uint8_t RAINBOW_LEVEL = 14;
const unsigned long LED_STEP_MS = 40;        // ~25 fps
const float ROTATIONS_PER_SEC = 0.30f;
const unsigned long SEQUENCE_X_MS = 3000;    // run for ~3 s per press

Adafruit_NeoPixel strip(LED_COUNT, LED_PIN, NEO_GRB + NEO_KHZ800);
unsigned long lastLedStep = 0;
unsigned long sequenceUntil = 0;   // 0 = idle
bool ledsLit = false;
float ledPhase = 0.0f;

// ---- BLE -------------------------------------------------------------------
#define SERVICE_UUID "5f1d0000-9c2b-4e7a-a3d6-0b8e1c4f2a71"
#define CHAR_UUID    "5f1d0001-9c2b-4e7a-a3d6-0b8e1c4f2a71"
NimBLECharacteristic *buttonChar = nullptr;
bool clientConnected = false;

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer *, NimBLEConnInfo &) override {
    clientConnected = true;
  }
  void onDisconnect(NimBLEServer *, NimBLEConnInfo &, int) override {
    clientConnected = false;
    NimBLEDevice::startAdvertising();   // else it vanishes after one client
  }
};

// ---- Rainbow ---------------------------------------------------------------
void hueToRgb(float hue, uint8_t level, uint8_t &r, uint8_t &g, uint8_t &b) {
  hue = hue - floorf(hue);
  float h6 = hue * 6.0f;
  int sector = (int)h6;
  float f = h6 - sector;
  uint8_t rise = (uint8_t)(level * f), fall = (uint8_t)(level * (1.0f - f));
  switch (sector % 6) {
    case 0: r = level; g = rise;  b = 0;     break;
    case 1: r = fall;  g = level; b = 0;     break;
    case 2: r = 0;     g = level; b = rise;  break;
    case 3: r = 0;     g = fall;  b = level; break;
    case 4: r = rise;  g = 0;     b = level; break;
    default: r = level; g = 0;    b = fall;  break;
  }
}

void drawRainbow(float phase) {
  for (int i = 0; i < LED_COUNT; i++) {
    uint8_t r, g, b;
    hueToRgb(phase + (float)i / LED_COUNT, RAINBOW_LEVEL, r, g, b);
    strip.setPixelColor(i, strip.Color(r, g, b));
  }
  strip.show();
}

void ledsOff() {
  strip.clear();
  strip.show();
}

// ---- Shift register --------------------------------------------------------
uint8_t readShiftByte() {
  digitalWrite(PIN_CLOCK, LOW);
  digitalWrite(PIN_LOAD, LOW);
  delayMicroseconds(5);
  digitalWrite(PIN_LOAD, HIGH);
  delayMicroseconds(5);
  uint8_t value = 0;
  for (int i = 0; i < 8; i++) {
    value <<= 1;
    if (digitalRead(PIN_DATA)) value |= 1;
    digitalWrite(PIN_CLOCK, HIGH);
    delayMicroseconds(5);
    digitalWrite(PIN_CLOCK, LOW);
    delayMicroseconds(5);
  }
  return value;
}

uint16_t decodeButtons(uint8_t raw, bool startLow) {
  uint16_t held = 0;
  for (int code = 0; code < 7; code++) {
    if (!(raw & (1 << (7 - code)))) held |= (1 << code);
  }
  if (startLow) held |= 0x100;
  return held & PHYSICAL_MASK;
}

const int STABLE_SAMPLES = 3;   // ~15 ms at the loop rate below
uint16_t reportedMask = 0, candidateMask = 0;
int candidateCount = 0;

void sendState(uint16_t mask, uint8_t raw) {
  uint8_t payload[3] = {(uint8_t)(mask & 0xff), (uint8_t)(mask >> 8), raw};
  buttonChar->setValue(payload, sizeof(payload));
  if (clientConnected) buttonChar->notify();
}

void setup() {
  pinMode(PIN_LOAD, OUTPUT);
  pinMode(PIN_CLOCK, OUTPUT);
  pinMode(PIN_DATA, INPUT);
  pinMode(PIN_START, INPUT_PULLUP);
  digitalWrite(PIN_CLOCK, LOW);
  digitalWrite(PIN_LOAD, HIGH);

  strip.begin();
  ledsOff();

  SPI.begin(TFT_SCLK, -1, TFT_MOSI, TFT_CS);
  tft.init(240, 320);
  tft.setRotation(3);
  tft.invertDisplay(true);
  tft.fillScreen(ST77XX_BLACK);
  const int BAND = 24;
  for (int y = 0; y < JET_H; y += BAND) {
    int h = min(BAND, JET_H - y);
    tft.drawRGBBitmap(0, y, (uint16_t *)(JET_IMAGE + (size_t)y * JET_W),
                      JET_W, h);
    delay(2);
  }

  NimBLEDevice::init("HTN Badge Buttons");
  // Lowest transmit power: the laptop is inches away, and every milliamp
  // of headroom matters next to a powered panel.
  NimBLEDevice::setPower(-12);
  NimBLEServer *server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  NimBLEService *service = server->createService(SERVICE_UUID);
  buttonChar = service->createCharacteristic(
      CHAR_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  sendState(0, 0xfe);
  service->start();
  NimBLEAdvertising *adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->enableScanResponse(true);
  NimBLEDevice::startAdvertising();
}

void loop() {
  uint8_t raw = readShiftByte();
  uint16_t mask = decodeButtons(raw, digitalRead(PIN_START) == LOW);

  if (mask == candidateMask) {
    if (candidateCount < STABLE_SAMPLES) candidateCount++;
  } else {
    candidateMask = mask;
    candidateCount = 1;
  }

  unsigned long now = millis();
  if (candidateCount >= STABLE_SAMPLES && candidateMask != reportedMask) {
    // Any newly pressed button retriggers sequence X. Releases do not.
    uint16_t newlyPressed = candidateMask & ~reportedMask;
    reportedMask = candidateMask;
    sendState(reportedMask, raw);
    if (newlyPressed) sequenceUntil = now + SEQUENCE_X_MS;
  }

  if (now < sequenceUntil) {
    if (now - lastLedStep >= LED_STEP_MS) {
      ledPhase += ROTATIONS_PER_SEC * (now - lastLedStep) / 1000.0f;
      if (ledPhase >= 1.0f) ledPhase -= 1.0f;
      lastLedStep = now;
      drawRainbow(ledPhase);
      ledsLit = true;
    }
  } else if (ledsLit) {
    ledsOff();          // one clean clear, not a write every loop
    ledsLit = false;
  }

  delay(5);
}
