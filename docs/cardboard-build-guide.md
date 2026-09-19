# Build a Cardboard Cockpit

**Ordinary cardboard. Two paper markers. One webcam.** Plan roughly 45–60 minutes for a first build. Print `vision/printable-cockpit.html` at actual size for the marker sheet and keyboard labels. Dimensions below are starting sizes for an adult desk; cut rounded edges and adjust the hand spacing before final taping.

## Cut list

| Part | Pieces and dimensions |
| --- | --- |
| Yoke | Two identical 32 × 20 cm blanks; remove a centered 16 × 12 cm opening from the top edge to form a U. Remaining lower bridge is 8 cm tall; handles are 8 cm wide. |
| Marker plate | One 11 × 11 cm square. Mount centered above the yoke's lower bridge, facing the camera; glue/tape only around its edges. |
| Stiffeners | Two 28 × 3 cm strips across the lower bridge; four 16 × 3 cm strips along the handle edges. Fold strips lengthwise to create ribs. |
| Optional resting cradle | Two 16 × 12 cm sides with 3 cm-deep semicircular notches in their top edges; one 22 × 16 cm base. Tape upright 12 cm apart. |
| Throttle box | One shoebox approximately 30 × 16 × 12 cm, with lid. |
| Slider | One 10 × 8 cm cardboard carriage, two 26 × 2 cm folded guide rails, and one 8 × 8 cm marker plate. |
| Throttle slot | Cut a centered 20 cm-long × 1.2 cm-wide slot lengthwise in the lid, beginning 5 cm from each short end. |

## Assemble

**Yoke.** Laminate the two U shapes with their cardboard flutes crossing. Tape on the folded stiffeners, then wrap the handles with tape. Keep the center marker plate flat and unobstructed by fingers. Place the **70 mm ID 7 black square** on the camera-facing plate; retain its surrounding white margin. If the webcam cannot be mounted well above the yoke, wedge the plate so it leans back 10–15° (top edge away from the camera): a flat marker seen exactly head-on is ambiguous in pitch, and the placement check below tells you whether this is needed. The yoke is freely held: rotate left/right to bank and tilt its top edge forward/backward to pitch. Rest wrists on the desk edge or an empty folded towel to reduce wobble. The optional cradle is a parking support, not a hinge: lift the yoke clear to fly, so roll and pitch remain free.

**Throttle.** Tape the guide rails under the lid, parallel to the slot, 8.5 cm apart. Put the carriage between them. Tape a capped marker pen upright to the carriage and pass it through the slot. Add a cardboard crosspiece beneath the lid so the grip cannot pull through. Tape the **8 × 8 cm marker plate** to a short upright folded-cardboard bracket on the carriage, just in front of the grip; it must move with the slider and face the camera. Attach the **50 mm ID 23 black square**, retaining its white margin. Add folded stops at each end. Adjust rail friction with paper shims until the slider holds position without sticking. Label the pilot end **IDLE**, midpoint **CRUISE**, far end **FULL**. Tape the box to the desk so it cannot shift during calibration.

## Position and fly

```text
                        AUDIENCE
                 [ large flight display ]
                     [ webcam ]
                  ↙ 70–100 cm ↘
              ID 7             ID 23
              YOKE         THROTTLE BOX
          [ auxiliary keyboard labels ]
                       PILOT
```

Mount the webcam 25–40 cm above the desktop, aimed down slightly, with both markers visible. Keep it fixed. Raise or offset it until IDLE-to-FULL visibly moves the throttle marker in the preview; travel directly toward a level lens is hard to measure. The yoke should stay within about ±35° roll and ±25° pitch, with no hands across the markers. Use diffuse room light and matte paper. Keep spare printed markers out of view.

First run `.venv/bin/python vision/tracker.py --camera 0 --check`, sweep both controls through their full travel, press **Q**, and fix anything marked FAIL or WARN by moving the camera or props.

Then run `.venv/bin/python vision/tracker.py --camera 0 --calibrate`. Hold each displayed pose for one second, then press **Space**: neutral → left → right → forward → backward → idle → full. Re-center the yoke and return to idle, select vision input in the game, then start. See [setup and recovery](vision-setup.md) for full instructions.

**Auxiliary panel:** W/S throttle · arrows pitch/roll · A/D steering · G gear · V view · Space brakes · R reset · M mute · Enter start · Escape pause. Label **N: NEW PILOT** and **C: CALIBRATE** for the tracker preview; that window must have focus. Keep paper tabs beside keys, not stuck over moving key mechanisms.

**Event reset:** let the next pilot sit comfortably, check both TRACKED indicators, hold the yoke centered, press **N** then **Space** in the tracker preview to re-center for their grip, idle the throttle, and reset the flight. Run the full calibration (**C**) after the camera or props move. Short pitch: “Remember pretending a cardboard box was a plane? A webcam sees these two paper markers and turns their movement into flight controls.”

This is a build design ready for physical testing; prop durability, camera positioning, and live control feel still need a real build-and-fly check.
