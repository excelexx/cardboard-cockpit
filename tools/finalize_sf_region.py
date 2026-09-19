#!/usr/bin/env python3
"""Index converted source meshes and rasterize source terrain for flight contact."""
import json,sys
import numpy as np
from import_sf_region import OUT,SRC,xyz,LON0,LAT0,HEADING
from pathlib import Path
STEP=50.;MINX=-60000.;MINZ=-70000.;SIZE=2601
height=np.zeros((SIZE,SIZE),dtype='<f4');manifest=[];tris=0
for path in sorted(OUT.glob('*.gltf')):
 if path.name.startswith('tree_'):continue
 g=json.loads(path.read_text());lo=[];hi=[]
 for primitive in g['meshes'][0]['primitives']:
  a=g['accessors'][primitive['attributes']['POSITION']];lo.append(a['min']);hi.append(a['max']);tris+=a['count']//3
 bounds=[np.min(lo,axis=0).tolist(),np.max(hi,axis=0).tolist()];kind=path.stem.split('_')[0]
 manifest.append(dict(file=path.name,bounds=bounds,kind=kind))
 if kind!='terrain' or '--index-only' in sys.argv:continue
 data=(OUT/g['buffers'][0]['uri']).read_bytes()
 for primitive in g['meshes'][0]['primitives']:
  a=g['accessors'][primitive['attributes']['POSITION']];view=g['bufferViews'][a['bufferView']];p=np.frombuffer(data,dtype='<f4',count=a['count']*3,offset=view['byteOffset']).reshape(-1,3,3)
  for t in p:
   x=(t[:,0]-MINX)/STEP;z=(t[:,2]-MINZ)/STEP
   x0=max(0,int(np.ceil(x.min())));x1=min(SIZE-1,int(np.floor(x.max())));z0=max(0,int(np.ceil(z.min())));z1=min(SIZE-1,int(np.floor(z.max())))
   if x1<x0 or z1<z0:continue
   den=(z[1]-z[2])*(x[0]-x[2])+(x[2]-x[1])*(z[0]-z[2])
   if abs(den)<1e-8:continue
   gx,gz=np.meshgrid(np.arange(x0,x1+1),np.arange(z0,z1+1));u=((z[1]-z[2])*(gx-x[2])+(x[2]-x[1])*(gz-z[2]))/den;v=((z[2]-z[0])*(gx-x[2])+(x[0]-x[2])*(gz-z[2]))/den;w=1-u-v;valid=(u>=-1e-6)&(v>=-1e-6)&(w>=-1e-6)
   dst=height[z0:z1+1,x0:x1+1];dst[valid]=np.maximum(dst[valid],(u*t[0,1]+v*t[1,1]+w*t[2,1])[valid])
 print(path.stem,flush=True)
if '--index-only' not in sys.argv:height.tofile(OUT/'heights.f32')
(OUT/'region.json').write_text(json.dumps(dict(origin=[LON0,LAT0],heading_degrees=float(np.degrees(HEADING)),bounds_wgs84=[-123,37,-122,38],grid=dict(step=STEP,x=MINX,z=MINZ,size=SIZE),chunks=manifest,triangles=tris),indent=2))
print('CHUNKS',len(manifest),'TRIANGLES',tris)
