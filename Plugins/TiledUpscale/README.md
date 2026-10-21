# Tiled Upscale

A plug-in for DT Hub that enlarges a picture **2× or 4×** and gives it new detail tile by tile, with an edit model: the picture is enlarged once (bilinear), cut into overlapping tiles, and each tile is regenerated with a preset and a LoRA. Every result is put back into the picture before the next tile is cut, so the part a tile shares with its neighbour is already enlarged, and a mask, a fade of the join and a correction of the brightness keep the join invisible.

**Works with:** edit and in-context models, with a preset for **FLUX.2 [klein] 9B**, **Qwen Image 2.1 Turbo** and **Qwen Image 2.1** (see *Models*); any other model shows a notice and the *Prepare* button stays off. **Needs DT Hub 0.3.6 or later** (0.3.2 works, but the last tile is then missing from the preview and from the picture) (the pipeline a plug-in guides, see `PluginKit/README.md`). No network.

## How it works

1. Drop or open a picture, choose the enlargement (2× or 4×), the overlap between tiles (256 or 320 px) and the strength of the LoRA. The **tile size sets itself** from the picture (see below); the *Advanced* section, closed by default, holds the rest.
2. Optionally write **additional instructions**: they are added to the preset's prompt of every tile, and can be changed while the job waits or runs (the next tile reads the new text). The tab shows the final size, the tiles, the **number of passes** and the megapixels the model will make, over a preview: the enlarged picture faded, with the grid of the tiles on it. Press **Prepare** (a very big job asks for a second press): the plug-in registers its preset and proposes a pipeline.
3. Press **RUN** in DT Hub. The app asks the plug-in for each pass in turn; DT Hub shows "Pass k of N", Stop ends the job, and no other pipeline or RUN can start meanwhile. Each tile that comes back is drawn over the preview at full opacity, covering the grid, so a join that is not clean shows instead of being masked by a line.
4. When the last tile is back the picture goes to **DT Hub's Results**: it is saved in the project's folder and put first in the strip (the side panel says «Tiled Upscale 4× · 3×3 tiles · LoRA 1.00 · tile 1536 · free 256 · …», with the time the whole pipeline took), and the pipeline leaves the Run button. *Use as start image* sends it to the Control tab. The pictures of the single passes are not results: they do not go to the Results strip or to the project's folder.

## Making one tile again

When a run is finished the picture stays in the plug-in. Click a tile in the preview to pick it (click again to let it go), optionally write instructions **for that tile only** (added after the general ones), and press **Regenerate tile**. The plug-in proposes a one-pass pipeline: press **RUN**. The tile starts **from the original** (the enlarged source, not the result that is there); the strips it shares with the tiles above and on the left are what those tiles made, so the join is kept. The seed is random, so every try differs. The new tile replaces the old one, and the whole picture goes to the Results again. The join with the tiles to the right and below, made from the old tile, can differ a little. Changing the image, the enlargement, the overlap or the advanced values drops the kept picture.

## Models

| | FLUX.2 [klein] 9B | Qwen Image 2.1 Turbo | Qwen Image 2.1 |
| --- | --- | --- | --- |
| Steps / guidance / sampler | 4 / 1 / 16 | 8 / 1 / 16 | 33 / 1 / 16 |
| Shift | 3 | 6.5 | 1 |
| Shift worked out from the size | no | no | yes |
| LoRA (default strength) | `f2_ultra_real_v5_pro_lora_f16` (1) | `q21_detail_fix_2.0_lora_f16` (2.5) | `q21_detail_fix_2.0_lora_f16` (2.5) |
| Prompt | one fixed prompt: «make this photo high-quality. preserve details. preserve overall composition of this photo. Preserve colors and lights.» | one fixed prompt: «Upscale this image to a substantially higher resolution with a decisive gain in clarity…» | the same |

