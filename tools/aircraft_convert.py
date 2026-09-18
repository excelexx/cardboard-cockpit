#!/usr/bin/env python3
"""Convert the selected GPL FlightGear AC3D/3DS source meshes into meter-scale glTF.
No network or third-party Python dependencies are needed for conversion.
Sources and textures remain under each aircraft/source. See THIRD_PARTY_ASSETS.md.
"""
from pathlib import Path
import json, math, re, shlex, struct, zlib, hashlib
ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'simulator/assets/aircraft'

def vadd(a,b):return tuple(x+y for x,y in zip(a,b))
def vsub(a,b):return tuple(x-y for x,y in zip(a,b))
def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def unit(a):
 l=math.sqrt(sum(x*x for x in a));return tuple(x/l for x in a) if l>1e-10 else (0,1,0)
def bounds(verts):return [[min(v[k] for v in verts) for k in range(3)],[max(v[k] for v in verts) for k in range(3)]]
def ac3d(path):
 lines=path.read_text(errors='replace').splitlines();i=1;materials=[];objects=[]
 while i<len(lines) and lines[i].startswith('MATERIAL '):
  ts=shlex.split(lines[i]);rgb=ts.index('rgb');trans=ts.index('trans');materials.append({'name':ts[1],'rgb':list(map(float,ts[rgb+1:rgb+4])),'alpha':1-float(ts[trans+1])});i+=1
 def obj(parent=(0,0,0), ancestry=()):
  nonlocal i
  assert lines[i].startswith('OBJECT '),(i,lines[i]);i+=1
  o={'name':'mesh','loc':(0,0,0),'verts':[],'faces':[],'texture':None,'materials':materials,'path':str(path),'crease':45,'parents':ancestry};rot=None
  while i<len(lines):
   ts=shlex.split(lines[i]);i+=1
   if not ts:continue
   k=ts[0]
   if k=='name':o['name']=ts[1]
   elif k=='loc':o['loc']=tuple(map(float,ts[1:4]))
   elif k=='rot':rot=list(map(float,ts[1:]))
   elif k=='crease':o['crease']=float(ts[1])
   elif k=='texture':o['texture']=ts[1]
   elif k=='data':i+=1
   elif k=='numvert':
    for _ in range(int(ts[1])):o['verts'].append(tuple(map(float,lines[i].split())));i+=1
   elif k=='numsurf':
    for _ in range(int(ts[1])):
     f={'mat':0,'refs':[],'flag':0}
     while i<len(lines):
      fs=lines[i].split();i+=1
      if fs[0]=='SURF':f['flag']=int(fs[1],0)
      elif fs[0]=='mat':f['mat']=int(fs[1])
      elif fs[0]=='refs':
       for _ in range(int(fs[1])):
        rs=lines[i].split();i+=1;f['refs'].append((int(rs[0]),float(rs[1]),float(rs[2])))
       break
     o['faces'].append(f)
   elif k=='kids':
    p=vadd(parent,o['loc'])
    if rot:
     o['verts']=[tuple(sum(rot[r*3+c]*v[c] for c in range(3)) for r in range(3)) for v in o['verts']]
    o['verts']=[vadd(v,p) for v in o['verts']]
    if o['verts']:objects.append(o)
    for _ in range(int(ts[1])):obj(p,ancestry+(o['name'],))
    return
  raise ValueError('unterminated object')
 obj();return objects


