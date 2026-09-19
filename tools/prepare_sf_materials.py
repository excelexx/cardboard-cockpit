#!/usr/bin/env python3
"""Keep imported source alpha cutouts and mipmaps stable in motion."""
from pathlib import Path
import json
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];cache={};changed=0
for root in [ROOT/'simulator/assets/san_francisco',ROOT/'simulator/assets/sourced_flight']:
 for p in root.glob('*.gltf'):
  g=json.loads(p.read_text());dirty=False
  for m in g['materials']:
   t=m['pbrMetallicRoughness'].get('baseColorTexture')
   if not t:continue
   path=root/g['images'][g['textures'][t['index']]['source']]['uri']
   if path not in cache:
    im=Image.open(path);cache[path]='A' in im.getbands() and im.getextrema()[-1][0]<255
   if cache[path] and m.get('alphaMode')!='MASK':m['alphaMode']='MASK';m['alphaCutoff']=.4;dirty=True
  if dirty:p.write_text(json.dumps(g,separators=(',',':')));changed+=1
 for p in root.rglob('*.png.import'):
  s=p.read_text();new=s.replace('mipmaps/generate=false','mipmaps/generate=true').replace('detect_3d/compress_to=1','detect_3d/compress_to=0')
  if new!=s:p.write_text(new)
print('alpha models corrected',changed,'unique textures checked',len(cache))
