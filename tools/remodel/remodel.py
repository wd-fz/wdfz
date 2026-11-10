#!/usr/bin/env python3
"""Rebuild the figures as one continuous surface from the old build's own primitives.

  python3 tools/remodel/capture_primitives.py --old <wd-fz.github.io checkout>   # once: primitives/*.json
  python3 tools/remodel/remodel.py                                                # writes assets/campus/figures, patrol

The old build lays a person out as sixty-odd ellipsoids, tapered rods and bevelled blocks (model/figure.js). Meshed one
by one they meet in hard seams. Here the same primitives, with the same positions and radii, are treated as signed
distance fields and joined with a smooth union; the zero surface is extracted with marching cubes, simplified, and
given normals from the field's gradient. Proportions, heights and poses are the old build's; only the surface changes.

Needs numpy, scikit-image and fast-simplification (development machines only; nothing here runs in the game).
"""
import argparse
import json
import struct
from pathlib import Path

import fast_simplification
import numpy as np
from skimage import measure

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
KINDS = ['tall', 'roam', 'person', 'teacher', 'neck', 'sit']
VOXEL = 0.003            # 3 mm: a finger (8 mm radius) is still a few cells thick
TARGET_TRIS = {'sit': 9000}
DEFAULT_TRIS = 10000


# ---- signed distance of one primitive at points p (N x 3), and the radius it blends over ----

def prim_field(prim):
    t, a = prim['t'], prim['a']
    if t == 'rod':
        p0, p1, r0, r1 = np.array(a[0:3]), np.array(a[3:6]), float(a[6]), float(a[7])
        ab = p1 - p0
        ll = float(ab @ ab) or 1e-12

        def f(p):
            h = np.clip(((p - p0) @ ab) / ll, 0.0, 1.0)
            return np.linalg.norm(p - (p0 + h[:, None] * ab), axis=1) - (r0 + (r1 - r0) * h)
        lo = np.minimum(p0, p1) - max(r0, r1)
        hi = np.maximum(p0, p1) + max(r0, r1)
        return f, lo, hi, blend_radius(min(r0, r1), True), 0.0
    if t == 'blob':
        c, r = np.array(a[0:3]), np.array(a[3:6], dtype=float)

        def f(p):
            q = p - c
            k0 = np.linalg.norm(q / r, axis=1)
            k1 = np.linalg.norm(q / (r * r), axis=1)
            return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
        return f, c - r, c + r, blend_radius(float(r.min()), False), float(r.min())
    if t in ('bevel', 'box'):
        c, half = np.array(a[0:3]), np.array(a[3:6], dtype=float) / 2.0
        rad = float(a[8]) if t == 'bevel' and len(a) > 8 and a[8] is not None else (0.02 if t == 'bevel' else 0.0)
        rad = min(rad, float(half.min()) * 0.6)

        def f(p):
            q = np.abs(p - c) - (half - rad)
            return np.linalg.norm(np.maximum(q, 0.0), axis=1) + np.minimum(q.max(axis=1), 0.0) - rad
        return f, c - half, c + half, blend_radius(float(half.min()), False), float(half.min())
    if t == 'cyl':
        base, rb, rt, h = np.array(a[0:3]), float(a[3]), float(a[4]), float(a[5])

        def f(p):
            q = p - base
            k = np.clip(q[:, 1] / h, 0.0, 1.0)
            dr = np.hypot(q[:, 0], q[:, 2]) - (rb + (rt - rb) * k)
            dy = np.abs(q[:, 1] - h / 2.0) - h / 2.0
            return np.minimum(np.maximum(dr, dy), 0.0) + np.hypot(np.maximum(dr, 0.0), np.maximum(dy, 0.0))
        r = max(rb, rt)
        return f, base - np.array([r, 0, r]), base + np.array([r, h, r]), blend_radius(min(rb, rt, h / 2.0), False), float(min(rb, rt, h / 2.0))
    raise ValueError(t)