def three_ds(path):
 data=path.read_bytes();objects=[];materials=[]
 def chunks(start,end):
  while start+6<=end:
   cid,size=struct.unpack_from('<HI',data,start)
   if size<6:break
   yield cid,start+6,start+size
   start+=size
 def textat(p):
  q=data.index(b'\0',p);return data[p:q].decode('latin1'),q+1
 def read_color(s,e):
  for cid,a,b in chunks(s,e):
   if cid in (0x10,0x12):return list(struct.unpack_from('<3f',data,a))
   if cid in (0x11,0x13):return [v/255 for v in data[a:a+3]]
  return [.8,.8,.8]
 def walk(start,end):
  for cid,s,e in chunks(start,end):
   if cid in [0x4d4d,0x3d3d]:walk(s,e)
   elif cid==0xafff:
    m={'name':'material','rgb':[.8,.8,.8],'alpha':1}
    for c,a,b in chunks(s,e):
     if c==0xa000:m['name']=textat(a)[0]
     elif c==0xa020:m['rgb']=read_color(a,b)
     elif c==0xa200:
      for tc,ta,tb in chunks(a,b):
       if tc==0xa300:m['texture']=textat(ta)[0]
    materials.append(m)
   elif cid==0x4000:
    name,p=textat(s);o={'name':name,'verts':[],'faces':[],'texture':None,'materials':materials,'path':str(path),'crease':45};uv=[]
    for cc,ss,ee in chunks(p,e):
     if cc!=0x4100:continue
     for c,a,b in chunks(ss,ee):
      if c==0x4110:
       n=struct.unpack_from('<H',data,a)[0]
       # 3DS stores Z-up; AC3D uses Y-up.
       o['verts']=[(v[0],v[2],-v[1]) for v in [struct.unpack_from('<3f',data,a+2+12*i) for i in range(n)]]
      elif c==0x4120:
       n=struct.unpack_from('<H',data,a)[0]
       for i in range(n):o['faces'].append({'refs':[(v,0,0) for v in struct.unpack_from('<3H',data,a+2+8*i)],'mat':0,'flag':0x10})
       for fc,fa,fb in chunks(a+2+8*n,b):
        if fc==0x4130:
         mn,q=textat(fa);num=struct.unpack_from('<H',data,q)[0];mi=next((j for j,m in enumerate(materials) if m['name']==mn),0)
         for j in range(num):o['faces'][struct.unpack_from('<H',data,q+2+2*j)[0]]['mat']=mi
      elif c==0x4140:
       n=struct.unpack_from('<H',data,a)[0];uv=[struct.unpack_from('<2f',data,a+2+8*i) for i in range(n)]
    for f in o['faces']:f['refs']=[(v,*(uv[v] if v<len(uv) else (0,0))) for v,_,_ in f['refs']]
    if o['verts']:objects.append(o)
 walk(0,len(data));return objects

def sgi_png(data):
 """Decode 8-bit uncompressed/RLE SGI RGB and encode PNG losslessly."""
 magic,storage,bpc,dim,w,h,channels=struct.unpack_from('>HBBHHHH',data,0)
 if magic!=474 or bpc!=1:raise ValueError('unsupported SGI image')
 planes=[]
 for c in range(channels):
  rows=[]
  for y in range(h):
   if not storage:row=data[512+(c*h+y)*w:512+(c*h+y+1)*w]
   else:
    p=struct.unpack_from('>I',data,512+4*(c*h+y))[0];row=bytearray()
    while True:
     n=data[p];p+=1;count=n&127
     if count==0:break
     if n&128:row.extend(data[p:p+count]);p+=count
     else:row.extend([data[p]]*count);p+=1
    row=bytes(row)
   rows.append(row)
  planes.append(rows)
 channels=min(channels,4);mode={1:0,2:4,3:2,4:6}[channels]
 pixels=b''.join(b'\0'+bytes(planes[c][y][x] for x in range(w) for c in range(channels)) for y in reversed(range(h)))
 def chunk(t,p):return struct.pack('>I',len(p))+t+p+struct.pack('>I',zlib.crc32(t+p)&0xffffffff)
 return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,mode,0,0,0))+chunk(b'IDAT',zlib.compress(pixels,9))+chunk(b'IEND',b'')

def translate(objects,offset):
 for o in objects:o['verts']=[vadd(v,offset) for v in o['verts']]
 return objects

def a380_objects(src):
 obs=ac3d(src/'Models/a380.ac')
 obs+=three_ds(src/'Models/windshield.3ds')
 obs=[o for o in obs if 'light' not in o['name'].lower()]
 wing_offset=(31.496,4.65804,0)
 obs+=translate(ac3d(src/'Models/Wings/wings.ac'),wing_offset)
 obs+=translate(three_ds(src/'Models/htp.3ds'),(64.616,7.19884,0))
 obs+=translate(three_ds(src/'Models/Wings/bathtub.3ds'),wing_offset)
 import xml.etree.ElementTree as ET
 for n in range(1,5):
  doc=ET.parse(src/f'XML/Wings/pylon{n}.xml').getroot()
  def offset(el):
   off=el.find('offsets')
   return (float(off.findtext('x-m','0')),float(off.findtext('z-m','0')),-float(off.findtext('y-m','0')))
  pylon_offset=vadd(wing_offset,offset(doc))
  obs+=translate(three_ds(src/f'Models/Wings/pylon{n}.3ds'),pylon_offset)
  engine_offset=vadd(pylon_offset,offset(doc.find('model')))
  # Static display assembly, the original 3-degree engine pitch is intentionally omitted.
  obs+=translate(ac3d(src/'Models/Wings/cowling.ac'),engine_offset)
  obs+=translate(three_ds(src/'Engines/Models/high.3ds'),engine_offset)
 return obs

