#!/usr/bin/env python3
"""Dressed figures for the death stages: the rebuilt figure with clothes over it.

  python3 tools/remodel/dress.py            # writes assets/campus/figures/dressed/{person,sit,teacher,roam}.glb

The rebuilt figures (remodel.py) are one smooth body with no clothes: lit up close they read as a painted mannequin.
Here the same old-build primitives give the body, and the clothes are distance fields laid over it: each garment is
the body part it covers, inflated by the cloth's thickness and cut where the garment ends. The cut edges are what
make clothes read as clothes (a hem, a cuff, a collar standing off the neck, a zip), so they are kept crisp.

  person, sit   the school tracksuit: zip jacket with a stand collar and a stripe down each sleeve, trousers with a
                side stripe, trainers
  teacher       a jacket open in a V over a shirt and a tie, trousers, shoes
  roam          a long coat to below the knee with a turned-up collar, trousers, shoes

Each garment is a separate mesh in the GLB (skin, jacket, trim, trousers, shoes; the teacher adds shirt) so the game
can give each its own material. Proportions are the old build's: nothing is moved, only covered. The faceless head
is kept as skin (the death stages put their own head on the neck). Vertex colour is a baked crease shade as in
remodel.py. Development machines only; nothing here runs in the game.
"""
import argparse
import json
from pathlib import Path

import fast_simplification
import numpy as np
from skimage import measure

from remodel import Field, HERE, REPO, faceless, write_glb, srgb_to_linear

KINDS = ['person', 'sit', 'teacher', 'roam']
TARGET_TRIS = 20000
VOXEL_DRESSED = 0.002   # 2 mm: hems, the zip and the collar edge stay straight
LABELS = ['skin', 'jacket', 'trim', 'zip', 'trousers', 'shoes', 'shirt']
# Base colours in the GLB (the game overrides them; they only make the file readable in a viewer).
COLOURS = {'skin': 0xb9aea0, 'jacket': 0x2b3a5c, 'trim': 0xd8d8d0, 'zip': 0x4a5060, 'trousers': 0x23283a, 'shoes': 0x1a1a1a, 'shirt': 0xd9d6cc}


def roles(prims):
    """Split the old figure's primitives by what they are. figGeo() always emits them in the same order (legs and
    feet, pelvis, torso, shoulders, neck, head, then each arm followed by its hand); the split is by that order and
    by size, never by a hard-coded index, so the seated layout (fewer pelvis parts) is handled the same way."""
    out = {'shoes': [], 'legs': [], 'body': [], 'neck': None, 'head': [], 'arms': [[], []], 'hands': [[], []]}
    neck = None
    for i, p in enumerate(prims):
        a = p['a']
        if p['t'] == 'rod' and i >= 16 and abs(a[0]) < 0.01 and abs(a[3]) < 0.01 and a[6] > 0.03:
            neck = i
            break
    out['neck'] = prims[neck]
    side = 0
    seen_arm = False
    for i, p in enumerate(prims):
        a = p['a']
        if i < 16:
            top = a[1] + (a[4] / 2.0 if p['t'] in ('bevel', 'box') else (a[4] if p['t'] == 'blob' else 0.0))
            if p['t'] == 'rod':
                top = max(a[1], a[4])
            (out['shoes'] if top < 0.1 else out['legs']).append(p)
        elif i < neck:
            out['body'].append(p)
        elif i == neck:
            continue
        else:
            big = (p['t'] == 'rod' and max(a[6], a[7]) >= 0.03) or (p['t'] == 'blob' and min(a[3:6]) >= 0.03 and abs(a[0]) > 0.1)
            near_axis = abs(a[0]) < 0.06 and (p['t'] != 'rod' or abs(a[3]) < 0.06)
            if not seen_arm and near_axis:
                out['head'].append(p)
                continue
            x = a[0]
            side = 0 if x < 0 else 1
            if big:
                seen_arm = True
                out['arms'][side].append(p)
            else:
                out['hands'][side].append(p)
    return out


def rod_axis(p):
    a = p['a']
    return np.array(a[0:3], float), np.array(a[3:6], float), float(a[6]), float(a[7])


