#!/usr/bin/env python3
"""Convert downloaded FlightGear Bay Area scenery (GPL-2.0+) to glTF.
No new scenery geometry is authored here: source meshes, UVs and placements are retained.
Requires numpy, pyproj, mapbox-earcut, Pillow. Sources: docs/san-francisco.md.
"""
from pathlib import Path
import sys,json,struct,gzip,math,hashlib,shutil,urllib.request,xml.etree.ElementTree as ET
from collections import defaultdict
import numpy as np
from pyproj import Transformer
import mapbox_earcut
from aircraft_convert import ac3d,sgi_png
ROOT=Path(__file__).resolve().parents[1]; SRC=ROOT/'.downloads/sf-region'; OUT=ROOT/'simulator/assets/san_francisco'; OUT.mkdir(exist_ok=True)
WORK=ROOT/'docs/source/san_francisco'; TEX=OUT/'textures';TEX.mkdir(exist_ok=True)
# Midpoint of KSFO 28R, true bearing derived from runway endpoints.
LON0,LAT0=-122.375285,37.62114; HEADING=math.radians(298.0)
PROJ=Transformer.from_crs('EPSG:4326',f'+proj=aeqd +lat_0={LAT0} +lon_0={LON0} +datum=WGS84 +units=m',always_xy=True)
ECEF=Transformer.from_crs(4978,4979,always_xy=True)
C,S=math.cos(HEADING),math.sin(HEADING)
def xyz(lon,lat,h=0):
 e,n=PROJ.transform(lon,lat);return np.stack([e*C-n*S,np.broadcast_to(h,np.shape(e)),-e*S-n*C],axis=-1)
def local(v,lon,lat,h=0,heading=0):
 # AC3D scenery axes: -Z east, -X north, +Y up.
 a=math.radians(heading);e=-v[:,2]*math.cos(a)+v[:,0]*math.sin(a);n=-v[:,2]*math.sin(a)-v[:,0]*math.cos(a)
 return np.stack([e*C-n*S,v[:,1],-e*S-n*C],axis=-1)+xyz(lon,lat,h)
def safe_path(base,value):
 p=(base/value).resolve()
 if not p.is_relative_to(SRC.resolve()):raise ValueError('asset path outside source tree')
 return p
texture_map={};missing=set();alpha_cache={}
def texture(path):
 if path is None:return None
 path=Path(path)
 if not path.exists():missing.add(str(path));return None
 key=hashlib.sha256(path.read_bytes()).hexdigest()[:16]
 name=key+'.png';dest=TEX/name
 if not dest.exists():
  from PIL import Image
  if path.suffix.lower() in ['.rgb','.rgba','.sgi']:dest.write_bytes(sgi_png(path.read_bytes()))
  else:
   im=Image.open(path);im.save(dest)
 return 'textures/'+name
class GLTF:
 def __init__(self):
  self.g={'asset':{'version':'2.0','generator':'FlightGear source format conversion'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'mesh':0}],'meshes':[{'primitives':[]}],'materials':[],'textures':[],'images':[],'samplers':[{'magFilter':9729,'minFilter':9987,'wrapS':10497,'wrapT':10497}],'buffers':[],'bufferViews':[],'accessors':[]};self.b=bytearray();self.m={};self.tris=0
 def acc(self,a):
  a=np.asarray(a,dtype='<f4');a=np.ascontiguousarray(a);kind='VEC'+str(a.shape[1]);g=self.g
  while len(self.b)%4:self.b.append(0)
  v=len(g['bufferViews']);g['bufferViews'].append({'buffer':0,'byteOffset':len(self.b),'byteLength':a.nbytes});self.b.extend(a.tobytes())
  i=len(g['accessors']);g['accessors'].append({'bufferView':v,'componentType':5126,'count':len(a),'type':kind,'min':a.min(axis=0).tolist(),'max':a.max(axis=0).tolist()});return i
 def add(self,p,uv,tex=None,rgb=(1,1,1),water=False):
  p=np.asarray(p,dtype=float).reshape(-1,3);uv=np.asarray(uv).reshape(-1,2)
  if not len(p):return
  tris=p.reshape(-1,3,3);norm=np.cross(tris[:,1]-tris[:,0],tris[:,2]-tris[:,0]);ln=np.linalg.norm(norm,axis=1);valid=ln>1e-7
  p=tris[valid].reshape(-1,3);uv=uv.reshape(-1,3,2)[valid].reshape(-1,2);norm=np.repeat(norm[valid]/ln[valid,None],3,axis=0)
  if not len(p):return
  key=(tex,tuple(rgb),water)
  if key not in self.m:
   mat={'name':Path(tex).stem if tex else 'source_material','doubleSided':True,'pbrMetallicRoughness':{'baseColorFactor':list(rgb)+[1],'roughnessFactor':.3 if water else .9,'metallicFactor':.05 if water else 0}}
   if tex:
    ti=len(self.g['textures']);self.g['images'].append({'uri':tex,'mimeType':'image/jpeg' if tex.endswith('.jpg') else 'image/png'});self.g['textures'].append({'source':ti,'sampler':0});mat['pbrMetallicRoughness']['baseColorTexture']={'index':ti}
   if tex:
    if tex not in alpha_cache:
     from PIL import Image
     im=Image.open(OUT/tex);alpha_cache[tex]='A' in im.getbands() and im.getextrema()[-1][0]<255
    if alpha_cache[tex]:mat['alphaMode']='MASK';mat['alphaCutoff']=.4
   self.m[key]=len(self.g['materials']);self.g['materials'].append(mat)
  self.g['meshes'][0]['primitives'].append({'attributes':{'POSITION':self.acc(p),'NORMAL':self.acc(norm),'TEXCOORD_0':self.acc(uv)},'material':self.m[key]});self.tris+=len(p)//3
 def save(self,name):
  (OUT/(name+'.bin')).write_bytes(self.b);self.g['buffers']=[{'uri':name+'.bin','byteLength':len(self.b)}];(OUT/(name+'.gltf')).write_text(json.dumps(self.g,separators=(',',':')))

