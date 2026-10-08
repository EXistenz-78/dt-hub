# Character Sheet

> **Works with:** **Qwen Image 2.1** only. On any other family the plug-in is switched off and its tab is hidden.
> **Based on [NeuroContent's workflow](https://civitai.com/models/2960750/qwen-image-21-character-design-sheet-maker-workflow?modelVersionId=3377047)** for ComfyUI.

A DT Hub plug-in that prepares a **character design sheet** from a single picture of a character, drawn by Qwen Image 2.1 from
the picture you give it. Three kinds of sheet, picked with the radio buttons at the top of the tab:

- **Base sheet:** hero view, front/side/back turnaround, action poses, silhouettes, expressions and detail close-ups on one sheet;
- **Expressions sheet:** twelve expressions of the character's head on a 4×3 grid;
- **Poses sheet:** ten dynamic full-body poses on a 5×2 grid.

## Credits

This plug-in is **based on the work of [NeuroContent](https://civitai.com/models/2960750/qwen-image-21-character-design-sheet-maker-workflow?modelVersionId=3377047)**,
author of the ComfyUI workflow *Qwen Image 2.1 Character Design Sheet Maker*. The idea (a master prompt that makes a
language model write the brief of the sheet from one picture, or a static prompt for the same layout) and the **base sheet's master prompt
and static prompt** are theirs; DT Hub carries a copy of both inside the plug-in so it works out of the box, and the expressions and
poses prompts are derived from them. Thank you! If you are the author and would like something changed, please open an
[Issue](https://github.com/EXistenz-78/dt-hub/issues).

## What it does

Pick the kind of sheet, a picture and the character's name, then press **Prepare**. The plug-in then:

1. sends the picture to the **Moodboard** (Qwen Image 2.1 reads it as the reference),
2. sets the canvas to **2048×1536** (4:3, the same for every kind of sheet: the widest canvas the app takes without tiled diffusion),
3. writes the **prompt** in the Generation tab, and leaves the Run button to you. The fields it filled turn teal and stay editable.

Two ways to write the prompt:

- **Static prompt** (switch on): a fixed prompt with the name filled in. No language model, instant. It draws the structure well; the small
  texts of the base sheet can come out garbled.
- **Language model** (switch off): the picture and the *master prompt* go to the language model you choose in the menu, which
  writes a prompt that follows the picture. Only models that read pictures are listed.
  - Any vision model (for example **Qwen3-VL 8B**, which gave faithful sheets in our tests): the master prompt is its system prompt and
    the request is `Entity name: <name>`.
  - **Qwen-Image-2.1-PE-I2I** (Qwen's prompt enhancer for image editing): it keeps its own `system_prompt.txt`, which must be in the
    model's folder next to the weights, and receives the master prompt as the instruction to rewrite. It writes cleaner sheets but tends to
    reinvent the character. Some conversions of it keep the image settings nested under `image_processor` in `processor_config.json`:
    DT Hub then adds the flat `preprocessor_config.json` the library needs next to the weights the first time it loads the model (only
    an addition; on a read-only folder the app says the model cannot read pictures instead of ignoring them).

The sheet follows the reference's style, whatever the prompt says about the medium. The status line under the buttons shows how many words
the prompt has and how long the model took, to compare models. The language model cannot be stopped once asked (as everywhere in DT
Hub), so **Prepare** stays disabled while it works.

## The texts

The six prompt texts (a master prompt and a static prompt for each kind of sheet) are built into the plug-in. To change them press **Open
folder**: it writes the texts that are not there yet into `~/Library/Application Support/DT Hub/Data/CharacterSheet/` and opens it.

| Kind | Language model | Static prompt |
| --- | --- | --- |
| Base sheet | `master-prompt.txt` | `static-prompt.txt` |
| Expressions sheet | `master-prompt-expressions.txt` | `static-prompt-expressions.txt` |
| Poses sheet | `master-prompt-poses.txt` | `static-prompt-poses.txt` |

A file in that folder wins over the built-in text, with no rebuild: edit it freely, and **delete it to go back to the built-in one**. In a
static prompt `{{name}}` is replaced by the character's name (`CHARACTER` if the field is empty).

`Scripts/extract-from-workflow.py` reads the base pair out of a copy of the ComfyUI workflow, and `Scripts/make-builtin-texts.py` regenerates
`CSBuiltIn.swift` from the six files when the built-in texts change.

## Projects

The settings of the tab (the kind of sheet, the static-prompt switch and the model) are preferences: they are the same in every project.

## Install and build

Add the `.dthubplugin` bundle in DT Hub › Preferences › Plug-ins (**Add…**, or drag the file in), then restart the app. To build
the bundle yourself:

    Plugins/CharacterSheet/Scripts/build.sh OUT_FOLDER     # makes OUT_FOLDER/CharacterSheet.dthubplugin
    cd Plugins/CharacterSheet && swift test                # the plug-in's tests

The tab uses the app's own components (`DTHubDesign`, from the `PluginKit` package).