class Garment:
    """One piece of the outfit: a field, a label, and cuts. The field is a group of body primitives inflated by
    thickness (plus a small fold ripple); cuts are half-space SDFs intersected with it."""

    def __init__(self, label, prims, thick, cuts=(), fold=0.0, extra=None):
        self.label = label
        self.field = Field(prims) if prims else None
        self.thick = thick
        self.cuts = list(cuts)
        self.fold = fold
        self.extra = extra

    def at(self, p):
        d = self.field.at(p) - self.thick if self.field is not None else np.full(len(p), 1e3)
        if self.extra is not None:
            d = np.minimum(d, self.extra(p))
        if self.fold:
            # Soft horizontal folds that wander a little around the limb: cloth bunching, not a pattern.
            x, y, z = p[:, 0], p[:, 1], p[:, 2]
            wobble = np.sin(y * 150.0 + 2.2 * np.sin(x * 31.0 + z * 23.0)) * (0.55 + 0.45 * np.sin(x * 17.0 - y * 9.0 + z * 13.0))
            d = d - self.fold * wobble
        for cut in self.cuts:
            d = np.maximum(d, cut(p))
        return d


def stripe(rods, sgn, half):
    """A band down the outside of a limb: points whose offset from the limb's axis points outwards (sgn along x)
    and lies within half of the outward line, measured across the limb."""
    segs = [rod_axis(q)[:2] for q in rods]

    def f(p):
        best = np.full(len(p), 1e9)
        across = np.zeros(len(p))
        out = np.zeros(len(p))
        for a, b in segs:
            ab = b - a
            h = np.clip(((p - a) @ ab) / float(ab @ ab), 0.0, 1.0)
            radial = p - (a + h[:, None] * ab)
            dist = np.linalg.norm(radial, axis=1)
            axis = ab / np.linalg.norm(ab)
            side = np.cross(axis, [sgn, 0.0, 0.0])
            side = side / max(np.linalg.norm(side), 1e-9)
            outward = np.cross(side, axis)
            outward = outward if outward[0] * sgn > 0 else -outward
            closer = dist < best
            best[closer] = dist[closer]
            across[closer] = np.abs(radial[closer] @ side)
            out[closer] = radial[closer] @ outward
        return np.maximum(across - half, -out)
    return f


def plane_cut(point, normal):
    """Keep the side the normal points to."""
    point, normal = np.asarray(point, float), np.asarray(normal, float) / np.linalg.norm(normal)
    return lambda p: -((p - point) @ normal)


def collar(base, axis, radius, height, wall, front_open):
    """A stand collar: a short tube round the neck, off the skin by a finger, open at the front by front_open
    (the half angle in degrees; 0 = closed)."""
    base, axis = np.asarray(base, float), np.asarray(axis, float) / np.linalg.norm(axis)
    front = np.array([0.0, 0.0, 1.0]) - axis * axis[2]
    front /= np.linalg.norm(front)
    cos_open = np.cos(np.radians(front_open)) if front_open > 0 else 2.0

    def f(p):
        q = p - base
        h = q @ axis
        radial = q - h[:, None] * axis
        r = np.linalg.norm(radial, axis=1)
        d = np.maximum(np.abs(r - radius) - wall, np.abs(h - height / 2.0) - height / 2.0)
        facing = (radial @ front) / np.maximum(r, 1e-6)
        return np.maximum(d, (facing - cos_open) * 0.06)
    return f


def emergence(body_prims, neck):
    """Where the neck leaves the body: the lowest point on the neck's axis whose ring is outside the torso."""
    p0, p1, r0, r1 = rod_axis(neck)
    torso = Field(body_prims)
    axis = (p1 - p0) / np.linalg.norm(p1 - p0)
    side = np.cross(axis, [0.0, 0.0, 1.0])
    side /= np.linalg.norm(side)
    for s in np.linspace(0.0, 1.0, 200):
        c = p0 + (p1 - p0) * s
        ring = np.array([c + (side * np.cos(t) + np.cross(axis, side) * np.sin(t)) * (r0 + 0.006) for t in np.linspace(0, 2 * np.pi, 12, endpoint=False)])
        if (torso.at(ring) > 0).all():
            return c, axis, r0
    return p1, axis, r1


