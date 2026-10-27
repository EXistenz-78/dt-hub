# Panorama 360

A plug-in for DT Hub that makes **360° panoramas** (equirectangular, 2:1) with the *360 ERP outpaint* LoRA of FLUX.2 [klein]. You place pictures («stickers») on a canvas that shows the whole sphere unrolled, write a few words about the place, and press **Send to Generation**: the plug-in sends the canvas, with the stickers drawn on green, as the start image, and the model fills the green with the rest of the panorama.

**Works with:** FLUX.2 [klein] 9B and 4B, **Base** models only. Needs DT Hub 0.5.0 or later (it uses additions to the plug-in contract: a preset can carry a model and advanced values, a plug-in can ask for a saved preset to be applied, the context carries the latest result, and a plug-in can send a result to the Results at any time).

## How it works

1. **Canvas.** The picture is always **2048 × 1024**, 360° wide, on `#00ff00`. Drop pictures on it (from the Finder, from a browser, or from DT Hub's Results strip: every file becomes a sticker), or press **+**. The left and right edges are the same place: a sticker that crosses the edge comes back on the other side.
2. **Stickers.** Drag one to move it, a corner to make it bigger or smaller (that changes its field of view), the round handle to turn it (Shift snaps to 45°). The arrow keys move it by 1° (Shift 5°), ⌫ deletes it, ⌘D duplicates it. The **Stickers** card lists them: drag a row to set the order of the layers (the top row is on top); its eye shows or hides a sticker and its numbers are: yaw (0 is straight ahead, positive to the right), pitch (positive is up), rotation, field of view and opacity.
3. **The size of a sticker is an angle.** A photo that carries its focal length in the EXIF data (the 35 mm equivalent, which already includes the size of the sensor) starts at the angle it really covers, so photos taken with different lenses keep their scale. Without it, or when the photo has been cropped, it starts at 60°; you can change it.
4. **Prompt.** Describe the place (light, season, style). **Improve prompt** asks the local LLM to rewrite it as a short English description (the canvas goes along as a full-size picture, so the LLM describes what must complete the parts that are not green; your text is then only a guide and the field may even be empty), **Undo** brings the old text back. The LoRA's own trigger phrase («fill the green spaces…») is added by DT Hub in front of the prompt: never write it yourself.
5. **Normal / Fast.** Normal uses the preset `PAN · 360 ERP` (the base model alone); Fast uses `PAN · 360 ERP Fast` (the same, with the KV refiner).
6. **Send to Generation** applies the preset, puts the canvas as the start image (strength 1) and writes the description in the prompt and 2048 × 1024 as the size. Then press RUN in DT Hub.

Only 2048 × 1024 works well: at 1024 × 512 the sky holds but water and ground come out streaky.

## Looking around: the sphere view

**View** at the top of the card chooses **Plane** (the unrolled canvas above) or **Sphere**: you stand in the centre and look outwards. In the sphere view the picture is 4:3, and next to it **Canvas | Result** says what you look at:

- **Canvas** is your stickers on green. You can edit them from inside: drag one to move it, a corner to scale it, the round handle to turn it, exactly as on the plane. Drag the empty view to look around, the wheel or a pinch to zoom (the field of view goes from 20° to 160°), the crosshair button looks straight ahead again.
- **Result** is the picture the last RUN made, shown as a panorama, for looking only (no handles, `+` and the bin are off). It updates by itself when a RUN ends. It is off until the project has a result.
  You can also **drop any picture** (from the Finder, or from DT Hub's Results strip) on the view: it is shown as the result, and Cutout and *Fix the seam* work on it. It stays until the app tells about a newer result or you open another project. A file that cannot be read says so and changes nothing.

The view, the source and where you look are saved with the project.

## Cutout: take a piece, retouch it, put it back

In the sphere view the **Cutout** panel takes what you see as a flat 4:3 picture (**Extract**; the size is in megapixels, 1.0 by default, always exactly 4:3 with sides in multiples of 64: 1.0 MP is 1280 × 960). Then:

1. **Use as start image** (it also sets the size of the Generation tab to the cutout's) or **Add to Moodboard** send the picture to the Generation tab, so you can retouch it with an edit model; **Save…** writes a PNG.
2. Run the retouch. Before you do, **switch the 360 LoRA off** (and pick another preset): the last «Send to Generation» left it on the tab, and its trigger phrase would be put in front of your prompt. The model must keep the framing and the size. When the RUN ends its result is the retouch, and two buttons come on:
   - **Put back as a sticker** places it on the canvas exactly where the cutout was taken (same yaw, pitch and angle), so **Send to Generation** can redraw the panorama around it.
   - **Put back in the panorama** pastes it, with a soft edge, on the panorama the cutout was taken from and sends the new panorama to DT Hub's **Results** (it becomes the latest result; the source **Result** shows it). Nothing else is generated.
3. Both buttons stay on for the same retouch until you extract again. If one is off, its tooltip says why: no cutout yet, no retouch yet, the retouch is not 4:3, its file cannot be read, or (for the panorama) there was no result when the cutout was taken.

## Closing the seam

The left and the right edge of a panorama are the same place, and the model does not always make them meet. In the sphere view with the **Result** as the source, **Fix the seam** (Correggi giunzione) closes it:

1. The plug-in rolls the latest result by half its width, so the seam is in the middle, and paints a **green stripe** over it, as tall as the picture and **an eighth of its width** wide (256 px on a 2048 px panorama).
2. It proposes a one-pass pipeline to DT Hub ("Run · 1 pass") with the preset **`PAN · 360 ERP Fast`** and the whole panorama, stripe included, as the start image, with no mask: the 360 LoRA of the preset fills the green, as it does when you send the canvas. Press RUN. The preset is yours (model, LoRA, steps, refiner); the prompt is the description of the place you wrote in the card (empty if none). A plug-in cannot change the model: DT Hub uses the one chosen in its header, so pick the model your preset was saved with before pressing RUN (if they differ, the notice after the button says which one).
3. When the RUN ends the plug-in takes only the **central quarter of the width** of what the model made (twice the green, so the soft edge falls on picture the model kept) and pastes it into the original panorama with a soft edge, levelling its brightness to the original's (the method Tiled Upscale uses to join its tiles); everything else stays pixel for pixel as it was. It rolls the panorama back and sends it to the **Results**. The picture the model made is not saved.

The button is off, with the reason in its tooltip, when there is no result, the result is not 2:1, its sides are not both multiples of 64 (the whole picture is the pass) or it would pass 2048 px on a side. The pass is as big as the panorama, and Draw Things makes at most 2048 px on a side without HiRes (a bigger pass comes back cut to that and the correction cannot use it). The name of the preset and the fractions of the green and of the band are constants at the top of `PSSeam.swift`.

**In the queue.** With the correction prepared, the **+** of DT Hub's queue sidebar keeps it as an entry: the panorama it was made from (the one at the time of the click, even if a newer result has arrived) is copied into the entry's folder. When the entry runs the plug-in makes the correction again from that copy, without touching the result shown in the tab, and DT Hub presses RUN. The plug-in must be switched on at that moment, otherwise the entry fails (orange X) and the queue goes on.

## The presets are yours

The first time DT Hub starts with the plug-in, it adds `PAN · 360 ERP` and `PAN · 360 ERP Fast` to the Preset menu. After that it never touches them: change them as you like (the 4B model and its LoRA, other quantisations, other steps). Values of the shipped ones:

| | `PAN · 360 ERP` | `PAN · 360 ERP Fast` |
| --- | --- | --- |
| Model | `flux_2_klein_base_9b_i8x.ckpt` | the same |
| Refiner | none | `flux_2_klein_9b_kv_i8x.ckpt`, from 0.25 |
| Steps | 30 | 16 |
| Guidance / sampler / shift | 4 / 16 / 3 (shift worked out from the size) | the same |
| LoRA | `f2_360_erp_outpaint_lora_v1_lora_f16.ckpt` at 1 | the same |

If the preset's model or LoRA is not installed, the plug-in shows what DT Hub says. If a model that is not a Base one ends up selected, a warning says that the LoRA works only with Base models.

## Credits

The idea, the LoRA and the workflow come from **nomadoor**: this plug-in is the DT Hub counterpart of the [ComfyUI-Panorama-Stickers](https://github.com/nomadoor/ComfyUI-Panorama-Stickers) custom nodes (stickers on an equirectangular canvas, a sphere viewer, the LoRA's outpaint). The author's notes on the workflow and the LoRA are on [comfyui.nomadoor.net](https://comfyui.nomadoor.net/en/notes/panorama-stickers/).

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
