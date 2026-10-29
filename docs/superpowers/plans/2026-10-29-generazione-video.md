# Generazione video (H3, FastH3 Omni, LTX-2.3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generare video con MiniMax H3, FastH3 Omni e LTX-2.3 dal server gRPC di Draw Things (cloud DT+ e modelli locali) e vederli nella striscia Risultati come MP4 HEVC con audio.

**Architecture:** Una tabella di famiglie video in HubKit (frame validi, fps, audio) guida parametri, valori predefiniti e interfaccia. `GenerationJob`/`GenerationParameters` ricevono campi video opzionali e tolleranti; `GenerationUpdate` un esito `finishedVideo`. DTBridge mappa i campi sulla configurazione, accumula i frame, ritenta gli errori casuali e registra le specifiche dei modelli community. HubCore codifica l'MP4 a fine run e salva accanto a esso il PNG di copertina (che porta il job nei metadati e tiene in piedi cronologia, ripristino e cestino). L'app aggiunge le card e il lettore.

**Tech Stack:** Swift 6.2, SwiftUI, AVFoundation (AVAssetWriter, AVPlayer), Swift Testing (`@Test`, `#expect`), DrawThings-Swift 2.2.x, pacchetto `Packages`, app Xcode `DTHub`.

**Spec:** `docs/superpowers/specs/2026-10-29-generazione-video-design.md`

## Global Constraints

- Lavora sul ramo `feat/video`, senza unire in `main`, senza push né release.
- `git add` sempre **per nome**, mai `git add -A` (nel repo ci sono file non tracciati non tuoi). I commit finiscono con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Stringhe dell'interfaccia in `App/Localizable.xcstrings`, tutte tradotte in `en` e `it` (lo verifica `CatalogTests`); niente testo fisso nelle viste.
- Formati salvati tolleranti: un campo mancante nel JSON prende il suo valore predefinito (come `GenerationParameters`).
- Famiglie video abilitate: solo `minimax_h3` e `ltx2.3`. Wan, Hunyuan, SVD, `ltx2`, `longcat_video_avatar_v1.5` restano nascoste.
- Frame validi: H3 e FastH3 `17k+5` (5, 22, 39, 56, 73, 90, 107, 124…); LTX-2.3 `8k+1` (25, 81, 121…). fps: H3 24, LTX 25 (solo per durata ed export, nessun campo). Audio: H3 32000 Hz, LTX 48000 Hz.
- Valori della scheda: Audio Shift predefinito 3 (intervallo 0,1–12); Strategic Stochastic Sampling 0,3 (0–1), solo LTX con sampler TCD o TCD Trailing; Sol Attention start 2, tau 0,50; TeaCache start 5, end -1, threshold 0,06, max skip 3; Compression Artifacts `none/h264/h265/jpeg` (già in `AdvancedParameters`).
- Valori predefiniti alla selezione del modello (`ModelSelection.choose`): FastH3: 8 step, DDIM Trailing (sampler 16), guidance 1, shift 12 (senza shift dipendente dalla risoluzione), audio shift 3, 832×512, 124 frame, decodifica a tessere 256×256 sovrapposizione 64. H3: 50 step, DDIM Trailing, guidance 1, shift 12, audio shift 3, 576×448, 56 frame, stessa decodifica a tessere. LTX-2.3: 8 step, TCD Trailing (19), guidance 1, shift 5, 121 frame, risoluzione finale 1280×768 con correzione ad alta risoluzione che parte da 640×384, strength 0,7. (I valori di FastH3 e H3 sono quelli provati sul cloud; per LTX la configurazione provata era 768×448, 25 frame, senza correzione, mentre quella qui sopra viene dal preset di `drawthings-py` e non è provata: vedi Task 12.)
- Batch size sempre 1 per i modelli video. Nessuna stima CU per i video.
- Il run sul cloud con un solo frame da un modello video è un errore; in locale no.
- Comandi: test `swift test` in `Packages` (con `--filter <NomeTest>` per uno solo); app `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build` dalla radice del repo.

## Review Focus

1. Passare da un modello video a uno immagine: i parametri video non devono finire nel job dell'immagine (`numFrames`, audio shift, Sol Attention tornano ai valori predefiniti). Test nel Task 4.
2. Frame fuori serie (56 per LTX, 100 per H3) da JSON editor, preset o sessione salvata: il job li porta al valore valido più vicino. Test nel Task 4.
3. Batch size > 1 su un modello video: il job lo porta a 1. Test nel Task 4.
4. Stop a metà run, con frame già arrivati: non si salva nulla. Un errore dopo i primi frame invece salva un video parziale. Test nel Task 9.
5. Voce di cronologia il cui MP4 non c'è più, o cestino di un video: la striscia mostra la sola copertina senza badge, e il cestino toglie sia PNG sia MP4. Test nei Task 5 e 6.

---

## File structure

**HubKit**
- Modify `Packages/Sources/HubKit/Catalog/VideoFamilies.swift` — tabella delle famiglie abilitate.
- Create `Packages/Sources/HubKit/Generation/VideoParameters.swift` — parametri video.
- Create `Packages/Sources/HubKit/Generation/VideoDefaults.swift` — valori predefiniti per famiglia e per file.
- Modify `Packages/Sources/HubKit/Generation/GenerationParameters.swift` (campo `video`), `GenerationJob.swift` (campo `videoFPS`, tipi `GeneratedVideo`, caso `finishedVideo`), `Backend/GenerationBackend.swift` (errore `videoNotAvailable`), `Catalog/ModelCatalog.swift` (`CatalogModel.isLocalOnly`).

**HubCore**
- Modify `Packages/Sources/HubCore/ModelPicker/ModelTree.swift`, `Selection/ModelSelection.swift`, `Family/AdvancedField.swift`, `Generation/JobComposer.swift`, `Generation/GenerationSession.swift`, `Output/ImageStore.swift`, `Output/ResultInfo.swift`.
- Create `Packages/Sources/HubCore/Output/MP4Encoder.swift`.

