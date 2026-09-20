#!/usr/bin/env python3
"""Convert selected existing GPL FlightGear artwork; no original model geometry."""
import import_sf_region as sf
from aircraft_convert import ac3d,sgi_png
import numpy as np
from pathlib import Path
import shutil
from collections import defaultdict
sf.OUT=sf.ROOT/'simulator/assets/sourced_flight';sf.OUT.mkdir(exist_ok=True);sf.TEX=sf.OUT/'textures';sf.TEX.mkdir(exist_ok=True)
for name,file in [('cockpit','Cockpit.ac'),('cannon','A10.ac'),('missile','AIM-120.ac')]:
 model=sf.GLTF();groups=defaultdict(lambda:[[],[]])
 for o in ac3d(sf.SRC/file):
  if name=='cannon' and o['name']!='Cannon':continue
  v=np.array(o['verts']);v=np.stack([-v[:,2],v[:,1],v[:,0]],axis=-1)
  if name=='cockpit':v+=np.array([0,-1.08,5.05])
  elif name=='cannon':v=(v-(v.min(axis=0)+v.max(axis=0))/2)*2.5
  t=sf.texture(sf.SRC/Path(o['texture']).name) if o['texture'] else None
  for face in o['faces']:
   if len(face['refs'])<3:continue
   refs=np.array(face['refs']);p=v[refs[:,0].astype(int)];uv=refs[:,1:];uv[:,1]=1-uv[:,1]
   n=np.sum(np.cross(p,np.roll(p,-1,axis=0)),axis=0);axes=[i for i in range(3) if i!=np.argmax(abs(n))]
   tri=sf.mapbox_earcut.triangulate_float64(np.ascontiguousarray(p[:,axes]),np.array([len(p)],dtype=np.uint32)) if len(p)>3 else np.arange(3)
   rgb=tuple(o['materials'][face['mat']]['rgb']) if not t else (1,1,1);key=(t,rgb);groups[key][0].append(p[tri]);groups[key][1].append(uv[tri])
 for (t,rgb),(ps,uvs) in groups.items():
  if ps:model.add(np.concatenate(ps),np.concatenate(uvs),t,rgb)
 model.save(name);print(name,model.tris)
for original,output in [('puff-nuzzle.rgb','muzzle.png'),('puff-new.rgb','smoke.png')]:
 (sf.OUT/output).write_bytes(sgi_png((sf.SRC/original).read_bytes()))
# Retain the downloaded editable sources and licence alongside their conversions.
source=sf.OUT/'source';source.mkdir(exist_ok=True)
for name in ['Cockpit.ac','Panel.png','AIM-120.ac','AIM-120.png','A10.ac','A-10-000B.png','A10-COPYING','puff-nuzzle.rgb','puff-new.rgb']:shutil.copy2(sf.SRC/name,source/name)
shutil.copy2(sf.ROOT/'simulator/assets/aircraft/f35/source/License.txt',source/'F35-LICENSE.txt')
