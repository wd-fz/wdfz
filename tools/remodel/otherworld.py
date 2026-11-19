"""Bake the otherworld cast. Every body and articulated face has one opaque surface."""

import argparse
from math import cos, pi, sin
from pathlib import Path

import numpy as np

from student_cast import GLB, Mesh, ROOT, anatomy, color, posed_bones, quaternion, skeleton
from student_motion import CLIPS, pose

DEST = ROOT / "assets/campus/figures/otherworld"


def body(role, bones):
    m = Mesh(bones)
    adult = role in ("teacher", "patroller")
    patrol = role == "patroller"
    garage = role == "roam"
    coat = "272c31" if patrol else "30322f" if adult else "191d23" if garage else "37434d"
    stripe = "64595b" if adult else "65757a"
    linen = "70746a" if not garage else "353b39"

    def trunk(rows, fabric, bone="Chest"):
        m.rings(
            [(0, y, z, w, d, b) for y, w, d, z, b in rows],
            fabric,
            bone,
            20,
            lambda i, a: color(fabric) * (0.72 + 0.18 * cos(a - 0.55) + 0.09 * cos(5 * a)),
        )

    trunk([(0.848, 0.163, 0.111, 0, "Hips"), (0.96, 0.163, 0.12, 0, "Hips")], "24282d")
    bottom = 0.75 if adult else 0.925
    trunk(
        [
            (bottom, 0.188, 0.135, 0.008, "Hips"),
            (0.965, 0.173, 0.128, 0, "Hips"),
            (1.07, 0.155, 0.117, 0, "Spine"),
            (1.24, 0.178, 0.129, 0, "Chest"),
            (1.366, 0.207, 0.113, 0.004, "Chest"),
            (1.411, 0.164, 0.092, 0.004, "Chest"),
            (1.454, 0.071, 0.066, 0, "Neck"),
        ],
        coat,
    )
    m.rings(
        [(0, 1.438, 0, 0.06, 0.05), (0, 1.514, 0, 0.043, 0.041), (0, 1.55, 0, 0.045, 0.045)],
        "575b52",
        "Neck",
        12,
    )
    for s in (-1, 1):
        m.patch(
            [
                (s * 0.115, 1.415, -0.056),
                (s * 0.049, 1.46, -0.054),
                (s * 0.009, 1.382, -0.116),
                (s * 0.066, 1.359, -0.106),
            ],
            linen,
            "Chest",
        )
    m.tube(
        [[0, 1.383, -0.114], [0, 1.26, -0.13], [0.004, 1.13, -0.123], [0.006, 0.96, -0.132]],
        0.005,
        stripe,
        "Chest",
        5,
    )
    if adult:
        m.patch(
            [
                (-0.014, 1.393, -0.122),
                (0.018, 1.393, -0.122),
                (0.025, 1.229, -0.137),
                (0.003, 1.198, -0.136),
                (-0.019, 1.237, -0.133),
            ],
            "252325",
            "Chest",
        )
    else:
        m.patch(
            [(0.046, 1.292, -0.124), (0.134, 1.292, -0.096), (0.131, 1.261, -0.097), (0.046, 1.261, -0.128)],
            "b3b0a0",
            "Chest",
        )
        m.tube([[0.057, 1.276, -0.13], [0.118, 1.278, -0.107]], 0.003, "41484c", "Chest", 4)
    if patrol:
        m.tube(
            [[-0.081, 1.425, -0.083], [-0.044, 1.275, -0.139], [0.018, 1.174, -0.131], [0.105, 1.42, -0.084]],
            0.006,
            "8b886e",
            "Chest",
            6,
        )
        m.oval((0.018, 1.166, -0.142), (0.025, 0.037, 0.013), "9c9b83", "Chest", 9, 4)
    for suffix, s in [("L", 1), ("R", -1)]:
        arm, elbow, hand = "Arm" + suffix, "Elbow" + suffix, "Hand" + suffix
        thigh, knee, foot = "Thigh" + suffix, "Knee" + suffix, "Foot" + suffix

        def limb(rows, tint):
            m.rings([(s * x, y, z, w, d, b) for x, y, z, w, d, b in rows], tint, rows[0][-1], 12)

        limb(
            [
                (0.108, 0.112, 0.001, 0.044, 0.051, foot),
                (0.109, 0.24, 0.003, 0.054, 0.063, knee),
                (0.102, 0.485, -0.010, 0.061, 0.067, knee),
                (0.102, 0.63, 0.006, 0.076, 0.078, thigh),
                (0.095, 0.90, 0.011, 0.084, 0.092, thigh),
            ],
            "272b33",
        )
        m.oval((s * 0.108, 0.062, -0.049), (0.064, 0.056, 0.123), "29292b", foot, 12, 5)
        limb(
            [
                (0.264, 0.91, -0.025, 0.046, 0.05, elbow),
                (0.257, 1.023, -0.003, 0.053, 0.06, elbow),
                (0.249, 1.126, 0.002, 0.058, 0.058, elbow),
                (0.226, 1.27, 0.004, 0.065, 0.071, arm),
                (0.186, 1.392, 0.003, 0.087, 0.087, arm),
            ],
            coat,
        )
        limb(
            [(0.264, 0.902, -0.025, 0.047, 0.051, elbow), (0.262, 0.927, -0.023, 0.05, 0.053, elbow)], stripe
        )
        if not adult:
            m.tube(
                [[s * 0.208, 1.392, -0.066], [s * 0.255, 1.27, -0.057], [s * 0.278, 1.15, -0.041]],
                0.008,
                stripe,
                arm,
                5,
            )
        if patrol and suffix == "L":
            limb(
                [(0.228, 1.229, 0.004, 0.069, 0.075, arm), (0.216, 1.30, 0.004, 0.077, 0.080, arm)], "974540"
            )
            m.patch(
                [
                    (s * 0.211, 1.279, -0.080),
                    (s * 0.239, 1.273, -0.070),
                    (s * 0.231, 1.251, -0.074),
                    (s * 0.204, 1.26, -0.08),
                ],
                "b5a689",
                arm,
            )
        skin = "373a3b" if patrol or garage else "8b9084"
        m.oval((s * 0.265, 0.866, -0.033), (0.043, 0.064, 0.032), skin, hand, 12, 5)
        for j in range(4):
            x = s * (0.236 + j * 0.016)
            length = (0.077, 0.094, 0.089, 0.066)[j]
            m.tube(
                [
                    (x, 0.844, -0.046),
                    (x + s * (j - 1.3) * 0.004, 0.82, -0.06),
                    (x + s * (j - 1.3) * 0.006, 0.844 - length, -0.076),
                ],
                [0.009, 0.008, 0.004],
                skin,
                hand,
                6,
            )
        m.tube(
            [(s * 0.239, 0.878, -0.045), (s * 0.219, 0.846, -0.063), (s * 0.215, 0.828, -0.083)],
            [0.014, 0.011, 0.006],
            skin,
            hand,
            6,
        )
    return m


