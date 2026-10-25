# Panorama 360 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Execution chosen by the user: native** (superpowers:executing-plans, in this session, one final independent review of the branch).

**Goal:** A DT Hub plug-in «Panorama 360» where the user places images («stickers») on a 360° equirectangular canvas and sends it as the start image to FLUX.2 [klein] Base + the «360 ERP outpaint» LoRA, plus the two contract additions it needs.

**Architecture:** Pure-math `PSProjection` and a Codable `PanoState` feed a renderer (Metal, with an identical-interface CPU renderer as test oracle and automatic fallback) that returns a `CGImage`; the canvas shows that image with a SwiftUI overlay (outline, handles) and routes pointer events through pure functions in `PSInteraction`. `PSSender` renders the 2048×1024 ERP and sends one `contribute` naming a saved preset. The app gains `presets[].model/advanced` and `contribute.preset`.

**Tech Stack:** Swift 6.2, macOS 26, SwiftUI + AppKit, Metal (runtime-compiled shader string), Swift Testing, `DTHubPluginKit`/`DTHubDesign` (module-aliased copies like every plug-in).

**Spec:** `docs/superpowers/specs/2026-10-25-plugin-panorama-360-design.md` (mockup `docs/superpowers/mockups/2026-10-25-panorama-360.html`).

## Global Constraints

