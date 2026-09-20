"""Original CG-26 rotary cannon. Blender --background --python this_file."""
import bpy, math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
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

def empty(name,parent=None):
    ob=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(ob);ob.parent=parent;return ob
def tube(name,x,y,z0,z1,r,inner,mat,parent):
    ob=lathe(name,[(z0,inner),(z0,r),(z1,r),(z1,inner),(z0,inner)],mat)
    ob.location=(x,0,y);ob.parent=parent;return ob
def box(name,pos,size,mat,parent):
    bpy.ops.mesh.primitive_cube_add(size=1,location=(pos[0],-pos[2],pos[1]));ob=bpy.context.object;ob.name=name
    ob.scale=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    ob.data.materials.append(mat);ob.parent=parent
    bevel=ob.modifiers.new('Machined edges','BEVEL');bevel.width=.035;bevel.segments=3
    ob.modifiers.new('Weighted normals','WEIGHTED_NORMAL');return ob
mount=empty('CG26Mount');gimbal=empty('GunGimbal',mount);rotor=empty('GatlingRotor',gimbal)
box('Shoulder_mount',(0,-.23,.28),(.62,.30,1.05),finmat,mount)
box('Feed_housing',(-.29,.02,.45),(.24,.36,.62),finmat,gimbal)
tube('Receiver',0,0,-.10,.88,.295,.055,finmat,gimbal)
for z in [.0,.72]:tube('Receiver_collar',0,0,z,z+.08,.318,.26,steel,gimbal)
for j in range(12):
    a=j*math.tau/12
    ob=box('Cooling_slot',(math.cos(a)*.297,math.sin(a)*.297,.33),(.030,.028,.38),ink,gimbal)
    ob.rotation_euler[1]=a
for j in range(6):
    a=j*math.tau/6;x=math.cos(a)*.163;y=math.sin(a)*.163
    tube('Hollow_barrel_%s'%j,x,y,-1.72,-.08,.063,.038,steel,rotor)
    tube('Heat_treated_muzzle_%s'%j,x,y,-1.735,-1.53,.067,.038,bodymat,rotor)
for z in [-1.42,-.55]:tube('Rotating_brace',0,0,z,z+.12,.255,.222,finmat,rotor)
tube('Rotor_spindle',0,0,-1.40,-.05,.068,.012,steel,rotor)
tube('Amber_service_band',0,0,.57,.62,.297,.29,amber,gimbal)
marker=empty('GunMuzzle',gimbal);marker.location=(0,1.78,0)
# A few grouped material meshes per animated part keep draw calls bounded.
for parent in [mount,gimbal,rotor]:
    groups={}
    for ob in list(parent.children):
        if ob.type=='MESH':groups.setdefault(ob.data.materials[0].name,[]).append(ob)
    for name,objects in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for ob in objects:
            bpy.context.view_layer.objects.active=ob;ob.select_set(True)
            for mod in list(ob.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
            ob.select_set(False)
        for ob in objects:ob.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        if len(objects)>1:bpy.ops.object.join()
        bpy.context.object.name=parent.name+'_'+name.replace(' ','_')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'docs/source/CG26.blend'))
bpy.ops.export_scene.gltf(filepath=str(ROOT/'simulator/assets/weapons/cg26.glb'),export_format='GLB',export_yup=True,export_apply=True,export_animations=False)
print('CG26_EXPORTED')
