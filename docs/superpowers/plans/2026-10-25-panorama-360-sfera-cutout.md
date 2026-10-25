# Panorama 360 — vista a sfera e Cutout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Execution chosen by the user: native** (superpowers:executing-plans, in this session, one final independent review of the branch).

**Goal:** Add to the Panorama 360 plug-in a spherical viewer (canvas and last result, stickers editable in the canvas view) and the Cutout (extract the view, send it, put the retouched picture back as a sticker or into the result panorama), plus the two contract additions it needs.

**Architecture:** A pure `PSCamera` gives rays and screen projections; the renderer gains `renderView` (rays from the camera onto stickers or onto a panorama) and a panorama `background` with a `feather` for the ERP render, both in Metal with the CPU renderer as oracle and fallback. The card gets a View toggle (Plane | Sphere), a Source toggle (Canvas | Result) and a Cutout panel. The app tells plug-ins the last result (`lastResult` in the context) and accepts `contribute.result` outside guided pipelines.

**Tech Stack:** as the first plan (Swift 6.2, SwiftUI, Metal, Swift Testing, `DTHubPluginKit`/`DTHubDesign`).

**Spec:** `docs/superpowers/specs/2026-10-25-panorama-360-sfera-cutout-design.md` (extends `…-plugin-panorama-360-design.md`; mockup `docs/superpowers/mockups/2026-10-25-panorama-360-sfera.html`).

## Global Constraints

