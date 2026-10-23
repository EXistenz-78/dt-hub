# Prompt Master MOSS

> **Works with:** MOSS Image (Base and SFT, `moss_image` / `mossImage`). On any other family the plug-in is switched off and its tab is hidden.

A DT Hub plug-in that builds the **JSON layout prompt of MOSS Image**: a `summary` of the whole picture and a flat list of `items`, each with a label, a caption and a box. The result goes to the Prompt field of the Generation tab, and the negative terms to the negative field.

```json
{"summary":{"meta":["photograph"],"canvas":"single","caption":"A Japanese girl in a red kimono in a bamboo forest."},
 "items":[{"label":"object","caption":"A paper umbrella of bamboo and rice paper.","bbox":[-290,-362,10,288]},
          {"label":"text","caption":"Small white serif lettering.","text":"Kyoto\nArashiyama","bbox":[220,-472,290,-212]}],
 "bbox_coord_space":"abs_centralized","bbox_format":"yxyx"}
```

Plain natural-language prompts for MOSS are covered by the app's own Family prompt; this plug-in is for the JSON layout.

## The tab

- **Summary** (left card): the general description (it becomes the `caption`), Photo / Art, Shuffle and the terms database. Terms for medium and genre go to `meta`, the other ones into the `caption`. You can add free `meta` tags, choose the `canvas` (`single`, `multi_panel`, `collage`) and a colour palette (up to 5). The **Negative** section holds the negative terms (several can be picked, `worst quality, bad anatomy` by default) and a free text field.
- **Canvas** (right, top): drag on the empty part to draw a box, drag a box to move it, the corners of the selected one to resize it. The orange dot is the centre, the origin of the coordinates. **Click the tag of a box** to change its type from a small menu.
- **Elements** (right, bottom): one card per box, with the type (`object`, `character`, `text`, `panel`, `subject`), the caption, the exact text (for a Text element, never rewritten), tags, the position and up to 5 colours.

## Coordinates

MOSS reads each box as `[y0, x0, y1, x1]` in **pixels from the centre** of the picture, so the boxes only make sense for the size they were calculated for: with a bigger canvas the picture is drawn at the original size with blank space around it, with a smaller one the excess is cut off, and there is no error either way. The plug-in keeps the boxes as fractions of the canvas and converts them with the **current** Generation size when you press **Send** (the size must be a multiple of 16). If the *shape* of the Generation changes after you drew, a notice appears above the canvas and the boxes keep their fractions (they are stretched).

## Write with LLM, Undo, Send

- **Write with LLM** sends the description (with the picked terms), the free `meta` tags, and the caption and tags of each element as Markdown blocks in one request, and replaces the texts in the fields. The reply is checked in code: quoted words unchanged, English not Italian; a part that fails keeps your original. The literal text of Text elements, the positions and the colours are never sent. **Undo** puts the previous texts back (the last writing only). The request, the raw answer and the previous texts are saved in `llm/` next to `state.json` in the project.
- **Send** is disabled, with the reason shown, when the description is empty, there are no elements, an element has no caption (or a Text element no text), or the Generation size is unknown.

## Data

| File | Where |
|---|---|
| `prompt-database.json` | `~/Library/Application Support/DT Hub/Data/` (the same as Prompt Master's) |
| `moss.json` | `…/Data/prompt-master/`: hidden categories, Photo-only and Art-only categories, which categories go to `meta`, extra negative terms, LLM settings |
| `master-prompt.md` | `…/Data/prompt-master-moss/` (`custom/master-prompt.md` for your own notes) |

Recommended settings for MOSS Image in Draw Things: 50 steps, text guidance 3, shift 5.

## Build

```
Plugins/PromptMasterMOSS/Scripts/build.sh "$TMPDIR/pm-moss"
```

Then add `PromptMasterMOSS.dthubplugin` in **Preferences › Plug-ins**. No LoRA is needed.