def blend_radius(small, rod):
    """How far a primitive melts into its neighbours. Rods are limbs and fingers: they keep their own shape (a finger
    hardly blends at all). Ellipsoids and blocks are the masses of the body and the swells on it (chest, hip, knee,
    chin, nose): they blend wide, so chest, waist and coat hem run into one another instead of stacking up."""
    if rod:
        return float(np.clip(small * 0.6, 0.004, 0.03))
    # Small swells (brow, nose, ears, chin) melt into the head as relief; they must not stand on it as lumps.
    return float(np.clip(small * 0.8, 0.024, 0.075))


## A smooth union swells where two shapes overlap (by up to k / 4). The masses that only exist to overlap their
## neighbours (joints, chest on abdomen, chin on head) are drawn in by that much first (never by more than a quarter
## of their own smallest radius), so a knee does not end up thicker than the thigh above it; limbs keep their radii.
SWELL = 0.25


def smin(a, b, k):
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


class Field:
    def __init__(self, prims):
        self.parts = []
        for prim in prims:
            self.parts.append(prim_field(prim))
        self.lo = np.min([p[1] for p in self.parts], axis=0) - 0.02
        self.hi = np.max([p[2] for p in self.parts], axis=0) + 0.02

    def at(self, pts):
        """Field value at arbitrary points (used for normals and occlusion)."""
        d = np.full(len(pts), 1e3)
        for f, lo, hi, k, mass in self.parts:
            near = np.all((pts > lo - 0.08) & (pts < hi + 0.08), axis=1)
            if near.any():
                d[near] = smin(d[near], f(pts[near]) + min(k, mass) * SWELL, k)
        return d

    def grid(self, voxel):
        n = np.ceil((self.hi - self.lo) / voxel).astype(int) + 1
        vol = np.full(tuple(n), 1e3, dtype=np.float32)
        axes = [self.lo[i] + np.arange(n[i]) * voxel for i in range(3)]
        for f, lo, hi, k, mass in self.parts:
            a = np.maximum(np.floor((lo - 0.05 - self.lo) / voxel).astype(int), 0)
            b = np.minimum(np.ceil((hi + 0.05 - self.lo) / voxel).astype(int) + 1, n)
            gx, gy, gz = np.meshgrid(axes[0][a[0]:b[0]], axes[1][a[1]:b[1]], axes[2][a[2]:b[2]], indexing='ij')
            pts = np.stack([gx.ravel(), gy.ravel(), gz.ravel()], axis=1)
            block = vol[a[0]:b[0], a[1]:b[1], a[2]:b[2]]
            block[...] = smin(block.ravel().astype(np.float64), f(pts) + min(k, mass) * SWELL, k).reshape(block.shape)
        return vol


def faceless(prims, spec, sit):
    """The user's choice for the rebuilt figures: a smooth head with no face. The old layout puts a brow ridge, a nose
    and two ears on the head as small ellipsoids; blended into one surface they pinch into a hollow that reads as a
    damaged face. They are left out (skull, hair mass, chin and jaw stay), so the head is a plain rounded shape."""
    head = float(spec['head'])
    hy = (0.535 if sit else float(spec['leg'])) + float(spec['torso']) + float(spec['neck']) + head * 0.5
    keep = []
    for prim in prims:
        a = prim['a']
        if prim['t'] == 'blob' and abs(a[1] - hy) < head * 0.6 and a[3] * a[4] * a[5] < 0.002 * head ** 3:
            continue
        keep.append(prim)
    return keep


def build(prims, voxel, target_tris):
    field = Field(prims)
    vol = field.grid(voxel)
    verts, faces, _, _ = measure.marching_cubes(vol, level=0.0, spacing=(voxel, voxel, voxel))
    verts = verts + field.lo
    verts, faces = fast_simplification.simplify(verts.astype(np.float32), faces.astype(np.int32), target_count=target_tris)
    verts = verts.astype(np.float64)
    # Normals: the field's gradient (central differences), so shading is smooth whatever the triangle layout.
    e = 0.002
    grad = np.stack([field.at(verts + np.eye(3)[i] * e) - field.at(verts - np.eye(3)[i] * e) for i in range(3)], axis=1)
    normals = grad / np.maximum(np.linalg.norm(grad, axis=1, keepdims=True), 1e-9)
    # Triangles wound to face outwards (counter-clockwise seen from outside, as glTF expects).
    fn = np.cross(verts[faces[:, 1]] - verts[faces[:, 0]], verts[faces[:, 2]] - verts[faces[:, 0]])
    flip = np.einsum('ij,ij->i', fn, normals[faces].mean(axis=1)) < 0
    faces[flip] = faces[flip][:, ::-1]
    # A soft baked shade in the creases (armpits, between fingers, under the chin), kept as vertex colour like the
    # old models' baked shades: how open the surface is a few centimetres out along the normal.
    occ = np.ones(len(verts))
    for step, weight in ((0.012, 0.5), (0.03, 0.3), (0.06, 0.2)):
        occ -= weight * (1.0 - np.clip(field.at(verts + normals * step) / step, 0.0, 1.0))
    shade = 0.55 + 0.45 * np.clip(occ, 0.0, 1.0)
    return verts.astype(np.float32), normals.astype(np.float32), np.repeat(shade[:, None], 3, axis=1).astype(np.float32), faces.astype(np.uint32)