def face(role, source, alternate=False):
    m = Mesh({"Head": (None, np.zeros(3))})
    b = "Head"
    patrol = role == "patroller"
    teacher = role == "teacher"
    garage = role == "roam"
    skin = color("a2a494" if not garage else "4f554d")
    hair = "353834" if teacher else "292b2c"

    def gaussian(x, y):
        return np.exp(-x * x - y * y)

    def point(x, y, z):
        front = np.clip((z - 0.80) / 0.57, 0, 1)
        orbit = gaussian((abs(x) - 0.31) / 0.239, (y - 7.27) / 0.202)
        hollow = gaussian((abs(x) - 0.52) / 0.24, (y - 6.74) / 0.28)
        jaw = gaussian(x / 0.54, (y - 6.35) / 0.36)
        return np.array(
            [
                -x * 0.119 * (1 - 0.13 * hollow * front),
                (y - 6.18) * 0.118 - 0.024 * jaw + 0.007 * x * front,
                -(z - 0.42) * 0.102 + (0.012 * orbit + 0.014 * hollow + 0.008 * jaw) * front,
            ]
        )

    verts, faces = source
    used = {}
    for polygon in faces:
        coords = verts[polygon]
        if min(coords[:, 1]) < 5.83 or max(abs(coords[:, 0])) > 1.15:
            continue
        indices = []
        for idx in polygon:
            if idx not in used:
                x, y, z = verts[idx]
                front = np.clip((z - 0.7) / 0.6, 0, 1)
                orbit = gaussian((abs(x) - 0.31) / 0.27, (y - 7.26) / 0.23)
                cheek = gaussian((abs(x) - 0.53) / 0.31, (y - 6.77) / 0.29)
                lip = gaussian(x / 0.27, (y - 6.58) / 0.062)
                trail = gaussian((abs(x) - 0.33 - 0.062 * sin(13 * y + x)) / 0.052, (y - 6.98) / 0.32)
                shade = (0.83 + 0.07 * sin(17 * x + 11 * y) * cos(9 * y)) * (
                    1 - front * (0.88 * orbit + 0.34 * cheek + 0.69 * lip + 0.33 * trail)
                )
                used[idx] = m.vertex(point(x, y, z), skin * max(0.04, shade), b)
            indices.append(used[idx])
        for j in range(1, len(indices) - 1):
            m.tris.append((indices[0], indices[j], indices[j + 1]))
    # Merge nearby samples on the HM08 surface before adding the eyelids and hair.
    # The desks share this rigid mesh; no facial skeleton or texture is evaluated.
    skin_pos = np.array(m.vertices)
    cells, indices = np.unique(np.round(skin_pos / 0.0064).astype(int), axis=0, return_inverse=True)
    counts = np.bincount(indices)[:, None]
    positions = np.zeros((len(cells), 3))
    pigments = np.zeros_like(positions)
    np.add.at(positions, indices, skin_pos)
    np.add.at(pigments, indices, np.array(m.colors))
    triangles = indices[np.array(m.tris)]
    m = Mesh({"Head": (None, np.zeros(3))})
    for pos, tint in zip(positions / counts, pigments / counts):
        m.vertex(pos, tint, b)
    m.tris.extend(
        triangles[
            (triangles[:, 0] != triangles[:, 1])
            & (triangles[:, 1] != triangles[:, 2])
            & (triangles[:, 2] != triangles[:, 0])
        ].tolist()
    )

    def mark(points, width, tint):
        m.tube(points, width, tint, b, 6)

    for sign in (-1, 1):
        eye = point(sign * 0.31, 7.285, 1.265)
        cloudy = alternate and sign < 0
        m.oval(eye, (0.016, 0.014, 0.0155), "898e7c" if not cloudy else "aaa995", b, 16, 7)
        iris = eye + [0.0023 if not alternate else -0.002, 0.001, -0.015]
        m.oval(iris, (0.0068, 0.0074, 0.0012), "4f5047" if not cloudy else "8a8b7f", b, 13, 5)
        m.oval(
            iris + [0.001, 0, -0.0012],
            (0.0033, 0.0043, 0.0008),
            "242a25" if not cloudy else "676e60",
            b,
            10,
            5,
        )
        m.oval(iris + [0.002, 0.0025, -0.002], (0.0014, 0.0011, 0.0007), "c3c8ae", b, 7, 4)
    if patrol:
        for i in range(4):
            y = -0.025 + i * 0.024
            m.rings(
                [(0, y, -0.016, 0.084 + i * 0.003, 0.101), (0, y + 0.021, -0.014, 0.085 + i * 0.003, 0.106)],
                "686e66" if i % 2 else "8a8b7a",
                b,
                24,
            )
        mark([(-0.057, 0.075, -0.103), (-0.021, 0.039, -0.119), (0.041, -0.005, -0.106)], 0.0035, "4c534c")
    elif teacher:
        for sign in (-1, 1):
            rim = [
                point(
                    sign * (0.32 + 0.263 * cos(a)), 7.23 + 0.159 * sin(a) + sign * 0.035, 1.57 - 0.11 * cos(a)
                )
                for a in np.linspace(0, 2 * pi, 21)
            ]
            mark(rim, 0.0028, "929480")
            mark([rim[0], point(sign * 0.79, 7.17, 0.8)], 0.0023, "848678")
        mark([point(-0.081, 7.22, 1.60), point(0, 7.28, 1.67), point(0.081, 7.25, 1.60)], 0.0027, "999c82")
        for j in range(3):
            x = -0.22 + j * 0.087
            mark(
                [point(x, 6.64, 1.64), point(x + 0.009, 6.51, 1.66), point(x - 0.032, 6.41, 1.59)],
                [0.0022, 0.0017, 0.0009],
                "c0bfa3",
            )
    else:
        # Two short tensions beside the natural dark lip seam read at a distance;
        # they are written into the surface instead of painting a large smile.
        for sign in (-1, 1):
            mark(
                [
                    point(sign * 0.24, 6.59, 1.56),
                    point(sign * 0.32, 6.62, 1.48),
                    point(sign * 0.37, 6.69, 1.43),
                ],
                [0.0021, 0.0029, 0.0009],
                "5c5e50",
            )

    def scalp(a, t):
        front = (1 + cos(a)) * 0.5
        edge = 6.72 + 1.09 * front**3 + 0.14 * sin(a + 0.52) * front
        if alternate:
            edge = 5.95 + 1.76 * front**3 + 0.51 * sin(a + 0.34) * front**2
        if teacher:
            edge = 7.09 + 0.63 * front**2 + 0.13 * sin(2 * a + 0.6) * front
        if patrol or garage:
            edge = 6.8 + 1.0 * front**2
        lat = np.arcsin(np.clip((edge - 7.46) / 1.15, -0.99, 0.97))
        lat = lat + (pi / 2 - lat) * t
        radius = cos(lat) * (1 + 0.023 * sin(9 * a + 2 * t) * (1 - t))
        y = 7.46 + 1.15 * sin(lat)
        if alternate and front < 0.7:
            y = edge + (8.61 - edge) * sin(t * pi * 0.5)
            radius = max(radius, 0.91 * (1 - t * t))
        return point(0.87 * radius * sin(a), y, 0.55 + 1.065 * radius * cos(a))

    rings = []
    for t in np.linspace(0, 0.997, 10):
        rings.append(
            [
                m.vertex(scalp(a, t), color(hair) * (0.87 + 0.16 * sin(9 * a + 1.6 * t)), b)
                for a in np.arange(36) * 2 * pi / 36
            ]
        )
    for lo, hi in zip(rings, rings[1:]):
        for i in range(36):
            j = (i + 1) % 36
            m.tris.extend([(lo[i], lo[j], hi[j]), (lo[i], hi[j], hi[i])])
    for j in range(22):
        a = j * 2 * pi / 22
        curve = [
            scalp(a + 0.48 * t, t) + np.array([-0.0008 * sin(a), 0.0005, -0.0008 * cos(a)])
            for t in np.linspace(0, 0.87, 7)
        ]
        tint = "777a70" if teacher and j % 3 == 0 else "40423d"
        mark(curve, [0.0007, 0.0014, 0.0016, 0.0015, 0.0013, 0.001, 0.0005], tint)
    if alternate:
        p = scalp(0.76, 0)
        mark([p, p + [-0.001, -0.034, -0.012], p + [0.006, -0.078, -0.010]], [0.016, 0.012, 0.001], "222627")
    if patrol:
        m.rings(
            [
                (0, 0.157, -0.019, 0.123, 0.149),
                (0, 0.166, -0.031, 0.124, 0.161),
                (0, 0.189, 0.001, 0.123, 0.116),
                (-0.016, 0.217, 0.015, 0.146, 0.126),
                (-0.018, 0.249, 0.017, 0.134, 0.116),
            ],
            "3b4141",
            b,
            28,
        )
        m.patch(
            [(-0.014, 0.205, -0.116), (0, 0.227, -0.114), (0.015, 0.205, -0.116), (0, 0.191, -0.12)],
            "adaa8e",
            b,
        )
    if garage:
        for sign in (-1, 1):
            mark(
                [
                    point(0.62 * sign, 7.71, 1.25),
                    point(0.71 * sign, 7.2, 1.19),
                    point(0.64 * sign, 6.78, 1.17),
                ],
                [0.032, 0.028, 0.007],
                "2c3331",
            )
    return m


