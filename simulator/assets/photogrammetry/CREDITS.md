# Helsinki photograph-derived city mesh

Source: City of Helsinki, Helsinki 3D Mesh 2017, tiles 672496x2 and 674496x2.
[Official dataset information](https://www.hel.fi/en/decision-making/information-on-helsinki/maps-and-geospatial-data/helsinki-3d).
Licensed [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
Source archive: https://3d.hel.ninja/data/mesh/Helsinki3D-MESH_2017_OBJ_2km-250m_ZIP/Helsinki3D_2017_OBJ_672496x2.zip

Downloaded September 19, 2026. Converted selected OBJ levels of detail into GLB
with gltfpack 1.2, preserving source photographic textures. Below-datum scan
outliers were clamped to source elevation zero to fit the fictional plateau.
Coordinates are
relocated into a fictional game world; this does not represent actual Helsinki
geography or imply endorsement by the City of Helsinki. The source data was
captured in 2017 and is not a current navigation product.

Rebuild: fetch L16 for tiles 672496 and 674496, and L17 for 672496 with
`tools/fetch_photogrammetry.py --tile TILE --match _L16_ --download` (use `_L17_`
for the detail level). Install `gltfpack@1.2.0` under `.tools/mesh-tools`, then
run `tools/convert_photogrammetry.py --tile TILE --lod LEVEL` for each set.
The generated manifest supports both source launches and packaged exports.
Original downloads remain in ignored
`.downloads/helsinki`. Keep this attribution with redistributions.
