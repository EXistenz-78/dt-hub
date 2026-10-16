#!/usr/bin/env python3
"""Converts DWPose-L (a whole-body pose model, 133 keypoints) to the Core ML package the Depth & Pose plug-in uses.

    uv venv --python 3.12 env && source env/bin/activate
    uv pip install -r requirements-convert.txt
    python convert_pose_model.py dw-ll_ucoco_384.onnx OUT/DWPoseL384F16.mlpackage

The ONNX file is `dw-ll_ucoco_384.onnx` of https://huggingface.co/yzd-v/DWPose (Apache-2.0; DWPose by IDEA-Research,
Zhendong Yang et al., https://github.com/IDEA-Research/DWPose). The package takes an RGB picture of 288x384 (width x
height), values 0..255 (the mean/std normalisation is inside), and gives the two SimCC vectors `simcc_x` (1x133x576) and
`simcc_y` (1x133x768), float16.

Why it is not a plain conversion:
- Core ML has no ONNX reader any more, so the graph goes through PyTorch with `onnx2torch`.
- `onnx2torch` cannot read a `Clip` whose min or max is an empty name, or comes through an `Identity`: those inputs are
  given explicit constants first.

What this makes carries the Apache-2.0 licence of DWPose: keep its licence and attribution, and say it was "converted to
Core ML (float16, fixed 288x384 input, normalisation included)". The weights come out byte-for-byte the same on every run
(the two small files carry fresh identifiers each time).
"""
import hashlib
import sys
import time
from pathlib import Path

import coremltools as ct
import numpy as np
import onnx
import onnx2torch
import torch
from onnx import numpy_helper

MEAN = [123.675, 116.28, 103.53]
STD = [58.395, 57.12, 57.375]
WIDTH, HEIGHT = 288, 384


def patch_clips(proto):
    """Give every Clip an explicit min and max constant (see the note above)."""
    initializers = {i.name for i in proto.graph.initializer}
    identity = {n.output[0]: n.input[0] for n in proto.graph.node if n.op_type == "Identity"}
    for node in proto.graph.node:
        if node.op_type != "Clip":
            continue
        inputs = list(node.input) + [""] * (3 - len(node.input))
        for slot in (1, 2):
            while inputs[slot] and inputs[slot] not in initializers and inputs[slot] in identity:
                inputs[slot] = identity[inputs[slot]]
        for slot, value in ((1, -3.4e38), (2, 3.4e38)):
            if inputs[slot] == "":
                name = f"{node.name or node.output[0]}_clip{slot}"
                proto.graph.initializer.append(numpy_helper.from_array(np.array(value, dtype=np.float32), name))
                inputs[slot] = name
        del node.input[:]
        node.input.extend(inputs)


class Wrapped(torch.nn.Module):
    """RGB 0..255 in (mean/std normalisation inside), the two SimCC vectors out."""

    def __init__(self, model):
        super().__init__()
        self.model = model
        self.register_buffer("mean", torch.tensor(MEAN).view(1, 3, 1, 1))
        self.register_buffer("inverse_std", (1.0 / torch.tensor(STD)).view(1, 3, 1, 1))

    def forward(self, x):
        simcc_x, simcc_y = self.model((x - self.mean) * self.inverse_std)
        return simcc_x, simcc_y


def main():
    onnx_path, out = Path(sys.argv[1]), Path(sys.argv[2])
    proto = onnx.load(str(onnx_path))
    patch_clips(proto)
    wrapped = Wrapped(onnx2torch.convert(proto).eval()).eval()
    example = torch.rand(1, 3, HEIGHT, WIDTH) * 255
    traced = torch.jit.trace(wrapped, example, strict=False)
    started = time.time()
    model = ct.convert(
        traced,
        inputs=[ct.ImageType(name="image", shape=(1, 3, HEIGHT, WIDTH), scale=1.0, color_layout=ct.colorlayout.RGB)],
        outputs=[ct.TensorType(name="simcc_x"), ct.TensorType(name="simcc_y")],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS15,
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    model.save(str(out))
    print(f"converted in {time.time() - started:.1f} s -> {out}")
    for relative in ("Manifest.json", "Data/com.apple.CoreML/model.mlmodel", "Data/com.apple.CoreML/weights/weight.bin"):
        path = out / relative
        print(f"{relative} {path.stat().st_size} {hashlib.sha256(path.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    main()
