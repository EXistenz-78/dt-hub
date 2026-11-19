# Custom gRPCServerCLI (Krea 2 Edit, MOSS Image Edit, MiniMax H3 Image)

This is a custom build of `gRPCServerCLI` (the Draw Things image server), so that [DT Hub](https://github.com/EXistenz-78/dt-hub) can use things the official server does not have:

- **Krea 2 Edit LoRAs** with reference pictures, for example [Krea 2 General Edit V2](https://huggingface.co/conradlocke/krea2-identity-edit) (new in this build, see below).
- **MOSS Image Edit LoRAs** with reference pictures (see `MOSS-Image-Edit-LoRA-guide.md` in the DT Hub release).
- **MiniMax H3 Image** (`minimax_h3_image`).

## Krea 2 Edit (new)

The patch in `krea2-edit.patch` lets Krea 2 take reference pictures (the canvas and the Moodboard images) the way the ComfyUI node pack [comfyui-krea2edit](https://github.com/lbouaraba/comfyui-krea2edit) does: each picture is encoded by the VAE and added to the model's token sequence next to the image being generated, aligned with it. Without a reference picture, Krea 2 behaves exactly as before (the same prompt, settings and seed give the same image).

What it does **not** do (the text encoder does not see the picture, no `ref_boost`, no placement options): an edit like "make the cat black" works; instructions that depend on understanding the scene may work less well than in ComfyUI. A Moodboard picture is centre-cropped to the aspect ratio of the output, so choose an output size with the same ratio as your picture to keep it whole (the canvas picture is scaled to the output size by Draw Things before the engine sees it).

To use a Krea 2 Edit LoRA, set its category to **Edit** in DT Hub's LoRA Advisor (DT Hub 1.7.1 or later): DT Hub then sends it with the modifier it needs. With an older DT Hub, its entry in the models folder's `custom_lora.json` must have `"modifier": "kontext"`, like this:

```
{ "file": "krea2_general_edit_v2_lora_f16.ckpt", "name": "K2 General Edit v2", "prefix": "", "version": "krea_2", "is_lo_ha": false, "modifier": "kontext" }
```

With the manual entry, restart DT Hub. Put the picture in the DT Hub Moodboard or Canvas; recommended settings for General Edit V2: Krea 2 Turbo, 8 steps, guidance 1. Use one Edit LoRA at a time.

## Credits

**The engine work (MOSS edit LoRAs, MiniMax H3 Image and the rest of the fork) is by ianiv, the author of [Atelier](https://github.com/ianiv/Atelier).** The Krea 2 Edit patch is by the DT Hub author. This is not an official Draw Things build and not an Atelier release.

- Source: <https://github.com/ianiv/draw-things-community>, branch `atelier-engine`, revision `8f899411` (16 November 2026) **plus** `krea2-edit.patch` (in this folder).
- That fork comes from Draw Things' community repository, <https://github.com/drawthingsai/draw-things-community>.
- This revision is a few commits newer than the one of the previous DT Hub engine (`9599c5ff`): the newer commits change the sampler grids of MiniMax H3 Image and the Karras / LCM samplers of flow models, and one LongCat setting.
- License: **GPL-3.0**, see `LICENSE.md`. The source of exactly this binary is the revision above with the patch applied; to rebuild it:

```
git init engine && cd engine
git remote add origin https://github.com/ianiv/draw-things-community
git fetch --depth 1 origin 8f89941
git checkout FETCH_HEAD
git apply ../krea2-edit.patch      # path to the patch of this folder
swift build -c release --product gRPCServerCLI
```

(Xcode needed; the program is `.build/release/gRPCServerCLI`, with the `*.bundle` folders next to it.)

## Use

**DT Hub 1.8.0 and later carry this server inside the app** (`DT Hub.app/Contents/Helpers`), and use it when **Preferences › Draw Things › gRPCServerCLI program** is empty. Nothing to download or set up.

To run it on its own, or with an older DT Hub (`Custom-gRPCServerCLI.zip` of an earlier release):

1. Keep `gRPCServerCLI-macOS` and the four `*.bundle` folders together.
2. If macOS blocks it: `xattr -dr com.apple.quarantine <folder>` and `chmod +x <folder>/gRPCServerCLI-macOS`.
3. In DT Hub: **Preferences › Draw Things**, mode **Start gRPCServerCLI**, set **gRPCServerCLI program** to that file and restart the server.

Apple Silicon only. Tried by the DT Hub author on macOS 26: Krea 2 Turbo with the General Edit V2 LoRA recolours a picture and keeps the scene; Krea 2 without an Edit LoRA gives the same image as the previous engine for the same prompt, settings and seed. MOSS Image edit and MiniMax H3 Image were tried with the previous engine (`9599c5ff`), not again with this one.
