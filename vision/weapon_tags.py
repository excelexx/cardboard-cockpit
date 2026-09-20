"""Visible-to-fire tags, tolerant of distance, print noise and small overlaps.

This checks image evidence, not physical occlusion: a tiny obstruction or one
matching the printed colour cannot always be distinguished from an intact tag.
"""
import math

GUN_ID = 4
WEAPON_IDS = {"gun": GUN_ID}


class WeaponTags:
    MIN_SIDE = 24
    CLEAR_SECONDS = .08
    CLEAR_FRAMES = 3
    MAX_FRAME_GAP = .15
    CELL = 20
    MIN_CONTRAST = 35
    MAX_PATTERN_MISMATCH = .18

    def __init__(self, cv2, np):
        self.cv2, self.np = cv2, np
        dictionary = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
        parameters = cv2.aruco.DetectorParameters()
        # Allow the dictionary's normal single-bit correction and some border
        # damage: a fingertip barely overlapping the print is not a release.
        parameters.errorCorrectionRate = 1.0
        parameters.maxErroneousBitsInBorderRate = .35
        parameters.cornerRefinementMethod = cv2.aruco.CORNER_REFINE_SUBPIX
        self.detector = cv2.aruco.ArucoDetector(dictionary, parameters)
        self.templates = {}
        for marker_id in WEAPON_IDS.values():
            cells = np.full((8, 8), 255, np.uint8)
            cells[1:7, 1:7] = cv2.aruco.generateImageMarker(dictionary, marker_id, 6)
            expected = np.repeat(np.repeat(cells, self.CELL, axis=0), self.CELL, axis=1)
            # Ignore colour transitions for resampling/corner noise. Score the
            # whole black square; individual scuffs and covered margins do not
            # veto an otherwise clearly recognisable marker.
            kernel = np.ones((5, 5), np.uint8)
            white = cv2.erode((expected == 255).astype(np.uint8), kernel).astype(bool)
            black = cv2.erode((expected == 0).astype(np.uint8), kernel).astype(bool)
            checked = np.zeros_like(white)
            checked[self.CELL:7*self.CELL, self.CELL:7*self.CELL] = True
            self.templates[marker_id] = (white & checked, black & checked)
        self.reset()

    def reset(self):
        self.since = {name: None for name in WEAPON_IDS}
        self.frames = {name: 0 for name in WEAPON_IDS}
        self.previous_time = None
        self.legacy_observations = {}
        self.messages = {name: "not seen" for name in WEAPON_IDS}
        return {name: False for name in WEAPON_IDS}

    def _visibility_issue(self, gray, corners, marker_id):
        cv2, np = self.cv2, self.np
        points = np.asarray(corners, dtype=np.float32).reshape(4, 2)
        if not np.isfinite(points).all() or not cv2.isContourConvex(points):
            return "unclear shape"
        # Corners are pixel centres; a nominal 24-pixel square spans ~23 px.
        if 1 + min(np.linalg.norm(points[(i + 1) % 4] - points[i]) for i in range(4)) < self.MIN_SIDE:
            return "tag too small"
        # Only score the printed black square. Paper margins are not controls.
        c = self.CELL
        target = np.array([[c, c], [7*c-1, c], [7*c-1, 7*c-1], [c, 7*c-1]], np.float32)
        transform = cv2.getPerspectiveTransform(points, target)
        height, width = gray.shape
        if (points < 0).any() or (points[:, 0] >= width).any() or (points[:, 1] >= height).any():
            return "edge out of frame"
        patch = cv2.warpPerspective(gray, transform, (8*c, 8*c))
        white, black = self.templates[marker_id]
        dark = float(np.median(patch[black]))
        light = float(np.median(patch[white]))
        contrast = light - dark
        if contrast < self.MIN_CONTRAST:
            return "needs clearer light"
        wrong = (black & (patch > dark + contrast*.30)) | (white & (patch < light - contrast*.30))
        checked = white | black
        # Require substantial damage across the marker before turning it off,
        # rather than rejecting a few pixels in any single cell.
        if np.count_nonzero(wrong) > self.MAX_PATTERN_MISMATCH * np.count_nonzero(checked):
            return "covered / unclear"
        return ""

    def detect(self, frame, now):
        if frame is None or not math.isfinite(now):
            result = self.reset()
            self.messages = {name: "no camera" for name in WEAPON_IDS}
            return result
        if self.previous_time is not None and not 0 < now-self.previous_time <= self.MAX_FRAME_GAP:
            self.reset()
        self.previous_time = now
        gray = self.cv2.cvtColor(frame, self.cv2.COLOR_BGR2GRAY)
        candidates = {marker_id: [] for marker_id in WEAPON_IDS.values()}
        # Accommodate a mirrored camera feed just like the paper yoke. Both
        # orientations participate in duplicate rejection; never choose one
        # visible copy while another copy of that ID is also detected.
        legacy_candidates = {}
        for view_index, view in enumerate((gray, self.cv2.flip(gray, 1))):
            corners, ids, _ = self.detector.detectMarkers(view)
            if ids is not None:
                for points, marker_id in zip(corners, ids.flatten()):
                    if view_index==0 and int(marker_id) in (31,32,41,42):legacy_candidates.setdefault(int(marker_id),[]).append(points.reshape(4,2))
                    if int(marker_id) in candidates:
                        candidates[int(marker_id)].append((view, points))
        self.legacy_observations = {}
        legacy_ids={31:('primary',True),32:('primary',False),41:('salvo',True),42:('salvo',False)}
        seen=legacy_candidates
        scale=min(frame.shape[1]/1280,frame.shape[0]/720)
        for marker_id,(role,value) in legacy_ids.items():
            matches=seen.get(marker_id,[]);opposite={31:32,32:31,41:42,42:41}[marker_id]
            if len(matches)==1 and opposite not in seen:
                points=matches[0];side=min(float(self.np.linalg.norm(points[(i+1)%4]-points[i])) for i in range(4))
                if side>=24*scale:self.legacy_observations[role]=(value,max(.3,min(1,side/(75*scale))))
        result = {}
        for name, marker_id in WEAPON_IDS.items():
            matches = candidates[marker_id]
            issue = "not seen" if not matches else "duplicate ID" if len(matches) > 1 else self._visibility_issue(matches[0][0], matches[0][1], marker_id)
            clear = not issue
            if not clear:
                self.frames[name] = 0
                self.since[name] = None
            else:
                if self.since[name] is None:
                    self.since[name] = now
                self.frames[name] += 1
            result[name] = bool(clear and self.frames[name] >= self.CLEAR_FRAMES and now-self.since[name] >= self.CLEAR_SECONDS)
            self.messages[name] = issue or ("clear" if result[name] else "checking")
        return result
