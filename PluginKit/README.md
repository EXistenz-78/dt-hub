# DTHubPluginKit

The package a DT Hub plug-in is written with. It does not depend on DT Hub: the app and a plug-in only talk through
Objective-C selectors and JSON messages (see `docs/superpowers/specs/2026-10-03-plugin-design.md`).

## Writing a plug-in

1. A Swift package with a **dynamic** library product that depends on `DTHubPluginKit` (copy `Examples/Sample`).
2. A class conforming to `DTHubPlugin` (`manifest`, `makeViewController()`, `start(host:)`, `handle(_:)`).
3. A subclass of `DTHubPluginEntry` with an Objective-C name, overriding `makePlugin()`:

        @objc(MyPluginEntry)
        public final class MyPluginEntry: DTHubPluginEntry {
          public override func makePlugin() -> any DTHubPlugin { MyPlugin() }
        }

4. `swift build`, then wrap the library into a bundle:

        Scripts/make-bundle.sh .build/out/Products/Debug/libMyPlugin.dylib MyPlugin.dthubplugin com.you.myplugin MyPlugin 1.0 MyPluginEntry

   The arguments are the library, the bundle to make, the identifier (it must equal `manifest.id`), the name, the
   version, the principal class and, optionally, the contract version (default 1).

The bundle is added in DT Hub › Preferences › Plug-ins.

## The look of the app

`DTHubDesign` (a second product of this package, SwiftUI only) holds the components of the app: `DS` (colours, radii,
spacing), `dsPanel`, `DSPanelHeader`, `DSGroupHeader`, `DSCollapsibleCard` (with an optional `trailing` accessory),
`DSPillButtonStyle`, `DSGlassCircleButtonStyle`, `DSCheckboxToggleStyle`, `dsGlass`… A plug-in tab that uses them looks
like the rest of DT Hub. Take the product next to the kit and give **each** module an alias of its own (the kit does not
re-export the design system: with `moduleAliases` that does not resolve):

        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "MyPluginKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "MyPluginDesign"]),

and `import DTHubDesign` in the views (see `Plugins/SphereLight`).

## Messages (contract 1)

JSON objects with a `type`. An unknown type gets `{"type":"unsupported"}`.

**App → plug-in:** `context` (model, family, `parameters`: the Generation tab's parameters as they are when the message is sent — `width`, `height`, `steps`, `guidanceScale`, `sampler`, `shift`, `resolutionDependentShift`, `cfgZeroStar`, `cfgZeroInitSteps`, `seed`, `randomSeed`, `batchSize`, `batchCount`, `loras` (`[{"file","weight","mode","trigger"}]`), and `advanced` and `extra` (name → value, to show and not to change); `DTHubContext.parameters` reads them with tolerance, a missing or mistyped value is nil and never costs the rest of the context; `tempFolder`: a folder to exchange picture files through;
`prompt`, `negativePrompt`: the Generation tab's prompts as they are now (an empty one is still sent; absent from older apps); `strength`: how much the start image is changed, 0–1, as the Control tab's slider shows it (absent without a start image); `startImage`: the path of the Control tab's start image when there is one; `moodboard`: the paths of the Moodboard
pictures that are on, in the order of the thumbnails; `languageModels`: `[{"name", "path", "supportsImages", "family", "use"}]`, the
language models of the app's models folder (`family`: the family the user assigned the model to in Settings › LLM — `"*"` for "all others", otherwise the family key such as `"qwen_image_2.1"`, absent for none; `use`: `"enhance"`, `"describe"`, `"both"`, `"plugins"`, `"i2i"` (like both, but only when the Control tab has images) or `"t2i"` (like both, but only when it is empty); both are optional additions) — each key is left out when there is nothing to say; the app sends the context again when a plug-in's tab is shown),
`activate`, `deactivate`, and `project`: `{"type":"project","name","folder","adoptLegacy"}`, sent to every loaded plug-in (on for the job or not) when a project is opened and right after launch. `folder` is a folder of the plug-in's own inside the project (the app has created it): keep the state there (for example `<folder>/state.json`, written at every change), load what is there, and take no file or an unreadable one as the initial state. `adoptLegacy` is true once, for the first project ever: if `folder` has no state yet, move the state you had before projects into it. A plug-in that does not handle `project` (it answers `unsupported`) keeps one global state; the app tells the user once. `DTHubProject` decodes it.

**Plug-in → app:**

