# Seamless Pattern — piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** un plug-in DT Hub che, con Krea 2, Z-Image, FLUX.2 [klein] e FLUX.3 [klein], prepara un RUN la cui immagine si ripete senza giunzione, grazie a RoPE a toro e decoder VAE con wrap nel server custom.

**Architecture:** tre strati.
1. **Fork del motore:** campo `seamless_tile` in `GenerationConfiguration`, RoPE con frequenze portate a un numero intero di giri, wrap nei decoder `Decoder` e `WanDecoderCausal3D`.
2. **App:** il campo viaggia solo nei job di un passo di pipeline che lo chiede; il contratto dei plug-in guadagna `seamless` nel passo, il ritiro della pipeline e `customServer` nel contesto.
3. **Plug-in:** prepara la pipeline di un passo "Run · Seamless", mostra le viste ripetute e il controllo della giunzione, e ha i suoi strumenti MCP.

**Tech Stack:** Swift. Fork: s4nnc/NNC, FlatBuffers (file generati modificati a mano), SwiftPM. App: SwiftPM `Packages`, `ThirdParty/DrawThings-Swift`, SwiftUI. Plug-in: package SwiftPM in `Plugins/SeamlessPattern`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-25-plugin-seamless-pattern-design.md`

## Global Constraints

- Senza il plug-in nulla cambia: con `seamless_tile = 0`, o con il campo assente, il server calcola gli stessi tensori di oggi e l'app manda gli stessi byte di oggi.
- `seamless_tile: byte = 0` in coda a `GenerationConfiguration`; valori 0 off, 1 left-right, 2 up-down, 3 both. Vtable `190` (dopo `scheduler = 188`).
- Versioni del server che leggono il campo: `.krea2`, `.zImage`, `.flux2`, `.flux2_9b`, `.flux2_4b`, `.flux3_5b`. Mai `.mingImage` o altre.
- `min_turns` di partenza: Z-Image `1.0`; Krea 2, FLUX.2, FLUX.3 `0.5`.
- θ attuali: Krea 2 `1000`, Z-Image `256`, FLUX.2 `2000`, FLUX.3 `10000`. Periodo FLUX.3 = griglia × `0.5`; per le altre il periodo è la griglia.
- Con il flag acceso il server ignora tiled decoding e tiled diffusion; una griglia non compatibile o memoria insufficiente danno un errore, mai una generazione normale al suo posto.
- Famiglie del plug-in (chiavi DT Hub): `["krea_2", "z_image", "flux2_9b", "flux2_4b", "flux3_5b"]`.
- Valori di `seamless` nel JSON del contratto: `"both" | "leftRight" | "upDown"`.
- Seam check: passo `4` px, `WARN` entro `1.25` volte la seconda linea peggiore, `N/A` sotto `64` px.
- Testi dell'interfaccia e README del plug-in in inglese, come gli altri plug-in; spec e note in italiano.
- Fork: ramo nuovo `seamless-tile` da `ming-image` nel worktree `Developer-krea2/fork-f4d03b02`. Non si pusha (la fork è di ianiv).
- Pubblicare (release, upload, push di tag) richiede il via libera esplicito dell'utente: nessun task del piano pubblica.

## Review Focus

1. **Una generazione normale cambia di qualche bit** (RoPE o codec): l'utente se ne accorgerebbe solo confrontando seed. Test di invarianza nei Task 2 e 7, più il confronto di PNG nel Task 6.
2. **Ming-Image con il flag acceso** (ad esempio un job in coda creato con Z-Image ed eseguito dopo un cambio di modello): deve uscire normale. Test nel Task 6.
3. **HiRes fix acceso**: il primo passo e il secondo hanno griglie diverse e ciascuno deve chiudere sulla propria. Prova e2e nel Task 6.
4. **Tiled decoding acceso nella tab dell'utente**: il RUN seamless deve comunque decodificare intero. Prova e2e nel Task 6.
5. **Il plug-in ritira una pipeline che non è sua** (dell'utente o di un altro plug-in): non deve toccarla. Test nel Task 8.

---

## Parte A — Fork del motore

Tutti i comandi della parte A partono da `Developer-krea2/fork-f4d03b02`. Prima del Task 1: `git switch -c seamless-tile ming-image`.

### Task 1: Campo di configurazione e matematica del toro

**Files:**
- Modify: `Libraries/DataModels/Sources/config.fbs` (in coda, dopo `scheduler`)
- Modify: `Libraries/DataModels/PreGeneratedSPM/config_generated.swift`, `config_data_model_generated.swift`, `config_mutating_generated.swift`, `config_query_generated.swift` (a mano, sul modello del commit `002084e` per `scheduler`)
- Create: `Libraries/SwiftDiffusion/Sources/SeamlessTile.swift`
- Create: `Apps/SeamlessTileTest/main.swift` e il suo `.executableTarget` in `Package.swift` (come `MingVAETest`: dipende da `Diffusion` e `NNC`)

**Interfaces:**
- Produces:
  - `GenerationConfiguration.seamlessTile: Int8` (JSON `seamlessTile`, default 0)
  - `public struct SeamlessTile: Equatable, Sendable { public var wrapsHeight: Bool; public var wrapsWidth: Bool }` con `public init?(configurationValue: Int8)` (nil per 0 e per valori sconosciuti; 1 → solo larghezza, 2 → solo altezza, 3 → entrambe)
  - `public static func minTurns(for version: ModelVersion) -> Double?` (nil per le versioni non supportate)
  - `public func torusFrequency(omega: Double, period: Double, minTurns: Double) -> Double`
  - `public func torusAngle(position: Double, omega: Double, period: Double, minTurns: Double) -> Double` (posizione presa modulo `period`)

- [ ] **Step 1: Scrivere i test nel `main.swift` di `SeamlessTileTest`** (ogni controllo che fallisce stampa e fa `exit(1)`):
  - `SeamlessTile(configurationValue: 0) == nil`, `(1)` = solo larghezza, `(2)` = solo altezza, `(3)` = entrambe, `(9) == nil`;
  - `minTurns(for: .zImage) == 1.0`, `minTurns(for: .krea2) == 0.5`, `minTurns(for: .flux3_5b) == 0.5`, `minTurns(for: .mingImage) == nil`, `minTurns(for: .flux1) == nil`;
  - per θ ∈ {256, 1000, 2000, 10000}, dim 48 o 32, periodo 64: `cos/sin(torusAngle(position: 64, …))` uguali a quelli di `position: 0` entro `1e-9`;
  - `torusFrequency(omega: 0.01, period: 64, minTurns: 0.5)`: 0.01·64/2π ≈ 0.10 giri → `0`;
  - una frequenza a 2,6 giri sul periodo diventa esattamente `3·2π/64`.
- [ ] **Step 2:** `swift run SeamlessTileTest`. Atteso: non compila (i simboli non esistono).
- [ ] **Step 3: Implementare.**
  - Campo `seamless_tile: byte = 0;` in `config.fbs`, con un commento come quello di `scheduler`; i 4 file generati a mano, vtable `190`.
  - `SeamlessTile.swift` con i tipi e le funzioni sopra. Formula della spec: `giri = round(ω·P/2π)`, `0` se `ω·P/2π < minTurns`, `ω' = giri·2π/P`, tutto in `Double`.
