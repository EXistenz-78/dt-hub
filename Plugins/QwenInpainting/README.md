# Qwen 2.1 Inpainting

A plug-in for DT Hub for **Qwen Image 2.1**, inspired by the Sketch node of ComfyUI-Pixaroma (no code of that project is used). **Works with: Qwen Image 2.1 only.**

You draw **colored marks** on the start image (brush, rectangle, oval, arrow) and, for each pair of **color and tool**, write what to change there. *Send* puts the drawing in the **Brush layer** of the Canvas card in the Control tab and writes the prompt. At RUN the app puts the drawing over the image; Qwen reads the instructions and removes the marks. There is no mask.

## Drawing

- **Tools:** brush, rectangle, oval, arrow; the **width** goes from 4 to 128 px of the start image. **Nine pure colors:** yellow, red, blue, cyan, magenta, green, purple, white, black. Undo, Redo and Clear all (up to 200 marks).
- The start image is the one of the Control tab. When it changes, the marks go (the texts stay).

## Cards and prompt

There is **one card for each pair of color and tool**: two green rectangles are one card, a green rectangle and a green brush stroke are two. The title and the sentence use the plural when there is more than one mark:

| Tool | Card title | Sentence in the prompt |
| --- | --- | --- |
| rectangle | `INSIDE red box(es)` | `Inside the red box(es): <text>` |
| oval | `INSIDE red circle(s)` | `Inside the red circle(s): <text>` |
| brush | `INSIDE red sketch(es)` | `Inside the red sketch(es): <text>` |
| arrow | `WHERE red arrow(s) point(s)` | `Where the red arrow(s) point(s): <text>` |

The sentences, in the order of the cards, are followed by **«Remove all the colored marks and keep everything else the same.»** The text of a card is kept even when its marks are gone. A drawing without any text only sends the drawing and leaves the Prompt field alone.

## Qwen's prompt enhancer

If an LLM is assigned to **Qwen Image 2.1 · I2I** in Settings › LLM (the PE I2I), a box *Improve with …* appears (off by default): the prompt is sent to it together with the start image and the marks, and the rewritten prompt is written into the tab. If it fails, the direct prompt is sent and the status says why. Without it, the sentences go straight into the prompt.

## State

The marks, the texts, the tool, the color, the width and the box are kept **per project**.

## Requirements

DT Hub 0.1.7 or later (the app has to accept `contribute.paint`), and Qwen Image 2.1 selected.

Build: `Plugins/QwenInpainting/Scripts/build.sh <folder>` → `QwenInpainting.dthubplugin`. Tests: `swift test` in this folder. Design: `docs/superpowers/specs/2026-10-10-plugin-qwen-inpainting-design.md`.
