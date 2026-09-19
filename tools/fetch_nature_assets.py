"""Fetch CC0 Poly Haven nature sources into ignored downloads for optimization."""
import concurrent.futures
import json
import sys
from pathlib import Path
from fetch_city_assets import get, download

ROOT = Path(__file__).resolve().parents[1] / ".downloads/nature"
if __name__ == "__main__":
    for asset in (sys.argv[1:] or ("tree_small_02", "coast_land_rocks_04", "fir_tree_01")):
        info = json.loads(get("https://api.polyhaven.com/files/" + asset))["gltf"]["1k"]["gltf"]
        folder = ROOT / asset
        items = [(folder / (asset + ".gltf"), info)]
        items += [(folder / name, entry) for name, entry in info["include"].items()]
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(download, items))
