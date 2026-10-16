# DT Hub

A native macOS companion for [Draw Things](https://drawthings.ai/): a dedicated workspace for **preparing and launching image generations**. DT Hub connects to the Draw Things gRPC server, which does all the rendering, and adds what sits around it: inputs you can always see, a canvas you can draw on from an iPad, a local LLM that writes and improves prompts, and plug-ins that each bring their own tab.

This is an independent community project, not affiliated with or endorsed by Draw Things Technologies. It started as a personal tool and is published as open source under the GPL-3.0.

![The Control tab: start image, Moodboard and Canvas side by side](docs/images/control.png)

## What DT Hub adds

- **Canvas on your iPad.** The Canvas card opens in a window of its own that shows nothing but the drawing, as large as the window allows. Move it to an iPad connected with **Sidecar** and paint the inpainting mask, or draw in colour onto the image, with an **Apple Pencil** or your fingers. Undo and redo keep working in the window.
- **Image and Moodboard always in sight.** The Control tab shows the start image, the Moodboard and the Canvas side by side, never behind a menu: every Moodboard picture can be switched on or off with its eye, and you drag pictures in from the Results strip, the Finder or the clipboard.
- **A lock on the canvas proportions.** Width and height follow the ratio you choose: *Lock ratio* keeps it while you type or step either value, and the Ratios menu and the swap button change it in one click.
- **Everything you made, at hand.** The Results window keeps the images of the session (and brings back the last ones after a restart); each thumbnail shows **how many seconds it took**, can be dragged anywhere, and offers *Use as image*, *Add to Moodboard*, *Show in Finder*, *Resume parameters* and *Trash*. Every PNG is saved with its prompt, its whole configuration and the time it took inside the file, in the same layout as Draw Things' own images, so tools made for those read DT Hub's too.
- **Result details.** A collapsible sidebar in the Results window shows the prompt, settings, LoRAs and timing saved in the selected image; the text can be selected and copied.
- **Incremental mode.** A switch in the header makes each result the start image of the next RUN.
- **Projects.** Each project is a subfolder of the output folder with its own start image, mask, Moodboard, results strip and plug-in state; reopening one restores the prompt and settings of its last image. Switch from the **Project** menu in the header.
- **Your own LoRA trigger words and weights.** *Manage LoRAs…* (LoRA card) lists the LoRAs of the server by model family, compactly: change a trigger word or the default weight (−1.5 to 2.5) of any of them. The server's trigger words are inherited and only your changes are kept, in a file of DT Hub's own: Draw Things' files are never touched.
- **Presets and preset pipelines.** Save a configuration as a preset and chain several presets into one Run. Recommended settings per model family are suggested for you.
- **A local LLM (MLX)** that runs inside the app and can see images, with controls to free memory so the image model and the LLM can share a Mac. Nothing is downloaded unless you ask for it.
- **Prompt tools.** *Enhance Prompt* rewrites your prompt for the selected model's family (and sees the start image and the Moodboard pictures, so "image 1", "image 2"… keep their meaning) and *Generate Prompt* writes one from the start image, both with the local language model.
- **Plug-ins**, each with its own tab and active only on the model families it was made for: Prompt Master, Prompt Master I4 (Ideogram 4), Sphere Light Reference, Character Sheet (Qwen Image 2.1), Batch plus (a series of RUNs with growing parameters, or one per prompt; all families), AI Assistant (chat with a local LLM that can write the prompt and the settings on command), Qwen 2.1 Inpainting (colored marks and instructions on the start image, for Qwen Image 2.1) and LoRA Advisor (a visual list of your LoRAs with thumbnails and notes, and the LLM's advice on which to use; all families). See [`Plugins/`](Plugins/README.md).
- **Keyboard.** ⌘↩ Run, ⌘. Stop, ⌘R Results, ⌃Page Up / ⌃Page Down to step through the tabs.
- **Managed server.** DT Hub can start Draw Things' `gRPCServerCLI` by itself, or connect to the server of the Draw Things app.
- **DT+ (Draw Things+ cloud).** When DT Hub is connected to the Draw Things app with Bridge Mode on, the **DT+** switch next to the model menu lists the models the cloud can run (asked to Draw Things' cloud server, no account involved) and adds the cloud's LoRAs to yours, always for the current model. Account and subscription stay in the Draw Things app.
- **CU meter.** With DT+ on, a meter next to the switch shows the compute units (CU) the next RUN needs against the DT+ limit per RUN (40 000 CU, or the policy Draw Things announces), green, amber and red, with the boosts a RUN above the limit needs. For a pipeline it shows the heaviest pass. It estimates with Draw Things' own calculation (ported from its open source code) for the image families (FLUX, Qwen, Z Image, SD 1.5, SDXL, Cosmos and more); video models and a few old families show a dash. It only advises: the cloud decides.
- **A model picker for DT+.** The cloud has hundreds of models, so with DT+ on the model button opens a panel with a search field and the models grouped as Draw Things groups them: **Official**, **Community** and **Uncurated**, and inside each by family; every group opens and closes (only Official is open at first). It lists the Official models too, downloaded or not, and hides the models of your server that Draw Things does not list. With DT+ off the menu is the one of the models installed on your server.
- **New models without waiting for an update.** When it connects, DT Hub downloads the lists of official models and of their recommended settings that Draw Things publishes (`models.drawthings.ai`, the same lists the Draw Things app reads) and keeps a copy, so a model released after this version of DT Hub is recognised, with its own steps, guidance, sampler and shift, as soon as its file is in your models folder. Offline, the saved copy is used. Nothing of yours is sent.

## A look around

**Generation.** The prompt (with the negative prompt, shown only for the families that use it) and collapsible cards for dimensions, sampling, seed and batch, LoRAs and an advanced section. Every value can be typed or stepped, the open or closed state of each card is remembered, and a JSON editor shows and edits the whole configuration.

<p align="center"><img src="docs/images/generation.png" alt="The Generation tab" width="55%"></p>

**Presets.** Save a configuration as a preset, import and manage them, and let a plug-in register its own: Sphere Light's two presets, for example, are chained into one Run. You can also build your own pipelines: **Create Pipeline…** in the Preset menu lines up your presets in the order you tick them; each pass can use its preset's model, scale the size of the previous pass and have its own strength, and the result of a pass can be the start image of the next.

<p align="center"><img src="docs/images/presets.png" alt="The Presets menu" width="55%"></p>

**Canvas window.** Only the drawing, for the Pencil.

![The Canvas in its own window](docs/images/canvas-window.png)

**Results.** Live preview while generating, then the image; the strip shows the seconds each picture took.

![The Results window](docs/images/results.png)

**Preferences.** The Draw Things server, the local LLM and its memory behaviour, the output folder and the plug-ins.

<p>
  <img src="docs/images/preferences-draw-things.png" alt="Preferences: Draw Things" width="32%">
  <img src="docs/images/preferences-llm.png" alt="Preferences: LLM" width="32%">
  <img src="docs/images/preferences-plugins.png" alt="Preferences: Plug-ins" width="32%">
</p>

## Requirements

- macOS 26 and an Apple Silicon Mac.
- A Draw Things gRPC server: the Draw Things app with its API server enabled, or the `gRPCServerCLI` binary, which DT Hub can start itself.
- To build: Xcode 27.

## Install

1. Download **`DT-Hub-0.2.3-macOS-arm64.zip`** from the [latest release](https://github.com/EXistenz-78/dt-hub/releases/latest).
2. Unzip it and drag **DT Hub.app** into `/Applications`.
3. Read **First launch** below before you open it.
4. Optional: add the plug-ins (they are in the same release, see [`Plugins/`](Plugins/README.md#install)).

You also need a Draw Things gRPC server (see Requirements).

## First launch (important)

The app is signed with an Apple Development certificate but it is **not notarized**, so macOS Gatekeeper refuses to open it the first time. This is expected, not a broken download.

When you see *"Apple could not verify 'DT Hub' is free of malware"*:

1. Open **System Settings › Privacy & Security**.
2. Scroll down: there is a line saying **"DT Hub" was blocked**.
3. Click **Open Anyway** and confirm in the dialog that appears.

You only need to do this once per download. If you would rather not trust a binary, build it yourself from source (below).

## Updating the server (`gRPCServerCLI`)

When DT Hub starts the server for you, it runs the `gRPCServerCLI` binary you chose in **Preferences › Draw Things**; the same pane shows which release it is and tells you when a newer one exists. DT Hub does not update it by itself:

1. Download `gRPCServerCLI-macOS` from the [Draw Things releases](https://github.com/drawthingsai/draw-things-community/releases) and put it in place of the old one (same folder, same name, so the path in Preferences stays valid).
2. A file downloaded with a browser is not executable and is marked as quarantined by macOS, so the server will not start. In Terminal, with the path of your file:

```bash
chmod +x "/path/to/gRPCServerCLI-macOS"
```

```bash
xattr -d com.apple.quarantine "/path/to/gRPCServerCLI-macOS"
```

3. Start the server again from DT Hub (Connect, or restart the app).

The second command tells macOS to skip its check on a downloaded program: run it only on a file you downloaded yourself from the official releases page.

## Build from source

1. Install the Metal Toolchain once (MLX's shaders need it):

        xcodebuild -downloadComponent MetalToolchain

2. Open `DTHub.xcodeproj` in Xcode and run the **DTHub** scheme, or from a terminal:

        xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' build

3. The logic lives in Swift packages: run its tests from `Packages/`:

        cd Packages && swift test

   Each plug-in is a package of its own, with its own tests (`cd Plugins/PromptMasterI4 && swift test`).

## The local LLM

DT Hub looks for MLX models (Hugging Face format: a folder with `config.json` and `.safetensors` files) in the folder you choose in **Preferences › LLM**. The recommended model is `mlx-community/Qwen3-VL-8B-Instruct-4bit` (about 5.8 GB, Apache-2.0); the Preferences can download it, but only when you ask and after a dialog that names the repository, the size and the destination. The same pane has a test question, with or without an image.

Each installed LLM can be assigned to a model family and a use (enhance, generate, both, plug-ins only); a dedicated LLM's own `system_prompt.txt` is used when present. With a single LLM installed nothing needs to be set up.

### The prompts that guide the LLM

What *Enhance Prompt* and *Generate Prompt* tell the LLM is not hidden in the code: it is a set of Markdown files in `~/Library/Application Support/DT Hub/Data/DTHub/`, written by the app at launch and read at every request.

- `rules/` — the rules of the task (`enhance.md`, `describe.md`).
- `family/` — the instructions of each model family (one file per family, named with the id of the family), including the rule for the answer (plain prose, or JSON with a negative prompt) and the length. **These are the app's own files: changing them is not recommended** (a newer version of the app rewrites them, keeping the old one as `.md.bak`).
- `custom/` — **yours**. `enhance.md` and `describe.md` add instructions for a task; `family-<id>.md` adds them for one family. They go last and win if they disagree with the app's. A file may start with a header `---` / `mode: replace` / `---` to replace the app's text instead of adding to it. `custom/families.txt` lists the names and ids of the families.

An LLM that comes with a system prompt of its own (Qwen's prompt enhancers) receives only your `enhance.md` / `describe.md`, added after its own text; being trained for one job, such a model may ignore instructions that go against it (for example to write in another language).

**Preferences › LLM › Prompts** opens the folder, shows which families have a file of their own and the final text the LLM receives.

## Plug-ins

A plug-in is a bundle (`.dthubplugin`) with a dynamic library, loaded into the app and shown as a tab. You add one in **Preferences › Plug-ins**. A plug-in only works with the model families it was made for: on any other family it is switched off and its tab is hidden. Plug-ins work on your Mac; the one exception is LoRA Advisor, which contacts Civitai and Hugging Face when you press its buttons to find or import a LoRA's page (it says what it sends in its README). The plug-ins in this repository, which families each one works with, and how to build and install them are described in [`Plugins/README.md`](Plugins/README.md). To write your own, start from [`PluginKit/README.md`](PluginKit/README.md): the app and a plug-in talk only through Objective-C selectors and JSON messages, and the kit includes the design system so a plug-in tab looks like the rest of the app.

## Languages

The interface of the app and of the plug-ins is available in **English and Italian** and follows the language of macOS. The design documents in [`docs/superpowers/`](docs/superpowers/) (specs and plans) are written in Italian.

## Repository layout

| Folder | What is in it |
| --- | --- |
| `App/` | The app: connection, controls, generation, main window, plug-in host, preferences, results. |
| `Packages/` | The logic (`HubCore`, `HubKit`, `DTBridge`, `LLMBridge`, `PluginHost`) and its tests. |
| `PluginKit/` | The kit and the design system a plug-in is written with; contract 1 of the plug-ins. |
| `Plugins/` | Prompt Master, Prompt Master I4, Sphere Light Reference, Character Sheet, Batch plus, AI Assistant, Qwen 2.1 Inpainting and LoRA Advisor. |
| `docs/superpowers/` | Specs and plans (in Italian). |

## Status

An early version (0.2.3), used daily by its author. Feedback, bug reports and ideas are welcome: open an [Issue](../../issues).

## License

[GPL-3.0](LICENSE).

The compute-unit calculation of the CU meter is ported from [draw-things-community](https://github.com/drawthingsai/draw-things-community) (GPL-3.0), by Draw Things Technologies.
