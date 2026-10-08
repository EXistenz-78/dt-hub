# Prompt Master

> **Works with:** FLUX.1 · FLUX.2 [dev] · FLUX.2 [klein] 9B · FLUX.2 [klein] 4B · Krea 2 · Qwen Image · Qwen Image 2.1 · Z Image · Stable Diffusion XL (and Pony / Illustrious) · Stable Diffusion 1.5 · ERNIE-Image · HiDream-I1 · Anima (Cosmos 2.5) — 13 model families in all.
> On any other family (Ideogram 4 has its own plug-in, [Prompt Master I4](../PromptMasterI4/README.md)) the plug-in is switched off and its tab is hidden.

A DT Hub plug-in: a list of terms (8 groups → 40 categories → 875 terms of photography, light, colour, style and matter) that you
pick with a checkbox, plus a free description in any language. *Write prompt* sends everything to the app's local LLM, together
with the master prompt of the selected model family, and the English prompt that comes back lands in the Prompt field of the
Generation tab (and in the negative prompt, for the families that read one).

![Prompt Master](../../docs/images/prompt-master.png)

- **Photo / Art** only steer Shuffle (which categories it draws from); **Shuffle** replaces the selection with a random term per
  category; **Shuffle scene** asks the LLM for a subject and a setting and writes them into the description.
- **Your own terms:** "Add a term" at the bottom of every category (one string, in any language).
- **What the LLM receives:** the description, then the terms in English **with their category**, one line per category
  (`Light Source: Starlight`, `Color Palette: Jewel tones`). The category tells the model how to use the term (a light, a palette,
  a genre) and keeps "butterfly lighting" from turning into butterflies.
- **Qwen Image 2.1:** if the models folder holds the official T2I prompt enhancer (`…PE-T2I…`, with its `system_prompt.txt` next
  to the weights) the plug-in uses it instead of the general LLM, with a prose request (the description and a `Look: …` line).
  Under the prompt appears the format it suggests, with an **Apply** button that sets the width and height of the Generation tab
  to that ratio, keeping the same area in pixels. Without the enhancer, the chosen model is used with the fallback master prompt
  (same structure, 500 words at most). The I2I enhancer is not supported: it belongs to a plug-in dedicated to Qwen Image 2.1.

## Data

Three JSON files, each with a copy embedded in the plug-in (a plug-in bundle holds only the library):

| File | Where | Written by |
|---|---|---|
| `prompt-database.json` | `~/Library/Application Support/DT Hub/Data/` (shared with other plug-ins) | you, to update it |
| `master-prompts.json` | `…/Data/prompt-master/` | you (this is how master prompts are revised) |
| `custom-terms.json` | `…/Data/prompt-master/` | the plug-in |

A file is used if it exists, can be read, has `schema` 1 and a `version` not older than the embedded one; otherwise the embedded
copy is used (and if the file cannot be read or has an unknown layout, the status line says so). The plug-in never writes the
first two. The embedded copies and the files in `Data/` are regenerated with `Scripts/make-prompt-data.py` from Prompt Master 2.0
(which is never modified): pass its folder with `--source` or the `PM2_SOURCE` variable.

## Projects

The tab keeps its state **per project**: when you open another project in DT Hub (the **Project** menu) the tab shows what that project had, and a new project starts from scratch. The state is `state.json` in the plug-in's own folder inside the project (`<output>/<project>/.dthub/plugins/`). The first project you make adopts the state the tab had before projects existed.

## Install and build

Add the `.dthubplugin` bundle in DT Hub › Preferences › Plug-ins (**Add…**), then restart the app. To build the bundle yourself:

    Plugins/PromptMaster/Scripts/build.sh OUT_FOLDER     # makes OUT_FOLDER/PromptMaster.dthubplugin
    cd Plugins/PromptMaster && swift test                # the plug-in's tests

It needs the `llm` contract with `system`, `model` and `options`, and the `context` with `languageModels` and `parameters`
(see [`PluginKit/README.md`](../../PluginKit/README.md)).