def flat_mesh(glb, mesh, vertices, name):
    v = np.asarray(vertices)
    faces = np.array(mesh.tris)
    fn = np.cross(v[faces[:, 1]] - v[faces[:, 0]], v[faces[:, 2]] - v[faces[:, 0]])
    normals = np.zeros_like(v)
    for k in range(3):
        np.add.at(normals, faces[:, k], fn)
    normals /= np.maximum(1e-12, np.linalg.norm(normals, axis=1))[:, None]
    rgb = np.column_stack((np.uint16(65535 * np.clip(mesh.colors, 0, 1)), np.full(len(v), 65535)))
    attrs = {
        "POSITION": glb.array(v, "VEC3", bounds=True),
        "NORMAL": glb.array(normals, "VEC3"),
        "COLOR_0": glb.array(rgb, "VEC4", "H", normalized=True),
    }
    index = len(glb.doc["meshes"])
    glb.doc["meshes"].append(
        {
            "name": name,
            "primitives": [
                {"attributes": attrs, "material": 0, "indices": glb.array(faces.flatten(), "SCALAR", "H")}
            ],
        }
    )
    node = len(glb.doc["nodes"])
    glb.doc["nodes"].append({"name": name, "mesh": index})
    glb.doc["nodes"][0]["children"].append(node)
    return glb.doc["nodes"][node]


