"""Preserve photograph textures and tile borders in compact Godot-ready GLBs."""
from pathlib import Path
import concurrent.futures
import subprocess
import os
import argparse
import json
import struct

ROOT=Path(__file__).resolve().parents[1]

def level_subsurface_artifacts(target):
    """The relocated plateau has no below-sea-level basements/scan outliers."""
    data=target.read_bytes()
    json_size=struct.unpack_from("<I",data,12)[0]
    scene=json.loads(data[20:20+json_size])
    binary=bytearray(data[28+json_size:])
    changed=False
    positions={p["attributes"]["POSITION"] for m in scene["meshes"] for p in m["primitives"]}
    for index in positions:
        accessor=scene["accessors"][index]
        assert accessor["componentType"]==5126 and accessor["type"]=="VEC3"
        view=scene["bufferViews"][accessor["bufferView"]]
        offset=view.get("byteOffset",0)+accessor.get("byteOffset",0)
        stride=view.get("byteStride",12)
        for vertex in range(accessor["count"]):
            at=offset+vertex*stride+8
            if struct.unpack_from("<f",binary,at)[0]<0:
                struct.pack_into("<f",binary,at,0.0)
                changed=True
        accessor["min"][2]=max(0,accessor["min"][2])
        accessor["max"][2]=max(0,accessor["max"][2])
    if changed:
        document=json.dumps(scene,separators=(",",":")).encode()
        document+=b" "*((-len(document))%4)
        total=12+8+len(document)+8+len(binary)
        target.write_bytes(struct.pack("<4sII",b"glTF",2,total)+struct.pack("<II",len(document),0x4E4F534A)+document+struct.pack("<II",len(binary),0x004E4942)+binary)
if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--lod",default="16")
    parser.add_argument("--tile",default="672496")
    args=parser.parse_args()
    sources=sorted((ROOT/".downloads/helsinki"/args.tile).rglob(f"*_L{args.lod}_*.obj"))
    destination=ROOT/"simulator/assets/photogrammetry/helsinki"/f"lod{args.lod}"
    destination.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ,npm_config_cache="/tmp/cardboard-npm-cache")
    def convert(source):
        target=destination/(source.stem+".glb")
        if not target.exists():
            subprocess.run(["node",str(ROOT/".tools/mesh-tools/node_modules/gltfpack/cli.js"),"-i",str(source),"-o",str(target),"-noq","-slb"],check=True,env=env)
        level_subsurface_artifacts(target)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(convert,sources))
    collection=destination.parent
    manifest={level:sorted(p.name for p in (collection/level).glob("*.glb")) for level in ("lod16","lod17")}
    (collection/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    print("CONVERTED",len(sources),"tiles",sum(p.stat().st_size for p in destination.glob("*.glb")),"bytes")
