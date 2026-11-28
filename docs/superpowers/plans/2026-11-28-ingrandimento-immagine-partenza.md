# Algoritmo di ingrandimento dell'immagine di partenza e tasto 1:1 — piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nella card Canvas di Control, scegliere con quale algoritmo l'immagine di partenza viene portata alla scala del canvas (automatico per famiglia, salvabile per famiglia), più un tasto 1:1.

**Architecture:** L'algoritmo è un campo opzionale di `AdvancedParameters` (`nil` = automatico), quindi viaggia con preset e metadati. Il default per famiglia sta nella sezione nuova `resampling` di `recommended-overrides.json` (letta e scritta da `RecommendedSettings`), con un valore di fabbrica nel codice. `InputComposer.frame` riceve l'algoritmo e, fuori da Core Graphics, ridimensiona con Core Image prima di comporre come oggi.

**Tech Stack:** Swift 6, SwiftUI, Core Graphics, Core Image, Swift Testing (`swift test` in `Packages/`), `xcodebuild` per l'app.

**Spec:** `docs/superpowers/specs/2026-11-28-ingrandimento-immagine-partenza-design.md`

## Global Constraints

- Ramo: `seedvr2-color-calibration` con la calibrazione colore già committata (prerequisito, vedi Task 0); il lavoro va su un ramo nuovo `start-image-resampling` creato da lì.
- `nil` = Automatico ovunque; campo mancante o valore sconosciuto nel JSON → `nil`, mai un errore.
- Valori di fabbrica: `seedvr2_3b`, `seedvr2_7b` → `catmullRom`; ogni altra famiglia, o famiglia sconosciuta → `coreGraphics`.
- Ordine: valore esplicito nei parametri > default salvato dall'utente per la famiglia > fabbrica.
- Coefficienti bicubici (Core Image `CIBicubicScaleTransform`): Catmull-Rom B=0 C=0,5; Mitchell B=1/3 C=1/3; B-spline B=1 C=0.
- Nome del campo JSON e della sezione: `resampling`. Valori raw: `coreGraphics`, `catmullRom`, `mitchell`, `bSpline`, `bilinear`, `lanczos`, `nearest`.
- Il campo non va nella configurazione Draw Things (`JobMapper`, `ConfigurationCodec.modeledKeys`).
- «Salva come default» della tab Generazione NON salva l'algoritmo.
- Simboli: tasto 1:1 `1.magnifyingglass`; icona salva `square.and.arrow.down`.
- Stringhe in `App/Localizable.xcstrings`, italiano e inglese.
- Test dei pacchetti: `cd Packages && swift test`. Se fallisce con `unable to spawn process '…/metal'`: `rm -rf .build/out/Intermediates.noindex/XCBuildData` e rilanciare.
- Build app: `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build`.

## Review Focus

1. **Immagine più grande del canvas (riduzione) con algoritmo non Core Graphics:** deve leggere il file a piena dimensione e ridurre con l'algoritmo scelto, senza aliasing a scalini. Test in Task 5.
2. **Margini e rotazione con un algoritmo Core Image:** i margini (`edges`, `gray`, `green`) e la posizione dell'immagine devono restare quelli di Core Graphics; cambia solo il contenuto dentro l'immagine. Test in Task 4.
3. **Preset o risultato vecchio senza `resampling`, o con un valore che una versione futura aggiunge:** si carica, algoritmo Automatico. Test in Task 1.
4. **File `recommended-overrides.json` scritto da una versione vecchia (senza sezione) o con una famiglia dal valore sconosciuto:** i default per modello restano intatti e la voce sconosciuta si salta. Test in Task 2.
5. **Immagine verticale o orizzontale in canvas di proporzioni diverse, e zoom 1:1 fuori range (immagine minuscola in canvas enorme):** il tasto 1:1 calcola sull'asse giusto e si spegne se lo zoom uscirebbe da −100…+100. Test in Task 3.

---

### Task 0: Mettere in salvo la calibrazione colore e aprire il ramo

