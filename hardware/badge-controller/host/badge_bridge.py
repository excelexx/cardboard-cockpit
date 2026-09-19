#!/usr/bin/env python3
"""BLE badge buttons -> local game UDP; local game phase -> badge LEDs.
Uses the branch's existing GATT protocol. No OS keyboard injection or firmware flashing.
"""
import argparse,asyncio,json,socket,time,uuid,os,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from instrument_protocol import validate,encode,fragments,disconnected
SERVICE_UUID='5f1d0000-9c2b-4e7a-a3d6-0b8e1c4f2a71'
BUTTON_UUID='5f1d0001-9c2b-4e7a-a3d6-0b8e1c4f2a71'
PHASE_UUID='5f1d0002-9c2b-4e7a-a3d6-0b8e1c4f2a71'
INSTRUMENT_UUID='5f1d0003-9c2b-4e7a-a3d6-0b8e1c4f2a71'
INFO_UUID='5f1d0004-9c2b-4e7a-a3d6-0b8e1c4f2a71'
DEVICE_NAME='HTN Badge Buttons'
PHASES={'idle':0,'takeoff':1,'sky':2,'landing':3}
NAMES={0:'A',1:'B',2:'HOME',3:'DOWN',4:'LEFT',5:'RIGHT',6:'UP',8:'START'}
PHYSICAL_MASK=0x17f

def decode(data):
 if len(data)!=3:raise ValueError('Expected the existing three-byte badge packet')
 mask=int.from_bytes(data[:2],'little')
 if mask&~PHYSICAL_MASK:raise ValueError('Unknown/unused button bit')
 return mask

class Relay:
 def __init__(self,phase_port=8770,input_port=8771,parent_pid=0):
  self.parent_pid=parent_pid
  self.socket=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
  try:self.socket.bind(('127.0.0.1',phase_port))
  except OSError:self.socket.close();raise
  self.socket.setblocking(False)
  self.destination=('127.0.0.1',input_port);self.session=uuid.uuid4().hex
  self.instrument_supported=False;self.telemetry=None;self.telemetry_at=0.;self.telemetry_sequence=0
  self.sequence=0;self.phase=0;self.phase_at=0.;self.mask=0;self.connected=False;self.phase_supported=False
 def game_phase(self):
  for _ in range(32):
   try:data,_=self.socket.recvfrom(8192)
   except BlockingIOError:break
   if len(data)>4096:continue
   text=data.decode('utf-8','ignore').strip()
   if text.startswith('{'):
    try:
     incoming=json.loads(text)
     if self.parent_pid and incoming.get('sender_pid')!=self.parent_pid:continue
     self.telemetry=validate(incoming);self.telemetry_at=time.monotonic()
     if incoming.get('phase') in PHASES:self.phase=PHASES[incoming['phase']];self.phase_at=time.monotonic()
    except (ValueError,TypeError):pass
    continue
   text=text.lower()
   if not self.parent_pid and text in PHASES:self.phase=PHASES[text];self.phase_at=time.monotonic()
  return self.phase if time.monotonic()-self.phase_at<3 else 0
 def send(self):
  self.sequence+=1
  packet={'version':1,'session':self.session,'sequence':self.sequence,'connected':self.connected,'mask':self.mask if self.connected else 0,'phase_supported':self.phase_supported,'instrument_supported':self.instrument_supported}
  self.socket.sendto(json.dumps(packet,separators=(',',':')).encode(),self.destination)
 def buttons(self,data):
  try:mask=decode(data)
  except ValueError:return
  if mask!=self.mask:print('BUTTONS '+(' + '.join(name for bit,name in NAMES.items() if mask&(1<<bit)) or 'released'),flush=True)
  self.mask=mask

