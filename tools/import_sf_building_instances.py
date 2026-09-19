#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Bake published FlightGear BuildingList instances using its GPL template/shader.
Template: Stuart Buchanan's SGBuildingBin.cxx (GPL-2.0-or-later).
Dimensions, roof shapes, rotations and texture selections come from the source list.
"""
from import_sf_region import *
import re
code=(WORK/'SGBuildingBin.cxx').read_text().split('geom->setVertexArray')[0]
points=np.array([[float(v) for v in s.split(',')] for s in re.findall(r'v->push_back\( osg::Vec3\(\s*([^)]*)\)',code)])
coords=np.array([[float(v) for v in s.split(',')] for s in re.findall(r't->push_back\( osg::Vec2\(\s*([^)]*)\)',code)])
# Four basement loops each emit six copies of their one UV entry.
coords=np.concatenate([np.zeros((24,2)),coords[4:]])
assert points.shape==(78,3) and coords.shape==(78,2),(points.shape,coords.shape)
colors=np.zeros((78,4));colors[:24,0]=1
for i in range(4):colors[24+i*6:30+i*6,0 if i%2==0 else 3]=1
colors[48:,1]=1
for i in range(4):colors[48+i*6+np.array([2,3,4]),2]=1
colors[72:,2]=1
tex=texture(SRC/'buildings-atlas.png');total=0
for stg in sorted((SRC/'buildings/w123n37').glob('*.stg')):
 for line in stg.read_text().splitlines():
  a=line.split()
  if not a or a[0]!='BUILDING_LIST':continue
  lon,lat,alt=map(float,a[3:6]);origin=xyz(lon,lat,alt);groups=defaultdict(list);uvgroups=defaultdict(list)
  for row in (stg.parent/a[1]).read_text().splitlines():
   vals=row.split('#')[0].split()
   if not vals:continue
   south,east,up,rotation,kind,width,depth,height,pitch,roof,orient,floors,wt,rt=map(float,vals)
   kind,roof,orient,floors,wt,rt=map(int,[kind,roof,orient,floors,wt,rt]);scale=np.ones(2)
   if pitch>0:
    if roof in [2,6,10,11]:scale=[0,1] if orient==0 else [1,0]
    if roof in [3,4,7]:scale=[0,np.clip((depth-2*pitch)/width,.5,1)] if orient==0 else [np.clip((width-2*pitch)/width,.5,1),0]
    if roof in [5,8,9]:scale=[0,0]
   p=points.copy();top=colors[:,2].astype(bool);p[top,0]=(p[top,0]+.5)*scale[0]-.5;p[top,1]*=scale[1];p[top,2]+=pitch/max(height,.1)
   p*=np.array([width,depth,height]);angle=math.radians(rotation);cr,sr=math.cos(angle),math.sin(angle);south_v=p[:,0]*cr+p[:,1]*sr+south;e=-p[:,0]*sr+p[:,1]*cr+east;n=-south_v
   p=np.stack([e*C-n*S,p[:,2]+up,-e*S-n*C],axis=-1)+origin
   if kind==0:wx,wy,rx,ry=0,wt%6*3/64,0,rt%6*3/64;tx=min(.5,round(width/5)/32);sx=min(.5,round(depth/5)/32);ty=min(3,floors)/64
   elif kind==1:wx,wy,rx,ry=wt%2*.25,(18+wt%3*8)/64,rt%2*.25,(18+rt%3*8)/64;tx=min(.25,math.ceil(width/10)/32);sx=min(.5,round(depth/10)/32);ty=min(8,floors)/64
   else:wx,wy,rx,ry=wt%4*.125,42/64,rt%4*.125,42/64;tx=min(.125,math.ceil(width/20)/32);sx=min(.5,round(depth/20)/32);ty=min(22,floors)/64
   uv=np.zeros((78,2));uv[:,0]=np.sign(coords[:,0])*(colors[:,0]*wx+colors[:,1]*rx+colors[:,3]*wx)+coords[:,0]*(colors[:,0]*tx+colors[:,1]*tx+colors[:,3]*sx);uv[:,1]=colors[:,0]*wy+colors[:,1]*ry+colors[:,3]*wy+coords[:,1]*ty
   uv[:,0]+=colors[:,1]*.5;uv[:,1]=1-uv[:,1]
   center=p.mean(axis=0);key=(int(center[0]//2500),int(center[2]//2500));groups[key].append(p);uvgroups[key].append(uv);total+=1
  for key,ps in groups.items():
   model=GLTF();model.add(np.concatenate(ps),np.concatenate(uvgroups[key]),tex);model.save(f'city_instances_{stg.stem}_{key[0]}_{key[1]}')
  print(stg.stem,total,flush=True)
print('SOURCE BUILDING INSTANCES',total)