**Files:** nessuno nuovo (le modifiche già presenti a `Packages/Sources/HubCore/Selection/ModelSelection.swift` e `Packages/Tests/HubCoreTests/ModelSelectionTests.swift`; la spec e questo piano).

- [ ] **Step 1:** `cd Packages && swift test --filter ModelSelectionTests` → `Test run with 9 tests … passed`.
- [ ] **Step 2: Commit della calibrazione (sul ramo `seedvr2-color-calibration`)**

```bash
git add Packages/Sources/HubCore/Selection/ModelSelection.swift Packages/Tests/HubCoreTests/ModelSelectionTests.swift
git commit -m "SeedVR2: Color calibration on when chosen in the header, off when leaving it"
```

- [ ] **Step 3:** `git switch -c start-image-resampling`, poi commit di spec e piano:

```bash
git add docs/superpowers/specs/2026-11-28-ingrandimento-immagine-partenza-design.md docs/superpowers/plans/2026-11-28-ingrandimento-immagine-partenza.md
git commit -m "Spec and plan: start image resampling and 1:1 in the Canvas card"
```

### Task 1: `Resampling` e il campo in `AdvancedParameters`

**Files:**
- Create: `Packages/Sources/HubKit/Generation/Resampling.swift`
- Modify: `Packages/Sources/HubKit/Generation/AdvancedParameters.swift` (campo nella sezione `// Output.`, decodifica in `init(from:)`)
- Test: `Packages/Tests/HubKitTests/ResamplingTests.swift`

**Interfaces:**
- Produces:
  - `public enum Resampling: String, Codable, Sendable, CaseIterable` con i sette casi (ordine: `coreGraphics, catmullRom, mitchell, bSpline, bilinear, lanczos, nearest`).
  - `public static func factory(forFamily family: String?) -> Resampling`
  - `public static func effective(explicit: Resampling?, family: String?, saved: [String: Resampling]) -> Resampling`
  - `AdvancedParameters.resampling: Resampling?` (default `nil`).

- [ ] **Step 1: Test che falliscono** (`ResamplingTests.swift`, Swift Testing):
  - `factoryIsCatmullRomForSeedVR2`: `factory(forFamily: "seedvr2_7b") == .catmullRom`, idem `"seedvr2_3b"`.
  - `factoryIsCoreGraphicsElsewhere`: `"flux2_9b"` e `nil` → `.coreGraphics`.
  - `explicitWinsOverSavedAndFactory`: `effective(explicit: .nearest, family: "seedvr2_7b", saved: ["seedvr2_7b": .bSpline]) == .nearest`.
  - `savedWinsOverFactory`: `effective(explicit: nil, family: "seedvr2_7b", saved: ["seedvr2_7b": .bSpline]) == .bSpline`.
  - `missingFieldDecodesAsAutomatic`: decodificare `{"colorCalibration":true}` come `AdvancedParameters` → `resampling == nil`, `colorCalibration == true`.
  - `unknownValueDecodesAsAutomatic`: `{"resampling":"sinc"}` → `resampling == nil`.
  - `roundTripKeepsTheChoice`: encode/decode di `AdvancedParameters` con `.bSpline` → `.bSpline`; con `nil` il JSON non contiene la chiave `resampling`.
- [ ] **Step 2:** `swift test --filter ResamplingTests` → FAIL (tipo non definito).
- [ ] **Step 3:** Implementare `Resampling.swift` e il campo. Nella decodifica tollerante: `resampling = (try? container.decodeIfPresent(String.self, forKey: .resampling)).flatMap { $0.flatMap(Resampling.init(rawValue:)) }`.
- [ ] **Step 4:** `swift test --filter ResamplingTests` → PASS; poi `swift test` intero → tutto verde.
- [ ] **Step 5: Commit** `"Resampling: the start image's scaling algorithm as an Advanced field, automatic per family"`.

### Task 2: La sezione `resampling` di `recommended-overrides.json`