# ---- minimal glTF binary writer / reader ----

def _pad(b, fill=b'\x00'):
    return b + fill * ((4 - len(b) % 4) % 4)


def write_glb(path, name, meshes):
    """meshes: [{'name', 'pos', 'nrm', 'col', 'idx', 'color': [r, g, b] base colour (unlit, vertex colours on)}]"""
    blob = b''
    views, accessors, gl_meshes, materials, nodes = [], [], [], [], []

    def add(data, target, comp, kind, minmax=None):
        nonlocal blob
        raw = data.tobytes()
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(raw), 'target': target})
        blob = _pad(blob + raw)
        acc = {'bufferView': len(views) - 1, 'componentType': comp, 'count': int(data.shape[0]) if kind != 'SCALAR' else int(data.size), 'type': kind}
        if minmax is not None:
            acc['min'], acc['max'] = [float(v) for v in minmax[0]], [float(v) for v in minmax[1]]
        accessors.append(acc)
        return len(accessors) - 1

    for i, m in enumerate(meshes):
        attrs = {'POSITION': add(m['pos'], 34962, 5126, 'VEC3', (m['pos'].min(axis=0), m['pos'].max(axis=0))),
                 'NORMAL': add(m['nrm'], 34962, 5126, 'VEC3'), 'COLOR_0': add(m['col'], 34962, 5126, 'VEC3')}
        idx = add(m['idx'].reshape(-1), 34963, 5125, 'SCALAR')
        materials.append({'name': m.get('material', 'MeshBasicMaterial'), 'extensions': {'KHR_materials_unlit': {}},
                          'pbrMetallicRoughness': {'baseColorFactor': list(m.get('color', [1, 1, 1])) + [1.0], 'metallicFactor': 0.0, 'roughnessFactor': 1.0}})
        gl_meshes.append({'name': m['name'], 'primitives': [{'attributes': attrs, 'indices': idx, 'material': i}]})
        nodes.append({'name': m['name'], 'mesh': i})
    doc = {'asset': {'version': '2.0', 'generator': 'wdfz tools/remodel'}, 'scene': 0,
           'scenes': [{'name': name, 'nodes': [len(nodes)]}],
           'nodes': nodes + [{'name': name, 'children': list(range(len(nodes)))}],
           'meshes': gl_meshes, 'materials': materials, 'extensionsUsed': ['KHR_materials_unlit'],
           'accessors': accessors, 'bufferViews': views, 'buffers': [{'byteLength': len(blob)}]}
    js = _pad(json.dumps(doc, separators=(',', ':')).encode(), b' ')
    out = struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(js) + 8 + len(blob)) + struct.pack('<I4s', len(js), b'JSON') + js + struct.pack('<I4s', len(blob), b'BIN\x00') + blob
    Path(path).write_bytes(out)


def read_glb(path):
    raw = Path(path).read_bytes()
    n = struct.unpack('<I', raw[12:16])[0]
    doc = json.loads(raw[20:20 + n])
    blob = raw[20 + n + 8:]
    comp = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}

    def acc(i):
        a = doc['accessors'][i]
        v = doc['bufferViews'][a['bufferView']]
        off = v.get('byteOffset', 0) + a.get('byteOffset', 0)
        dt, w = comp[a['componentType']], width[a['type']]
        stride = v.get('byteStride')
        if stride and stride != np.dtype(dt).itemsize * w:
            rows = [np.frombuffer(blob, dt, w, off + k * stride) for k in range(a['count'])]
            return np.array(rows)
        return np.frombuffer(blob, dt, a['count'] * w, off).reshape(a['count'], w)
    return doc, acc