- `notice` — `text`, `isError`: a line shown over the window.
- `contribute` — what the plug-in puts on the Generation and Control tabs. Every key is optional; what cannot be
  read is left out; the answer is `{"type":"ok","conflicts":n,"problems":[…]}` or `{"type":"error","text":…}`.
  Only a plug-in that is on for the job (header menu) can contribute.
  - `fields`: `prompt`, `negativePrompt` (text); `width`, `height`, `steps`, `cfgZeroInitSteps`, `seed`, `batchSize`,
    `batchCount` (whole numbers); `guidanceScale`, `shift` (numbers); `cfgZeroStar`, `resolutionDependentShift`,
    `randomSeed` (true/false); `sampler` (the number of the Draw Things sampler, or its name). Values are limited like
    the cards limit them. A plug-in never changes the model.
  - `loras`: `[{"file", "weight", "mode", "trigger"}]`, added to the LoRA card.
  - `moodboard`: `[{"path", "name"}]`, files in the `tempFolder`, added to the Moodboard. Sending them again replaces
    the ones this plug-in sent before.
  - `startImage`: `{"path", "name"}`, the start image of the Control tab.
  - `strength`: a number, 0–1 (values outside are brought into it): how much the start image is changed, the Control tab's slider. It applies only when the tab has a start image (otherwise `problems` says so), after a `startImage` of the same message; it is not a field of the tab, so it is not coloured teal and raises no conflict: the last one to write wins.
  - `pipeline`: `{"name", "steps": [...]}`; each step is `{"title", "preset", "fields", "loras", "moodboard",
    "startImage", "useOutputAsStart"}`: the name of a preset in the app's Preset menu (its parameters, prompt and negative
    prompt are applied on the tab's fields, but not its model nor a size); then `fields`, the values this pass changes
    (the keys of `contribute.fields`, applied after the preset; a size in it is ignored, a pass never changes the size;
    the advanced values and the extras stay those of the tab); then `loras`, `[{"file","weight","mode","trigger"}]`: a
    LoRA already on the tab gets the weight (and the mode or trigger word when they are not the defaults), a new one is
    added at the end. A step with neither preset, `fields` nor `loras` runs the tab as it is. Then the Moodboard for the
    pass (replaces the tab's), a start image, and whether the picture the previous pass made becomes the start image. RUN
    then runs the passes one after the other; if a preset is not in the menu it says so and runs nothing.
  The fields a plug-in filled turn teal; the user can always change them. If two plug-ins fill the same field, or
  both propose a start image or a pipeline, the user chooses in a pop-up.
- `presets` — `{"presets": [{"name", "fields", "loras"}]}`: presets for the Preset menu. Each is a
  file in the app's Presets folder, named after the preset. **Name them with your own acronym** (2–4 letters), a
  middle dot and the name — `SMP · Overcast`, `SLR · Match the sun` — because that is the only sign of where a
  preset comes from. A name cannot contain `/` or `:`, start with a dot or be longer than 120 characters (file system rules); capitals and accents do not tell two
  names apart. `fields` has the keys of `contribute` above, the prompt and the negative prompt included; no size,
  no model. A name the menu has already is never touched (the user may have changed it), so register them
  whenever you like. The answer is `{"type":"ok","added":n,"existing":m,"rejected":k}`.
- `llm` — `{"prompt", "images": [paths], "system", "model", "options", "messages"}`: a question for the language model. `messages` (optional) holds the earlier turns of a conversation, oldest first: `[{"role":"user"|"assistant","text"}]`; `prompt` is the new message and `images` go with it (an entry with another role or without a text is skipped). `DTHubHost.askLanguageModel(…, history:)` sends them. The answer
  is `{"type":"llm","text":…}` (it can take a while: the model may have to load) or an `error`. Only `prompt` is
  needed. `system` is the system prompt. `model` is the `name` of one of `languageModels` and asks for that model
  instead of the one the user chose (the user's choice stays; an unknown name is an `error`). `options` is an object
  with `temperature` (0–2), `topP` (0–1), `topK` (0–200), `presencePenalty` (−2–2), `maxTokens` (1–32768) and
  `thinking` (true/false: lets a reasoning model think first); a number out of range is brought into range, what is
  not set keeps the app's default (temperature 0.6, 1024 tokens). With the library: `host.askLanguageModel(prompt,
  system:, model:, options: DTHubLLMOptions(…))` returns the text or nil, `askLanguageModelAnswer` also gives the
  app's reason; `DTHubLLMOptions.timeout` (seconds, 300 by default, 1800 at most) is how long the library waits and
  is not sent.

The Sample plug-in (`Examples/Sample`, `Scripts/build-sample.sh OUT [b]`) sends all of these.