- [ ] **Step 4:** `swift run SeamlessTileTest`. Atteso: `SeamlessTileTest: all passed`.
- [ ] **Step 5:** commit `Seamless tile: GenerationConfiguration.seamlessTile (appended byte) and the torus frequency math`.

### Task 2: RoPE a toro nelle quattro funzioni

**Files:**
- Modify: `Libraries/SwiftDiffusion/Sources/Models/Krea2.swift`, `ZImage.swift`, `Flux2.swift`, `Flux3.swift` (le funzioni `…RotaryPositionEmbedding`)
- Test: `Apps/SeamlessTileTest/main.swift`

**Interfaces:**
- Consumes: `SeamlessTile`, `torusAngle`, `SeamlessTile.minTurns(for:)` (Task 1)
- Produces: un parametro finale `seamless: SeamlessTile? = nil` in `Krea2RotaryPositionEmbedding`, `ZImageRotaryPositionEmbedding`, `Flux2RotaryPositionEmbedding` e `Flux3RotaryPositionEmbedding`. Il `minTurns` è fisso per funzione (Z-Image 1.0, le altre 0.5) e non è un parametro.

- [ ] **Step 1: Test.**
  - **Invarianza:** per ognuna delle quattro funzioni, con griglia 8×12 e testo 7, la chiamata con `seamless: nil` è uguale byte per byte a quella di una copia congelata della formula di oggi. Le copie si chiamano `referenceKrea2Rope`, `referenceZImageRope`, `referenceFlux2Rope` e `referenceFlux3Rope`, sono copiate nel test dal sorgente attuale **prima** di modificarlo e hanno le stesse firme.
  - **Periodicità:** con `SeamlessTile(configurationValue: 3)`, sulla griglia 8×12, per ogni canale dell'asse larghezza il passo d'angolo fra due colonne vicine (x=1 meno x=0) moltiplicato per 12 è un multiplo di 2π entro `1e-5`. Quindi la colonna 11 è vicina della colonna 0 come due colonne qualsiasi. Lo stesso per l'altezza con 8. Il passo si ricava da `atan2(sin, cos)` dei valori del tensore.
  - **Testo e asse 0:** i canali dell'asse 0 e le righe dei token di testo sono uguali a quelli con `seamless: nil`.
  - **Solo larghezza:** con `configurationValue: 1` i canali dell'asse altezza sono uguali a quelli con `nil`.
  - **Krea 2 con 1 riferimento:** i token del riferimento hanno gli stessi angoli y/x dei token dell'immagine.
  - **FLUX.3:** il periodo in unità di posizione è griglia × `0.5`. La periodicità vale sulla griglia, non sulla posizione.