**Files:**
- Modify: `Packages/Sources/HubKit/Generation/RecommendedSettings.swift`
- Test: `Packages/Tests/HubKitTests/RecommendedSettingsTests.swift` (esistente)

**Interfaces:**
- Consumes: `Resampling` (Task 1).
- Produces:
  - `public private(set) var resampling: [String: Resampling]` in `RecommendedSettings` (chiave = famiglia).
  - `public func settingResampling(_ value: Resampling, forFamily family: String) -> RecommendedSettings`
  - `public func removingResampling(forFamily family: String) -> RecommendedSettings`
  - `init(data:)` legge la sezione; `encoded()` la scrive solo se non vuota; `overriding(with:)` e `merging(_:)` portano con sé `resampling` di `overrides` / della tabella di partenza (non quella del `live`).

- [ ] **Step 1: Test che falliscono:**
  - `readsTheResamplingSection`: JSON `{"models":{},"families":{},"resampling":{"seedvr2_7b":"bSpline","x":"sinc"}}` → `resampling == ["seedvr2_7b": .bSpline]`.
  - `oldFileWithoutSectionKeepsModels`: un file con solo `models` (una voce valida) → la voce del modello c'è, `resampling.isEmpty`.
  - `encodedRoundTripsResampling`: `settingResampling(.mitchell, forFamily: "seedvr2_3b")` → `RecommendedSettings(data: encoded()).resampling == ["seedvr2_3b": .mitchell]`, e i modelli restano.
  - `removingResamplingForgetsOnlyThatFamily`.
  - `encodedWithoutResamplingHasNoKey`: tabella senza sezione → il JSON non contiene `"resampling"`.
- [ ] **Step 2:** `swift test --filter RecommendedSettings` → FAIL.
- [ ] **Step 3:** Implementare (aggiungere `resampling: [String: Resampling]?` alla struct `File` di `encoded()`).
- [ ] **Step 4:** test → PASS; `swift test` intero verde.
- [ ] **Step 5: Commit** `"Recommended overrides: a resampling section per family"`.

### Task 3: Riconoscere e impostare l'1:1

**Files:**
- Modify: `Packages/Sources/HubCore/Control/FramingMath.swift`, `Packages/Sources/HubCore/Control/ControlStore.swift`
- Test: `Packages/Tests/HubCoreTests/FramingTests.swift` (esistente)

**Interfaces:**
- Produces:
  - `FramingMath.oneToOneZoom(imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int) -> Double?` — `100 · log4(larghezza della finestra di riempimento / canvasWidth)`; `nil` se fuori da `Framing.zoomRange`.
  - `FramingMath.isOneToOne(imageWidth:imageHeight:canvasWidth:canvasHeight:framing:) -> Bool` — `abs(cropRect(...).width - canvasWidth) < 0.5 && framing.rotation == 0`.
  - `ControlStore.isOneToOne(canvasWidth: Int, canvasHeight: Int) -> Bool` (false senza immagine), `ControlStore.oneToOneZoom(canvasWidth:canvasHeight:) -> Double?`.

- [ ] **Step 1: Test che falliscono:**
  - `oneToOneZoomForHalfSizeImage`: immagine 1024×1024, canvas 2048×2048 → `-50` (±1e-9).
  - `oneToOneZoomForSameSize`: 1024 in 1024 → `0`.
  - `oneToOneZoomPortraitInLandscape`: 768×1024 in canvas 1536×1024 → la finestra di riempimento è larga 768 → `100·log4(768/1536) = -50`.
  - `oneToOneZoomOutOfRangeIsNil`: 64×64 in 2048×2048 → `nil`.
  - `isOneToOneAfterApplyingTheZoom`: con `Framing(zoom: oneToOneZoom!)` → `true`; stessa con `rotation: 10` → `false`; con `zoom: 0` (2× ingrandita) → `false`.
- [ ] **Step 2:** `swift test --filter FramingTests` → FAIL.
- [ ] **Step 3:** Implementare (la larghezza della finestra di riempimento è `cropRect(... Framing(zoom: 0)).width`).
- [ ] **Step 4:** PASS; `swift test` verde.
- [ ] **Step 5: Commit** `"FramingMath: the zoom at which the start image is 1:1"`.

