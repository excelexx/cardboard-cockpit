# Phase 0 — environment and implementation path

Checked September 18, 2026.

## Completed

- Read the supplied Cardboard Cockpit brief and incorporated the native-client, five-aircraft garage, realistic visuals, and keyboard/mouse-first amendments.
- Created the local project folder and planned source directories.
- Confirmed GitHub CLI access to the `excelexx` account. The repository will be private by default.
- Selected a native Godot architecture and documented phased acceptance checks.
- Researched externally sourced aircraft assets. Candidates are separate from downloaded, verified assets.

## Development environment

| Item | Observed result | Implication |
| --- | --- | --- |
| Computer | Apple M4, 8 GPU cores, 16 GiB RAM | Profile the detailed scene on this machine; use scalable rendering settings |
| OS | macOS 27.0, Apple Silicon | First exported client will be a Mac `.app` |
| Display | One built-in 2560 × 1664 display currently connected | Single-display layout first; spectator window can be optional later |
| Webcam | Built-in MacBook Air camera and an iPhone camera device are enumerated | Hardware is present; capture, permission, and tracking have not been tested |
| Godot | Not found in PATH or inspected application directories | Download the official prebuilt editor and export templates in Phase 1 |
| Blender | Not found in PATH or inspected application directories | Prefer directly importable assets; add Blender only if conversion is necessary |
| Python | Command Line Tools Python 3.9.6 works at its explicit path | A separate Python 3.12 environment is proposed for the future vision service |
| System Python launcher | `/usr/bin/python3` is blocked by an unaccepted Xcode license | Avoid relying on this launcher; no license terms were accepted on the user's behalf |
| Git | 2.52.0, identity configured | Ready for version control |
| GitHub | Authenticated as `excelexx`, repository access available | Ready to create and push the requested repository |
| Node.js / npm | 24.15.0 / 11.12.1 | Available for optional tooling; not required by the native game |

No camera feed was opened, and no game engine was installed at this checkpoint.

## Decisions

1. Use Godot 4.7.2 and typed GDScript to export a native Mac client.
2. Pursue a realistic mountain-airport aesthetic, since the latest request already specifies a Microsoft Flight Simulator-inspired direction.
3. Make keyboard and mouse sufficient for the first playable checkpoint. Defer camera setup and calibration until their scheduled phase.
4. Create the hangar as a distinct stage before flight. All five requested aircraft must be represented, with model provenance and a per-aircraft handling profile.
5. Keep flight simulation independent of the input source so cardboard controls can be added cleanly.
6. Treat frame rate, cockpit/model detail, and aircraft-download availability as things to verify in the playable phase, not claims made during planning.

## Review checkpoint

The folder, documentation, and repository can be reviewed now. Flight, rendering, aircraft imports, camera capture, and the complete mission cannot be tested yet.

The supplied brief explicitly says “Begin with Phase 0 only” and “Do not begin the next phase until I answer the phase question.” Implementation therefore waits at this checkpoint.

**Checkpoint question:** Proceed with Phase 1 using native Godot, realistic scenery, and the five-aircraft hangar?