def drill_clip(glb, body_mesh):
    # Counted arm raises, elbows locked in mid-air between each count. Feet never leave their mark.
    beats = [0, 0.46, 0.63, 1.34, 1.53, 2.28, 2.52, 3.18, 3.4]
    times = glb.array(beats, "SCALAR", bounds=True)
    channels = []
    samplers = []
    for suffix, s in [("L", 1), ("R", -1)]:
        for bone, angles in [
            (
                "Arm",
                [
                    (a, 0, s * z)
                    for a, z in [
                        (5, 2),
                        (5, 2),
                        (18, 81),
                        (18, 81),
                        (148, 14),
                        (148, 14),
                        (76, 0),
                        (76, 0),
                        (5, 2),
                    ]
                ],
            ),
            ("Elbow", [(x, 0, 0) for x in [9, 9, 0, 0, 8, 8, 0, 0, 9]]),
        ]:
            channels.append(
                {
                    "sampler": len(samplers),
                    "target": {"node": body_mesh.names.index(bone + suffix) + 1, "path": "rotation"},
                }
            )
            samplers.append(
                {
                    "input": times,
                    "output": glb.array([quaternion(a) for a in angles], "VEC4"),
                    "interpolation": "LINEAR",
                }
            )
    glb.doc["animations"].append({"name": "drill_loop", "channels": channels, "samplers": samplers})


