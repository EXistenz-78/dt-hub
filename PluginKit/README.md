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

The manifest also says which models the plug-in is for: `families` (model families; nil = all) and, since DT Hub 0.3.0,
`requiresEditModel: true` for a plug-in that only makes sense with an edit or in-context model (one that takes pictures as
references: FLUX.2 [klein], Qwen Image Edit, Kontext…). With any other model DT Hub switches the plug-in off and hides its
tab. An older DT Hub ignores the key and keeps the plug-in on.

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
`prompt`, `negativePrompt`: the Generation tab's prompts as they are now (an empty one is still sent; absent from older apps); `promptGuide`: `{"label","usesNegative","notes"}`, how to write prompts for the family of the chosen model — the guide the app's Enhance Prompt follows (absent when there is none); since 0.1.9 it also carries `familyPrompt` (the whole Family prompt, placeholders resolved: the rule for the answer and the notes), `words` and `maxWords` (all optional, absent from older apps); `strength`: how much the start image is changed, 0–1, as the Control tab's slider shows it (absent without a start image); `startImage`: the path of the Control tab's start image when there is one; `moodboard`: the paths of the Moodboard
`startImageWindow`: `{"x","y","width","height"}`, where the start image sits in the Generation canvas as the Control tab's framing puts it — the part of the image that fills the canvas, in the image's pixels from the top-left. It can be larger than the image (zoom below 0: the rest is margin the model regenerates) or smaller (zoom above 0). Absent without a start image or from an app older than 0.4.0 (number provisional); the plug-in then falls back to the whole image fitted to the canvas. `lastResult`: `{"path","name"}`, the newest result of the open project (the first of the Results strip), a file; absent when there is none (needs DT Hub 0.5.0). It changes when a new result arrives, so a plug-in that shows it is told.
pictures that are on, in the order of the thumbnails; `languageModels`: `[{"name", "path", "supportsImages", "family", "use"}]`, the
language models of the app's models folder (`family`: the family the user assigned the model to in Settings › LLM — `"*"` for "all others", otherwise the family key such as `"qwen_image_2.1"`, absent for none; `use`: `"enhance"`, `"describe"`, `"both"`, `"plugins"`, `"i2i"` (like both, but only when the Control tab has images) or `"t2i"` (like both, but only when it is empty); both are optional additions) ; `loraCatalog`: `[{"file","name","family","trigger","weight"}]`, the LoRAs of the server as the app's LoRA manager has them, with the user's trigger words and weights (`family` is left out when the server does not say; since 0.2.2 the key is always there, empty when there is no LoRA or no server, so a plug-in that does not find it is talking to an older app; `DTHubContext.loraCatalog` skips an entry it cannot read) — each other key is left out when there is nothing to say; the app sends the context again when a plug-in's tab is shown),
`activate`, `deactivate`, and `project`: `{"type":"project","name","folder","adoptLegacy"}`, sent to every loaded plug-in (on for the job or not) when a project is opened and right after launch. `folder` is a folder of the plug-in's own inside the project (the app has created it): keep the state there (for example `<folder>/state.json`, written at every change), load what is there, and take no file or an unreadable one as the initial state. `adoptLegacy` is true once, for the first project ever: if `folder` has no state yet, move the state you had before projects into it. A plug-in that does not handle `project` (it answers `unsupported`) keeps one global state; the app tells the user once. `DTHubProject` decodes it.

**Plug-in → app:**

