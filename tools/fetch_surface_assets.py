"""Fetch local CC0 surface maps from Poly Haven with checksum verification."""
import concurrent.futures
import json
from pathlib import Path
from fetch_city_assets import get, download

ROOT = Path(__file__).resolve().parents[1] / "simulator/assets/environment"
ASSETS = ("aerial_rocks_02", "coast_sand_rocks_02", "aerial_asphalt_01")

if __name__ == "__main__":
    items = []
    for asset in ASSETS:
        info = json.loads(get("https://api.polyhaven.com/files/" + asset))
        for key, suffix in (("Diffuse", "diff"), ("nor_gl", "nor_gl")):
            items.append((ROOT / f"{asset}_{suffix}_2k.jpg", info[key]["2k"]["jpg"]))
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(download, items))
