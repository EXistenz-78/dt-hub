#!/usr/bin/env python3
"""Paesaggio procedurale con l'orizzonte esattamente a metà altezza (riga H/2). Uso: make_landscape.py out.png [W H]"""
import sys, numpy as np
from PIL import Image
rng = np.random.default_rng(7)
W, H = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else (3200, 1600)
def noise2(h, w, cells_y, cells_x, octaves=5):
    out = np.zeros((h, w), np.float32); amp = 1.0; tot = 0
    for o in range(octaves):
        gy, gx = cells_y * 2**o + 2, cells_x * 2**o + 2
        g = rng.random((gy, gx), dtype=np.float32)
        out += amp * np.asarray(Image.fromarray(g).resize((w, h), Image.BICUBIC)); tot += amp; amp *= .5
    return out / tot
y = np.arange(H, dtype=np.float32)[:, None] / H
hz = 0.5
img = np.zeros((H, W, 3), np.float32)
# cielo: dal blu in alto al caldo all'orizzonte
t = np.clip(y / hz, 0, 1)
top = np.array([.18, .38, .72]); low = np.array([.95, .78, .60])
sky = top * (1 - t**1.6)[..., None] + low * (t**1.6)[..., None]
cl = noise2(H, W, 2, 5)[..., None]
cl = np.clip((cl - .52) * 4, 0, 1) * (1 - t[..., None]**3) * .85
sky = sky * (1 - cl) + np.array([1, .96, .92]) * cl
# montagne lontane: appoggiate sull'orizzonte
x = np.arange(W)
ridge = np.zeros(W, np.float32); amp = 0.09
for o in range(7):
    g = rng.random(int(6 * 2**o) + 2).astype(np.float32)
    ridge += amp * np.interp(x / W * (len(g) - 1), np.arange(len(g)), g); amp *= .5
ridge = (ridge - ridge.min()) / (ridge.max() - ridge.min()) * .10
ytop = hz - ridge[None, :]
mnt = (y >= ytop) & (y < hz)
shade = np.clip((y - ytop) / .10, 0, 1)[..., None]
mcol = np.array([.42, .46, .58]) * (1 - shade) + np.array([.62, .62, .70]) * shade
img[:] = sky
img = np.where(mnt[..., None], mcol, img)
# mare: sotto l'orizzonte, più chiaro vicino
s = np.clip((y - hz) / (1 - hz), 0, 1)
sea = np.array([.80, .70, .62]) * (1 - s**.5)[..., None] + np.array([.10, .24, .38]) * (s**.5)[..., None]
rip = noise2(H, W, 60, 3, 4)[..., None] - .5
sea = sea * (1 + rip * (.15 + .5 * s[..., None]))
img = np.where((y >= hz)[..., None], sea, img)
Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(sys.argv[1])
print(sys.argv[1], W, H, "orizzonte riga", int(H * hz))