- `notice` — `text`, `isError`: a line shown over the window.
- `contribute` — what the plug-in puts on the Generation and Control tabs. Every key is optional; what cannot be
  read is left out; the answer is `{"type":"ok","conflicts":n,"problems":[…]}` or `{"type":"error","text":…}`.
  Only a plug-in that is on for the job (header menu) can contribute.
  - `fields`: `prompt`, `negativePrompt` (text); `width`, `height`, `steps`, `cfgZeroInitSteps`, `seed`, `batchSize`,
    `batchCount` (whole numbers); `guidanceScale`, `shift` (numbers); `cfgZeroStar`, `resolutionDependentShift`,
    `randomSeed`, `highRes` (true/false; HiRes (beta) lets a side go up to 8192, a preset that makes a big picture turns it on); `sampler` (the number of the Draw Things sampler, or its name). Values are limited like
    the cards limit them. A plug-in never changes the model.
  - `loras`: `[{"file", "weight", "mode", "trigger"}]`, added to the LoRA card.
    With `"replaceLoRAs": true` (and at least one LoRA) the LoRAs already on the card are taken off first, so only the ones sent remain.
  - `moodboard`: `[{"path", "name"}]`, files in the `tempFolder`, added to the Moodboard. Sending them again replaces
    the ones this plug-in sent before.
  - `startImage`: `{"path", "name"}`, the start image of the Control tab.
  - `paint`: `{"path", "name"}`, a PNG with transparency in the `tempFolder`: it becomes the **Brush layer** of the Canvas card in the Control tab, over the start image, where the user sees it and can change it. It replaces the drawing that was there (Undo in Control brings it back), is stretched to the ratio of the start image, and at RUN the app puts it over the image. It needs a start image (otherwise `problems` says so) and applies after a `startImage` of the same message. It is not a field of the tab: no teal and no conflict, the last one to write wins.
  - `strength`: a number, 0–1 (values outside are brought into it): how much the start image is changed, the Control tab's slider. It applies only when the tab has a start image (otherwise `problems` says so), after a `startImage` of the same message; it is not a field of the tab, so it is not coloured teal and raises no conflict: the last one to write wins.
  - `result`: `{"path", "name", "description"}` (needs DT Hub 0.3.2 or later), a finished picture the plug-in made (a PNG
    in the `tempFolder`, any size). The app keeps it as a result: saved in the project's folder with the metadata of Draw
    Things and put first in the **Results** strip, filed under the model in the header; `description` takes the place of the
    prompt in the Results window's side panel. While a pipeline the plug-in guides is running it is filed under that
    pipeline's model (send it while handling `session.end`); since DT Hub 0.5.0 it is accepted at any other time
    too, filed under the model chosen in the header and with no generation time. A missing or unreadable file, or no model,
    comes back in `problems`. No teal, no conflict.
  - `pipeline`: `{"name", "steps": [...]}`; each step is `{"title", "preset", "fields", "loras", "moodboard",
    "startImage", "useOutputAsStart"}`: the name of a preset in the app's Preset menu (its parameters, prompt and negative
    prompt are applied on the tab's fields, but not its model nor a size); then `fields`, the values this pass changes
    (the keys of `contribute.fields`, applied after the preset; a size in it is ignored, a pass never changes the size;
    the advanced values and the extras stay those of the tab); then `loras`, `[{"file","weight","mode","trigger"}]`: a
    LoRA already on the tab gets the weight (and the mode or trigger word when they are not the defaults), a new one is
    added at the end. A step with neither preset, `fields` nor `loras` runs the tab as it is. Then the Moodboard for the
    pass (replaces the tab's), a start image, and whether the picture the previous pass made becomes the start image. RUN
    then runs the passes one after the other; if a preset is not in the menu it says so and runs nothing.
  - `pipeline` **guided by the plug-in** (needs DT Hub 0.3.2 or later): `{"name", "guided": true, "passes": n,
    "estimate": {…one pass…}}`, with no `steps`. `passes` (≥ 1) is how many passes the plug-in will hand over;
    `estimate` is a pass like the biggest one, so the CU meter can measure `n` of them. The user sees it on the Run
    button ("Run · n passes") and presses RUN as for any pipeline; the app then **asks the plug-in for each pass in
    turn** (see *Guided pipeline* below). While it runs, no other pipeline and no RUN can start.
  - `preset`: the name of a saved preset (needs DT Hub 0.5.0), applied **first**, as the Preset menu applies it
    (parameters, prompt and negative prompt when it has them, its LoRAs, its advanced values, and its model when it names one); the
    rest of the same message (`fields`, `loras`, `startImage`, `strength`…) is applied on top. The fields the preset changed turn
    teal for the plug-in; no conflict, the last one to write wins. A name the menu does not have, or a pipeline that is
    running, comes back in `problems` (`"preset: …"`) and changes nothing.
  The fields a plug-in filled turn teal; the user can always change them. If two plug-ins fill the same field, or
  both propose a start image or a pipeline, the user chooses in a pop-up.
- **Guided pipeline** (app → plug-in, answered by the plug-in), for a plug-in that has to compose or choose between
  one pass and the next (Tiled Upscale cuts a tile out of a picture that already holds the result of the one before):
  - `{"type":"session.next","index":3,"count":12,"previous":{"path","width","height"}}`: the pass wanted (1-based),
    the total, and the picture the previous pass made, a PNG in the `tempFolder` (absent at the first pass). The plug-in
    answers within 60 seconds with **one self-contained pass**:
    `{"title","startImage":{"path","name"},"moodboard":[{"path","name"}],"mask":{"path","name"},
    "maskSettings":{"blur","outset","preserveOriginal"},
    "size":{"width","height"},"preset","fields","loras","strength"}`, or `{"done":true}` to end before `count` (not an error).
    `startImage` is a PNG of exactly `size` (a multiple of 64, at most the model's size limit): the app sends it as it is,
    never reframed or resampled. Since DT Hub 0.7.1 it is **optional**: a pass with no
    `startImage` draws on an empty canvas of `size`, which is what a model that takes its pictures from the Moodboard
    wants; `strength` then means nothing. `moodboard` (since DT Hub 0.7.1) is the pass's own Moodboard, files in
    the `tempFolder`, in the order they are numbered for the model (`<image 1>`, `<image 2>`…); it can go with or without a
    `startImage`, and is left out for a family that does not read the Moodboard. `mask` is an optional grey PNG of the same
    size, **255 where the model regenerates**, 0 where the picture is kept (it needs no multiple of 64 for its inner
    edge) and **needs a `startImage`**; without a mask the whole picture is regenerated. `maskSettings` is how Draw Things treats the mask (blur 0–30, outset 0–100, keep the original outside it);
    without it the Control tab's are used. `preset`, `fields` (a size in them is ignored: `size` rules), `loras` and
    `strength` (0–1, default 1) work as in a step of `pipeline`. The model is always the header's, and the Control tab (its
    picture, mask and Moodboard) is not used. An answer that does not fit (no `size`, a size not multiple
    of 64 or too big, a `startImage` that cannot be read or of another size, a mask of another size or with no `startImage`,
    no answer in time) ends the pipeline. A Moodboard picture that cannot be read is left out, as in a step of `pipeline`.
  - `{"type":"session.end","reason":"finished"|"stopped"|"failed"|"closed"}`: sent once when the pipeline is over (all
    passes done or `done`; Stop; a pass failed; the plug-in did not answer or the model was changed meanwhile). The plug-in
    frees its memory and files, and with `finished` sends its `result`. Its answer is ignored. When the run ends the app
    takes the pipeline off the Run button (its session is gone).
  - `{"type":"queue.capture","folder":"…"}` (optional, an addition to contract 1): the user put the guided pipeline that is on
    RUN in the app's queue. Write the files you will need to guide it again (the picture you start from) into `folder` and answer
    `{"type":"ok","state":{…}}`, an object of your own that names them (relative names) and holds your choices; or
    `{"type":"error","text":…}` when nothing is prepared. A plug-in that answers `unsupported` cannot be queued.
    `DTHubQueueCapture` decodes it, `DTHubMessage.ok(state:)` / `.failure(_:)` answer.
  - `{"type":"queue.prepare","folder":"…","state":{…},"model":"…","family":"…"}`: the queued entry runs now. Rebuild your session
    from `folder` and `state`, show that state as if the user had set it, and propose the guided pipeline with `contribute` as
    your own Prepare does, **without asking for any confirmation**. `model` and `family` (absent when unknown) are the header's
    after the entry's model was chosen: a plug-in that is not active has not been told, so take them before looking for a
    preset. Answer `{"type":"ok"}` once the app accepted the pipeline, or an `error`. There is no time limit on a queued run:
    **answer `session.end` only when you are done** (the montage has been handed over), because the queue waits for it before
    it starts the next entry. `DTHubQueuePrepare` decodes it.
  The pictures of the passes are **not results**: they are written to files of their own (in a folder the app makes inside the `tempFolder`, named in
  `previous`), and go neither to the Results strip nor to the project's output folder. What the plug-in makes of them (a
  picture it composes) is up to it: hand it over as a `result`, or send it back with `contribute.startImage`.
- `presets` — `{"presets": [{"name", "fields", "loras"}]}`: presets for the Preset menu. Each is a
  file in the app's Presets folder, named after the preset. **Name them with your own acronym** (2–4 letters), a
  middle dot and the name — `SMP · Overcast`, `SLR · Match the sun` — because that is the only sign of where a
  preset comes from. A name cannot contain `/` or `:`, start with a dot or be longer than 120 characters (file system rules); capitals and accents do not tell two
  names apart. `fields` has the keys of `contribute` above, the prompt and the negative prompt included; no size. Since DT Hub 0.5.0 an entry may also carry `model` (a file name, such as `flux_2_klein_base_9b_i8x.ckpt`: loading the preset selects that model) and `advanced` (an object with the advanced values to set, such as `{"refinerModel":"…","refinerStart":0.25}`; keys not given stay at their default). A name the menu has already is never touched (the user may have changed it), so register them
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
