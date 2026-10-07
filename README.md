# DT Hub

A native macOS app that replaces the interface of [Draw Things](https://drawthings.ai/) for **preparing and launching image generations**. DT Hub talks to a Draw Things gRPC server, adds a local LLM (MLX) that can write and improve prompts for you, and grows through plug-ins that each bring their own tab.

This is an independent community project, not affiliated with or endorsed by Draw Things Technologies. It started as a personal tool and is published as open source under the GPL-3.0.

<!-- Screenshots go here (see docs/images/). -->

## What it does

- **One window, one flow.** A header with the model menu, the connection status and a single **Run** button; a tab for the inputs, a tab for the parameters, and one more tab per active plug-in.
- **Generation tab.** The prompt (with the negative prompt, shown only for families that use it) and collapsible cards for dimensions, sampling, seed and batch, LoRAs and an advanced section. Every value can be typed or stepped; the open/closed state of each card is remembered. A JSON editor shows and edits the whole configuration.
- **Control tab.** The start image (image-to-image), a **Moodboard** of reference pictures (each can be switched on or off), and a **Canvas** card: frame the image, outpaint, paint an inpainting mask or draw in colour straight onto the image, with undo and redo. The Canvas card can be opened in a window of its own, with nothing but the drawing, so it can be moved to a second screen (an iPad with Sidecar, for instance) and drawn on with an Apple Pencil.
- **Tiled Diffusion** for sizes up to 8192 × 8192.
- **Presets and preset pipelines.** Save a configuration as a preset and chain several presets into one Run. Recommended settings per model family are suggested for you.
- **Results window.** Live preview while generating, then the image. A strip keeps the images of the session (and brings back the last ones after a restart): each thumbnail shows how many seconds it took, can be dragged into the Control tab or any other app, and offers *Use as image*, *Add to Moodboard*, *Show in Finder*, *Resume parameters* and *Trash*. Every image is saved as a PNG with its prompt, its whole configuration and the time it took inside the file.
- **Keyboard.** ⌘↩ Run, ⌘. Stop, ⌘R Results, ⌃Page Up / ⌃Page Down to step through the tabs.
- **Managed server.** DT Hub can start Draw Things' `gRPCServerCLI` by itself, or connect to the server of the Draw Things app.
- **Local LLM (MLX).** A vision-capable model runs inside the app, with controls to free memory so that the image model and the LLM can share a Mac. Nothing is downloaded unless you ask for it.
- **Plug-ins.** See [`Plugins/`](Plugins/README.md): Prompt Master, Prompt Master I4 (for Ideogram 4) and Sphere Light Reference.

## Requirements

- macOS 26 and an Apple Silicon Mac.
- A Draw Things gRPC server: the Draw Things app with its API server enabled, or the `gRPCServerCLI` binary, which DT Hub can start itself.
- To build: Xcode 27.

## Install

For now DT Hub is built from source (below). A pre-built, signed app will be offered under [Releases](../../releases) when one is available.

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

## Plug-ins

A plug-in is a bundle (`.dthubplugin`) with a dynamic library, loaded into the app and shown as a tab. You add one in **Preferences › Plug-ins**, or by dropping it into `~/Library/Application Support/DT Hub/Plug-ins/`. The three plug-ins in this repository, and how to build and install them, are described in [`Plugins/README.md`](Plugins/README.md). To write your own, start from [`PluginKit/README.md`](PluginKit/README.md): the app and a plug-in talk only through Objective-C selectors and JSON messages, and the kit includes the design system so a plug-in tab looks like the rest of the app.

## Languages

The interface of the app and of the plug-ins is available in **English and Italian** and follows the language of macOS. The design documents in [`docs/superpowers/`](docs/superpowers/) (specs, plans, backlog) are written in Italian.

## Repository layout

| Folder | What is in it |
| --- | --- |
| `App/` | The app: connection, controls, generation, main window, plug-in host, preferences, results. |
| `Packages/` | The logic (`HubCore`, `HubKit`, `DTBridge`, `LLMBridge`, `PluginHost`) and its tests. |
| `PluginKit/` | The kit and the design system a plug-in is written with; contract 1 of the plug-ins. |
| `Plugins/` | Prompt Master, Prompt Master I4 and Sphere Light Reference. |
| `docs/superpowers/` | Specs, plans and the backlog (in Italian). |

## Status

An early version (0.1.0), used daily by its author. Feedback, bug reports and ideas are welcome: open an [Issue](../../issues).

## License

[GPL-3.0](LICENSE).
