# Prompt Master I4

> **Works with:** **Ideogram 4** only (`ideogram_4`).
> On any other family the plug-in is switched off and its tab is hidden (and [Prompt Master](../PromptMaster/README.md) is switched off on Ideogram 4).

A DT Hub plug-in for **Ideogram 4**: it composes the fixed-order JSON caption the model saw during training and sends it to the
Prompt field of the Generation tab. You pick entries from the terms database (one per category), write the texts, and define the
elements (objects and lettering, with their boxes and colours).

![Prompt Master I4](../../docs/images/prompt-master-i4.png)

- **Left card:** the general description (`high_level_description`); **Photo / Art** (when you switch, the entries of the
  categories that disappear are cleared); **Shuffle** (at most 3 categories per section, one entry each; Medium and Background
  just one); the **Aesthetics**, **Lighting**, **Photo** or **Art style**, and **Medium** sections (categories and entries, one entry
  per category, a single Medium); the palette (up to 16 colours); the background (a text and one entry of "Background Setup").
- **Canvas:** a rectangle with the proportions of the Generation tab (square until the app tells them). Drag on the empty canvas to
  make an object (minimum side 20 out of 1000); drag a box to move it, the corners of the selected one to resize it; click the
  `E1 · obj` tag to select a box and, if it is already selected, to turn it into text (and back). A box you draw is always a new
  element; an element without a position (added with the buttons) gets a box when you type the numbers on its card.
- **Write with LLM:** sends the language model chosen in the app **a single request** with a tagged block for every field to
  rewrite (description, Aesthetics, Lighting, Photo/Art style, Medium, Background, every element) and puts each English sentence
  back in its place in the JSON. A field *needs rewriting* if it has something in it and no sentence yet, or it changed since the
  last one: the others are not regenerated. If the answer lacks the sentence of a field, that field gets a request of its own. The
  words a lettering prints, the positions and the colours never go to the model. "What the LLM gets" (in the Elements card) shows
  every field with its state (raw, rewritten, needs rewriting, empty). A successful write replaces a JSON you edited by hand.
- **Right card:** the elements, one card each, closed at first (a new element opens by itself): description (the type is chosen by
  adding the element: **Add an object** or **Add a text**), the **Text & Lettering** menu and the verbatim text (for lettering), the
  position `y0, x0, y1, x1` on 0–1000 (sides of at least 20), a palette of up to 5 colours, up/down (the order is the z-order),
  remove. At the bottom: **Add an object**, **Add a text**, **Review JSON** and **Send**.
- **Review JSON:** the text of the JSON, copyable and editable by hand; it is what **Send** sends until you press "Restore from the
  fields". **Send** puts the JSON in the Prompt and empties the negative prompt.
- The JSON keys follow the order of the schema: `photo` BEFORE `medium`, `art_style` AFTER; no `aspect_ratio`. Until the LLM is
  used, entries go in with their English name (`en`) and the texts as they were written.

## Data

| File | Where | Written by |
|---|---|---|
| `prompt-database.json` | `~/Library/Application Support/DT Hub/Data/` (the same as Prompt Master's) | you, to update it |
| `ideogram4.json` | `…/Data/prompt-master/` | you: which categories feed each field, the LLM settings, the master prompt (version 1.1.0, tried with the 8B model) |

A file is used if it exists, can be read, has `schema` 1, no repeated id and a `version` not older than the embedded one;
otherwise the embedded copy is used (and if the file cannot be read, has an unknown layout or uses the same id twice, the status
line says so; an older file is ignored without a word). The plug-in never writes either of them. The embedded copies and the files
in `Data/` are regenerated with `Scripts/make-i4-data.py` (the database is copied from `Plugins/PromptMaster/Data/`, which is not
modified; a test checks that they are equal).

## Install and build

Add the `.dthubplugin` bundle in DT Hub › Preferences › Plug-ins (**Add…**), then restart the app. To build the bundle yourself:

    Plugins/PromptMasterI4/Scripts/build.sh OUT_FOLDER   # makes OUT_FOLDER/PromptMasterI4.dthubplugin
    cd Plugins/PromptMasterI4 && swift test              # the plug-in's tests (I4_RENDER_DIR=folder saves PNGs of the tab)
