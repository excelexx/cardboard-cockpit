# San Francisco regional scenery

Version 0.10 uses an existing regional FlightGear/OSM2City dataset for its default world. It preserves the downloaded terrain triangles, building meshes, roads, geographic placements and source textures. The converter changes file formats, coordinate systems, triangulation and material handling; it does not invent a new city or individually model landmarks.

## Coverage and flight

The imported geographic tile covers longitude **123°W to 122°W**, latitude **37°N to 38°N**. This contains all of San Francisco, SFO, the central Bay, Alcatraz, Treasure Island, the Golden Gate and Bay bridges, the Marin Headlands, Oakland and much of the Peninsula. It does **not** claim complete coverage of all nine Bay Area counties or San Jose. The historical source snapshot is not a live map or a surveyed navigation product. Individual businesses and newly changed buildings are not guaranteed to have bespoke models.

The default flight departs SFO 28R, visits fourteen waypoints around the city and bridges, and returns to the same runway. A deterministic flight verification completed in 459.85 simulated seconds with every waypoint visited and zero terrain-recovery position corrections. The former Azure Coast and Alpine Valley remain selectable as legacy maps.

The map is anchored at the midpoint of SFO runway 28R: **37.62114, -122.375285**, true heading **298°**. Horizontal positions use a WGS84 azimuthal-equidistant projection. Terrain heights use geodetic altitude, avoiding the curvature-induced sinking that results from using tangent-plane height over a whole region. A 50-metre collision grid is sampled from the imported terrain; it is an approximation between samples, and the imported buildings are visual scenery rather than individual collision bodies.

## Source artwork

| Component | Original source | License / attribution |
| --- | --- | --- |
| Regional terrain, airport geometry and landmark models | [FlightGear TerraSync scenery](https://flightgear.sourceforge.net/scenery/), `Terrain` and `Objects/w130n30/w123n37` | FlightGear scenery GPL-2.0; source metadata and editable AC3D/BTG files retained |
| Regional building meshes and 562,416 building instances | [OSM2City regional mirror](https://terrasync.eti.pg.gda.pl/o2c/Buildings/w130n30/w123n37.txz) | FlightGear scenery licensing; OpenStreetMap contributors, ODbL attribution |
| Regional roads and 2,007,435 tree locations | [OSM2City](https://terrasync.eti.pg.gda.pl/o2c/) Roads and Trees archives for the same tile | Same source-data attribution |
| Building and tree templates | [SimGear SGBuildingBin](https://github.com/FlightGear/simgear/blob/next/simgear/scene/tgdb/SGBuildingBin.cxx), TreeBin and FGData shaders | GPL-2.0-or-later; Stuart Buchanan and FlightGear contributors. Source template coordinates and shader calculations are converted, not replaced with invented buildings |
| Building, road, terrain, water-normal and tree textures | [FlightGear FGData](https://gitlab.com/flightgear/fgdata) | Original FlightGear asset terms; downloaded inputs retained |
| Photographic sky | [Qwantani Sunset (Pure Sky)](https://polyhaven.com/a/qwantani_sunset_puresky) | CC0. Photography Greg Zaal; processing Jarod Guest. Original 4K EXR |
| Fighter exterior and cockpit; missile | [FGMEMBERS F-35B](https://github.com/FGMEMBERS/F-35B) | GPL-3.0; original aircraft author credits in `THIRD_PARTY_ASSETS.md`. Original livery and Cockpit/AIM-120 geometry; live 2D instruments mapped onto the source panel |
| Cannon mesh and muzzle/smoke artwork | [FGMEMBERS A-10](https://github.com/FGMEMBERS/A-10) | GPL-2.0; source model, textures and COPYING retained. Cannon geometry is extracted from the existing aircraft mesh |
| Goose | [Poly Pizza original](https://poly.pizza/m/9wn3If7Qgb4) | CC BY 3.0; existing author attribution retained in `simulator/assets/goose/README.md` |

[© OpenStreetMap contributors](https://www.openstreetmap.org/copyright). Redistribution includes the original downloaded archives and source files in `docs/source/san_francisco`, with SHA-256 hashes. The source building archives carry June 2021 generation timestamps. Online scenery is converted to an offline game bundle; playing does not contact map servers.

The prior generated detonation image is replaced by the existing Kenney CC0 particle sprite.

No AI image generation or new Blender modeling was used for this version. HUD drawing and shader/rendering configuration remain application code. The old maps and older artwork are retained for compatibility, but the San Francisco world does not instantiate their procedural terrain, villages or generated forest artwork.

## Conversion and rendering

- `tools/import_sf_region.py`: BTG terrain, AC3D meshes, source UVs, material textures and STG placement.
- `tools/import_sf_building_instances.py`: published BuildingList template and source dimensions/roof shapes.
- `tools/import_sf_trees.py`: published TreeBin template, source seasonal atlas and exact source locations.
- `tools/import_sourced_flight_art.py`: existing cockpit, cannon and missile meshes.
- `tools/finalize_sf_region.py`: geographic chunk index and terrain contact grid. Use `--index-only` when only mesh listings change.
- `tools/prepare_sf_materials.py`: source transparency cutouts and mipmapped texture import settings.

The scene streams nearby city/road chunks and tree batches. Terrain remains available for long views; individual mesh bounds allow normal frustum culling. Masked transparency, mipmaps, anisotropic filtering, MSAA and a larger camera near plane reduce shimmering. Alternate bridge LOD shells and light sprites are excluded so they are not rendered on top of one another.

To rebuild, unpack the source archives into `.downloads/sf-region/{terrain,objects,textures,buildings,roads,trees}` and copy the supplied atlases there. Install NumPy, Pillow, pyproj and mapbox-earcut in the project virtual environment. Run the converters, material preparation, `bake_sf_native.gd`, `finalize_sf_native.py`, and Godot import. Native scenes are compressed to roughly 594 MB, and tree coordinates are consolidated into one indexed binary stream. The source snapshot hashes are in `docs/source/san_francisco/sha256.json`.