def bake(role, source):
    glb = GLB()
    bones = skeleton(1.0)
    m = body(role, bones)
    head = face(role, source)
    at = bones["Head"][1]
    if role in ("sit", "roam"):
        glb.doc["nodes"] = [{"name": "Figure", "children": []}]
        del glb.doc["animations"], glb.doc["skins"]
        v = np.asarray(m.vertices)
        if role == "sit":
            shift, angles = pose("sit", 0.2)
            matrices = posed_bones(bones, shift, angles)
            transforms = []
            for bone, (_, rest) in bones.items():
                inverse = np.eye(4)
                inverse[:3, 3] = -rest
                transforms.append((matrices[bone] @ inverse)[:3])
            weighted = np.einsum("vi,vijk->vjk", m.weights, np.asarray(transforms)[m.joints])
            v = np.einsum("vij,vj->vi", weighted, np.column_stack((v, np.ones(len(v)))))
            at = matrices["Head"][:3, 3]
        flat_mesh(glb, m, v, "Uniform")
    else:
        glb.build(m, {k: CLIPS[k] for k in ["idle", "walk"]})
        if role == "person":
            drill_clip(glb, m)
    flat_mesh(glb, head, head.vertices, "Visage")["translation"] = at.tolist()
    if role in ("sit", "person"):
        alt = face(role, source, True)
        flat_mesh(glb, alt, alt.vertices, "VisageAlt")["translation"] = at.tolist()
    glb.doc["asset"]["generator"] = "WDFZ otherworld figures"
    glb.save(DEST / (role + ".glb"))
    print(role, len(m.tris) + len(head.tris), "triangles")


if __name__ == "__main__":
    DEST.mkdir(exist_ok=True, parents=True)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, default=ROOT / "build/student-art/hm08.obj")
    source = anatomy(parser.parse_args().base)
    for role in ("sit", "person", "teacher", "patroller", "roam"):
        bake(role, source)
