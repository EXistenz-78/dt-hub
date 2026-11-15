# MOSS Image Edit LoRA in DT Hub (with Atelier's engine)

A LoRA from the **MOSS Image Edit** trainer turns MOSS Image into an edit model: you give it a picture and an instruction ("change the green velvet couch to deep red velvet, keep everything else the same") and it changes just that. A LoRA file alone is not enough. The engine has to feed the picture to the model as references, and that code is **not** in the official Draw Things `gRPCServerCLI`. It is in the engine fork that **Atelier** uses.

## Credits

- **Atelier**, by [ianiv](https://github.com/ianiv/Atelier): its engine fork, [ianiv/draw-things-community](https://github.com/ianiv/draw-things-community) (GPL-3.0, from [Draw Things' community repository](https://github.com/drawthingsai/draw-things-community)), reads reference pictures for MOSS Image edit LoRAs (commit `60e031b2`, "Use reference images with MOSS Image edit LoRAs"). The server attached to this release is built from that fork. Atelier also converts and registers the LoRA (below).
- **MOSS Image Edit**, by chinoll: the LoRA [chinoll/Moss-Image-Edit](https://huggingface.co/chinoll/Moss-Image-Edit) and its [trainer](https://github.com/Chenkin-x/Moss-Image-Edit) (GPL-3.0). Base model: [OpenMOSS-Team/MOSS-Image-SFT](https://huggingface.co/OpenMOSS-Team/MOSS-Image-SFT).
- The same method in ComfyUI: [Comfy-Org/ComfyUI#17296](https://github.com/Comfy-Org/ComfyUI/pull/17296) by kijai.

## What you need

1. **MOSS Image SFT** (or Base) installed in Draw Things' models folder.
2. **The LoRA file:** `adapter_model.safetensors` and `adapter_config.json` from [chinoll/Moss-Image-Edit](https://huggingface.co/chinoll/Moss-Image-Edit) (about 300 MB). Keep the two files in the same folder.
3. **Atelier 0.12 or later** ([releases](https://github.com/ianiv/Atelier/releases)), to import the LoRA.
4. **The engine server of this release:** `DrawThings-engine-Atelier-9599c5ff-macOS-arm64.zip` (see its own README inside).

## Steps

1. **Import the LoRA with Atelier**, not with the Draw Things app. In Atelier, use **Import LoRAs** and pick `adapter_model.safetensors`. Atelier renames its tensors so the engine can read them and registers it as an *edit* LoRA (`modifier: kontext` in the models folder's `custom_lora.json`). Make sure Atelier writes into the **same models folder** your DT Hub server uses. The imported file is named `adapter_model_lora_f16.ckpt` unless you rename it.
2. **Unzip the server** and put the folder somewhere stable, for example `~/Applications/DrawThings-CLI/`. If macOS blocks it, run `xattr -dr com.apple.quarantine <folder>` and `chmod +x <folder>/gRPCServerCLI-macOS`.
3. **In DT Hub:** Preferences › Draw Things, mode **Start gRPCServerCLI**, set the **gRPCServerCLI program** to `gRPCServerCLI-macOS` of that folder, then restart the server. Keep the `*.bundle` folders next to it.
4. **Generate:** choose **MOSS Image SFT**, add the LoRA at weight 1, put the picture you want to edit as the **start image** with **strength 100 %**, and write the change as a plain instruction. Settings that worked: 50 steps, text guidance 3, shift 5 (about 7 minutes for 1152×768 on an M-series Mac).
5. **Faster (draft quality):** add the 8-step DMD LoRA `MI 8-steps-dmd2` at weight 1 and set **8 steps** and **guidance 1**. In the author's tests the 8-step result is a little softer than the 50-step one.

## What to expect

- Edits of a **single picture** work well; the LoRA was trained on single-picture edits. Edits that combine pictures usually give the first one back.
- **Start image works; the Moodboard does not (yet):** pictures put only in the Moodboard were not used as references in DT Hub's tests. Use the start image.
- It needs about 20 GB or more of free memory.
- A bug of earlier DT Hub versions kept an imported LoRA from being an edit LoRA over the managed server; DT Hub 1.4.1 fixes it by sending the LoRA's own entry of `custom_lora.json`. This only matters with the server of this release.