- [ ] **Step 2:** `swift run SeamlessTileTest`. Atteso: FAIL di compilazione (il parametro `seamless` non esiste).
- [ ] **Step 3: Implementare.** Nei cicli y/x dei token **dell'immagine** (e, per Krea 2, dei riferimenti), quando `seamless` avvolge quell'asse, l'angolo diventa `torusAngle(position: Double(y) [× 0.5 per FLUX.3], omega: 1/pow(θ, …), period: Double(gridHeight) [× 0.5], minTurns: …)`. Il resto del codice non cambia, e con `nil` non si entra in nessun ramo nuovo.
- [ ] **Step 4:** `swift run SeamlessTileTest`. Atteso: PASS.
- [ ] **Step 5:** commit `Seamless tile: torus RoPE for Krea 2, Z-Image, FLUX.2 and FLUX.3 (nil keeps today's tensors)`.

### Task 3: Il flag arriva alle funzioni RoPE

**Files:**
- Modify: `Libraries/SwiftDiffusion/Sources/UNetFixedEncoder.swift`. Chiamate di oggi: Krea 2 riga ~890; Z-Image, ramo `case .zImage` righe ~2888, 2893, 2902; FLUX.3 riga ~3486; FLUX.2, ramo `case .flux2, .flux2_9b, .flux2_4b`, riga ~3702. **Non** il ramo `case .mingImage` (riga ~3111) né le chiamate con `height: 0`.

**Interfaces:**
- Produces: `UNetFixedEncoder.seamless: SeamlessTile?` (`public var`, default nil), passato come `seamless:` alle chiamate elencate.

- [ ] **Step 1: Test.** Nel `SeamlessTileTest`, un controllo statico: `grep` del sorgente da parte dello script `Apps/SeamlessTileTest/check-call-sites.sh`, che fallisce se nel ramo `.mingImage` compare `seamless:` o se una delle 4 righe elencate non lo passa.
- [ ] **Step 2:** lo script fallisce.
- [ ] **Step 3:** aggiungere la proprietà e passarla alle chiamate elencate.
- [ ] **Step 4:** lo script passa, `swift build --product gRPCServerCLI` compila.
- [ ] **Step 5:** commit `Seamless tile: UNetFixedEncoder.seamless reaches the image RoPE of the four families (never Ming)`.

### Task 4: Wrap nel `Decoder` (Z-Image, FLUX.2, FLUX.3)

**Files:**
- Modify: `Libraries/SwiftDiffusion/Sources/SeamlessTile.swift` (helper del grafo)
- Modify: `Libraries/SwiftDiffusion/Sources/Models/Autoencoder.swift` (`Decoder` e i blocchi che costruisce)
- Test: `Apps/SeamlessTileTest/main.swift`

