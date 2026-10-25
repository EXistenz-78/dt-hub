#!/usr/bin/env python3
"""ERP di prova per il LoRA «360 ERP outpaint» (FLUX.2 klein base).
Uso: make_erp.py immagine.jpg [--yaw 0 --pitch 0 --hfov 90 --rot 0] [--out file.png] [--width 2048]
Più sticker: ripetere il gruppo con --add immagine yaw pitch hfov rot.
Sfondo #00ff00, proiezione pinhole tangente alla sfera (come Panorama Stickers)."""
import argparse, math, numpy as np
from PIL import Image

def place(erp, img, yaw, pitch, hfov, rot):
    H, W, _ = erp.shape
    a = np.asarray(img.convert("RGBA"), dtype=np.float32) / 255.0
    ih, iw = a.shape[:2]
    tx = math.tan(math.radians(hfov) / 2); ty = tx * ih / iw
    y, p, r = map(math.radians, (yaw, pitch, rot))
    fwd = np.array([math.sin(y)*math.cos(p), math.sin(p), math.cos(y)*math.cos(p)])
    right = np.array([math.cos(y), 0, -math.sin(y)])
    up = np.cross(fwd, right)
    right, up = right*math.cos(r) - up*math.sin(r), right*math.sin(r) + up*math.cos(r)
    u = (np.arange(W) + 0.5) / W; v = (np.arange(H) + 0.5) / H
    lon = (u - 0.5) * 2 * math.pi; lat = (0.5 - v) * math.pi
    lon, lat = np.meshgrid(lon, lat)
    d = np.stack([np.sin(lon)*np.cos(lat), np.sin(lat), np.cos(lon)*np.cos(lat)], -1)
    dz = d @ fwd
    ok = dz > 1e-5
    dz = np.where(ok, dz, 1.0)
    px = (d @ right) / dz; py = (d @ up) / dz
    su = px / tx * 0.5 + 0.5; sv = 0.5 - py / ty * 0.5
    ok &= (su >= 0) & (su <= 1) & (sv >= 0) & (sv <= 1)
    x = np.clip(su * (iw - 1), 0, iw - 1); yy = np.clip(sv * (ih - 1), 0, ih - 1)
    x0 = np.floor(x).astype(int); y0 = np.floor(yy).astype(int)
    x1 = np.minimum(x0 + 1, iw - 1); y1 = np.minimum(y0 + 1, ih - 1)
    fx = (x - x0)[..., None]; fy = (yy - y0)[..., None]
    s = (a[y0, x0]*(1-fx)*(1-fy) + a[y0, x1]*fx*(1-fy) + a[y1, x0]*(1-fx)*fy + a[y1, x1]*fx*fy)
    al = (s[..., 3:4]) * ok[..., None]
    erp[:] = s[..., :3] * al + erp * (1 - al)

ap = argparse.ArgumentParser()
ap.add_argument("image"); ap.add_argument("--yaw", type=float, default=0)
ap.add_argument("--pitch", type=float, default=0); ap.add_argument("--hfov", type=float, default=90)
ap.add_argument("--rot", type=float, default=0); ap.add_argument("--out", default="erp.png")
ap.add_argument("--width", type=int, default=2048)
ap.add_argument("--add", nargs=5, action="append", metavar=("IMG", "YAW", "PITCH", "HFOV", "ROT"))
n = ap.parse_args()
W = n.width; H = W // 2
erp = np.empty((H, W, 3), np.float32); erp[:] = (0, 1, 0)
place(erp, Image.open(n.image), n.yaw, n.pitch, n.hfov, n.rot)
for im, *v in (n.add or []):
    place(erp, Image.open(im), *map(float, v))
Image.fromarray((erp * 255 + 0.5).astype(np.uint8)).save(n.out)
print(n.out, W, H)
