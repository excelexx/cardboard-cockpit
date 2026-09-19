#!/usr/bin/env python3
"""Explicit hardware acceptance test. One BLE owner, synthetic game telemetry.
Does not flash or touch USB. Shows readiness, horizon/radar, warning and scorecard.
"""
import asyncio,argparse,json,math,time
from bleak import BleakClient,BleakScanner
from badge_bridge import SERVICE_UUID,BUTTON_UUID,PHASE_UUID,INSTRUMENT_UUID,INFO_UUID
from instrument_protocol import encode,fragments,disconnected
async def main(seconds):
 device=await BleakScanner.find_device_by_filter(lambda d,a:SERVICE_UUID in a.service_uuids,timeout=10)
 if device is None:raise RuntimeError('Badge not advertising')
 async with BleakClient(device) as client:
  c=client.services.get_characteristic(INSTRUMENT_UUID)
  if c is None:raise RuntimeError('Instrument characteristic missing')
  print('CONNECTED instrument; write payload',c.max_write_without_response_size,flush=True)
  await client.start_notify(BUTTON_UUID,lambda _,data:print('BUTTON MASK',int.from_bytes(data[:2],'little'),flush=True))
  seq=0;began=time.monotonic();bytes_sent=0;last_phase=-1;last_phase_at=0.;last_health=0.;last_frames=0
  d=disconnected();d.update(mode=0,name='PILOT',pilot=1)
  while time.monotonic()-began<seconds:
   elapsed=time.monotonic()-began
   if elapsed<4:d.update(mode=0,flags=0)
   elif elapsed<seconds-7:
    d.update(mode=1,roll=math.sin(elapsed*1.2)*55,pitch=math.sin(elapsed*.7)*18,heading=(elapsed*8)%360,speed=345,altitude=1250,flags=33 if int(elapsed)%8<4 else 35,range=740,contacts=[dict(x=600,y=1100,kind=2,selected=1),dict(x=-800,y=1900,kind=1,selected=0),dict(x=200,y=500,kind=3,selected=0)])
   else:d.update(mode=2,flags=64,score=4200,kills=18,landing=1,roll=0,pitch=0,contacts=[])
   phase=0 if d['mode'] in (0,2) else 1 if elapsed<8 else 3 if elapsed>seconds-12 else 2
   if phase!=last_phase or elapsed-last_phase_at>=1:
    await client.write_gatt_char(PHASE_UUID,bytes([phase]),response=True);last_phase=phase;last_phase_at=elapsed
   if elapsed-last_health>=5:
    health=json.loads((await client.read_gatt_char(INFO_UUID)).decode())
    if health['frames']<=last_frames or health['bad']!=0:raise RuntimeError('Reset or invalid packet during combined LED/display/BLE load')
    print('HEALTH',json.dumps(health),flush=True);last_frames=health['frames'];last_health=elapsed
   seq+=1
   for part in fragments(encode(d,seq),seq,c.max_write_without_response_size):
    await client.write_gatt_char(INSTRUMENT_UUID,part,response=False);bytes_sent+=len(part)
   await asyncio.sleep(.05)
  info=json.loads((await client.read_gatt_char(INFO_UUID)).decode())
  print('MEASURED',json.dumps(info),flush=True)
  print('SENT',seq,'frames;',bytes_sent,'BLE payload bytes;',round(bytes_sent*8/(time.monotonic()-began)),'bits/s',flush=True)
  if info['packets']<seq*.9 or info['bad']!=0 or info['fps10']<100:raise RuntimeError('Telemetry/render acceptance failed')
  for phase in range(4):
   await client.write_gatt_char(PHASE_UUID,bytes([phase]),response=True)
   result=await client.read_gatt_char(PHASE_UUID)
   if result!=bytes([phase]):raise RuntimeError('Phase readback mismatch')
  print('PASS: telemetry, render counters and four legacy phase readbacks',flush=True)
 # A new connection must recover both directions without a USB reset.
 device=await BleakScanner.find_device_by_filter(lambda d,a:SERVICE_UUID in a.service_uuids,timeout=10)
 if device is None:raise RuntimeError('Badge did not advertise after disconnect')
 async with BleakClient(device) as client:
  resumed=json.loads((await client.read_gatt_char(INFO_UUID)).decode())
  if resumed['frames']<info['frames'] or resumed['packets']<info['packets']:raise RuntimeError('Unexpected reboot during reconnect')
  buttons=await client.read_gatt_char(BUTTON_UUID)
  if len(buttons)!=3:raise RuntimeError('Buttons unavailable after reconnect')
  ready=disconnected();ready.update(mode=0,name='PILOT',pilot=1)
  c=client.services.get_characteristic(INSTRUMENT_UUID)
  for part in fragments(encode(ready,seq+1),seq+1,c.max_write_without_response_size):await client.write_gatt_char(INSTRUMENT_UUID,part,response=True)
  confirmed=json.loads((await client.read_gatt_char(INFO_UUID)).decode())
  if confirmed['mode']!=0 or confirmed['packets']<=info['packets']:raise RuntimeError('Telemetry did not recover after reconnect')
  print('PASS: Bluetooth disconnect/reconnect, buttons and fresh telemetry without USB reset',flush=True)
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--seconds',type=int,default=25);args=parser.parse_args();asyncio.run(main(args.seconds))
