"""Bind the existing moving campus silhouettes to a compact walking rig."""
import json
import struct
from pathlib import Path
import numpy as np
from student_cast import GLB, ROOT, quaternion
from student_motion import pose

BASE = ROOT/"assets/campus"
MODELS = {"person":BASE/"figures/person.glb","teacher":BASE/"figures/teacher.glb",
          "tall":BASE/"figures/tall.glb","patroller":BASE/"patrol/patrol_figure.glb"}

def build(path,target):
    raw=path.read_bytes()
    length=struct.unpack_from("<I",raw,12)[0]
    out=GLB()
    out.doc=json.loads(raw[20:20+length])
    out.binary=bytearray(raw[28+length:])
    doc=out.doc
    def positions(prim):
        acc=doc["accessors"][prim["attributes"]["POSITION"]]
        view=doc["bufferViews"][acc["bufferView"]]
        return np.ndarray((acc["count"],3),dtype="<f4",buffer=out.binary,
                          offset=view.get("byteOffset",0)+acc.get("byteOffset",0),
                          strides=(view.get("byteStride",12),4)).copy()
    primitives=[(p,positions(p)) for m in doc["meshes"] for p in m["primitives"]]
    all_pos=np.concatenate([v for p,v in primitives])
    h=all_pos[:,1].max()
    width=.27*(h/1.85)**.42
    names=["Hips"]
    pivots=[(0,.48*h,0)]
    parents=[None]
    for suffix,sign in (("L",1),("R",-1)):
        for n,parent,x,y in [("Thigh","Hips",.34,.48),("Knee","Thigh"+suffix,.35,.25),
                             ("Arm","Hips",.72,.79),("Elbow","Arm"+suffix,.83,.61)]:
            names.append(n+suffix)
            pivots.append((sign*width*x,h*y,0))
            parents.append(parent)
    offset=len(doc["nodes"])
    root=doc["scenes"][doc.get("scene",0)]["nodes"][0]
    doc["nodes"][root].setdefault("children",[]).append(offset)
    for i,(name,parent) in enumerate(zip(names,parents)):
        p=np.array(pivots[i],dtype=float)
        if parent: p-=pivots[names.index(parent)]
        children=[offset+j for j,pn in enumerate(parents) if pn==name]
        node={"name":name,"translation":p.tolist()}
        if children: node["children"]=children
        doc["nodes"].append(node)
    for n in doc["nodes"]:
        if "mesh" in n: n["skin"]=0
    matrices=[]
    for p in pivots:
        m=np.eye(4); m[:3,3]=-np.asarray(p); matrices.append(m.T.flatten())
    doc["skins"]=[{"joints":list(range(offset,offset+len(names))),"inverseBindMatrices":out.array(matrices,"MAT4")}]
    for prim,values in primitives:
        joints=[]; weights=[]
        for x,y,z in values:
            side="L" if x>=0 else "R"
            level=y/h
            if level<.51:
                parent,child,centre=("Thigh"+side,"Knee"+side,.25) if level<.43 else ("Hips","Thigh"+side,.48)
            elif abs(x)>width*.60 and level<.83:
                parent,child,centre=("Arm"+side,"Elbow"+side,.61) if level<.72 else ("Hips","Arm"+side,.79)
            else:
                parent=child="Hips"; centre=0
            amount=np.clip(.5+(centre-level)/.085,0,1)
            joints.append([names.index(parent),names.index(child),0,0]); weights.append([1-amount,amount,0,0])
        prim["attributes"]["JOINTS_0"]=out.array(joints,"VEC4","B")
        prim["attributes"]["WEIGHTS_0"]=out.array(weights,"VEC4")
    doc["animations"]=[]
    for action in ("walk","idle"):
        phase=np.linspace(0,1,17)
        time=out.array(phase,"SCALAR",bounds=True)
        channels=[]; samplers=[]
        for i,name in enumerate(names):
            values=[]
            for t in phase:
                _,rot=pose(action,t)
                x,y,z=rot.get(name,(0,0,0)) if action=="walk" else (0,0,0)
                values.append(quaternion((-x,y,z)))
            channels.append({"sampler":i,"target":{"node":offset+i,"path":"rotation"}})
            samplers.append({"input":time,"output":out.array(values,"VEC4")})
        doc["animations"].append({"name":action+"_loop","samplers":samplers,"channels":channels})
    out.save(target)

if __name__=="__main__":
    out=BASE/"figures/motion"
    out.mkdir(exist_ok=True)
    for name,path in MODELS.items(): build(path,out/(name+".glb"))