def btg(path):
 data=gzip.decompress(path.read_bytes());i=0
 def read(fmt):
  nonlocal i
  vals=struct.unpack_from('<'+fmt,data,i);i+=struct.calcsize('<'+fmt);return vals[0] if len(vals)==1 else vals
 header=read('I');version=header&65535;read('I');num=read('I' if version>=10 else 'H');items=[];center=None;verts=None;uvs=None
 for _ in range(num):
  typ=read('B');np_,ne=read('II' if version>=10 else 'HH');props={}
  for _ in range(np_):
   k=read('B');n=read('I');props[k]=data[i:i+n];i+=n
  elems=[]
  for _ in range(ne):
   n=read('I');elems.append(data[i:i+n]);i+=n
  if typ==0:center=np.frombuffer(elems[0][:24],dtype='<f8')
  elif typ==1:verts=np.frombuffer(b''.join(elems),dtype='<f4').reshape(-1,3).astype(float)
  elif typ==3:uvs=np.frombuffer(b''.join(elems),dtype='<f4').reshape(-1,2)
  elif typ in [10,11,12]:items.append((typ,props,elems))
 lon,lat,h=ECEF.transform(*(verts+center).T);v=xyz(lon,lat,h)
 out=[]
 for typ,props,elems in items:
  mask=props.get(1,b'\x09')[0];bits=[b for b in range(8) if mask&(1<<b)];va=int.from_bytes(props.get(2,b'\0\0\0\0'),'little').bit_count();cols=len(bits)+va
  material=props.get(0,b'Unknown').rstrip(b'\0').decode();vi=bits.index(0);ti=bits.index(3) if 3 in bits else None
  for raw in elems:
   a=np.frombuffer(raw,dtype='<u4' if version>=10 else '<u2').reshape(-1,cols)
   if typ==10:idx=np.arange(len(a)).reshape(-1,3)
   elif typ==11:idx=np.array([[j,j+1,j+2] if j%2==0 else [j+1,j,j+2] for j in range(len(a)-2)])
   else:idx=np.array([[0,j,j+1] for j in range(1,len(a)-1)])
   if not len(idx):continue
   idx=idx.ravel();p=v[a[idx,vi]];uv=uvs[a[idx,ti]] if ti is not None else np.zeros((len(idx),2));out.append((material,p,uv))
 return out

def materials():
 m={}
 for name in ['materials-base.xml','global.xml','global-summer.xml']:
  doc=ET.parse(WORK/name)
  for node in doc.iter('material'):
   tex=node.findtext('texture') or node.findtext('texture-set/texture')
   for n in node.findall('name'):
    if tex:m[n.text]=(tex,float(node.findtext('xsize','1000')),float(node.findtext('ysize','1000')))
 return m

