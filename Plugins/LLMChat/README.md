# LLM Chat

A plug-in for DT Hub to **chat with a local LLM** about what you are preparing: improve a prompt, discuss the settings, get the start image and the Moodboard pictures described, prepare variants. **Works with: all model families.**

With a command you give, the LLM can also **change the Generation tab for you**: the prompt and the negative prompt, the parameters, the weight of the LoRAs on the card, the strength of the start image, or a **pipeline** (variants, series of tests on a parameter, combinations, chains of passes, at most 20). **You always press Run yourself.**

## The command

The LLM acts only when your message contains **`<SEND>`** (or **`<INVIA>`**, with the app in Italian), spelled exactly so. The button next to the text field adds it at the end of what you are writing; then press Return. Without it nothing is ever changed, even if the answer contains an action block: the plug-in ignores it and says so. After a send, a line in the chat tells what went (`Sent: prompt, steps, LoRAs (2), strength.`), with any conflict or problem the app reports.

What it can change: prompt and negative prompt, size, steps, guidance, shift, CFG-Zero*, seed, sampler, batch, the weight of the LoRAs already on the card, the strength, and pipelines (each pass only lists what it changes; no size). What it cannot do: press Run, change the model, touch the advanced settings, remove the start image or the Moodboard pictures, load presets.

## Images

The **Images** switch sends, with your message, the start image and the Moodboard pictures that are on, numbered the way Draw Things numbers them (the start image is 1), so "image 2" means the same picture to the LLM. It needs a model that reads images; with a text-only model the switch is off. The pictures are not kept in the chat, only their names.

## Model, chats, projects

- You choose the **model** in the plug-in (any LLM of the models folder); it does not depend on the assignments in Settings › LLM.
- **Chats are kept per project.** *New chat* archives the open one; the *Chats* menu opens an earlier chat, renames or deletes it.
- The LLM receives the earlier messages of the chat, the most recent ones that fit in 24 000 characters (a note says when the oldest are left out), the current state of the Generation tab, and the app's **guide for writing prompts** for the family of the chosen model (the same one Enhance Prompt follows), when the app has one.

## Requirements

DT Hub 0.1.6 or later (the app has to send the prompts and the strength in its context, accept the chat history in the `llm` message and the `strength` key in `contribute`), and an LLM in the models folder (Settings › LLM). For the images, a model with vision.

Build: `Plugins/LLMChat/Scripts/build.sh <folder>` → `LLMChat.dthubplugin`. Tests: `swift test` in this folder. Design: `docs/superpowers/specs/2026-10-10-plugin-llm-chat-design.md`.
