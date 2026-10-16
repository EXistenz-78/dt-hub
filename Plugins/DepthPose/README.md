# Depth & Pose

A plug-in for DT Hub that makes a **depth map** and/or an **OpenPose skeleton** from one picture, in a moment, and puts them in the Moodboard (or on your Desktop), so an edit or in-context model can take them as a reference. **Works with: edit and in-context models, whatever their family** (FLUX.2 [klein] and dev, Qwen Image 2.1, Qwen Image Edit, FLUX.1 Kontext, HiDream E1…). With any other model the plug-in is switched off and its tab is hidden; that needs a DT Hub version that knows the plug-in manifest's `requiresEditModel` key, an older one shows the tab with every model.

The maps come from small dedicated models, in about a second, instead of a generation with a LoRA.

## Using it

1. **Drop a picture** on the tab (a file from the Finder, or a picture dragged from a browser when it hands over the picture itself; an address alone is not followed), or press **Open…**.
2. Tick **Depth**, **Pose** or both. The choice is kept per project.
3. Press **Create**. The maps appear side by side on the right.
4. **Send to the Moodboard** puts the ticked maps in the Moodboard, named *Depth* and *Pose*; sending again replaces the ones this plug-in sent before. **Save to Desktop** keeps a copy as `Depth 001.png` and `Pose 001.png` (the first free number, an earlier file is never overwritten);

A picture is never changed. The plug-in works on at most 2048 pixels on the long side, and the maps come out at that size.

## Depth

[Depth Anything V2](https://github.com/DepthAnything/Depth-Anything-V2) **Base**, converted to Core ML (see *The depth model* below). Near is bright, far is dark, stretched over the whole picture. The model takes one fixed size for landscape pictures (1036×784) and one for portrait ones (784×1036): the picture is fitted inside it without being deformed, the padding is cut away from the answer and the map is brought back to the size of the picture. A square picture uses the landscape size.

The first map of each orientation takes up to half a minute, while Core ML prepares the model for the Neural Engine; after that, about a second.

## Pose

Apple's Vision framework finds the people (2D body pose, every person in the picture) and the plug-in draws them as an **OpenPose** picture: the 18 points and 17 bones with OpenPose's colours on a black background. A joint Vision is not sure of (confidence below 0.3) is left out, and so is a bone with a missing end; if nobody is found, the plug-in says so and sends nothing for the pose.

Limits: body only (no hands and no face), and Vision often cannot tell where a limb is when it is hidden. A better pose model is planned.

## The depth model

The **Download the model (200 MB)** button appears **only when the plug-in does not find the model**. Until it is there the Depth box is off; the pose works without it. The download checks the size and the SHA-256 of every file, compiles the model and only then puts it in place: a failed or cancelled download leaves nothing behind. The model lives in `~/Library/Application Support/DT Hub/Data/DepthPose/`: `DepthAnythingV2BaseF16.mlpackage` (the three files) and `DepthAnythingV2BaseF16.mlmodelc` (compiled). If you put the package there by hand (for example one you downloaded from the [release](https://github.com/EXistenz-78/dt-hub/releases/tag/depth-anything-v2-base-coreml)), the plug-in checks and compiles it at the next launch.

**Licence.** The original weights are by Lihe Yang et al. ([Depth Anything V2](https://github.com/DepthAnything/Depth-Anything-V2)) under **CC BY-NC 4.0**: the converted files carry it too, so use and share them for non-commercial purposes, with attribution, and do not sell them or include them in a commercial product. Changes made: converted to Core ML (float16, fixed shapes, functions merged, output normalised). DT Hub and this plug-in are free and under their own licence; the model keeps its own. The conversion script is in `Scripts/convert_depth_model.py` (`requirements-convert.txt`; `python convert_depth_model.py OUT_DIR [base|large]`).

## Network

This is one of two plug-ins of DT Hub that use the network (the other is LoRA Advisor), and only when you press **Download the model**:

- It downloads three files from the GitHub release of this repository, `github.com` and the servers GitHub serves release files from (`githubusercontent.com`); a redirect anywhere else is refused.
- Requests are `GET` over https, with no cookies and no credentials. Nothing of yours leaves your Mac: no picture, no prompt, no account. The depth and the pose are computed on your Mac.

## Good to know

- The picture and the maps are not kept: reopening a project starts the tab empty, with your Depth and Pose boxes as you left them.
- The maps go to the picture folder the app lends the plug-in (they are copied into the Moodboard) and are overwritten by the next send.
- The Depth box is greyed out, and **Create** with only Depth ticked is disabled, until the model is on the disk.

## Build

    Plugins/DepthPose/Scripts/build.sh OUT_FOLDER

Tests: `cd Plugins/DepthPose && swift test` (no test touches the network, a model or Vision on a real person; `DP_RENDER_DIR=folder swift test --filter RenderTests` writes pictures of the tab). Probes with the real model and the real Vision are behind `DTHUB_LIVE_DEPTH=1` (see `Tests/DepthPoseTests/LiveTests.swift`). Design: `docs/superpowers/specs/2026-10-16-plugin-depth-pose-design.md`.
