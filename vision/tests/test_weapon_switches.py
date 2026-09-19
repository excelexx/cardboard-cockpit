import unittest
from vision.weapon_switches import WeaponSwitches

class WeaponSwitchTests(unittest.TestCase):
    def test_latched_on_off_and_bounce(self):
        s=WeaponSwitches()
        self.assertFalse(s.step({'primary':(True,1)},0)['primary'])
        self.assertFalse(s.step({'primary':(False,1)},.04)['primary'])
        s.step({'primary':(True,1)},.05)
        self.assertTrue(s.step({'primary':(True,1)},.15)['primary'])
        self.assertTrue(s.step({},.4)['primary'])
        s.step({'primary':(False,1)},.5)
        self.assertFalse(s.step({'primary':(False,1)},.60)['primary'])
    def test_independent_simultaneous_and_loss(self):
        s=WeaponSwitches(); both={'primary':(True,.9),'salvo':(True,.8)}
        s.step(both,1); result=s.step(both,1.1)
        self.assertTrue(result['primary'] and result['salvo'])
        s.step({'primary':(True,.9)},1.8)
        result=s.step({'primary':(True,.9)},2)
        self.assertTrue(result['primary']);self.assertFalse(result['salvo'])
        result=s.step({},3)
        self.assertFalse(result['primary'] or result['salvo'])
        self.assertEqual(result['primary_confidence'],0)
    def test_no_controls_without_markers(self):
        s=WeaponSwitches();s.step({},50);self.assertFalse(s.configured)
