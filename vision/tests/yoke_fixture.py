"""Render a yoke marker with a known physical orientation; no camera access."""
import cv2
import numpy as np


def yoke_frame(yaw=0, pitch=0, bank=0, mounting=0):
    square = np.array([[-.5,-.5,0],[.5,-.5,0],[.5,.5,0],[-.5,.5,0]],float)
    k = np.array([[921.6,0,640],[0,921.6,360],[0,0,1]],float)
    ry, _ = cv2.Rodrigues(np.array([0,np.deg2rad(yaw),0]))
    rx, _ = cv2.Rodrigues(np.array([-np.deg2rad(pitch),0,0]))
    rz, _ = cv2.Rodrigues(np.array([0,0,np.deg2rad(bank+mounting)]))
    rvec, _ = cv2.Rodrigues(ry@rx@rz)
    points, _ = cv2.projectPoints(square,rvec,np.array([0.,0.,4.]),k,np.zeros(5))
    source = np.array([[0,0],[399,0],[399,399],[0,399]],np.float32)
    homography = cv2.getPerspectiveTransform(source,points.reshape(4,2).astype(np.float32))
    marker = cv2.aruco.generateImageMarker(cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50),7,400)
    frame = cv2.warpPerspective(marker,homography,(1280,720),borderValue=255)
    return cv2.cvtColor(frame,cv2.COLOR_GRAY2BGR)
