"""Build indexed, lit glTF meshes in metres for the playable campus."""
from functools import lru_cache
from math import cos, sin, tau
from pathlib import Path

import numpy as np

from student_cast import GLB, color, unit


@lru_cache(None)
def paint(value):
    return np.rint(color(value) * 255).astype('uint8').tolist()


class Part:
    """Flat polygons share vertices inside a face; rings can supply smooth normals."""
    def __init__(self, tiled=False, texture=None):
        self.texture = 'pavers.png' if tiled else texture
        self.vertices, self.normals, self.colors, self.indices, self.uv = [], [], [], [], []

    def face(self, points, tint, normals=None, uv=None):
        p = np.asarray(points, dtype=float)
        n = unit(np.cross(p[1] - p[0], p[2] - p[0]))
        offset = len(self.vertices)
        self.vertices.extend(p)
        self.normals.extend([n] * len(p) if normals is None else normals)
        self.colors.extend([paint(tint)] * len(p))
        for i in range(1, len(p) - 1):
            self.indices.extend((offset, offset + i, offset + i + 1))
        if uv is not None:
            self.uv.extend(uv)
        elif self.texture == 'pavers.png':
            # Paving UVs stay continuous across adjoining ground panels.
            self.uv.extend(p[:, [0, 2]] / 2.4)

    def block(self, center, size, tint, axes=None):
        axes = np.eye(3) if axes is None else axes
        center = np.asarray(center)
        u, v, w = np.asarray(axes) * (np.asarray(size)[:, None] / 2)
        for a, b, c in ((u, v, w), (v, w, u), (w, u, v)):
            for side in (-1, 1):
                origin = center + c * side
                self.face([origin - a - b*side, origin + a - b*side,
                           origin + a + b*side, origin - a + b*side], tint)

    def beam(self, a, b, width, depth, tint):
        a, b = np.asarray(a), np.asarray(b)
        direction = unit(b-a)
        side = unit(np.cross(direction, (0, 0, 1) if abs(direction[2]) < .95 else (0, 1, 0)))
        self.block((a+b)/2, (width, depth, np.linalg.norm(b-a)), tint,
                   [side, np.cross(direction, side), direction])

    def tube(self, a, b, r0, r1, tint, sides=12):
        a, b = np.asarray(a), np.asarray(b)
        axis = unit(b-a)
        u = unit(np.cross(axis, (0, 0, 1) if abs(axis[2]) < .95 else (0, 1, 0)))
        v = np.cross(axis, u)
        radial = [u*cos(tau*k/sides) + v*sin(tau*k/sides) for k in range(sides)]
        low, high = [a+r*r0 for r in radial], [b+r*r1 for r in radial]
        ns = [unit(r + axis*(r0-r1)/np.linalg.norm(b-a)) for r in radial]
        for i in range(sides):
            j = (i+1) % sides
            self.face([low[i], low[j], high[j], high[i]], tint, [ns[i], ns[j], ns[j], ns[i]])
        self.face(low[::-1], tint)
        self.face(high, tint)

    def disk(self, x, y, z, radius, height, tint, top=None, sides=32):
        self.tube((x, y, z), (x, y+height, z), radius, radius if top is None else top, tint, sides)

    def floor(self, x0, z0, x1, z1, y, tint):
        self.face([(x0,y,z0), (x0,y,z1), (x1,y,z1), (x1,y,z0)], tint)


def save(path, parts):
    lib = GLB()
    doc = lib.doc
    del doc['skins'], doc['animations']
    doc['asset']['generator'] = 'WDFZ campus architecture'
    doc['materials'] = [{'name': 'CampusFinish', 'pbrMetallicRoughness':
                         {'metallicFactor': 0, 'roughnessFactor': .95}}]
    textures = list(dict.fromkeys(p.texture for p in parts.values() if p.texture))
    if textures:
        doc['images'] = [{'uri': name} for name in textures]
        doc['textures'] = [{'source': i} for i in range(len(textures))]
        for i,name in enumerate(textures):
            material = {'name': Path(name).stem, 'pbrMetallicRoughness':
                        {'baseColorTexture': {'index': i}, 'metallicFactor': 0, 'roughnessFactor': 1}}
            if name.startswith('../textures/'):
                material.update(alphaMode='MASK', alphaCutoff=.4, doubleSided=True)
            doc['materials'].append(material)
    if 'CeilingLights' in parts:
        lamp_material = len(doc['materials'])
        doc['extensionsUsed'] = ['KHR_materials_unlit']
        doc['materials'].append({'name': 'wdfz_live:emit', 'extensions': {'KHR_materials_unlit': {}},
                                 'pbrMetallicRoughness': {'metallicFactor': 0, 'roughnessFactor': 1}})
    doc['nodes'].append({'name': path.stem, 'children': list(range(1, len(parts)+1))})
    for index, (name, part) in enumerate(parts.items()):
        attrs = {'POSITION': lib.array(part.vertices, 'VEC3', bounds=True),
                 'NORMAL': lib.array(part.normals, 'VEC3'),
                 'COLOR_0': lib.array(part.colors, 'VEC3', 'B', normalized=True)}
        if part.texture:
            assert len(part.uv) == len(part.vertices), name
            attrs['TEXCOORD_0'] = lib.array(part.uv, 'VEC2')
        assert len(part.vertices) <= 65535, name
        primitive = {'attributes': attrs, 'material': textures.index(part.texture)+1 if part.texture else 0,
                     'indices': lib.array(part.indices, 'SCALAR', 'H')}
        if name == 'CeilingLights':
            primitive['material'] = lamp_material
        doc['meshes'].append({'name': name, 'primitives': [primitive]})
        doc['nodes'].append({'name': name, 'mesh': index})
    lib.save(path)
