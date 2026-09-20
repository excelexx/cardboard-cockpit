"""Fixed, mirrored camera previews. Marker motion never changes framing."""


class PreviewFramer:
    GROUPS = ("throttle", "yoke", "weapons")

    def __init__(self, cv2, np):
        self.cv2, self.np = cv2, np

    def render(self, frame, focus, now, label):
        if frame is None:
            return None
        # Mirror display pixels only; detection and control signs use the raw frame.
        view = self.cv2.flip(frame, 1)
        scale = min(960/view.shape[1], 540/view.shape[0], 1)
        size = (max(1, round(view.shape[1]*scale)), max(1, round(view.shape[0]*scale)))
        view = self.cv2.resize(view, size, interpolation=self.cv2.INTER_AREA)
        self.cv2.rectangle(view, (0, size[1]-28), size, (20, 28, 32), -1)
        label_width = self.cv2.getTextSize(label, self.cv2.FONT_HERSHEY_SIMPLEX, .48, 1)[0][0]
        self.cv2.putText(view, label, (max(10, (size[0]-label_width)//2), size[1]-9), self.cv2.FONT_HERSHEY_SIMPLEX,
                         .48, (170, 240, 200), 1, self.cv2.LINE_AA)
        return view

    def combined(self, primary, throttle, primary_label, throttle_label):
        if primary is None and throttle is None:
            return None
        view = self.np.full((540, 960, 3), (20, 28, 32), dtype=self.np.uint8)
        for column, (frame, label) in enumerate(((primary, primary_label), (throttle, throttle_label))):
            if frame is not None:
                scale = min(480/frame.shape[1], 500/frame.shape[0])
                width, height = max(1, round(frame.shape[1]*scale)), max(1, round(frame.shape[0]*scale))
                small = self.cv2.resize(self.cv2.flip(frame, 1), (width, height), interpolation=self.cv2.INTER_AREA)
                x, y = column*480+(480-width)//2, (500-height)//2
                view[y:y+height, x:x+width] = small
            else:
                self.cv2.putText(view, "Camera unavailable", (column*480+70, 260),
                                 self.cv2.FONT_HERSHEY_SIMPLEX, .7, (160, 160, 160), 1, self.cv2.LINE_AA)
            self.cv2.putText(view, label, (column*480+10, 523), self.cv2.FONT_HERSHEY_SIMPLEX,
                             .48, (170, 240, 200), 1, self.cv2.LINE_AA)
        return view
