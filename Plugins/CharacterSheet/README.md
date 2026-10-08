# Character Sheet

> **Works with:** **Qwen Image 2.1** only. On any other family the plug-in is switched off and its tab is hidden.

A DT Hub plug-in that prepares a **character design sheet** from a single picture of a character: front, side and back
views, action poses, silhouettes, expressions and detail close-ups on one 3:2 sheet, all drawn by Qwen Image 2.1 from the
picture you give it.

It is inspired by a community ComfyUI workflow for Qwen Image 2.1 character sheets. **The workflow's prompt texts are not part
of this repository**: you extract them from your own copy of the workflow (see below).

## What it does

Pick the kind of sheet, a picture and the character's name, then press **Prepare**. The plug-in then:

1. sends the picture to the **Moodboard** (Qwen Image 2.1 reads it as the reference),
2. sets the canvas to **2048×1536** (4:3, the same for every kind of sheet),
3. writes the **prompt** in the Generation tab, and leaves the Run button to you. The fields it filled turn teal and stay editable.

Three kinds of sheet (radio buttons at the top), all on the same canvas:

- **Base sheet:** the full design sheet: hero view, turnarounds, action poses, silhouettes, expressions and detail close-ups;
- **Expressions sheet:** twelve expressions of the character's head on a 4×3 grid;
- **Poses sheet:** ten dynamic full-body poses on a 5×2 grid.

Two ways to write the prompt:

- **Static prompt** (switch on): a fixed prompt with the name filled in. No language model, instant.
- **Language model** (switch off): the picture and the *master prompt* go to the language model you choose in the menu, which
  writes a prompt that follows the picture. Only models that read pictures are listed.
  - Any vision model (for example Qwen3-VL): the master prompt is its system prompt and the request is `Entity name: <name>`.
  - **Qwen-Image-2.1-PE-I2I** (Qwen's prompt enhancer for image editing): it keeps its own `system_prompt.txt`, which must be
    in the model's folder next to the weights, and receives the master prompt as the instruction to rewrite.

The status line under the buttons shows how many words the prompt has and how long the model took, to compare models.
The language model cannot be stopped once asked (as everywhere in DT Hub), so **Prepare** stays disabled while it works.

## The text files

They live in `~/Library/Application Support/DT Hub/Data/CharacterSheet/` (the **Open folder** button opens it). Each kind of
sheet has two files, one for the language model and one for the static prompt:

| Kind | Language model | Static prompt |
| --- | --- | --- |
| Base sheet | `master-prompt.txt` | `static-prompt.txt` |
| Expressions sheet | `master-prompt-expressions.txt` | `static-prompt-expressions.txt` |
| Poses sheet | `master-prompt-poses.txt` | `static-prompt-poses.txt` |

In a static prompt `{{name}}` is replaced by the character's name (`CHARACTER` if the field is empty). A missing file is
named in the status line.

The base pair comes from a copy of the ComfyUI workflow (`Character_Sheet_Production.json`):

    python3 Plugins/CharacterSheet/Scripts/extract-from-workflow.py --source /path/to/Character_Sheet_Production.json

The script writes both files (it refuses to overwrite existing ones without `--force`). The other four are your own to
write, in the same spirit. You can edit all of them at any time, no rebuild needed.

## Install and build

Add the `.dthubplugin` bundle in DT Hub › Preferences › Plug-ins (**Add…**, or drag the file in), then restart the app. To build
the bundle yourself:

    Plugins/CharacterSheet/Scripts/build.sh OUT_FOLDER     # makes OUT_FOLDER/CharacterSheet.dthubplugin
    cd Plugins/CharacterSheet && swift test                # the plug-in's tests

The tab links to the workflow the plug-in is based on ("Based on NeuroContent work").
The tab uses the app's own components (`DTHubDesign`, from the `PluginKit` package).
