"""Layered broadleaf planting for the existing raised beds in the game garden."""
from math import cos, pi, sin, tau

import numpy as np

from campus_mesh import Part

LEAVES = '../textures/78b5f0ecb3de266b.png'


def crown(part, center, radii, rng, shades, count):
    """Distribute overlapping sprays of the game's cutout leaves around each twig."""
    for i in range(count):
        azimuth = tau * (i * .618034 + rng.uniform(-.075, .075))
        elevation = np.arcsin(2 * (i+.5)/count - 1)
        direction = np.array((cos(azimuth)*cos(elevation), sin(elevation), sin(azimuth)*cos(elevation)))
        outward = np.array([cos(azimuth),0,sin(azimuth)])
        across = np.array([-outward[2],0,outward[0]])
        mid = np.asarray(center) + direction*radii*rng.uniform(.40,.83)
        half_width = across*radii[0]*rng.uniform(.42,.64)
        tilt = rng.uniform(-.22,.85)
        half_height = (np.array([0,1,0])*cos(tilt)+outward*sin(tilt))*radii[1]*.88
        points = [mid-half_width-half_height,mid+half_width-half_height,
                  mid+half_width+half_height,mid-half_width+half_height]
        tint = shades[int(np.clip(round((direction[1]+1)*1.4+rng.uniform(-.62,.62)),0,3))]
        part.face(points,tint,uv=[(0,1),(1,1),(1,0),(0,0)])


def garden_beds(x,z,w,d):
    trunks, leaves = Part(), Part(texture=LEAVES)
    rng = np.random.default_rng(811)
    for ix,iz in ((.15,.21),(.15,.79),(.85,.21),(.85,.79)):
        xx,zz = x+w*ix,z+d*iz
        if (ix,iz) in ((.15,.79),(.85,.21)):
            trunks.tube((xx,.25,zz),(xx+.08,2.16,zz-.07),.105,.075,'7e7764',9)
            for i in range(6):
                a = tau*i/6+rng.uniform(-.28,.28)
                ex,ez = xx+cos(a)*.88,zz+sin(a)*.88
                ey = 2.7+rng.uniform(.0,.75)
                trunks.tube((xx+.07,1.65+i*.085,zz-.05),(ex,ey,ez),.052,.023,'817963',8)
                crown(leaves,(ex,ey+.28,ez),np.array((1.13,.78,1.02)),rng,
                      ('526b49','668054','7e985e','a0ad73'),28)
            crown(leaves,(xx,3.69,zz),np.array((1.19,.81,1.05)),rng,
                  ('56724c','728c5c','8fa565','a8b67c'),34)
        for _ in range(8):
            ax,az = xx+rng.uniform(-1.07,1.07),zz+rng.uniform(-.39,.39)
            crown(leaves,(ax,.60,az),np.array((.46,.32,.39)),rng,
                  ('667548','83945a','a3af6a','b4bd83'),16)
    return trunks,leaves
