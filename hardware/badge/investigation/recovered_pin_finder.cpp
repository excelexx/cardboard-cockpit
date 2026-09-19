// Analytical reconstruction, not the installed sketch's original source.
// Do not flash: it scans pins shared with the LCD/LEDs and uses UART0 on the
// same GPIO20/21 pair it tries to discover. USB CDC avoids that conflict.
// Derived from current IROM 0x42000020..0x42000274 and its DROM pin list.
#include <Arduino.h>
static const int candidates[]={0,1,2,3,4,5,6,7,8,10,20,21};
uint8_t reconstructedRead165(int load,int clock,int data) {
  pinMode(load,OUTPUT);pinMode(clock,OUTPUT);pinMode(data,INPUT);
  digitalWrite(clock,LOW);digitalWrite(load,LOW);delayMicroseconds(5);
  digitalWrite(load,HIGH);delayMicroseconds(5);
  uint8_t value=0;
  for(int n=0;n<8;n++) {
    value=(value<<1)|(digitalRead(data)?1:0);
    digitalWrite(clock,HIGH);delayMicroseconds(5);
    digitalWrite(clock,LOW);delayMicroseconds(5);
  }
  return value;
}
bool reconstructedSingleLow(uint8_t value) {
  uint8_t low=~value;
  return low && !(low & (low-1));
}
void reconstructedSweep() {
  for(int load:candidates) for(int clock:candidates) for(int data:candidates) {
    if(load==clock || load==data || clock==data) continue;
    uint8_t first=reconstructedRead165(load,clock,data);
    uint8_t second=reconstructedRead165(load,clock,data);
    if(first==second && reconstructedSingleLow(first)) {
      // Original prints a candidate at IROM 0x420001b2.
      // It fails when a real button AND the unused shift input are both low.
    }
  }
  delay(5000);
}