### Task 4: `InputComposer.frame` con l'algoritmo

**Files:**
- Modify: `Packages/Sources/HubCore/Control/InputComposer.swift`
- Create: `Packages/Sources/HubCore/Control/ImageResampler.swift`
- Test: `Packages/Tests/HubCoreTests/ImageResamplerTests.swift`, `Packages/Tests/HubCoreTests/OutpaintComposerTests.swift` (esistente, testa già `InputComposer.frame`)

**Interfaces:**
- Consumes: `Resampling` (Task 1).
- Produces:
  - `enum ImageResampler { static func scaled(_ image: CGImage, toWidth: Int, height: Int, with: Resampling) -> CGImage? }` — `.coreGraphics`: `CGContext` con `.high`; bicubici: `CIBicubicScaleTransform` con B/C dei Global Constraints; `.lanczos`: `CILanczosScaleTransform`; `.bilinear`/`.nearest`: Core Image con campionamento lineare / più vicino. Bordi con `clampedToExtent()`; contesto Core Image senza gestione colore (`workingColorSpace` e `outputColorSpace` `NSNull`), come nella prova che ha dato scarto 0,16 rispetto a PIL.
  - `InputComposer.frame(_:toWidth:height:framing:paint:fill:resampling: Resampling = .coreGraphics)`.

Approccio in `frame`: con `.coreGraphics` il percorso di oggi, identico. Altrimenti si ridimensiona prima l'immagine intera a `image.width·scale × image.height·scale` (arrotondato, minimo 1) con `ImageResampler.scaled` e la si disegna nello stesso `drawn` rect (che ora coincide con la sua dimensione), con i bordi estesi e la rotazione come oggi.

- [ ] **Step 1: Test che falliscono:**
  - `ImageResamplerTests.nearestDuplicatesPixels`: immagine 2×2 con 4 colori, `scaled(..., 4, 4, .nearest)` → ogni blocco 2×2 ha il colore del pixel d'origine.
  - `ImageResamplerTests.smoothnessOrder`: immagine 32×32 di rumore deterministico (seed fisso) ingrandita 2× → energia del Laplaciano `bSpline < mitchell < catmullRom`.
  - `ImageResamplerTests.constantStaysConstant`: immagine uniforme (120,80,40) ingrandita 2× con ogni algoritmo → tutti i pixel entro ±1.
  - `ImageResamplerTests.reductionIsSmooth`: scacchiera 1 px 64×64 ridotta a 16×16 con `.catmullRom` e `.lanczos` → deviazione standard della luminanza < 20 (niente aliasing a scalini).
  - `OutpaintComposerTests.coreGraphicsIsUnchanged`: `frame(... resampling: .coreGraphics)` uguale byte per byte a `frame(...)` senza il parametro.
  - `OutpaintComposerTests.marginsUnchangedWithCoreImage`: immagine 64×64 in canvas 256×256 a zoom −50 con `fill: .green` e `.bSpline` → i pixel dei margini sono verdi (0,255,0) come con `.coreGraphics`; con `rotation: 30` i quattro angoli del canvas sono verdi.
- [ ] **Step 2:** `swift test --filter "ImageResamplerTests|OutpaintComposerTests"` → FAIL.
- [ ] **Step 3:** Implementare `ImageResampler` e il parametro di `frame`.
- [ ] **Step 4:** PASS; `swift test` verde.
- [ ] **Step 5: Commit** `"InputComposer: scale the start image with the chosen algorithm"`.

### Task 5: Passare l'algoritmo dal RUN e dai plug-in

**Files:**
- Modify: `Packages/Sources/HubCore/Control/ControlStore.swift` (`pendingInputs`, `PendingInputs`, `framedStartImage`, `framedStartImageRender`, `framedStartImageKey`)
- Modify: `Packages/Sources/HubCore/Plugins/FramedStartImage.swift` (`path(for:canvasWidth:canvasHeight:fill:)` e il render: parametro `resampling`)
- Test: `Packages/Tests/HubCoreTests/ControlStoreTests.swift` e `FramedStartImageTests.swift` (esistenti)

