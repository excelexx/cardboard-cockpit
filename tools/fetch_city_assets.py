"""Fetch the two CC0 Poly Haven kits used by the city; no runtime network needed."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1] / "simulator/assets/city"
ASSETS = ("modular_urban_apartments_facade", "modular_factory_facade")

def get(url):
    with urlopen(Request(url, headers={"User-Agent": "CardboardCockpitAssetSetup/1.0"}), timeout=90) as response:
        return response.read()

def download(item):
    path, metadata = item
    if path.exists() and hashlib.md5(path.read_bytes()).hexdigest() == metadata["md5"]:
        return
    data = get(metadata["url"])
    if hashlib.md5(data).hexdigest() != metadata["md5"]:
        raise RuntimeError(f"Checksum mismatch: {path.name}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    print(path.name, len(data), flush=True)

if __name__ == "__main__":
    for asset in ASSETS:
        info = json.loads(get("https://api.polyhaven.com/files/" + asset))["gltf"]["1k"]["gltf"]
        folder = ROOT / asset
        items = [(folder / (asset + "_1k.gltf"), info)]
        items += [(folder / name, entry) for name, entry in info["include"].items()]
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(download, items))
