import unittest
from vision.tracker import PaperController


class PaperTests(unittest.TestCase):
    def test_center_bank_pitch_and_recenter(self):
        controller = PaperController()
        for _ in range(19):
            self.assertIsNone(controller.map_observation(4, .5, 1))
        neutral = controller.map_observation(4, .5, 1)
        self.assertEqual((neutral.roll, neutral.pitch), (0, 0))
        for _ in range(3): moved = controller.map_observation(24, 15, 1)
        self.assertLess(moved.roll, 0)
        self.assertGreater(moved.pitch, 0)
        for _ in range(3): moved = controller.map_observation(4, -15, 1)
        self.assertLess(moved.pitch, 0)
        controller.recenter()
        self.assertIsNone(controller.neutral)

    def test_unstable_center_is_rejected(self):
        controller = PaperController()
        for i in range(40):
            self.assertIsNone(controller.map_observation((-1)**i*20, .5, 1))

    def test_sensitive_mapping_and_saturation(self):
        controller = PaperController()
        for _ in range(20): controller.map_observation(0, 0, 1)
        for _ in range(3): half = controller.map_observation(10, 14, 1)
        self.assertAlmostEqual(half.roll, -35*9/19)
        self.assertAlmostEqual(half.pitch, 12.5)
        for _ in range(3): full = controller.map_observation(20, 25, 1)
        self.assertAlmostEqual(full.roll, -35)
        self.assertAlmostEqual(full.pitch, 25)
        beyond = controller.map_observation(70, 45, 1)
        self.assertAlmostEqual(beyond.roll, -35)
        self.assertAlmostEqual(beyond.pitch, 25)

    def test_stationary_noise_and_single_frame_outlier_do_not_steer(self):
        controller = PaperController()
        for _ in range(20): controller.map_observation(0, .5, 1)
        for i in range(120):
            value = controller.map_observation((-1)**i*.8, .5+(-1)**i*2, 1)
            self.assertEqual((value.roll,value.pitch),(0,0))
        value = controller.map_observation(30,30,1)
        self.assertEqual((value.roll,value.pitch),(0,0))

    def test_neutral_does_not_drift_during_held_command(self):
        controller = PaperController()
        for _ in range(20): controller.map_observation(0,.5,1)
        for _ in range(120): result = controller.map_observation(15,18,1)
        self.assertEqual(controller.neutral,(0,.5))
        self.assertGreater(result.pitch,10)
        for _ in range(3): result = controller.map_observation(0,1,1)
        self.assertEqual((result.roll,result.pitch),(0,0))

    def test_projected_square_translation_depth_and_signed_tilt(self):
        import cv2
        import numpy as np
        c = PaperController()
        square = np.array([[-.5,-.5,0],[.5,-.5,0],[.5,.5,0],[-.5,.5,0]],float)
        k = np.array([[921.6,0,640],[0,921.6,360],[0,0,1]],float)
        for tilt in [-30,0,30]:
            for bank in [-20,0,20]:
                rx,_ = cv2.Rodrigues(np.array([np.deg2rad(tilt),0,0]))
                rz,_ = cv2.Rodrigues(np.array([0,0,np.deg2rad(bank)]))
                rvec,_ = cv2.Rodrigues(rz@rx)
                for position in [(0,0,4),(.7,-.8,4),(-.6,.8,6)]:
                    points,_ = cv2.projectPoints(square,rvec,np.array(position,float),k,np.zeros(5))
                    actual_bank,actual_tilt = c.perspective_angles(points.reshape(4,2),1280,720)
                    self.assertAlmostEqual(actual_bank,bank,places=3)
                    expected = -np.rad2deg(np.arctan2(np.cos(np.deg2rad(bank))*np.sin(np.deg2rad(tilt)),np.cos(np.deg2rad(tilt))))
                    self.assertAlmostEqual(actual_tilt,expected,places=3)

    def test_upside_down_sticker_has_same_pitch_direction(self):
        import cv2
        import numpy as np
        c=PaperController()
        square=np.array([[-.5,-.5,0],[.5,-.5,0],[.5,.5,0],[-.5,.5,0]],float)
        k=np.array([[921.6,0,640],[0,921.6,360],[0,0,1]],float)
        rx,_=cv2.Rodrigues(np.array([-.35,0,0]))
        pitches=[]
        for orientation in [0,np.pi/2,np.pi]:
            rz,_=cv2.Rodrigues(np.array([0,0,orientation],float))
            rvec,_=cv2.Rodrigues(rx@rz)
            points,_=cv2.projectPoints(square,rvec,np.array([0.,0.,4.]),k,np.zeros(5))
            pitches.append(c.perspective_angles(points.reshape(4,2),1280,720)[1])
        for pitch in pitches: self.assertAlmostEqual(pitch,np.rad2deg(.35),places=3)

    def test_marker_and_mirrored_marker(self):
        import cv2
        import numpy as np
        frame = np.full((720,1280,3),255,dtype=np.uint8)
        marker = cv2.aruco.generateImageMarker(cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50),7,240)
        frame[240:480,500:740] = cv2.cvtColor(marker,cv2.COLOR_GRAY2BGR)
        for source in (frame, cv2.flip(frame,1)):
            controller=PaperController()
            for i in range(21): result,_=controller.detect(source.copy(),i/30,False)
            self.assertIsNotNone(result)
        self.assertEqual(controller.detect(np.full_like(frame,255),1,False),(None,None))
