# Panorama 360

A plug-in for DT Hub that makes **360° panoramas** (equirectangular, 2:1) with the *360 ERP outpaint* LoRA of FLUX.2 [klein]. You place pictures («stickers») on a canvas that shows the whole sphere unrolled, write a few words about the place, and press **Send to Generation**: the plug-in sends the canvas, with the stickers drawn on green, as the start image, and the model fills the green with the rest of the panorama.

**Works with:** FLUX.2 [klein] 9B and 4B, **Base** models only. Needs a DT Hub release newer than 0.4.3 (it uses two additions to the plug-in contract: a preset can carry a model and advanced values, and a plug-in can ask for a saved preset to be applied).

## How it works

1. **Canvas.** The picture is always **2048 × 1024**, 360° wide, on `#00ff00`. Drop pictures on it (from the Finder, from a browser, or from DT Hub's Results strip: every file becomes a sticker), or press **+**. The left and right edges are the same place: a sticker that crosses the edge comes back on the other side.
2. **Stickers.** Drag one to move it, a corner to make it bigger or smaller (that changes its field of view), the round handle to turn it (Shift snaps to 45°). The arrow keys move it by 1° (Shift 5°), ⌫ deletes it, ⌘D duplicates it. The **Stickers** card lists them: drag a row to set the order of the layers (the top row is on top); its eye shows or hides a sticker and its numbers are: yaw (0 is straight ahead, positive to the right), pitch (positive is up), rotation, field of view and opacity.
3. **The size of a sticker is an angle.** A photo that carries its focal length in the EXIF data (the 35 mm equivalent, which already includes the size of the sensor) starts at the angle it really covers, so photos taken with different lenses keep their scale. Without it, or when the photo has been cropped, it starts at 60°; you can change it.
4. **Prompt.** Describe the place (light, season, style). **Improve prompt** asks the local LLM to rewrite it as a short English description, **Undo** brings the old text back. The LoRA's own trigger phrase («fill the green spaces…») is added by DT Hub in front of the prompt: never write it yourself.
5. **Normal / Fast.** Normal uses the preset `PAN · 360 ERP` (the base model alone); Fast uses `PAN · 360 ERP Fast` (the same, with the KV refiner).
6. **Send to Generation** applies the preset, puts the canvas as the start image (strength 1) and writes the description in the prompt and 2048 × 1024 as the size. Then press RUN in DT Hub.

Only 2048 × 1024 works well: at 1024 × 512 the sky holds but water and ground come out streaky.

## The presets are yours

The first time DT Hub starts with the plug-in, it adds `PAN · 360 ERP` and `PAN · 360 ERP Fast` to the Preset menu. After that it never touches them: change them as you like (the 4B model and its LoRA, other quantisations, other steps). Values of the shipped ones:

| | `PAN · 360 ERP` | `PAN · 360 ERP Fast` |
| --- | --- | --- |
| Model | `flux_2_klein_base_9b_i8x.ckpt` | the same |
| Refiner | none | `flux_2_klein_9b_kv_i8x.ckpt`, from 0.25 |
| Steps / guidance / sampler / shift | 16 / 4 / 16 / 3 (shift worked out from the size) | the same |
| LoRA | `f2_360_erp_outpaint_lora_v1_lora_f16.ckpt` at 1 | the same |

If the preset's model or LoRA is not installed, the plug-in shows what DT Hub says. If a model that is not a Base one ends up selected, a warning says that the LoRA works only with Base models.

## Where to get the LoRA

By [nomadoor](https://huggingface.co/nomadoor), one for each size (put the file in Draw Things' LoRA folder, or import it from Draw Things; the name above is the one Draw Things gives it):

- FLUX.2 [klein] **9B** Base: [Hugging Face](https://huggingface.co/nomadoor/flux-2-klein-9B-360-erp-outpaint-lora). The licence follows the base model: the FLUX non-commercial licence v2.1.
- FLUX.2 [klein] **4B** Base: [Hugging Face](https://huggingface.co/nomadoor/flux-2-klein-4B-360-erp-outpaint-lora). Apache-2.0 in the model's metadata; the card asks to follow the licence of the base model.

Use the **Base** models (`flux_2_klein_base_9b…`, `flux_2_klein_base_4b…`), not the distilled ones: the LoRA hardly works with those.

## Data and credits

- The master prompt of *Improve prompt* is `~/Library/Application Support/DT Hub/Data/panorama-360/master-prompt.md`; yours goes in `custom/master-prompt.md` in the same folder.
- Each project keeps its stickers (the pictures are copied into the project, reduced to 2048 px on the long side) and its text in its own folder.
- The idea and the maths of placing pictures on the sphere come from [ComfyUI-Panorama-Stickers](https://github.com/nomadoor/ComfyUI-Panorama-Stickers) by nomadoor (MIT); the plug-in is a new implementation in Swift and Metal.

## Build

```bash
Plugins/Panorama360/Scripts/build.sh "$TMPDIR/p360"
cd Plugins/Panorama360 && swift test
```

Then add the bundle in DT Hub › Preferences › Plug-ins.