def outfit(kind, prims, spec):
    r = roles(prims)
    sit = kind == 'sit'
    hip = 0.55 if sit else float(spec['leg'])
    neck_base, neck_axis, neck_r = emergence(r['body'], r['neck'])
    shoe_top = 0.0
    for p in r['shoes']:
        a = p['a']
        shoe_top = max(shoe_top, a[1] + (a[4] / 2.0 if p['t'] in ('bevel', 'box') else a[4]))
    pieces = []
    # Sleeves end a little short of the wrist so the cuff stands off it; the hand stays skin.
    sleeve_end = 0.86 if kind != 'roam' else 0.9
    for side in (0, 1):
        arm = r['arms'][side]
        last = [p for p in arm if p['t'] == 'rod'][-1]
        p0, p1, _, _ = rod_axis(last)
        end = p0 + (p1 - p0) * sleeve_end
        cut = plane_cut(end, p0 - p1)
        pieces.append(Garment('jacket', arm, 0.009 if kind != 'roam' else 0.016, [cut], fold=0.0016))
        if kind in ('person', 'sit'):
            # The tracksuit's stripe runs down the outside of each sleeve: a raised band 1.8 cm wide.
            pieces.append(Garment('trim', arm, 0.0115, [cut, stripe([q for q in arm if q['t'] == 'rod'], -1.0 if side == 0 else 1.0, 0.009)]))
    # Jacket body: torso, shoulders and the top of the pelvis, down to the hem.
    hem = {'person': hip - 0.035, 'sit': hip + 0.02, 'teacher': hip - 0.11, 'roam': None}[kind]
    torso_thick = {'person': 0.011, 'sit': 0.011, 'teacher': 0.011, 'roam': 0.02}[kind]
    torso_cuts = [plane_cut([0, hem, 0], [0, 1, 0])] if hem is not None else []
    collar_h = {'person': 0.05, 'sit': 0.05, 'teacher': 0.0, 'roam': 0.085}[kind]
    if kind == 'roam':
        # A long coat: the body plus a skirt that hangs from the hips over both legs to below the knee.
        knee = [p for p in r['legs'] if p['t'] == 'blob'][0]['a'][1]
        coat_hem = knee - 0.09
        legs_top = Field(r['legs'])
        width = max(abs(p['a'][0]) for p in r['legs']) + 0.1

        def skirt(p, top=hip + 0.05, bottom=coat_hem, width=width):
            t = np.clip((top - p[:, 1]) / (top - bottom), 0.0, 1.0)
            rx, rz = width + 0.03 * t, 0.15 + 0.03 * t
            e = np.sqrt((p[:, 0] / rx) ** 2 + ((p[:, 2] - 0.005) / rz) ** 2) - 1.0
            d = e * min(rx.min(), rz.min()) if hasattr(rx, 'min') else e * 0.15
            return np.maximum(np.maximum(d, p[:, 1] - top), bottom - p[:, 1])
        pieces.append(Garment('jacket', r['body'], torso_thick, [], fold=0.0014, extra=lambda p: np.maximum(legs_top.at(p) - 0.03, -np.minimum(0, 0) + (coat_hem - p[:, 1]))))
        pieces.append(Garment('jacket', [], 0.0, [], fold=0.0012, extra=skirt))
    elif kind == 'teacher':
        # The jacket opens in a V from the collar to mid chest; inside it the shirt and a tie.
        top = neck_base[1] + 0.01
        v_bottom = top - 0.3

        def v_open(p, top=top, v_bottom=v_bottom):
            w = np.clip((p[:, 1] - v_bottom) / (top - v_bottom), 0.0, 1.0) * 0.11
            inside = np.maximum(np.maximum(np.abs(p[:, 0]) - w, v_bottom - p[:, 1]), -p[:, 2])
            return -inside
        pieces.append(Garment('jacket', r['body'], torso_thick, torso_cuts + [v_open], fold=0.0012))
        pieces.append(Garment('shirt', r['body'], 0.006, [plane_cut([0, v_bottom - 0.02, 0], [0, 1, 0]), plane_cut([0, 0, 0.0], [0, 0, 1])]))
        tie = lambda p, top=top, v_bottom=v_bottom: np.maximum(np.maximum(np.abs(p[:, 0]) - (0.018 + 0.012 * np.clip((top - p[:, 1]) / 0.3, 0, 1)), np.abs(p[:, 1] - (top + v_bottom) / 2 + 0.01) - (top - v_bottom) / 2), -p[:, 2])
        pieces.append(Garment('trim', r['body'], 0.0095, [tie]))
        # A shirt collar: low, closed, white.
        pieces.append(Garment('shirt', [], 0.0, [], extra=collar(neck_base - neck_axis * 0.01, neck_axis, neck_r + 0.009, 0.035, 0.004, 22)))
    else:
        pieces.append(Garment('jacket', r['body'], torso_thick, torso_cuts, fold=0.0013))
        # The zip: a raised strip down the front centre of the jacket, from the collar to the hem.
        zip_cut = [lambda p: np.abs(p[:, 0]) - 0.008, lambda p: -p[:, 2]] + torso_cuts
        # Flush with the cloth (a fraction of a millimetre proud, following the same folds): a raised strip
        # would step along the voxel grid.
        pieces.append(Garment('zip', r['body'], torso_thick + 0.0006, zip_cut, fold=0.0013))
    if collar_h:
        pieces.append(Garment('jacket', [], 0.0, [], extra=collar(neck_base - neck_axis * 0.012, neck_axis, neck_r + (0.03 if kind == 'roam' else 0.017), collar_h, 0.0055, 0 if kind == 'roam' else 14)))
    # Trousers: legs and pelvis, from the waist down to just above the shoe.
    pelvis = [p for p in r['body'] if p['a'][1] < hip + 0.08]
    waist = [plane_cut([0, hip + 0.1, 0], [0, -1, 0])]
    pieces.append(Garment('trousers', r['legs'] + pelvis, 0.011, [plane_cut([0, shoe_top + 0.012, 0], [0, 1, 0])] + waist, fold=0.0019))
    if kind == 'person':
        for side in (0, 1):
            leg = [q for q in r['legs'] if (q['a'][0] < 0) == (side == 0)]
            pieces.append(Garment('trim', leg, 0.0135, [plane_cut([0, shoe_top + 0.012, 0], [0, 1, 0]), plane_cut([0, hip - 0.04, 0], [0, -1, 0]),
                                                        stripe([q for q in leg if q['t'] == 'rod'], -1.0 if side == 0 else 1.0, 0.008)]))
    pieces.append(Garment('shoes', r['shoes'], 0.006))
    return pieces


