#!/usr/bin/env python3
"""Download public-domain USGS/USDA regional aerial photos and apply source UVs.
The FlightGear terrain geometry is unchanged. Original JPEGs, extents and hashes remain bundled.
"""
from import_sf_region import *
import urllib.parse,concurrent.futures,time
from pyproj.enums import TransformDirection
AERIAL=OUT/'aerial';AERIAL.mkdir(exist_ok=True)
URL='https://imagery.nationalmap.gov/arcgis/rest/services/USGSNAIPImagery/ImageServer/exportImage'
WATER={'Ocean','Lake','Water','Reservoir'}
def geographic(p):
 e=C*p[:,0]-S*p[:,2];n=-S*p[:,0]-C*p[:,2]
 return np.array(PROJ.transform(e,n,direction=TransformDirection.INVERSE)).T

def fetch(url):
 for attempt in range(3):
  try:return urllib.request.urlopen(url,timeout=90).read()
  except (TimeoutError,OSError):
   if attempt==2:raise
   time.sleep(1+attempt)

def convert(path):
 name=path.name.split('.')[0];photo=AERIAL/(name+'.jpg');metadata=AERIAL/(name+'.json')
 parts=btg(path);groups=defaultdict(lambda:[[],[]])
 for mat,p,uv in parts:groups[mat][0].append(p);groups[mat][1].append(uv)
 if not any(k not in WATER for k in groups):return None
 allv=np.concatenate([np.concatenate(a[0]) for a in groups.values()]);ll=geographic(allv);lo=ll.min(axis=0);hi=ll.max(axis=0)
 bounds=[round(lo[0]*4)/4,round(lo[1]*8)/8,round(hi[0]*4)/4,round(hi[1]*8)/8]
 if not photo.exists():
  params=dict(f='json',bbox=','.join(map(str,bounds)),bboxSR=4326,imageSR=4326,size='4000,2000',format='jpg',pixelType='U8',interpolation='RSP_BilinearInterpolation',compressionQuality=92)
  request=URL+'?'+urllib.parse.urlencode(params);j=json.loads(fetch(request))
  if 'href' not in j:raise RuntimeError(j)
  photo.write_bytes(fetch(j['href']));j['request']=request;j['copyright']='USGS, USDA, The National Map: Orthoimagery';j['license']='Public domain';j['sha256']=hashlib.sha256(photo.read_bytes()).hexdigest();metadata.write_text(json.dumps(j,indent=2))
 j=json.loads(metadata.read_text());ex=j['extent'];west,south,east,north=ex['xmin'],ex['ymin'],ex['xmax'],ex['ymax']
 model=GLTF()
 for mat,(ps,us) in groups.items():
  p=np.concatenate(ps);uv=np.concatenate(us)
  if mat in WATER:
   uv[:,1]=1-uv[:,1];model.add(p,uv,None,(.055,.15,.20),True)
  else:
   ll=geographic(p);uv=np.stack([(ll[:,0]-west)/(east-west),(north-ll[:,1])/(north-south)],axis=-1)
   model.add(p,uv,'aerial/'+photo.name)
 model.save('terrain_'+name);print('AERIAL',name,photo.stat().st_size,flush=True)
 return dict(tile=name,extent=ex,sha256=j['sha256'],source=j['request'])
if __name__=='__main__':
 files=[p for p in sorted((SRC/'terrain').glob('*.btg.gz')) if p.name[0].isdigit() and p.name.split('.')[0].isdigit()]
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:rows=list(ex.map(convert,files))
 (AERIAL/'manifest.json').write_text(json.dumps([r for r in rows if r],indent=2));print('AERIAL TILES',sum(r is not None for r in rows))
