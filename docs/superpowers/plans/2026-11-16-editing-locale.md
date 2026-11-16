# Editing locale Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Una terza modalità «Editing locale» nella card Canvas di Control: si ritaglia un riquadro dell'immagine di partenza, lo si ritocca come immagine di partenza temporanea alle sue dimensioni esatte, e si conferma il tentativo scelto, che torna al suo posto raccordato nei colori.

**Architecture:** La sessione (`LocalEditSession`) sta in `ControlInputs` e passa per la cronologia di `ControlStore`: entrare, confermare e annullare sono passi annullabili. La matematica (riquadro, ritaglio, guadagno, montaggio) è in HubCore come funzioni pure. `GenerationController` segue la sessione (dimensioni, HiRes, Incrementale), ricava i tentativi dai Risultati e fa il montaggio alla conferma. La card ha una vista nuova per la modalità.

**Tech Stack:** Swift 6, SwiftUI (macOS 26), CoreGraphics, Swift Testing, pacchetto `Packages` (HubKit, HubCore), app `DTHub.xcodeproj`.

**Spec:** `docs/superpowers/specs/2026-11-16-editing-locale-design.md`

## Global Constraints

- Ritaglio a lati multipli di 64, lato minimo 512, massimo 4096; un'immagine con un lato sotto 512 non permette l'Editing locale.
- La tab Generazione prende **le dimensioni esatte del ritaglio**; `highRes` acceso se un lato supera 2048, spento altrimenti; alla chiusura della sessione tornano larghezza, altezza e `highRes` ricordati all'apertura.
- Tentativo = risultato non video, uscito dopo l'apertura della sessione, con **esattamente** le dimensioni in pixel del ritaglio (lette dal file).
- Conferma: gli altri tentativi vanno nel Cestino con `GenerationSession.remove`; il confermato resta; il montaggio diventa risultato e immagine di partenza.
- Annulla rimette tutto; la sessione si chiude solo con Annulla o Conferma (cambiare modalità non la chiude).
- Durante la sessione: Incrementale sospesa senza avvisi; sostituire, togliere o svuotare l'immagine di partenza è rifiutato con «Conferma o annulla prima l'Editing locale».
- Raccordo colori: guadagno per canale (media originale + 1) / (media tentativo + 1), limitato a 0,2…5; sfumatura interna larga `max(8, 3% del lato corto)`.
- Plug-in Panorama non toccati. Stringhe in `App/Localizable.xcstrings` (en sorgente, it), `extractionState: manual`, inserite senza riformattare il file (`json.dumps(..., ensure_ascii=False, indent=2)` + `\n` riproduce il file com'è).
- Commenti in inglese nello stile del progetto. Lavoro nel worktree `.claude/worktrees/editing-locale`, ramo `feat/editing-locale`.

## Review Focus

- Riquadro tracciato in parte fuori dall'immagine o con un semplice clic: niente sessione, nessun crash; il riquadro si tiene dentro l'immagine. → test in Task 2.
- Immagine con lati non multipli di 64 e riquadro contro un bordo: il ritaglio sta dentro l'immagine. → test in Task 2.
- Tentativo cancellato dai Risultati, o il cui file non c'è più, al momento della conferma: errore mostrato, nulla cambia. → test in Task 5 (`confirmFailsWithoutTouchingAnything`).
- Cambio di progetto o riavvio con la sessione aperta: ritaglio, sessione e dimensioni del ritaglio ritornano. → test in Task 3 (`theSessionSurvivesAReload`) e verifica dal vivo.
- ⌘Z subito dopo «Usa il ritaglio» con una maschera: tornano originale, maschera intera e dimensioni di prima. → test in Task 3 e Task 5.

---

### Task 1: La sessione nei dati di Control

**Files:**
- Create: `Packages/Sources/HubKit/Control/LocalEditSession.swift`
- Modify: `Packages/Sources/HubKit/Control/ControlInputs.swift` (campo, `init`, `init(from:)`)
- Test: `Packages/Tests/HubKitTests/LocalEditSessionTests.swift`

**Interfaces:**
- Produces:
  - `public struct PixelRect: Equatable, Codable, Sendable { public var x, y, width, height: Int; public init(x:y:width:height:); public var cgRect: CGRect }`
  - `public struct LocalEditSession: Equatable, Codable, Sendable` con `public let id: UUID`, `rect: PixelRect` (in pixel dell'originale), `original: ReferenceImage`, `framing: Framing`, `mask: MaskReference?`, `paint: PaintReference?`, `strength: Double?`, `marginFill: MarginFill?`, `generationWidth: Int`, `generationHeight: Int`, `generationHighRes: Bool`, `openedAt: Date`, `public var matchColors: Bool` (default `true`); `init` memberwise pubblico.
  - `ControlInputs.localEdit: LocalEditSession?` (default `nil`, decodifica tollerante come gli altri campi; senza `image` non si tiene).

- [ ] **Step 1: test**

```swift
@Test func anOldControlFileHasNoSession() throws {
  let data = Data(#"{"framing":{"zoom":0,"offsetX":0,"offsetY":0,"rotation":0},"moodboard":[]}"#.utf8)
  #expect(try JSONDecoder().decode(ControlInputs.self, from: data).localEdit == nil)
}
@Test func theSessionRoundTrips() throws { /* inputs con image e localEdit (rect 64,128,1024,512; matchColors false) → encode → decode == inputs */ }
@Test func aSessionWithoutAnImageIsDropped() throws { /* JSON con localEdit e senza image → localEdit == nil */ }
```

- [ ] **Step 2:** `swift test --package-path Packages --filter LocalEditSessionTests` → errore di compilazione (`no member 'localEdit'`).
- [ ] **Step 3:** implementare i tipi e il campo.
- [ ] **Step 4:** stesso comando → 3 test passati.
- [ ] **Step 5:** commit `Local editing: the session in the Control inputs`.

### Task 2: Il riquadro

**Files:**
- Create: `Packages/Sources/HubCore/Control/LocalEditMath.swift`
- Test: `Packages/Tests/HubCoreTests/LocalEditMathTests.swift`

**Interfaces:**
- Consumes: `PixelRect` (Task 1).
- Produces: `public enum LocalEditMath` con `static let minSide = 512`, `maxSide = 4096`, `step = 64`; `public static func snapped(_ drawn: CGRect, imageWidth: Int, imageHeight: Int) -> PixelRect?` (nil se un lato dell'immagine è sotto 512 o se `drawn` non interseca l'immagine); `public static func featherWidth(for rect: PixelRect) -> Int`.

Regola, per ogni asse: lato = multiplo di 64 superiore al lato tracciato (dopo averlo ritagliato all'immagine), poi `max(512, …)`, `min(4096, …)`, `min(multiplo di 64 ≤ lato dell'immagine, …)`; centrato sul centro del tracciato; spostato dentro `0…lato immagine`.

- [ ] **Step 1: test**

```swift
@Test func aSmallBoxGrowsTo512AroundItsCentre() {
  #expect(LocalEditMath.snapped(CGRect(x: 1000, y: 1000, width: 100, height: 50), imageWidth: 4000, imageHeight: 3000)
    == PixelRect(x: 794, y: 769, width: 512, height: 512))
}
@Test func sidesGoUpToTheNextMultipleOf64() {
  #expect(LocalEditMath.snapped(CGRect(x: 0, y: 0, width: 700, height: 600), imageWidth: 4000, imageHeight: 3000)
    == PixelRect(x: 0, y: 0, width: 704, height: 640))
}
@Test func aBoxAgainstTheEdgeStaysInside() {
  #expect(LocalEditMath.snapped(CGRect(x: 3700, y: 2800, width: 300, height: 200), imageWidth: 4000, imageHeight: 3000)
    == PixelRect(x: 3488, y: 2488, width: 512, height: 512))
}
@Test func anImageNotAMultipleOf64KeepsTheCropInside() {
  #expect(LocalEditMath.snapped(CGRect(x: 0, y: 0, width: 1000, height: 1000), imageWidth: 1000, imageHeight: 700)
    == PixelRect(x: 20, y: 30, width: 960, height: 640))
}
@Test func nothingUnder512AndNothingOutside() {
  #expect(LocalEditMath.snapped(CGRect(x: 0, y: 0, width: 300, height: 300), imageWidth: 500, imageHeight: 2000) == nil)
  #expect(LocalEditMath.snapped(CGRect(x: 5000, y: 0, width: 10, height: 10), imageWidth: 4000, imageHeight: 3000) == nil)
}
@Test func theLongestSideStopsAt4096() {
  #expect(LocalEditMath.snapped(CGRect(x: 0, y: 0, width: 6000, height: 1000), imageWidth: 8000, imageHeight: 2000)?.width == 4096)
}
@Test func theFeatherIs3PercentOfTheShortSideAtLeast8() {
  #expect(LocalEditMath.featherWidth(for: PixelRect(x: 0, y: 0, width: 1024, height: 512)) == 15)
  #expect(LocalEditMath.featherWidth(for: PixelRect(x: 0, y: 0, width: 512, height: 256)) == 8)
}
```

(Posizione: centro del tracciato ritagliato all'immagine meno metà lato, arrotondata verso il basso, poi tenuta in `0…(lato immagine − lato)`. Sfumatura: `max(8, floor(0,03 × lato corto))`.)

- [ ] **Step 2:** `swift test --package-path Packages --filter LocalEditMathTests` → errore di compilazione.
- [ ] **Step 3:** implementare.
- [ ] **Step 4:** stesso comando → 7 test passati.
- [ ] **Step 5:** commit `Local editing: the crop rectangle`.

### Task 3: Montaggio e raccordo dei colori

**Files:**
- Create: `Packages/Sources/HubCore/Control/LocalEditCompositor.swift`
- Test: `Packages/Tests/HubCoreTests/LocalEditCompositorTests.swift`

**Interfaces:**
- Consumes: `PixelRect`, `LocalEditMath.featherWidth`.
- Produces: `public enum LocalEditCompositor` con
  - `public static func crop(_ image: CGImage, to rect: PixelRect) -> CGImage?` (pixel identici, sRGB RGBA 8 bit);
  - `public static func crop(_ image: CGImage, to rect: PixelRect, fullWidth: Int, fullHeight: Int) -> CGImage?` (per maschera e disegno, salvati più piccoli: il riquadro si scala a `image.width / fullWidth`);
  - `public static func montage(original: CGImage, retouch: CGImage, rect: PixelRect, matchColors: Bool) -> CGImage?` (nil se `retouch` non ha esattamente `rect.width × rect.height`).

Algoritmo del guadagno (non determinato dalla firma): fascia `b = featherWidth` dentro il riquadro, sui quattro lati; per ogni lato e canale `g = clamp((mediaOriginale + 1) / (mediaRitocco + 1), 0.2, 5)`; nel punto normalizzato `(u, v)` del riquadro `g(u,v) = ((1−v)·gTop + v·gBottom + (1−u)·gLeft + u·gRight) / 2`. Sfumatura: peso del ritocco `w = min(1, d / b)` con `d` = distanza in pixel dal bordo più vicino del riquadro.

- [ ] **Step 1: test** (immagini sintetiche costruite nei test)

```swift
@Test func theCropHasTheExactPixels() { /* originale 1024×768 a gradiente; crop(64,64,512,512) → 512×512, pixel (0,0) == originale (64,64) */ }
@Test func outsideTheRectNothingChanges() { /* montage: pixel (10,10) fuori riquadro == originale */ }
@Test func theCentreIsTheRetouchAndTheEdgeTheOriginal() { /* matchColors false: centro == ritocco; bordo del riquadro == originale */ }
@Test func aDarkerRetouchIsBroughtToTheOriginalLevel() {
  // originale grigio 160, ritocco grigio 80, matchColors true → centro del montaggio entro 160 ± 2
}
@Test func theGainIsHeldBetweenPoint2And5() { /* originale 250, ritocco 1 → centro ≤ 5·(1+1)−1 = 9 */ }
@Test func aRetouchOfAnotherSizeIsRefused() { /* retouch 511×512 → nil */ }
@Test func aMaskSavedSmallerIsCroppedToTheSameArea() { /* maschera 1024×768 per originale 4096×3072; rect (1024,768,1024,768) → 256×192 */ }
```

- [ ] **Step 2:** `swift test --package-path Packages --filter LocalEditCompositorTests` → errore di compilazione.
- [ ] **Step 3:** implementare con `CGContext` RGBA premoltiplicato sRGB, come `PSPixels` di Pano 360 (`PSRenderer.swift`).
- [ ] **Step 4:** stesso comando → 7 test passati.
- [ ] **Step 5:** commit `Local editing: crop, colour match and soft paste`.

### Task 4: Entrare, confermare, annullare in `ControlStore`

**Files:**
- Create: `Packages/Sources/HubCore/Control/ControlStore+LocalEdit.swift`
- Modify: `Packages/Sources/HubCore/Control/ControlStore.swift` (rifiuti in `setImage(data:…)`, `removeImage`, `clear`; `collectGarbage` conta i file della sessione; avviso nuovo), `Packages/Sources/HubCore/Control/ReferenceStorage.swift` (`ControlError.localEditOpen`)
- Test: `Packages/Tests/HubCoreTests/ControlStoreLocalEditTests.swift`

**Interfaces:**
- Consumes: Task 1–3.
- Produces:
  - `ControlError.localEditOpen`; `ControlNotice.localEditOpen`.
  - `public func beginLocalEdit(rect: PixelRect, generation: (width: Int, height: Int, highRes: Bool), now: Date = .now) throws(ControlError)`
  - `public func confirmLocalEdit(montage data: Data, name: String) throws(ControlError)`
  - `public func cancelLocalEdit()`
  - `public func setLocalEditMatchColors(_ on: Bool)` (fuori cronologia: cambia `inputs` e salva, come gli interruttori del Moodboard, e lo riporta negli stati di undo/redo come `keepingSwitchesAndOrder`)
  - `public func originalImage(maxPixel: Int?) -> CGImage?` (l'originale della sessione, o l'immagine di partenza senza sessione)
  - `public var onLocalEditChange: ((_ old: LocalEditSession?, _ new: LocalEditSession?) -> Void)?` (`@ObservationIgnored`), chiamato quando cambia `inputs.localEdit?.id` per qualunque via: `commit`, `undo`, `redo`, `switchTo`.

`beginLocalEdit`: un solo `commit`. Il ritaglio (immagine, maschera e disegno) si salva nello storage con `ReferenceImage.Source.plugin(id: "localEdit")`, nome `"<nome originale> (ritaglio).png"`; `framing = Framing()`; `strength` e `marginFill` restano; la sessione ricorda tutto lo stato di prima. Già in sessione → `.localEditOpen`. `confirmLocalEdit`: un `commit` con l'immagine nuova (sorgente `.result`) e lo stato ricordato (framing, maschera, disegno, forza, riempimento); `localEdit = nil`. `cancelLocalEdit`: un `commit` con l'originale e lo stato ricordato.

- [ ] **Step 1: test** (storage in memoria come in `ControlStoreTests`)

```swift
@Test func beginningMakesTheCropTheStartImage()      // image 512×512, localEdit.original == originale, framing == Framing()
@Test func theMaskAndTheDrawingAreCroppedToo()       // maschera e disegno presenti → anche nel ritaglio, diversi da prima
@Test func undoAfterBeginningBringsEverythingBack()  // originale, maschera intera, localEdit nil
@Test func cancelBringsBackTheOriginalAndTheMask()
@Test func confirmPutsTheMontageAndClosesTheSession() // image.source == .result, framing/maschera di prima, localEdit nil
@Test func undoAfterConfirmReopensTheSession()
@Test func theStartImageCannotBeReplacedDuringASession() // setImage → throws .localEditOpen; removeImage e clear → notice .localEditOpen, inputs invariati
@Test func theOriginalFileSurvivesTheGarbageCollection()
@Test func theSessionSurvivesAReload()                // nuovo ControlStore sullo stesso file → localEdit uguale, image == ritaglio
@Test func matchColorsIsOutsideTheHistory()           // setLocalEditMatchColors(false); undo di una pennellata successiva lo lascia false
@Test func theChangeIsReportedForEveryWay()           // onLocalEditChange chiamato per begin, undo, redo, cancel, confirm, switchTo
```

- [ ] **Step 2:** `swift test --package-path Packages --filter ControlStoreLocalEditTests` → errore di compilazione.
- [ ] **Step 3:** implementare.
- [ ] **Step 4:** stesso comando → 11 test passati; poi `swift test --package-path Packages --filter ControlStore` → tutti passati.
- [ ] **Step 5:** commit `Local editing: begin, confirm and cancel in the Control store`.

### Task 5: `GenerationController` segue la sessione

**Files:**
- Create: `App/Generation/GenerationController+LocalEdit.swift`, `Packages/Sources/HubCore/Generation/LocalEditAttempts.swift`
- Modify: `App/Generation/GenerationController.swift` (Incrementale: righe ~464 e ~473), `App/DTHubApp.swift` (collega `control.onLocalEditChange`; in `onOpen`, dopo `generation.apply(...)`, chiama `generation.applyLocalEditSize()`)
- Test: `Packages/Tests/HubCoreTests/LocalEditAttemptsTests.swift`

**Interfaces:**
- Consumes: Task 1–4.
- Produces:
  - HubCore: `public enum LocalEditAttempts { public static func select(_ results: [GeneratedImage], session: LocalEditSession, pixelSize: (GeneratedImage) -> (width: Int, height: Int)?) -> [GeneratedImage] }` (più recente prima; non video, `date >= openedAt`, dimensioni esatte).
  - App: `var localEditAttempts: [GeneratedImage]` (con cache delle dimensioni per id, lette con `CGImageSourceCopyPropertiesAtIndex`); `func beginLocalEdit(rect: PixelRect) throws`; `func applyLocalEditSize()`; `func localEditChanged(from old: LocalEditSession?, to new: LocalEditSession?)` (apre: `parameters.width/height = rect`, `highRes = max > 2048`; chiude: rimette i valori di `old`); `func confirmLocalEdit(attempt: GeneratedImage) async throws`.
- `confirmLocalEdit`: legge originale a piena risoluzione (`control.originalImage(maxPixel: nil)`) e il file del tentativo; montaggio fuori dal main actor; PNG in una cartella temporanea; `session.adopt(fileAt:job:)` con il job del tentativo e `width/height` dell'originale; `control.confirmLocalEdit(montage:name:)`; infine `session.remove` degli altri tentativi. Se qualcosa manca prima del `confirm` del store, errore e nulla cambia.
- Incrementale: `if incremental, control.inputs.localEdit == nil, …` nei due punti.

- [ ] **Step 1: test** di `LocalEditAttempts.select`: esclude un risultato più vecchio di `openedAt`, uno video, uno 1024×1024 per un ritaglio 1024×1023, e ordina dal più recente.
- [ ] **Step 2:** `swift test --package-path Packages --filter LocalEditAttemptsTests` → errore di compilazione.
- [ ] **Step 3:** implementare `LocalEditAttempts`, poi la parte app.
- [ ] **Step 4:** test → 4 passati; `xcodebuild -project DTHub.xcodeproj -scheme DTHub -configuration Debug -derivedDataPath build-le build` → `** BUILD SUCCEEDED **`.
- [ ] **Step 5:** commit `Local editing: generation size, Incremental and the montage follow the session`.

### Task 6: La modalità nella card Canvas

**Files:**
- Create: `App/Control/LocalEditStage.swift`
- Modify: `App/Control/CanvasStage.swift` (`Mode` aggiunge `.localEdit`; il selettore la mostra solo nella card, non nella finestra staccata), `App/Control/ControlText.swift` (testi di `.localEditOpen`), `App/Localizable.xcstrings`

**Interfaces:**
- Consumes: `control.originalImage`, `control.inputs.localEdit`, `generation.localEditAttempts`, `generation.beginLocalEdit(rect:)`, `generation.confirmLocalEdit(attempt:)`, `control.cancelLocalEdit()`, `control.setLocalEditMatchColors(_:)`, `LocalEditMath.snapped`, `LocalEditCompositor.montage`.
- Produces: `struct LocalEditStage: View` (`generation`, `connection`, `report: (ControlMessage) -> Void`).

- Senza sessione: originale intero in anteprima (lato lungo 1400, come `CanvasStage`); trascinare traccia il riquadro, dall'interno lo sposta, dagli angoli lo ridimensiona; Esc lo toglie; il riquadro mostrato è sempre quello arrotondato da `LocalEditMath.snapped`. Sotto: `localEdit.size` e **Usa il ritaglio** (spento con il motivo se `snapped` è nil).
- Con sessione: anteprima del montaggio del tentativo mostrato (originale e tentativo ridotti allo stesso fattore, montaggio fuori dal main actor, ricalcolato quando cambiano tentativo o `matchColors`); senza tentativi originale con riquadro tratteggiato e `localEdit.noAttempt`. Comandi: `‹ n/m ›` (un tentativo nuovo diventa quello mostrato), **Raccorda colori**, **Annulla**, **Conferma e rimetti nell'immagine** (spento senza tentativi).
- Il selettore mostra Editing locale spento senza immagine di partenza.

Stringhe (en / it):

| chiave | en | it |
|---|---|---|
| `control.stage.mode.localEdit` | Local Editing | Editing locale |
| `localEdit.drawHint` | Drag on the image to choose the part to retouch | Trascina sull'immagine per scegliere la parte da ritoccare |
| `localEdit.size` | %d × %d at (%d, %d) | %d × %d dal punto (%d, %d) |
| `localEdit.useCrop` | Use the Crop | Usa il ritaglio |
| `localEdit.tooSmall` | Local editing needs an image at least 512 px on each side | L'Editing locale vuole un'immagine di almeno 512 px per lato |
| `localEdit.noAttempt` | Press Run to retouch the crop | Premi Run per ritoccare il ritaglio |
| `localEdit.attempt` | %d/%d | %d/%d |
| `localEdit.matchColors` | Match Colours | Raccorda colori |
| `localEdit.cancel` | Cancel | Annulla |
| `localEdit.confirm` | Confirm and Put Back | Conferma e rimetti nell'immagine |
| `control.notice.localEditOpen` | Confirm or cancel the local edit first | Conferma o annulla prima l'Editing locale |

- [ ] **Step 1:** implementare; build come in Task 5 → `** BUILD SUCCEEDED **`.
- [ ] **Step 2:** commit `Local editing: the third mode of the Canvas card`.

### Task 7: Verifica

- [ ] `swift test --package-path Packages` → tutti passati.
- [ ] Build Debug → `** BUILD SUCCEEDED **`.
- [ ] Dal vivo (build Debug, non `/Applications`), con un'immagine di partenza grande (es. 5056×3328):
  1. Editing locale → riquadro piccolo → diventa 512×512; «Usa il ritaglio» → Generazione 512×512, HiRes spento; Canvas mostra il ritaglio.
  2. Run due volte → ‹ 2/2 ›; Raccorda colori acceso e spento cambia l'anteprima.
  3. Passare a Disegno, dipingere, tornare: la sessione c'è.
  4. Incrementale acceso: dopo Run l'immagine di partenza è ancora il ritaglio.
  5. Trascinare un'altra immagine sul Canvas → avviso, nulla cambia.
  6. Conferma → montaggio nei Risultati e come immagine di partenza, l'altro tentativo nel Cestino, dimensioni di prima.
  7. ⌘Z → sessione riaperta con il solo tentativo confermato; Annulla → originale.
  8. Riquadro sopra 2048 → HiRes acceso; chiusura → HiRes com'era.
  9. Uscire e riaprire con la sessione aperta → tutto come prima.
- [ ] Riferire cosa è stato provato e cosa no.
