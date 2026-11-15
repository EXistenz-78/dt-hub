"""Rewrite an mlx-vlm folder that kept ModelOpt NVFP4 weights (packed nvfp4 + weight_scale_2)
as standard MLX affine quantization, which mlx-swift-lm can load.

For each tensor with `.scales` + `.weight_scale_2`:
    W = dequantize(nvfp4) * weight_scale_2      (as mlx_vlm's ScaledQuantizedLinear computes)
    weight, scales, biases = quantize(W, group_size, bits)   (affine)
Everything else is copied unchanged.

usage: requant_nvfp4_to_mlx_affine.py <src> <dst> [bits] [group_size] [--check]
(defaults: 8 bits, group size 64; --check compares one layer and writes nothing)
"""
import json
import os
import shutil
import sys

import mlx.core as mx

# On the CPU: on the GPU a big shard can end in a Metal timeout.
mx.set_default_device(mx.cpu)

src, dst = sys.argv[1], sys.argv[2]
args = [a for a in sys.argv[3:] if not a.startswith("--")]
bits = int(args[0]) if len(args) > 0 else 8
group = int(args[1]) if len(args) > 1 else 64
check_only = "--check" in sys.argv

index = json.load(open(os.path.join(src, "model.safetensors.index.json")))
shards = sorted(set(index["weight_map"].values()))


def nvfp4_dense(t, name):
    w = mx.dequantize(
        t[f"{name}.weight"], t[f"{name}.scales"], group_size=16, bits=4, mode="nvfp4",
        dtype=mx.float32,
    )
    return w * t[f"{name}.weight_scale_2"].astype(mx.float32)


if check_only:
    # Compare dequantize*scale with the quantized matmul mlx_vlm runs, on one layer.
    t = mx.load(os.path.join(src, shards[0]))
    name = next(k[: -len(".scales")] for k in t if k.endswith(".scales"))
    w = nvfp4_dense(t, name)
    x = mx.random.normal((4, w.shape[1]))
    ref = mx.quantized_matmul(
        x, t[f"{name}.weight"], scales=t[f"{name}.scales"], group_size=16, bits=4,
        mode="nvfp4", transpose=True,
    ) * t[f"{name}.weight_scale_2"].astype(mx.float32)
    out = x @ w.T
    q, s, b = mx.quantize(w.astype(mx.bfloat16), group_size=group, bits=bits)
    back = mx.dequantize(q, s, b, group_size=group, bits=bits, dtype=mx.float32)
    print(name, w.shape, "std", w.std().item())
    print("matmul rel err", (mx.abs(out - ref).max() / mx.abs(ref).max()).item())
    print(f"affine {bits}-bit rel err", (mx.abs(back - w).mean() / mx.abs(w).mean()).item())
    sys.exit()

os.makedirs(dst, exist_ok=True)
weight_map = {}
total = 0
for shard in shards:
    out_path = os.path.join(dst, shard)
    if os.path.exists(out_path):
        # A shard written by an earlier run is kept: the conversion can be resumed.
        done = mx.load(out_path)
        for key in done:
            weight_map[key] = shard
        total += sum(v.nbytes for v in done.values())
        print(f"{shard}: already written, kept", flush=True)
        del done
        continue
    tensors = mx.load(os.path.join(src, shard))
    names = {k[: -len(".scales")] for k in tensors if k.endswith(".scales")}
    out = {}
    for key, value in tensors.items():
        base = key.rsplit(".", 1)[0]
        if base in names:
            continue
        out[key] = value
    for name in sorted(names):
        w = nvfp4_dense(tensors, name).astype(mx.bfloat16)
        mx.eval(w)
        q, s, b = mx.quantize(w, group_size=group, bits=bits)
        out[f"{name}.weight"], out[f"{name}.scales"], out[f"{name}.biases"] = q, s, b
        mx.eval(q, s, b)
    tmp = out_path + ".part.safetensors"
    mx.save_safetensors(tmp, out, metadata={"format": "mlx"})
    os.replace(tmp, out_path)
    for key in out:
        weight_map[key] = shard
    total += sum(v.nbytes for v in out.values())
    print(f"{shard}: {len(names)} matrices requantized", flush=True)
    del tensors, out
    mx.clear_cache()

json.dump(
    {"metadata": {"total_size": total}, "weight_map": dict(sorted(weight_map.items()))},
    open(os.path.join(dst, "model.safetensors.index.json"), "w"), indent=2,
)

config = json.load(open(os.path.join(src, "config.json")))
config.pop("quantization_config", None)
config.get("text_config", {}).pop("quantization_config", None)
quant = {"group_size": group, "bits": bits, "mode": "affine"}
config["quantization"] = quant
config["quantization_config"] = quant
json.dump(config, open(os.path.join(dst, "config.json"), "w"), indent=2)

skip = {"config.json", "model.safetensors.index.json", "hf_quant_config.json"}
for item in os.listdir(src):
    if item in skip or item.endswith(".safetensors"):
        continue
    s, d = os.path.join(src, item), os.path.join(dst, item)
    if os.path.isdir(s):
        shutil.copytree(s, d, dirs_exist_ok=True)
    else:
        shutil.copy2(s, d)
print("done", round(total / 1e9, 1), "GB")
