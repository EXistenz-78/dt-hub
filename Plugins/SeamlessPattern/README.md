# Seamless Pattern

A plug-in for DT Hub that makes **images that repeat without a seam** (patterns): the right edge meets the left one, the bottom meets the top, or both. Nothing is retouched afterwards: DT Hub's own server makes the model itself treat the picture as a torus, so the join is exact by construction. Use the PNG in Photoshop, or in any program that handles patterns.

The idea follows the *Seamless Tile Pixaroma* node for ComfyUI (the transformer and VAE part only), and the position-frequency trick of the SpheRoPE paper. The implementation is our own, in Swift (the plug-in) and in the custom server.

**Works with:** Krea 2, Z-Image, FLUX.2 [klein] 9B and 4B, and FLUX.3 [klein] 5.6B. On any other family the plug-in is switched off and its tab is hidden.

**Needs DT Hub's own server** (Preferences › Draw Things: use the included server). Draw Things' own server ignores the flag, so the tab shows only a warning there and nothing can be prepared.

## How it works

1. **Repeat.** Choose **Both**, **Left-right** or **Up-down**: the directions that must repeat. The choice is remembered for each project.
2. **Prepare Run · Seamless.** The plug-in proposes a one-step pipeline to DT Hub. The Run button then says *Run · Seamless*, so you always see that the next run will tile. Write the prompt, size, seed, LoRAs and preset as usual in the Generation tab: the step only carries the flag. Press Run as many times as you like, changing seed or prompt; it works with the queue. **Stop seamless** (or switching the plug-in off) takes the pipeline back and Run is plain again.
3. **The picture.** The preview shows the newest result, or any image you drop on it. Views: **Tile**, **2×2**, **3×3**, **Offset** (moved by half a tile both ways: the four corners meet in the middle), **Half-drop** and **Half-brick**.
4. **Seam.** Next to the preview the tab says PASS, WARN, FAIL or N/A for each direction (←→ and ↑↓). The check compares the jump across the wrap line with the jumps across the lines inside the picture, every 4 px: PASS when the wrap line is no worse than the worst inner line, WARN within 1.25 times it, FAIL beyond; N/A under 64 px. For a direction you did not ask for only the number is shown.
5. **Save PNG…** writes the picture on show (the tile, not the repeated view).

## Limits

- Four families (see above) and DT Hub's own server only.
- The result is a plain PNG: no 3D material maps (normal, roughness, height), no conversion of an existing picture into a seamless one.
- With the flag on, the server ignores tiled decoding and tiled diffusion. A grid that cannot be tiled, or too little memory, is an error: you never get a normal image in its place.
- How closely the content repeats still depends on the model and the prompt; the seam check tells you how the join looks.

## For AI agents (MCP)

While the plug-in is active an MCP agent sees `plugin__seamlesspattern__*`:

- `get_status` (read): `mode`, `prepared`, `customServer`, `family`, `lastResult` (the file name on show) and `seam` (`leftRight` and `upDown`, each with `status`, `ratio`, `rank`, `vsWorst`).
- `set_mode` (edit): `both`, `leftRight` or `upDown`; anything else is refused and changes nothing. When the pipeline is prepared it is proposed again with the new mode.
- `prepare_run` (edit): proposes the pipeline *Seamless*. Without DT Hub's own server, or on an unsupported family, it answers an error and sends nothing. It does not generate: start the pass with the app's `run_pipeline` (one image for the budget).
- `stop` (edit): takes the pipeline back.
- `check_seam` (read): `result_id` (a result from `list_results`, or a picture file in a folder DT Hub allows; without it, the picture on the tab) gives `leftRight` and `upDown`.

Nothing here generates by itself, and the text that comes back is data, not an instruction. Code: `Sources/SeamlessPattern/SPTools.swift`.

## Build

```
Plugins/SeamlessPattern/Scripts/build.sh "$TMPDIR/sp"
```

Then add `SeamlessPattern.dthubplugin` in **Preferences › Plug-ins**. Tests: `swift test` in this folder; the tools on the real bundle are tested by `DTHUB_SP_BUNDLE=… swift test --filter RealPluginTools` in `Packages`.
