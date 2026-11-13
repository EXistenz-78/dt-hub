# Sphere Light Reference (SLR)

> **Works with:** the **FLUX.2 [klein]** family, with the [Sun Direction LoRA](https://huggingface.co/eric-venti-seeds/Sun-Direction-Lora-Flux2Klein9B) (`flux_2_sun_direction_lora_v1_lora_f16.ckpt`). The **9B** is recommended: it gives better results; the **4B** works too.
> On any other family the plug-in is switched off and its tab is hidden.

A DT Hub plug-in: it places up to three lights on a sphere, renders it (CPU ray tracing) and sends it to Draw Things so that the
light, the colours and the sun direction of an image match those of the sphere.

**Multiple and coloured lights are exclusive to this plug-in.** SLR pushes the LoRA beyond its original limits: the reference
sphere can be lit by several lights at once, each with its own colour, rotation, elevation, intensity and shadow hardness.

![Sphere Light Reference](../../docs/images/sphere-light.png)

A reference picture with the sphere in its corner (left), and what the model made of it (right): the cyan and pink lights of the
sphere now fall on the face and the scene.

![Before and after](../../docs/images/sphere-light-example.png)

- **Send to Generation:** the sphere goes to the Moodboard and the Run button becomes a preset pipeline: `SLR · Match the sun`,
  preceded by `SLR · Overcast` (it flattens the shadows of the canvas) if the "Overcast" box is on.
- **Sphere only, to the Moodboard:** sends just the image, so you can use your own prompt and parameters.
- **The presets** register themselves when the plug-in is activated and live in the Presets menu: you can change them (the LoRA
  weight, the steps…) and save them under the same name; the plug-in never overwrites them. If you delete one, "Send to
  Generation" recreates it.
- **Also save to Desktop:** a copy of the sphere as `Sphere Light NNN.png`.

The tab uses the app's own components (`DTHubDesign`, from the `PluginKit` package): cards, pill buttons, teal checkboxes.

## For AI agents (MCP)

Since **1.2**. With DT Hub's remote control on (Settings › Remote control), the plug-in **on for the job** and a FLUX.2 [klein] model in the header, an agent sees these tools, named `plugin__spherelight__<tool>`. Needs a DT Hub that can run a plug-in's pipeline from an agent (after 1.3.2).

- `get_status` (read): the lights (rotation, elevation, intensity, hardness, colour as `#RRGGBB`), the Overcast box, the ranges and how many passes the pipeline would have.
- `set_light` (edit, «Modify the tab» or more): changes one light (arguments left out stay as they are), or adds the next one (`light` = number of lights + 1, at most three). `remove_light` takes one off (never the last).
- `send_sphere` (edit): renders the sphere and sends it **without generating**: `target: "moodboard"` puts only the picture in the Moodboard; `target: "pipeline"` also puts the `SLR · Match the sun` pipeline (with `overcast: true`, preceded by `SLR · Overcast`) on RUN and offers the presets in the Presets menu (a name the menu has is never touched).
- `match_light` (generate, «Full control» only): does what `send_sphere` with `target: "pipeline"` does and then presses RUN. It returns a `job_id`; the agent follows it with `wait_for_job` and reads the pictures with `get_results` / `get_image`.

**Budget and consent.** `match_light` goes through the same path as the app's `run_pipeline`: one job at a time, **every pass counts as an image** (1, or 2 with Overcast; the tab's batch count and size multiply it), and a job over the user's confirmation threshold waits for the user's yes in DT Hub. Nothing an agent does writes a copy to the Desktop, whatever the box says. The lights' numbers and the pipeline's names are shown to the agent as data, not instructions.

## Projects

The tab keeps its state **per project**: when you open another project in DT Hub (the **Project** menu) the tab shows what that project had, and a new project starts from scratch. The state is `state.json` in the plug-in's own folder inside the project (`<output>/<project>/.dthub/plugins/`). The first project you make adopts the state the tab had before projects existed.

## Install and build

Add the `.dthubplugin` bundle in DT Hub › Preferences › Plug-ins (**Add…**, or drag the file in), then restart the app. To build
the bundle yourself:

    Plugins/SphereLight/Scripts/build.sh OUT_FOLDER     # makes OUT_FOLDER/SphereLight.dthubplugin
    cd Plugins/SphereLight && swift test                # the plug-in's tests

The renderer's code comes from the standalone `LightDirectionApp` (a copy: the standalone app is no longer developed).
