# Flux3 Editing

> **Works with:** FLUX.3 [klein] 5.6B (editing with reference pictures and boxes), in all its variants (`flux3_5b`: Base, 8-bit, 4-bit, Exact).
> On any other family the plug-in is switched off and its tab is hidden. It needs **DT Hub 0.4.0 or later** (the number is provisional) and a **start image** in the Control tab.

A DT Hub plug-in that builds the **editing prompt of FLUX.3 with reference pictures**: a short text that cites the pictures (`<ref_image_0>`, `<ref_image_1>`…) and the elements (`<id>`), and a JSON array that says, for each element, **where to take it from** and **where to put it**. You draw the boxes on the real pictures; the result goes to the Prompt field of the Generation tab.

```
Modify <ref_image_0> by adding the table lamp <lamp_1> from <ref_image_1> on the sideboard. Keep everything else unchanged.

[
  {
    "id": "lamp_1",
    "from": "ref_image_1",
    "src_bbox": [250, 180, 820, 620],
    "tgt_bbox": [300, 550, 550, 720],
    "desc": "A ceramic table lamp, preserving its exact design and details."
  }
]
```

Boxes are `[top, left, bottom, right]` on a 0–1000 grid, each one on its own picture. The start image is `ref_image_0`; the pictures of the Moodboard that are **on** follow in the order of the thumbnails (`ref_image_1`, `ref_image_2`…): the number is the one on the badge in the Control tab, minus one.

## The three cards

1. **Moodboard** — the picture shown with `‹` `›` to move through the others. Draw a box on what you want to take: its pair appears on the start image, where you can move and resize it. Each picture keeps its own boxes.
2. **Start image** — the output canvas (the proportions of the Generation), with the picture placed and zoomed as in the Control tab. Draw a box here for something that is not taken from a reference. Needs DT Hub 0.4.0 or later to know where the picture sits in the canvas; with an older app the whole picture is shown fitted to the canvas, and the plug-in says so.
3. **Prompt** — the text and one small card per box. In the text, `<e` completes to `<el_` and `<r` to `<ref_image_`, and the first digit after them closes the tag with `>`; each `<id>` is coloured like its box and its card.

Each pair has its own colour on both pictures; the box of origin is dashed, the one of destination solid.

## The kinds of box

| Kind | `from` | `src_bbox` | `tgt_bbox` |
|---|---|---|---|
| **From reference** (drawn on the Moodboard) | `ref_image_N` | on that picture | on the start image |
| **New** | `null` | `null` | the box |
| **Existing** (keep it, or change it: the description says which) | `ref_image_0` | the box | the same box |
| **Move** (two boxes, with an arrow) | `ref_image_0` | where it is | where it goes |
| **Remove** | `ref_image_0` | the box | `null` |

A box drawn on the start image is **New**; the menu of its card turns it into the other kinds. A pair from a reference cannot change kind: delete it and draw it again.

## Improve prompt

One button, with the language model the app uses for this model family (Settings › LLM). It rewrites the general text and the description of each box and **replaces the texts in the fields**; **Undo** puts the previous texts back (the last run only). The pictures always go along: the start picture as the canvas of the result and the Moodboard pictures you drew on. The plug-in picks one of two ways to write, and says which in the status line («Improved with <model> (PUP mode)»):

- **PUP mode.** If the model assigned to the family (or, failing that, to «all others») is BFL's own prompt upsampler `flux-3-image-klein-pup` (the plug-in recognises it by `system_prompts.json` with an `i2i_bbox` entry in the model's folder, and reads the official system prompt from there), one request in its native format goes out: the raw pictures (prepared as BFL does: sides in multiples of 32, a pixel budget by number of pictures, JPEG q92), your text and the table of boxes as «locked annotations». The answer is reconciled with your boxes: ids, `from` and coordinates stay as you drew them, the model's paragraph becomes the text and its descriptions replace yours. Rows the model adds (for example the girl as an anchor element) are kept, shown read-only under the boxes with **Remove**, and go into the final prompt. A new object is written with `from: "target"`, as BFL does. Every request names the model, so the plug-in is sure who answers.
- **Standard mode.** With any other language model: the texts are sent as Markdown blocks (the general text and each description), with the pictures drawn with the boxes and their ids. The master prompt (`Data/flux3-editing/master-prompt.md`, and `custom/master-prompt.md` for your own notes) teaches the model to write the general text as an instruction with the knock-on effects of the change (shadows, reflections, occlusion, scale, lighting) and a closing «everything else stays identical», and each description as the static appearance of its element only; focus and blur are never mentioned unless you ask. The plug-in checks the answer (every placeholder stays, none is invented, quoted words are copied) and keeps your text for a part that fails.

If PUP mode fails twice (an id not cited, a quoted word changed, Italian left over), the same model writes in standard mode; if that fails too, your texts stay. The request, the raw answer and the previous texts are saved in the `llm` folder next to `state.json` in the project.

**A tip from the tests:** FLUX.3 [klein] places an object from a reference best when the scene shows depth. With a very blurred background the object tends to look pasted; sharpening the background first and then adding the object gives a much better result.

**Send** is disabled while there is no start image, no box, a description is missing (New, From reference, Existing), an id is empty or repeated, or a box points to a picture that is no longer on in the Moodboard (the box stays, out of the text, until the picture is back or you delete it).

## Build and test

```
Plugins/Flux3Editing/Scripts/build.sh "$TMPDIR/f3e"      # → Flux3Editing.dthubplugin
cd Plugins/Flux3Editing && swift test
```

`F3E_RENDER_DIR=<folder> swift test --filter RenderTests` saves PNGs of the tab. Install in DT Hub: Preferences › Plug-ins › Add…, then restart.

## What is still to be verified

These are assumptions, still to be checked with FLUX.3 in Draw Things, each in one place of the code: the numbering of the pictures (`RefNumbering`), the 0–1000 scale (`BBoxScale`), that the model receives the start image as the output canvas, and that **Remove** is written with `tgt_bbox: null` as BFL documents.

Sources: BFL documentation (`docs.bfl.ai/flux_3/flux3_image_bounding_boxes`, `…/guides/prompting_editing_multi_reference`).
