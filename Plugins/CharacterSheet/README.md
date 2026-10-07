# Character Sheet

> **Works with:** **Qwen Image 2.1** only. On any other family the plug-in is switched off and its tab is hidden.

A DT Hub plug-in that prepares a **character design sheet** from a single picture of a character: front, side and back
views, action poses, silhouettes, expressions and detail close-ups on one 3:2 sheet, all drawn by Qwen Image 2.1 from the
picture you give it.

It is inspired by a community ComfyUI workflow for Qwen Image 2.1 character sheets. **The workflow's prompt texts are not part
of this repository**: you extract them from your own copy of the workflow (see below).

## What it does

Pick a picture, type the character's name, press **Prepare**. The plug-in then:

1. sends the picture to the **Moodboard** (Qwen Image 2.1 reads it as the reference),
2. sets the canvas to **2304×1536** (3:2),
3. writes the **prompt** in the Generation tab, and leaves the Run button to you. The fields it filled turn teal and stay editable.

Two ways to write the prompt:

- **Static prompt** (switch on): a fixed prompt with the name filled in. No language model, instant.
- **Language model** (switch off): the picture and the *master prompt* go to the language model you choose in the menu, which
  writes a prompt that follows the picture. Only models that read pictures are listed.
  - Any vision model (for example Qwen3-VL): the master prompt is its system prompt and the request is `Entity name: <name>`.
  - **Qwen-Image-2.1-PE-I2I** (Qwen's prompt enhancer for image editing): it keeps its own `system_prompt.txt`, which must be
    in the model's folder next to the weights, and receives the master prompt as the instruction to rewrite.

The status line under the buttons shows how many words the prompt has and how long the model took, to compare models.
The language model cannot be stopped once asked (as everywhere in DT Hub), so **Prepare** stays disabled while it works.

## The two text files

They live in `~/Library/Application Support/DT Hub/Data/CharacterSheet/` (the **Open folder** button opens it):

- `master-prompt.txt`: the instructions for the language model;
- `static-prompt.txt`: the prompt used without a model. `{{name}}` is replaced by the character's name (`CHARACTER` if the
  field is empty).

Get them from a copy of the ComfyUI workflow (`Character_Sheet_Production.json`):

    python3 Plugins/CharacterSheet/Scripts/extract-from-workflow.py --source /path/to/Character_Sheet_Production.json

The script writes both files (it refuses to overwrite existing ones without `--force`). You can edit them at any time, no
rebuild needed.

## Install and build

Add the `.dthubplugin` bundle in DT Hub › Preferences › Plug-ins (**Add…**, or drag the file in), then restart the app. To build
the bundle yourself:

    Plugins/CharacterSheet/Scripts/build.sh OUT_FOLDER     # makes OUT_FOLDER/CharacterSheet.dthubplugin
    cd Plugins/CharacterSheet && swift test                # the plug-in's tests

The tab uses the app's own components (`DTHubDesign`, from the `PluginKit` package).