- Everything of the first plan still holds (ERP 2048×1024 on `#00ff00`, the trigger phrase never in the prompt, texts in Italian and English in `L`, fields read the state, no captions, files added by name, commits end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`, no merge or push without the user's word).
- Camera: yaw wrapped to (−180, 180], pitch ±89°, horizontal FOV 20…120°, default `0, 0, 90`. The sphere view is **4:3**, 1024 × 768 internal points; half resolution while dragging.
- Sphere + Result is view only: no handles, no outlines, `+`, trash and keyboard editing off. Plane has no source (it is the Canvas).
- Cutout: always 4:3 of what is seen; `megapixels` 0.25…4 (default 1.0); `w = max(2, round(√(MP·10⁶·4/3)/256))·256`, `h = w·3/4`, exactly 4:3 (1.0 MP → 1280 × 960; 0.25 → 512 × 384; 4 → 2304 × 1728). No frame, no aspect menu.
- «Put back» (sticker or panorama) is enabled only with a cutout in memory, a last result that is different from `resultPathAtExtraction` or equal to `patchPath`, and whose width/height is 4:3 within 2 %.
- The montage goes to Results with `contribute.result` (PNG in `tempFolder`, description «Montaggio · ritaglio rimesso a yaw …° pitch …° FOV …°»), feather 3 % of the patch side; there is no «Montage» source.
- New `state.json` keys are optional with defaults; `version` stays 1; a file from before still loads.
- Contract additions (optional, same release as the earlier two, newer than 0.4.3): `lastResult: {"path","name"}` in the context (absent without results; part of `PluginContextKey` as `lastResultID`); `contribute.result` accepted without a guided pipeline and filed under the model chosen in the header, with no generation time.
- Commands as in the first plan (plug-in tests `swift test --package-path Plugins/Panorama360`, app logic `swift test --package-path Packages`, app build `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build`). Redirect long output; read only `grep -E "error:|✘|Test run with"`.
- Branch `feat/panorama-360` (the same).

## Review Focus

1. A sticker partly or wholly behind the camera, or near the poles: outlines are cut where a point is behind, no line crosses the view, a sticker entirely behind is not drawn or picked.
2. The last result file is moved, deleted, unreadable, or not 2:1: a notice, the view falls back to Canvas, no crash.
3. «Put back» with a retouch of another proportion, with the same result as at the extraction, and after the montage was made (the retouch must still be found through `patchPath`).
4. A `state.json` written before this change loads with the defaults; a project switch brings back that project's view, source, camera and cutout.
5. `contribute.result` with no guided pipeline and no model selected, or with a missing or unreadable file: `problems`, nothing filed, no crash.

---

### Task 1: Contract — `lastResult` and `contribute.result` without a guided pipeline

**Files:**
- Modify: `Packages/Sources/HubKit/Plugin/PluginMessages.swift` (`PluginLastResult`, `PluginContext.lastResult`)
- Modify: `Packages/Sources/HubCore/Plugins/PluginContextKey.swift` (`lastResultID: String?`)
- Modify: `Packages/Sources/HubCore/Plugins/PluginRegistry.swift` (`lastResultPath` closure, in `sendContext`)
- Create: `Packages/Sources/HubCore/Plugins/ResultFiling.swift` (`ResultFiling.model(guided:header:)`)
- Modify: `App/DTHubApp.swift` (`plugins.lastResultPath`), `App/MainWindow/MainWindowView.swift` (`lastResultID` in the key), `App/Generation/GenerationController.swift` (`addResult` uses `ResultFiling.model`)
- Modify: `PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift` (`DTHubLastResult`, `DTHubContext.lastResult`), `PluginKit/README.md`
- Test: `Packages/Tests/HubKitTests/…` (context encode/decode), `Packages/Tests/HubCoreTests/ResultFilingTests.swift`, `PluginContextKey` equality test in `HubCoreTests`, kit test in `PluginKit/Tests`

**Interfaces:**
- Produces: `PluginLastResult { path: String; name: String }`; `PluginContext.lastResult: PluginLastResult?`; `PluginContextKey.lastResultID: String?`; `PluginRegistry.lastResultPath: (@MainActor () -> String?)?`; `enum ResultFiling { static func model(guided: String?, header: String?) -> String? }` (guided wins, else the header's, else nil); kit `DTHubLastResult { path, name }` and `DTHubContext.lastResult`.

- [ ] **Step 1: Write failing tests:** `theContextCarriesTheLastResultOrNothing` (encode with and without `lastResult`: key absent when nil; round trip equal); `aNewLastResultChangesTheContextKey` (two keys differing only in `lastResultID` are not equal; same id equal); `theModelOfTheFilingIsTheGuidedOneThenTheHeaders` (`("g","h") → "g"`, `(nil,"h") → "h"`, `(nil,nil) → nil`, `("", "h") → "h"`); kit `theLastResultIsReadByTheKit` (JSON with `lastResult` decodes; absent → nil; malformed → nil and the rest of the context still decodes).
- [ ] **Step 2: Run** `swift test --package-path Packages --filter "ResultFilingTests|PluginContext"` and the kit suite — expect FAIL (no such members).
- [ ] **Step 3: Implement** the members above. `sendContext` fills `lastResult` from `lastResultPath?()` (name = file name). `DTHubApp`: `plugins.lastResultPath = { generation.session.results.first?.fileURL?.path }`; `MainWindowView.contextKey` adds `generation.session.results.first?.id.uuidString`. `GenerationController.addResult`: `guard let model = ResultFiling.model(guided: guidedModelFile, header: presetConnection?.selection.selectedFile) else { throw ControlError.unreadable(image.name) }`; elapsed stays nil without a guided session.
- [ ] **Step 4: Docs** in `PluginKit/README.md` (the context key and the relaxed `result`, «needs the DT Hub release after 0.4.3»). Run the `Packages` suite, the kit suite and the `xcodebuild` build — expect PASS / BUILD SUCCEEDED.
- [ ] **Step 5: Commit** the listed files by name — `feat(contract): lastResult in the context; contribute.result outside guided pipelines`.

### Task 2: Camera and the new state

**Files:**
- Modify: `Plugins/Panorama360/Sources/Panorama360/PSProjection.swift` (add `PSCamera`), `PSModels.swift` (`PSViewMode`, `PSSource`, `PSCutoutMemory`, new `PanoState` fields, custom `init(from:)`)
- Test: `Tests/Panorama360Tests/PSCameraTests.swift`, `PSModelsTests.swift`

**Interfaces:**
- Produces: `struct PSCamera: Codable, Equatable { var yaw = 0.0, pitch = 0.0, fov = 90.0; static let fovRange: ClosedRange<Double> = 20...120; mutating func clamp(); var basis: (forward: Vec3, right: Vec3, up: Vec3, tanX: Double); func ray(x: Double, y: Double, width: Double, height: Double) -> Vec3; func screenPoint(of d: Vec3, width: Double, height: Double) -> CGPoint?; mutating func look(dx: Double, dy: Double, width: Double); mutating func zoom(by delta: Double) }`; `enum PSViewMode: String, Codable { case plane, sphere }`; `enum PSSource: String, Codable { case canvas, result }`; `struct PSCutoutMemory: Codable, Equatable { yaw, pitch, fov: Double; width, height: Int; resultPathAtExtraction: String?; patchPath: String? }`; `PanoState` gains `viewMode`, `source`, `camera`, `cutoutMegapixels` (1.0), `lastCutout: PSCutoutMemory?`.

- [ ] **Step 1: Write failing tests:** `theCentreRayLooksAlongTheCamera`; `rayAndScreenPointAreInverse` (a grid of pixels, view 1024 × 768, FOV 60 and 120, camera at yaw 40 pitch −20); `aDirectionBehindTheCameraHasNoScreenPoint` (and one at 90° off with FOV 60 falls outside 0…w); `lookingDragsTheSceneTheOtherWay` (`look(dx: 10 pixels…)` lowers yaw, `dy` raises pitch; pitch ±89, yaw wrapped); `zoomClampsTheFOV` (20…120); `aFileFromBeforeLoadsWithTheDefaults` (the JSON of the first plan's tests, with no new keys → `viewMode .plane`, `source .canvas`, `camera` default, `lastCutout nil`, `cutoutMegapixels 1`); `theNewFieldsRoundTrip`; `unknownKeysAreIgnoredAndAMalformedNewFieldFallsBack` (e.g. `"camera": 3` → default camera, rest intact).
- [ ] **Step 2: Run** `swift test --package-path Plugins/Panorama360 --filter "PSCameraTests|PSModelsTests"` — expect FAIL.
- [ ] **Step 3: Implement** `PSCamera` with the formulas of the spec §3.1 (`ray` normalized; `screenPoint` nil when `dz ≤ 1e-4`), and the new fields. `PanoState.init(from:)`: old fields with their defaults when missing; new ones with `try?` so a malformed value falls back.
- [ ] **Step 4: Run** — expect PASS; run the whole plug-in suite.
- [ ] **Step 5: Commit** — `feat(panorama-360): camera and the state of the sphere view`.

### Task 3: Renderer — `renderView`, panorama background, feather

**Files:**
- Modify: `Sources/Panorama360/PSRenderer.swift` (protocol, `PSViewSource`, `PSLayer.feather`, CPU renderer), `PSMetalRenderer.swift` (shaders and passes)
- Test: `Tests/Panorama360Tests/PSRendererTests.swift`

**Interfaces:**
- Produces: `enum PSViewSource { case layers([PSLayer]); case panorama(CGImage) }`; `PSLayer.feather: Double` (default 0; fraction of the side, 0…0.5); `PSRendering.renderView(_ source: PSViewSource, camera: PSCamera, width: Int, height: Int) throws -> CGImage`; `PSRendering.render(_ layers:, width:, height:, uOffset:, background: CGImage?)` (the old signature stays as an extension calling it with `nil`).
- Consumes: `PSCamera.ray`, `PSProjection.planeCoords`, `PSProjection.point(of:)`.

- [ ] **Step 1: Write failing tests** (both renderers via `renderers()`): `aViewOfNothingIsPureGreen`; `theViewLooksWhereTheCameraLooks` (red sticker at yaw 0 and blue at yaw 90; camera yaw 0 sees red at the centre pixel, camera yaw 90 sees blue; camera yaw 180 sees green); `aStickerOnTheSeamIsWholeInTheView` (yaw 180 sticker, camera yaw 180: centre colour, no gap); `aPanoramaIsSampledByDirection` (an ERP with a red quarter and a blue quarter: camera at yaw 0 sees the colour at u = 0.5; yaw 90 the one at u = 0.75; looking up sees the top row colour; longitude wraps, latitude is held at the edges); `aBackgroundReplacesTheGreen` (render with a 64×32 solid ERP background and no layers → that colour everywhere; with a layer, layer over background); `featherSoftensTheEdgeOfALayer` (feather 0.2: alpha 0 at the very edge, 1 at the centre, monotonic between); `metalMatchesTheCPUOnViews` (random three-sticker scene and a panorama, 256 × 192 view, mean difference < 2, worst ≤ 12); `theViewBeatsTheERPForDetail` (a sticker with a 1-pixel black line, camera FOV 30: the line is crisp in `renderView` — document that this is why layers are not resampled from the ERP).
- [ ] **Step 2: Run** `--filter PSRendererTests` — expect FAIL (compile).
- [ ] **Step 3: Implement.** CPU: refactor the per-pixel layer composition into a helper shared by `render` and `renderView`; panorama sampling bilinear, `u` wrapped, `v` clamped. Metal: a second vertex/fragment pair `viewVertex`/`viewFragment` taking the camera basis in the uniforms (layers) and `panoViewFragment` (panorama, sampler `address::repeat` on s, `clamp_to_edge` on t); `background` drawn first with `bgFragment` (same maths as the panorama sampler with `uOffset`); `feather` as a smoothstep of `min(s, 1−s, t, 1−t)` in the layer fragment. Keep one pass per layer; the texture cache keeps only the pictures just drawn (the fix of the first plan).
- [ ] **Step 4: Run** — expect PASS; run the whole suite.
- [ ] **Step 5: Commit** — `feat(panorama-360): view renderer, panorama background and feather`.

### Task 4: Pointer and overlay in the sphere

**Files:**
- Create: `Sources/Panorama360/PSSphere.swift` (pure projection of outlines and handles for a camera), `Sources/Panorama360/PSStateSphere.swift` (pointer API of the sphere)
- Modify: `Sources/Panorama360/PSStateEditing.swift` (selection helper shared with the plane)
- Test: `Tests/Panorama360Tests/PSSphereTests.swift`

**Interfaces:**
- Produces: `enum PSSphere { static func outline(of: Sticker, aspect: Double, camera: PSCamera, size: CGSize) -> [[CGPoint]]` (points in view points; polylines cut where a point is behind the camera or far outside the view); `static func handles(of: Sticker, aspect: Double, camera: PSCamera, size: CGSize) -> (center: CGPoint?, corners: [CGPoint?], rotate: CGPoint?)`; `static func hit(at: CGPoint, stickers: [(sticker: Sticker, aspect: Double)], camera: PSCamera, size: CGSize) -> UUID?` }`. `PSState`: `func spherePointerDown(at: CGPoint, size: CGSize)`, `func spherePointerDragged(to: CGPoint, size: CGSize, shift: Bool)`, `func spherePointerUp()`, `func sphereZoom(by: Double)`, `func resetCamera()`; `PSDrag` gains `.look(camera: PSCamera, from: CGPoint)`.
- Consumes: `PSCamera`, `PSInteraction.grab/moved/scaled/rotated`, `PSProjection.point(of:)`, `PSProjection.hitTest`.

- [ ] **Step 1: Write failing tests:** `theOutlineOfAStickerInFrontIsOneClosedLine`; `aStickerHalfBehindTheCameraIsCutAndNoSegmentCrossesTheView` (camera looking 70° away: no consecutive points farther apart than half the view); `aStickerEntirelyBehindHasNoOutlineAndIsNotHit`; `theHandlesAreWhereTheCornersProject`; `aClickOnAStickerSelectsTheTopmostOne` (two overlapping, camera at 0); `dragMovesTheStickerWithTheGrabOffset` (pointer 80 points to the right → yaw changes by `80 · FOV / 1024`·… (compute from the camera: the direction under the pointer before and after, longitude difference)); `dragFromACornerScalesByTheRatioOfScreenDistances`; `dragFromTheRotateHandleRotatesAndShiftSnaps`; `draggingTheEmptyViewLooksAround` (camera changes, stickers do not; selection kept); `inResultNothingIsEditable` (`source .result`: pointer down on a sticker position changes nothing, no selection change, but the camera still looks around); `zoomAndResetWork`.
- [ ] **Step 2: Run** `--filter PSSphereTests` — expect FAIL.
- [ ] **Step 3: Implement.** Pointer → `camera.ray` → `PSProjection.point(of:)` gives `(u, v)`; move reuses `PSInteraction.grab/moved`. Scale and rotate measure in view points around the projected centre (no seam handling needed). `look(dx:dy:width:)` per `PSCamera`. All writes go through `mutate` so they are saved.
- [ ] **Step 4: Run** — expect PASS; whole suite.
- [ ] **Step 5: Commit** — `feat(panorama-360): pointer and overlay in the sphere view`.

### Task 5: The card — View, Source, sphere area

**Files:**
- Create: `Sources/Panorama360/PSSphereView.swift` (image + overlay + gestures + wheel/pinch), `Sources/Panorama360/PSResultImage.swift` (loads and caches the last result)
- Modify: `PSView.swift` (View toggle first, Source toggle in Sphere, 4:3 area, crosshair button), `PSCanvasView.swift` (renders only the Plane), `PSState.swift` and `PSStateEditing.swift` (`lastResultPath` from the context, `resultImage`, `refreshPreview` for both views), `Strings.swift`
- Test: `Tests/Panorama360Tests/PSSourceTests.swift`, `RenderTests.swift`

**Interfaces:**
- Produces: `PSState.lastResultPath: String?` (set by `apply(context:)` from `lastResult.path`); `PSState.resultImage: CGImage?` (loaded from `lastResultPath`, nil when it cannot be read); `PSState.effectiveSource: PSSource` (`.result` only when `resultImage != nil`); `PSState.resultNotice: String?`; `PSState.setView(_:)`, `setSource(_:)`.

- [ ] **Step 1: Write failing tests:** `theContextBringsTheLastResult` (apply a context JSON with and without `lastResult`); `withoutAResultTheSourceFallsBackToTheCanvas`; `aMissingOrUnreadableResultFileGivesANoticeAndTheCanvas`; `aNon2To1ResultIsShownWithANotice`; `aNewResultReplacesTheOneShown` (change the path in a context → `resultImage` is the new picture); `viewAndSourceArePerProject` (switch project → each project's own values); `theSphereAreaIs4To3` (the layout constant `PSSphereView.aspect == 4.0 / 3.0`); `renderedPreviewExistsForEachView` (state in Sphere with a sticker → `refreshPreview` produces an image of the sphere size; in Plane a 1024 × 512 one); `theLabelsAreInBothLanguages` (strings test already covers every key).
- [ ] **Step 2: Run** `--filter PSSourceTests` — expect FAIL.
- [ ] **Step 3: Implement** the UI of the mockup: the View segmented control first, then in Sphere the Source segmented control (Result disabled without a result), the crosshair button, the badge `yaw · pitch · FOV`, the empty-result placeholder. In Sphere + Result hide `+`/trash and the keyboard handlers. `refreshPreview` picks `render` (Plane) or `renderView` (Sphere, `.layers` for Canvas, `.panorama(resultImage)` for Result). Persist view, source and camera through `mutate`.
- [ ] **Step 4: Run** — expect PASS; render the tab to PNG (`PANORAMA360_RENDER_DIR`) in both views and look at it against the mockup.
- [ ] **Step 5: Commit** — `feat(panorama-360): sphere view in the card`.

### Task 6: Cutout

**Files:**
- Create: `Sources/Panorama360/PSCutout.swift` (sizes, extraction, memory), `Sources/Panorama360/PSCutoutActions.swift` (the five actions), `Sources/Panorama360/PSCutoutPanel.swift` (UI)
- Modify: `PSView.swift` (panel under the sphere), `Panorama360Plugin.swift` (glue), `Strings.swift`
- Test: `Tests/Panorama360Tests/PSCutoutTests.swift`

**Interfaces:**
- Produces: `enum PSCutout { static func size(megapixels: Double) -> (width: Int, height: Int); static func canPutBack(memory: PSCutoutMemory?, lastResult: URL?, size: (Int, Int)?) -> PutBackReason? }` (nil = allowed; reasons: no cutout, same result, wrong proportion); `PSState.extractCutout() throws -> CGImage` (renders the current view at `size(megapixels:)` with the sphere's source and stores `lastCutout` with `resultPathAtExtraction = lastResultPath`); `PSCutoutActions.startImageBody(file:)`, `.moodboardBody(file:)` (`[String: Any]` for `contribute`); `PSState.putBackAsSticker()`; `PSState.putBackInPanorama(contribute:) async`.
- Consumes: Task 3 (`render` with `background` and `feather`, `renderView`), Task 5 (`resultImage`, `lastResultPath`), `PSStickerStore`.

- [ ] **Step 1: Write failing tests:** `theCutoutSizeIsFourByThreeInMultiplesOf64` (1.0 MP → 1152 × 896; 0.25 → 576 × 448; 4 → 2304 × 1728; both sides multiples of 64, ratio within 6 %); `extractRendersTheViewAtThatSizeAndRemembersThePose`; `theExtractionOfTheResultSamplesThePanorama`; `startImageAndMoodboardBodiesNameThePng` (`startImage.path/name`, `moodboard` list); `putBackIsOffWithoutACutoutOrWithTheSameResult`; `putBackIsOffForAnotherProportion` (a 2:1 last result → `wrongProportion`; 4:3 ±2 % → allowed); `putBackStaysAvailableAfterTheMontageThroughThePatchPath`; `putBackAsStickerPlacesThePatchAtThePoseOfTheExtraction` (sticker `yaw/pitch/hfov` equal to the memory's, `rot 0`, selected; the view goes to Plane + Canvas; the file is a copy in the project); `putBackInThePanoramaComposesAndFilesTheMontage` (fake `contribute` captures `result.path/name/description`; the PNG has the result's size; a pixel inside the patch has the patch colour, one far away the result's; the description names yaw/pitch/FOV); `aFailedContributeShowsTheProblemsAndKeepsTheMemory`; `aNewExtractionResetsThePatch`.
- [ ] **Step 2: Run** `--filter PSCutoutTests` — expect FAIL.
- [ ] **Step 3: Implement.** The patch is the file at `lastResultPath`; `patchPath` is set at the first put-back. The montage: `render(layers: [patch layer at the memory pose, feather 0.03, aspect from the patch], width/height of the result, uOffset 0, background: result)`. «Save…» opens an `NSSavePanel` through an injectable closure so it is testable. The panel: the megapixel field, the size label, **Extract**, the thumbnail and the five icon buttons with their tooltips and enable rules (mockup).
- [ ] **Step 4: Run** — expect PASS; whole suite.
- [ ] **Step 5: Commit** — `feat(panorama-360): Cutout`.

### Task 7: Texts, README, hand tests

**Files:**
- Modify: `Strings.swift` (any word still inline), `Plugins/Panorama360/README.md` (sphere view, Cutout, the three flows, the 4:3 note, the retouch must keep framing), `Plugins/README.md` (row text), the notes (Obsidian `DT Hub - Panorama 360`, briefing)
- Test: `Tests/Panorama360Tests/StringsTests.swift`

- [ ] **Step 1: Write failing test** `theNewWordsAreInBothLanguages` (the existing loop over `L.Key.allCases` fails until every new key has both texts; also check that formatted keys keep their arguments).
- [ ] **Step 2: Run** the suite — expect FAIL for any missing word.
- [ ] **Step 3: Finish** `Strings.swift` and the README sections: *Looking around* (Plane/Sphere, Canvas/Result, controls), *Cutout* (what it extracts, the five buttons, when «put back» is off and why), *Typical flows* (look at the result → extract → retouch → put back as a sticker or into the panorama).
- [ ] **Step 4: Run** the plug-in suite, `Packages`, kit and `xcodebuild`; build the bundle with `Scripts/build.sh` and check `file`/`codesign`.
- [ ] **Step 5: Hand-test list for the user** (in the final message): Metal in the sphere (or the CPU fallback), looking around and zooming, moving/scaling/rotating a sticker from inside the sphere, the Result source updating after a RUN and being view only, a result that is deleted, Extract at 1 MP, the start-image and Moodboard buttons, Save…, a retouch with an edit model and both «put back» buttons, the montage appearing in the Results strip and in the viewer, opening an old project.
- [ ] **Step 6: Commit** — `feat(panorama-360): texts and README for the sphere view and the Cutout`.

---

## Self-review (done before saving)

- **Spec coverage:** §1–2 → Global Constraints and Tasks 5–6; §3 units → Tasks 2–6 (`PSCamera` T2, `renderView`/`background` T3, `PSSphere`/pointer T4, card T5, `PSCutout` T6); §3.1 camera maths → T2; §3.2 rendering → T3; §3.3 sticker interaction → T4; §4 state → T2 and T5; §5 contract → T1; §6 Cutout → T6; §7 limits and errors → Review Focus and tests in T5/T6; §8 tests → each task; §9 out of scope → not touched; §10 phases → the seven tasks.
- **Type consistency:** `PSCamera`, `PSViewMode`, `PSSource`, `PSCutoutMemory`, `PSViewSource`, `PSCutout`, `lastResultPath`, `resultImage` are named the same in every task that uses them.
- **Proportion:** interfaces, values and test names only; the formulas the spec fixes are the only ones stated.