async def run(relay,once=False):
 from bleak import BleakScanner,BleakClient
 while True:
  relay.connected=False;relay.mask=0;relay.send()
  print('Scanning for HTN badge…',flush=True)
  try:
   device=await BleakScanner.find_device_by_filter(lambda d,a:SERVICE_UUID in [u.lower() for u in a.service_uuids] or (d.name or a.local_name or '')==DEVICE_NAME,timeout=8)
   if device is None:
    if once:return
    await asyncio.sleep(1);continue
   async with BleakClient(device) as client:
    relay.phase_supported=client.services.get_characteristic(PHASE_UUID) is not None
    instrument=client.services.get_characteristic(INSTRUMENT_UUID);relay.instrument_supported=instrument is not None
    relay.connected=True;relay.mask=0;relay.session=uuid.uuid4().hex;relay.sequence=0
    print('CONNECTED — secondary flight/session panel; cardboard cockpit retains steering, throttle and weapons',flush=True)
    print('Phase feedback '+('available' if relay.phase_supported else 'not supported by installed firmware'),flush=True)
    relay.buttons(await client.read_gatt_char(BUTTON_UUID));relay.send()
    await client.start_notify(BUTTON_UUID,lambda _,data:relay.buttons(data))
    last_poll=0.;last_phase=-1;phase_at=0.;telemetry_at=0.;info_at=0.
    if instrument:print("INSTRUMENT available; BLE write payload="+str(instrument.max_write_without_response_size),flush=True)
    while client.is_connected:
     now=time.monotonic()
     # Polling also checks liveness when the notification stream is quiet.
     if now-last_poll>.3:
      relay.buttons(await asyncio.wait_for(client.read_gatt_char(BUTTON_UUID),timeout=.8));last_poll=now
     phase=relay.game_phase()
     if relay.phase_supported and (phase!=last_phase or now-phase_at>1):
      await asyncio.wait_for(client.write_gatt_char(PHASE_UUID,bytes([phase]),response=False),timeout=.8)
      if phase!=last_phase:
       confirmed=await asyncio.wait_for(client.read_gatt_char(PHASE_UUID),timeout=.8)
       print('PHASE '+next(k for k,v in PHASES.items() if v==phase)+' readback='+str(list(confirmed)),flush=True)
      last_phase=phase;phase_at=now
     if instrument and now-telemetry_at>=.05:
      snapshot=relay.telemetry if relay.telemetry is not None and now-relay.telemetry_at<1 else disconnected()
      relay.telemetry_sequence=(relay.telemetry_sequence+1)&65535
      packet=encode(snapshot,relay.telemetry_sequence)
      for fragment in fragments(packet,relay.telemetry_sequence,max(20,instrument.max_write_without_response_size)):
       await asyncio.wait_for(client.write_gatt_char(INSTRUMENT_UUID,fragment,response=False),timeout=.8)
      telemetry_at=now
     if instrument and now-info_at>10:
      info=await asyncio.wait_for(client.read_gatt_char(INFO_UUID),timeout=.8)
      print('INSTRUMENT '+info.decode('ascii','replace'),flush=True);info_at=now
     relay.send();await asyncio.sleep(.01 if instrument else .04)
  except Exception as exc:print('Badge connection unavailable: '+type(exc).__name__+' — '+str(exc),flush=True)
  finally:relay.connected=False;relay.mask=0;relay.send()
  if once:return
  await asyncio.sleep(1)

async def owned_run(relay,once,parent):
 task=asyncio.create_task(run(relay,once))
 try:
  while not task.done():
   if parent:
    try:os.kill(parent,0)
    except ProcessLookupError:return
   await asyncio.sleep(.5)
  await task
 finally:
  task.cancel()
  try:await task
  except asyncio.CancelledError:pass

def main():
 if getattr(sys,'frozen',False):
  try:
   folder=Path.home()/'Library'/'Logs'/'Cardboard Cockpit';folder.mkdir(parents=True,exist_ok=True)
   sys.stdout=open(folder/'badge.log','w',buffering=1);sys.stderr=sys.stdout
  except OSError:pass
 parser=argparse.ArgumentParser();parser.add_argument('--port',type=int,default=8770);parser.add_argument('--input-port',type=int,default=8771);parser.add_argument('--once',action='store_true');parser.add_argument('--simulate',action='store_true');parser.add_argument('--parent-pid',type=int,default=0);args=parser.parse_args()
 try:relay=Relay(args.port,args.input_port,args.parent_pid)
 except OSError as exc:
  print('Badge relay already owned or port unavailable: '+str(exc),flush=True);return
 try:
  if args.simulate:
   relay.connected=True
   while True:relay.game_phase();relay.send();time.sleep(.04)
  else:asyncio.run(owned_run(relay,args.once,args.parent_pid))
 except KeyboardInterrupt:pass
 finally:
  relay.connected=False;relay.mask=0;relay.send();relay.socket.close()
if __name__=='__main__':main()
