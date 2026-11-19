#!/usr/bin/env python3
"""Build the four original, vertex-painted, single-surface skinned campus students."""
import argparse
import hashlib
import json
import struct
import urllib.request
from math import cos, exp, pi, sin, tanh
from pathlib import Path

import numpy as np

from student_motion import CLIPS, ONE_SHOTS, pose

ROOT = Path(__file__).resolve().parents[2]
SOURCE = "https://raw.githubusercontent.com/makehumancommunity/makehuman/a8bc2d54ff0ac92e78ff71431b1023eda42bf482/makehuman/data/3dobjs/base.obj"
SHA256 = "8e761e6624b8f54536409135d1636da63b32486a90d4897f84e121d144f6fb4c"
# jacket, sleeves, trim, trousers, leather, hair, complexion, shoulder, jaw
CAST = {
    "lin": ("294b69", "304f69", "c9ab77", "414850", "6b4a3b", "302728", "d9a78c", 1.03, 1.00),
    "qiao": ("ac3a43", "efe2cb", "f4cb80", "283950", "f2e8d6", "282326", "c28d73", 0.94, 0.93),
    "shen": ("536955", "cbc2a8", "d5bc82", "444950", "604b3a", "252326", "dbad91", 1.10, 1.08),
    "xu": ("ae7848", "c98e5d", "eee3bb", "444652", "473b35", "493134", "e0af98", 0.91, 0.91),
    "teacher": ("47515a", "47515a", "8c8577", "343b45", "3d322e", "514b49", "c99e84", 1.10, 1.12),
}
SKIRT_PANELS = 12
SKIRT_RINGS = (("Lap",.824,.199,.150),("Rim",.621,.241,.171),("Hem",.548,.252,.178))
TAU = 2 * pi


def color(hex_value):
    a = np.array(list(bytes.fromhex(hex_value))) / 255.0
    return np.where(a <= .04045, a / 12.92, ((a + .055) / 1.055)**2.4)


def unit(v):
    v = np.asarray(v, float)
    return v / max(1e-9, np.linalg.norm(v))


def quaternion(euler):
    x, y, z = np.radians(euler) / 2
    sx, sy, sz = sin(x), sin(y), sin(z)
    cx, cy, cz = cos(x), cos(y), cos(z)
    return [sx*cy*cz-cx*sy*sz, cx*sy*cz+sx*cy*sz, cx*cy*sz-sx*sy*cz, cx*cy*cz+sx*sy*sz]


def skeleton(shoulder, skirt=False):
    bones = {}

    def add(name, parent, x, y, z=0):
        bones[name] = (parent, np.array([x, y, z]))

    add("Hips", None, 0, .905)
    add("Spine", "Hips", 0, 1.045)
    add("Chest", "Spine", 0, 1.25)
    add("Neck", "Chest", 0, 1.462)
    add("Head", "Neck", 0, 1.514)
    for side, s in (("L", 1), ("R", -1)):
        def limb(name, parent, x, y, z=0):
            add(name + side, parent, s*x, y, z)
        limb("Clavicle", "Chest", .068, 1.40)
        limb("Arm", "Clavicle"+side, .185 * shoulder, 1.393)
        limb("Elbow", "Arm"+side, .25 * shoulder, 1.126, .004)
        limb("Hand", "Elbow"+side, .264 * shoulder, .891, -.025)
        limb("Fingers", "Hand"+side, .269 * shoulder, .814, -.035)
        limb("Thigh", "Hips", .097, .890)
        limb("Knee", "Thigh"+side, .103, .488, -.014)
        limb("Foot", "Knee"+side, .110, .107, .004)
        limb("Toe", "Foot"+side, .111, .050, -.12)
    if skirt:
        for i in range(SKIRT_PANELS):
            a = TAU * i / SKIRT_PANELS
            for label, y, rx, rz in SKIRT_RINGS:
                add(f"{label}{i:02}", "Hips", rx*sin(a), y, -rz*cos(a))
    return bones


class Mesh:
    def __init__(self, bones):
        self.bones = bones
        self.names = list(bones)
        self.vertices, self.colors, self.joints, self.weights, self.tris = [], [], [], [], []

    def vertex(self, p, c, bone):
        if isinstance(c, str):
            c = color(c)
        if isinstance(bone, str):
            bone = [(bone, 1)]
        joints = [self.names.index(name) for name, w in bone]
        weights = [w for name, w in bone]
        idx = len(self.vertices)
        self.vertices.append(p)
        self.colors.append(c)
        self.joints.append((joints+[0]*4)[:4])
        self.weights.append((weights+[0]*4)[:4])
        return idx

    def rings(self, rows, c, bone, sides=24, paint=None):
        """Rows ascend in y. Each carries centre, x/z radii and an optional binding."""
        rings = []
        for i, row in enumerate(rows):
            x, y, z, rx, rz = row[:5]
            ring = []
            for j in range(sides):
                angle = TAU*j/sides
                tint = paint(i, angle) if paint else c
                ring.append(self.vertex((x+rx*sin(angle), y, z-rz*cos(angle)), tint,
                                        row[5] if len(row)>5 else bone))
            rings.append(ring)
        for lower, upper in zip(rings, rings[1:]):
            for j in range(sides):
                k = (j+1) % sides
                self.tris.extend(((lower[j], upper[j], lower[k]), (lower[k], upper[j], upper[k])))
        for ring, upper in ((rings[0], False), (rings[-1], True)):
            for j in range(1, sides-1):
                self.tris.append((ring[0], ring[j+1], ring[j]) if upper else (ring[0], ring[j], ring[j+1]))

    def oval(self, center, radii, c, bone, sides=16, levels=8):
        x, y, z = center
        rx, ry, rz = radii
        rows = []
        for i in range(levels+1):
            a = -pi/2 + pi*i/levels
            rows.append((x, y+ry*sin(a), z, rx*max(.002,cos(a)), rz*max(.002,cos(a))))
        self.rings(rows,c,bone,sides)

    def tube(self, points, radius, c, bone, sides=7):
        rings = []
        for i, point in enumerate(points):
            tangent = unit(np.array(points[min(i+1,len(points)-1)]) - points[max(0,i-1)])
            base = unit(np.cross(tangent, (0,0,1) if abs(tangent[2]) < .9 else (1,0,0)))
            other = unit(np.cross(tangent,base))
            r = radius[i] if isinstance(radius,list) else radius
            rings.append([self.vertex(point+r*(cos(TAU*j/sides)*base+sin(TAU*j/sides)*other),c,bone)
                          for j in range(sides)])
        for a,b in zip(rings,rings[1:]):
            for j in range(sides):
                k=(j+1)%sides
                self.tris.extend(((a[j],a[k],b[j]),(a[k],b[k],b[j])))

    def patch(self, points, c, bone):
        # Front-facing cloth and hardware; emit the polygon in either winding.
        verts = [self.vertex(p,c,bone) for p in points]
        reverse = np.cross(np.subtract(points[1],points[0]),np.subtract(points[2],points[0]))[2] > 0
        for i in range(1,len(verts)-1):
            self.tris.append((verts[0],verts[i+1],verts[i]) if reverse else (verts[0],verts[i],verts[i+1]))


