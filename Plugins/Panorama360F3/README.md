# Pano 360 F3

A plug-in for DT Hub that makes **360° panoramas** (equirectangular, 2:1) with **FLUX.3 [klein]** and two LoRAs by [denrakeiw](https://civitai.com/user/denrakeiw): *360 Degree [Flux]* (Flux 3 Klein version) and *360 Flux 2/3 Klein Seamfix*. You put one or more **reference pictures** in the Moodboard of the plug-in, write (if you want) a few words about the place, and press **Send to Generation**: DT Hub then runs **two passes in one pipeline**, the panorama and the repair of its seam, and puts the finished panorama in the Results.

**Works with:** FLUX.3 [klein] 5.6B (`flux3_5b`). Needs **DT Hub 0.7.0 or later** (provisional number: it uses an addition to the guided pipelines, a pass with its own Moodboard and no start image).

For the same job on FLUX.2 [klein], with pictures placed on a canvas, see [Panorama 360](../Panorama360/README.md): the 360 LoRA of FLUX.3 does not outpaint a green canvas, it builds the panorama from reference pictures.

## The three cards

1. **Moodboard.** Drop pictures (from the Finder, a browser or DT Hub's Results strip) or press **+**. The badge of each row is the number the model sees (`<image 1>`, `<image 2>`…): drag a row onto another to reorder, the eye turns a picture off (it is not sent and not numbered), the bin deletes it. The pictures are copied into the project, reduced to 2048 px on the long side. At the bottom right, the **size selector** keeps the panorama 2:1: it starts at **2048 × 1024**, `^` adds 128 × 64 and `v` takes them away (1024 × 512 … 8192 × 4096; above 2048 on a side HiRes must be on, which both presets have).
2. **Prompt.** The description of the place is optional: **Improve prompt** asks the local LLM to write one in English from the pictures (**Undo** brings the old text back). **Send to Generation** (top right of the card) is off until there is a picture with its eye on.
3. **Viewer.** The sphere view of the latest result, closed at first: it opens by itself when a panorama arrives (or by the arrow). Drag to look around, the wheel or a pinch to zoom, the target button looks straight ahead. You can **drop any picture** on it (from the Finder or the Results strip): it is shown as the result and **Fix the seam** works on it.

   The **Cutout** is on the header of the Viewer, as in Panorama 360: set the size in megapixels and press **Extract** to take the view you are looking at as a flat 4:3 picture (1.0 MP is 1280 × 960). Then **Use as start image** (it also sets the Generation tab's size to the cutout's), **Add to Moodboard** (DT Hub's own Moodboard) or **Save…** let you retouch it with an edit model (switch the 360 LoRA off first); when the RUN ends, **Put back in the panorama** pastes the retouch, with a soft edge, on the panorama the cutout was taken from and sends the montage to the **Results**. The montage is made on the panorama **enlarged** until the retouch has its own pixels (up to 8192 × 4096), so it does not lose detail.

## What the pipeline does

The prompt of the first pass is `starting from <image 1>, <image 2>…` followed, when you wrote one, by `. ` and your description. DT Hub puts the LoRA's trigger word (`create a 360 hdr`) in front: never write it yourself.

| Pass | Preset | Pictures | Size | Prompt |
| --- | --- | --- | --- | --- |
| 1 · Panorama | `PANO F3` | your Moodboard pictures, **no start image** (empty canvas) | the one you chose | `starting from <image 1>…` (+ description) |
| 2 · Seam | `PANO F3 Seamfix` | **only** the square below, as the start image, **no Moodboard** | the panorama's height, squared | empty (the trigger is `seamfix`) |

**The Seamfix square.** For a panorama W × H the plug-in builds an H × H square: the right end of the panorama, then its left end (a quarter of the width each), so the seam is in the middle, covered by a **white bar** an eighth of the width wide. The model fills the bar. The plug-in then puts the two halves back at the ends of the panorama, with its colour brought to the panorama's (Reinhard, in lαβ) and a soft edge on the inner side; the rest of the panorama stays pixel for pixel. If the second pass fails or is stopped, the **raw panorama of the first pass** still goes to the Results.

Every pass asks for a new random seed and sends `highRes` on. **Fix the seam** (in the Viewer) runs the second pass alone on the panorama shown; it is off, with the reason in its tooltip, when there is no result, the picture is not 2:1, its height is not a multiple of 64 or it is taller than 4096 px.

## The presets are yours

The first time DT Hub starts with the plug-in, it adds `PANO F3` and `PANO F3 Seamfix` to the Preset menu; after that it never touches them. Values of the shipped ones:

| | `PANO F3` | `PANO F3 Seamfix` |
| --- | --- | --- |
| Model | `flux_3_klein_q8p.ckpt` | the same |
| Steps / guidance / sampler / shift | 24 / 1 / 16 / 16 | 16 / 1 / 16 / 16 |
| HiRes | on | on |
| LoRA | `f3_360_lora_f16.ckpt` at 1, trigger `create a 360 hdr` | `f3_seamfix_lora_f16.ckpt` at 1, trigger `seamfix` |

A guided pass always runs on the model chosen in DT Hub's header: pick the model of the presets before pressing RUN (the note after the button says which one if they differ).

## Where to get the LoRAs

By denrakeiw (put the files in Draw Things' LoRA folder, or import them from Draw Things; the names above are the ones Draw Things gives them). Trained on the **Base** model; the licence is the FLUX Kommunity License.

- [360 Degree [Flux]](https://civitai.com/models/682349/360-degree-flux): the *Flux_3_Klein* version, file `360_f3.safetensors`.
- [360 Flux 2/3 Klein Seamfix](https://civitai.com/models/2709848/360-flux-klein-seamfix), file `F_3_seamfix.safetensors`.
- The author's ComfyUI workflow for the same job: [360 Flux Klein Comfyui Workflow](https://civitai.com/models/2709871/360-flux-klein-comfyui-workflow).

## Not in this version

The queue of generations, the «put back as a sticker» of Panorama 360, pictures placed on a canvas.

## Data and credits

- The master prompt of *Improve prompt* is `~/Library/Application Support/DT Hub/Data/panorama-360-f3/master-prompt.md`; yours goes in `custom/master-prompt.md` in the same folder.
- Each project keeps its pictures and its text in its own folder (`images/`, `state.json`).
- The LoRAs and the workflow this plug-in follows are by **denrakeiw**. The spherical viewer and the drop code are adapted from the *Panorama 360* plug-in of this repository.

## Build

```bash
Plugins/Panorama360F3/Scripts/build.sh "$TMPDIR/pf3"
cd Plugins/Panorama360F3 && swift test
```

Then add the bundle in DT Hub › Preferences › Plug-ins.