def clip(verts, faces, side):
    """The part of a triangle mesh where side < 0 (side given per vertex, linear along edges). Returns
    (positions, triangles) with the cut vertices added and unused vertices dropped."""
    inside = side < 0
    count = inside[faces].sum(axis=1)
    keep = [faces[count == 3]]
    pos = [verts]
    cut = {}
    extra = []

    def at(i, j):
        key = (min(i, j), max(i, j))
        if key not in cut:
            t = side[i] / (side[i] - side[j])
            extra.append(verts[i] + (verts[j] - verts[i]) * t)
            cut[key] = len(verts) + len(extra) - 1
        return cut[key]
    new = []
    for f in faces[(count > 0) & (count < 3)]:
        ins = [bool(inside[v]) for v in f]
        # Rotate so the odd vertex out is first, keeping the winding.
        k = ins.index(True) if sum(ins) == 1 else ins.index(False)
        a, b, c = f[k], f[(k + 1) % 3], f[(k + 2) % 3]
        ab, ac = at(a, b), at(a, c)
        if sum(ins) == 1:
            new.append([a, ab, ac])
        else:
            new.append([ab, b, c])
            new.append([ab, c, ac])
    if extra:
        pos.append(np.array(extra))
    if new:
        keep.append(np.array(new, dtype=faces.dtype))
    allpos = np.concatenate(pos)
    tris = np.concatenate(keep) if keep else np.zeros((0, 3), dtype=faces.dtype)
    used, inverse = np.unique(tris.reshape(-1), return_inverse=True)
    return allpos[used], inverse.reshape(-1, 3)


class Dressed:
    def __init__(self, body_prims, pieces):
        self.body = Field(body_prims)
        self.pieces = pieces
        self.lo = self.body.lo - 0.05
        self.hi = self.body.hi + 0.05

    def parts(self, p):
        return [self.body.at(p)] + [g.at(p) for g in self.pieces]

    def at(self, p):
        return np.min(self.parts(p), axis=0)