def anatomy(path):
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(urllib.request.urlopen(SOURCE, timeout=45).read())
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != SHA256:
        raise ValueError("Unexpected HM08 OBJ checksum")
    vertices, faces = [], []
    group = ""
    for line in raw.decode().splitlines():
        row = line.split()
        if not row:
            continue
        if row[0] == "v": vertices.append([float(x) for x in row[1:4]])
        elif row[0] == "g": group = row[1]
        elif row[0] == "f" and group == "body": faces.append([int(x.split("/")[0])-1 for x in row[1:]])
    return np.array(vertices), faces


def face_and_hands(mesh, role, source):
    _, _, _, _, _, hair, skin, _, jaw = CAST[role]
    vertices, faces = source
    skin = color(skin)
    scale = .105
    def head(x,y,z):
        width = 1 + (jaw-1) * (.35 + .65 * exp(-((y-6.5)/.65)**2))
        cheek=exp(-((y-6.98)/.36)**2-((abs(x)-.47)/.31)**2)
        nose=exp(-((y-6.98)/.28)**2-(x/.22)**2) if z>1.25 else 0
        width*=1+{"lin":-.035,"qiao":.075,"shen":.0,"xu":.12,"teacher":-.06}[role]*cheek
        z+=nose*{"lin":.04,"qiao":-.09,"shen":.105,"xu":-.12,"teacher":.075}[role]
        height={"lin":1.01,"qiao":.97,"shen":1.015,"xu":.95,"teacher":1.04}[role]
        return np.array([-x*scale*width, 1.47+(y-5.89)*scale*height, -(z-.42)*scale])
    face_points = vertices[np.unique(np.concatenate([f for f in faces if min(vertices[f,1])>5.53]))]
    def forehead(x,y):
        dist = (face_points[:,0]-x)**2+(face_points[:,1]-y)**2
        close = face_points[(dist < (.075**2)) & (face_points[:,2] > .9)]
        return max(close[:,2],default=1.49-.35*x*x)

    selected = {}
    for indices in faces:
        coords=vertices[indices]
        if coords[:,1].min()>5.80 and max(abs(coords[:,0])) < 1.15:
            part = "Head"
        elif min(abs(coords[:,0]))>3.86 and coords[:,1].max()<2.72:
            part = "HandR" if coords[0,0]>0 else "HandL"
        else:
            continue
        polygon = []
        for idx in indices:
            if idx not in selected:
                x,y,z=vertices[idx]
                c=skin.copy()
                bone=part
                if part == "Head":
                    p = head(x,y,z)
                    if y < 6.13:
                        f=np.clip((y-5.70)/.43,0,1)
                        bone=[("Head",f),("Neck",1-f)]
                    if z>1.35 and abs(x)<.28:
                        # Pigment follows the lips around the anatomical mouth seam.
                        lip=exp(-((y-6.584)/.078)**2-(abs(x)/.245)**4)
                        c=c*(1-.58*lip)+color("a95e5b")*.58*lip
                    if z>1 and abs(x)<.62:
                        socket=exp(-((abs(x)-.31)/.22)**2-((y-7.26)/.113)**2)
                        c*=1-.28*socket
                    if z>.9:
                        blush=.14*exp(-((abs(x)-.49)/.25)**2-((y-6.97)/.22)**2)
                        c=c*(1-blush)+color("c58277")*blush
                else:
                    s=1 if part=="HandL" else -1
                    hand=mesh.bones[part][1]
                    # Rotate the open base-mesh wrist into the arm's resting orientation.
                    v=np.array([(abs(x)-4.31)*s,(y-2.45),-(z-1.76)])*.087
                    axis=unit(np.array([.47*s,-1.15,-1.25]))
                    dest=unit(np.array([.08*s,-1,-.08]))
                    k=np.cross(axis,dest)
                    p=hand+v+np.cross(k,v)+np.cross(k,np.cross(k,v))/(1+axis.dot(dest))
                    blend=np.clip((hand[1]-.055-p[1])/.047,0,1)
                    bone=[(part,1-blend),("Fingers"+part[-1],blend)]
                selected[idx]=mesh.vertex(p,c,bone)
            polygon.append(selected[idx])
        for i in range(1,len(polygon)-1):
            mesh.tris.append((polygon[0],polygon[i],polygon[i+1]))

    # The cropped anatomical neck continues into the collar even when the head turns.
    mesh.rings([(0,1.419,.012,.066,.062),(0,1.459,.004,.061,.060),
                (0,1.501,-.004,.053,.055),(0,1.531,-.009,.047,.048)],
               skin,"Neck",30)
    for s in (1,-1):
        x, y, z = .310*s, 7.285, 1.265
        eye=head(x,y,z)
        mesh.oval(eye,(.0154,.014,.0160),"c5bdb0","Head",22,12)
        # Iris and pupil remain inside the modelled eyelid aperture.
        iris=eye+np.array([0,0,-.0151])
        mesh.oval(iris,(.0076,.0077,.00135),"503a30","Head",20)
        mesh.oval(iris+[0,0,-.001],(.0043,.00435,.0008),"211e20","Head")
        mesh.oval(iris+[-.0016,.0022,-.0017],(.0012,.0011,.00055),"f4eadd","Head",8,4)
        pts=[]
        for t in np.linspace(0,1,8):
            bx=s*(.118+.425*t)
            by=7.455+(.056 if role in ("lin","shen") else .085)*sin(pi*t)-.046*t
            pts.append(head(bx,by,forehead(bx,by)+.022))
        mesh.tube(pts,[.0017,.0032,.0039,.0041,.0038,.0032,.0024,.0010],hair,"Head",7)

    # A sculpted cap with swept ribbons and separate locks, ponytail or bob.
    def scalp(a,t):
        front=(1+cos(a))*.5
        edge=6.75+1.03*front**3+.055*sin(3*a+.45)
        if role=="lin": edge+=.23*sin(a+.12)*front
        if role=="qiao": edge=6.95+1.04*front**2
        if role in ("shen","teacher"): edge=7.08+.61*front**2+.065*sin(6*a)
        if role=="xu":
            edge=5.51+2.23*np.clip((front-.52)/.40,0,1)**1.3+.18*sin(a)*front**3
        bot=np.arcsin(np.clip((edge-7.47)/1.11,-.98,.95))
        lat=bot+(pi/2-bot)*t
        volume=1+.032*sin(a*9+1.7*t)*(1-t)
        radius=cos(lat)
        if role=="xu" and edge<7.0: radius=max(radius,.87*(1-t))
        y=7.47+1.11*sin(lat)
        if role=="xu":
            y=edge+(8.59-edge)*sin(t*pi*.5)
            radius=max(.89*(1-t**2),np.sqrt(max(0,1-((y-7.52)/1.09)**2)))
        if role=="shen": volume+=.055+.038*sin(7*a+6*t)
        return head((.90 if role=="xu" else .84)*radius*sin(a)*volume,y,.55+1.065*radius*cos(a)*volume)
    rings=[]
    for t in np.linspace(0,.999,16):
        ring=[]
        for j in range(56):
            a=j*TAU/56
            tint=color(hair)*(1+.13*sin(a*9+1.7*t))
            ring.append(mesh.vertex(scalp(a,t),tint,"Head"))
        rings.append(ring)
    for low,up in zip(rings,rings[1:]):
        for j in range(56):
            k=(j+1)%56
            mesh.tris.extend(((low[j],low[k],up[j]),(low[k],up[k],up[j])))
    rng=np.random.default_rng(list(CAST).index(role)+12)
    for j in range(34):
        a=j*TAU/34
        sweep=.66 if role in ("lin","xu") else .32
        change=(1 if role!="shen" else -1)*sweep
        curve=[]
        for t in np.linspace(.02,.85,9):
            p=scalp(a+change*t,t)
            p+=unit(p-head(0,7.5,.55))*.0012
            curve.append(p)
        mesh.tube(curve,[.00045+.0017*sin(i*pi/8)**.6 for i in range(9)],color(hair)*rng.uniform(1.12,1.45),"Head",5)
    for j in range(0 if role=="qiao" else 7):
        a=-1.16+j*.28
        p=scalp(a,0)
        length=(.016+.026*(1+sin(j*.9))/2) * (.48 if role in ("qiao","shen") else 1)
        q=p+[.022 if role!="shen" else -.010,-length,-.001]
        mesh.tube([scalp(a+.12,.19),p,q],[.007,.007,.0003],color(hair)*(1+.06*j),"Head",8)
    if role=="teacher":
        for s in (-1, 1):
            for j in range(8):
                a = s*(1.15 + .10*j)
                strand = [scalp(a+.16*t, t) for t in np.linspace(.04,.54,7)]
                mesh.tube(strand,.0016,"978e83","Head",5)
    if role=="qiao":
        p=head(.07,8.05,-.29)
        mesh.oval(p+[0,.028,-.003],(.043,.04,.046),hair,"Head")
        mesh.oval(p+[0,.014,.035],(.029,.025,.025),"ae4846","Head")
        mesh.tube([p+[0,.022,.033],p+[.01,-.013,.065],p+[.055,-.044,.091],p+[.081,-.139,.089],p+[.074,-.225,.063]],
                  [.024,.043,.040,.030,.007],hair,"Head",17)
    if role=="xu":
        for s in (-1,1):
            p=head(s*.76,7.46,.89)
            mesh.tube([p+[0,.044,0],p,p+[s*.006,-.069,-.010],p+[-s*.009,-.144,-.021],p+[-s*.023,-.18,-.007]],
                      [.009,.018,.021,.014,.0015],hair,"Head",16)
    if role=="shen":
        for j in range(10):
            a=j*TAU/10
            p=scalp(a,.59+.09*sin(2*a))
            mesh.oval(p,(.022,.016,.020),color(hair)*(1.08+.10*sin(a)), "Head",14)
    if role in ("shen","teacher"):
        for s in (-1,1):
            ring=[head(s*(.317+.241*cos(a)),7.282+.175*sin(a),1.52-.10*cos(a)) for a in np.linspace(0,TAU,26)]
            mesh.tube(ring,.00195,"493e35","Head")
            mesh.tube([head(s*.54,7.31,1.44),head(s*.74,7.35,.91),head(s*.75,7.29,.42)],.00175,"4a413b","Head")
        mesh.tube([head(-.085,7.31,1.55),head(0,7.345,1.565),head(.085,7.31,1.55)],.00195,"6e5845","Head")


