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

## Write with LLM

One button, with the language model chosen in the app. It sends the text and the description of each box as Markdown blocks and **replaces the texts in the fields**. The LLM translates into English and enriches the words around the placeholders, and is told **never to touch what is between `<` and `>`**: the plug-in checks that too (every placeholder you wrote stays, none is invented, quoted words are copied) and keeps your original text for a part that fails. The text may gain the citation of an element it forgot. **Undo** puts the previous texts back (the last writing only). By default the LLM does not see the pictures; the checkbox **Send the cropped pictures to the LLM** attaches, for each box drawn on a Moodboard picture, the crop of that box (it needs a model that can read images; with another one the texts are written without them).

The request, the raw answer and the previous texts are saved in the `llm` folder next to `state.json` in the project; the master prompt is `Data/flux3-editing/master-prompt.md` (and `custom/master-prompt.md` for your own notes).

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