def bounds(path):
    doc, _ = read_glb(path)
    lo, hi = np.full(3, 1e9), np.full(3, -1e9)
    for m in doc['meshes']:
        for p in m['primitives']:
            a = doc['accessors'][p['attributes']['POSITION']]
            lo, hi = np.minimum(lo, a['min']), np.maximum(hi, a['max'])
    return lo, hi


def srgb_to_linear(c):
    """glTF base colours are linear; the old build gives its colours in sRGB."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def old_gear(path):
    """The patroller's coat and cap from the existing model (second mesh): kept as it is."""
    doc, acc = read_glb(path)
    for m in doc['meshes'][1:]:
        p = m['primitives'][0]
        mat = doc['materials'][p['material']]
        col = acc(p['attributes']['COLOR_0'])[:, :3].astype(np.float32) if 'COLOR_0' in p['attributes'] else None
        pos = acc(p['attributes']['POSITION']).astype(np.float32)
        if col is not None and col.max() > 1.5:
            col = col / (255.0 if col.max() <= 255 else 65535.0)
        return {'name': m.get('name', 'patrol_figure_m1'), 'pos': pos, 'nrm': acc(p['attributes']['NORMAL']).astype(np.float32),
                'col': col if col is not None else np.ones_like(pos), 'idx': acc(p['indices']).reshape(-1, 3).astype(np.uint32),
                'color': mat.get('pbrMetallicRoughness', {}).get('baseColorFactor', [1, 1, 1, 1])[:3], 'material': mat.get('name', 'MeshBasicMaterial')}
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', default='', help='comma separated kinds')
    ap.add_argument('--voxel', type=float, default=VOXEL)
    ap.add_argument('--out', default=str(REPO / 'assets' / 'campus'))
    a = ap.parse_args()
    out = Path(a.out)
    want = [k for k in KINDS if not a.only or k in a.only.split(',')]
    built = {}
    for kind in want:
        data = json.loads((HERE / 'primitives' / f'figure_{kind}.json').read_text())
        prims = faceless(data['prims'], data['spec'], kind == 'sit')
        pos, nrm, col, idx = build(prims, a.voxel, TARGET_TRIS.get(kind, DEFAULT_TRIS))
        built[kind] = (pos, nrm, col, idx)
        target = out / 'figures' / f'{kind}.glb'
        old = bounds(target) if target.exists() else None
        target.parent.mkdir(parents=True, exist_ok=True)
        write_glb(target, f'figure_{kind}', [{'name': f'figure_{kind}_m0', 'pos': pos, 'nrm': nrm, 'col': col, 'idx': idx}])
        lo, hi = pos.min(axis=0), pos.max(axis=0)
        note = ''
        if old is not None:
            note = '  old height %.3f, width %.3f, depth %.3f' % (old[1][1], old[1][0] - old[0][0], old[1][2] - old[0][2])
        print('%-8s %5d verts %5d tris  height %.3f, width %.3f, depth %.3f%s' % (kind, len(pos), len(idx), hi[1], hi[0] - lo[0], hi[2] - lo[2], note))
    if 'teacher' in built and (not a.only or 'patrol' in a.only.split(',') or 'teacher' in a.only.split(',')):
        # The patroller: the teacher's build at 1.12, in near-black, wearing the old coat and cap.
        target = out / 'patrol' / 'patrol_figure.glb'
        gear = old_gear(target)
        pos, nrm, col, idx = built['teacher']
        meshes = [{'name': 'patrol_figure_m0', 'pos': (pos * 1.12).astype(np.float32), 'nrm': nrm, 'col': col, 'idx': idx, 'color': [srgb_to_linear(v / 255.0) for v in (0x04, 0x05, 0x06)]}]
        if gear is not None:
            meshes.append(gear)
        write_glb(target, 'patrol_figure', meshes)
        print('patrol   body %d tris%s' % (len(idx), ', coat and cap kept (%d tris)' % len(gear['idx']) if gear else ''))


if __name__ == '__main__':
    main()