def outfit(m, role, classroom=False):
    coat,sleeve,trim,pants,shoe,hair,skin,width,jaw=CAST[role]
    if classroom:
        coat,sleeve,trim,pants = "506780","d5d9d5","a7b9cc","414858"
    w=lambda x:x*width
    chest="Chest"
    def trunk(rows,c,paint=None):
        m.rings([(0,y,z,w(x),rz,b) for y,x,rz,z,b in rows],c,chest,32,paint)
    if role == "xu":
        trunk([(.823,.146,.092,0,"Hips"),(.898,.157,.113,0,"Hips"),(.962,.149,.105,0,"Hips")],"393e4b")
    else:
        trunk([(.849,.155,.105,.004,"Hips"),(.895,.177,.13,.004,"Hips"),(.976,.166,.121,0,"Spine")],pants)
    rows=[(.936,.170,.127,0,"Hips"),(.954,.177,.13,0,[("Hips",.67),("Spine",.33)]),
          (1.032,.166,.114,0,"Spine"),(1.14,.167,.118,-.004,[("Spine",.6),(chest,.4)]),
          (1.24,.180,.128,-.004,chest),(1.335,.191,.121,0,chest),(1.393,.192,.103,0,chest),
          (1.428,.145,.091,.002,chest),(1.463,.068,.064,0,"Neck")]
    trunk(rows,coat,lambda i,a: color(trim if role=="qiao" and i>=6 else coat)*(.94+.06*cos(a*3)))
    trunk([(.94,.176,.131,0,"Hips"),(.957,.177,.131,0,"Hips")],coat)
    # Shirt front, folded collars, placket, stitched breast pockets and campus badge.
    def shell(x,y,extra=.003):
        levels=np.array([r[:4] for r in rows])
        rx=np.interp(y,levels[:,0],levels[:,1])*width
        rz=np.interp(y,levels[:,0],levels[:,2])
        z=np.interp(y,levels[:,0],levels[:,3])
        return [x,y,z-rz*np.sqrt(max(.001,1-(x/rx)**2))-extra]
    def textile(edges,c):
        ribbons=[]
        for y,left,right in edges:
            ribbons.append([shell(x,y,.004) for x in np.linspace(left,right,7)])
        for low,up in zip(ribbons,ribbons[1:]):
            for j in range(6): m.patch([low[j],low[j+1],up[j+1],up[j]],c,chest)
    if role=="qiao":
        trunk([(1.417,.105,.085,0,chest),(1.443,.083,.075,0,chest),(1.466,.072,.064,0,"Neck")],coat)
        for s in (-1,1):
            m.tube([shell(0,1.340,.008),shell(s*.075,1.366,.008),shell(s*.155,1.392,.008)],.0052,sleeve,chest)
    else:
        textile([(1.337,-.003,.003),(1.356,-.024,.024),(1.381,-.039,.039),(1.413,-.046,.046),
                 (1.44,-.05,.05),(1.461,-.049,.049)],"d6cbb4" if role=="shen" else "d2dce1" if role=="lin" else "e4d9c4")
    for s in (-1,1):
        if role!="qiao":
            collar=[shell(s*x,y,.011) for x,y in [(.056,1.461),(.100,1.427),(.057,1.361),(.015,1.409)]]
            m.patch(collar, color(coat)*.73 if role!="shen" else "8e866e",chest)
            m.tube(collar[:3],.0016,trim,chest)
        if role in ("lin","shen"):
            pocket=[shell(s*x,y,.008) for x,y in [(.042,1.296),(.128,1.296),(.125,1.220),(.073,1.203),(.042,1.221)]]
            m.patch(pocket,color(coat)*.77,chest)
            flap=[shell(s*x,y,.012) for x,y in [(.041,1.303),(.13,1.303),(.124,1.281),(.079,1.271),(.042,1.281)]]
            m.patch(flap,color(coat)*1.14,chest)
            m.tube(flap[2:],.0015,trim,chest)
            m.oval(shell(s*.084,1.283,.016),(.0035,.0035,.0019),"c1af87",chest,8)
    # Panel seams follow the curved fabric, including the dropped shoulder and waist.
    for s in (-1,1):
        m.tube([shell(s*.108,1.414,.004),shell(s*.145,1.36,.004),shell(s*.147,1.31,.004)],
               .0018,color(coat)*.60,chest)
        m.tube([shell(s*.118,1.105,.005),shell(s*.102,1.084,.005),shell(s*.074,1.043,.005)],
               .004,color(coat)*.52,"Spine")
        m.tube([shell(s*.118,1.111,.005),shell(s*.102,1.09,.005),shell(s*.074,1.050,.005)],
               .0016,color(coat)*1.38,"Spine")
    m.tube([shell(0,y,.007) for y in [.951,1.033,1.14,1.24,1.338,1.43] if y<=1.34 or role=="qiao"],
           .0022,"9f9988","Spine")
    m.oval(shell(.106,1.337,.011),(.014,.017,.004),trim,chest,12)
    m.patch([shell(x,y,.018) for x,y in [(.098,1.339),(.113,1.341),(.105,1.329)]],coat,chest)
    for side,s in (("L",1),("R",-1)):
        arm,elbow,hand="Arm"+side,"Elbow"+side,"Hand"+side
        thigh,knee,foot="Thigh"+side,"Knee"+side,"Foot"+side
        mix=[(elbow,.48),(arm,.52)]
        rows=[(.893,.264,.044,.043,-.025,elbow),(.919,.266,.051,.052,-.022,elbow),(.995,.259,.063,.064,-.014,elbow),
              (1.108,.251,.064,.067,0,mix),(1.153,.246,.069,.071,0,mix),
              (1.274,.218,.074,.076,0,arm),(1.352,.192,.084,.087,0,arm),(1.393,.177,.078,.078,0,arm),(1.426,.172,.036,.039,0,arm)]
        def sleeve_color(i,a):
            stripe=(role=="qiao" and abs(sin(a)-s)<.12) or (role=="xu" and i in [1,6])
            return color(trim if stripe else coat if role=="shen" and i>=6 else sleeve)*(.94+.06*cos(a))
        m.rings([(s*w(x),y,z,rx,rz,b) for y,x,rx,rz,z,b in rows],sleeve,arm,22,sleeve_color)
        m.rings([(s*w(.264),.887,-.025,.045,.044),(s*w(.265),.913,-.022,.046,.044)],coat,elbow,20)
        leg=[(.122,.111,.053,.059,.006,knee),(.146,.111,.061,.068,.005,knee),(.277,.111,.067,.078,.012,knee),
             (.43,.104,.076,.086,0,knee),(.487,.103,.072,.078,-.012,[(thigh,.50),(knee,.50)]),
             (.54,.105,.081,.091,-.007,thigh),(.718,.100,.093,.102,0,thigh),(.865,.09,.099,.113,0,thigh),(.937,.085,.088,.11,0,"Hips")]
        if role=="xu":
            # Opaque tights and fitted undershorts leave room for the outer garment.
            m.rings([(s*x,y,z,rx*.78,rz*.76,b) for y,x,rx,rz,z,b in leg],"373b47",thigh,22,
                    lambda i,a: "323a48" if i>=6 else "454451")
        else:
            m.rings([(s*x,y,z,rx,rz,b) for y,x,rx,rz,z,b in leg],pants,thigh,22,
                    lambda i,a:trim if role=="qiao" and abs(sin(a)-s)<.017 else pants)
        m.rings([(s*.11,.014,-.055,.067,.148),(s*.11,.025,-.056,.071,.151),(s*.11,.046,-.056,.073,.15)],"d6cdbb",foot,24)
        m.rings([(s*.11,.043,-.055,.071,.145),(s*.11,.067,-.058,.071,.143),(s*.11,.094,-.04,.066,.119),
                 (s*.11,.125,-.003,.056,.072),(s*.11,.154,.004,.052,.060)],shoe,foot,24)
        for j in range(3):
            m.tube([[s*.11-.029,.094+j*.008,-.113+j*.014],[s*.11,.097+j*.008,-.108+j*.014],
                    [s*.11+.029,.094+j*.008,-.113+j*.014]],.0026,"dfd9cb",foot,6)
        # Piped cutlines, heel counter and flex creases survive the lower mesh LODs.
        for y,x,rad,z,bnd in [(1.113,.252,.065,-.001,elbow),(.493,.104,.078,-.018,knee)]:
            if role=="xu" and bnd==knee: continue
            pts=[[s*(x+rad*k),y+.006*cos(k*2),z-rad*np.sqrt(max(.01,1-k*k))-.002] for k in np.linspace(-.68,.77,9)]
            m.tube(pts,.0018,color(sleeve if bnd==elbow else pants)*.60,bnd)
        m.tube([[s*.169,.059,-.086],[s*.179,.066,-.043],[s*.170,.079,.024],[s*.149,.093,.061]],
               .0034,trim,foot)
    if role=="xu":
        pleated_skirt(m)
    if classroom: return
    if role=="teacher":
        # Muted faculty jacket, tie, pen pocket and chalk at the right fingertips.
        textile([(1.145,-.010,.010),(1.18,-.024,.024),(1.39,-.014,.014),(1.425,-.022,.022)],"485b6c")
        m.patch([shell(x,y,.013) for x,y in [(.045,1.296),(.127,1.296),(.125,1.242),(.047,1.240)]],"3c454c",chest)
        m.tube([shell(.105,1.28,.018),shell(.105,1.315,.018)],.003,"b4a891",chest)
        textbook(m)
    if role=="lin":
        # Fabric camera sling crossing the jacket, camera housing, barrel and window.
        m.tube([[-.124,1.416,-.07],[-.083,1.327,-.127],[.005,1.204,-.132],[.077,1.090,-.111],[.138,1.011,-.078]],.013,"6e5040",chest,8)
        m.rings([(-.043,1.129,-.145,.065,.027),(-.043,1.137,-.145,.070,.032),
                 (-.043,1.193,-.145,.070,.032),(-.043,1.204,-.145,.063,.027)],"3c4244","Spine",12)
        m.oval([-.063,1.208,-.146],(.022,.012,.019),"6b7374","Spine",10)
        m.patch([(-.097,1.130,-.174),(.017,1.130,-.161),(.019,1.201,-.157),(-.097,1.201,-.157)],"363e45","Spine")
        m.oval([-.043,1.166,-.178],(.031,.030,.020),"8e9292","Spine")
        m.oval([-.043,1.166,-.197],(.022,.022,.008),"263745","Spine")
        m.oval([-.078,1.188,-.161],(.01,.006,.002),"d4c9b4","Spine")
        m.tube([[-.15,1.39,-.054],[-.108,1.236,-.126],[-.086,1.191,-.156]],.0035,"383b3d",chest)
    elif role=="shen":
        m.tube([[.139,1.406,-.063],[.100,1.297,-.120],[-.005,1.156,-.135],[-.130,1.005,-.106]],.014,"786143",chest)
        m.oval([-.156,.965,-.051],(.077,.086,.079),"817256","Hips",14)
        m.patch([(-.217,1.01,-.091),(-.113,1.025,-.129),(-.120,.959,-.137),(-.205,.945,-.108)],"a18a67","Hips")
        for j in range(2):
            m.tube([[.061+j*.011,1.297,-.129],[.064+j*.011,1.335,-.122]],.0035,["b99b67","34434b"][j],chest)
    elif role=="qiao":
        for s in (-1,1):
            m.tube([[s*.175,1.382,-.046],[s*.127,1.347,-.098],[s*.074,1.327,-.120]],.006,"eee3cc",chest)
        m.oval([-.264*width,.932,-.055],(.044,.017,.022),"443f3f","ElbowR")
    elif role=="xu":
        m.oval([0,1.427,.048],(.123,.074,.097),"b4aa91",chest,28)
        for s in (-1,1):
            m.oval([s*.091,1.419,-.079],(.034,.041,.036),"423b40",chest)
            m.oval([s*.106,1.417,-.101],(.024,.029,.021),"ab7555",chest)
        m.tube([[-.074,1.418,-.036],[-.083,1.462,.019],[0,1.483,.068],[.083,1.462,.019],[.074,1.418,-.036]],.009,"413d41",chest)


