# Prompt Master F3

> **Works with:** FLUX.3 [klein] 5.6B (structured prompts with boxes), in all its variants (`flux3_5b`: Base, 8-bit, 4-bit, Exact).
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

**Two ways to write.** The plug-in picks the language model the app uses for this model family (Settings › LLM) and says which way it used in the status line.

- **PUP mode.** If that model is BFL's own prompt upsampler `flux-3-image-klein-pup` (recognised by a `system_prompts.json` with a `t2i_bbox` entry in the model's folder, which is also where the official system prompt is read from), one request in its native format goes out: your description, the picked terms and the composition as the original prompt, and your elements as locked `{id, bbox, desc}` rows. The answer is reconciled with your boxes (ids and coordinates stay as you drew them, the model's descriptions replace yours). Its paragraph becomes the **composition** (the description and the picked terms are already inside it, so those fields are emptied: **Undo** brings them back), and the rows it adds become new elements with its box and description. If it cannot write (the app could not load its vision part, an id is not cited, a quoted word changed…), the status line says why and your texts stay: the PUP answers in its own format whatever system prompt it gets, so there is no fallback with it. The PUP needs `"processor_class"` in its `preprocessor_config.json`; DT Hub adds it when it loads the model.
- **Standard mode.** With any other model: the master prompt below, as before.

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