**Interfaces:**
- Consumes: `Resampling`, `InputComposer.frame(…resampling:)`.
- Produces: tutte le funzioni elencate prendono `resampling: Resampling = .coreGraphics` come ultimo parametro; `PendingInputs` ha `let resampling: Resampling`. Con `resampling != .coreGraphics` si decodifica con `maxPixel` = lato lungo dell'immagine (piena dimensione).

- [ ] **Step 1: Test che falliscono:**
  - `framedKeyChangesWithResampling`: `framedStartImageKey(..., resampling: .coreGraphics) != framedStartImageKey(..., resampling: .bSpline)`.
  - `pendingRenderUsesTheAlgorithm`: con un'immagine di prova 64×64 salvata nello storage di test e canvas 128×128 a zoom 0, `render()` con `.nearest` dà blocchi 2×2 uguali, con `.coreGraphics` no.
  - `reductionDecodesFullSizeWithCoreImage`: immagine 256×256 in canvas 64×64: con `.lanczos` il risultato coincide (±2 per canale) con `ImageResampler.scaled(originale, 64, 64, .lanczos)`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Implementare.
- [ ] **Step 4:** PASS; `swift test` verde.
- [ ] **Step 5: Commit** `"Control: the RUN and the framed start image use the chosen algorithm"`.

### Task 6: L'app risolve l'algoritmo e salva il default per famiglia

**Files:**
- Modify: `App/Generation/ModelDefaults.swift`, `App/Generation/GenerationController.swift` (`renderInputs`, proprietà nuove), `App/DTHubApp.swift:137-143` (`FramedStartImage`)
- Modify: `App/Localizable.xcstrings` (messaggi di conferma)

**Interfaces:**
- Consumes: `Resampling.effective`, `RecommendedSettings.settingResampling/removingResampling/resampling`.
- Produces:
  - `ModelDefaults.savedResampling: [String: Resampling]` (= `saved.resampling`), `saveResampling(_ value: Resampling, forFamily: String)`, `resetResampling(forFamily: String)` — scrivono con `store.save(saved)` e impostano `notice` (`defaults.resampling.saved`, `defaults.resampling.reset`).
  - `GenerationController.resampling(for model: CatalogModel?) -> Resampling` = `Resampling.effective(explicit: parameters.advanced.resampling, family: model?.family, saved: defaults.savedResampling)`; `var resampling: Resampling { resampling(for: selectedModel()) }`.
  - `renderInputs(parameters:model:)` passa `resampling(for: model)` a `pendingInputs`; `DTHubApp` passa `generation.resampling` a `FramedStartImage`.

