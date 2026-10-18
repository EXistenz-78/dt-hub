# Tiled Upscale

A plug-in for DT Hub that enlarges a picture **2×, 4× or 8×** and gives it new detail tile by tile, with an edit model: the picture is enlarged once (bilinear), cut into overlapping tiles, and each tile is regenerated with a preset and a LoRA. Every result is put back into the picture before the next tile is cut, so the part a tile shares with its neighbour is already enlarged, and a mask keeps the join invisible.

**Works with:** edit and in-context models. The first version has a preset for **FLUX.2 [klein] 9B** only (with the LoRA `f2_ultra_real_v5_pro_lora_f16`); other models show a notice and the *Prepare* button stays off. Qwen Image 2.1 will be one more preset. **Needs DT Hub 0.3.2 or later** (the pipeline a plug-in guides, see `PluginKit/README.md`). No network.

## How it works

1. Drop or open a picture, choose the enlargement and the overlap (256 px, or 320 px for a wider join) and the strength of the LoRA.
2. The tab shows the final size, the tiles and the **number of passes**. Press **Prepare** (a very big job asks for a second press): the plug-in registers its preset and proposes a pipeline.
3. Press **RUN** in DT Hub. The app asks the plug-in for each pass in turn; DT Hub shows "Pass k of N", Stop ends the job, and no other pipeline or RUN can start meanwhile.
   While it runs the tab shows the **preview**: the enlarged picture faded, with the grid of the tiles on it; each tile that comes back is drawn over it at full opacity, covering the grid, so a join that is not clean shows instead of being masked by a line. The preview is small (1200 px on the long side): the real picture is never copied for the screen.
4. When the last tile is back the picture is saved on your **Desktop** as `Tiled Upscale 001.png` (the first free number, never overwriting), and *Use as start image* sends it to the Control tab. The pictures of the single passes are not results: they do not go to the Results strip or to the project's folder.

## Multiples of 64

Draw Things works in multiples of 64 on both sides, and a tile that is not would be resampled, which would shift the pixels the join depends on. So:

- a picture whose sides are already multiples of 64 is enlarged by the chosen factor and nothing is cut;
- otherwise the enlarged picture is cut, centered, to the lower multiple of 64 (63 px at most per side; the tab says so);
- tiles are at most 1024 × 1024, the step between them is `1024 − overlap` (768 or 704), and the last tile of a row or a column is smaller but always a multiple of 64 and wider than the overlap;
- the mask, which only needs to cover the new part, does not have to follow the 64 grid.

Limits: over 16 384 px on a side or 268 megapixels the plug-in refuses; over 100 megapixels or 100 passes it asks for a confirmation (8× of a 1024 px picture takes about 120 passes).

## The mask

The first tile has no mask. Every other tile is regenerated everywhere but in the part it shares with the tiles already made, of which **200 px** (250 px with the 320 px overlap, always 25/32 of the overlap) are left free on the left and on top: the first row has the free strip on the left only, the first column on top only, the others both. Blur 30, margin 30, *Keep the original outside the mask* on.

## Files

- `TileGrid.swift`: the geometry (enlarged size, tiles, masks). The constants 1024, 256, 320 and 25/32 live in one place.
- `TUImage.swift`: the picture work (a canvas that cuts tiles out and puts them back row by row, so no pixel moves) and `TUPreview` (the small picture of the tab).
- `TUSession.swift`: one enlargement, from `session.next` to the composed picture.
- `TUPreset.swift`: the preset and the prompt (the LoRA's trigger word + ` ALSO PRESERVE COLORS AND LUMINOSITY`).
- `TUState.swift`, `TUView.swift`, `TiledUpscalePlugin.swift`: the tab and the plug-in.

Spec: `docs/superpowers/specs/2026-10-18-plugin-tiled-upscale-design.md`.

## Build and test

```sh
cd Plugins/TiledUpscale && swift test
Plugins/TiledUpscale/Scripts/build.sh "$TMPDIR/tu"   # → TiledUpscale.dthubplugin
```