**Interfaces:**
- Produces:
  - `func WrapPad(top: Int, left: Int, wrapsHeight: Bool, wrapsWidth: Bool) -> Model`: in NHWC, concatena le ultime `top` righe in testa e le prime in coda, e lo stesso con `left` per le colonne, solo sugli assi avvolti;
  - `func WrappingConvolution(groups:filters:filterSize:border:wrap:format:name:) -> (Model.IO) -> Model.IO`: con `wrap == nil` è **esattamente** `Convolution(...)` di oggi, con gli stessi nomi dei pesi; altrimenti `WrapPad` seguito da una `Convolution` con il bordo a 0 sugli assi avvolti;
  - un parametro finale `wrap: SeamlessTile? = nil` in `Decoder(...)`, propagato a ogni conv con bordo del decoder.

- [ ] **Step 1: Test.**
  - **`WrapPad`:** su un tensore 1×4×5×1 noto, l'uscita è 1×6×7×1 con le righe/colonne del lato opposto ai bordi.
  - **Conv circolare:** una `WrappingConvolution` 3×3 con pesi casuali su un input 1×8×8×4 è uguale (entro `1e-4`) alla stessa conv applicata al tile 3×3 dell'input e ritagliata al centro.
  - **Nomi dei pesi:** il `Decoder` con `wrap: nil` e quello con `wrap: SeamlessTile(configurationValue: 3)` hanno gli stessi nomi dei parametri, quindi leggono lo stesso file `.ckpt`.
- [ ] **Step 2:** FAIL di compilazione.
- [ ] **Step 3:** implementare `WrapPad`, `WrappingConvolution` e il parametro `wrap` nel `Decoder`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** commit `Seamless tile: wrap padding in the Decoder (Z-Image, FLUX.2, FLUX.3; nil builds today's graph)`.

### Task 5: Wrap in `WanDecoderCausal3D` (Krea 2)

**Files:**
- Modify: `Libraries/SwiftDiffusion/Sources/Models/WanVAE.swift` (`WanDecoderCausal3D` e i blocchi causali 3D che usa; **non** `NCHWWanDecoderCausal3D` se Krea 2 non lo usa: verificarlo nel ramo `.krea2` di `FirstStage.swift`)
- Test: `Apps/SeamlessTileTest/main.swift`

**Interfaces:**
- Consumes: `WrapPad` (Task 4)
- Produces: un parametro finale `wrap: SeamlessTile? = nil` in `WanDecoderCausal3D(...)`. Avvolge solo H/W; il padding temporale causale non cambia.

- [ ] **Step 1: Test.**
  - **Nomi dei pesi:** con `wrap` nil o acceso i nomi dei parametri sono gli stessi.
  - **Conv causale circolare:** su 1 frame, la conv causale 3D con wrap è uguale alla stessa conv su un input allargato a tile 3×3 nello spazio e ritagliato.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** implementare.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** commit `Seamless tile: spatial wrap padding in WanDecoderCausal3D (Krea 2)`.

### Task 6: Collegamento nel generatore e prova reale

**Files:**
- Modify: `Libraries/LocalImageGenerator/Sources/LocalImageGenerator.swift` (dove si costruiscono `UNetFixedEncoder` e `FirstStage`; vicino al blocco di `scheduler`)
- Modify: `Libraries/SwiftDiffusion/Sources/FirstStage.swift` (proprietà `wrap`; rami `.zImage` ~373, FLUX.2/3 ~533, `.krea2` ~687; no `existingDecoder` quando `wrap != nil`)
- Create: `Apps/SeamlessTileTest/e2e.sh` (genera e misura)

**Interfaces:**
- Consumes: `SeamlessTile(configurationValue:)`, `SeamlessTile.minTurns(for:)`, `UNetFixedEncoder.seamless`, `Decoder(wrap:)`, `WanDecoderCausal3D(wrap:)`
- Produces: `FirstStage.wrap: SeamlessTile?`. Comportamento del server:
  - `let seamless = SeamlessTile.minTurns(for: version) != nil ? SeamlessTile(configurationValue: configuration.seamlessTile) : nil`;
  - con `seamless != nil`: tiled decoding e tiled diffusion spenti per questa generazione;
  - griglia di latent non divisibile per il patch della famiglia: errore `"Seamless tile: the size must be a multiple of 16 px"`, nessuna generazione;
  - mancanza di memoria per il decode intero: l'errore del decoder risale, senza ripiegare sul decode a tile.

