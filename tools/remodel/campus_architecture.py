#!/usr/bin/env python3
"""Bake original campus architecture from the game's own layout, in metres.

Visual reference: 武汉大学附属中学VR实景校园, https://www.720yuntu.com/tour/7e11b56b6f8381ab
Run python3 tools/remodel/campus_architecture.py from any directory (numpy, Pillow).
"""
import json
from math import cos, pi, sin, tau
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from campus_mesh import Part, save
from campus_furniture import furniture
from campus_planting import garden_beds

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'assets/campus/architecture'
LAYOUT = ROOT / 'assets/campus/layout'
CREAM, LIMESTONE, JOINT, PEACH = 'f6e7cf', 'c9bba8', 'a68e7c', 'e3a28c'
PORTICO_PROJECTION = 3.13
PORTICO_PIER_X = 3.26
RED, OXIDE, TILE, BRONZE = 'b65033', '84402e', 'cb6944', '675343'


def pavers():
    rng = np.random.default_rng(725)
    size = 384
    y, x = np.indices((size, size))
    tile = 48
    field = rng.normal(0, 3.6, (size, size)) + rng.normal(182, 6, (8, 8))[y//tile, x//tile]
    edge = np.minimum(x % tile, y % tile)
    field -= np.where(edge < 2, 50, np.where(edge == 2, -8, 0))
    rgb = np.clip(field[:, :, None] + [6, 4, 1], 0, 255).astype('uint8')
    Image.fromarray(rgb).save(DEST / 'pavers.png', optimize=True)


def footprint(obj):
    scale = 2/9
    return tuple(obj[k]*scale for k in ('x', 'y', 'w', 'h'))


def arch(part, x, z, radii, spring, thickness, depth, tint, stones=25):
    """Solid elliptical voussoirs; a player can walk through the actual opening."""
    rx, ry = radii
    for i in range(stones):
        a, b = pi*i/stones, pi*(i+1)/stones
        face = []
        for r, t in [(0,a), (thickness,a), (thickness,b), (0,b)]:
            face.append(np.array((x+(rx+r)*cos(t), spring+(ry+r)*sin(t), z)))
        back = [v-(0,0,depth) for v in face]
        shade = tint[i % len(tint)]
        part.face(face, shade)
        part.face(back[::-1], shade)
        for j in range(4):
            k = (j+1) % 4
            part.face([face[j],back[j],back[k],face[k]], shade)


def facade(name, obj, link_gaps):
    p = Part()
    x,z,w,d = footprint(obj)
    cx, front = x+w/2, z+d
    dorm = name.startswith('dorm')
    rise = 3 if dorm else 3.2
    floors = 6 if dorm else 5
    if name == 'canteen':
        floors, rise = 2, 4.3
    # Thin courses sit on the floor slabs, above the glazed and walk-through bays.
    for level in range(1, floors+1):
        y = rise*level-.12
        for zz in (z-.05,front+.05):
            p.block((cx,y,zz), (w+.24,.16,.18), CREAM)
            p.block((cx,y-.12,zz), (w+.12,.055,.13), LIMESTONE)
        for xx in (x-.05,x+w+.05):
            p.block((xx,y,z+d/2), (.18,.16,d+.24), CREAM)
    # The accessible teaching roof has an open parapet on the gallery side.
    crown = floors*rise + (.42 if dorm else (.14 if name=='canteen' else 1.17))
    for zz in ([z-.10] if name=='teach' else [z-.10,front+.10]):
        p.block((cx,crown,zz),(w+.55,.19,.34),CREAM)
        p.block((cx,crown+.11,zz),(w+.66,.05,.39),'84918d')
    for xx in (x-.1,x+w+.1):
        p.block((xx,crown,z+d/2),(.30,.19,d+.48),CREAM)
    if name in ('teach','lab','admin'):
        # Paired pilasters frame the existing front entry, away from its clear span.
        spring = 1.32
        face = front+PORTICO_PROJECTION
        for side in (-1,1):
            xx = cx+side*PORTICO_PIER_X
            p.block((xx,spring/2,face-.12),(.42,spring,.30),CREAM)
            p.block((xx,.22,face-.10),(.54,.44,.38),LIMESTONE)
            p.block((xx,spring-.02,face-.10),(.56,.13,.41),CREAM)
            p.block((xx,3.20,(front+face)/2),(.27,.20,face-front),LIMESTONE)
            for offset in (4.18, 4.46):
                p.block((cx+side*offset,1.44,front+.03),(.16,2.88,.22),PEACH)
        # An open window bay rises over the entrance. Shadowed reveals and the
        # cream centre mullion give the front a vertical rhythm among the galleries.
        projection = front+1.53
        for level in range(1,floors):
            base = level*rise
            for side in (-1,1):
                p.block((cx+side*2.64,base+rise/2,projection-.20),(1.23,rise,.42),PEACH)
                p.block((cx+side*1.98,base+rise/2,projection-.095),(.14,rise,.29),CREAM)
            p.block((cx,base+.44,projection-.17),(5.52,.88,.35),PEACH)
            p.block((cx,base+.93,projection-.10),(4.20,.12,.49),CREAM)
            p.block((cx,base+rise-.15,projection-.19),(5.53,.30,.36),PEACH)
            p.block((cx,base+rise-.35,projection-.13),(4.15,.11,.32),CREAM)
            for mx in (-.65,.65):
                p.block((cx+mx,base+1.90,projection-.30),(.045,1.85,.063),'76817e')
        p.block((cx,floors*rise+.12,projection-.23),(7.05,.35,.60),CREAM)
        # Posts on the upper gallery edge leave the existing level-two links clear.
        for k in range(1,round(w/4.2)):
            xx = x+k*w/round(w/4.2)
            if abs(xx-cx)<3.8 or any(lo-.5 < xx < hi+.5 for lo,hi in link_gaps): continue
            p.block((xx,(rise+rise*floors)/2,projection-.15),(.31,rise*(floors-1),.32),PEACH)
            for level in range(2,floors+1):
                p.block((xx,rise*level-.25,projection-.15),(.42,.18,.41),CREAM)
        arch(p,cx,face,(3.06,2.22),spring,.40,.36,[CREAM,'ecdbc3','f3e4ce'])
        arch(p,cx,face+.04,(2.98,2.14),spring,.09,.24,[LIMESTONE])
        arch(p,cx,face+.02,(3.46,2.62),spring,.09,.32,[LIMESTONE])
        p.block((cx,spring+2.49,face+.025),(.32,.39,.39),CREAM)
    return p


def bridge(orange):
    p, deck, lamps = Part(), Part(tiled=True), Part()
    # Both game bridges use the same 5 x 24 m deck. The two ends remain open.
    p.block((0,-.085,0), (5,.17,24), 'b8ada1')
    deck.floor(-2.5,-12,2.5,12,.004,'fcf8ef')
    for x in (-1.80,1.80):
        p.floor(x-.055,-12,x+.055,12,.009,'ab7763')
    if not orange:
        for z in (-8,-4,0,4,8):
            p.floor(-2.45,z-.055,2.45,z+.055,.009,'ab7763')
    side_color = RED if orange else PEACH
    metal = OXIDE if orange else '465357'
    for side in (-1,1):
        x = side*2.39
        for y,h,w,c in ((.10,.20,.19,side_color),(.22,.075,.09,metal),(.83,.055,.08,metal),
                        (1.08,.075,.12,side_color if orange else '5b5c59')):
            p.block((x,y,0),(w,h,24),c)
        for z in np.arange(-11.75,12,.50):
            p.block((x,.53,z),(.042,.59,.042),metal)
        for z in np.linspace(-11.87,11.87,9):
            p.block((x,.10,z),(.31,.2,.31),OXIDE if orange else LIMESTONE)
            p.block((x,1.50,z),(.19 if orange else .33,2.95,.20 if orange else .36),side_color)
            p.block((x,2.80,z),(.31,.18,.33),side_color if orange else CREAM)
        p.block((x,2.91,0),(.26,.20,24),side_color)
    if orange:
        # Pitched roof visible from underneath; purlins and triangular bracing carry it.
        for side in (-1,1):
            a,b = np.array((0,3.96,0)),np.array((side*2.61,2.99,0))
            run = (b-a)/np.linalg.norm(b-a)
            axis = np.array((0,0,side))
            p.block((a+b)/2,(np.linalg.norm(b-a),.115,24.12),TILE,[run,np.cross(axis,run),axis])
            for k in range(1,7):
                u = k/7
                p.block((side*2.58*u,3.86-.96*u,0),(.065,.11,24),OXIDE)
        for z in np.linspace(-11.87,11.87,9):
            p.block((0,2.96,z),(4.91,.16,.18),RED)
            for side in (-1,1):
                p.beam((side*2.47,2.96,z),(0,3.91,z),.17,.16,RED)
                p.beam((side*1.58,2.99,z),(side*.78,3.57,z),.10,.12,OXIDE)
                p.beam((side*2.36,2.43,z),(side*1.86,2.93,z),.11,.12,RED)
            p.block((0,3.42,z),(.13,.91,.13),OXIDE)
        p.block((0,4.01,0),(.19,.10,24.16),RED)
    else:
        p.block((0,3.11,0),(5.24,.22,24.1),CREAM)
        for z in np.linspace(-11.87,11.87,9):
            p.block((0,2.92,z),(4.95,.17,.32),LIMESTONE)
    for z in (-8,0,8):
        if orange: p.block((0,2.85,z),(.48,.12,.20),BRONZE)
        lamps.block((0,2.82 if orange else 2.97,z),(.43,.035,.17),'eee5c8')
    return {'Frame':p,'Paving':deck,'CeilingLights':lamps}


def courts(obj):
    p = Part()
    x,z,w,d = footprint(obj)
    # Gameplay hoops face across the longer dimension of each court.
    cx,cz = x+w/2,z+d/2
    length, width = max(w,d), min(w,d)
    def point(u,v,y):
        return (cx+u,y,cz+v) if w>=d else (cx-v,y,cz+u)
    def panel(u0,v0,u1,v1,y,tint):
        p.face([point(u0,v0,y),point(u0,v1,y),point(u1,v1,y),point(u1,v0,y)],tint)
    white='f2edda'
    def stripe(u0,v0,u1,v1):
        panel(u0,v0,u1,v1,.111,white)
    def ring(u,v,r,a,b):
        for a0,a1 in zip(np.linspace(a,b,45)[:-1],np.linspace(a,b,45)[1:]):
            p.face([point(u+(r+e)*cos(t),v+(r+e)*sin(t),.113) for e,t in
                    ((0,a0),(0,a1),(.075,a1),(.075,a0))],white)
    panel(-length/2,-width/2,length/2,width/2,.101,'517e68')
    end, edge = length/2-.32,width/2-.32
    key = min(5.2,end*.48)
    half = min(2.12,edge*.41)
    for side in (-1,1):
        lo,hi=sorted((side*end,side*(end-key)))
        panel(lo,-half,hi,half,.106,'b56e5a')
        stripe(lo,-half,hi,-half+.077)
        stripe(lo,half-.077,hi,half)
        stripe(side*(end-key)-.038,-half,side*(end-key)+.038,half)
        ring(side*(end-key),0,half,0,tau)
        start = -pi/2 if side<0 else pi/2
        ring(side*(end-.68),0,min(edge*.80,key*1.05),start,start+pi)
        stripe(-end,side*edge-.04,end,side*edge+.04)
        stripe(side*end-.04,-edge,side*end+.04,edge)
    stripe(-.04,-edge,.04,edge)
    ring(0,0,min(1.65,half),0,tau)
    return p


def geography(x,z):
    p = Part()
    stone, light, bronze = 'b6b3a3','e9e3cd','877452'
    solids = []
    # The open-sided pavilion stands on the game's garden path.
    for r,y,h in ((2.20,0,.09),(2.03,.09,.09),(1.88,.18,.08)):
        p.disk(x,y,z,r,h,stone if y<.18 else light,sides=48)
    for i in range(8):
        t = tau*i/8+pi/8
        xx, zz = x+1.62*cos(t),z+1.62*sin(t)
        for y,r,h,rt in ((.26,.23,.15,.23),(.41,.18,.12,.13),(.53,.122,2.37,.106),
                         (2.90,.13,.11,.18),(3.01,.20,.12,.20)):
            p.disk(xx,y,zz,r,h,light,rt,16)
        solids.append((xx,zz,.22,3.15))
    p.disk(x,3.12,z,1.96,.16,light,2.04,48)
    for i in range(7):
        lo,hi = 1.38*i/7,1.38*(i+1)/7
        p.disk(x,3.28+sin(lo)*.89,z,2.01*cos(lo),(sin(hi)-sin(lo))*.89,
               ['467b94','51869c','508198'][i%3],2.01*cos(hi),48)
    p.disk(x,4.15,z,.39,.10,bronze,.24)
    p.disk(x,4.25,z,.078,.22,bronze,.022)
    gx,gz = x-6.2,z+.18
    p.disk(gx,.02,gz,1.10,.15,stone,sides=40)
    p.disk(gx,.17,gz,.63,.35,'c2ac89',.49)
    p.disk(gx,.52,gz,.37,.23,bronze,.27)
    center=np.array((gx,1.49,gz))
    # Hand-drawn continental silhouettes on a sphere, with raised graticules.
    land = Image.new('L',(1024,512))
    draw = ImageDraw.Draw(land)
    for coast in [[(-165,68),(-139,70),(-120,61),(-98,76),(-64,57),(-61,44),(-82,24),(-90,17),(-83,8),(-103,19),(-119,29),(-130,48)],
                  [(-80,10),(-62,13),(-51,4),(-35,-5),(-43,-22),(-57,-37),(-69,-55),(-76,-23)],
                  [(-18,30),(3,37),(25,33),(35,25),(49,11),(42,-2),(33,-25),(20,-35),(12,-17),(8,1),(-8,5)],
                  [(-10,37),(1,48),(-6,57),(15,71),(27,61),(54,68),(95,78),(145,72),(172,61),(163,50),(139,44),(126,35),(119,22),(107,6),(95,20),(80,8),(68,24),(48,29),(42,15),(30,31)],
                  [(113,-22),(124,-14),(140,-12),(154,-27),(146,-39),(132,-33),(114,-34)],
                  [(-53,60),(-43,62),(-20,82),(-43,84),(-61,76)],[(47,-13),(50,-16),(46,-26),(43,-23)]]:
        draw.polygon([((lon+180)*1024/360,(90-lat)*512/180) for lon,lat in coast],fill=255)
    iy,ix = np.indices((512,1024))
    variation = np.sin(ix/13+np.cos(iy/8))*3 + np.cos(iy/5+ix/31)*2
    blue = np.array([54,133,164]) + (variation+6*np.sin(iy/32))[:,:,None]
    green = np.array([152,156,92]) + (variation*1.6+8*np.cos(ix/22+iy/13))[:,:,None]
    map_image = Image.fromarray(np.uint8(np.where(np.asarray(land)[:,:,None]>0,green,blue)))
    ink = ImageDraw.Draw(map_image)
    for lon in range(0,360,15):
        line = lon*1024/360
        ink.line([(line,0),(line,512)],fill=(122,161,159))
    for lat in range(15,180,15):
        line = lat*512/180
        ink.line([(0,line),(1024,line)],fill=(134,169,159))
    map_image.save(DEST/'globe.png',optimize=True)
    sphere = Part(texture='globe.png')
    def globe(lon,lat,r=.79):
        a,b = np.radians([lon,lat])
        return np.array([cos(b)*cos(a),sin(b),cos(b)*sin(a)])*r
    for lon in range(-180,180,10):
        for lat in range(-90,90,10):
            coords=[(lon,lat),(lon,lat+10),(lon+10,lat+10),(lon+10,lat)]
            if lat==-90: coords=coords[:3]
            if lat==80: coords=[coords[0],coords[1],coords[3]]
            pts=[globe(*v) for v in coords]
            sphere.face([center+v for v in pts], 'ffffff', [v/.79 for v in pts],
                        [((a+180)/360,(90-b)/180) for a,b in coords])
    # Curved meridian bearing and two end collars support the globe.
    tilt=.28
    def bearing(t):
        return center+np.array([.87*cos(t)*cos(tilt),.87*sin(t),.87*cos(t)*sin(tilt)])
    for a,b in zip(np.linspace(-pi/2,pi/2,23)[:-1],np.linspace(-pi/2,pi/2,23)[1:]):
        p.beam(bearing(a),bearing(b),.038,.043,bronze)
    solids.append((gx,gz,.79,2.29))
    return p, sphere, solids


def collision_scene(solids, x, z, objects):
    data = ['[gd_scene format=3]', '']
    cylinders = list(dict.fromkeys((r,h) for _,_,r,h in solids))
    for i,(r,h) in enumerate(cylinders):
        data += [f'[sub_resource type="CylinderShape3D" id="Cylinder_{i}"]',
                 f'radius = {r:g}', f'height = {h:g}', '']
    data += ['[sub_resource type="BoxShape3D" id="PorticoPier"]',
             'size = Vector3(0.54, 1.39, 0.40)', '']
    points = []
    for y,r in ((-.02,2.28),(.26,1.88)):
        for k in range(32):
            points.extend((round(r*cos(tau*k/32),5),y,round(r*sin(tau*k/32),5)))
    data += ['[sub_resource type="ConvexPolygonShape3D" id="PavilionSteps"]',
             'points = PackedVector3Array('+', '.join(map(str,points))+')','',
             '[node name="Courtyard" type="Node3D"]', '',
             '[node name="PavilionSteps" type="CollisionShape3D" parent="."]',
             f'position = Vector3({x:.5f}, 0, {z:.5f})',
             'shape = SubResource("PavilionSteps")', '']
    for i,(x,z,r,h) in enumerate(solids):
        data += [f'[node name="GardenPost{i}" type="CollisionShape3D" parent="."]',
                 f'position = Vector3({x:.5f}, {h/2:.5f}, {z:.5f})',
                 f'shape = SubResource("Cylinder_{cylinders.index((r,h))}")', '']
    for host in ('teach','lab','admin'):
        x,z,w,d = footprint(objects[host])
        for side in (-1,1):
            xx, zz = x+w/2+side*PORTICO_PIER_X, z+d+PORTICO_PROJECTION-.10
            data += [f'[node name="{host}Pier{"Left" if side<0 else "Right"}" type="CollisionShape3D" parent="."]',
                     f'position = Vector3({xx:.5f}, 0.695, {zz:.5f})',
                     'shape = SubResource("PorticoPier")', '']
    (DEST/'courtyard_collision.tscn').write_text('\n'.join(data))


def main():
    DEST.mkdir(exist_ok=True)
    pavers()
    objects = {o['id']:o for o in json.loads((LAYOUT/'out.json').read_text())['objects']}
    link_gaps = [(x,x+w) for x,_,w,_ in (footprint(objects[k]) for k in ('c1','c2'))]
    parts = {host+'Trim':facade(host,objects[host],link_gaps) for host in ('teach','lab','admin','dormN','dormS','canteen')}
    parts.update({key:courts(objects[key]) for key in ('courtA','courtB','court2')})
    x,z,w,d = footprint(objects['teach'])
    plaza, inlay = Part(tiled=True), Part()
    left,right,front,back=x+1.3,x+w-1.3,z+d+1.0,z+d+10.5
    plaza.floor(left,front,right,back,.034,'f8f8ef')
    for xx in np.arange((left+right)/2-24,(left+right)/2+24.1,6):
        inlay.floor(xx-.07,front,xx+.07,back,.042,'b47e6a')
    for zz in (front+.55,back-.55):
        inlay.floor(left,zz-.065,right,zz+.065,.042,'b47e6a')
    parts.update(Courtyard=plaza, TerracottaInsets=inlay)
    x,z,w,d = footprint(objects['garden'])
    parts['GardenTrunks'],parts['GardenLeaves'] = garden_beds(x,z,w,d)
    parts['GeographyGarden'],parts['Globe'],solids=geography(x+w*.205,z+d*.49)
    collision_scene(solids, x+w*.205, z+d*.49, objects)
    save(DEST/'courtyard.glb',parts)
    save(DEST/'gallery.glb',bridge(False))
    save(DEST/'orange_walk.glb',bridge(True))
    save(DEST/'furnishings.glb',furniture())


if __name__=='__main__':
    main()
