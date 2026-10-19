# Tiled Upscale Lab

An **experimental fork** of [Tiled Upscale](../TiledUpscale/README.md), kept apart so the original stays as it is: its own id (`com.exiztenz.dthub.tiledupscalelab`), its own name in the tab bar and its own files. The enlargement (2× or 4×, tiles with a 256 or 320 px overlap, multiples of 64, FLUX.2 [klein] 9B with its LoRA, the preview, the result in the Results) works as in the original; what the Lab adds is what the original fixes:

- **Advanced** (closed by default; its values start at the ones found by trying, for the overlap chosen, and a button puts them back): the free part, the blur and the margin of the mask, the fade of the join, and the correction of the brightness with its radius.
- **Free part of the overlap** (0 to the overlap, default the overlap but 64 px: 192 of 256, 256 of 320): how much of what the neighbour already made is kept as it is; the rest of the overlap is regenerated.
- **Blur of the mask** (0–30, default 30) and **Margin of the mask** (0–100, default 29): Draw Things' own mask settings.
- **Fade of the join** (0 to what the free part leaves of the overlap, default 64 px): before a tile is sent to the model, the neighbour's result is faded into the enlarged source over that many pixels, ending at the end of the overlap. Without it the tile has a hard edge there (sharp on one side, soft on the other, with the tone of the neighbour on one side and of the source on the other) that the model takes for a part of the picture and repeats: the seam seen at 256 px from the edge of some tiles at 4×. With 0 the Lab behaves as the original. The fade has to stay inside the regenerated part (the free part is put back as it was sent), so its slider stops at *overlap − free part*.

- **Tile size** (1024–2048, steps of 64), **set by itself** from the picture: the smallest tile that needs at most three tiles along the shorter side of the enlarged picture (`(side + 2 × overlap) / 3`, rounded up to 64), when the picture, the enlargement or the overlap change; the slider can then be moved by hand. A bigger tile means fewer joins and more of the picture in each tile, so the model has more to go on (a 4× enlargement of a 1000 px picture goes from 25 passes at 1024 to 9 at 1536, in less time overall). The summary says how many megapixels the model will make.
- **Brightness correction** (0–100 %, default 100) and its **radius** (16–256 px, default 16): the model tends to make a tile lighter or darker than the source, by an amount that depends on what the tile shows, so two neighbours come out at different levels and no fade can hide the step. Each result is brought back to the source's brightness before it is composed (and before the next tile is cut): where the enlarged source is brighter or darker than the result over a wide area, the colours of the result are scaled by the ratio of the two (limited to 0.5–2). The hue and the fine detail stay, only the slow drift of the level goes. It acts only on the regenerated part and grows from the edge of the mask over 48 px, so it makes no step of its own. The radius says what is "slow": smaller follows the source more closely, bigger corrects only the wide drifts.

The values are kept per project, and the picture in the Results says which ones were used («Tiled Upscale Lab 4× · 5×5 tiles · LoRA 1.00 · free 200 · blur 30 · margin 30 · fade 48»), to compare tries.

**Models.** The Lab has a preset for **FLUX.2 [klein] 9B** (LoRA `f2_ultra_real_v5_pro_lora_f16`, prompt = the LoRA's trigger word + the fixed sentence), for **Qwen Image 2.1 Turbo** (8 steps, shift 6.5, shift not worked out from the size) and for **Qwen Image 2.1** (40 steps, shift 1, shift worked out from the size). Both Qwen presets use the LoRA `q21_detail_fix_2.0_lora_f16` at 2.5 and one fixed prompt ("Upscale this image to a substantially higher resolution with a decisive gain in clarity…", with no trigger word). Turbo is told from the other by "turbo" in the model's file name. Guidance 1, sampler 16 and strength 1 for all. The LoRA strength is remembered **per preset** (and per project): each starts from its own (1 for FLUX, 2.5 for Qwen).

Both plug-ins can be installed together; use one at a time (each proposes its own pipeline).

```sh
cd Plugins/TiledUpscaleLab && swift test
Plugins/TiledUpscaleLab/Scripts/build.sh "$TMPDIR/tul"   # → TiledUpscaleLab.dthubplugin
```