- [ ] **Step 1: Scrivere `e2e.sh`.** Con `draw-things-cli generate --local --models-dir "$MODELS" --model <file> --config-json '{"seamlessTile":3}' --width 1024 --height 1024 --seed 7 --output …` genera un'immagine per famiglia (Krea 2, Z-Image, FLUX.2 klein 9B, FLUX.3 klein). Poi misura la giunzione con il `seam_check` del nodo, usando il Python di ComfyUI (`/Users/existenz/ComfyUI-Installs/eXistenZ/ComfyUI`, `nodes/_seamless_helpers.py`). Lo script esce con 1 se una direzione non è PASS. `MODELS` è la cartella dei modelli del server gestito di DT Hub (Preferenze › Draw Things).
- [ ] **Step 2: Fissare la base di confronto.** Con il binario di oggi (`build/server-src/Custom-gRPCServerCLI` o la build Release di `ming-image`), stesse 4 generazioni **senza** `seamlessTile`; salvare gli sha256 dei PNG in `Apps/SeamlessTileTest/baseline.sha256`.
- [ ] **Step 3: Implementare il collegamento** come descritto in "Produces".
- [ ] **Step 4: Verificare.**
  - `e2e.sh`: atteso PASS ←→ e ↑↓ per tutte e 4 le famiglie.
  - Le 4 generazioni senza flag con il binario nuovo hanno gli sha256 di `baseline.sha256`.
  - Z-Image con `seamlessTile:3` e Ming con `seamlessTile:3`: l'uscita Ming ha lo sha256 di Ming senza flag.
  - Una FLUX.2 con `"hiresFix":true` e `seamlessTile:3` dà PASS.
  - Una Krea 2 con `"tiledDecoding":true` e `seamlessTile:3` dà PASS.
- [ ] **Step 5: Tarare `min_turns`.** Per ogni famiglia, 8 prompt (texture di pietra, legno, tessuto, carta da parati floreale, motivo geometrico, prato, nuvole, una scena) a 1024 e 1536. Si controlla a occhio il caso "tile ripetuto più volte dentro il tile". Se capita, si alza `min_turns` di quella famiglia a 1.0 e si annota nel commit.
- [ ] **Step 6:** commit `Seamless tile: LocalImageGenerator reads seamlessTile for the four families; whole decode, no tiled diffusion`.

### Task 7: Binario Release e patch

**Files:**
- Modify (DT Hub): `Server/krea2-edit.patch` (diff `f4d03b0..seamless-tile`), `Server/README.md` (una riga sul campo `seamlessTile`)
- Binario: `build/server-src/Custom-gRPCServerCLI/gRPCServerCLI-macOS`, sostituito con la build Release (con le 4 `*.bundle`, come per Ming)

- [ ] **Step 1:** `swift build -c release --product gRPCServerCLI` nel fork; copiarlo in `build/server-src/Custom-gRPCServerCLI` come per la build Ming del briefing.
- [ ] **Step 2:** rigenerare `Server/krea2-edit.patch` e controllarlo su un worktree pulito (stesso patch-id), come nel briefing.
- [ ] **Step 3:** commit in DT Hub `Server: seamless tile in the custom server (seamlessTile field)`.

---

## Parte B — App (DT Hub)

Comandi da `Packages/`: `swift test --filter <Nome>`. Per `ThirdParty/DrawThings-Swift`: `swift test --package-path ThirdParty/DrawThings-Swift --filter <Nome>`.

### Task 8: Il campo nel job e il contratto dei plug-in