def convert(id,files):
 src=ASSETS/id/'source';out=ASSETS/id
 objects=a380_objects(src) if id=='a380' else sum((ac3d(src/f) for f in files),[])
 # FlightGear selects these light sprites / duplicate opaque shells at runtime.
 excluded={'b737':['Llightl','Llightr','navlight_back','navlight_left','navlight_right'],'b747':['FuselageBottomGearDown'],'f35':['sonicboom','redlight','greenlight'],'b2':[]}
 objects=[o for o in objects if o['name'] not in excluded.get(id,[]) and o['faces']]
 allv=[v for o in objects for v in o['verts']];lo,hi=bounds(allv)
 center=( (lo[0]+hi[0])/2,lo[1]+3,(lo[2]+hi[2])/2 )
 for o in objects:o['verts']=[(-(v[2]-center[2]),v[1]-center[1],v[0]-center[0]) for v in o['verts']]
 gltf={'asset':{'version':'2.0','generator':'Cardboard Cockpit FlightGear source converter'},'scene':0,'scenes':[{'nodes':[]}],'nodes':[],'meshes':[],'materials':[],'textures':[],'images':[],'samplers':[{'magFilter':9729,'minFilter':9987,'wrapS':10497,'wrapT':10497}],'accessors':[],'bufferViews':[],'buffers':[]}
 binary=bytearray();matmap={};texmap={};triangles=0;gear_nodes=[];gear_names=[]
 def blob(raw,target=None):
  while len(binary)%4:binary.append(0)
  ix=len(gltf['bufferViews']);view={'buffer':0,'byteOffset':len(binary),'byteLength':len(raw)}
  if target:view['target']=target
  gltf['bufferViews'].append(view);binary.extend(raw);return ix
 def accessor(vals,kind):
  comps={'VEC3':3,'VEC2':2}[kind];raw=struct.pack('<'+'f'*(len(vals)*comps),*(c for v in vals for c in v))
  acc={'bufferView':blob(raw,34962),'componentType':5126,'count':len(vals),'type':kind}
  if kind=='VEC3':acc['min'],acc['max']=bounds(vals)
  ix=len(gltf['accessors']);gltf['accessors'].append(acc);return ix
 def tex(name,path):
  if not name:return None
  key=(name,path)
  if key in texmap:return texmap[key]
  source=Path(path).parent/name
  if id=='a380' and (src/'Textures/Livery/House'/name).exists():source=src/'Textures/Livery/House'/name
  if not source.exists():
   hits=[p for p in src.rglob('*') if p.is_file() and p.name.lower()==Path(name).name.lower()]
   if not hits:raise ValueError(f'missing texture {id}/{name}')
   source=hits[0]
  raw=source.read_bytes()
  if source.suffix.lower()=='.rgb':raw=sgi_png(raw)
  ix=len(gltf['textures']);gltf['images'].append({'bufferView':blob(raw),'mimeType':'image/png','name':name});gltf['textures'].append({'source':len(gltf['images'])-1,'sampler':0});texmap[key]=ix;return ix
 def material(o,index):
  m=o['materials'][index] if o['materials'] else {'name':'default','rgb':[.7,.7,.72],'alpha':1}
  texture=o['texture'] or m.get('texture');name=o['name'].lower()
  isglass=(id=='f35' and name in ['canopy','eots']) or 'glass' in m['name'].lower() or 'windshield' in name or 'windscreen' in name or (id=='b737' and name in ['glas','glas2','eyebrowwindow']) or (id=='a380' and 'windshield' in o['path'])
  key=(tuple(m['rgb']),m['alpha'],texture,o['path'],isglass)
  if key in matmap:return matmap[key]
  factor=m['rgb']+[m['alpha']];metal=.22;rough=.42
  if id=='b2' and texture and 'spirit' in texture.lower():factor=[x*.36 for x in factor[:3]]+[factor[3]];metal=.05;rough=.8
  if id=='f35' and texture and 'Default' in texture:factor=[x*.6 for x in factor[:3]]+[factor[3]];metal=.08;rough=.65
  if isglass:factor=[.15,.23,.29,1];metal=.65;rough=.12;texture=None
  if id=='a380' and texture is None and factor[:3]==[1,1,1]:factor=[.79,.83,.86,1]
  mat={'name':m['name']+'_'+o['name'],'pbrMetallicRoughness':{'baseColorFactor':factor,'metallicFactor':metal,'roughnessFactor':rough},'doubleSided':True}
  t=tex(texture,o['path'])
  if t is not None:mat['pbrMetallicRoughness']['baseColorTexture']={'index':t}
  if factor[3]<.99:mat['alphaMode']='BLEND'
  ix=len(gltf['materials']);gltf['materials'].append(mat);matmap[key]=ix;return ix
 for o in objects:
  tris=[];sums=[(0,0,0) for _ in o['verts']]
  for f in o['faces']:
   if f['flag']&15:continue # ignore AC3D line primitives
   for k in range(1,len(f['refs'])-1):
    refs=[f['refs'][0],f['refs'][k],f['refs'][k+1]];vs=[o['verts'][r[0]] for r in refs];normal=cross(vsub(vs[1],vs[0]),vsub(vs[2],vs[0]))
    if sum(v*v for v in normal)<1e-16:continue
    for r in refs:sums[r[0]]=vadd(sums[r[0]],normal)
    tris.append((f,refs,unit(normal)))
  groups={}
  for f,refs,n in tris:
   g=groups.setdefault(f['mat'],{'v':[],'n':[],'uv':[]})
   for r in refs:
    g['v'].append(o['verts'][r[0]]);smooth=unit(sums[r[0]])
    g['n'].append(smooth if f['flag']&16 and sum(x*y for x,y in zip(smooth,n))>math.cos(math.radians(o['crease'])) else n);g['uv'].append((r[1],1-r[2]))
  prim=[]
  for mi,g in groups.items():prim.append({'attributes':{'POSITION':accessor(g['v'],'VEC3'),'NORMAL':accessor(g['n'],'VEC3'),'TEXCOORD_0':accessor(g['uv'],'VEC2')},'material':material(o,mi),'mode':4})
  if prim:
   node_idx=len(gltf['nodes'])
   name=o['name'].lower();anc='/'.join(o.get('parents',())).lower()
   isgear=False
   if id=='f35':isgear=Path(o['path']).name=='Gear.ac'
   elif id=='a380':isgear=any(t in name for t in ['tyre','strut','axle','truck','steercyl','linklower','linkupper']) or name=='collar'
   elif id=='b737':isgear=any(t in name for t in ['tyre','strut','axle','steercyl','linklower','linkupper']) or name=='collar'
   elif id=='b747':isgear=any(t in (name+' '+anc) for t in ['gearnose','gearwing','gearbody','gearwheel','gearaxel']) and not any(t in name for t in ['door','well'])
   elif id=='b2':isgear=('tire' in name or 'gear' in name) and not any(t in name for t in ['cover','box'])
   if isgear:gear_nodes.append(node_idx);gear_names.append(o['name'])
   else:gltf['scenes'][0]['nodes'].append(node_idx)
   gltf['nodes'].append({'name':o['name'],'mesh':len(gltf['meshes'])});gltf['meshes'].append({'name':o['name'],'primitives':prim})
  triangles+=len(tris)
 gltf['scenes'][0]['nodes'].append(len(gltf['nodes']));gltf['nodes'].append({'name':'LandingGear','children':gear_nodes})
 while len(binary)%4:binary.append(0)
 gltf['buffers']=[{'byteLength':len(binary)}];rawjson=json.dumps(gltf,separators=(',',':')).encode()
 while len(rawjson)%4:rawjson+=b' '
 total=12+8+len(rawjson)+8+len(binary)
 raw=struct.pack('<III',0x46546c67,2,total)+struct.pack('<II',len(rawjson),0x4e4f534a)+rawjson+struct.pack('<II',len(binary),0x004e4942)+binary
 (out/f'{id}.glb').write_bytes(raw)
 (out/f'{id}.tscn').write_text(f'[gd_scene load_steps=2 format=3]\n\n[ext_resource type="PackedScene" path="res://assets/aircraft/{id}/{id}.glb" id="1"]\n\n[node name="{id.upper()}" type="Node3D"]\n\n[node name="Airframe" parent="." instance=ExtResource("1")]\n')
 bb=bounds([v for o in objects for v in o['verts']]);dimensions=[bb[1][i]-bb[0][i] for i in range(3)]
 manifest={'id':id,'scene':f'res://assets/aircraft/{id}/{id}.tscn','forward':'-Z','up':'+Y','unit':'meter','bounds':bb,'dimensions':{'wingspan':dimensions[0],'height':dimensions[1],'length':dimensions[2]},'triangle_count':triangles,'mesh_count':len(gltf['meshes']),'source_origin_removed':center,'sha256_glb':hashlib.sha256(raw).hexdigest(),'landing_gear':'visual group Airframe/LandingGear, initially extended','gear_mesh_names':gear_names,'conversion':'Static source mesh assembly; FlightGear animation and systems are not imported.'}
 (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps(manifest));return manifest

def main():
 configs={'a380':[],'f35':['Models/F-35B.ac','Models/Engine.ac','Models/Gear.ac'],'b2':['Models/spirit.ac'],'b737':['Models/737-300.ac'],'b747':['Models/boeing747-400-jw.ac']}
 all=[convert(id,fs) for id,fs in configs.items()]
 (ASSETS/'manifest.json').write_text(json.dumps(all,indent=2)+'\n')
if __name__=='__main__':main()
