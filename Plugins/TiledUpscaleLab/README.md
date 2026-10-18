# Tiled Upscale Lab

An **experimental fork** of [Tiled Upscale](../TiledUpscale/README.md), kept apart so the original stays as it is: its own id (`com.exiztenz.dthub.tiledupscalelab`), its own name in the tab bar and its own files. The enlargement (2×, 4× or 8×, tiles of at most 1024 px with a 256 or 320 px overlap, multiples of 64, FLUX.2 [klein] 9B with its LoRA, the preview, the result in the Results) works as in the original; what the Lab adds is what the original fixes:

- **Free part of the overlap** (0 to the overlap, default 200 px): how much of what the neighbour already made is kept as it is; the rest of the overlap is regenerated.
- **Blur of the mask** (0–30, default 30) and **Margin of the mask** (0–100, default 30): Draw Things' own mask settings.
- **Fade of the join** (0 to what the free part leaves of the overlap, default 48 px): before a tile is sent to the model, the neighbour's result is faded into the enlarged source over that many pixels, ending at the end of the overlap. Without it the tile has a hard edge there (sharp on one side, soft on the other, with the tone of the neighbour on one side and of the source on the other) that the model takes for a part of the picture and repeats: the seam seen at 256 px from the edge of some tiles at 4×. With 0 the Lab behaves as the original. The fade has to stay inside the regenerated part (the free part is put back as it was sent), so its slider stops at *overlap − free part*.

The values are kept per project, and the picture in the Results says which ones were used («Tiled Upscale Lab 4× · 5×5 tiles · LoRA 1.00 · free 200 · blur 30 · margin 30 · fade 48»), to compare tries.

Both plug-ins can be installed together; use one at a time (each proposes its own pipeline).

```sh
cd Plugins/TiledUpscaleLab && swift test
Plugins/TiledUpscaleLab/Scripts/build.sh "$TMPDIR/tul"   # → TiledUpscaleLab.dthubplugin
```
