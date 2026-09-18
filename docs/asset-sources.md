# Aircraft assets used in the playable client

The first playable client uses actual FlightGear exterior meshes and original textures for all five aircraft. The earlier Sketchfab shortlist was not used because its downloads require authentication. No downloaded model here is a procedural placeholder.

See [THIRD_PARTY_ASSETS.md](../THIRD_PARTY_ASSETS.md) for authors, licenses, conversion details and source distribution notices. The pinned [sources manifest](../simulator/assets/aircraft/sources.json) records every original file and its SHA-256 hash.

| ID | Included variant | Model triangles | Measured span × length | Godot entry scene |
| --- | --- | ---: | --- | --- |
| a380 | Airbus A380, Airbus house livery | 20,220 | 79.78 × 73.02 m | `assets/aircraft/a380/a380.tscn` |
| f35 | F-35B, default source livery | 28,387 | 11.05 × 17.15 m | `assets/aircraft/f35/f35.tscn` |
| b2 | B-2 Spirit, source military livery | 5,612 | 52.20 × 21.21 m | `assets/aircraft/b2/b2.tscn` |
| b737 | Boeing 737-300, white livery | 48,534 | 28.73 × 33.30 m | `assets/aircraft/b737/b737.tscn` |
| b747 | Boeing 747-400 exterior, original livery | 6,725 | 65.09 × 72.12 m | `assets/aircraft/b747/b747.tscn` |

Dimensions are the imported mesh bounds, not certified aircraft dimensions. Source detail such as probes can extend beyond the nominal dimensions. All scenes have their nose toward -Z and their up axis +Y. Place their root at Y=3 to put the extended wheels on a flat ground plane. Each model's exact bounds are in its `manifest.json`.

The A380 is assembled from its real upstream fuselage, wings, horizontal stabilizer, pylons and four engines. The F-35 includes the original engine and landing-gear meshes. The models have varying source quality, from a detailed 737 to an older low-polygon 747. The models expose `Airframe/LandingGear` to hide/show their wheels and struts, but do not translate FlightGear's animation XML, flight model or cockpit systems into Godot.

Use `python3 tools/aircraft_fetch.py` to verify source integrity and `python3 tools/aircraft_convert.py` to regenerate assets. Both scripts use only the standard library. `tools/aircraft_preview.gd` renders each converted aircraft in an isolated inspection scene.

## Render verification

All five scenes were imported and rendered in Godot 4.7.2 with OpenGL compatibility on Apple M4. Front-quarter, overhead and side views were inspected: aircraft point toward -Z, textures resolve, and A380 components are assembled symmetrically. The `Airframe/LandingGear` child was found and toggled successfully for every aircraft (52, 14, 21, 29 and 57 geometry nodes respectively). Gear retraction currently hides wheel/strut meshes instantly; door poses remain static. No model import errors appeared.
