#!/usr/bin/env python3
"""Cull source tree instances from pavement/water using the downloaded aerial photos.
Retained positions and tree models are unchanged. No new trees are generated.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image
from pyproj.enums import TransformDirection
from import_sf_region import OUT,PROJ,C,S
meta=json.loads((OUT/'trees.json').read_text())
if 'source_count' in meta:
 print('Vegetation already filtered:',meta['count']);raise SystemExit
points=np.fromfile(OUT/'tree_positions.f32',dtype='<f4').reshape(-1,3)
e=C*points[:,0]-S*points[:,2];n=-S*points[:,0]-C*points[:,2]
lon,lat=PROJ.transform(e,n,direction=TransformDirection.INVERSE)
keep=np.ones(len(points),dtype=bool);covered=np.zeros(len(points),dtype=bool)
for tile in json.loads((OUT/'aerial/manifest.json').read_text()):
 ex=tile['extent'];ids=np.flatnonzero((lon>=ex['xmin'])&(lon<ex['xmax'])&(lat>=ex['ymin'])&(lat<ex['ymax']))
 if not len(ids):continue
 image=np.array(Image.open(OUT/'aerial'/(tile['tile']+'.jpg')).convert('RGB'))
 h,w=image.shape[:2];x=np.minimum(w-1,((lon[ids]-ex['xmin'])/(ex['xmax']-ex['xmin'])*w).astype(int));y=np.minimum(h-1,((ex['ymax']-lat[ids])/(ex['ymax']-ex['ymin'])*h).astype(int))
 rgb=image[y,x].astype(np.int16);r,g,b=rgb.T
 # Ordinary RGB vegetation: green dominates red and exceeds blue. This rejects
 # neutral roofs/pavement and blue water, without inventing replacement geometry.
 keep[ids]=(g-r>0)&(g-b>8)&(g>30);covered[ids]=True
chunks=[];selected=[];offset=0
for chunk in meta['chunks']:
 start=chunk['offset']//3;end=start+chunk['count'];p=points[start:end][keep[start:end]]
 if not len(p):continue
 selected.append(p);chunk['offset']=offset*3;chunk['count']=len(p);chunks.append(chunk);offset+=len(p)
backup=Path(__file__).resolve().parents[1]/'.downloads/sf-region/tree_positions-original.f32'
if not backup.exists():backup.write_bytes((OUT/'tree_positions.f32').read_bytes())
np.concatenate(selected).astype('<f4').tofile(OUT/'tree_positions.f32')
meta['source_count']=meta['count'];meta['count']=offset;meta['chunks']=chunks;meta['selection']='Source instances on vegetated aerial-photo pixels; original geometry and retained coordinates unchanged.'
(OUT/'trees.json').write_text(json.dumps(meta,separators=(',',':')))
print('VEGETATION:',meta['source_count'],'source instances ->',offset,'retained;',int(covered.sum()),'sampled against aerial photography')