def build(kind, voxel):
    data = json.loads((HERE / 'primitives' / f'figure_{kind}.json').read_text())
    prims = faceless(data['prims'], data['spec'], kind == 'sit')
    field = Dressed(prims, outfit(kind, prims, data['spec']))
    n = np.ceil((field.hi - field.lo) / voxel).astype(int) + 1
    axes = [field.lo[i] + np.arange(n[i]) * voxel for i in range(3)]
    vol = np.empty(tuple(n), dtype=np.float32)
    for i in range(n[0]):
        gy, gz = np.meshgrid(axes[1], axes[2], indexing='ij')
        pts = np.stack([np.full(gy.size, axes[0][i]), gy.ravel(), gz.ravel()], axis=1)
        vol[i] = field.at(pts).reshape(gy.shape)
    verts, faces, _, _ = measure.marching_cubes(vol, level=0.0, spacing=(voxel, voxel, voxel))
    verts = verts + field.lo
    verts, faces = fast_simplification.simplify(verts.astype(np.float32), faces.astype(np.int32), target_count=TARGET_TRIS)
    verts = verts.astype(np.float64)
    # Each garment is cut out of the surface along the line where it stops being the outermost layer: the cut
    # runs through the triangles (values interpolated along their edges), so a zip or a hem has a clean edge
    # instead of the saw-tooth of whole triangles.
    labels = ['skin'] + [g.label for g in field.pieces]
    parts = np.array(field.parts(verts))
    parts[0] += 0.001     # a garment within a millimetre of the skin is the surface there
    per_label = {}
    for name in LABELS:
        rows = [i for i, l in enumerate(labels) if l == name]
        if rows:
            per_label[name] = parts[rows].min(axis=0)
    meshes = []
    for label, own in per_label.items():
        others = [v for k, v in per_label.items() if k != label]
        side = own - (np.min(others, axis=0) if others else np.full(len(own), 1e3))
        pos, idx = clip(verts, faces, side)
        if not len(idx):
            continue
        e = 0.0015
        grad = np.stack([field.at(pos + np.eye(3)[i] * e) - field.at(pos - np.eye(3)[i] * e) for i in range(3)], axis=1)
        nrm = grad / np.maximum(np.linalg.norm(grad, axis=1, keepdims=True), 1e-9)
        fn = np.cross(pos[idx[:, 1]] - pos[idx[:, 0]], pos[idx[:, 2]] - pos[idx[:, 0]])
        flip = np.einsum('ij,ij->i', fn, nrm[idx].mean(axis=1)) < 0
        idx[flip] = idx[flip][:, ::-1]
        occ = np.ones(len(pos))
        for step, weight in ((0.008, 0.45), (0.02, 0.3), (0.05, 0.25)):
            occ -= weight * (1.0 - np.clip(field.at(pos + nrm * step) / step, 0.0, 1.0))
        shade = (0.5 + 0.5 * np.clip(occ, 0.0, 1.0)).astype(np.float32)
        c = COLOURS[label]
        meshes.append({'name': f'dressed_{kind}_{label}', 'pos': pos.astype(np.float32), 'nrm': nrm.astype(np.float32),
                       'col': np.repeat(shade[:, None], 3, axis=1), 'idx': idx.astype(np.uint32),
                       'color': [srgb_to_linear(((c >> s) & 255) / 255.0) for s in (16, 8, 0)], 'material': label})
    meshes.sort(key=lambda m: LABELS.index(m['material']))
    return meshes, verts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', default='')
    ap.add_argument('--voxel', type=float, default=VOXEL_DRESSED)
    ap.add_argument('--out', default=str(REPO / 'assets' / 'campus' / 'figures' / 'dressed'))
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for kind in [k for k in KINDS if not a.only or k in a.only.split(',')]:
        meshes, verts = build(kind, a.voxel)
        write_glb(out / f'{kind}.glb', f'dressed_{kind}', meshes)
        lo, hi = verts.min(axis=0), verts.max(axis=0)
        parts = ', '.join('%s %d' % (m['material'], len(m['idx'])) for m in meshes)
        print('%-8s height %.3f width %.3f depth %.3f  tris: %s' % (kind, hi[1], hi[0] - lo[0], hi[2] - lo[2], parts))


if __name__ == '__main__':
    main()