**DTBridge**
- Modify `JobMapper.swift`, `ConfigurationCodec.swift`, `DrawThingsBackend.swift`, `CatalogBuilder.swift`.
- Create `VideoStreamTools.swift` (accumulo frame e logica di ritentativo), `VideoModelSpecs.swift` (generato), e `Scripts/make-video-specs.py`.

**App**
- Create `App/Generation/Cards/VideoSettingsCard.swift`, `AcceleratorCard.swift`, `App/Results/VideoPlayerView.swift`.
- Modify `App/MainWindow/GenerationTabView.swift`, `App/Generation/Advanced/AdvancedSection.swift`, `App/Results/ResultsView.swift`, `App/MainWindow/ModelPickerView.swift`, `App/Localizable.xcstrings`, `README.md`.

---

### Task 1: Famiglie video abilitate

**Files:**
- Modify: `Packages/Sources/HubKit/Catalog/VideoFamilies.swift`
- Modify: `Packages/Sources/HubCore/ModelPicker/ModelTree.swift:59-60`
- Test: `Packages/Tests/HubKitTests/VideoFamiliesTests.swift` (create), `Packages/Tests/HubCoreTests/ModelTreeTests.swift` (modify)

**Interfaces:**
- Produces:
  - `public struct VideoFamilyInfo: Equatable, Sendable` con `family: String`, `framesPerSecond: Double`, `audioSampleRate: Int`, `frameStep: Int`, `frameOffset: Int`, `minFrames: Int`, `maxFrames: Int`, `usesAudioShift: Bool`, `usesAccelerators: Bool`, `usesStochasticSampling: Bool`.
  - `VideoFamilyInfo.snap(_ frames: Int) -> Int` (valore valido più vicino nell'intervallo `minFrames...maxFrames`), `.step(_ frames: Int, by direction: Int) -> Int` (valido successivo/precedente, `direction` ±1, fermo agli estremi), `.seconds(forFrames: Int) -> Double`.
  - `VideoFamilies.keys` (tutte le famiglie video, resta), `VideoFamilies.info(for family: String?) -> VideoFamilyInfo?` (solo abilitate), `VideoFamilies.isEnabled(_:) -> Bool`, `VideoFamilies.isHidden(_:) -> Bool` (video ma non abilitata). Il vecchio `contains` si toglie e i suoi usi passano a `isHidden`.

- [ ] **Step 1: Write the failing tests** in `VideoFamiliesTests.swift`:
  - `h3FramesFollowSeventeenKPlusFive`: `info(for: "minimax_h3")!.snap(56) == 56`, `snap(57) == 56`, `snap(120) == 124`, `snap(1) == 5`, `step(56, by: 1) == 73`, `step(56, by: -1) == 39`.
  - `ltxFramesFollowEightKPlusOne`: `info(for: "ltx2.3")!.snap(100) == 97`, `snap(121) == 121`, `step(121, by: 1) == 129`.
  - `limitsAreHonoured`: `snap(10_000) == maxFrames` per famiglia con `maxFrames` H3 192 e LTX 249; `minFrames` H3 5 e LTX 9.
  - `secondsUseTheFamilyFrameRate`: H3 `seconds(forFrames: 124)` ≈ 5,1667 (±0,001); LTX `seconds(forFrames: 121)` ≈ 4,84.
  - `onlyH3AndLTXAreEnabled`: `isEnabled("minimax_h3")`, `isEnabled("ltx2.3")`, `!isEnabled("wan_v2.2_5b")`; `isHidden("wan_v2.2_5b")`, `!isHidden("minimax_h3")`, `!isHidden("flux2_9b")`, `!isHidden(nil)`.
  - In `ModelTreeTests`, il test esistente che si aspetta le famiglie video nascoste va adattato: `minimax_h3` e `ltx2.3` compaiono nell'albero, `wan_v2.2_5b` no.
- [ ] **Step 2: Run to verify failure**: `swift test --filter VideoFamiliesTests` in `Packages`. Atteso: errore di compilazione (tipi non definiti).
- [ ] **Step 3: Implement** la tabella: H3 `frameStep 17`, `frameOffset 5`, 24 fps, 32000 Hz, `usesAudioShift` e `usesAccelerators` true, `usesStochasticSampling` false; LTX `frameStep 8`, `frameOffset 1`, 25 fps, 48000 Hz, `usesStochasticSampling` true, gli altri due false. `snap` calcola `k = round((n - offset) / step)` e riporta nell'intervallo. In `ModelTree.sections` la guardia diventa `guard !VideoFamilies.isHidden(family.family)`; aggiorna il commento di `VideoFamilies` (ora descrive le famiglie nascoste).
- [ ] **Step 4: Run** `swift test --filter VideoFamiliesTests` e `--filter ModelTreeTests`. Atteso: PASS.
- [ ] **Step 5: Commit**: `git add Packages/Sources/HubKit/Catalog/VideoFamilies.swift Packages/Sources/HubCore/ModelPicker/ModelTree.swift Packages/Tests/HubKitTests/VideoFamiliesTests.swift Packages/Tests/HubCoreTests/ModelTreeTests.swift` e `git commit -m "feat(video): famiglie video abilitate e frame validi"`.

---

### Task 2: Parametri video nel job

**Files:**
- Create: `Packages/Sources/HubKit/Generation/VideoParameters.swift`
- Modify: `Packages/Sources/HubKit/Generation/GenerationParameters.swift`, `GenerationJob.swift`
- Test: `Packages/Tests/HubKitTests/VideoParametersTests.swift` (create)

**Interfaces:**
- Produces:
  - `public struct VideoParameters: Equatable, Codable, Sendable` con `numFrames: Int = 1`, `shiftForAudio: Double = 3`, `usesSolAttention: Bool = false`, `solAttentionStart: Int = 2`, `solAttentionTau: Double = 0.5`; `static let default`; `static let audioShiftRange = 0.1...12.0`, `solStartRange = 0...150`, `solTauRange = 0.0...4.0`; `func clamped(for info: VideoFamilyInfo?) -> VideoParameters` (frame con `snap` se c'è la famiglia, altrimenti `numFrames` resta com'è; gli altri campi nei loro intervalli); decodifica tollerante.
  - `GenerationParameters.video: VideoParameters` (parametro dell'init con valore predefinito `.default`, decodifica tollerante, incluso in `clamped()` senza famiglia).
  - `GenerationJob.videoFPS: Double?` (nil per le immagini; init con parametro `videoFPS: Double? = nil`; decodifica tollerante) e `GenerationJob.isVideo: Bool { videoFPS != nil }`, `GenerationJob.videoSeconds: Double? { videoFPS.map { Double(parameters.video.numFrames) / $0 } }`.
  - `public struct GeneratedAudioTrack: Equatable, Sendable { channels: [[Float]]; sampleRate: Double }` e `public struct GeneratedVideo: Sendable { frames: [CGImage]; audio: GeneratedAudioTrack?; framesPerSecond: Double; isPartial: Bool }` (init con `isPartial: Bool = false`).
  - `GenerationUpdate.finishedVideo(GeneratedVideo)`.

- [ ] **Step 1: Write the failing tests**:
  - `defaultsMatchDrawThings`: `VideoParameters.default` ha `numFrames 1`, `shiftForAudio 3`, `usesSolAttention false`, `solAttentionStart 2`, `solAttentionTau 0.5`.
  - `clampedSnapsFramesToTheFamily`: con `VideoFamilies.info(for: "minimax_h3")`, `numFrames 100` → 107; senza famiglia resta 100; `shiftForAudio 99` → 12; `solAttentionTau -1` → 0.
  - `oldSavedParametersStillLoad`: il JSON di un `GenerationParameters` senza chiave `video` si decodifica con `video == .default`; un job senza `videoFPS` si decodifica con `videoFPS == nil`.
  - `jobKnowsItsDuration`: job con `videoFPS 24` e `numFrames 124` → `videoSeconds ≈ 5.1667`; senza `videoFPS` → nil e `isVideo == false`.
  - `roundTripKeepsVideoFields`: codifica e decodifica un job video.
- [ ] **Step 2: Run** `swift test --filter VideoParametersTests`. Atteso: FAIL (non compila).
- [ ] **Step 3: Implement** i tipi come sopra. `GenerationParameters.clamped()` clampa `video` con `clamped(for: nil)`. La famiglia entra in gioco solo nel `JobComposer` (Task 4).
- [ ] **Step 4: Run** `swift test --filter VideoParametersTests` e poi `swift test --filter HubKitTests`. Atteso: PASS (i test esistenti non si rompono).
- [ ] **Step 5: Commit**: aggiungi per nome `VideoParameters.swift`, `GenerationParameters.swift`, `GenerationJob.swift` e il test; `git commit -m "feat(video): parametri video nel job"`.

---

### Task 3: Valori predefiniti alla selezione del modello

**Files:**
- Create: `Packages/Sources/HubKit/Generation/VideoDefaults.swift`
- Modify: `Packages/Sources/HubCore/Selection/ModelSelection.swift`
- Test: `Packages/Tests/HubKitTests/VideoDefaultsTests.swift` (create), `Packages/Tests/HubCoreTests/ModelSelectionTests.swift` (modify)

**Interfaces:**
- Consumes: `VideoFamilies.info(for:)`, `GenerationParameters.video`, `AdvancedParameters`.
- Produces: `VideoDefaults.applying(to parameters: GenerationParameters, file: String, family: String?) -> GenerationParameters?` — nil se la famiglia non è un video abilitato. Cambia: step, guidance, sampler, shift, `resolutionDependentShift`, larghezza e altezza, `video.numFrames`, `video.shiftForAudio`, decodifica a tessere e (solo LTX) la correzione ad alta risoluzione con i valori dei Global Constraints; azzera anche `video.usesSolAttention` e `advanced.teaCache`. Il file `fasth3_omni…` (prefisso del nome) usa i valori FastH3 anche se la famiglia è `minimax_h3`. Non tocca seed, batch, LoRA, prompt. Imposta `batchSize = 1`.
- `ModelSelection.choose(_:applyingTo:from:in:)` mantiene la firma: se il modello cambia e `VideoDefaults.applying` dà un risultato, vince sui valori di `RecommendedSettings`; altrimenti il comportamento di oggi resta.

- [ ] **Step 1: Write the failing tests**:
  - `fastH3Defaults`: da `GenerationParameters()` con file `fasth3_omni_i4x.ckpt` e famiglia `minimax_h3` → `steps 8`, `sampler == .ddimTrailing`, `guidanceScale 1`, `shift 12`, `resolutionDependentShift == false`, `width 832`, `height 512`, `video.numFrames 124`, `video.shiftForAudio 3`, `advanced.tiledDecoding == true` con tessere 256/256/64, `batchSize 1`.
  - `h3Defaults`: file `minimax_h3_ref2va_i4x.ckpt` → `steps 50`, `width 576`, `height 448`, `video.numFrames 56`.
  - `ltxDefaults`: file `ltx_2.3_22b_distilled_1.1_q8p.ckpt`, famiglia `ltx2.3` → `steps 8`, `sampler == .tcdTrailing`, `shift 5`, `video.numFrames 121`, `width 1280`, `height 768`, `advanced.hiresFix == true`, `hiresFixWidth 640`, `hiresFixHeight 384`, `hiresFixStrength 0.7`.
  - `imageFamilyGivesNil`: famiglia `flux2_9b` → `nil`.
  - `keepsSeedBatchAndLoRAs`: seed, `batchCount` e LoRA invariati.
  - In `ModelSelectionTests`: `choose` di un modello H3 diverso dal precedente ritorna parametri con 50 step; `choose` dello stesso modello due volte ritorna nil la seconda.
- [ ] **Step 2: Run** `swift test --filter VideoDefaultsTests`. Atteso: FAIL.
- [ ] **Step 3: Implement** `VideoDefaults` come tabella di costanti più la funzione, poi il ramo in `ModelSelection.choose`.
- [ ] **Step 4: Run** `swift test --filter VideoDefaultsTests`, `--filter ModelSelectionTests`, `--filter ModelChoiceTests`. Atteso: PASS.
- [ ] **Step 5: Commit** dei cinque file per nome: `git commit -m "feat(video): valori predefiniti per modello video"`.

---

### Task 4: Composizione del job video

**Files:**
- Modify: `Packages/Sources/HubCore/Generation/JobComposer.swift`, `Packages/Sources/HubCore/Family/AdvancedField.swift`
- Test: `Packages/Tests/HubCoreTests/JobComposerVideoTests.swift` (create), `Packages/Tests/HubCoreTests/AdvancedFieldTests.swift` (modify)

**Interfaces:**
- Consumes: `VideoFamilies.info(for:)`, `VideoParameters.clamped(for:)`, `GenerationJob.videoFPS`.
- Produces:
  - `JobComposer.batches(...)` invariata nella firma. Con `family` video abilitata: `parameters.video` clampato con `clamped(for: info)`, `batchSize = 1`, `videoFPS = info.framesPerSecond`; `usesAudioShift == false` → `shiftForAudio` torna a 3; `usesAccelerators == false` → `usesSolAttention` false e `advanced.teaCache` false (TeaCache e Sol Attention restano solo per H3); con una famiglia non video: `video = .default` e `videoFPS == nil`.
  - `AdvancedField.isInVideoCards(for model: CatalogModel?) -> Bool` — true per `.teaCache`, `.compressionArtifacts` e `.stochasticSamplingGamma` quando la famiglia del modello è un video abilitato. Non cambia `isShown`.

- [ ] **Step 1: Write the failing tests** in `JobComposerVideoTests`:
  - `videoJobCarriesFpsAndSnappedFrames`: famiglia `ltx2.3`, `video.numFrames 100` → ogni job ha `parameters.video.numFrames == 97` e `videoFPS == 25`.
  - `switchingToAnImageModelResetsVideoParameters`: famiglia `flux2_9b` con `video.numFrames 124`, `shiftForAudio 8`, `usesSolAttention true` → job con `video == .default` e `videoFPS == nil`.
  - `batchSizeIsOneForVideo`: `batchSize 4` con famiglia `minimax_h3` → tutti i job `batchSize == 1`.
  - `ltxDoesNotKeepH3Accelerators`: famiglia `ltx2.3` con `usesSolAttention true` e `advanced.teaCache true` → entrambi false nel job.
  - In `AdvancedFieldTests`: `isInVideoCards` true per `.teaCache` con un modello `minimax_h3`, false con un modello `flux2_9b`, false per `.guidanceEmbed`; `isShown` di `.teaCache` per un modello H3 con `capabilities.teaCache == true` resta true.
- [ ] **Step 2: Run** `swift test --filter JobComposerVideoTests`. Atteso: FAIL.
- [ ] **Step 3: Implement** in `JobComposer` (la parte video dopo il filtro dei LoRA) e il nuovo metodo in `AdvancedField`.
- [ ] **Step 4: Run** `swift test --filter JobComposerVideoTests`, `--filter AdvancedFieldTests`, `--filter HubCoreTests`. Atteso: PASS.
- [ ] **Step 5: Commit**: `git commit -m "feat(video): job video nel composer"` con i file per nome.

---

### Task 5: Codifica MP4 e salvataggio

**Files:**
- Create: `Packages/Sources/HubCore/Output/MP4Encoder.swift`
- Modify: `Packages/Sources/HubCore/Output/ImageStore.swift`
- Test: `Packages/Tests/HubCoreTests/MP4EncoderTests.swift` (create), `Packages/Tests/HubCoreTests/PNGImageStoreTests.swift` (modify)

**Interfaces:**
- Consumes: `GeneratedVideo`, `GeneratedAudioTrack`, `ImageStore.save(_:job:index:date:elapsed:)`.
- Produces:
  - `public enum MP4Encoder { public static func write(_ video: GeneratedVideo, to url: URL) async throws }` — HEVC (`AVVideoCodecType.hevc`), `framesPerSecond` della video, traccia AAC stereo alla frequenza dell'audio se `audio != nil`; sovrascrive un file esistente. Errore `MP4EncoderError.cannotWrite(String)`; un video senza frame lancia `MP4EncoderError.noFrames`.
  - `ImageStore.videoURL(forPoster poster: URL) -> URL` (stesso nome, estensione `mp4`, statico nell'extension) e `ImageStore.saveVideo(_ video: GeneratedVideo, job: GenerationJob, date: Date, elapsed: TimeInterval?) async throws -> URL` che salva il primo frame con `save(...)` (la copertina PNG col job nei metadati), scrive l'MP4 accanto e ritorna l'URL della copertina. Se la scrittura dell'MP4 fallisce, la copertina viene tolta e l'errore sale come `ImageStoreError.cannotWrite`.
  - `ImageStore.trash(_:)` toglie anche l'MP4 gemello se esiste.

- [ ] **Step 1: Write the failing tests**:
  - `encoderWritesHEVCWithAudio`: 5 frame sintetici 256×144, 24 fps, audio stereo 32000 Hz di 0,2 s (seno) → il file esiste, `AVURLAsset` ha durata di 5/24 s (±0,05), una traccia video con sottotipo `hvc1` e una traccia audio.
  - `encoderWithoutAudioHasNoAudioTrack`: stesso video con `audio: nil` → nessuna traccia audio.
  - `encoderRejectsEmptyVideo`: `frames: []` lancia `MP4EncoderError.noFrames`.
  - In `PNGImageStoreTests`: `saveVideoWritesPosterAndMP4Together`: dopo `saveVideo` esistono `x.png` e `x.mp4` con lo stesso nome base, e `PNGImageStore.job(in:)` della copertina rilegge il job; `trashRemovesBothFiles`: dopo `trash(posterURL)` nessuno dei due esiste (un MP4 già mancante non è un errore).
- [ ] **Step 2: Run** `swift test --filter MP4EncoderTests`. Atteso: FAIL.
- [ ] **Step 3: Implement** `MP4Encoder` con `AVAssetWriter`, `AVAssetWriterInputPixelBufferAdaptor` per i frame e `AVAssetWriterInput` con campioni PCM convertiti in `CMSampleBuffer` per l'audio (interleaved float32, output AAC). Le dimensioni vengono arrotondate al pari più vicino se dispari. Poi le estensioni di `ImageStore`.
- [ ] **Step 4: Run** `swift test --filter MP4EncoderTests`, `--filter PNGImageStoreTests`. Atteso: PASS. Se la codifica HEVC non parte nell'ambiente dei test, il test fallisce con l'errore dell'encoder: segnalalo invece di cambiare codec.
- [ ] **Step 5: Commit**: `git commit -m "feat(video): codifica MP4 HEVC e salvataggio"`.

---

### Task 6: Sessione e informazioni del risultato

**Files:**
- Modify: `Packages/Sources/HubCore/Generation/GenerationSession.swift`, `Packages/Sources/HubCore/Output/ResultInfo.swift`
- Test: `Packages/Tests/HubCoreTests/GenerationSessionVideoTests.swift` (create), `Packages/Tests/HubCoreTests/ResultInfoTests.swift` (modify), `Packages/Tests/HubCoreTests/FakeBackend.swift` (modify se serve un'uscita video)

**Interfaces:**
- Consumes: `GenerationUpdate.finishedVideo`, `ImageStore.saveVideo`, `ImageStore.videoURL(forPoster:)`.
- Produces:
  - `GeneratedImage.videoURL: URL?`, `GeneratedImage.videoSeconds: Double?`, `GeneratedImage.isPartialVideo: Bool` (tutti con valore predefinito nil/nil/false).
  - `GenerationSession` gestisce `.finishedVideo`: salva con `saveVideo`, inserisce un `GeneratedImage` con la copertina ridotta a `displayPixels`, `videoURL`, `videoSeconds = frames / fps` e `isPartialVideo`. Con `intermediate != nil` usa il solo primo frame come immagine intermedia. Se l'MP4 non si scrive, il risultato resta come immagine non salvata con `saveError`.
  - `restoredImage` imposta `videoURL` se l'MP4 gemello esiste e `videoSeconds` da `job.videoSeconds`.
  - `ResultInfo`: nuove righe nella sezione `.model` — `Field.frames` (numero di frame) e `Field.duration` (secondi) — e `Field.partial` nella sezione `.file` se il video è parziale. Compaiono solo se `job.isVideo`; il resto resta come per le immagini.

- [ ] **Step 1: Write the failing tests**:
  - `finishedVideoAddsOneResultWithVideoURL`: un `FakeBackend` che emette `.finishedVideo` con 5 frame → `results.count == 1`, `results[0].videoURL != nil`, il file esiste, `videoSeconds ≈ 5/24`.
  - `partialVideoIsMarked`: con `isPartial: true` → `results[0].isPartialVideo == true`.
  - `restoredVideoKeepsItsURL`: dopo `restoreHistory()` in un'altra sessione sullo stesso archivio, il risultato ha ancora `videoURL`; se l'MP4 è stato cancellato, `videoURL == nil` e la copertina resta (Review Focus 5).
  - `removingAVideoTrashesBothFiles`: `remove([id])` toglie PNG e MP4.
  - In `ResultInfoTests`: un job con `videoFPS 24` e `numFrames 124` ha righe `.frames` = "124" e `.duration` presente; un job immagine non le ha.
- [ ] **Step 2: Run** `swift test --filter GenerationSessionVideoTests`. Atteso: FAIL.
- [ ] **Step 3: Implement** i campi, il ramo `finishedVideo` accanto a `.finished` e il ripristino. Le etichette delle nuove righe di `ResultInfo` si aggiungono in `App/Results/ResultInfoSidebar.swift` insieme alle stringhe (Task 11).
- [ ] **Step 4: Run** `swift test --filter GenerationSessionVideoTests`, `--filter ResultInfoTests`, `--filter GenerationSessionTests`. Atteso: PASS.
- [ ] **Step 5: Commit**: `git commit -m "feat(video): risultati video nella sessione"`.

---

### Task 7: Configurazione e mappatura degli eventi (DTBridge)

**Files:**
- Modify: `Packages/Sources/DTBridge/JobMapper.swift`, `Packages/Sources/DTBridge/ConfigurationCodec.swift`, `Packages/Sources/HubKit/Backend/GenerationBackend.swift`
- Test: `Packages/Tests/DTBridgeTests/JobMapperVideoTests.swift` (create), `Packages/Tests/DTBridgeTests/ConfigurationCodecTests.swift` (modify)

**Interfaces:**
- Consumes: `GenerationParameters.video`, `GeneratedVideo`, `GenerationUpdate.finishedVideo`.
- Produces:
  - `BackendError.videoNotAvailable` (caso nuovo, "il modello video non gira sul cloud").
  - `JobMapper.configuration(model:parameters:)` imposta `numFrames`, `shiftForAudio`, `usesSolAttention`, `solAttentionStart`, `solAttentionTau` dalla `video` solo quando `parameters.video.numFrames > 1` (i tipi sono quelli di `DrawThingsConfiguration`); per un job immagine la configurazione non cambia rispetto a oggi.
  - `JobMapper.update(for event: GenerationEvent, expected: Int, video: VideoFamilyInfo?, runsLocally: Bool) throws -> GenerationUpdate?`: con `video != nil`, `.completed` ritorna `.finishedVideo(GeneratedVideo(frames: result.images, audio: result.audio.first.map(GeneratedAudioTrack.init), framesPerSecond: info.framesPerSecond))` **senza** `finalImages`; con un solo frame, `!runsLocally` e `numFrames` richiesti > 1 lancia `BackendError.videoNotAvailable`; nessun frame lancia `.noImages`. Gli `.image` restano anteprime.
  - `JobMapper.progressSteps(stage:..., steps: Int, hiresFixStrength: Double?) ` come funzione pura: il passo del secondo passaggio (`secondPassSampling`) si somma a `steps`, e il totale con correzione ad alta risoluzione è `steps × (1 + strength)` arrotondato per eccesso.
  - `ConfigurationCodec`: le cinque chiavi diventano modellate (`modeledKeys`) e `parameters(from:base:)` le legge in `video`; non finiscono più in `extra`.

- [ ] **Step 1: Write the failing tests**:
  - `configurationCarriesVideoFields`: `video(numFrames: 124, shiftForAudio: 3, usesSolAttention: true, start 2, tau 0.5)` → `configuration.numFrames == 124`, `shiftForAudio == 3`, `usesSolAttention == true`.
  - `imageJobConfigurationIsUnchanged`: la configurazione di `GenerationParameters()` coincide con quella calcolata prima del cambio per i campi di sempre (confronta `toJSON()` con un JSON atteso per le chiavi non video).
  - `completedVideoKeepsEveryFrame`: 124 immagini sintetiche e `video: info H3` → `.finishedVideo` con 124 frame, non 1.
  - `singleFrameOnCloudIsAnError`: 1 frame, `runsLocally false`, `numFrames` richiesti 56 → lancia `.videoNotAvailable`; con `runsLocally true` ritorna un video di un frame.
  - `secondPassStepsAddToTheFirst`: `progressSteps` con 8 step, secondo passaggio step 3, strength 0,7 → passo 11 su totale 14 (8 × 1,7 = 13,6 → 14).
  - Nel codec: un JSON `{"numFrames": 56, "shiftForAudio": 5}` applicato aggiorna `video.numFrames` e `video.shiftForAudio` e non compare in `extra`.
- [ ] **Step 2: Run** `swift test --filter JobMapperVideoTests`. Atteso: FAIL. Il tipo esatto degli eventi di avanzamento (`GenerationEvent.progress`) si legge in `Packages/.build/checkouts/DrawThings-Swift`; se non si può costruire nei test, testa la funzione pura `progressSteps` e basta.
- [ ] **Step 3: Implement** le modifiche e adegua i punti di chiamata di `update(for:expected:)` (solo `DrawThingsBackend.generate`, Task 9).
- [ ] **Step 4: Run** `swift test --filter JobMapperVideoTests`, `--filter JobMapperTests`, `--filter ConfigurationCodecTests`. Atteso: PASS.
- [ ] **Step 5: Commit**: `git commit -m "feat(video): configurazione e eventi video in DTBridge"`.

---

### Task 8: Specifiche dei modelli community e catalogo locale

**Files:**
- Create: `Scripts/make-video-specs.py`, `Packages/Sources/DTBridge/VideoModelSpecs.swift` (generato dallo script)
- Modify: `Packages/Sources/DTBridge/CatalogBuilder.swift`, `Packages/Sources/DTBridge/DrawThingsBackend.swift`, `Packages/Sources/HubKit/Catalog/ModelCatalog.swift`
- Test: `Packages/Tests/DTBridgeTests/VideoModelSpecsTests.swift` (create), `Packages/Tests/DTBridgeTests/CatalogBuilderTests.swift` (modify)

**Interfaces:**
- Produces:
  - `Scripts/make-video-specs.py <community_models.json> <out.swift>`: legge il catalogo di `https://kcjerrell.github.io/dt-models/community_models.json` (scaricato a mano in un file locale: lo script non usa la rete) e scrive `VideoModelSpecs.swift` con le voci il cui `version` è `minimax_h3` o il cui `file` inizia per `fasth3_omni`, come `static let byFile: [String: String]` (file → JSON).
  - `enum VideoModelSpecs { static let byFile: [String: String]; static func data(for file: String) -> Data? }`.
  - `CatalogModel.isLocalOnly: Bool` (init con `isLocalOnly: Bool = false`; `with(source:isRemote:)` lo conserva).
  - `CatalogBuilder.cloudCatalog(...)`: un modello installato in locale la cui famiglia è un video abilitato resta nel catalogo anche se non è nei file del cloud, con `isLocalOnly = true`.
  - `DrawThingsBackend`: nell'elenco delle specifiche (`remote`) e in `specs(toRegisterFor:live:)` si aggiungono quelle di `VideoModelSpecs` per i file che le liste non hanno (le liste vincono); `registerRemoteSpec` registra la specifica incorporata di un file video quando il servizio non ne ha una (`service.modelSpecs.spec(for:) == nil`), anche per file installati, mai al posto di quella del server.

- [ ] **Step 1: Write the failing tests**:
  - `bundledSpecsCoverTheEnabledH3Files`: `VideoModelSpecs.data(for: "fasth3_omni_i4x.ckpt")` è un JSON con `version == "minimax_h3"`, `modifier == "ref2va"`, `frames_per_second == 24`, `text_encoder == "qwen_3_vl_32b_50_i8x.ckpt"`; la chiave `file` coincide con quella richiesta; esistono anche `minimax_h3_fl2va_i4x.ckpt` e `minimax_h3_ref2va_i4x.ckpt`.
  - `unknownFileHasNoSpec`: `data(for: "flux_2_klein_9b_q6p.ckpt") == nil`.
  - `localVideoModelStaysWhenNotOnCloud`: catalogo locale con `minimax_h3_ref2va_q8p.ckpt` (famiglia `minimax_h3`), `cloudFiles` senza di esso → il modello è nel risultato con `isLocalOnly == true`; un modello locale immagine fuori dal cloud resta escluso.
  - `listsWinOverBundledSpecs`: se la lista community ha `fasth3_omni_i4x.ckpt` con un nome diverso, il catalogo usa quello della lista.
- [ ] **Step 2: Run** `swift test --filter VideoModelSpecsTests`. Atteso: FAIL.
- [ ] **Step 3: Implement.** Scarica `community_models.json` in una cartella nuova e vuota fuori dal repo (con il permesso dell'utente se la sessione lo richiede), esegui lo script con `python3 -I`, controlla che il file generato contenga le voci attese e committa solo `VideoModelSpecs.swift` e lo script. Poi le modifiche al catalogo e al backend.
- [ ] **Step 4: Run** `swift test --filter VideoModelSpecsTests`, `--filter CatalogBuilderTests`, `--filter DrawThingsBackendTests`, `--filter DTPlusTests`. Atteso: PASS.
- [ ] **Step 5: Commit**: `git commit -m "feat(video): specifiche community incorporate e modelli locali"`.

---

### Task 9: Accumulo frame, ritentativo e invio (DTBridge)

**Files:**
- Create: `Packages/Sources/DTBridge/VideoStreamTools.swift`
- Modify: `Packages/Sources/DTBridge/DrawThingsBackend.swift`
- Test: `Packages/Tests/DTBridgeTests/VideoStreamToolsTests.swift` (create)

**Interfaces:**
- Consumes: `JobMapper.update(for:expected:video:runsLocally:)`, `GeneratedVideo`.
- Produces:
  - `enum VideoStreamTools`:
    - `static func isRetryable(_ error: any Error) -> Bool` — true per gli errori gRPC `INTERNAL` e `UNAVAILABLE` (il caso esatto con cui la libreria li espone si legge in `DrawThingsError`; l'`internalError` visto nelle prove è questo), false per cancellazione, `BackendError`, `unauthenticated`.
    - `struct Accumulator` con `mutating func add(_ image: CGImage)` e `func partialVideo(framesPerSecond: Double) -> GeneratedVideo?` (nil sotto 2 frame, altrimenti `isPartial: true`).
    - `static let retryDelay: Duration = .milliseconds(500)`.
  - `DrawThingsBackend.generate`: per i job video (`job.isVideo`): un solo ritentativo dopo `retryDelay` se l'errore è ritentabile e non è arrivato alcun frame; se l'errore arriva dopo almeno 2 frame, emette `.finishedVideo` parziale e termina senza errore; la cancellazione non salva né ritenta; passa `runsLocally = installedFiles.contains(job.model)` e `VideoFamilies.info(for:)` a `JobMapper.update`. I job immagine non cambiano.

- [ ] **Step 1: Write the failing tests**:
  - `retryableErrors`: un errore `INTERNAL` e uno `UNAVAILABLE` sono ritentabili; `CancellationError`, `BackendError.unauthorized` e un errore di argomento non lo sono.
  - `accumulatorBuildsAPartialVideo`: 1 frame → `nil`; 3 frame → video con 3 frame, `isPartial true`, fps passati.
  - `retryDelayIsHalfASecond`.
- [ ] **Step 2: Run** `swift test --filter VideoStreamToolsTests`. Atteso: FAIL.
- [ ] **Step 3: Implement** gli strumenti e il ciclo in `generate`. Il flusso reale non si prova con un test automatico (`DrawThingsService` è concreto): si prova a mano nel Task 12.
- [ ] **Step 4: Run** `swift test --filter VideoStreamToolsTests` e `swift test` completo in `Packages`. Atteso: PASS.
- [ ] **Step 5: Commit**: `git commit -m "feat(video): ritentativo e video parziale"`.

---

### Task 10: Card "Video Settings" e "Accelerator Settings"

**Files:**
- Create: `App/Generation/Cards/VideoSettingsCard.swift`, `App/Generation/Cards/AcceleratorCard.swift`
- Modify: `App/MainWindow/GenerationTabView.swift`, `App/Generation/Advanced/AdvancedSection.swift`, `App/Localizable.xcstrings`, `App/MainWindow/ModelPickerView.swift`
- Test: `Packages/Tests/CatalogTests` (esistente, verifica le traduzioni) e prova a mano nel Task 12

**Interfaces:**
- Consumes: `VideoFamilies.info(for:)`, `VideoFamilyInfo.step/seconds`, `GenerationParameters.video`, `AdvancedField.isInVideoCards`, `CatalogModel.isLocalOnly`, e il modo in cui `ControlStore` dice se c'è un'immagine iniziale (da trovare in `Packages/Sources/HubCore/Control/ControlStore.swift`).
- Produces: due viste `VideoSettingsCard(controller:connection:)` e `AcceleratorCard(controller:connection:)`, visibili solo con un modello di famiglia video abilitata (la seconda solo con `usesAccelerators`); posto in `GenerationTabView` dopo la riga Campionamento/LoRA e prima di `AdvancedSection`. `AdvancedSection.visibleCards` e il suo avviso dei valori nascosti ignorano i campi per cui `isInVideoCards` è true.

- [ ] **Step 1: Write the failing check**: aggiungi le chiavi di stringa usate dalle viste a `App/Localizable.xcstrings` con la traduzione `en` e `it`: `card.video`, `card.video.frames`, `card.video.frames.seconds` (formato `%@ s`), `card.video.audioShift`, `card.video.stochastic`, `card.video.compression`, `card.video.compressionQuality`, `card.video.imageToVideo`, `card.accelerators`, `card.accelerators.sol`, `card.accelerators.sol.start`, `card.accelerators.sol.tau`, `card.accelerators.sol.help`, `card.accelerators.teacache`, `card.accelerators.teacache.start`, `.end`, `.threshold`, `.skip`, `card.accelerators.teacache.help`, `model.local`. I testi dei tooltip sono le descrizioni mostrate dall'app Draw Things per Sol Attention e TeaCache (in inglese e tradotte in italiano). Lancia `swift test --filter CatalogTests`: i controlli sulla copertura delle traduzioni devono restare verdi.
- [ ] **Step 2: Implement `VideoSettingsCard`**: stesso stile di `SamplingCard` (`DSCollapsibleCard`, `CardRow`). Righe: numero di frame (`Stepper`/campo che passa da `VideoFamilyInfo.step` e `snap` a fine modifica) con accanto solo la stima, ad esempio "5,2 s" (secondi con una cifra decimale, nella lingua dell'utente); Audio Shift (solo `usesAudioShift`); Strategic Stochastic Sampling (solo `usesStochasticSampling` e sampler TCD/TCD Trailing); Compression Artifacts con la qualità quando non è `none` (tutti i video); l'etichetta "Immagine → video" quando c'è un'immagine iniziale.
- [ ] **Step 3: Implement `AcceleratorCard`**: due blocchi con checkbox `DSCheckboxToggleStyle`; con Sol Attention attivo compaiono i campi numerici Start Step e Tau; con TeaCache attivo Start, End, Threshold, Max Skip Steps (campi numerici come `IntField`/`DecimalField`, non slider). Entrambi legati a `controller.parameters.video` e `controller.parameters.advanced.teaCache*`. L'etichetta `model.local` appare nel selettore accanto ai modelli con `isLocalOnly`.
- [ ] **Step 4: Build**: `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build`. Atteso: BUILD SUCCEEDED. Poi `swift test --filter CatalogTests`. Atteso: PASS.
- [ ] **Step 5: Commit** dei file per nome: `git commit -m "feat(video): card Video Settings e Accelerator Settings"`.

---

### Task 11: Risultati video: badge, lettore, export

**Files:**
- Create: `App/Results/VideoPlayerView.swift`
- Modify: `App/Results/ResultsView.swift`, `App/Results/ResultInfoSidebar.swift`, `App/Localizable.xcstrings`
- Test: `Packages/Tests/CatalogTests` e prova a mano nel Task 12

**Interfaces:**
- Consumes: `GeneratedImage.videoURL`, `videoSeconds`, `isPartialVideo`, `ResultInfo.Field.frames/.duration/.partial`.
- Produces: `VideoPlayerView(url: URL)` (`NSViewRepresentable` su `AVPlayerView`, ripetizione automatica, controlli in linea, audio attivo, si ferma quando la vista sparisce); in `ResultsView` la miniatura di un video ha un piccolo badge (icona play più durata, ad esempio "5 s"); l'immagine grande di un risultato con `videoURL` mostra il lettore al posto della copertina; il trascinamento dalla striscia e "Mostra nel Finder" usano l'MP4; un risultato parziale mostra la nota "Video parziale". Nessun lettore se `videoURL == nil` (resta la copertina, senza badge).

- [ ] **Step 1: Add strings** (`en` + `it`): `results.video.badge` (formato con i secondi), `results.video.partial`, `results.info.frames`, `results.info.duration`, `results.info.partial`. `swift test --filter CatalogTests` verde.
- [ ] **Step 2: Implement** `VideoPlayerView` e i punti d'uso in `ResultsView` (area immagine, striscia, azioni) e le etichette nella barra laterale delle informazioni.
- [ ] **Step 3: Build** (comando del Task 10). Atteso: BUILD SUCCEEDED.
- [ ] **Step 4: Run** `swift test --filter CatalogTests`. Atteso: PASS.
- [ ] **Step 5: Commit**: `git commit -m "feat(video): badge, lettore ed export nei risultati"`.

---

### Task 12: Stima CU, README e prova reale

**Files:**
- Modify: i punti in `Packages/Sources/HubCore/ComputeUnits/` e `Packages/Sources/HubKit/ComputeUnits/` che calcolano la stima per un job (trovali con `grep -rn "estimate" Packages/Sources/HubCore/ComputeUnits Packages/Sources/HubKit/ComputeUnits Packages/Sources/DTBridge/ComputeUnits`), `README.md`
- Test: `Packages/Tests/HubCoreTests/CUPlannerTests.swift` (modify)

**Interfaces:**
- Produces: per un job con `isVideo == true` il calcolatore non dà alcuna stima (il misuratore non mostra la riga); i job immagine restano com'erano.

- [ ] **Step 1: Write the failing test**: un job con `videoFPS 24` non produce una stima; un job immagine identico per il resto sì.
- [ ] **Step 2: Run** `swift test --filter CUPlannerTests`. Atteso: FAIL.
- [ ] **Step 3: Implement** l'esclusione e aggiungi al `README.md` una nota che dichiara che il supporto ai modelli video è ancora in sviluppo e che alcune funzioni potrebbero non funzionare come previsto.
- [ ] **Step 4: Run** `swift test` completo in `Packages`, poi la build dell'app. Atteso: tutto PASS e BUILD SUCCEEDED.
- [ ] **Step 5: Commit**: `git commit -m "feat(video): nessuna stima CU per i video, nota nel README"`.
- [ ] **Step 6: Prova manuale sul cloud DT+** (l'utente deve avere il server gRPC attivo sulla porta 7859; i `internalError` casuali si riprovano): (a) H3 ref2va i4x: valori predefiniti, 56 frame, il risultato è un video con audio nella striscia; (b) H3 fl2va i4x; (c) FastH3 Omni i4x, 124 frame, 8 step, il video non è rumore (verifica che la specifica incorporata arrivi nella richiesta); (d) LTX-2.3 con i valori predefiniti del Task 3 — se la correzione ad alta risoluzione non funziona, riporta il valore predefinito a 768×448 senza correzione e 25 frame (la configurazione provata) e annotalo; (e) immagine nella scheda Control: la richiesta è I2V; (f) Stop a metà: nessun risultato salvato; (g) riavvio dell'app: il video torna nella striscia con badge; cestino: spariscono PNG e MP4. Annota gli esiti in fondo alla spec, nella sezione dei risultati delle prove.
- [ ] **Step 7: Prova manuale in locale**: con almeno un modello H3 scaricato in locale (q8p o i8x) verifica che compaia con l'etichetta "locale", che generi un video e non dia l'errore "un solo frame". Annota l'esito nella spec; se non funziona, descrivi il sintomo in un messaggio all'utente invece di cambiare il design.
