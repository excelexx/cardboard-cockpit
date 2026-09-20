"""Exercise the actual firmware decoder against Python-encoded frames; no hardware."""
import json, shutil, subprocess, tempfile, unittest, sys, struct, binascii
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'hardware/badge-controller/host'))
import instrument_protocol as protocol

class FirmwareDecoderTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  compiler=shutil.which('c++')
  if compiler is None:raise unittest.SkipTest('C++ compiler unavailable')
  cls.temp=tempfile.TemporaryDirectory(prefix='badge-decoder-')
  source=(ROOT/'hardware/badge-controller/firmware/badge_controller/instrument.cpp').read_text()
  declarations=source[source.index('struct Contact'):source.index('Telemetry latest;')+len('Telemetry latest;')]
  decoder=source[source.index('uint16_t u16'):source.index('class InstrumentCallbacks')]
  harness='''#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <cstdio>
#define portENTER_CRITICAL(x)
#define portEXIT_CRITICAL(x)
bool telemetryFresh=false;uint32_t lastPacketAt=0,goodPackets=0;int stateMux;
uint32_t millis(){return 1234;}
'''+declarations+decoder+'''
int main(int argc,char**argv){if(argc!=2)return 3;uint8_t data[300];size_t n=strlen(argv[1])/2;if(n>300)return 3;for(size_t i=0;i<n;i++){char b[3]={argv[1][i*2],argv[1][i*2+1],0};data[i]=strtoul(b,nullptr,16);}if(!acceptFrame(data,n))return 2;
printf("{\\"mode\\":%u,\\"extended\\":%d,\\"engine\\":%u,\\"fpaYaw\\":%d,\\"fpaPitch\\":%d,\\"worldX\\":%ld,\\"worldZ\\":%ld,\\"gLoad\\":%d,\\"accuracy\\":%u,\\"lastVx\\":%d,\\"lastVy\\":%d,\\"lastAlt\\":%d}",latest.mode,latest.extended,latest.engine,latest.fpaYaw,latest.fpaPitch,(long)latest.worldX,(long)latest.worldZ,latest.gLoad,latest.accuracy,latest.contacts[latest.count?latest.count-1:0].vx,latest.contacts[latest.count?latest.count-1:0].vy,latest.contacts[latest.count?latest.count-1:0].altitude);}
'''
  cpp=Path(cls.temp.name)/'decoder.cpp';cpp.write_text(harness);cls.binary=Path(cls.temp.name)/'decoder'
  subprocess.run([compiler,'-std=c++17',str(cpp),'-o',str(cls.binary)],check=True,capture_output=True)
 @classmethod
 def tearDownClass(cls):cls.temp.cleanup()
 def frame(self):
  d=protocol.disconnected();d.update(version=2,mode=1,aim_yaw=18,aim_pitch=3,engine=98,systems=7,fpa_yaw=1.2,fpa_pitch=-1.3,climb=600,seconds=147,accuracy=76,throttle=100,world_x=1234,world_z=-5678,g_load=1.4,contacts=[dict(x=i*100,y=1100,kind=4,selected=0,vx=-80+i,vy=-200-i,altitude=100+i) for i in range(12)])
  return protocol.encode(d,9)
 def decode(self,frame):return subprocess.run([str(self.binary),frame.hex()],capture_output=True,text=True)
 def test_extended_maximum_frame_matches_firmware_fields(self):
  result=self.decode(self.frame());self.assertEqual(result.returncode,0,result.stderr)
  self.assertEqual(json.loads(result.stdout),dict(mode=1,extended=1,engine=98,fpaYaw=120,fpaPitch=-130,worldX=1234,worldZ=-5678,gLoad=140,accuracy=76,lastVx=-69,lastVy=-211,lastAlt=111))
 def test_legacy_frame_still_accepted(self):
  d=protocol.disconnected();d['mode']=0;r=self.decode(protocol.encode(d,1));self.assertEqual(r.returncode,0);self.assertEqual(json.loads(r.stdout)['extended'],0)
 def test_corruption_truncation_and_unknown_version_rejected(self):
  frame=self.frame();corrupt=bytearray(frame);corrupt[72]^=1
  for bad in (bytes(corrupt),frame[:20],frame[:-1],frame[:2]+b'\3'+frame[3:]):self.assertEqual(self.decode(bad).returncode,2)
 def test_semantic_range_rejected_even_with_valid_crc(self):
  frame=bytearray(self.frame());struct.pack_into('<h',frame,46,18001);struct.pack_into('<H',frame,len(frame)-2,binascii.crc_hqx(frame[:-2],0xffff));self.assertEqual(self.decode(frame).returncode,2)