**Files:**
- Modify: `ThirdParty/DrawThings-Swift/Sources/DrawThingsClient/Generated/config_generated.swift` (vtable `190`, come `scheduler` a 188), `…/Configuration/DrawThingsConfiguration.swift` (`public var seamlessTile: Int8 = 0`, incluso in init e JSON)
- Create: `Packages/Sources/HubKit/Generation/SeamlessTile.swift`
- Modify: `Packages/Sources/HubKit/Generation/GenerationJob.swift`, `Packages/Sources/DTBridge/JobMapper.swift` (`request(for:inputs:)`), `Packages/Sources/HubCore/Generation/JobComposer.swift`
- Modify: `Packages/Sources/HubKit/Plugin/PluginContribution.swift` (`PipelineStep.seamless`, parsing di `"seamless"` e di `"pipeline": null`), `PipelineStepCoding.swift` (persistenza in coda), `PluginMessages.swift` (`PluginContext.customServer`)
- Modify: `Packages/Sources/HubCore/Plugins/ContributionStore.swift` (ritiro e rifiuto), `Packages/Sources/HubCore/Plugins/PluginRegistry.swift` (`contextData`)
- Modify: `App/Generation/GenerationController.swift` (il passo porta `seamless` a `JobComposer.batches`, riga ~610), `App/DTHubApp.swift` (fornisce `customServer` al registry con `ManagedServerSettings.usesBundledServer()` in modalità gestita)
- Modify: `PluginKit/README.md` (le tre aggiunte del contratto)
- Test: `Packages/Tests/DTBridgeTests/JobMapperTests.swift`, `Packages/Tests/HubKitTests/…` (test del passo di pipeline), `Packages/Tests/HubCoreTests/…` (ContributionStore e JobComposer)

**Interfaces:**
- Produces:
  - `public enum SeamlessTile: String, Codable, Sendable, CaseIterable { case both, leftRight, upDown; public var configurationValue: Int8 }` (both 3, leftRight 1, upDown 2);
  - `public static let families: Set<String> = ["krea_2", "z_image", "flux2_9b", "flux2_4b", "flux3_5b"]`;
  - `GenerationJob.seamlessTile: SeamlessTile?` (default nil, `Codable` senza la chiave se nil);
  - `PipelineStep.seamless: SeamlessTile?`;
  - `PluginContext.customServer: Bool?`;
  - `JobComposer.batches(..., seamlessTile: SeamlessTile? = nil)`;
  - `ContributionStore` riceve `seamlessProblem: (_ family: String?) -> String?` (nil = consentito): con il server non custom dà `"seamless: the custom server is not running."`, con una famiglia fuori lista `"seamless: this model family does not support it."`.

- [ ] **Step 1: Test.**
  - `aJobWithoutSeamlessEncodesTheSameBytesAsBefore`: i byte FlatBuffers della richiesta di un job tipico (fixture salvata **prima** di modificare `JobMapper`) sono uguali dopo la modifica.
  - `aSeamlessJobCarriesTheConfigurationValue`: `.both` → `seamlessTile == 3`, `.leftRight` → 1, `.upDown` → 2.
  - `aPipelineStepReadsSeamless`: il JSON `{"steps":[{"seamless":"both"}]}` dà `.both`; `"seamless":"diagonal"` dà nil.
  - `aQueuedStepKeepsSeamless`: un passo codificato e decodificato con `PipelineStepCoding` conserva `.both`.
  - `aPluginWithdrawsOnlyItsOwnPipeline`: `"pipeline": null` dal plug-in A toglie la pipeline di A; non toglie quella di B né quella dell'utente.
  - `aSeamlessStepIsRefusedWithoutTheCustomServer` e `…OnAnotherFamily`: c'è un problem con il testo esatto e la pipeline non cambia.
  - `turningThePluginOffDropsItsSeamlessPipeline`: è il comportamento di `forget` di oggi, fissato da un test.
  - `theContextSaysWhetherTheServerIsCustom`: `customServer` è `true` o `false` nel JSON del contesto.
- [ ] **Step 2:** `swift test --filter "Seamless|Withdraw|CustomServer"`. Atteso: FAIL.
- [ ] **Step 3:** implementare. Due dettagli:
  - in `GenerationController` il valore del passo arriva al job **solo** per i passi di una pipeline;
  - il RUN normale chiama `JobComposer.batches` senza il parametro.
- [ ] **Step 4:** `swift test` completo in `Packages` e in `ThirdParty/DrawThings-Swift`. Atteso: PASS, salvo il test già noto come instabile (briefing).
- [ ] **Step 5:** aggiornare `PluginKit/README.md`: il passo con `seamless`, `"pipeline": null` e `customServer` nel contesto.
- [ ] **Step 6:** commit `Plug-in contract: seamless pipeline step, pipeline withdrawal, customServer in the context`.

---

## Parte C — Plug-in Seamless Pattern

Comandi da `Plugins/SeamlessPattern`: `swift test`. Bundle: `Scripts/build.sh <cartella>`. Struttura e stile come `Plugins/Panorama360` e `Plugins/SphereLight`; prefisso `SP`; id `com.exiztenz.dthub.seamlesspattern`; versione `1.0`; simbolo `square.grid.3x3`.