def posed_bones(bones, shift, angles):
    matrices = {}
    for bone,(parent,rest) in bones.items():
        local = np.eye(4)
        local[:3,:3] = rotation(angles.get(bone,(0,0,0)))
        local[:3,3] = rest-bones[parent][1] if parent else rest+shift
        matrices[bone] = matrices[parent]@local if parent else local
    return matrices


def textbook(mesh):
    pose_now = posed_bones(mesh.bones,*pose("read",.25))
    left = pose_now["FingersL"][:3,3]
    right = pose_now["FingersR"][:3,3]
    middle = (left+right)*.5 + [0,.012,-.020]
    grip = np.linalg.inv(pose_now["HandL"])
    def point(x,y,z):
        p = middle + [x,y+.30*abs(x)-.40*z,z]
        return (grip@np.append(p,1))[:3]+mesh.bones["HandL"][1]
    for side in (-1,1):
        width = abs(left[0]-right[0])*.56
        for height,margin,tint in [(0,.004,"683e37"),(.006,0,"ded4ad")]:
            corners = [point(x,height,z) for x,z in
                       [(0,-.088-margin),(side*(width+margin),-.088-margin),
                        (side*(width+margin),.086+margin),(0,.086+margin)]]
            indices = [mesh.vertex(p,tint,"HandL") for p in corners]
            for a,b,c in [(0,1,2),(0,2,3)]:
                face = [indices[a],indices[b],indices[c]]
                mesh.tris.append(face)
                mesh.tris.append([mesh.vertex(mesh.vertices[i],tint,"HandL") for i in reversed(face)])
        for line in range(6):
            z = -.058+.019*line
            mesh.tube([point(side*.013,.007,z),point(side*(width-.012-.007*(line%2)),.007,z)],
                      .0017,"756d5f","HandL",4)