- ERP is **2048 × 1024**, background `#00ff00` (RGB 0,255,0), 360° only; no other size, colour, mask or zoom.
- Families `["flux2_9b","flux2_4b"]`; plug-in id `com.exiztenz.dthub.panorama360`, name «Panorama 360», symbol `globe`, version `1.0`; entry class `Panorama360Entry`.
- Preset names (fixed, English): `PAN · 360 ERP` (Normal) and `PAN · 360 ERP Fast`; UI words «Normale/Veloce» (it), «Normal/Fast» (en).
- **The LoRA trigger phrase is never written into the prompt.** `fields.prompt` is only the user's description. Trigger = `fill the green spaces according to the image. outpaint as a seamless 360 equirectangular panorama (2:1). keep the horizon level. match left and right edges.` in the LoRA's `trigger` field of the preset.
- Preset values (from the user's saved `PAN · 360 ERP 9B`): model `flux_2_klein_base_9b_i8x.ckpt`, steps 16, guidanceScale 4, sampler 16, shift 3, resolutionDependentShift true, LoRA file `f2_360_erp_outpaint_lora_v1_lora_f16.ckpt` weight 1; Fast adds `advanced.refinerModel = flux_2_klein_9b_kv_i8x.ckpt`, `advanced.refinerStart = 0.25`.
- Contract additions are optional and backward compatible: `presets[]` entries accept `model` (string) and `advanced` (object, decoded leniently into `AdvancedParameters`); `contribute.preset` (string) applies the saved preset before `fields`, `startImage` and `strength` of the same message. The plug-in still never changes the model by itself.
- Sticker model: FOV 5…170°, pitch ±89°, yaw wrapped to −180…180°, opacity 0…1; array order = z order (last on top); vertical FOV derived, never stored. The horizontal axis is periodic and every projection function takes `uOffset` (0 now).
- Text fields read the state, never a stale copy (rule of the plug-in text fields); every new text has Italian and English in `L`; no captions in the UI beyond the mockup.
- No merge or push without the user's explicit word; add files by name (never `git add -A`); commits end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Commands: plug-in tests `cd Plugins/Panorama360 && swift test 2>&1 | grep -E "Test run with|error:"`; app logic `cd Packages && swift test 2>&1 | grep -E "Test run with|✘|error:"`; app build `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build`.
- Branch `feat/panorama-360` (already created from `main`).

## Review Focus

1. A sticker straddling the seam (yaw ±180°) draws continuously, can be picked on both sides and its outline does not draw a line across the canvas.
2. A phone photo with an EXIF rotation, a PNG with transparency, a huge image (e.g. 12 000 px) and an unreadable or empty file dropped on the canvas: upright, composited by alpha, downscaled to 2048 px on the long side, and a notice without a crash.
3. Before the app says which project is open (no `project` message yet) nothing is written and nothing crashes; switching project swaps the whole state and images.
4. A `state.json` that is corrupt or of a newer `version` starts empty and keeps the file as `state.json.bak`.
5. `contribute.preset` naming a missing preset, or sent while a pipeline runs, only returns `problems` (shown in the error box); the rest of the message is still applied or refused as the app already does for other keys.

---

### Task 0: Plug-in skeleton and Metal probe

**Files:**
- Create: `Plugins/Panorama360/Package.swift` (copy of `Plugins/Flux3Editing/Package.swift`, names `Panorama360`, aliases `Panorama360Kit`/`Panorama360Design`, test target `Panorama360Tests`)
- Create: `Plugins/Panorama360/Sources/Panorama360/Panorama360Plugin.swift` (manifest per Global Constraints, empty `NSHostingController` view, entry class)
- Create: `Plugins/Panorama360/Sources/Panorama360/PSMetalProbe.swift`
- Create: `Plugins/Panorama360/Scripts/build.sh` (copy of Flux3Editing's, ids and names changed, `VERSION="1.0"`)
- Test: `Plugins/Panorama360/Tests/Panorama360Tests/MetalProbeTests.swift`

**Interfaces:**
- Produces: `enum PSMetalProbe { static func canCompileAndRun() -> Bool }` — compiles a trivial fragment+vertex shader from a Swift string with `MTLDevice.makeLibrary(source:options:)`, draws one triangle into a 4×4 `.rgba8Unorm` texture and reads back a pixel.

- [ ] **Step 1: Write the failing test** `@Test func shaderCompiledFromAStringRunsAndReadsBack()` asserting `PSMetalProbe.canCompileAndRun() == true`.
- [ ] **Step 2: Run** `swift test --filter MetalProbeTests` — expect FAIL (no such type).
- [ ] **Step 3: Implement** the package files above and `PSMetalProbe` (device via `MTLCreateSystemDefaultDevice()`, offscreen render pass, `getBytes` readback; returns false instead of throwing).
- [ ] **Step 4: Run** the test — expect PASS. Then `Plugins/Panorama360/Scripts/build.sh "$TMPDIR/p360"` and check `file -b "$TMPDIR/p360/Panorama360.dthubplugin/Contents/MacOS/Panorama360"` says «shared library» and `codesign --verify --deep --strict` passes.
- [ ] **Step 5: Commit** `git add Plugins/Panorama360/Package.swift Plugins/Panorama360/Sources Plugins/Panorama360/Scripts Plugins/Panorama360/Tests` — `feat(panorama-360): plug-in skeleton and Metal probe`.

*Note:* whether the shader also compiles inside the signed DT Hub process is proved at the first hand test; `PSRenderer.make()` (Task 4) falls back to the CPU renderer on any failure, so this does not block.

### Task 1: Contract additions (app and kit)

**Files:**
- Modify: `Packages/Sources/HubKit/Plugin/PluginPresets.swift` (read `model`, `advanced`)
- Modify: `Packages/Sources/HubKit/Plugin/PluginContribution.swift` (`preset`, `isEmpty`, `init(message:)`)
- Modify: `Packages/Sources/HubCore/Plugins/ContributionStore.swift` (`ContributionTarget.applyPreset`, `receive`)
- Modify: `App/Generation/GenerationController.swift` (conformance; keep a weak `DrawThingsConnection`) and `App/DTHubApp.swift:63` (pass the connection to `attach`)
- Modify: `PluginKit/README.md` (the two additions, «needs DT Hub ≥ next release»), `PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift` (doc comments of `registerPresets` and `contribute`)
- Test: `Packages/Tests/HubCoreTests/PluginPresetsTests.swift`, `Packages/Tests/HubKitTests/ContributionContractTests.swift`, `Packages/Tests/HubCoreTests/ContributionStoreTests.swift` (extend `FakeContributionTarget`)

**Interfaces:**
- Produces: `PluginContribution.preset: String?` (trimmed, empty = nil); `ContributionTarget.applyPreset(named: String) -> String?` (nil = applied, else the reason); `PluginPresets` entries now yield `Preset` with `model` and `parameters.advanced` set.

- [ ] **Step 1: Write failing tests.**
  - `presetsCarryModelAndAdvanced`: a `presets` message with `"model":"m.ckpt"` and `"advanced":{"refinerModel":"r.ckpt","refinerStart":0.25}` gives `preset.model == "m.ckpt"`, `preset.parameters.advanced.refinerModel == "r.ckpt"`, `refinerStart == 0.25`; an entry without them keeps `model == ""` and default advanced; a non-object `advanced` is ignored.
  - `contributePresetIsParsed`: `{"preset":" PAN · 360 ERP "}` → `preset == "PAN · 360 ERP"`; `{"preset":""}` → nil; a message with only `preset` is not `isEmpty`.
  - `storeAppliesThePresetBeforeTheFields`: `FakeContributionTarget.applyPreset` records order; message with `preset` and `fields.prompt` → order `["preset","fields"]`; fields the preset changed are marked teal for that plug-in (`marks[.steps]`), a missing preset returns `problems == ["preset: <reason>"]` and the fields of the message still apply; with `pipelineLocked = true` → `problems == ["preset: a pipeline is running."]` and `applyPreset` is not called.
- [ ] **Step 2: Run** `cd Packages && swift test --filter "PluginPresetsTests|ContributionContractTests|ContributionStoreTests"` — expect FAIL.
- [ ] **Step 3: Implement.** `PluginPresets`: `Preset.model` from the string, `parameters.advanced` by decoding the `advanced` object (re-encode `JSONValue` → `AdvancedParameters`, which is lenient), then `.clamped()`. `PluginContribution`: new stored property and parse. `ContributionStore.receive`: before the fields loop, if `contribution.preset` is set → guard `pipelineLocked` → snapshot `target.fields`, call `target.applyPreset`, then for every `ContributionField` whose value changed set `marks[field] = FieldMark(pluginID:, value:, isOverridden: false)` (no conflict, last writer wins). `GenerationController.applyPreset(named:)` → `loadPreset(named:with:)` using the stored connection; map `PresetError` to a short text.
- [ ] **Step 4: Run** the three suites then the whole `Packages` suite — expect PASS; run the `xcodebuild … build` — expect BUILD SUCCEEDED.
- [ ] **Step 5: Docs** in the two files above; run `cd PluginKit && swift test` (kit tests stay green).
- [ ] **Step 6: Commit** the listed files by name — `feat(contract): presets with model and advanced; contribute.preset`.

### Task 2: Data model and state per project

**Files:**
- Create: `Sources/Panorama360/PSModels.swift`, `Sources/Panorama360/PSState.swift`
- Test: `Tests/Panorama360Tests/PSModelsTests.swift`, `Tests/Panorama360Tests/PSStateTests.swift`

**Interfaces:**
- Produces: `struct Sticker: Codable, Equatable, Identifiable { id: UUID; name: String; file: String; yaw, pitch, rot, hfov, opacity: Double; visible: Bool }`; `enum PanoMode: String, Codable { case normal, fast }`; `struct PanoState: Codable, Equatable { version = 1; stickers: [Sticker]; selectedID: UUID?; description: String; mode: PanoMode; guides: Bool }` with `static func load(from folder: URL) -> PanoState` (corrupt/newer → empty and rename to `state.json.bak`) and `func save(to folder: URL) throws`; `@MainActor final class PSState: ObservableObject` with `@Published var doc: PanoState`, `projectFolder: URL?`, `switchProject(folder:)`, `apply(context: Data)` (stores `model`, `tempFolder`, `family`), `var modelIsBase: Bool?` (nil = no model; true when the file name contains `base`), and `mutate(_ change: (inout PanoState) -> Void)` which saves when a project is open.

- [ ] **Step 1: Write failing tests.** `roundTripKeepsEverythingInOrder`; `corruptFileStartsEmptyAndKeepsBackup`; `newerVersionIsTreatedAsCorrupt`; `nothingIsWrittenBeforeAProjectIsOpen` (mutate with `projectFolder == nil`, no file anywhere); `switchingProjectSwapsTheDocument`; `modelIsBaseReadsTheFileName` («flux_2_klein_base_9b_i8x.ckpt» true, «flux_2_klein_9b_q8p.ckpt» false, no model nil).
- [ ] **Step 2: Run** `swift test --filter "PSModelsTests|PSStateTests"` — expect FAIL.
- [ ] **Step 3: Implement** as above; JSON with `JSONEncoder` sorted keys; sticker images live in `<folder>/stickers/` (referenced by relative `file`).
- [ ] **Step 4: Run** — expect PASS.
- [ ] **Step 5: Commit** — `feat(panorama-360): data model and per-project state`.

### Task 3: Projection and interaction math

**Files:**
- Create: `Sources/Panorama360/PSProjection.swift`, `Sources/Panorama360/PSInteraction.swift`
- Test: `Tests/Panorama360Tests/PSProjectionTests.swift`, `Tests/Panorama360Tests/PSInteractionTests.swift`

**Interfaces:**
- Produces: `struct Vec3 { x, y, z: Double }`; `struct StickerBasis { forward, right, up: Vec3; tanX, tanY: Double }`; `enum PSProjection` with `direction(u:v:uOffset:) -> Vec3`, `point(of:uOffset:) -> (u: Double, v: Double)` (u, v in 0…1), `basis(for: Sticker, aspect: Double) -> StickerBasis` (aspect = width/height of the image), `planeCoords(_ d: Vec3, in: StickerBasis) -> (s: Double, t: Double)?` (0…1 inside, nil outside or behind), `verticalFOV(hfov: Double, aspect: Double) -> Double`, `wrapYaw(_:) -> Double`, `hitTest(u:v:stickers:[(Sticker, aspect)], uOffset:) -> UUID?` (top z first, visible only), `outline(of: Sticker, aspect:, samplesPerEdge: 28, uOffset:) -> [[(u: Double, v: Double)]]` (polylines split where the seam is crossed), `handles(of:aspect:) -> (center, corners: [4], rotate)` in (u,v).
  `enum PSInteraction` with `grab(sticker:at:) -> Grab`, `moved(_:to:grab:) -> Sticker`, `scaled(_:startFOV:startDistance:distance:) -> Sticker`, `rotated(_:startRot:startAngle:angle:snap:) -> Sticker` (all (u,v)-based, clamped per Global Constraints).

- [ ] **Step 1: Write failing tests** (exact numbers): `centerOfAStickerMapsToItsYawPitch` (sticker yaw 0, pitch 0 → `point(of: basis.forward)` = (0.5, 0.5); yaw 90 → u = 0.75; pitch 45 → v = 0.25); `erpRoundTrip` (direction(u,v) → point == (u,v) within 1e-9, also with `uOffset 0.5`); `yawWrapsAt180` (`wrapYaw(190) == -170`, `wrapYaw(-180)` is ±180 and equal to `wrapYaw(180)` modulo sign); `verticalFOVFollowsTheAspect` (hfov 90, aspect 1.5 → 2·atan(tan45°/1.5) in degrees); `planeCoordsInsideAndOutside` (centre → (0.5, 0.5); a direction 80° off a 60° sticker → nil; a direction behind → nil); `hitTestPicksTheTopmostVisible` (two overlapping stickers: the later in the array wins; hidden one never); `straddlingStickerIsPickedOnBothSidesOfTheSeam` (yaw 180: points at u=0.01 and u=0.99 both hit); `outlineIsSplitAtTheSeam` (yaw 180 → at least two polylines and no segment longer than 0.5 in u); `moveKeepsTheGrabOffset` (grab at an offset, move pointer by +10° in lon → yaw +10°, not recentred); `moveCrossingTheSeamWraps`; `scaleIsRatioOfDistancesAndClamped` (×2 distance → 2× FOV, result clamped 5…170); `rotateSnapsTo45WithShift`; `pitchClampedTo89`.
- [ ] **Step 2: Run** `swift test --filter "PSProjectionTests|PSInteractionTests"` — expect FAIL.
- [ ] **Step 3: Implement** with the formulas of spec §3.2 (`forward = (sin y·cos p, sin p, cos y·cos p)`, `right = (cos y, 0, −sin y)`, `up = forward × right`, then rotation `rot` of `right/up` in their plane; `tanX = tan(hfov/2)`, `tanY = tanX / aspect`; plane coords `s = (d·right/dz)/tanX·0.5+0.5`, `t = 0.5 − (d·up/dz)/tanY·0.5`, nil when `dz ≤ 1e-5`).
- [ ] **Step 4: Run** — expect PASS.
- [ ] **Step 5: Commit** — `feat(panorama-360): projection and interaction math`.

### Task 4: Renderers (Metal and CPU)

**Files:**
- Create: `Sources/Panorama360/PSRenderer.swift` (protocol, `PSLayer`, `PSCPURenderer`, `PSRendererFactory`), `Sources/Panorama360/PSMetalRenderer.swift` (shader string and pipeline)
- Test: `Tests/Panorama360Tests/PSRendererTests.swift`

**Interfaces:**
- Consumes: `PSProjection.basis`, `StickerBasis`, `Sticker`.
- Produces: `struct PSLayer { image: CGImage; basis: StickerBasis; opacity: Double }`; `protocol PSRendering { func render(_ layers: [PSLayer], width: Int, height: Int, uOffset: Double) throws -> CGImage }` (layers in z order, first = bottom; result is opaque, background 0,255,0); `final class PSCPURenderer: PSRendering` (multithreaded rows, bilinear, premultiplied alpha); `final class PSMetalRenderer: PSRendering` (texture cache keyed by `ObjectIdentifier` of the `CGImage`); `enum PSRendererFactory { static func make() -> any PSRendering }` (Metal if `PSMetalProbe.canCompileAndRun()` and pipeline creation succeeds, else CPU).

- [ ] **Step 1: Write failing tests** with synthetic images from a helper `TestImages.solid(w,h,rgba)`: `emptySceneIsPureGreen` (both renderers, every pixel 0,255,0); `aCentredStickerFillsItsPlaceAndNothingElse` (red sticker 90° at yaw 0: the pixel at (W/2,H/2) is red, (10,10) is green); `opacityBlends` (opacity 0.5 red over green → ≈ (128,128,0) ±2); `alphaIsComposited` (a sticker whose image is half transparent shows green through); `zOrderLastOnTop`; `seamStickerIsContinuous` (yaw 180: pixels at x=0 and x=W−1 on the equator are both the sticker colour); `metalMatchesCPU` (random three-sticker scene at 512×256: mean absolute channel difference < 2/255 and no pixel differing by more than 12); `uOffsetShiftsTheImage` (offset 0.5 puts a yaw-0 sticker at x ≈ 0 and W).
- [ ] **Step 2: Run** `swift test --filter PSRendererTests` — expect FAIL.
- [ ] **Step 3: Implement.** CPU: per pixel ray → per layer `planeCoords` → bilinear sample (clamp) → `out = rgb·a + out·(1−a)` with `a = alpha·opacity`. Metal: one pass, a fullscreen triangle, fragment shader loops over up to 32 layers (arrays of basis vectors and `tanX/tanY/opacity` in a constant buffer; textures in an argument array or a texture2d_array with equal slices — the implementer picks), same maths in MSL, output `.rgba8Unorm`, readback to `CGImage` (sRGB). More than 32 visible stickers: the factory's renderer splits into passes by feeding the previous result as the first layer's background texture, or documents the cap and the UI refuses the 33rd sticker — **decision: cap at 32 stickers in `PSState` and in the UI** (add a test `thirtyThirdStickerIsRefused` in Task 6).
- [ ] **Step 4: Run** — expect PASS (the Metal tests return early when there is no Metal device).
- [ ] **Step 5: Commit** — `feat(panorama-360): Metal and CPU renderers`.

### Task 5: Canvas view and interactions

**Files:**
- Create: `Sources/Panorama360/PSCanvasView.swift` (image + SwiftUI `Canvas` overlay: guides, outlines, handles, drop highlight), `Sources/Panorama360/PSView.swift` (the tab: canvas card first), `Sources/Panorama360/PSImages.swift` (`PSImageCache`: sticker `CGImage` by id, loaded from the project folder)
- Modify: `Sources/Panorama360/PSState.swift` (selection, `render(scale:)`, key commands)
- Test: `Tests/Panorama360Tests/PSCanvasTests.swift`, `Tests/Panorama360Tests/RenderTests.swift`

**Interfaces:**
- Consumes: `PSProjection`, `PSInteraction`, `PSRendererFactory.make()`, `PSState`.
- Produces: `PSState.renderedERP(width: Int, height: Int) throws -> CGImage` (visible stickers, array order); `PSState.pointerDown(at:)`, `pointerDragged(to:shift:)`, `pointerUp()` (u,v in 0…1: handle hit → rotate or scale; else pick → move; selection set); `PSState.nudge(yaw:pitch:)`, `deleteSelected()`, `duplicateSelected()` (yaw + 10°, inserted above), `clearAll()`.

- [ ] **Step 1: Write failing tests** driving `PSState` with test stickers: `dragMovesTheSelectedStickerKeepingTheGrab`; `dragFromACornerScalesTheFOV`; `dragFromTheRotateHandleRotatesAndShiftSnaps`; `clickOnEmptyDoesNotChangeTheSelectionOrTheStickers` (also keeps selection per spec: clicking empty canvas deselects? **decision: keeps the selection**); `arrowsNudgeByOneAndShiftByFive`; `deleteSelectsTheNeighbour`; `duplicateCopiesAndShiftsYawBy10`; `fieldReadsTheCurrentStateEvenWithAStaleCopy` (rule: set `doc.stickers[0].yaw` and read back through the binding helper `state.binding(\.yaw)` with a captured old sticker); `renderedERPIs2048By1024`.
- [ ] **Step 2: Run** `swift test --filter PSCanvasTests` — expect FAIL.
- [ ] **Step 3: Implement.** The canvas renders at half resolution while a drag is active and at full on release (render on a background `Task`, drop stale frames); guides toggled by `doc.guides`; the overlay uses `PSProjection.outline`/`handles` times the view size; look as in the mockup. `RenderTests` writes the tab to PNG when `PANORAMA360_RENDER_DIR` is set (pattern of `TiledUpscale/Tests/.../RenderTests.swift`).
- [ ] **Step 4: Run** — expect PASS; set `PANORAMA360_RENDER_DIR` to a folder and look at the PNG against the mockup.
- [ ] **Step 5: Commit** — `feat(panorama-360): canvas view and interactions`.

### Task 6: Sticker card, drops and project images

**Files:**
- Create: `Sources/Panorama360/PSStickerStore.swift`, `Sources/Panorama360/PSStickerCard.swift`
- Modify: `Sources/Panorama360/PSView.swift`, `PSState.swift`
- Test: `Tests/Panorama360Tests/PSStickerStoreTests.swift`, `Tests/Panorama360Tests/PSStickerCardTests.swift`

**Interfaces:**
- Produces: `PSStickerStore.add(contentsOf url: URL, into folder: URL) throws -> (file: String, size: CGSize)` (copies as PNG into `<folder>/stickers/<uuid>.png`, applies EXIF orientation, downscales to 2048 px on the long side, throws `PSStickerError.unreadable(name)` for empty/unreadable files); `PSState.addStickers(from urls: [URL])` (one sticker per file, cascade from the centre with +10° yaw each, selects the last, collects failures into `notice`), `PSState.moveSticker(id:, before:)` (row drag reorder), `PSState.setVisible(id:, Bool)`; the 32-sticker cap.

- [ ] **Step 1: Write failing tests:** `copiesAsPNGAndKeepsTheRelativeName`; `appliesTheExifOrientation` (a fixture JPEG with orientation 6 comes out portrait); `keepsAlphaOfAPNG`; `downscalesAHugeImage` (4000×3000 → 2048×1536); `emptyFileThrowsUnreadable`; `dropOfThreeFilesMakesThreeCascadingStickers` (yaws differ by 10°); `aBadFileDoesNotStopTheOthers` (notice names it); `thirtyThirdStickerIsRefused`; `reorderMovesARowAfterTheTarget` (matches the mockup: drop = after that row); `deletingAStickerRemovesItsFile`; `fieldsOfTheSelectedStickerClampTheirValues` (FOV 200 → 170, pitch 95 → 89, opacity 2 → 1).
- [ ] **Step 2: Run** `swift test --filter "PSStickerStoreTests|PSStickerCardTests"` — expect FAIL.
- [ ] **Step 3: Implement** the store (ImageIO: `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailWithTransform` and `kCGImageSourceThumbnailMaxPixelSize 2048`) and the card (list with thumbnail, name, z, eye, drag reorder with `draggable`/`dropDestination`; duplicate and delete icon buttons; the six numeric fields — no `Slider`, text fields with `onSubmit`/focus-loss commit); canvas drop `.onDrop(of: [.image, .fileURL, .url])` as in `TUView`.
- [ ] **Step 4: Run** — expect PASS; render PNG check as in Task 5.
- [ ] **Step 5: Commit** — `feat(panorama-360): sticker card, drops and project images`.

### Task 7: Prompt card and «Migliora prompt»

**Files:**
- Create: `Sources/Panorama360/PSPrompt.swift` (master prompt text, request, language check), `Sources/Panorama360/PSPromptCard.swift`
- Create: `Data/master-prompt.md`, `Scripts/make-embedded.py` and `Sources/Panorama360/Embedded/PSEmbedded.swift` (the text embedded as a Swift string, pattern of `Plugins/Flux3Editing/Scripts/make-embedded.py`); `DTHubPromptFolder` installs it to `Data/panorama-360/master-prompt.md` with `custom/` support (pattern: `Plugins/Flux3Editing/Sources/Flux3Editing/EditPrompts.swift`)
- Test: `Tests/Panorama360Tests/PSPromptTests.swift`

**Interfaces:**
- Produces: `struct PSPrompt { static func request(description: String, context: DTHubContext?) -> (prompt: String, system: String) }`; `PSState.improve(using ask: (String, String) async -> String?) async` (sets `doc.description`, remembers the previous text for `undo()`; at most one level); `PSState.undoImprove()`; `static func PSPrompt.looksItalian(_:) -> Bool` (copy the idea of `F3Language.looksItalian`).
- Master prompt rules (text, English): rewrite only the description, keep it English, 30–80 words, light, season, style, lens; **never** write the phrases «fill the green spaces», «outpaint», «360», «equirectangular», «panorama (2:1)», «horizon» or «left and right edges»; answer with the description only.

- [ ] **Step 1: Write failing tests:** `improveReplacesOnlyTheDescription` (fake ask returns text → `doc.description` replaced, stickers untouched); `undoRestoresTheLastTextOnly`; `anItalianAnswerIsRetriedOnceThenKeptOut` (first answer Italian → second request has a reminder; second Italian → description unchanged and `error` set); `theAnswerNeverCarriesTheTriggerPhrase` (answer containing «fill the green spaces» is stripped or rejected → description unchanged); `noModelGivesAReadableError`; `emptyDescriptionIsRefused` (no request sent); `requestIncludesTheDescriptionAndNotTheTrigger`.
- [ ] **Step 2: Run** `swift test --filter PSPromptTests` — expect FAIL.
- [ ] **Step 3: Implement** `PSPromptCard`: multi-line field bound to `state.doc.description` through a getter that reads the state (cursor rule), «Migliora prompt» (text), Annulla (icon, enabled when there is something to undo), word count; the error or warning box and the Normale/Veloce switch and «Invia a Generazione» are added in Task 8.
- [ ] **Step 4: Run** — expect PASS.
- [ ] **Step 5: Commit** — `feat(panorama-360): prompt card and Improve prompt`.

### Task 8: Send, factory presets, errors, plug-in wiring

**Files:**
- Create: `Sources/Panorama360/PSSender.swift`, `Sources/Panorama360/PSPresets.swift`
- Modify: `Sources/Panorama360/Panorama360Plugin.swift` (handle `context`/`project`/`activate`/`deactivate`, `start(host:)` registers presets once), `PSPromptCard.swift` (switch, box, send), `PSState.swift`
- Test: `Tests/Panorama360Tests/PSSenderTests.swift`, `Tests/Panorama360Tests/PSPresetsTests.swift`, `Tests/Panorama360Tests/PluginTests.swift`

**Interfaces:**
- Produces: `enum PSPresets { static let normalName = "PAN · 360 ERP"; static let fastName = "PAN · 360 ERP Fast"; static func messages() -> [[String: Any]] }` (two entries with `name`, `model`, `fields`, `loras`, `advanced` exactly as Global Constraints); `PSSender.body(startImage: URL, description: String, mode: PanoMode) -> [String: Any]` = `["preset": name, "startImage": ["path":…, "name":"panorama-360.png"], "fields": ["prompt": description, "width": 2048, "height": 1024], "strength": 1]` (no `prompt` key when the description is empty after trimming); `PSState.send(contribute:)` renders `renderedERP(2048,1024)`, writes the PNG into `tempFolder`, sends, turns `problems` into `state.error`, and sets `state.warning` when the new `context` model is not base after the send.

- [ ] **Step 1: Write failing tests:** `normalPresetMatchesTheUsersFile` (decode `messages()[0]`: model, steps 16, guidanceScale 4, sampler 16, shift 3, resolutionDependentShift true, the LoRA file/weight/trigger verbatim, no `advanced.refinerModel`); `fastPresetAddsTheRefiner` (`refinerModel`, `refinerStart 0.25`, everything else equal to Normal); `thePromptNeverContainsTheTrigger`; `bodyNamesThePresetForTheMode`; `bodyKeepsTheSizeAt2048x1024AndStrength1`; `emptyDescriptionSendsNoPromptKey`; `problemsFromTheAppBecomeTheErrorBox` (fake contribute returns `problems:["preset: not found"]`); `sendIsRefusedWithoutVisibleStickers`; `warningWhenTheModelIsNotBaseAfterTheContext` (context model `flux_2_klein_9b_q8p.ckpt`); `pluginRegistersThePresetsOnceAtStart` (fake host closure called once with two presets); `pluginIgnoresSendBeforeAProject` (no project → error «Open a project»-style text, nothing written).
- [ ] **Step 2: Run** `swift test --filter "PSSenderTests|PSPresetsTests|PluginTests"` — expect FAIL.
- [ ] **Step 3: Implement.** The box shows `error` first, else `warning`; the switch is a two-segment control bound to `doc.mode`; «Invia a Generazione» disabled with no visible sticker; `Panorama360Plugin.handle` follows `TiledUpscalePlugin.handle` (unknown type → `DTHubMessage.bare("unsupported")`).
- [ ] **Step 4: Run** — expect PASS; render PNG of the whole tab against the mockup (states: ok, error, warning).
- [ ] **Step 5: Commit** — `feat(panorama-360): send, factory presets and errors`.

### Task 9: Texts, README, bundle and hand-test list

**Files:**
- Create: `Sources/Panorama360/Strings.swift` (pattern of `TiledUpscale/Sources/TiledUpscale/Strings.swift`), `Plugins/Panorama360/README.md`, `Tests/Panorama360Tests/StringsTests.swift`
- Modify: `Plugins/README.md` (new row, plug-in count), `README.md` (plug-in list and link; screenshot later), `Plugins/Panorama360/Scripts/build.sh` (final)
- Test: `Tests/Panorama360Tests/StringsTests.swift`

- [ ] **Step 1: Write failing test** `everyWordIsInBothLanguages` (loop over `L.Key.allCases`, as in `TiledUpscale`'s `StringsTests`) and `formattedWordsKeepTheirNumbers` for any `%d` text; run `swift test --filter StringsTests` — expect FAIL until `Strings.swift` holds every word used in Tasks 2–8 (replace any inline literal).
- [ ] **Step 2: Implement** `L`, switch all views to it.
- [ ] **Step 3: README** (English): what it does, install (Preferences › Plug-ins › Add…), the workflow, the two presets and how to customise (4B, quantisation, refiner), **LoRA download links** `https://huggingface.co/nomadoor/flux-2-klein-9B-360-erp-outpaint-lora` and `…4B…` with the licence note (9B: FLUX non-commercial licence v2.1; 4B: Apache-2.0 in the metadata, follow the base model's licence), use **Base** models only, 2048×1024 only, credit to nomadoor/ComfyUI-Panorama-Stickers (MIT) and the guide page, requires the DT Hub release that carries the contract additions (number decided at release).
- [ ] **Step 4: Run** the whole plug-in suite, then `Scripts/build.sh "$TMPDIR/p360"` + `file`/`codesign` checks of Task 0; run `cd Packages && swift test` and the `xcodebuild` build once more.
- [ ] **Step 5: Hand-test list for the user** (written to the final message, not to a file): install the new app build and the bundle; Metal renders in the tab (else CPU fallback is used: say which); drop 1 and 3 files from Finder, a browser image and two Results from the gallery; move across the seam; scale; rotate with Shift; reorder rows; save/reopen the project; Send Normal with a 9B Base model + LoRA and RUN; Send Fast; model not Base → warning; remove the LoRA → error box; «Migliora prompt» + Annulla.
- [ ] **Step 6: Commit** — `feat(panorama-360): texts, README and bundle`.

---

## Self-review (done before saving)

- **Spec coverage:** §1 scope → Tasks 2–8; §2 choices → Global Constraints; §3 units → Tasks 2–8 (`PSStickerStore` Task 6, `PSPresets`/`PSSender` Task 8, `PSPrompt` Task 7, `Strings` Task 9); §3.3 Metal risk → Task 0 + fallback in Task 4; §3.4 UI → Tasks 5–8 (+ mockup); §4 send, presets, errors, Improve → Tasks 7–8; §5 contract → Task 1; §6 tests → in each task; §7 phases → same order; §8 delivery → Task 9 and the final message; §9 seam correction → `uOffset` in Tasks 3–4, `version` in Task 2, nothing blocking `session.*` later; §10 risks → Task 0 note, README (licences), fixed size.
- **Not in the spec but decided here:** cap of 32 stickers (shader loop bound); clicking empty canvas keeps the selection; textures downscaled to 2048 px on import.
- **Type consistency:** `Sticker`, `PanoState`, `PanoMode`, `PSState`, `PSLayer`, `PSRendering`, `StickerBasis` are used with the same names in every task; `PSSender.body` and `PSPresets.messages()` match Global Constraints.
- **Proportion:** the plan states interfaces, values and test names; bodies are left to the implementer except the projection formulas the spec already fixes.