### Task 9: Controllo della giunzione e viste ripetute

**Files:**
- Create: `Plugins/SeamlessPattern/Package.swift`, `Scripts/build.sh` (copia di quello di SphereLight)
- Create: `Sources/SeamlessPattern/SPSeam.swift`, `SPTileView.swift`
- Test: `Tests/SeamlessPatternTests/SPSeamTests.swift`, `SPTileViewTests.swift`

**Interfaces:**
- Produces:
  - `enum SPSeamStatus: String, Codable { case pass, warn, fail, notApplicable }`;
  - `struct SPSeamResult: Codable, Equatable { var status: SPSeamStatus; var ratio: Double?; var rank: Double?; var vsWorst: Double? }`;
  - `enum SPSeam { static func check(_ image: CGImage) -> (leftRight: SPSeamResult, upDown: SPSeamResult) }` (porting di `seam_check` / `_boundary_scores` di `_seamless_helpers.py`, stesse costanti);
  - `enum SPView: String, CaseIterable, Codable { case tile, twoByTwo, threeByThree, offset, halfDrop, halfBrick }`;
  - `enum SPTileView { static func render(_ image: CGImage, view: SPView) -> CGImage? }` (porting di `tile_view`).

- [ ] **Step 1: Test.**
  - Un'immagine 128×128 periodica (sinusoide con un numero intero di periodi) dà PASS in tutte e due le direzioni.
  - Un'immagine con un gradiente orizzontale da 0 a 1 dà FAIL in ←→.
  - Un'immagine 48×48 dà N/A.
  - Un'immagine piatta dà PASS (pareggio).
  - Sulla stessa immagine di prova i `ratio` coincidono, entro `1e-3`, con quelli del Python. Il valore atteso si calcola una volta con il Python di ComfyUI e si scrive nel test.
  - `render(.twoByTwo)` di un'immagine 64×32 è 128×64 con i quattro quadranti uguali. `.offset` sposta di 32×16. `.halfDrop` e `.halfBrick` hanno le dimensioni di `tile_view`: rispettivamente 3·W × 2·H e 2·W × 3·H.
- [ ] **Step 2:** `swift test`. Atteso: FAIL.
- [ ] **Step 3:** implementare.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** commit `Seamless Pattern: seam check and tiled views (ports of the node's math)`.

### Task 10: Stato, interfaccia e pipeline