def pleated_skirt(mesh):
    # One continuous tube: the turned-under hem is joined to the outer cloth.
    # The waist is pinned; every lower vertex blends adjacent panels across the seam.
    rings = []
    sides = 96
    for y, rx, rz, fullness, tint in [
            (.894,.163,.128,.2,"343d50"), (.735,.217,.155,.78,"343d50"), (.621,.231,.163,1,"343d50"),
            (.557,.242,.170,.90,"343d50"), (.544,.253,.179,1,"434d65"),
            (.550,.252,.178,1,"a09785"), (.556,.252,.178,1,"535e76"),
            (.621,.241,.171,1,"566178"), (.735,.226,.163,.78,"535e76"),
            (.831,.197,.150,.49,"4d586d"), (.902,.175,.135,.2,"434e62"),
            (.923,.173,.133,.05,"353e50"), (.952,.173,.133,0,"394256")]:
        ring = []
        for j in range(sides):
            a = TAU*j/sides
            fold = [1.,.985,.94,.90,.915,.956][j%6]
            depth = 1 - (1-fold)*fullness
            panel = j*SKIRT_PANELS/sides
            k = int(panel)
            u = panel-k
            if y>=SKIRT_RINGS[0][1]:
                follow = np.clip((.939-y)/(.939-SKIRT_RINGS[0][1]),0,1)
                weights = [("Hips",1-follow),(f"Lap{k:02}",follow*(1-u)),
                           (f"Lap{(k+1)%SKIRT_PANELS:02}",follow*u)]
            else:
                upper, lower = SKIRT_RINGS[:2] if y>=SKIRT_RINGS[1][1] else SKIRT_RINGS[1:]
                blend = np.clip((upper[1]-y)/(upper[1]-lower[1]),0,1)
                weights = [(f"{bone}{idx%SKIRT_PANELS:02}",w*t) for bone,w in ((upper[0],1-blend),(lower[0],blend))
                           for idx,t in ((k,1-u),(k+1,u))]
            ring.append(mesh.vertex((rx*depth*sin(a),y,-rz*depth*cos(a)),
                                    color(tint)*(.82+.18*(fold-.90)/.10), weights))
        rings.append(ring)
    for lower, upper in zip(rings, rings[1:]):
        for j in range(sides):
            k = (j+1)%sides
            mesh.tris.extend(((lower[j],upper[j],lower[k]),(lower[k],upper[j],upper[k])))


