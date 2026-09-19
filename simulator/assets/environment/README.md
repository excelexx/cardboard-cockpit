# Alpine environment assets

## Coastal surface upgrade

The coast also includes 2K diffuse and OpenGL normal maps from these Poly Haven CC0 assets: [Aerial Rocks 02](https://polyhaven.com/a/aerial_rocks_02), [Coast Sand Rocks 02](https://polyhaven.com/a/coast_sand_rocks_02), and [Aerial Asphalt 01](https://polyhaven.com/a/aerial_asphalt_01). `tools/fetch_surface_assets.py` reproduces the downloads and checks their published MD5 hashes. Nature model credits are in `../nature/CREDITS.md`.

All scenery geometry, terrain generation, atmospheric billboards, and material shaders in this directory are original to Cardboard Cockpit.

The two photographic ground textures were downloaded from **Poly Haven** and used unmodified as input to the terrain material. Both are distributed under [CC0](https://polyhaven.com/license), allowing redistribution and commercial use.

| File | Asset page | Download |
| --- | --- | --- |
| `aerial_grass_rock_diff_1k.jpg` | [Aerial Grass Rock](https://polyhaven.com/a/aerial_grass_rock) | [1K JPEG](https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/aerial_grass_rock/aerial_grass_rock_diff_1k.jpg) |
| `aerial_rocks_02_diff_1k.jpg` | [Aerial Rocks 02](https://polyhaven.com/a/aerial_rocks_02) | [1K JPEG](https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/aerial_rocks_02/aerial_rocks_02_diff_1k.jpg) |

Sources accessed September 18, 2026. The landscape and airports are fictional; no Microsoft Flight Simulator content is included.

The golden-hour photographic sky uses [Kloppenheim 06 (Pure Sky)](https://polyhaven.com/a/kloppenheim_06_puresky), a CC0 panorama from Poly Haven ([2K HDR source](https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/kloppenheim_06_puresky_2k.hdr)). Clear midday and high overcast use the original `weather_sky.gdshader`, with static procedural cloud cover and no additional geometry or external assets. Lighting, fog and sky changes are visual presets; they do not simulate wind, turbulence, precipitation, or real-world weather. The original billboard cloud shader remains available but is not instantiated in the scene.
# Real elevation relief

`rainier_terrarium.png` and `rainier_south_terrarium.png` are Terrarium tiles
10/165/360 and 10/165/361 from the [Mapzen Terrain Tiles dataset](https://registry.opendata.aws/terrain-tiles/), accessed September 19, 2026.
SRTM and GMTED2010 terrain data courtesy of the U.S. Geological Survey.
Sources: https://s3.amazonaws.com/elevation-tiles-prod/terrarium/10/165/360.png
and https://s3.amazonaws.com/elevation-tiles-prod/terrarium/10/165/361.png.
Provider attribution and terms: https://github.com/tilezen/joerd/blob/master/docs/attribution.md.
The game bilinearly samples, rescales vertically to 74%, relocates, and blends
this relief into a fictional coastline. This is not an accurate Rainier map,
not endorsed by USGS, and not suitable for navigation. Preserve the PNGs
losslessly: RGB values encode numeric elevations, not display colors.