**Files:**
- Create: `Sources/SeamlessPattern/SeamlessPatternPlugin.swift` (manifest; `static let families = ["krea_2", "z_image", "flux2_9b", "flux2_4b", "flux3_5b"]`, la stessa lista di `SeamlessTile.families` dell'app: il plug-in non dipende da HubKit), `SPState.swift`, `SPStore.swift` (stato per progetto: modo, vista), `SPSender.swift` (JSON di `contribute`), `SPView.swift`, `Strings.swift`
- Test: `Tests/SeamlessPatternTests/SPSenderTests.swift`, `SPStoreTests.swift`, `SPStateTests.swift`

**Interfaces:**
- Consumes: `SPSeam`, `SPTileView`, `SPView` (Task 9); contratto del Task 8.
- Produces:
  - `enum SPMode: String, Codable, CaseIterable { case both, leftRight, upDown }`;
  - `SPSender.prepare(mode:) -> Data`: `{"type":"contribute","pipeline":{"name":"Seamless","steps":[{"title":"Seamless","seamless":"<mode>"}]}}`, senza preset, campi o immagini;
  - `SPSender.stop() -> Data`: `{"type":"contribute","pipeline":null}`;
  - `SPState`: `mode`, `view`, `isPrepared`, `customServer`, `lastResult` (dal contesto `lastResult`, oppure un'immagine trascinata), `seam` (calcolato a ogni nuovo risultato), `notice` (il problem che l'app restituisce).

- [ ] **Step 1: Test.**
  - Il JSON esatto di `prepare(.both)` e di `stop()`.
  - Cambiare il modo con `isPrepared == true` rimanda `prepare` con il modo nuovo.
  - Con `customServer == false`, `canPrepare == false` e l'avviso è `"Seamless Pattern needs DT Hub's own server (Preferences › Draw Things: use the included server)."`.
  - Con `customServer == nil` (app vecchia) vale lo stesso.
  - Lo stato salvato e riletto per progetto conserva modo e vista.
  - Un nuovo `lastResult` ricalcola `seam`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** implementare la tab come nello schizzo della spec, con i componenti `DTHubDesign` (`DSTabFrame`, `DSCollapsibleCard`, `DSButtons`):
  - Repeat (tre bottoni);
  - Prepare Run · Seamless e Stop seamless;
  - anteprima con la scelta della vista;
  - riga Seam con ←→ e ↑↓; la direzione non richiesta mostra solo il `ratio`;
  - Save PNG… (salva il tile) e Show in Finder;
  - trascinamento di un'immagine sull'anteprima;
  - senza server custom, solo l'avviso.
- [ ] **Step 4:** `swift test`. Atteso: PASS. `Scripts/build.sh /tmp/sp-build` produce `SeamlessPattern.dthubplugin`.
- [ ] **Step 5:** commit `Seamless Pattern 1.0: tab, per-project state, seamless pipeline`.

### Task 11: Strumenti MCP e documentazione

**Files:**
- Create: `Sources/SeamlessPattern/SPTools.swift`, `Tests/SeamlessPatternTests/SPToolsTests.swift`
- Modify: `Packages/Tests/…/RealPluginToolsTests.swift` (bundle reale del plug-in)
- Create: `Plugins/SeamlessPattern/README.md` (con «For AI agents (MCP)»)
- Modify: `Plugins/README.md` (riga e conteggio), `README.md` («Plug-in tools»), `docs/superpowers/specs/2026-11-08-server-mcp-design.md` (nuova `## 23. …: Seamless Pattern 1.0`)

**Interfaces:**
- Produces (strumenti `plugin__seamlesspattern__<tool>`, struttura `Connection` con closure come in `PSTools`):
  - `get_status` (read): `mode`, `prepared`, `customServer`, `family`, `lastResult`, `seam`;
  - `set_mode` (edit): `mode` ∈ `both|leftRight|upDown`;
  - `prepare_run` (edit, `startsRun: true`): rifiuta senza server custom, con lo stesso testo dell'avviso;
  - `stop` (edit);
  - `check_seam` (read): `result_id` → `{leftRight, upDown}` come `SPSeamResult`.

- [ ] **Step 1: Test.**
  - Ogni strumento con valori validi.
  - `set_mode` con `"diagonal"` dà errore e non cambia niente.
  - `prepare_run` senza server custom dà errore e non manda niente.
  - `check_seam` con un id inesistente dà errore.
  - Test sul bundle reale in `RealPluginToolsTests` (mai sui dati dell'utente).
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** implementare e scrivere la documentazione.
- [ ] **Step 4:** `swift test` nel plug-in e `swift test --filter RealPluginTools` in `Packages`. Atteso: PASS.
- [ ] **Step 5:** commit `Seamless Pattern: MCP tools and docs`.

### Task 12: Prova nell'app

- [ ] **Step 1:** build Debug di DT Hub con il server del Task 7; installare il bundle del plug-in.
- [ ] **Step 2:** per ognuna delle quattro famiglie:
  1. **Prepare** → il bottone dice "Run · Seamless".
  2. **RUN tre volte** con seed diversi → Seam PASS sulle tre.
  3. **Stop seamless** → "Run".
  4. **RUN normale** → stessa immagine (sha256) del RUN fatto con lo stesso seed prima di installare il plug-in.
- [ ] **Step 3:** passare a Ming → la tab sparisce e il bottone torna "Run". Con il server non custom (Preferenze) compare solo l'avviso.
- [ ] **Step 4:** un'entry in coda creata con "Run · Seamless" esce seamless.
- [ ] **Step 5 (punti da verificare della spec):**
  - **Start image:** un RUN seamless con una start image nella tab; se il risultato peggiora, aggiungere al plug-in un avviso quando la tab ha una start image.
  - **Refiner:** un RUN seamless con un preset che usa un refiner di un'altra famiglia; la giunzione deve restare PASS, altrimenti annotarlo nel README del plug-in.

  Gli esiti vanno annotati nel briefing.
- [ ] **Step 6:** se gli step 2–4 passano, aggiornare briefing e Obsidian (nota del plug-in nuova). **Non pubblicare**: la pubblicazione è un passo a parte che richiede il via libera dell'utente.
