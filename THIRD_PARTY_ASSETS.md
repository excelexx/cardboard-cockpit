> Version 0.10 adds the sourced San Francisco regional world and restores source aircraft artwork. See [San Francisco source credits](docs/san-francisco.md) for the active assets and included original archives.

> Version 0.6: only the modified F-35B-derived SPECTRE is playable. Other aircraft are retained as licensed source provenance and excluded from the executable. Current art/audio modifications and credits are in [SPECTRE asset credits](docs/demo-assets.md).

# Third-party aircraft assets

## Countryside architecture

Kominka Modular Home Pack Lite by Rice Studio Lab, MIT license. Source:
https://store.godotengine.org/asset/rice-studio-lab/kominka-modular-home-pack-lite/
License and conversion notes are in `simulator/assets/kominka/`. The exterior
assembly layout and 24 modules are included; textures are shared and reduced to
512 px for aerial viewing. Publisher demo scripts are not used.

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

## Version 0.3 demo assets

See [demo asset credits](docs/demo-assets.md) for the Canada goose (Poly by Google, CC BY 3.0), Kenney ships and effects (CC0), MintoDog music (CC0), British Library goose recording (CC BY-SA 4.0), generated title artwork and original fan-made freighter adaptations. An-225 by Herbert Wagner, liveries by eagle, is GPL-2.0 with pinned source, COPYING and textures included.
# Coastal scenery additions

City of Helsinki photographic city mesh, CC BY 4.0: [credits and modifications](simulator/assets/photogrammetry/CREDITS.md). USGS/Mapzen elevation: [attribution and modifications](simulator/assets/environment/README.md).

Poly Haven CC0 architecture: [credits](simulator/assets/city/CREDITS.md). Optimized scanned rocks, tree model and derived tree silhouettes: [nature credits](simulator/assets/nature/CREDITS.md). Additional photographic 2K surfaces: [environment credits](simulator/assets/environment/README.md).