def terrain():
 mats=materials();files=sorted((SRC/'terrain').glob('*.btg.gz'));allmaterials=set();manifest=[]
 for path in files:
  name='terrain_'+path.name.split('.')[0]
  if (OUT/(name+'.gltf')).exists():continue
  model=GLTF();bounds=[]
  batches=defaultdict(lambda:[[],[]])
  for mat,p,uv in btg(path):
   batches[mat][0].append(p);batches[mat][1].append(uv)
  for mat,(ps,uvs) in batches.items():
   p=np.concatenate(ps);uv=np.concatenate(uvs)
   allmaterials.add(mat);tex=None;rgb=(1,1,1);water=mat.lower() in ['ocean','lake','water','reservoir']
   if mat in mats:
    t,x,y=mats[mat];tp=SRC/'textures'/t;tp.parent.mkdir(parents=True,exist_ok=True)
    if not tp.exists():
     try:tp.write_bytes(urllib.request.urlopen('https://gitlab.com/flightgear/fgdata/-/raw/next/Textures/'+t,timeout=30).read())
     except Exception:missing.add(t)
    tex=texture(tp)
   if not tex:rgb=(.055,.15,.20) if water else (.36,.39,.28)
   uv=uv.copy();uv[:,1]=1-uv[:,1]
   model.add(p,uv,tex,rgb,water);bounds.append(p)
  if model.tris:model.save(name);print(name,model.tris,flush=True)
 (OUT/'terrain_materials.json').write_text(json.dumps(sorted(allmaterials),indent=2))

def acmesh(path,lon,lat,h,heading,name,osm=False):
 model=GLTF();groups=defaultdict(lambda:[[],[]]);obs=ac3d(path)
 for o in obs:
  # This bridge includes an obsolete ground apron; regional terrain supplies it.
  if path.name=='ggb-fb.ac' and o['name'] in ['Plane.009','Plane.010','Plane.011','Plane.012','Plane.016']:continue
  if any(t.lower() in ['bare','rough','lod_rough'] for t in (*o['parents'],o['name'])) and not osm:continue
  if 'light' in o['name'].lower() and not osm:continue
  vs=local(np.asarray(o['verts']),lon,lat,h,heading)
  tex=texture(SRC/('roads.png' if osm=='roads' else 'atlas_facades.png')) if osm else texture(safe_path(path.parent,o['texture'])) if o['texture'] else None
  for f in o['faces']:
   if len(f['refs'])<3 or (f['flag']&15)!=0:continue
   a=np.array(f['refs']);ix=a[:,0].astype(int);verts=vs[ix];uv=a[:,1:];uv[:,1]=1-uv[:,1]
   if len(ix)==3:tri=np.array([0,1,2])
   else:
    normal=np.sum(np.cross(verts,np.roll(verts,-1,axis=0)),axis=0);axes=[i for i in range(3) if i!=np.argmax(np.abs(normal))];tri=mapbox_earcut.triangulate_float64(np.ascontiguousarray(verts[:,axes]),np.array([len(verts)],dtype=np.uint32))
   mat=o['materials'][f['mat']];rgb=tuple(mat['rgb']) if not tex else (1,1,1);key=(tex,rgb)
   groups[key][0].append(verts[tri]);groups[key][1].append(uv[tri])
 for (tex,rgb),(p,uv) in groups.items():
  if p:model.add(np.concatenate(p),np.concatenate(uv),tex,rgb)
 if model.tris:model.save(name)
 return model.tris

def buildings():
 base=SRC/'buildings/w123n37';i=0
 for stg in sorted(base.glob('*.stg')):
  for line in stg.read_text().splitlines():
   a=line.split()
   if not a or not a[0].startswith('OBJECT_BUILDING_MESH'):continue
   name='city_'+Path(a[1]).stem
   if (OUT/(name+'.gltf')).exists():continue
   tris=acmesh(base/a[1],*map(float,a[2:6]),name,True);i+=1
   print(name,tris,flush=True)

def landmarks():
 base=SRC/'objects'
 for stg in sorted(base.glob('*.stg')):
  for line in stg.read_text().splitlines():
   a=line.split()
   if not a or a[0]!='OBJECT_STATIC':continue
   path=safe_path(base,a[1]);name='landmark_'+path.stem
   if (OUT/(name+'.gltf')).exists():continue
   if path.suffix=='.xml':
    value=ET.parse(path).findtext('path')
    if not value:continue
    path=safe_path(base,value)
   if path.suffix!='.ac' or not path.exists():continue
   try:print(name,acmesh(path,*map(float,a[2:6]),name),flush=True)
   except Exception as e:print('ERROR',name,str(e),flush=True)

def roads():
 base=SRC/'roads/w123n37'
 for stg in sorted(base.glob('*.stg')):
  for line in stg.read_text().splitlines():
   a=line.split()
   if not a or not a[0].startswith(('OBJECT_ROAD','OBJECT_RAILWAY')):continue
   name='road_'+Path(a[1]).stem
   if (OUT/(name+'.gltf')).exists():continue
   lon,lat,h,heading=map(float,a[2:6])
   print(name,acmesh(base/a[1],lon,lat,h+.12,heading,name,'roads'),flush=True)

if __name__=='__main__':
 for mode in sys.argv[1:] or ['terrain','buildings','landmarks']:globals()[mode]()
 (OUT/'missing_textures.json').write_text(json.dumps(sorted(missing),indent=2))
