# Custom gRPCServerCLI (Ming-Image, Krea 2 Edit, MOSS Image Edit, MiniMax H3 Image, schedulers)

This is a custom build of `gRPCServerCLI` (the Draw Things image server), so that [DT Hub](https://github.com/EXistenz-78/dt-hub) can use things the official server does not have:

- **Ming-Image 0.1 Design** (`ming_image`): text to image, transparent (RGBA) output, image editing with reference pictures, and Z-Image LoRAs (new in this build, see below).
- **Krea 2 Edit LoRAs** with reference pictures, for example [Krea 2 General Edit V2](https://huggingface.co/conradlocke/krea2-identity-edit).
- **MOSS Image Edit LoRAs** with reference pictures (see `MOSS-Image-Edit-LoRA-guide.md` in the DT Hub release).
- **MiniMax H3 Image** (`minimax_h3_image`).
- **Schedulers** (Simple, SGM Uniform, Normal, Karras, Exponential, Linear Quadratic, Beta) and the ComfyUI samplers of the fork, chosen per request: DT Hub's Scheduler menu under the Sampler.
- **Safer file upload** (`--no-file-upload` turns it off) and checked LoRA names, from the fork.

## Ming-Image (new)

[Ming-Image 0.1 Design](https://huggingface.co/inclusionAI/Ming-Image-0.1-Design) (inclusionAI, MIT) is a 6B design model (posters, UI, lettering, logos) with a Ling MoE text encoder, a Qwen2.5 vision tower for editing and a 4-channel VAE that can give a transparent background. The patch adds `ModelVersion.mingImage` and everything to run it: the text encoder (with the MoE routing), the DiT conditioning (Z-Image's graph), the 4-channel VAE, editing with reference pictures (the canvas and the Moodboard: the vision tower reads them for the text side, the VAE adds them to the image tokens), the converters for the ComfyUI files of [Comfy-Org/Ming-Image](https://huggingface.co/Comfy-Org/Ming-Image) and its 8-bit S rule. Each part was checked against a PyTorch reference written from inclusionAI's code.

- **Converting the model:** use [Model Converter](https://github.com/EXistenz-78/Fibo-Converter/releases/latest), tab *Ming-Image*. It writes the files with the names the engine looks for and the `custom.json` entry (with the activation scaling below).
- **Settings:** 12 steps, DDIM Trailing, guidance 1, shift about 3.86; 1024 or 2048 pixels on the long side. Transparency needs 1024 px or more and a prompt that asks for it ("RGBA, 4-channel, transparent background").
- **Activation scaling:** in FP16 the model overflows (a black image, no result) when image and text tokens grow, for example above 1216 px with a long prompt. The `custom.json` entry must carry Z-Image Base's `activation_*_scaling` (Model Converter writes it).
- **Z-Image LoRAs:** Ming's DiT is Z-Image's graph with the same weight names, so a Z-Image LoRA runs on Ming as its own (`LoRAZoo.versionForModel(_:runningWith:)`). Its text-encoder part is not used.

## Scheduler

The fork's engine spaces the steps with ComfyUI's schedulers independently of the sampler, but only for local use. The patch in `krea2-edit.patch` carries the choice over gRPC: `GenerationConfiguration` gets an appended field `scheduler` (0 the sampler's own, 1 simple, 2 sgm_uniform, 3 normal, 4 karras, 5 exponential, 6 linear_quadratic, 7 beta), and the server runs the request on a copy of the generator that has it. A client or server without the field sees 0, so nothing changes for them. The Substep samplers and Stable Cascade keep their own schedule; MiniMax H3 Image ignores Shift, as in ComfyUI.

## Seamless tile (new)

`GenerationConfiguration` gets an appended field `seamlessTile` (0 off, 1 left-right, 2 up-down, 3 both): the sampler and decoder wrap around the picture edges on those axes, so the result tiles with no visible seam. It works for Z-Image, FLUX.2, FLUX.3 and Krea 2; the size must be a multiple of 16 px, and the picture is decoded whole (no tiled decoding). A client or server without the field sees 0, so nothing changes for them.

## Krea 2 Edit (new)

The patch in `krea2-edit.patch` lets Krea 2 take reference pictures (the canvas and the Moodboard images) the way the ComfyUI node pack [comfyui-krea2edit](https://github.com/lbouaraba/comfyui-krea2edit) does: each picture is encoded by the VAE and added to the model's token sequence next to the image being generated, aligned with it. Without a reference picture, Krea 2 behaves exactly as before (the same prompt, settings and seed give the same image).

What it does **not** do (the text encoder does not see the picture, no `ref_boost`, no placement options): an edit like "make the cat black" works; instructions that depend on understanding the scene may work less well than in ComfyUI. A Moodboard picture is centre-cropped to the aspect ratio of the output, so choose an output size with the same ratio as your picture to keep it whole (the canvas picture is scaled to the output size by Draw Things before the engine sees it).

To use a Krea 2 Edit LoRA, set its category to **Edit** in DT Hub's LoRA Advisor (DT Hub 1.7.1 or later): DT Hub then sends it with the modifier it needs. With an older DT Hub, its entry in the models folder's `custom_lora.json` must have `"modifier": "kontext"`, like this:

```
{ "file": "krea2_general_edit_v2_lora_f16.ckpt", "name": "K2 General Edit v2", "prefix": "", "version": "krea_2", "is_lo_ha": false, "modifier": "kontext" }
```

With the manual entry, restart DT Hub. Put the picture in the DT Hub Moodboard or Canvas; recommended settings for General Edit V2: Krea 2 Turbo, 8 steps, guidance 1. Use one Edit LoRA at a time.

## Credits

**The engine work (MOSS edit LoRAs, MiniMax H3 Image and the rest of the fork) is by ianiv, the author of [Atelier](https://github.com/ianiv/Atelier).** The Krea 2 Edit, scheduler and Ming-Image patches are by the DT Hub author. This is not an official Draw Things build and not an Atelier release.

- Source: <https://github.com/ianiv/draw-things-community>, branch `atelier-engine`, revision `f4d03b02` (22 November 2026) **plus** `krea2-edit.patch` (in this folder).
- That fork comes from Draw Things' community repository, <https://github.com/drawthingsai/draw-things-community>.
- This revision is newer than the previous DT Hub engine (`8f899411`): it brings the upload checks and `--no-file-upload`, schedulers and four ComfyUI samplers, H3 Image fixes, a fix for masks at few steps, and upstream's Inkling 2 Small and GLM 5.3. `krea2-edit.patch` holds the Krea 2 patch, the scheduler patch, the Ming-Image patch, and the SwiftPM targets of the conversion tools (`ModelConverter`, `QuantI8x`) that Model Converter bundles.
- License: **GPL-3.0**, see `LICENSE.md`. The source of exactly this binary is the revision above with the patch applied; to rebuild it:

```
git init engine && cd engine
git remote add origin https://github.com/ianiv/draw-things-community
git fetch --depth 1 origin f4d03b02
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

Apple Silicon only. Tried by the DT Hub author on macOS 26: Krea 2 Turbo with the General Edit V2 LoRA recolours a picture and keeps the scene; Krea 2 without an Edit LoRA gives the same image as the previous engine for the same prompt, settings and seed. MiniMax H3 Image, MOSS Image edit and Krea 2 Edit were tried by the DT Hub author with this engine before the scheduler field was added. Ming-Image was tried by the DT Hub author: text to image up to 2048 px, transparent output at 1024 px, editing with a reference picture, and a Z-Image LoRA with and without a reference.
