# CC0 nature models

Models from Poly Haven, redistributed and optimized under CC0: https://polyhaven.com/license

- Tree Small 02 — Rico Cilliers: https://polyhaven.com/a/tree_small_02
- Coast Land Rocks 04 — Rob Tuytel (photography/processing), Rico Cilliers (cleanup): https://polyhaven.com/a/coast_land_rocks_04

The GLBs embed the original 1K PBR textures. Geometry was simplified with gltfpack 1.2: tree 2,062,487 → 12,610 triangles; rock 1,086,668 → 10,865 triangles. Distant forests use `tree_impostor.png`, rendered from the full-resolution tree with `tests/bake_tree_impostor.gd`. No original source models are required at runtime.

Reproduce by running `python3 tools/fetch_nature_assets.py`, then gltfpack with `-si 0.006 -se 0.05 -sp -noq` for the tree, or `-si 0.01 -se 0.03 -sp -noq` for the rocks. Source glTFs are downloaded under ignored `.downloads/nature/`; output GLBs go here. Do not use mesh compression without adding a compatible Godot importer.
# Fir forest

`fir_0.png`, `fir_1.png`, and `fir_2.png` are offline rendered derivatives of
[Poly Haven fir_tree_01](https://polyhaven.com/a/fir_tree_01), licensed CC0.
Restore the source with `python3 tools/fetch_nature_assets.py fir_tree_01`, then
run `simulator/tests/bake_forest_impostors.gd` with native Godot. The large source
is kept in ignored `.downloads/nature`; only the three silhouettes ship.