def rotation(euler):
    x,y,z,w = quaternion(euler)
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                     [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                     [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])


def drape(bones, angles, name):
    # Each control samples the two posed legs at its height. Joint translation
    # is baked into the clip so remote avatars need no runtime cloth solver.
    a = TAU*int(name[3:])/SKIRT_PANELS
    n = np.array([sin(a),0,-cos(a)])
    front = tanh(2.8*cos(a))/tanh(2.8)
    legs = [angles.get("Thigh"+s,(0,0,0)) for s in ("L","R")]
    flex = sum(v[0] for v in legs)/2
    rest = bones[name][1]
    thighs, shins = [], []
    for side,angles_at_hip in zip(("L","R"), legs):
        hip = bones["Thigh"+side][1]
        knee = bones["Knee"+side][1]
        ankle = bones["Foot"+side][1]
        leg = rotation(angles_at_hip)
        bent_knee = hip+leg@(knee-hip)
        bent_ankle = bent_knee+leg@rotation(angles.get("Knee"+side,(0,0,0)))@(ankle-knee)
        thighs.append((hip,bent_knee))
        shins.append((bent_knee,bent_ankle))
    # Intersect the actual posed legs with each horizontal cloth station. A
    # bind-length sample misses the forward knee when it rises above the hem.
    y = rest[1] + .83*(.89-rest[1])*(1-min(cos(v[0]*pi/180) for v in legs))
    centers = []
    support = []
    for thigh,shin in zip(thighs,shins):
        top,bottom = thigh if y>=thigh[1][1] else shin
        direction = bottom-top
        fraction = np.clip((y-top[1])/min(-.001,direction[1]),0,1)
        centers.append((top+direction*fraction)[[0,2]])
        slope = np.abs(direction[[0,2]])/max(.12,abs(direction[1]))
        support.append(.078*np.sqrt(1+np.minimum(1.8,slope)**2))
    half = (centers[0]-centers[1])*.5
    middle = (centers[0]+centers[1])*.5
    direction = n[[0,2]]
    spread = np.linalg.norm(half)
    softness = max(.055,spread*.92)
    side_weight = tanh(np.dot(direction,half)/softness)/max(.01,tanh(spread/softness))
    radius = (support[0]*(1+side_weight)+support[1]*(1-side_weight))*.5
    outline = middle + half*side_weight + (radius + [.048,.040])*direction
    swing = min(1,max(max(abs(v[0]),abs(v[2])) for v in legs)/32)
    target = (1-swing)*rest + swing*np.array([outline[0],y,outline[1]])
    lift = np.clip((flex-25)/55,0,1)
    lift = lift*lift*(3-2*lift)
    if name.startswith("Lap"):
        folded = np.array([.243*sin(a),.870+.148*front,-.120-.125*front])
    elif name.startswith("Rim"):
        folded = np.array([.255*sin(a),.864+.149*front,-.244-.226*front])
    else:
        folded = np.array([.251*sin(a),.775+.056*front,-.260-.253*front])
    target = target*(1-lift) + folded*lift
    return target-bones["Hips"][1]


