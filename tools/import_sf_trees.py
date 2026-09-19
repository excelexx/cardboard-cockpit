#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Import FlightGear TreeBin's published crossed-plane template and TREE_LIST positions.
Template/UV layout: SimGear TreeBin.cxx and FGData tree.vert, GPL-2.0-or-later.
"""
from import_sf_region import *
# FlightGear source tree atlas: eight columns, four seasonal rows; bottom row is summer.
for name in ['deciduous','mixed']:
 tex=texture(SRC/(name+'.png'))
 for variety in range(8):
  p=[];uv=[]
  for i in range(3):
   x1=math.sin(i*math.pi/3)*.5;z1=math.cos(i*math.pi/3)*.5
   vs=[(x1,0,z1),(-x1,0,-z1),(-x1,1,-z1),(x1,1,z1)]
   for k in [0,1,2,0,2,3]:
    p.append(vs[k]);uv.append(((variety+(1 if k in [1,2] else 0))/8,1-(.234 if k>1 else 0)))
  m=GLTF();m.add(p,uv,tex);m.save(f'tree_{name}_{variety}')
base=SRC/'trees/w123n37';groups=defaultdict(list);total=0
for stg in sorted(base.glob('*.stg')):
 for line in stg.read_text().splitlines():
  a=line.split()
  if not a or a[0]!='TREE_LIST':continue
  lon,lat,h=map(float,a[3:6]);v=np.loadtxt(base/a[1],dtype=np.float64,ndmin=2)[:,:3]
  if not len(v):continue
  # makeZUpFrame uses south/east/up; a comment in TreeBin uses a different convention.
  e=v[:,1];n=-v[:,0];points=np.stack([e*C-n*S,v[:,2],-e*S-n*C],axis=-1)+xyz(lon,lat,h)
  kind='deciduous' if 'Deciduous' in a[2] else 'mixed'
  for i,p in enumerate(points):groups[(int(p[0]//2000),int(p[2]//2000),kind,i%8)].append(p)
  total+=len(points)
manifest=[]
for (x,z,kind,variety),points in groups.items():
 p=np.asarray(points,dtype='<f4');name=f'trees_{x}_{z}_{kind}_{variety}.f32';p.tofile(OUT/name)
 manifest.append(dict(file=name,mesh=f'tree_{kind}_{variety}.gltf',center=[x*2000+1000,z*2000+1000],count=len(p)))
(OUT/'trees.json').write_text(json.dumps(dict(count=total,chunks=manifest),separators=(',',':')))
print('SOURCE TREES',total,'chunks',len(manifest))
