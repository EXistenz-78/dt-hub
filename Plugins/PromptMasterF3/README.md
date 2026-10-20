# Prompt Master F3

> **Works with:** FLUX.3 Klein (structured prompts with boxes). **For now it is switched on for the FLUX.2 [klein] families** (`flux2_9b`, `flux2_4b`) so it can be tried in the app up to the generated prompt; the Run only makes sense on FLUX.3 Klein, which Draw Things does not offer yet.
> On any other family the plug-in is switched off and its tab is hidden.

A DT Hub plug-in that builds the **structured prompt of FLUX.3**: a description of the scene, a composition sentence that names the elements with `<id>` placeholders, and a JSON array that says where each element goes (`bbox`, `[top, left, bottom, right]` on a 0–1000 grid) and what it is (`desc`). The result goes to the Prompt field of the Generation tab.

```
A cinematic editorial photograph of a woman in a rainy Tokyo street at night.

The composition contains a woman <woman_1> and a red umbrella <umbrella_1>.

[
  {
    "id": "woman_1",
    "bbox": [250, 350, 850, 650],
    "desc": "A young woman in a black trench coat, standing upright."
  },
  {
    "id": "umbrella_1",
    "bbox": [120, 280, 420, 720],
    "desc": "A vivid transparent red umbrella held above her head."
  }
]
```

## The four cards

1. **General description** — a text field, Photo / Art, Shuffle, and the terms database (every group except "Technical"). Terms you pick are added to the description as a sentence (or merged into it by the LLM).
2. **Composition** — a text field. Write `<id>` to create an element: a box appears on the canvas (new boxes line up from the top left so they do not pile up) and a card with the id already filled in. The `<id>` are highlighted with the element's colour. A repeated id shows a warning that suggests numbering them (`lamp_1`, `lamp_2`…).
3. **Canvas** — drag a box to move it, the corners of the selected one to resize it. It has the proportions of the Generation tab.
4. **Elements** — one card per id: the description of what must appear inside that region, and the position `y0, x0, y1, x1`. Up/down changes the order of the array; the cross removes the element and its `<id>` from the text.

The ids are the only link between the text and the boxes, so an element exists only while its `<id>` is in the composition (a removed one comes back, with its description and box, if you type the same id again; renaming an id in the text keeps the card).

## Write with LLM

One button, at the bottom, with the language model chosen in the app. It sends the parts (description with the picked terms, composition, the description of each element) as Markdown blocks in **one request** and **replaces the texts in the fields**, so you see the final prompt right there. The LLM translates into English and enriches the words around the placeholders, and is told **never to touch what is between `<` and `>`**: the plug-in checks that too (same ids, same number of times, quoted words unchanged) and keeps your original text for a part that fails the check. **Undo** puts the previous texts back (the last writing only).

The request, the raw answer and the previous texts are saved in the `llm` folder next to `state.json` in the project; the master prompt is `Data/prompt-master-f3/master-prompt.md` (and `custom/master-prompt.md` for your own notes).

**Send** is disabled while an element has no description, an id is repeated, or there is nothing to send.

## Data

| File | Where |
|---|---|
| `prompt-database.json` | `~/Library/Application Support/DT Hub/Data/` (the same as Prompt Master's) |
| `flux3.json` | `…/Data/prompt-master/`: groups left out, categories only for Photo or Art, LLM settings |
| `master-prompt.md` | `…/Data/prompt-master-f3/` |

## Build

```
Plugins/PromptMasterF3/Scripts/build.sh "$TMPDIR/pm-f3"
```

Then add `PromptMasterF3.dthubplugin` in **Preferences › Plug-ins**. No LoRA is needed.