class GLB:
    COMPONENT = {"f": 5126, "B": 5121, "H": 5123}

    def __init__(self):
        self.binary = bytearray()
        self.doc = {"asset": {"version": "2.0", "generator": "WDFZ student cast"},
                    "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [], "meshes": [], "skins": [],
                    "animations": [], "accessors": [], "bufferViews": [],
                    "materials": [{"name":"CampusCloth","pbrMetallicRoughness":{"metallicFactor":0,"roughnessFactor":.83}}]}

    def array(self, values, kind, dtype="f", bounds=False, normalized=False):
        data = np.ascontiguousarray(values, dtype={"f":"<f4","H":"<u2","B":"u1"}[dtype])
        offset = len(self.binary)
        self.binary.extend(data.tobytes())
        self.binary.extend(b"\0" * (-len(self.binary) % 4))
        views = self.doc["bufferViews"]
        acc = {"bufferView": len(views), "componentType": self.COMPONENT[dtype], "count": len(data), "type": kind}
        if bounds:
            acc.update(min=np.atleast_1d(data.min(axis=0)).tolist(),max=np.atleast_1d(data.max(axis=0)).tolist())
        if normalized: acc["normalized"] = True
        views.append({"buffer":0, "byteOffset":offset, "byteLength":data.nbytes})
        self.doc["accessors"].append(acc)
        return len(self.doc["accessors"])-1

    def build(self, mesh, clips=CLIPS):
        names = mesh.names
        nodes = self.doc["nodes"]
        nodes.append({"name":"Student","children":[1,len(names)+1]})
        for name,(parent,position) in mesh.bones.items():
            node={"name":name,"translation":(position-(mesh.bones[parent][1] if parent else 0)).tolist()}
            children=[names.index(b)+1 for b,(p,_) in mesh.bones.items() if p==name]
            if children: node["children"]=children
            nodes.append(node)
        nodes.append({"name":"Uniform","mesh":0,"skin":0})
        binds=[]
        for _,pos in mesh.bones.values():
            matrix=np.eye(4); matrix[:3,3]=-pos
            binds.append(matrix.T.flatten())
        self.doc["skins"].append({"name":"StudentRig","skeleton":1,"joints":list(range(1,len(names)+1)),
                                  "inverseBindMatrices":self.array(binds,"MAT4")})
        v=np.asarray(mesh.vertices)
        faces=np.array(mesh.tris)
        cross=np.cross(v[faces[:,1]]-v[faces[:,0]],v[faces[:,2]]-v[faces[:,0]])
        normals=np.zeros_like(v)
        for k in range(3): np.add.at(normals,faces[:,k],cross)
        normals/=np.maximum(1e-12,np.linalg.norm(normals,axis=1))[:,None]
        props={"POSITION":self.array(v,"VEC3",bounds=True),"NORMAL":self.array(normals,"VEC3"),
               "JOINTS_0":self.array(mesh.joints,"VEC4","B"),"WEIGHTS_0":self.array(mesh.weights,"VEC4")}
        rgba=np.column_stack((np.uint16(65535*np.clip(mesh.colors,0,1)),np.full(len(v),65535,dtype=np.uint16)))
        props["COLOR_0"]=self.array(rgba,"VEC4","H",normalized=True)
        self.doc["meshes"].append({"name":"CampusStudent","primitives":[{"attributes":props,
                                    "indices":self.array(faces.flatten(),"SCALAR","H"),"material":0}]})
        for clip,length in clips.items():
            phase=np.linspace(0,1,17)
            times=self.array(phase*length,"SCALAR",bounds=True)
            hold_times=self.array([0,length],"SCALAR",bounds=True)
            samples=[pose(clip,t) for t in phase]
            if "Lap00" in mesh.bones and clip in ("sit","ride","sit_down","stand_up"):
                for shift,angles in samples:
                    seated = -shift[1]/.435
                    for side in ("L","R"):
                        arm = angles["Arm"+side]
                        elbow = angles["Elbow"+side]
                        angles["Arm"+side]=(arm[0]+9*seated,arm[1],arm[2])
                        angles["Elbow"+side]=(elbow[0]+4*seated,elbow[1],elbow[2])
            if "Lap00" in mesh.bones and clip in ("crouch","search","bandage"):
                for _,angles in samples:
                    for side,sign in (("L",1),("R",-1)):
                        arm = angles["Arm"+side]
                        elbow = angles["Elbow"+side]
                        angles["Arm"+side]=(arm[0]+7,arm[1],arm[2]+sign*13)
                        angles["Elbow"+side]=(elbow[0]+9,elbow[1],elbow[2])
            channels=[]; samplers=[]
            def channel(bone,path,values,kind):
                input_keys=times
                if np.allclose(values,values[0]):
                    input_keys=hold_times
                    values=[values[0],values[-1]]
                channels.append({"sampler":len(samplers),"target":{"node":names.index(bone)+1,"path":path}})
                samplers.append({"input":input_keys,"output":self.array(values,kind),"interpolation":"LINEAR"})
            channel("Hips","translation",[mesh.bones["Hips"][1]+shift for shift,_ in samples],"VEC3")
            for bone in names:
                if bone.startswith("Clavicle") or bone=="Neck": continue
                if bone.startswith(("Lap","Rim","Hem")):
                    cloth=[drape(mesh.bones,rot,bone) for _,rot in samples]
                    channel(bone,"translation",cloth,"VEC3")
                    continue
                values=[]
                for _,rot in samples:
                    angles=rot.get(bone,(0,0,0))
                    if bone.startswith("Fingers"):
                        angles=(9 if clip in ("walk","idle","sit") else 25,0,0)
                    values.append(quaternion(angles))
                channel(bone,"rotation",values,"VEC4")
            suffix="" if clip in ONE_SHOTS else "_loop"
            self.doc["animations"].append({"name":clip+suffix,"samplers":samplers,"channels":channels})

    def seated_extra(self, mesh, name):
        # Bake a shared, reduced mesh for background desks. The entire classroom
        # can use two static meshes without evaluating dozens of skeletons.
        shift, angles = pose("sit", .2)
        matrices = posed_bones(mesh.bones,shift,angles)
        v = np.column_stack((mesh.vertices, np.ones(len(mesh.vertices))))
        skin = []
        for bone,(_,rest) in mesh.bones.items():
            inverse = np.eye(4)
            inverse[:3,3] = -rest
            skin.append((matrices[bone]@inverse)[:3,:])
        weighted = np.einsum("vi,vijk->vjk", mesh.weights, np.asarray(skin)[mesh.joints])
        posed = np.einsum("vij,vj->vi", weighted, v)
        paint = np.array(mesh.colors)
        cells, index = np.unique(np.round(posed/.016).astype(int),axis=0,return_inverse=True)
        counts = np.bincount(index)[:,None]
        positions = np.zeros((len(cells),3))
        colors = np.zeros_like(positions)
        np.add.at(positions,index,posed)
        np.add.at(colors,index,paint)
        positions /= counts
        colors /= counts
        faces = index[np.asarray(mesh.tris)]
        faces = faces[(faces[:,0]!=faces[:,1]) & (faces[:,1]!=faces[:,2]) & (faces[:,2]!=faces[:,0])]
        cross = np.cross(positions[faces[:,1]]-positions[faces[:,0]],positions[faces[:,2]]-positions[faces[:,0]])
        normals = np.zeros_like(positions)
        for k in range(3): np.add.at(normals,faces[:,k],cross)
        normals /= np.maximum(1e-12,np.linalg.norm(normals,axis=1))[:,None]
        rgb = np.column_stack((np.uint16(65535*np.clip(colors,0,1)),np.full(len(colors),65535)))
        attributes = {"POSITION":self.array(positions,"VEC3",bounds=True),
                      "NORMAL":self.array(normals,"VEC3"),"COLOR_0":self.array(rgb,"VEC4","H",normalized=True)}
        node = len(self.doc["nodes"])
        if node: self.doc["scenes"][0]["nodes"].append(node)
        self.doc["nodes"].append({"name":name,"mesh":node})
        self.doc["meshes"].append({"name":name,"primitives":[{"attributes":attributes,
            "indices":self.array(faces.flatten(),"SCALAR","H"),"material":0}]})

    def save(self,path):
        self.doc["buffers"]=[{"byteLength":len(self.binary)}]
        raw=json.dumps(self.doc,separators=(",",":")).encode()
        raw+=b" "*(-len(raw)%4)
        size=28+len(raw)+len(self.binary)
        path.write_bytes(struct.pack("<4sIII4s",b"glTF",2,size,len(raw),b"JSON")+raw+
                         struct.pack("<I4s",len(self.binary),b"BIN\0")+self.binary)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base",type=Path,default=ROOT/"build"/"student-art"/"hm08.obj")
    source=anatomy(parser.parse_args().base)
    out=ROOT/"assets"/"characters"
    out.mkdir(parents=True,exist_ok=True)
    classroom=GLB()
    for role,design in CAST.items():
        mesh=Mesh(skeleton(design[-2], skirt=role=="xu"))
        face_and_hands(mesh,role,source)
        if role in ("lin","qiao"):
            extra=Mesh(mesh.bones)
            face_and_hands(extra,role,source)
            outfit(extra,role,classroom=True)
            classroom.seated_extra(extra,"Seated"+role.title())
        outfit(mesh,role)
        model=GLB()
        clips={c:CLIPS[c] for c in ("read","speak")} if role=="teacher" else CLIPS
        model.build(mesh, clips)
        model.save(out/(role+".glb"))
        print(f"{role}: {len(mesh.vertices)} vertices, {len(mesh.tris)} triangles, {len(mesh.bones)} bones, {len(clips)} clips")

    classroom.doc.pop("animations")
    classroom.doc.pop("skins")
    classroom.save(out/"classmates.glb")


if __name__=="__main__":
    main()