**Where to get the LoRAs** (put the file in Draw Things' LoRA folder, or import it from Draw Things; the names above are the ones Draw Things gives them):

- `f2_ultra_real_v5_pro_lora_f16` — *UltraReal* v5 Pro for FLUX.2 klein 9B by vizsumit: [Civitai](https://civitai.com/models/2462105?modelVersionId=3370879).
- `q21_detail_fix_2.0_lora_f16` — *Qwen Image 2.1 Fix* v2.0 by _Envy_: [Hugging Face](https://huggingface.co/e-n-v-y/Qwen-Image-2.1-Fix-v2.0).

Strength 1 for all. The FLUX prompt is fixed here and the trigger word of the LoRA on the server is not used: it says «face», «expression», «figure» and «pose», and on a tile with no face the model adds one. Turbo is told from the other Qwen by "turbo" in the model's file name. The LoRA strength (−4 to 4, as in the generation tab) is remembered **per preset** and per project. The plug-in never changes the model: it is the one in the header. The values are in `TUPreset.swift`.

## Multiples of 64 and the size of the tile

Draw Things works in multiples of 64 on both sides, and a tile that is not would be resampled, which would shift the pixels the join depends on. So:

- a picture whose sides are already multiples of 64 is enlarged by the chosen factor and nothing is cut; otherwise the enlarged picture is cut, centered, to the lower multiple of 64 (63 px at most per side; the tab says so);
- the **tile size** (1024–2048, steps of 64) is the smallest that needs at most **three tiles along the shorter side** of the enlarged picture: `(side + 2 × overlap) / 3`, rounded up to 64. It is set again when the picture, the enlargement or the overlap change; the slider can then be moved by hand;
- the step between tiles is `tile − overlap`; the last tile of a row or a column is smaller but always a multiple of 64 and wider than the overlap;
- the mask, which only needs to cover the new part, does not have to follow the 64 grid.

Bigger tiles mean fewer joins and more of the picture in each tile, so the model has more to go on (it stops mistaking hair for bamboo). The cost per tile grows much more slowly than the area: a 4× enlargement of a 1000 px picture took about 800 s as 25 tiles of 1024 and about 360 s as 9 of 1536.

Limits: over 16 384 px on a side or 268 megapixels the plug-in refuses; over 100 megapixels or 100 passes it asks for a confirmation.

## The mask, the join and the brightness (*Advanced*)

The values start at the ones found by trying, for the overlap chosen, and a button puts them back.

- **Free part of the overlap** (default the overlap minus 64 px: 192 of 256, 256 of 320): how much of what the neighbour already made is kept as it is (the first tile has no mask; the first row has the free strip on the left only, the first column on top only, the others both). The rest is regenerated.
- **Blur of the mask** (0–30, default 30) and **margin of the mask** (0–100, default 29): Draw Things' own mask settings; *Keep the original outside the mask* is on.
- **Fade of the join** (0 to what the free part leaves of the overlap, default 64 px): before a tile is sent to the model, the neighbour's result is faded into the enlarged source over that many pixels, ending at the end of the overlap. Without it the tile has a hard edge there (sharp on one side, soft on the other, with the tone of the neighbour on one side and of the source on the other) that the model takes for a part of the picture and repeats. The fade has to stay inside the regenerated part (the free part is put back as it was sent), so its slider stops at *overlap − free part*.
- **Brightness correction** (0–100 %, default 100) and its **radius** (16–256 px, default 16): the model tends to make a tile lighter or darker than the source (2 to 4.7 times, by what the tile shows), so two neighbours come out at different levels and no fade can hide the step. Each result is brought back to the source's brightness before it is composed (and before the next tile is cut): where the enlarged source is brighter or darker than the result over a wide area, the colours of the result are scaled by the ratio of the two (limited to 0.2–5). The hue and the fine detail stay, only the slow drift of the level goes. It grows from the edge of the tile that meets the neighbour over 64 px, so it makes no step of its own (it must not start at the edge of the mask: the model changes the tile also before it, and a correction that began there would leave that part light, a bright band). The radius says what is "slow": smaller follows the source more closely, bigger corrects only the wide drifts.

The values are kept per project, and the picture in the Results says which ones were used, to compare tries.

## Files

- `TileGrid.swift`: the geometry (enlarged size, tiles, masks). `TUStore.swift`: the settings, their defaults and the automatic tile.
- `TUImage.swift`: the picture work (a canvas that cuts tiles out and puts them back row by row, so no pixel moves; the small preview).
- `TUFade.swift`, `TUTone.swift`: the fade of the join and the brightness correction.
- `TUSession.swift`: one enlargement, from `session.next` to the composed picture.
- `TUPreset.swift`: the presets and the prompts.
- `TUState.swift`, `TUView.swift`, `TiledUpscalePlugin.swift`: the tab and the plug-in.

Spec: `docs/superpowers/specs/2026-10-18-plugin-tiled-upscale-design.md` (the first version; the values and the controls above are the ones found by trying since).

## Build and test

```sh
cd Plugins/TiledUpscale && swift test
Plugins/TiledUpscale/Scripts/build.sh "$TMPDIR/tu"   # → TiledUpscale.dthubplugin
```
