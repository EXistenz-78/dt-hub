# Plug-in Tiled Upscale e pipeline guidata — Piano di implementazione

> **Per chi esegue:** SOTTO-SKILL OBBLIGATORIA: `superpowers:subagent-driven-development` (consigliata) oppure `superpowers:executing-plans`. I passi usano le caselle (`- [ ]`).

**Obiettivo:** un plug-in può guidare una pipeline passo dopo passo (l'app chiede il passo successivo, esegue, restituisce il risultato); il primo a usarla è Tiled Upscale (2×/4×/8× per tile con maschere, sovrapposizione 256 o 320).

**Architettura:** `HubKit` descrive i messaggi e il passo autonomo; `HubCore` ha il ciclo della sessione (`GuidedSessionDriver`, testabile con finti) e il registro che parla con il plug-in; `GenerationController` (app) estrae l'esecuzione di un passo e la usa per le pipeline statiche e per quelle guidate. Il plug-in ha un modulo puro (`TileGrid`) e uno per le immagini, separati dalla vista.

**Tecnologie:** Swift 6.2, Swift Testing, CoreGraphics/ImageIO, SwiftUI/AppKit, `PluginKit` (moduleAliases), xcodebuild per l'app.

**Spec:** `docs/superpowers/specs/2026-10-18-plugin-tiled-upscale-design.md` (la spec prevale).

## Vincoli globali

- Ramo `feat/tiled-upscale` (base `main` 0.3.1). **Niente unione, push o release senza via libera esplicito.** File aggiunti **per nome**, mai `git add -A`.
- Commenti in inglese; testi dell'app e del plug-in in italiano e inglese (`Localizable.xcstrings` per l'app, tabella `L` per il plug-in; `LocalizationCatalogTests` deve restare verde).
- Dimensioni dei tile e dei passi sempre multipli di 64; tile 1024; sovrapposizioni ammesse **256 (predefinita) e 320**; margine libero della maschera = `round(overlap · 25/32)` (200 / 250); costanti in un solo punto (`TileConstants`).
- Fattori 2, 4, 8; limiti: rifiuto oltre 16 384 px per lato o 268 megapixel, avviso oltre 100 passi o 100 megapixel.
- Preset FLUX.2 klein 9B: 4 passi, guidance 1, forza 1, sampler 16, shift 3, LoRA `f2_ultra_real_v5_pro_lora_f16` (peso predefinito 1, regolabile), Sfumatura 30, Margine 30, Conserva originale; prompt = trigger word del LoRA + ` ALSO PRESERVE COLORS AND LUMINOSITY`.
- Il plug-in non cambia mai il modello (resta quello dell'header), richiede un modello edit (`requiresEditModel: true`), niente rete.
- Convenzione della maschera nel contratto: PNG con la dimensione del tile, **255 (alpha o bianco) dove il modello rigenera**, come `MaskBitmap`. L'app la converte in `GenerationInputs.mask` (trasparente = rigenerato).
- Le pipeline statiche di oggi non cambiano comportamento.

## Review Focus

1. Immagine già in base 64: nessun ritaglio; non in base 64: ritaglio centrato di al massimo 63 px per lato (Task 1).
2. Lato ≤ 1024: un solo tile, senza maschera (Task 1).
3. L'ultimo tile resta largo più della sovrapposizione e multiplo di 64, con 256 e con 320 (Task 1).
4. Il plug-in risponde con un passo non valido (file mancante, `size` non multiplo di 64 o fuori limite, maschera di dimensione diversa dal tile): la sessione chiude con `failed` e il motivo (Task 2 e 3).
5. Stop a metà di un passo: nessun `session.next` dopo, `session.end` con `stopped` (Task 3).
6. Il plug-in non risponde (timeout) o sparisce: sessione chiusa con `closed` e un avviso, nessun blocco della RUN (Task 3 e 4).
7. Una pipeline statica o dell'utente si esegue come prima (Task 5).

---

### Task 1: Pacchetto del plug-in e `TileGrid`

**Files:**
- Create: `Plugins/TiledUpscale/Package.swift` (come `Plugins/DepthPose/Package.swift`: prodotto dinamico `TiledUpscale`, `moduleAliases` `TiledUpscaleKit` / `TiledUpscaleDesign`, test target `TiledUpscaleTests`)
- Create: `Plugins/TiledUpscale/Sources/TiledUpscale/TileGrid.swift`, `TileLimits.swift`
- Test: `Plugins/TiledUpscale/Tests/TiledUpscaleTests/TileGridTests.swift`, `TileLimitsTests.swift`

**Interfaces:**
- Produces:
  - `enum TileConstants { static let tile = 1024; static let freeFactor = 25.0 / 32.0 }`
  - `enum TileOverlap: Int, CaseIterable, Sendable { case standard = 256, wide = 320 }` con `var step: Int` (`1024 − rawValue`) e `var free: Int` (`Int((Double(rawValue) * TileConstants.freeFactor).rounded())`: 200 / 250)
  - `struct TileRect: Equatable, Sendable { var x, y, width, height: Int }`
  - `struct ScaledSize: Equatable { let width, height: Int; let cropLeft, cropTop: Int }` e `static func TileGrid.scaledSize(width: Int, height: Int, factor: Int) -> ScaledSize` (ingrandimento intero poi ritaglio centrato a multipli di 64; il pixel in più a destra/in basso)
  - `struct Tile: Equatable, Sendable { let index: Int; let row: Int; let column: Int; let rect: TileRect; let maskRect: TileRect? }` (`maskRect` nelle coordinate del tile; `nil` per il primo tile)
  - `struct TilePlan: Equatable, Sendable { let width, height: Int; let overlap: TileOverlap; let tiles: [Tile]; var columns: Int; var rows: Int; var count: Int }` e `static func TileGrid.plan(width: Int, height: Int, overlap: TileOverlap) -> TilePlan` (`width`/`height` = immagine già ritagliata)
  - `enum TileLimits { enum Verdict: Equatable { case ok, warn, refuse } static func verdict(width: Int, height: Int, passes: Int) -> Verdict }`

- [ ] **Step 1: Test di `TileGrid`** (nomi e asserzioni, con i valori della spec):
  - `scaledSizeKeepsAMultipleOf64`: `scaledSize(width: 1024, height: 768, factor: 4)` → 4096 × 3072, crop 0/0.
  - `scaledSizeCropsToTheNearestLowerMultipleOf64Centered`: `scaledSize(width: 1000, height: 1000, factor: 2)` → 1984 × 1984 (da 2000), `cropLeft == 8`, `cropTop == 8`; con resto dispari (`width 1001, factor 2` → 2002 → 1984, resto 18, `cropLeft == 9`); con resto 63 (`scaledSize(width: 2047, height: 64, factor: 1)`) il pixel in più va a destra (`cropLeft == 31`).
  - `oneTileWhenTheSideIsAtMost1024`: `plan(width: 1024, height: 1024, overlap: .standard).count == 1` e `tiles[0].maskRect == nil`; `plan(width: 640, height: 512, …)` un tile 640 × 512.
  - `columnsStartAtMultiplesOfTheStep`: con `.standard`, `plan(width: 2560 + 128, height: 1024, …)` → colonne `x` = 0, 768, 1536, 2304; l'ultima `width == 2688 − 2304 == 384` (cioè `256 + Z`, Z = 128); con `.wide` il passo è 704 e `x` = 0, 704, 1408, 2112.
  - `lastTileIsWiderThanTheOverlapAndAMultipleOf64`: per tutti i lati multipli di 64 tra 1088 e 8192 e per entrambe le sovrapposizioni, ogni tile ha larghezza e altezza multiple di 64 e l'ultima è `> overlap.rawValue` e ≤ 1024.
  - `tilesAreRowMajor`: indici e (riga, colonna) in ordine `1A, 1B, …, 2A`.
  - `maskRectsFollowTheFourCases` (con `free` = 200 per `.standard` e 250 per `.wide`): primo tile `nil`; resto della prima riga `TileRect(x: free, y: 0, width: w − free, height: h)`; resto della prima colonna `TileRect(x: 0, y: free, width: w, height: h − free)`; tutti gli altri `TileRect(x: free, y: free, width: w − free, height: h − free)`; con l'ultimo tile largo 320 e `.standard` la maschera è larga 120.
  - `countMatchesTheSpecExample`: `plan(width: 8192, height: 8192, .standard).count == 121` e `.wide` → 144.
- [ ] **Step 2: Test di `TileLimits`:** `verdict(width: 16_384, height: 16_384, passes: 10) == .warn` (268 435 456 px = il limite: **rifiuto** solo se `> 268_435_456` px o un lato `> 16_384`; sopra 100 megapixel è avviso); `verdict(width: 16_384, height: 16_448, passes: 10) == .refuse`; `verdict(width: 2048, height: 2048, passes: 101) == .warn`; `verdict(width: 2048, height: 2048, passes: 12) == .ok`; `verdict(width: 16_448, height: 64, passes: 1) == .refuse`.
- [ ] **Step 3: Eseguire per vedere il fallimento:** `cd Plugins/TiledUpscale && swift test 2>&1 | grep -E "Test run with|error:"` → errore di compilazione (tipi non definiti).
- [ ] **Step 4: Implementare** i tipi sopra in `TileGrid.swift` e `TileLimits.swift`. Aritmetica solo su interi; `plan` calcola `n` per lato con `n = side ≤ 1024 ? 1 : ceil((side − 1024) / step) + 1`.
- [ ] **Step 5: Eseguire** lo stesso comando: tutti verdi.
- [ ] **Step 6: Commit** — `feat(tiled-upscale): geometria dei tile e limiti` (Package.swift, i due sorgenti e i due test, per nome).

### Task 2: Contratto in `HubKit` (pipeline guidata, passo autonomo, messaggi di sessione)

**Files:**
- Modify: `Packages/Sources/HubKit/Plugin/PluginContribution.swift` (`PipelineStep`, `PluginPipeline`, parsing in `PluginContribution.init(message:)`), `Packages/Sources/HubKit/Plugin/PluginMessages.swift` (`PluginMessageType`)
- Create: `Packages/Sources/HubKit/Plugin/PluginSession.swift`
- Test: `Packages/Tests/HubKitTests/GuidedPipelineContractTests.swift`

**Interfaces:**
- Consumes: `PluginImageRef`, `MaskSettings` (`HubKit/Control/ControlInputs.swift`), `FieldOverlay`, `LoRASelection`.
- Produces:
  - `PluginMessageType.sessionNext = "session.next"`, `.sessionEnd = "session.end"`.
  - `struct PipelineSize: Equatable, Sendable { var width: Int; var height: Int }`.
  - `PipelineStep` guadagna `mask: PluginImageRef?`, `maskSettings: MaskSettings?`, `size: PipelineSize?` (tutti facoltativi, nell'`init` con default `nil`; letti dal JSON di un passo solo per i passi guidati).
  - `struct GuidedPipeline: Equatable, Sendable { var passes: Int; var estimate: PipelineStep }`.
  - `PluginPipeline.guided: GuidedPipeline?` (campo nuovo, `init(name:steps:guided:)` con `guided` a `nil`) e `var passCount: Int` (`guided?.passes ?? steps.count`).
  - `enum PluginSessionReason: String, Sendable { case finished, stopped, failed, closed }`.
  - `struct SessionNextRequest: Sendable { var index: Int; var count: Int; var previous: SessionPrevious? ; func data() -> Data }` con `struct SessionPrevious: Sendable { var path: String; var width: Int; var height: Int }`; `static func PluginSession.endMessage(_ reason: PluginSessionReason) -> Data`.
  - `enum SessionAnswer: Equatable, Sendable { case pass(PipelineStep); case done; case invalid(String); static func parse(_ data: Data?, tileLimit: Int) -> SessionAnswer }`: `nil` o JSON non letto → `.invalid("no answer")`; `{"done":true}` → `.done`; altrimenti un passo con `startImage`, `size` presente, `size` multiplo di 64 e `1…tileLimit`, altrimenti `.invalid(motivo)`.

- [ ] **Step 1: Test** (nomi e asserzioni):
  - `readsAGuidedPipelineWithNoSteps`: `contribute` con `"pipeline": {"name": "Tiled Upscale", "guided": true, "passes": 12, "estimate": {…}}` → `pipeline.guided?.passes == 12`, `pipeline.steps.isEmpty`, `passCount == 12`.
  - `ignoresAGuidedPipelineWithoutPasses`: `passes` 0 o assente → `pipeline == nil` (e il messaggio resta vuoto se non c'è altro).
  - `aStaticPipelineKeepsItsPassCount`: tre passi → `passCount == 3`, `guided == nil`.
  - `readsTheAutonomousPass`: risposta con `startImage`, `mask`, `maskSettings {"blur":30,"outset":30,"preserveOriginal":true}`, `size {1024,1024}`, `preset`, `fields`, `loras`, `strength 1` → `.pass(step)` con tutti i campi.
  - `rejectsASizeThatIsNotAMultipleOf64`: `size {1000, 1024}` → `.invalid`; `size {2112, 64}` con `tileLimit: 2048` → `.invalid`; senza `startImage` → `.invalid`.
  - `doneAnswer`: `{"done":true}` → `.done`; `nil` → `.invalid`.
  - `nextRequestCarriesThePreviousFile`: `SessionNextRequest(index: 3, count: 12, previous: …).data()` ha `type == "session.next"`, `index 3`, `count 12`, `previous.path`; senza `previous` la chiave manca.
  - `endMessageNamesTheReason`: `PluginSession.endMessage(.stopped)` → `{"type":"session.end","reason":"stopped"}`.
  - `existingPipelineParsingIsUnchanged`: una pipeline statica senza i campi nuovi si legge come prima (`mask`, `maskSettings`, `size` e `guided` sono `nil`); i test già esistenti di `PluginContribution` restano verdi.
- [ ] **Step 2: Eseguire** `cd Packages && swift test --filter GuidedPipelineContract 2>&1 | grep -E "Test run with|error:"` → fallisce (tipi mancanti).
- [ ] **Step 3: Implementare** i tipi e il parsing. `PluginContribution.init(message:)`: una pipeline con `guided: true` e `passes ≥ 1` diventa `PluginPipeline(name:, steps: [], guided: GuidedPipeline(passes:, estimate: PipelineStep(object["estimate"])))`; senza `estimate` vale `PipelineStep()`.
- [ ] **Step 4: Eseguire** `swift test --filter "GuidedPipelineContract|PluginContribution"` → verdi; poi `swift test --filter HubKit` per i test già esistenti.
- [ ] **Step 5: Commit** — `feat(hubkit): contratto della pipeline guidata dal plug-in` (i tre file sorgente e il test, per nome).

### Task 3: Ciclo della sessione (`GuidedSessionDriver`) in `HubCore`

**Files:**
- Create: `Packages/Sources/HubCore/Plugins/GuidedSessionDriver.swift`
- Test: `Packages/Tests/HubCoreTests/GuidedSessionDriverTests.swift`

**Interfaces:**
- Consumes: `SessionNextRequest`, `SessionAnswer`, `PluginSession.endMessage`, `PluginSessionReason` (Task 2), `PipelineStep`.
- Produces:
  - `enum PassOutcome: Equatable, Sendable { case made(URL, width: Int, height: Int), stopped, failed(String) }`
  - `enum GuidedOutcome: Equatable, Sendable { case finished, stopped, failed(String), closed }`
  - `@MainActor final class GuidedSessionDriver { init(passes: Int, tileLimit: Int, ask: @escaping (Data) async -> Data?, runPass: @escaping (PipelineStep, _ index: Int) async -> PassOutcome, end: @escaping (Data) async -> Void, progress: @escaping (_ index: Int, _ count: Int) -> Void = { _, _ in }); func run() async -> GuidedOutcome }`

Comportamento: per `index` in `1…passes`: `progress`, `ask(SessionNextRequest(...).data())` (con `previous` dal passo prima), `SessionAnswer.parse`; `.done` → `finished` (con `end(.finished)`); `.invalid(m)` → `failed(m)` con `end(.failed)`; `.pass(step)` → `runPass`; `.stopped` → `stopped` (con `end(.stopped)`); `.failed(m)` → `failed(m)`; senza risposta (`ask` restituisce `nil`) → `closed` con `end(.closed)`; `Task.isCancelled` prima di un passo → `stopped`. Dopo l'ultimo passo `finished`. `end` è chiamato **una sola volta** per sessione.

- [ ] **Step 1: Test** (con finti `ask`, `runPass`, `end`):
  - `runsEveryPassInOrderAndEndsFinished`: 3 passi → `runPass` chiamato con indici 1, 2, 3, `ask` riceve `previous.path` del risultato del passo prima (assente al primo), `end` una volta con `finished`, esito `.finished`.
  - `doneEndsTheSessionEarlyWithoutError`: la risposta del 2° passo è `{"done":true}` → 1 passo eseguito, `.finished`.
  - `invalidAnswerFailsWithTheReason`: risposta con `size` 1000 → `.failed(motivo)`, nessun passo eseguito dopo, `end(.failed)` una volta.
  - `stopDuringAPassEndsStoppedAndAsksNoMore`: `runPass` restituisce `.stopped` al passo 2 → `ask` chiamato 2 volte, `end(.stopped)`, `.stopped`.
  - `failedPassStopsEverything`: `.failed("boom")` → `.failed("boom")`, `end(.failed)`.
  - `noAnswerClosesTheSession`: `ask` restituisce `nil` → `.closed`, `end(.closed)`, nessun passo eseguito.
  - `cancellationBeforeAPassStops`: task annullato dopo il passo 1 → `.stopped`, `end(.stopped)`.
  - `reportsProgress`: `progress` chiamato con (1, 3), (2, 3), (3, 3).
- [ ] **Step 2: Eseguire** `swift test --filter GuidedSessionDriver 2>&1 | grep -E "Test run with|error:"` → fallisce.
- [ ] **Step 3: Implementare** il ciclo come descritto (nessuna dipendenza da `PluginRegistry` né dall'app).
- [ ] **Step 4: Eseguire** lo stesso comando → verdi.
- [ ] **Step 5: Commit** — `feat(core): ciclo della sessione guidata dal plug-in`.

### Task 4: Registro, `ContributionStore` e misuratore dei CU per la pipeline guidata

**Files:**
- Modify: `Packages/Sources/HubCore/Plugins/PluginRegistry.swift` (nuovo `request`), `Packages/Sources/HubCore/Plugins/ContributionStore.swift` (righe ~210–215 e 234–235: `.passes(proposed.passCount)`; `forget` invariato), `Packages/Sources/HubCore/ComputeUnits/CUPlanner.swift` (la riga 41–52: una pipeline guidata genera `passCount` richieste uguali alla stima), `PluginHost/BundlePluginLoader.swift` (solo se `send` ha un timeout fisso: vedi step 1)
- Test: `Packages/Tests/HubCoreTests/PluginRegistrySessionTests.swift`, `ContributionStoreGuidedTests.swift`, `CUPlannerGuidedTests.swift`

**Interfaces:**
- Consumes: `PluginPipeline.guided`, `.passCount` (Task 2), `PluginHosting.send(_:) async -> Data?`.
- Produces: `PluginRegistry.request(_ message: Data, to pluginID: String, timeout: Duration) async -> Data?` (nil se il plug-in non è caricato o non risponde entro `timeout`); `PluginRegistry.sessionFolder(for pluginID: String) -> URL` (sottocartella nuova dentro il `tempFolder` del plug-in, creata se manca) e `func removeSessionFolder(_ url: URL)`.

- [ ] **Step 1: Leggere** `BundlePluginLoader.swift:56` e capire il timeout con cui `send` aspetta la risposta del plug-in; se è fisso e breve, aggiungere un parametro `timeout` (60 s per `session.next`).
- [ ] **Step 2: Test:**
  - `requestReturnsThePluginsAnswer` e `requestReturnsNilForAnUnknownPlugin` (con un `PluginHosting` finto);
  - `requestTimesOutAndReturnsNil`: plug-in finto che non risponde, `timeout: .milliseconds(50)` → `nil`;
  - `sessionFolderIsCreatedInsideTheTempFolderAndRemoved`;
  - `contributionStoreHoldsAGuidedPipeline`: `receive` di una pipeline guidata → `pipeline?.pipeline.passCount == 12` e il conflitto con un'altra pipeline mostra `.passes(12)`;
  - `cuPlannerMeasuresEachGuidedPassAsTheEstimate`: pipeline guidata con `passes: 5` e `estimate` con 4 passi → 5 richieste con `steps == 4`.
- [ ] **Step 3: Eseguire** `swift test --filter "PluginRegistrySession|ContributionStoreGuided|CUPlannerGuided"` → fallisce.
- [ ] **Step 4: Implementare:** `request` con `withTaskGroup` (la risposta contro un `Task.sleep`); `sessionFolder` con un nome `session-<UUID>`; gli altri due punti usano `passCount`.
- [ ] **Step 5: Eseguire** i test del passo 3 e poi `swift test --filter "ContributionStore|CUPlanner|PluginRegistry"` → verdi.
- [ ] **Step 6: Commit** — `feat(core): registro e CU per la pipeline guidata`.

### Task 5: L'app esegue un passo guidato

**Files:**
- Create: `Packages/Sources/HubCore/Plugins/GuidedPassInputs.swift`
- Modify: `App/Generation/GenerationController.swift` (`runPipeline`: estrarre `runPass`; ramo guidato), `Packages/Sources/HubCore/Plugins/PipelineInputs.swift` (nulla se basta `GuidedPassInputs`)
- Test: `Packages/Tests/HubCoreTests/GuidedPassInputsTests.swift`

**Interfaces:**
- Consumes: `PipelineStep.startImage`/`mask`/`maskSettings`/`size` (Task 2), `GenerationInputs` (`HubKit/Control/ControlInputs.swift`), `PNGImageStore.image(at:maxPixel:)`, `GuidedSessionDriver` (Task 3), `PluginRegistry.request`/`sessionFolder` (Task 4).
- Produces: `enum GuidedPassInputs { static func inputs(for step: PipelineStep, base: GenerationInputs) -> Result<GenerationInputs, GuidedPassError> }` dove `GuidedPassError` ha `.imageUnreadable`, `.maskUnreadable`, `.maskSize(expected: PipelineSize, got: PipelineSize)`: l'immagine di partenza è il PNG del passo (nessun ricampionamento: deve avere `size`), la maschera è un `CGImage` della stessa dimensione con **alpha 0 dove il PNG è ≥ 128** (rigenerato) e opaca altrove (convenzione di `GenerationInputs.mask`); gli ingressi della scheda Control (maschera, Moodboard) **non** si usano, tranne `enableInpainting` di `base`.

- [ ] **Step 1: Test di `GuidedPassInputs`:**
  - `usesTheStepImageAndNoControlMask`: `base` con una maschera della scheda → il risultato ha l'immagine del passo e `mask == nil` se il passo non porta maschera.
  - `convertsTheMaskPNGToTheGenerationConvention`: PNG 4 × 4 con 255 nella metà destra → il `CGImage` ha alpha 0 a destra e 255 a sinistra.
  - `rejectsAMaskOfAnotherSize`: maschera 512 × 512 con `size` 1024 × 1024 → `.failure(.maskSize(…))`.
  - `rejectsAnUnreadableImage` → `.failure(.imageUnreadable)`.
  - `keepsEnableInpaintingFromTheBase`.
- [ ] **Step 2: Eseguire** `swift test --filter GuidedPassInputs 2>&1 | grep -E "Test run with|error:"` → fallisce.
- [ ] **Step 3: Implementare `GuidedPassInputs`.**
- [ ] **Step 4: Verificare nel codice** (e annotarlo in una riga di commento del commit): come `JobMapper`/`JobComposer` usano `maskSettings` (oggi sempre quelle della scheda) e come `imageStrength`/`moodboardCount` si ricavano; il passo guidato deve passare le **sue** `maskSettings` (Sfumatura 30, Margine 30, Conserva) e la sua forza.
- [ ] **Step 5: Estrarre `runPass`** da `runPipeline`: una funzione privata `runPass(_ pass: PipelineStep, index: Int, …) async -> PassOutcome` con il corpo attuale del ciclo; per un passo statico lascia identico il comportamento (stessi input, stessa dimensione dalla scheda o dal preset); per un passo guidato usa `GuidedPassInputs`, imposta `used.parameters.width/height` da `step.size` (le dimensioni dei campi restano ignorate), il modello è quello dell'header e passa le `maskSettings` del passo. `runPipeline` chiama `runPass` per ogni passo di `pipeline.steps`.
- [ ] **Step 6: Ramo guidato.** Se la pipeline tenuta è guidata, `runPipeline` crea un `GuidedSessionDriver` con: `ask` = `registry.request(…, to: pluginID, timeout: 60 s)`; `runPass` che chiama `runPass` e, a passo riuscito, copia il PNG del risultato in `registry.sessionFolder(for:)/pass-<i>.png`; `end` = `registry.request(PluginSession.endMessage($0), …)`; `progress` aggiorna `pipelinePass`. Prima di ogni passo controlla che il modello dell'header non sia cambiato (altrimenti `closed`). Il risultato intermedio **non** va nella striscia dei Risultati (a fine sessione il plug-in manda l'immagine composta). Alla fine, `removeSessionFolder`. Le opzioni di Stop esistenti (`stop()`) annullano il task e mandano `session.end` con `stopped`.
- [ ] **Step 7: Verifica:** `cd Packages && swift test --filter "GuidedPassInputs|GuidedSessionDriver|Pipeline"` verdi; `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"` → `BUILD SUCCEEDED`; `swift test` completo in `Packages/` verde (le pipeline statiche non sono cambiate).
- [ ] **Step 8: Commit** — `feat(app): esecuzione di un passo guidato dal plug-in` (file per nome).

### Task 6: Immagini del plug-in (`TUImage`)

**Files:**
- Create: `Plugins/TiledUpscale/Sources/TiledUpscale/TUImage.swift`
- Test: `Plugins/TiledUpscale/Tests/TiledUpscaleTests/TUImageTests.swift`

**Interfaces:**
- Consumes: `TileRect`, `ScaledSize` (Task 1).
- Produces (`enum TUImage`, tutte su `CGImage` RGBA 8 bit sRGB):
  - `static func scaledAndCropped(_ image: CGImage, factor: Int, size: ScaledSize) -> CGImage?` (ingrandimento **bilineare** a `width·factor × height·factor`, poi ritaglio di `size.width × size.height` a partire da `(cropLeft, cropTop)`).
  - `static func crop(_ image: CGImage, _ rect: TileRect) -> CGImage?`
  - `static func paste(_ tile: CGImage, into canvas: inout CGContext, at rect: TileRect)` oppure un tipo `Canvas` con `init?(width:height:)`, `paste(_:at:)`, `image() -> CGImage?` (l'immagine intera di lavoro).
  - `static func maskPNG(width: Int, height: Int, masked: TileRect?) -> Data?` (255 nel rettangolo, 0 fuori; `nil` → tutto 0).
  - `static func pngData(_ image: CGImage) -> Data?`

- [ ] **Step 1: Test:** `scaledAndCroppedHasTheExpectedSize` (1000 × 1000 ×2 → 1984 × 1984); `cropReturnsTheRect`; `pasteDoesNotShiftPixels`: incolla un tile 64 × 64 con un pixel colorato in (10, 20) a `(128, 192)` → il canvas ha quel pixel in (138, 212) e il resto invariato; `maskPNGHas255InsideAndZeroOutside` (decodifica il PNG e controlla un pixel dentro, uno fuori e le dimensioni); `maskPNGWithNilIsAllZero`.
- [ ] **Step 2: Eseguire** `cd Plugins/TiledUpscale && swift test --filter TUImage 2>&1 | grep -E "Test run with|error:"` → fallisce.
- [ ] **Step 3: Implementare** con CoreGraphics (`interpolationQuality = .medium` per il bilineare; il canvas è un `CGContext` RGBA).
- [ ] **Step 4: Eseguire** → verdi.
- [ ] **Step 5: Commit** — `feat(tiled-upscale): operazioni sulle immagini`.

### Task 7: Sessione del plug-in (messaggi, preset, prompt)

**Files:**
- Create: `Plugins/TiledUpscale/Sources/TiledUpscale/TUSession.swift`, `TUPreset.swift`, `TUMessages.swift`
- Test: `Plugins/TiledUpscale/Tests/TiledUpscaleTests/TUSessionTests.swift`, `TUPresetTests.swift`

**Interfaces:**
- Consumes: `TilePlan`, `TileGrid`, `TUImage` (Task 1 e 6); formato dei messaggi del Task 2 (il plug-in ha il suo parsing, tollerante, in `TUMessages`).
- Produces:
  - `struct TUPresetTable` con `static func preset(forModel file: String) -> TUPreset?` (per ora solo `flux_2_klein_9b…`: i file `flux_2_klein_9b_f16.ckpt` e le sue varianti che DT Hub riconosce come FLUX.2 klein 9B; Qwen 2.1 assente) e `struct TUPreset { name: String ("TUP · FLUX.2 klein 9B"); fields: [String: Any]; loraFile: String; defaultLoRAWeight: Double }`.
  - `static func TUPrompt.text(trigger: String) -> String` (= trigger + `" ALSO PRESERVE COLORS AND LUMINOSITY"`, con un solo spazio se il trigger è vuoto: solo la frase).
  - `final class TUSession { init(source: CGImage, factor: Int, overlap: TileOverlap, loraWeight: Double, trigger: String, preset: TUPreset, tempFolder: URL); var plan: TilePlan; func next(_ request: SessionNextRequestData) -> Data (JSON del passo autonomo o {"done":true}); func end(_ reason: String) -> CGImage? (l'immagine composta se la ragione è "finished", altrimenti nil) }`.
  - `SessionNextRequestData`: `index`, `count`, `previous: (path, width, height)?` letti da `TUMessages.parseNext(_:)`.

Comportamento di `next`: se c'è `previous` e un tile in corso, lo incolla nell'immagine di lavoro (tutto il tile) alla sua posizione; ritaglia il tile successivo dall'immagine di lavoro (il primo tile da quella ingrandita e ritagliata), scrive `tile-<index>.png` e `mask-<index>.png` nel `tempFolder` e risponde con `startImage`, `mask` (assente per il primo tile), `maskSettings {"blur":30,"outset":30,"preserveOriginal":true}`, `size`, `preset`, `fields.prompt`, `loras` con il peso scelto, `strength 1`, `title` («Tile 2B»); oltre l'ultimo tile risponde `{"done": true}` dopo aver incollato l'ultimo risultato.

- [ ] **Step 1: Test di `TUSession`** (immagine finta di 1280 × 1024 a colori noti, `factor` 1 per la brevità, `overlap .standard` → 2 colonne, 1 riga; tile 0 = (0,0,1024,1024), tile 1 = (768,0,512,1024)):
  - `firstAnswerHasNoMaskAndTheFirstTileSize`: `size == 1024 × 1024`, nessuna chiave `mask`, `mask-…` non scritto, il PNG del tile ha 1024 × 1024.
  - `secondAnswerMasksFromTheFreeMargin`: dopo aver passato un `previous` (un PNG 1024 × 1024 di un colore), la risposta ha `size 512 × 1024`, una `mask` di 512 × 1024 con 255 da x = 200 al bordo e 0 prima.
  - `theTileCutOutIncludesThePastedNeighbourInTheOverlap`: il tile 1 ritagliato contiene, nei primi 256 px, il colore del risultato incollato del tile 0.
  - `doneAfterTheLastTileAndTheComposedImageIsReturned`: terza chiamata → `{"done": true}`; `end("finished")` restituisce un'immagine 1280 × 1024 con i colori attesi.
  - `endWithAnotherReasonReturnsNil`.
  - `usesThe320OverlapWhenChosen`: con `.wide` il tile 1 parte a x = 704 e la maschera da x = 250.
  - `promptAndLoRAWeightAreInTheAnswer`: `fields.prompt == TUPrompt.text(trigger: "TRIG")`, `loras[0].weight == 0.8` se scelto 0.8.
- [ ] **Step 2: Test del preset:** `fluxKlein9BHasThePresetValues` (steps 4, guidanceScale 1, sampler 16, shift 3, strength 1, LoRA `f2_ultra_real_v5_pro_lora_f16`); `unknownModelHasNoPreset` (Qwen 2.1 → `nil`); `promptHasTheFixedSentence`.
- [ ] **Step 3: Eseguire** `swift test --filter "TUSession|TUPreset" 2>&1 | grep -E "Test run with|error:"` → fallisce.
- [ ] **Step 4: Implementare.** Nei campi del preset le chiavi sono quelle di `contribute.fields` (leggere `FieldOverlay(json:)` per i nomi esatti: `steps`, `guidanceScale`, `sampler`, `shift`, `prompt`…); `sampler 16` come numero del preset dell'utente.
- [ ] **Step 5: Eseguire** → verdi.
- [ ] **Step 6: Commit** — `feat(tiled-upscale): sessione, preset e prompt`.

### Task 8: Plug-in completo (vista, stato, uscita, build, README)

**Files:**
- Create: `Plugins/TiledUpscale/Sources/TiledUpscale/TiledUpscalePlugin.swift`, `TUState.swift`, `TUView.swift`, `TUDesktopSaver.swift`, `Strings.swift`; `Plugins/TiledUpscale/Scripts/build.sh` (come `Plugins/DepthPose/Scripts/build.sh`, `VERSION=1.0`), `Plugins/TiledUpscale/README.md` (inglese)
- Test: `Plugins/TiledUpscale/Tests/TiledUpscaleTests/TUStateTests.swift`, `StringsTests.swift`, `TUDesktopSaverTests.swift`, `PluginTests.swift`

**Interfaces:**
- Consumes: `TileGrid`, `TileLimits`, `TUImage`, `TUSession`, `TUPresetTable` (Task 1, 6, 7); `DTHubPlugin`, `DTHubHost`, `DTHubContext` (`PluginKit`); `host.contribute(_:)`, `host.registerPresets(_:)`.
- Produces: manifest `id "com.exiztenz.dthub.tiledupscale"`, `name "Tiled Upscale"`, `version "1.0"`, `requiresEditModel: true`; `TUState` (`@MainActor @Observable`): scelta di fattore, sovrapposizione, peso del LoRA, immagine, riepilogo (`summary: TUSummary?` con dimensione finale, tile per lato, passi, `verdict`), `prepare()` che invia la pipeline guidata, `handle(session…)`; stato per progetto in `state.json` (come gli altri plug-in); `TUDesktopSaver.save(_ image: CGImage) -> URL?` («Tiled Upscale 001.png», primo numero libero, mai sovrascrive); tabella `L` it/en.

- [ ] **Step 1: Test:**
  - `summaryShowsTheFinalSizeTilesAndPasses`: immagine 1000 × 1000, 2×, 256 → «1984 × 1984», 3 colonne (x = 0, 768, 1536) × 3 righe = 9 passi.
  - `prepareIsOffWithoutAnImageOrWithAnUnsupportedModel`: nessuna immagine, o `model` Qwen 2.1 → `canPrepare == false` e un avviso.
  - `prepareRefusesAboveTheLimits`: immagine enorme → `verdict == .refuse`, nessun `contribute`.
  - `prepareSendsAGuidedPipeline`: con un `contribute` finto riceve `pipeline.guided == true`, `passes == plan.count`, `estimate.size == 1024 × 1024`, e il preset registrato con `registerPresets`.
  - `savesTheComposedImageOnTheDesktopWithTheFirstFreeNumber` (`TUDesktopSaver`, cartella finta): crea `Tiled Upscale 001.png`, poi `002`, mai sovrascrive.
  - `theStateIsKeptPerProject`: cambia progetto → scelte ripristinate dal `state.json`.
  - `everyTextIsInItalianAndEnglish` (`StringsTests`).
  - `manifestRequiresAnEditModelAndHasNoNetwork` (`PluginTests`: `requiresEditModel == true`).
- [ ] **Step 2: Eseguire** `cd Plugins/TiledUpscale && swift test 2>&1 | grep -E "Test run with|error:"` → fallisce.
- [ ] **Step 3: Implementare** `TUState` e la vista (immagine con scelta o trascinamento come Depth & Pose, ingrandimento 2×/4×/8×, sovrapposizione 256/320, peso del LoRA, riepilogo con avviso e conferma oltre il limite, tasto «Prepara», a fine sessione: Scrivania e «Usa come immagine di partenza» con `contribute.startImage`). `handle` risponde a `context`, `project`, `activate`, `deactivate`, `session.next` (tramite `TUSession.next`), `session.end` (tramite `TUSession.end`, poi salva sulla Scrivania se `finished`); un tipo sconosciuto → `unsupported`. Il preset si sceglie da `context.model` con `TUPresetTable`; il trigger dal `context.loraCatalog` (il LoRA del preset); senza trigger vale solo la frase fissa.
- [ ] **Step 4: Eseguire** tutti i test del plug-in → verdi.
- [ ] **Step 5: Costruire** il bundle: `Plugins/TiledUpscale/Scripts/build.sh "$TMPDIR/tu"`; controllare `file -b "$TMPDIR/tu/TiledUpscale.dthubplugin/Contents/MacOS/TiledUpscale"` («shared library») e `codesign --verify --deep --strict "$TMPDIR/tu/TiledUpscale.dthubplugin"`.
- [ ] **Step 6: README** del plug-in (inglese: cosa fa, la regola dei multipli di 64, 256/320, i limiti, preset, il modello richiesto, l'app minima), e riga in `Plugins/README.md`.
- [ ] **Step 7: Commit** — `feat(tiled-upscale): plug-in completo` (file per nome).

### Task 9: Documentazione del contratto, prova dal vivo, chiusura

**Files:**
- Modify: `PluginKit/README.md` (sezione «Pipeline guidata»: `contribute.pipeline.guided`, `session.next`, `session.end`, passo autonomo, `mask`/`maskSettings`/`size`, convenzione della maschera, versione minima dell'app: **0.3.2** come ipotesi), `PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift` solo se serve un helper `DTHubMessage.sessionNext(_:)`
- Create: `Plugins/TiledUpscale/Tests/TiledUpscaleTests/LiveTests.swift` (dietro `DTHUB_LIVE_TILEDUPSCALE=1`: usa un server con FLUX.2 klein e un'immagine piccola, 2×, e controlla che la dimensione e la giunzione siano coerenti)
- Modify (fuori da git): `docs/superpowers/briefing-prossima-sessione.md`, la nota Obsidian `DT Hub` e una nuova `DT Hub - Tiled Upscale`

- [ ] **Step 1: README del kit** con i JSON della spec §5 e la versione minima.
- [ ] **Step 2: Prova dal vivo** (fuori sandbox, server acceso): 2× su un'immagine 512 × 512 → 1024 × 1024 in un tile; poi 2× su 1000 × 700 → ritaglio a multipli di 64, più tile; controllare nel `tempFolder` i PNG dei tile e che l'immagine composta abbia le dimensioni attese.
- [ ] **Step 3: Verifica completa:** `cd Packages && swift test 2>&1 | grep -E "Test run with|✘|error:"`; `cd Plugins/TiledUpscale && swift test …`; `xcodebuild … build` → `BUILD SUCCEEDED`; `LocalizationCatalogTests` verde.
- [ ] **Step 4: Controllo dati personali:** `git diff main..HEAD -U0 | grep "^+" | grep -i "/Users/existenz\|antoniodachille\|/Volumes/LLM"` → nessun risultato.
- [ ] **Step 5: Commit** del README del kit e del test dal vivo; aggiornare briefing e Obsidian (stesso turno).
- [ ] **Step 6: Messaggio finale** all'utente: cosa provare a mano (2× su immagine piccola, 4× su media, con 256 e con 320; Stop a metà; chiudere il progetto durante la sessione), **«Decisioni che ho preso»** con costo di ciascuna, **«Rinviati»** (spec §10), via libera prima di unire, push o release, e il numero di versione dell'app da alzare alla release.
