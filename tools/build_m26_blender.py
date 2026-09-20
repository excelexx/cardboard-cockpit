"""Build the original M-26 game missile with Blender 4.5 and export GLB.
Run: Blender --background --factory-startup --python tools/build_m26_blender.py
"""
import bpy, bmesh, math
from pathlib import Path
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[1]
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def material(name, color, metal, rough):
    m=bpy.data.materials.new(name);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    return m
bodymat=material('Satin titanium grey',(.51,.55,.57),.65,.29)
finmat=material('Machined graphite fins',(.065,.085,.10),.72,.28)
seeker=material('Optical ceramic seeker',(.012,.035,.055),.78,.09)
amber=material('Identification band',(.60,.36,.08),.22,.48)
ink=material('Laser etched identification',(.025,.035,.04),.05,.65)
steel=material('Nozzle and fasteners',(.23,.26,.28),.82,.30)
def obj_mesh(name,vertices,faces,mat,smooth=False,bevel=0):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob);ob.data.materials.append(mat)
    for p in mesh.polygons:p.use_smooth=smooth
    if bevel:
        mod=ob.modifiers.new('Precision edge bevel','BEVEL');mod.width=bevel;mod.segments=3
        mod=ob.modifiers.new('Weighted face normals','WEIGHTED_NORMAL');mod.keep_sharp=True;mod.weight=50
    return ob
def lathe(name,profile,mat):
    n=64;verts=[(math.cos(i*math.tau/n)*r,-z,math.sin(i*math.tau/n)*r) for z,r in profile for i in range(n)]
    faces=[]
    for j in range(len(profile)-1):
        for i in range(n):
            a=j*n+i;b=j*n+(i+1)%n;c=(j+1)*n+(i+1)%n;d=(j+1)*n+i;faces.append((a,b,c,d))
    return obj_mesh(name,verts,faces,mat,True)
lathe('M26_ogive_airframe',[(-1.55,.003),(-1.51,.027),(-1.44,.058),(-1.32,.085),(-1.14,.103),(-.94,.110),(1.26,.110),(1.37,.095),(1.44,.075)],bodymat)
lathe('Optical_seeker',[(-1.553,.0035),(-1.51,.029),(-1.44,.060),(-1.32,.087),(-1.26,.094)],seeker)
lathe('Graphite_motor_sleeve',[(.54,.112),(1.25,.112),(1.39,.091)],finmat)
for z in [-.94,.10,.55,1.24]:lathe('Recessed_collar',[(z-.009,.1105),(z,.113),(z+.009,.1105)],finmat)
lathe('Amber_identification',[(-.73,.111),(-.67,.111)],amber)
lathe('Motor_serial_band',[(.64,.114),(.71,.114)],amber)
lathe('Exhaust_ring',[(1.40,.078),(1.45,.079),(1.47,.071),(1.47,.048),(1.43,.047)],steel)
for station in [-.45,.92]:
    for j in range(4):
        reach=.43 if station>.5 else .27
        outline=[(.092,station-.31),(reach,station+.015),(reach,station+.23),(.092,station+.27)]
        verts=[(x,-z,side*.008) for side in [-1,1] for x,z in outline]
        faces=[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
        ob=obj_mesh('Tail_fin' if station>.5 else 'Control_fin',verts,faces,finmat,False,.006)
        ob.rotation_euler[1]=math.pi/4+j*math.pi/2
for station in [.12,1.07]:
    for j in range(8):
        a=j*math.tau/8
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=6,radius=.008,location=(math.cos(a)*.109,-station,math.sin(a)*.109))
        ob=bpy.context.object;ob.name='Countersunk_fastener';ob.scale=(1,.5,1);ob.data.materials.append(steel)
font=bpy.data.curves.new('M26 service stencil','FONT');font.body='M-26 / 041';font.size=.060;font.extrude=.00015;font.align_x='CENTER'
label=bpy.data.objects.new('Service_identification',font);bpy.context.collection.objects.link(label);label.location=(0,0,.111);label.rotation_euler[2]=math.pi/2;label.data.materials.append(ink)
bpy.context.view_layer.objects.active=label;label.select_set(True);bpy.ops.object.convert(target='MESH');label.select_set(False)
# Bake modifiers for predictable game-engine shading and a portable source file.
for ob in list(bpy.context.scene.objects):
    if ob.type!='MESH':continue
    bpy.context.view_layer.objects.active=ob;ob.select_set(True)
    for mod in list(ob.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
    ob.select_set(False)
groups={}
for ob in list(bpy.context.scene.objects):
    if ob.type=='MESH': groups.setdefault(ob.data.materials[0].name,[]).append(ob)
for name,objects in groups.items():
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects: ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    if len(objects)>1: bpy.ops.object.join()
    bpy.context.object.name='M26_'+name.replace(' ','_')
bpy.context.preferences.filepaths.save_version=0
source=ROOT/'docs/source/M26.blend' ;source.parent.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(source))
out=ROOT/'simulator/assets/weapons/m26.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',export_yup=True,export_apply=True,export_animations=False)
print('M26_EXPORTED',out)
