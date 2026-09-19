#!/usr/bin/env python3
"""Use compressed native scenes and consolidate tree position streams for distribution."""
from pathlib import Path
import json,shutil
ROOT=Path(__file__).resolve().parents[1];r=ROOT/'simulator/assets/san_francisco';stage=ROOT/'.downloads/sf-region/converted-runtime';stage.mkdir(exist_ok=True)
region=json.loads((r/'region.json').read_text())
for item in region['chunks']:
 native=Path(item['file']).with_suffix('.scn').name
 if not (r/native).exists():raise RuntimeError('Missing compiled scene '+native)
 item['file']=native
(r/'region.json').write_text(json.dumps(region,indent=2))
trees=json.loads((r/'trees.json').read_text());data=bytearray()
if not (r/'tree_positions.f32').exists():
 for chunk in trees['chunks']:
  p=r/chunk.pop('file');raw=p.read_bytes();chunk['offset']=len(data)//4;data.extend(raw);shutil.move(str(p),str(stage/p.name))
 (r/'tree_positions.f32').write_bytes(data)
for chunk in trees['chunks']:chunk['mesh']=Path(chunk['mesh']).with_suffix('.scn').name
(r/'trees.json').write_text(json.dumps(trees,separators=(',',':')))
for p in list(r.glob('*.gltf'))+list(r.glob('*.bin'))+list(r.glob('*.gltf.import')):shutil.move(str(p),str(stage/p.name))
print('Native scenery:',len(region['chunks']),'chunks;',trees['count'],'source trees')
