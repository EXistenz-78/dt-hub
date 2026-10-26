# Panorama 360 — correzione della giunzione Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Execution chosen by the user: native** (superpowers:executing-plans, in this session, one final independent review of the branch).

**Goal:** One button, «Correggi giunzione», that rotates the latest result by half its width, cuts the central square, masks its central half, asks DT Hub to regenerate it with a saved preset (a one-pass guided pipeline), then pastes the new band into the panorama with a soft edge and a brightness correction, rotates it back and files it in the Results.

**Architecture:** Pure geometry and picture work in `PSSeam` and `PSSeamImages` (roll, crop, mask, compose with fade and tone, copied from Tiled Upscale's `TUFade`/`TUTone`); `PSSeamSession` answers `session.next` with one self-contained pass and, at `session.end`, composes and sends the result with `contribute.result`; `PSState` and the plug-in route the messages and enable the button.

**Tech Stack:** as the earlier plans (Swift 6.2, SwiftUI, CoreGraphics, Swift Testing).

**Spec:** `docs/superpowers/specs/2026-10-26-panorama-360-giunzione-design.md`.

## Global Constraints

- Everything of the earlier plans still holds (texts in Italian and English in `L`, fields read the state, files added by name, commits end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`, no merge or push without the user's word, branch `feat/panorama-360`).
- No contract addition: the pass is a one-pass guided pipeline (`contribute.pipeline` with `"guided": true`, `"passes": 1`); the result goes with `contribute.result` while handling `session.end`.
- The geometry uses the real size of the result: square `s = H`, band `s/2` centred on the seam, context `s/4` each side, fade `s/16`; the result must be 2:1 (±4%), `H` a multiple of 64, `s ≤ 2048`.
- Constants in one place (`PSSeam`): `presetName = "PANO Test"`, `strength = 1`, `maskBlur = 24`, `maskOutset = 0`, `bandFraction = 0.5`, `fadeDivisor = 16`, `toneRadiusDivisor = 32`, `maxSquare = 2048`.
- The pass answer has no `fields` and no `loras`: the prompt and the parameters belong to the preset.
- Rolling moves columns only (no resampling); rolling twice gives the identity.
- The generated square never goes to the Results; only the corrected panorama does.

## Review Focus

1. The result is replaced or removed between pressing the button and RUN, or the session never gets `session.next`: the plug-in never composes from a stale or missing picture, and `session.next` without a session answers `{"done":true}`.
2. `session.end` arrives with `stopped`, `failed`, `closed`, or `finished` without `previous`, or `previous` of the wrong size: nothing is sent, the box says so, no crash.
3. Odd widths, tiny panoramas (1024×512 → 512×512 square), the largest allowed (4096×2048), and a result that is not 2:1: the right outcome (works, works, works, refused with the reason).
4. The seam is really closed: after the correction the columns on both sides of the old seam come from the generated band and agree with each other.
5. Project switched or plug-in restarted while the pass runs: the result still goes out once, or nothing does; never twice.

---

### Task 1: Geometry, picture work and the fusion

**Files:**
- Create: `Plugins/Panorama360/Sources/Panorama360/PSSeam.swift` (constants, plan, reasons), `PSSeamImages.swift` (roll, crop, mask PNG, compose), `PSSeamFade.swift` (the ramp and the tone correction, adapted from `Plugins/TiledUpscale/Sources/TiledUpscale/TUFade.swift` and `TUTone.swift`)
- Test: `Tests/Panorama360Tests/PSSeamTests.swift`, `PSSeamImagesTests.swift`

**Interfaces:**
- Produces: `struct PSSeamPlan: Equatable { width, height, square, bandX, bandWidth, fade, cropX }`; `enum PSSeamReason: Equatable { noResult, unreadable, notTwoToOne, heightNotMultipleOf64, tooBig }`; `PSSeam.plan(width: Int, height: Int) -> Result<PSSeamPlan, PSSeamReason>`; `PSSeamImages.rolled(_ image: CGImage, by columns: Int) -> CGImage?`; `.crop(_ image: CGImage, x: Int, width: Int) -> CGImage?` (full height); `.maskPNG(square: Int, bandX: Int, bandWidth: Int) -> Data?`; `.pngData(_ image: CGImage) -> Data?`; `PSSeamImages.compose(rolled: CGImage, generated: CGImage, plan: PSSeamPlan) -> CGImage?` (the panorama with the generated band blended in, still rolled).

- [ ] **Step 1: Write failing tests** (with synthetic pictures from `TestImages`): `planForTheThreeSizes` (2048×1024 → square 1024, bandWidth 512, bandX 768 in the rolled panorama, cropX 512, fade 64; 1024×512 → 512/256/384/256/32; 4096×2048 → 2048/1024/…); `reasonsForRefusal` (1000×1024 not 2:1 → `.notTwoToOne`; 2000×1000 → `.heightNotMultipleOf64`; 6144×3072 → `.tooBig`; 2048×1024 with 4 % off is accepted, 5 % off refused); `rollingMovesColumnsExactly` (pixel `(x, y)` of the roll is pixel `((x + k) % W, y)` of the original) and `rollingTwiceByHalfIsTheIdentity` (also for an odd width: the second roll is by `W − k`); `cropTakesTheCentralSquare`; `theMaskIsGreyWith255OnlyInTheBand` (size `s × s`, columns `s/4 ..< 3s/4`); `composeKeepsTheOriginalOutsideTheBandAndTheGeneratedInsideIt` (solid red panorama, solid blue generated: the centre column is blue, a column in the context is red, the picture has the panorama's size); `theFadeIsMonotonic` (along the band's left edge the blue weight grows from 0 to 1 over `fade` pixels and never decreases); `theToneIsBroughtTowardsTheOriginal` (original mid-grey, generated much brighter: the composed band is closer to the original grey than the generated was); `composeRejectsAGeneratedPictureOfAnotherSize` (returns nil).
- [ ] **Step 2: Run** `swift test --package-path Plugins/Panorama360 --filter "PSSeamTests|PSSeamImagesTests"` — expect FAIL.
- [ ] **Step 3: Implement** per the spec §4. `compose`: weight ramp `smoothstep` of `min(distance from the band's left edge, distance from its right edge) / fade`; tone gain per pixel as `blur(origLum)/blur(genLum)` (box blur of radius `square/32`, separable), clamped 0.2…5, applied to the generated colours inside the band before the blend.
- [ ] **Step 4: Run** — expect PASS; whole suite.
- [ ] **Step 5: Commit** — `feat(panorama-360): seam geometry, picture work and fusion`.

### Task 2: The guided session

**Files:**
- Create: `Sources/Panorama360/PSSeamSession.swift`
- Test: `Tests/Panorama360Tests/PSSeamSessionTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces: `final class PSSeamSession` with `init(panorama: CGImage, plan: PSSeamPlan, folder: URL)`; `func next(index: Int, count: Int) -> [String: Any]` (the pass for `index == 1`, else `["done": true]`); `func end(reason: String, previous: (path: String, width: Int, height: Int)?) -> PSSeamOutcome` where `enum PSSeamOutcome { case montage(CGImage, description: String); case nothing(reason: PSSeamProblem) }` and `enum PSSeamProblem { stopped, failed, closed, noPicture, wrongSize, unreadable }`; `static func estimate() -> [String: Any]` (`preset`, `size`).

- [ ] **Step 1: Write failing tests:** `theFirstPassIsAutonomous` (answer has `startImage.path` and `mask.path` to files that exist, `size == {square, square}`, `preset == "PANO Test"`, `strength == 1`, `maskSettings == {blur 24, outset 0, preserveOriginal true}`, no `fields`, no `loras`; the start image is the central square of the rolled panorama, the mask as in Task 1); `aSecondNextIsDone`; `endFinishedComposesAndRollsBack` (previous = a solid colour square file of the right size → montage has the panorama's size and the columns `0` and `W−1` take the generated colour while the middle of the panorama keeps the original; the description names the band width); `endStoppedFailedClosedSendNothing` (`.nothing` with the matching problem); `endFinishedWithoutPreviousOrWithTheWrongSize` (`.noPicture` / `.wrongSize`); `anUnreadablePreviousFile` (`.unreadable`); `estimateNamesThePresetAndTheSize`.
- [ ] **Step 2: Run** `--filter PSSeamSessionTests` — expect FAIL.
- [ ] **Step 3: Implement** the pass answer like `TUSession.next` (PNG files in `folder`, paths in the answer) and `end` with `PSSeamImages.compose` then `rolled(by: W − W/2)` back; description «Giunzione corretta · fascia N px» via `L`.
- [ ] **Step 4: Run** — expect PASS; whole suite.
- [ ] **Step 5: Commit** — `feat(panorama-360): the guided session of the seam correction`.

### Task 3: State, plug-in, button, texts

**Files:**
- Create: `Sources/Panorama360/PSStateSeam.swift`
- Modify: `PSState.swift` (`seamSession`, `isSeamPrepared`), `Panorama360Plugin.swift` (`session.next`, `session.end`, the action), `PSView.swift` (the button), `PSPromptCard.swift` (`PSViewActions.seam`), `Strings.swift`
- Test: `Tests/Panorama360Tests/PSStateSeamTests.swift`, `PluginTests.swift`

**Interfaces:**
- Produces: `PSState.seamReason: PSSeamReason?` (nil = the button is on; uses `resultImage`/`lastResultPath`); `PSState.prepareSeamCorrection(contribute: PSContribute) async`; `PSState.seamNext(_ message: Data) -> Data`; `PSState.seamEnded(_ message: Data, contribute: PSContribute) async`.

- [ ] **Step 1: Write failing tests:** `theButtonIsOffWithoutAResultAndSaysWhy` (each `PSSeamReason` for the matching situation: no result, unreadable file, 2:1 off, height 500, too big); `prepareDeclaresAOnePassGuidedPipeline` (fake `contribute` captures `pipeline.name`, `guided == true`, `passes == 1`, `estimate.preset == "PANO Test"`, `estimate.size`); `aRefusedDeclarationShowsTheErrorAndKeepsNoSession`; `sessionNextAnswersThePassThenDone` (through `seamNext` with JSON `session.next` index 1 then 2); `sessionNextWithoutASessionIsDone`; `sessionEndFinishedSendsTheMontageToTheResults` (fake `contribute` captures `result.path/name/description`; the PNG has the result's size; `state.notice` says it is corrected); `sessionEndStoppedSendsNothingAndSaysSo`; `thePanoramaIsTheOneLoadedAtThePress` (the context changes the result between the press and the end: the montage is made on the old picture); `theMontageIsSentOnlyOnce` (a second `session.end` does nothing); plug-in: `sessionMessagesAreRoutedToTheState` (`handle` of `session.next` returns a pass JSON; unknown still `unsupported`).
- [ ] **Step 2: Run** `--filter "PSStateSeamTests|PluginTests"` — expect FAIL.
- [ ] **Step 3: Implement.** The button lives in the toolbar of the card in the sphere view when the source is the result (pill with the text «Correggi giunzione», tooltip with `seamReason` text when off); `prepareSeamCorrection` loads the panorama (`PSResultLoader.load(maxSide: nil)`), makes the plan, creates `PSSeamSession(folder: tempFolder)`, declares the pipeline, sets `notice` «Pronto: premi RUN in DT Hub.»; `seamEnded` parses `reason` and `previous`, runs `end` off the main actor, sends `contribute.result` on `.montage`, sets `notice` or `error`, drops the session. Texts: button, tooltips for the five reasons, «Pronto…», «Giunzione corretta: il panorama è nei Risultati.», problems.
- [ ] **Step 4: Run** — expect PASS; whole suite; render the card to PNG and look at the button.
- [ ] **Step 5: Commit** — `feat(panorama-360): Correggi giunzione`.

### Task 4: README, notes, bundle

**Files:** `Plugins/Panorama360/README.md`, `Plugins/README.md`, `Tests/Panorama360Tests/StringsTests.swift` (the loop over `L.Key.allCases` already guards the words)

- [ ] **Step 1: Write failing test** `theSeamWordsAreInBothLanguages` only if a new key lacks a text (the existing loop fails otherwise); run `--filter StringsTests` — expect PASS once Task 3 is complete (the guard).
- [ ] **Step 2: README** (English): *Closing the seam*: the button, what it does (roll, square, band, preset, paste back), the preset `PANO Test` is yours to change (name today in one constant), the limits (2:1, height multiple of 64, up to 2048), the generated square does not go to the Results.
- [ ] **Step 3: Run** the plug-in suite, `Scripts/build.sh`, `file`/`codesign`.
- [ ] **Step 4: Hand-test list** for the user (in the final message): button off/on, RUN with `PANO Test`, the corrected panorama in the Results and in the Result source, look at the old seam in the sphere view, Stop mid-run, a 1024×512 result.
- [ ] **Step 5: Commit** — `docs(panorama-360): README for the seam correction`.

---

## Self-review (done before saving)

- **Spec coverage:** §3 flow → Tasks 2–3; §4 geometry → Task 1; §5 errors → Review Focus and Tasks 2–3; §6 tests → each task; §7 phases → the four tasks; §8 out → not touched.
- **Type consistency:** `PSSeamPlan`, `PSSeamReason`, `PSSeamSession`, `PSSeamOutcome`, `seamReason`, `prepareSeamCorrection`, `seamNext`, `seamEnded` are named the same in every task.
- **Proportion:** interfaces, values and test names only.
