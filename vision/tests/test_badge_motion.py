"""Native checks for the hardware-independent cinematic timing/color functions."""
from pathlib import Path
import shutil,subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[2]
class BadgeMotionTests(unittest.TestCase):
 def test_motion_boundaries_and_undefined_behavior(self):
  compiler=shutil.which('c++')
  if not compiler:self.skipTest('C++ compiler unavailable')
  with tempfile.TemporaryDirectory(prefix='badge-motion-') as folder:
   binary=Path(folder)/'test_motion'
   subprocess.run([compiler,'-std=c++11','-fsanitize=undefined','-fno-sanitize-recover=all','-I',str(ROOT/'hardware/badge-controller/firmware/badge_controller'),str(ROOT/'hardware/badge-controller/firmware/tests/test_motion.cpp'),'-o',str(binary)],check=True,capture_output=True)
   result=subprocess.run([str(binary)],check=True,capture_output=True,text=True)
   self.assertIn('all checks passed',result.stdout)
