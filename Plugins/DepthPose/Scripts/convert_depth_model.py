#!/usr/bin/env python3
"""Converts Depth Anything V2 Base to the Core ML package the Depth & Pose plug-in uses.

    uv venv --python 3.12 env && source env/bin/activate
    uv pip install -r requirements-convert.txt
    python convert_depth_model.py OUT_DIR [base|large]

Writes OUT_DIR/DepthAnythingV2<Base|Large>F16.mlpackage: two functions with shared weights, `landscape` (input 1036x784) and
`portrait` (784x1036), input `image` (RGB), output `depth` (a grey picture, 0..1 stretched per picture, near is bright).
Then prints the size and SHA-256 of the three files (the weights come out byte-for-byte the same on every run; the two
small files carry fresh identifiers each time, so the release uses the files that `DPModelManifest` has the hashes of), which `DPModelManifest` (Sources/DepthPose/DPModelStore.swift)
repeats, and copies them under the flat names a GitHub release needs.

Why it is not a plain `ct.convert`:
- Core ML has no bicubic upsample, which Dinov2 uses to fit its position embedding to the picture size. For one fixed
  size that embedding is a constant, so it is computed once with the real function and handed back as a constant.
- The ImageNet normalisation sits inside the model, so the input is a plain 0..255 image.
- The depth is stretched to 0..1 inside the model, so the app reads a grey picture and never sees raw values.

The weights are CC BY-NC 4.0 (Lihe Yang et al., https://github.com/DepthAnything/Depth-Anything-V2): what this script
makes carries that licence, and must be given with attribution, as "converted to Core ML (F16, fixed shapes, functions
merged, output normalised)", and not sold.
"""
import hashlib
import shutil
import sys
from pathlib import Path

import coremltools as ct
import torch
from coremltools.models.utils import MultiFunctionDescriptor, save_multifunction
from transformers import AutoModelForDepthEstimation

SIZES = {"base": "Base", "large": "Large"}
SIZE = SIZES[sys.argv[2] if len(sys.argv) > 2 else "base"]
REPO = f"depth-anything/Depth-Anything-V2-{SIZE}-hf"
NAME = f"DepthAnythingV2{SIZE}F16"
SHAPES = {"landscape": (784, 1036), "portrait": (1036, 784)}  # (height, width), multiples of 14


class Wrapped(torch.nn.Module):
    """0..1 RGB in, ImageNet normalisation inside, depth stretched to 0..1 out."""

    def __init__(self, model):
        super().__init__()
        self.model = model
        self.register_buffer("mean", torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1))

    def forward(self, x):
        d = self.model(pixel_values=(x - self.mean) / self.std).predicted_depth.unsqueeze(1)
        low = d.amin(dim=(1, 2, 3), keepdim=True)
        high = d.amax(dim=(1, 2, 3), keepdim=True)
        return (d - low) / (high - low + 1e-6)


def convert(height, width, out):
    model = AutoModelForDepthEstimation.from_pretrained(REPO).eval()
    embeddings = model.backbone.embeddings
    with torch.no_grad():
        tokens = embeddings.patch_embeddings(torch.rand(1, 3, height, width))
        full = torch.cat([embeddings.cls_token.expand(1, -1, -1), tokens], dim=1)
        constant = embeddings.interpolate_pos_encoding(full, height, width).detach().clone()
    embeddings.interpolate_pos_encoding = lambda emb, h, w: constant
    wrapped = Wrapped(model).eval()
    example = torch.rand(1, 3, height, width)
    traced = torch.jit.trace(wrapped, example, strict=False)
    ml = ct.convert(
        traced,
        inputs=[ct.ImageType(name="image", shape=(1, 3, height, width), scale=1 / 255.0, color_layout=ct.colorlayout.RGB)],
        outputs=[ct.ImageType(name="depth", color_layout=ct.colorlayout.GRAYSCALE_FLOAT16)],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS15,
    )
    ml.save(str(out))


def main():
    out_dir = Path(sys.argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    parts = {}
    for function, (height, width) in SHAPES.items():
        path = out_dir / f"{function}.mlpackage"
        convert(height, width, path)
        parts[function] = path
    descriptor = MultiFunctionDescriptor()
    for function, path in parts.items():
        descriptor.add_function(str(path), src_function_name="main", target_function_name=function)
    descriptor.default_function_name = "landscape"
    package = out_dir / f"{NAME}.mlpackage"
    if package.exists():
        shutil.rmtree(package)
    save_multifunction(descriptor, str(package))
    for path in parts.values():
        shutil.rmtree(path)

    files = {
        f"{NAME}-Manifest.json": package / "Manifest.json",
        f"{NAME}-model.mlmodel": package / "Data/com.apple.CoreML/model.mlmodel",
        f"{NAME}-weight.bin": package / "Data/com.apple.CoreML/weights/weight.bin",
    }
    release = out_dir / "release-files"
    release.mkdir(exist_ok=True)
    for asset, source in files.items():
        shutil.copy(source, release / asset)
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        print(f"{asset} {source.stat().st_size} {digest}")
    print("package:", package, "\nrelease files:", release)


if __name__ == "__main__":
    main()
