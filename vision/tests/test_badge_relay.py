"""Protocol-only tests; never touches BLE or flashes hardware."""
import importlib.util,json,socket,time,unittest,select
from pathlib import Path
path=Path(__file__).resolve().parents[2]/'hardware/badge-controller/host/badge_bridge.py'
spec=importlib.util.spec_from_file_location('badge_relay',path)
relay_module=importlib.util.module_from_spec(spec);spec.loader.exec_module(relay_module)

class BadgeRelayTests(unittest.TestCase):
    def test_packet_mask(self):
        self.assertEqual(relay_module.decode(bytes([0x7f,1,0])),0x17f)
        for packet in (b'',b'\0\0',b'\0\0\0\0',bytes([128,0,0]),bytes([0,2,0])):
            with self.assertRaises(ValueError):relay_module.decode(packet)
    def test_transport_and_phase_timeout(self):
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sink:
            sink.bind(('127.0.0.1',0));sink.settimeout(.2)
            r=relay_module.Relay(0,sink.getsockname()[1])
            try:
                r.connected=True;r.mask=3;r.send()
                p=json.loads(sink.recv(512));self.assertEqual(p['mask'],3);self.assertTrue(p['connected'])
                r.connected=False;r.send();p2=json.loads(sink.recv(512))
                self.assertEqual(p2['mask'],0);self.assertGreater(p2['sequence'],p['sequence'])
                sink.sendto(b'sky',r.socket.getsockname());select.select([r.socket],[],[],.2);self.assertEqual(r.game_phase(),2)
                r.phase_at=time.monotonic()-3.1;self.assertEqual(r.game_phase(),0)
                sink.sendto(b'invalid',r.socket.getsockname());select.select([r.socket],[],[],.2);self.assertEqual(r.game_phase(),0)
                with self.assertRaises(OSError):relay_module.Relay(r.socket.getsockname()[1])
            finally:r.socket.close()
