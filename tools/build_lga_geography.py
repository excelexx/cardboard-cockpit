"""Create a compact, offline NYC scene from municipal footprints and OSM geometry.
Install shapely in a temporary venv to run. Source responses are cached in /tmp.
NYC Open Data: borough shorelines + building footprints. OSM: roads/airport/parks.
"""
import json, math, time
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.parse import urlencode
from shapely.geometry import shape, box, Polygon, LineString
from shapely.ops import transform, triangulate

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"simulator/assets/lga"
CACHE=Path("/tmp/cardboard-lga-geodata")
CACHE.mkdir(exist_ok=True)
OUT.mkdir(parents=True,exist_ok=True)
WEST,SOUTH,EAST,NORTH=-74.03,40.705,-73.80,40.85

def fetch(name,url,data=None):
    path=CACHE/name
    if path.exists(): return json.loads(path.read_text())
    print("Fetching",name,flush=True)
    request=Request(url,data=data,headers={"User-Agent":"CardboardCockpitGeography/1.0"})
    with urlopen(request,timeout=180) as response: result=json.load(response)
    path.write_text(json.dumps(result))
    return result

shore=fetch("shore.json","https://data.cityofnewyork.us/resource/gthc-hcne.json?$limit=5")
query='[out:json][timeout:120];(way["aeroway"](40.765,-73.90,40.80,-73.85);way["highway"~"^(motorway|trunk|primary|secondary|tertiary|residential)$"](%s,%s,%s,%s);way["leisure"="park"](%s,%s,%s,%s););out tags geom;'%(SOUTH,WEST,NORTH,EAST,SOUTH,WEST,NORTH,EAST)
osm=fetch("osm.json","https://overpass-api.de/api/interpreter",urlencode({"data":query}).encode())
runways=[e for e in osm["elements"] if e.get("tags",{}).get("aeroway")=="runway"]
print("Runways",[(r["tags"],len(r["geometry"])) for r in runways],flush=True)
runway=next(r for r in runways if "31" in r["tags"].get("ref",""))
ends=runway["geometry"]
lat0=sum(p["lat"] for p in [ends[0],ends[-1]])/2
lon0=sum(p["lon"] for p in [ends[0],ends[-1]])/2
kx=111320*math.cos(math.radians(lat0)); ky=111320
raw=lambda p: ((p[0]-lon0)*kx,(p[1]-lat0)*ky)
nw=max([ends[0],ends[-1]],key=lambda p:p["lat"])
ex,ny=raw((nw["lon"],nw["lat"]))
length=math.hypot(ex,ny); fx,fn=ex/length,ny/length
def project(x,y,z=None):
    e,n=(x-lon0)*kx,(y-lat0)*ky
    return (e*fn-n*fx,-(e*fx+n*fn))
def coords(points): return [[round(v,2) for v in project(*p)] for p in points]
clip=box(WEST,SOUTH,EAST,NORTH)
result={"source":"NYC DCP/OTI + OpenStreetMap contributors","origin":[lon0,lat0],"north_rotation":[fx,fn],"land":[],"buildings":[],"roads":[],"parks":[],"airport":[]}
for record in shore:
    geom=shape(record["the_geom"]).intersection(clip)
    if geom.is_empty: continue
    projected=transform(project,geom).simplify(7,preserve_topology=True)
    for poly in getattr(projected,"geoms",[projected]):
        if poly.area<100: continue
        # Bake triangulation; this preserves islands and excludes water/holes.
        triangles=[]
        for triangle in triangulate(poly):
            if poly.covers(triangle.representative_point()):
                triangles.extend([[round(x,2),round(y,2)] for x,y in list(triangle.exterior.coords)[:3]])
        result["land"].append({"name":record["boroname"],"outline":[[round(x,2),round(y,2)] for x,y in poly.exterior.coords],"triangles":triangles})
for e in osm["elements"]:
    tags=e.get("tags",{}); points=[(p["lon"],p["lat"]) for p in e.get("geometry",[])]
    if len(points)<2: continue
    line=transform(project,LineString(points)).simplify(3)
    item={"points":[[round(x,2),round(y,2)] for x,y in line.coords],"kind":tags.get("highway",tags.get("aeroway","park")),"name":tags.get("name",tags.get("ref","")),"bridge":tags.get("bridge","no")!="no"}
    if "aeroway" in tags: result["airport"].append(item)
    elif "highway" in tags: result["roads"].append(item)
    elif len(points)>3: result["parks"].append(item)
params={"$select":"the_geom,height_roof,ground_elevation,bin","$where":f"within_box(the_geom,{NORTH},{WEST},{SOUTH},{EAST})","$limit":"100000","$order":"height_roof DESC"}
buildings=fetch("buildings.json","https://data.cityofnewyork.us/resource/5zhs-2jue.json?"+urlencode(params))
for row in buildings:
    geom=transform(project,shape(row["the_geom"])).simplify(0.8,preserve_topology=True)
    for poly in getattr(geom,"geoms",[geom]):
        if poly.area<35: continue
        points=list(poly.exterior.coords)[:-1]
        if len(points)>55: poly=poly.simplify(2); points=list(poly.exterior.coords)[:-1]
        height=max(4,float(row.get("height_roof") or 20)*0.3048)
        result["buildings"].append({"p":[[round(x,1),round(y,1)] for x,y in points],"h":round(height,1),"id":row["bin"]})
print("Counts",{k:len(result[k]) for k in ("land","roads","parks","airport","buildings")},flush=True)
(OUT/"nyc.json").write_text(json.dumps(result,separators=(",",":")))
print("Projection",result["origin"],result["north_rotation"],flush=True)
for name,lon,lat in [("Whitestone",-73.8306,40.8010),("Rikers",-73.884,40.791),("Hell Gate",-73.921,40.786),("Midtown",-73.974,40.754),("Queensboro",-73.954,40.756),("Citi Field",-73.8458,40.7571),("Flushing Bay",-73.853,40.781),("Empire State",-73.9857,40.7484),("Central Park",-73.968,40.781)]:
    print(name,coords([(lon,lat)])[0],flush=True)
