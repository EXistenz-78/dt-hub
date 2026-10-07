# DT Hub plug-ins

Three plug-ins ship in this repository. Each is a Swift package of its own (with tests), and each has a README with all the details; those READMEs are written in Italian.

| Plug-in | What it does | Details |
| --- | --- | --- |
| **Prompt Master** | A database of 875 curated terms (8 groups, 40 categories: photography, light, colour, style, matter) that you pick with checkboxes, plus a free description in any language. *Write prompt* sends everything to the app's local LLM together with the master prompt of the selected model family, and the English prompt that comes back is written into the Generation tab (and into the negative prompt, for families that read one). Includes Shuffle and Shuffle scene. | [`PromptMaster/`](PromptMaster/README.md) |
| **Prompt Master I4** | For **Ideogram 4**: composes the fixed-order JSON caption the model was trained on. Pick terms from the database, write the texts, and place objects and text on a canvas with their boxes and colours; the JSON is previewed live, and an LLM can write the descriptions for you. | [`PromptMasterI4/`](PromptMasterI4/README.md) |
| **Sphere Light Reference** | Place up to three lights on a sphere, render it (CPU ray tracing) and send it to Draw Things to make the light, the colours and the sun direction of an image match the sphere. Works with FLUX.2 Klein 9B and the `flux_2_sun_direction_lora_v1_lora_f16.ckpt` LoRA. | [`SphereLight/`](SphereLight/README.md) |

## Build and install

Each plug-in has a `Scripts/build.sh`. For example, for Prompt Master I4:

    Plugins/PromptMasterI4/Scripts/build.sh "$TMPDIR/pm-i4"
    cp -R "$TMPDIR/pm-i4/PromptMasterI4.dthubplugin" "$HOME/Library/Application Support/DT Hub/Plug-ins/com.exiztenz.dthub.promptmasteri4.dthubplugin"

then restart DT Hub. A plug-in can also be added from **Preferences › Plug-ins**, and switched on or off from the plug-in menu in the header; a plug-in that does not support the family of the selected model is greyed out.

Run a plug-in's tests from its folder: `cd Plugins/PromptMasterI4 && swift test`.

## Writing your own

See [`../PluginKit/README.md`](../PluginKit/README.md): the contract between the app and a plug-in, the messages (`context`, `contribute`, `llm`, `presets`…), a sample plug-in and the design system.
