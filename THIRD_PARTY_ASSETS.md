# Third-party aircraft assets

The playable client contains real exterior geometry and textures converted from the open-source FlightGear aircraft listed below. No Microsoft Flight Simulator assets are used. The original source files, relevant model assembly XML, attribution and license texts are supplied under `simulator/assets/aircraft/<id>/source/`.

| Aircraft / scene | Upstream source | Credited source authors | Asset license |
| --- | --- | --- | --- |
| Airbus A380 (`a380`) | [FGMEMBERS/A380](https://github.com/FGMEMBERS/A380) | Ampere K., Innis Cunningham, F. Dalvi, S. Hamilton and contributors | GNU GPL v2; enclosed COPYING and A380-set.xml notice |
| F-35B Lightning II (`f35`) | [FGMEMBERS/F-35B](https://github.com/FGMEMBERS/F-35B) | Petar Jedvaj, Detlef Faber, F-GTUX, Stuart Cassie, Gary Brown and contributors | GNU GPL v3; enclosed License.txt |
| Northrop B-2 Spirit (`b2`) | [FGMEMBERS/B-2](https://github.com/FGMEMBERS/B-2) | Markus Zojer | GNU GPL v2 or later; [FlightGear catalogue license record](https://wiki.flightgear.org/B-2_Spirit), enclosed COPYING and LICENSE-NOTE.txt |
| Boeing 737-300 (`b737`) | [FGMEMBERS/737-300](https://github.com/FGMEMBERS/737-300) | Innis Cunningham, Heiko Schulz, Emmanuel Baranger; Jarvum, e-pilot, Skyop, Soitanen and contributors. David Culp is credited for upstream FDM. | GNU GPL v3; enclosed LICENSE.md and README.txt |
| Boeing 747-400 exterior (`b747`) | [FGMEMBERS/747](https://github.com/FGMEMBERS/747) | Jim Wilson (3D) and FlightGear 747 contributors; [FlightGear author record](https://wiki.flightgear.org/Boeing_747-100) | GNU GPL v2; enclosed COPYING |

Downloaded September 18, 2026. Exact immutable source URLs, upstream revision IDs, file sizes and SHA-256 hashes are in `simulator/assets/aircraft/sources.json`. These source licenses apply to the original and converted aircraft assets; no relicense of those assets is asserted. Include these notices, license texts, source files and conversion tools when redistributing the converted assets.

## Modifications in this project

`tools/aircraft_convert.py` parses the original AC3D and 3DS meshes, triangulates polygons, computes normals, converts source SGI textures to PNG, embeds textures into GLB, and assembles the A380 wings, engines, pylons and horizontal stabilizer from its upstream source parts. The conversion preserves original texture art. It sets consistent meter scale, Y up and negative Z forward, centers the longitudinal and lateral bounds, and places the lowest extended-gear point at local Y = -3 meters.

Original simulation light-volume meshes and overlapping alternate gear shell meshes are omitted. The F-35 canopy and cockpit glazing use a dark reflective material. Military skins are tinted darker to suit Godot lighting. The models start with landing gear extended and expose an `Airframe/LandingGear` group for instantaneous show/hide retraction: FlightGear systems, flight dynamics, instrument behavior and animations are not imported. The A380 engines use their neutral static assembly orientation. The simulator's cockpit instruments and flight behavior are independently implemented, approximate, and do not reproduce each real aircraft's systems.

## Rebuilding

1. Run `python3 tools/aircraft_fetch.py` to verify or restore pinned original files.
2. Run `python3 tools/aircraft_convert.py` to rebuild all GLB and TSCN files.
3. Import the `simulator/` Godot project. Load each aircraft through `res://assets/aircraft/<id>/<id>.tscn`.

The conversion requires only the Python standard library. Models were imported and rendered in Godot 4.7.2 for inspection. Per-aircraft `manifest.json` records measured geometry bounds and triangle counts. Measurements include source geometry details and are not manufacturer specifications.
