# DT Hub plug-ins

Three plug-ins ship in this repository. Each is a Swift package of its own, with its own tests and its own README.
A plug-in only works with the model families it was made for: on any other family it is **switched off and its tab is hidden**,
so the tab bar only ever shows what can be used with the model you picked.

| Plug-in | Works with | What it does |
| --- | --- | --- |
| **[Prompt Master](PromptMaster/README.md)** | FLUX.1, FLUX.2 (dev, klein 9B, klein 4B), Krea 2, Qwen Image, Qwen Image 2.1, Z Image, Stable Diffusion XL (and Pony / Illustrious), Stable Diffusion 1.5, ERNIE-Image, HiDream-I1, Anima (Cosmos 2.5): **13 families** | A database of 875 curated terms (8 groups, 40 categories: photography, light, colour, style, matter) that you pick with checkboxes, plus a free description in any language. *Write prompt* sends everything to the app's local LLM together with the master prompt of the selected model family, and the English prompt that comes back is written into the Generation tab (and into the negative prompt, for families that read one). Includes Shuffle and Shuffle scene. |
| **[Prompt Master I4](PromptMasterI4/README.md)** | **Ideogram 4** only | Composes the fixed-order JSON caption the model was trained on. Pick terms from the database, write the texts, and place objects and lettering on a canvas with their boxes and colours; the JSON is previewed live, and the LLM can write the descriptions for you. |
| **[Sphere Light Reference](SphereLight/README.md)** | **FLUX.2 [klein] 9B** only, with the [Sun Direction LoRA](https://huggingface.co/eric-venti-seeds/Sun-Direction-Lora-Flux2Klein9B) | Place lights on a sphere, render it (CPU ray tracing) and send it to Draw Things so the light, the colours and the sun direction of an image match the sphere. **Multiple and coloured lights are exclusive to this plug-in**: it pushes the LoRA beyond its original limits. |

<p>
  <img src="../docs/images/prompt-master.png" alt="Prompt Master" width="32%">
  <img src="../docs/images/prompt-master-i4.png" alt="Prompt Master I4" width="32%">
  <img src="../docs/images/sphere-light.png" alt="Sphere Light Reference" width="32%">
</p>

## Install

In DT Hub open **Preferences › Plug-ins**, press **Add…** and pick the plug-in's `.dthubplugin` bundle, then restart the app (turning a
plug-in on or off, or removing it, takes effect at the next launch). Each plug-in then appears as a tab, and can be switched on and off
there or from the plug-in menu in the header.

![Preferences › Plug-ins](../docs/images/preferences-plugins.png)

A plug-in runs code on your Mac with the same permissions as DT Hub: add only plug-ins you trust.

## Build a plug-in bundle (from a terminal)

Pre-built bundles will be attached to the [Releases](../../../releases) when they are available. Until then, each plug-in has a
`Scripts/build.sh` that makes the bundle. For example, for Prompt Master I4:

    Plugins/PromptMasterI4/Scripts/build.sh "$TMPDIR/pm-i4"

The bundle is `$TMPDIR/pm-i4/PromptMasterI4.dthubplugin`: add it from Preferences as above. As an alternative to the Add… button, copy it
into `~/Library/Application Support/DT Hub/Plug-ins/` with the bundle identifier as its name
(`com.exiztenz.dthub.promptmasteri4.dthubplugin`) and restart DT Hub.

Run a plug-in's tests from its folder: `cd Plugins/PromptMasterI4 && swift test`.

## Writing your own

See [`../PluginKit/README.md`](../PluginKit/README.md): the contract between the app and a plug-in, the messages (`context`, `contribute`,
`llm`, `presets`…), a sample plug-in and the design system.
