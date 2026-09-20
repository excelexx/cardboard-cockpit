import importlib.util,json,struct,binascii,socket,select,unittest,sys
from pathlib import Path
HOST=Path(__file__).resolve().parents[2]/'hardware/badge-controller/host'
sys.path.insert(0,str(HOST))
import instrument_protocol as p
from badge_bridge import Relay
class InstrumentTests(unittest.TestCase):
 def test_binary_and_minimum_mtu(self):
  d=p.disconnected();d.update(mode=1,roll=-45,pitch=12.5,heading=298,speed=360,altitude=1400,score=1234,kills=3,pilot=2,contacts=[dict(x=100,y=-200,kind=2,selected=1)])
  b=p.encode(d,65537);self.assertEqual(p.HEADER.size,44);self.assertEqual(len(b),52)
  self.assertEqual(struct.unpack_from('<Hhh',b,6),(1,-4500,1250))
  self.assertEqual(struct.unpack_from('<hhBB',b,44),(100,-200,2,1))
  self.assertEqual(struct.unpack_from('<H',b,len(b)-2)[0],binascii.crc_hqx(b[:-2],0xffff))
  parts=p.fragments(b,1,20);self.assertTrue(all(len(x)<=20 for x in parts));self.assertEqual(b''.join(x[4:] for x in parts),b)
  self.assertEqual([x[2] for x in parts],list(range(0,len(b),16)))
 def test_presentation_detail_crc_and_legacy_default(self):
  d=p.disconnected();self.assertEqual(p.encode(d,1)[43],0)
  for value in (0,15,16,47,79,111,100,255):
   d['detail']=value;b=p.encode(d,1);self.assertEqual(b[43],value)
   self.assertEqual(int.from_bytes(b[-2:],'little'),binascii.crc_hqx(b[:-2],0xffff))
  for value in (-1,256,1.5,True):
   d['detail']=value
   with self.assertRaises(ValueError):p.encode(d,1)
 def test_extended_sensor_frame_at_maximum_contacts(self):
  d=p.disconnected();d.update(version=2,aim_yaw=18,aim_pitch=3,engine=98,systems=7,fpa_yaw=1.2,fpa_pitch=-1.3,climb=600,seconds=147,accuracy=76,throttle=100,world_x=1234,world_z=-5678,g_load=1.4,contacts=[dict(x=600,y=1100,kind=4,selected=0,vx=-80,vy=-200,altitude=100) for _ in range(12)])
  b=p.encode(d,9);self.assertEqual(len(b),216);self.assertEqual(b[2],2)
  self.assertEqual(p.EXTENDED.unpack_from(b,44),(98,7,120,-130,600,147,76,100,1234,-5678,140,1800,300))
  self.assertEqual(p.CONTACT_V2.unpack_from(b,70),(600,1100,4,0,-80,-200,100))
  for mtu in (20,180,182):
   parts=p.fragments(b,9,mtu);self.assertTrue(all(len(part)<=mtu for part in parts));self.assertEqual(b''.join(part[4:] for part in parts),b)
  for key,value in [('systems',8),('fpa_yaw',181),('accuracy',254),('world_x',10000001),('g_load',float('inf'))]:
   bad=dict(d);bad[key]=value
   with self.subTest(key=key),self.assertRaises(ValueError):p.encode(bad,1)
 def test_invalid_inputs(self):
  for key,value in [('roll',float('nan')),('pitch',91),('mode',1.5),('score',-1),('name','a'*13),('pilot',0),('contacts',[dict(x=0,y=0,kind=9,selected=0)])]:
   d=p.disconnected();d[key]=value
   with self.subTest(key=key),self.assertRaises(ValueError):p.encode(d,0)
 def test_udp_keeps_last_valid_snapshot(self):
  r=Relay(0,18799)
  with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as s:
   try:
    d=p.disconnected();d['mode']=1
    s.sendto(json.dumps(d).encode(),r.socket.getsockname());select.select([r.socket],[],[],.2);r.game_phase()
    self.assertEqual(r.telemetry['mode'],1);at=r.telemetry_at
    s.sendto(b'{"kind":"instrument","version":1}',r.socket.getsockname());select.select([r.socket],[],[],.2);r.game_phase()
    self.assertEqual(r.telemetry_at,at)
   finally:r.socket.close()
