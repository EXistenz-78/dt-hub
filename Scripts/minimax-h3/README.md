# MiniMax H3 Image: conversion tools

Two small tools the author used to run **MiniMax H3 Image** and its prompt expander on a 64 GB Mac. They convert files you
download yourself; **no model weights are in this repository**.

> **Licence.** MiniMax-H3-Image and MiniMax-H3-Image-PE are released under the
> [MiniMax-H3-Image Community License Agreement](https://huggingface.co/MiniMaxAI/MiniMax-H3-Image/blob/main/LICENSE).
> It grants use, reproduction and distribution only in its "Applicable Territory", which **excludes the European Union,
> the United Kingdom, the Republic of Korea and the United States of America**, and a converted or quantized copy is a
> "Model Derivative" under the same terms. Read the licence before you download, convert or share anything; these
> scripts do not change what it allows.

## 1. The prompt expander (MiniMax-H3-Image-PE) for MLX

[`MiniMaxAI/MiniMax-H3-Image-PE`](https://huggingface.co/MiniMaxAI/MiniMax-H3-Image-PE) is published with NVFP4
weights. `mlx_vlm.convert` keeps that packing (4-bit weights plus a `weight_scale_2` per layer), which `mlx-vlm` runs
but `mlx-swift-lm`, the loader DT Hub uses, does not load. `requant_nvfp4_to_mlx_affine.py` rewrites the folder as
standard MLX affine quantization.

```bash
pip install -U "mlx-vlm>=0.7.12"
```

```bash
mlx_vlm.convert --hf-path MiniMaxAI/MiniMax-H3-Image-PE --mlx-path ./minimax-h3-image-pe-mlx
```

```bash
python3 requant_nvfp4_to_mlx_affine.py ./minimax-h3-image-pe-mlx ./minimax-h3-image-pe-mlx-8bit 8 64
```

- The first step downloads about 17 GB; the result of the second is about 29 GB (8 bit, group size 64) and took about
  five minutes on the CPU. A run that stops can be started again: shards already written are kept.
- `--check` at the end compares one layer and writes nothing. On the author's Mac the decoded NVFP4 weights reproduce
  the quantized product to about 2e-6, and the 8-bit copy differs from them by about 0.7% on average.
- The folder keeps the model's `prompt/` directory. Check that it is there (`prompt/t2i/system_prompt.txt`,
  `prompt/t2i/task_prompt.txt`, `prompt/t2i/request_params.json`, `prompt/edit/task_prompt.txt`); if it is not, copy it
  from the Hugging Face repository. DT Hub reads those files: see «The MiniMax H3 Image prompt expander» in the main
  README.
- Put the folder in the models folder of **Preferences › LLM** and assign it to the family of MiniMax H3 Image.

## 2. The text encoder at 4 bit (Q4_K)

MiniMax H3 Image uses a Qwen3-VL 32B text encoder. The 8-bit file in Draw Things' format
(`qwen_3_vl_32b_50_i8x.ckpt`, 26.5 GB) leaves little room next to the 21 GB model. `quant4` writes a 4-bit copy
(16.5 GB): the weight matrices become row-wise Q4_K, the token embeddings and the vision tower stay FP16, as in the
8-bit file.

```bash
cd quant4 && swift build -c release
```

```bash
.build/release/quant4 /path/to/qwen_3_vl_32b_50_i8x.ckpt /path/to/qwen_3_vl_32b_50_i4x.ckpt
```

- It took about 38 minutes on the author's Mac. A run that stops can be started again with the same command: tensors
  already in the output are kept.
- The build fetches [s4nnc](https://github.com/liuliu/s4nnc) (the library Draw Things is built on) at a pinned revision.
- To use it, add an entry to the `custom.json` of your models folder that is a copy of the model's entry with
  `"text_encoder": "qwen_3_vl_32b_50_i4x.ckpt"` and a `file` and `name` of its own (the `file` can be a copy or an APFS
  clone of the model's file).
- MiniMax H3 Image needs a server that knows the family `minimax_h3_image`. The `Custom-gRPCServerCLI.zip` of the
  [DT Hub releases](https://github.com/EXistenz-78/dt-hub/releases/latest) has it (built from the fork
  [`ianiv/draw-things-community`](https://github.com/ianiv/draw-things-community)); the official Draw Things server does
  not have it yet.
- The quality of the 4-bit encoder against the 8-bit one has not been measured.