- [ ] **Step 1:** Implementare (nessun test d'app: la logica sta nei pacchetti, Task 1–5).
- [ ] **Step 2:** Build: `xcodebuild … build` → `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Commit** `"App: resolve the start image algorithm per model and keep per-family defaults"`.

### Task 7: La card Canvas — tasto 1:1, menu e icona

**Files:**
- Modify: `App/Control/CanvasStage.swift` (overlay `.bottomLeading` sullo stage accanto agli altri badge; riga dei menu al posto di `fillRow` alla riga 98)
- Modify: `App/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ControlStore.isOneToOne/oneToOneZoom`, `control.setZoom(_:)`, `GenerationController.resampling`, `ModelDefaults.saveResampling/resetResampling/savedResampling`, `generation.family()`.

Comportamento (dalla spec, sezione «La card Canvas»):
- Tasto `1.magnifyingglass` in `.overlay(alignment: .bottomLeading)`, stesso stile del tasto ✕ (20 pt, palette bianca su nero 0,55, `.padding(8)`); azione `control.setZoom(z)` con `z = control.oneToOneZoom(...)`; spento se `isOneToOne` o `z == nil`. Aiuto e accessibilità: `control.stage.oneToOne` = «Dimensione reale (1:1)» / «Actual size (1:1)».
- Riga sostituisce `if control.hasMargins(...) { fillRow }`: si mostra se `!isOneToOne || hasMargins`. A sinistra (solo se `!isOneToOne`): icona salva + `Picker` menu; a destra (solo se `hasMargins`): il picker dei margini di oggi.
- Menu: titolo «Ingrandimento: <nome>» (`control.resampling.title`), voci «Automatico (<nome effettivo>)» (`tag nil`) e i sette nomi (Core Graphics, Catmull-Rom, Mitchell, B-spline, Bilineare/Bilinear, Lanczos, Nearest); se `savedResampling[famiglia] != nil`, dopo un `Divider` un pulsante «Torna al predefinito di fabbrica per <famiglia>» → `resetResampling`. Scrive `generation.parameters.advanced.resampling`.
- Icona `square.and.arrow.down`: salva `parameters.advanced.resampling!` per `generation.family()`; spenta se la selezione è `nil`, senza famiglia, o se uguale a `Resampling.effective(explicit: nil, family:, saved:)`. Aiuto «Usa <algoritmo> come predefinito per <famiglia>».
- La riga di conferma usa `defaults.notice` come fa «Salva come default» (stesso posto in cui oggi appare).

- [ ] **Step 1:** Implementare UI e stringhe (it/en).
- [ ] **Step 2:** Build → `** BUILD SUCCEEDED **`.
- [ ] **Step 3:** Prova a mano con l'app Debug (server di Draw Things acceso, SeedVR2 7B selezionato, `SeedVR2/Original.png` come partenza, canvas 2048): zoom 0 → il menu dice «Automatico (Catmull-Rom)»; tasto 1:1 → zoom −50, menu sparisce, compare la riga dei margini; scelgo B-spline, salvo con l'icona → `~/Library/Application Support/DT Hub/recommended-overrides.json` contiene `"resampling":{"seedvr2_7b":"bSpline"}` e i default per modello di prima; RUN a zoom 0 con Catmull-Rom → il risultato coincide con `SeedVR2/ingrandimenti/2_catmullrom.png` (scarto medio < 1); salvo un preset e lo ricarico → l'algoritmo torna; un preset vecchio → Automatico.
- [ ] **Step 4: Commit** `"Canvas card: 1:1 button and the start image algorithm menu with per-family default"`.

### Task 8: MCP, README e test completi

**Files:**
- Modify: `App/Agent/AppAgentHost.swift` (`advancedValues`, `setAdvanced`), `Packages/Sources/HubMCP/Tools/ReadTools.swift:136` e `Packages/Sources/HubMCP/Tools/EditTools.swift:126-130` (descrizioni)
- Modify: `README.md` (voce nella parte su Control)

**Interfaces:**
- `advancedValues()` aggiunge sempre `"resampling": .string(rawValue ?? "automatic")`.
- `setAdvanced`: la chiave `resampling` si gestisce prima del resto: `"automatic"` → `nil`, un raw valido → il caso, altro → `.invalid("Field 'resampling' takes automatic, coreGraphics, catmullRom, mitchell, bSpline, bilinear, lanczos or nearest.")`; poi la si toglie da `current` prima della fusione generica e si rimette sul risultato.
- Descrizioni: `get_advanced` cita «resampling (how the start image is scaled to the canvas)»; `set_advanced` cita i valori ammessi.

- [ ] **Step 1:** Implementare.
- [ ] **Step 2:** `cd Packages && swift test` → tutte le suite verdi; build app → `** BUILD SUCCEEDED **`.
- [ ] **Step 3:** Prova MCP (`dthub` collegato): `set_advanced {"values":{"resampling":"bSpline"}}` → «Applied: resampling.»; `get_advanced` mostra `bSpline`; `"resampling":"sinc"` → errore con l'elenco.
- [ ] **Step 4: Commit** `"MCP and README: the start image algorithm"`.
