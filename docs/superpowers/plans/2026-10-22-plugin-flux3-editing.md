# Flux3 Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** il plug-in «Flux3 Editing» (tre card: Moodboard, Immagine di partenza, Prompt) che scrive il prompt di editing di FLUX.3 con riquadri `from/src_bbox/tgt_bbox`, più l'aggiunta `startImageWindow` al contesto dei plug-in.

**Architecture:** due parti. (A) App: `startImageWindow` (la finestra dell'immagine che riempie il canvas, `FramingMath.cropRect`) esce nel contesto ed è letta dal kit. (B) Pacchetto nuovo `Plugins/Flux3Editing/`, modellato su Prompt Master F3 (ramo `feat/prompt-master-f3`, non unito: i file utili si **copiano** da lì con `git show feat/prompt-master-f3:<path>` e si rinominano `F3…` → `Edit…`; nessuna dipendenza di codice). Logica pura testata (numerazione, composer, geometria, conversioni di tipo, persistenza), poi stato, viste, LLM.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, Swift Testing, `DTHubPluginKit`/`DTHubDesign` come in F3.

**Spec:** `docs/superpowers/specs/2026-10-22-plugin-flux3-editing-design.md` (mockup `docs/superpowers/mockups/2026-10-22-flux3-editing.html`).

## Global Constraints

- Si risponde, si scrive la documentazione in `docs/superpowers/` e i commit in **italiano**; README e testi pubblici in **inglese**; testi dell'interfaccia in italiano e inglese (tabella `L` del plug-in, come F3).
- Griglia dei riquadri **0–1000**, ordine `[y0, x0, y1, x1]` = `[top, left, bottom, right]`, lato minimo 20 (`BBox.minSide`), una sola costante di scala (`BBoxScale.grid`).
- Numerazione: `ref_image_0` = immagine di partenza; `ref_image_{i+1}` = i-esima immagine **accesa** del Moodboard (`context.moodboard[i]`); unico punto: `RefNumbering`.
- Famiglie: costante unica `Flux3EditingPlugin.families = ["flux2_9b", "flux2_4b"]`.
- Id del plug-in `com.exiztenz.dthub.flux3editing`, nome «Flux3 Editing», versione 1.0, voce d'entrata `Flux3EditingEntry`.
- Il plug-in è un pacchetto indipendente (nessun `import` dell'app). Nei testi pubblici non si dice che DT Hub «sostituisce» Draw Things.
- Test-first (RED poi GREEN). **Non unire in `main` e non fare push senza un «unisci» / via libera esplicito.** `git add` per nome (mai `-A`). Ramo di lavoro: `feat/flux3-editing`, da `main`.
- Comandi: app `cd Packages && swift test 2>&1 | grep -E "Test run with|✘|error:"` (se «unable to spawn … metal»: `swift package clean`); plug-in `cd Plugins/Flux3Editing && swift test 2>&1 | grep -E "Test run with|✘|error:"`.

## Review Focus

1. Immagine del Moodboard **spenta o tolta** mentre ha riquadri: restano nell'elenco, fuori dal testo, Invia bloccato (T4, T5).
2. Moodboard **riordinato**: i numeri `<ref_image_N>` nel testo si ricalcolano e i riquadri seguono l'immagine (T4).
3. Canvas con **zoom < 0 (margini)** e **zoom > 0 (ritaglio)**: un riquadro disegnato nel margine resta valido e le coordinate sono del canvas (T1, T6).
4. **Id ripetuto, vuoto o con caratteri strani** (virgolette, a capo, `<`/`>`) nella `desc` e nell'id: il JSON resta valido (T5).
5. App **vecchia senza `startImageWindow`**, o senza immagine di partenza, o `size` assente: il plug-in non si rompe e lo dice (T2, T8).

---

### Task 1: `startImageWindow` nello store dell'app

**Files:**
- Modify: `Packages/Sources/HubKit/Plugin/PluginMessages.swift` (nuovo `PluginImageWindow`), `Packages/Sources/HubCore/Control/ControlStore.swift`
- Test: `Packages/Tests/HubCoreTests/ControlStoreTests.swift`

**Interfaces:**
- Produces: `public struct PluginImageWindow: Codable, Equatable, Sendable { public var x, y, width, height: Double; public init(x:y:width:height:) }` (pixel dell'immagine, dall'alto a sinistra); `ControlStore.startImageWindow(canvasWidth: Int, canvasHeight: Int) -> PluginImageWindow?` (nil senza immagine).

- [ ] **Step 1: test** `startImageWindowFollowsTheFraming` in `ControlStoreTests`: immagine 300×200, canvas 200×200 → a zoom 0 finestra `{x:50,y:0,width:200,height:200}`; dopo `setZoom(100)` larghezza 50; con `setZoom(-100)` larghezza 800 (finestra più larga dell'immagine, `x` negativo); senza immagine nil.
- [ ] **Step 2:** lanciare `swift test --filter startImageWindowFollowsTheFraming` → FAIL (API assente).
- [ ] **Step 3:** implementare `PluginImageWindow` e `ControlStore.startImageWindow` con `FramingMath.cropRect(imageWidth:imageHeight:canvasWidth:canvasHeight:framing: inputs.framing)`.
- [ ] **Step 4:** test → PASS.
- [ ] **Step 5: Commit** `feat(plugins): finestra dell'immagine di partenza nel canvas` (file per nome).

### Task 2: `startImageWindow` nel contesto, nel kit e nel README

**Files:**
- Modify: `Packages/Sources/HubKit/Plugin/PluginMessages.swift` (`PluginContext.startImageWindow: PluginImageWindow?`, init con valore predefinito nil), `Packages/Sources/HubCore/Plugins/PluginRegistry.swift` (closure `startImageWindow: (@MainActor () -> PluginImageWindow?)?`, usata in `sendContext`), `Packages/Sources/HubCore/Plugins/PluginContextKey.swift` (aggiungere `framingZoom: Double`, `framingOffsetX: Double`, `framingOffsetY: Double`, tutti con valore predefinito 0 nell'init), `App/DTHubApp.swift` (collegare la closure con `generation.parameters.width/height`), `App/MainWindow/MainWindowView.swift` (riempire i tre campi nella chiave), `PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift` (`DTHubContext.startImageWindow: DTHubImageWindow?`, decodifica tollerante `try?`), `PluginKit/README.md` (riga nel contesto: campo facoltativo, app ≥ 0.3.7 ipotesi)
- Test: `Packages/Tests/HubCoreTests/PluginContextKeyTests.swift`, `Packages/Tests/HubCoreTests/PluginRegistryTests.swift`, test del kit in `PluginKit/Tests`

**Interfaces:**
- Consumes: `ControlStore.startImageWindow` (T1).
- Produces: `DTHubImageWindow: Decodable, Equatable, Sendable { x, y, width, height: Double }` e `DTHubContext.startImageWindow`.

- [ ] **Step 1: test** `aFramingChangeChangesTheContextKey` (due chiavi uguali tranne `framingZoom` non sono uguali); `theContextCarriesTheImageWindow` (registry con la closure che dà `{x:50,y:0,width:200,height:200}`: il JSON del contesto la contiene; senza closure la chiave non c'è); test del kit: un contesto con e senza `startImageWindow` si decodifica, e con il campo malformato il resto del contesto sopravvive.
- [ ] **Step 2:** eseguire i test → FAIL.
- [ ] **Step 3:** implementare come da Files. In `MainWindowView` il `.task(id: contextKey)` già reinvia il contesto a ogni cambio della chiave.
- [ ] **Step 4:** test di `Packages` e del kit → PASS; `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build` compila.
- [ ] **Step 5: Commit** `feat(plugins): startImageWindow nel contesto (contratto 1, facoltativo)`.

### Task 3: Pacchetto `Flux3Editing` (scheletro, manifest, stringhe)

**Files:**
- Create: `Plugins/Flux3Editing/{Package.swift,Scripts/build.sh,README.md}`, `Sources/Flux3Editing/{Flux3EditingPlugin.swift,Strings.swift}`, `Tests/Flux3EditingTests/ManifestTests.swift`
- Copy+adapt da F3: `Package.swift` (nomi `Flux3Editing`, alias `Flux3EditingKit`/`Flux3EditingDesign`), `Scripts/build.sh` (id `com.exiztenz.dthub.flux3editing`, entry `Flux3EditingEntry`), `Strings.swift` (`L` con `text(_:italian:)`/`format`), `BBox.swift` (+ `BBoxTests.swift`), `F3Palette.swift` → `EditPalette.swift`

**Interfaces:**
- Produces: `final class Flux3EditingPlugin: DTHubPlugin` con `static let families`; `Flux3EditingEntry: DTHubPluginEntry`; `BBox` (come F3: `normalized`, `parse`, `minSide`, `grid`); `EditPalette.color(index:) -> Color`, `nsColor(index:)` (otto colori).

- [ ] **Step 1: test** `ManifestTests`: id, nome, versione «1.0», `families == ["flux2_9b","flux2_4b"]`, simbolo non vuoto; `BBoxTests` copiati (normalizzazione, lato minimo 20, parse).
- [ ] **Step 2:** `swift test` → FAIL (target mancante).
- [ ] **Step 3:** creare il pacchetto; il plug-in per ora mostra una vista segnaposto («Flux3 Editing») e risponde a `context`/`project`/`activate`/`deactivate` come `F3Plugin.handle`; simbolo `rectangle.on.rectangle`.
- [ ] **Step 4:** test → PASS; `Scripts/build.sh "$TMPDIR/f3e"` produce un bundle con `file -b …/Contents/MacOS/Flux3Editing` = «shared library» e `codesign --verify --deep --strict` ok.
- [ ] **Step 5: Commit** `feat(flux3-editing): scheletro del plug-in`.

### Task 4: Modello degli elementi, tipi e conversioni

**Files:**
- Create: `Sources/Flux3Editing/{EditElement.swift,EditDocument.swift}`, `Tests/Flux3EditingTests/{ElementTests.swift,DocumentTests.swift}`

**Interfaces:**
- Produces:
  - `enum EditKind: String, Codable { case fromReference, new, existing, move, remove }`
  - `struct EditElement: Codable, Equatable, Identifiable { var id: String; var colorIndex: Int; var kind: EditKind; var refFile: String?; var src: BBox?; var tgt: BBox?; var desc: String }` — significato per tipo come in spec §2/§5 (`existing` e `remove` usano `src`; `new` usa `tgt`; `move` e `fromReference` entrambi).
  - `struct EditDocument: Codable, Equatable { var prose: String; var elements: [EditElement]; var snapshot: EditSnapshot?; var referenceIndex: Int }`
  - `EditDocument.draw(onReference file: String, box: BBox)` (crea `fromReference` con destinazione: stessa proporzione dell'origine, lato massimo 30% della griglia, al centro; colore = prossimo in rotazione), `draw(onCanvas box: BBox)` (crea `new`), `setKind(_ kind: EditKind, of id: String)`, `delete(_ id: String)`, `move(_ id:, by step: Int)`, `repeatedIDs: Set<String>`.
  - Id predefinito `el_N` (N = primo libero).

- [ ] **Step 1: test** (nomi): `drawingOnAReferenceCreatesThePairInTheMiddle`; `drawingOnTheCanvasCreatesANewElement`; `colorsRotateThroughEight`; conversioni (`newToExistingKeepsTheBox`, `existingToMoveCreatesTheTargetBesideIt` — destinazione spostata a destra senza uscire dalla griglia, `moveToRemoveKeepsOnlyTheSource`, `moveToNewKeepsTheTarget`, `fromReferenceCannotChangeKind` → nessun cambio); `deletingKeepsTheOtherColors`; `repeatedIDsAreFound`; round-trip Codable.
- [ ] **Step 2:** → FAIL.
- [ ] **Step 3:** implementare (tabella delle conversioni della spec §5).
- [ ] **Step 4:** → PASS.
- [ ] **Step 5: Commit** `feat(flux3-editing): elementi, tipi e conversioni`.

### Task 5: Numerazione, composer e regole di Invia

**Files:**
- Create: `Sources/Flux3Editing/{RefNumbering.swift,EditComposer.swift}`, `Tests/Flux3EditingTests/{NumberingTests.swift,ComposerTests.swift}`

**Interfaces:**
- Consumes: `EditDocument`, `EditElement`, `BBox` (T3–T4).
- Produces:
  - `struct RefImage: Equatable { let number: Int; let path: String; let size: CGSize; var fileName: String }` (`fileName` = ultimo componente del percorso)
  - `enum RefNumbering { static let startImageNumber = 0; static func references(moodboard: [String], sizes: (String) -> CGSize?) -> [RefImage]; static func number(ofFile: String, in: [RefImage]) -> Int? }`
  - `enum EditProblem: Equatable { case noStartImage, noElements, emptyDescription(String), repeatedID(String), imageMissing(String) }` e `enum EditWarning: Equatable { case idNotInProse(String), unknownReferenceInProse(Int), tooManyImages }`
  - `enum EditComposer { static func text(_ doc: EditDocument, refs: [RefImage]) -> String; static func problems(_ doc: EditDocument, refs: [RefImage], hasStartImage: Bool) -> [EditProblem]; static func warnings(_ doc: EditDocument, refs: [RefImage]) -> [EditWarning] }`

- [ ] **Step 1: test** numerazione: con 3 immagini accese i numeri sono 1,2,3; riordinando l'array un riquadro `fromReference` segue il file e cambia numero (`referenceFollowsTheFileWhenReordered`); un file non più presente → `number(ofFile:)` nil. Composer, con asserzioni sul testo esatto: i cinque casi di spec §2 (`from`, `src_bbox`, `tgt_bbox` come nella tabella; `null` scritti, non omessi), ordine chiavi `id, from, src_bbox, tgt_bbox, desc`, indentazione di due spazi, prosa + riga vuota + array; `descWithQuotesAndNewlinesStaysValidJSON` (si rilegge con `JSONSerialization`); `removeWritesNullTarget`; `moveWritesTwoDifferentBoxes`; elementi con immagine mancante **non** compaiono nel testo; `problems`: nessuna immagine di partenza, nessun elemento, `desc` vuota per new/existing/fromReference ma non per remove/move, id ripetuto, immagine mancante; `warnings`: id non citato nella prosa, `<ref_image_5>` senza immagine, più di nove immagini accese.
- [ ] **Step 2:** → FAIL.
- [ ] **Step 3:** implementare; JSON scritto a mano a chiavi ordinate, stringhe con `JSONEncoder` per l'escape.
- [ ] **Step 4:** → PASS.
- [ ] **Step 5: Commit** `feat(flux3-editing): numerazione e composer`.

### Task 6: Geometria delle tele

**Files:**
- Create: `Sources/Flux3Editing/StageGeometry.swift`; copy+adapt `CanvasGeometry.swift` da F3 (macchina del trascinamento: `begin(at:items:selected:)`, `result(of:)`, `moved`, `fit`); `Tests/Flux3EditingTests/{StageGeometryTests.swift,CanvasGeometryTests.swift}` (questi ultimi copiati da F3)

**Interfaces:**
- Produces: `struct StageGeometry: Equatable { init(canvas: CGSize, image: CGSize, window: DTHubImageWindow?); var canvasAspect: Double; var imageFrame: CGRect /* in frazioni del canvas (0…1) */ ; static func plain(image: CGSize) -> StageGeometry }`. Formula: `imageFrame = (-w.x/w.width, -w.y/w.height, image.width/w.width, image.height/w.height)`; senza finestra l'immagine intera adattata al canvas (contain).

- [ ] **Step 1: test:** zoom 0 immagine 300×200 su canvas 200×200 → frame `x≈-0.25, width 1.5, height 1` (riempie, ritagliata ai lati); finestra più larga dell'immagine (zoom −100) → frame con margini (`x > 0`, `width < 1`); `plain` ha aspetto dell'immagine e frame `(0,0,1,1)`; senza finestra e proporzioni diverse → immagine adattata e centrata.
- [ ] **Step 2:** → FAIL. **Step 3:** implementare. **Step 4:** → PASS (anche i test di `CanvasGeometry` copiati).
- [ ] **Step 5: Commit** `feat(flux3-editing): geometria delle tele`.

### Task 7: Stato, persistenza e Annulla

**Files:**
- Create: `Sources/Flux3Editing/{EditState.swift,EditStore.swift,EditSnapshot.swift}`, `Tests/Flux3EditingTests/{StateTests.swift,StoreTests.swift}`; copy+adapt `F3Store.swift` (`EditStorage`, `DefaultsStorage`, `FileStorage`, `adoptLegacy`), `F3WorkFolder.swift` → `EditWorkFolder.swift`

**Interfaces:**
- Consumes: T4–T6.
- Produces: `@MainActor final class EditState: ObservableObject` con `@Published document`, `refs: [RefImage]`, `startImage: URL?`, `startSize: CGSize?`, `generationSize: CGSize?`, `window: DTHubImageWindow?`, `selected: String?`, `status: String`; `update(context: DTHubContext)` (ricalcola `refs` con `RefNumbering`, legge le dimensioni dei file con ImageIO, tiene `referenceIndex` dentro i limiti); `switchProject(folder:adoptLegacy:)`; `var problems: [EditProblem]`, `var warnings`, `var canSend`, `var sendText: String`; `struct EditSnapshot` (prosa + `desc` di ogni elemento) e `takeSnapshot()/undo()`.
- Persistenza: `state.json` per progetto con `document`; immagini ricordate per `fileName`.

- [ ] **Step 1: test:** `contextBuildsReferencesInOrder`; `missingImageKeepsElementButBlocksSend` (togliendo un file dal contesto l'elemento resta e `canSend` è falso); `startImageWindowAbsentFallsBack` (stato con `window` nil dichiarato nello `status`); `undoRestoresOnlyTheLastWrite`; `stateSurvivesRestart` (store su file temporaneo); `switchingProjectLoadsItsOwnState`; `referenceIndexIsClamped`.
- [ ] **Step 2:** → FAIL. **Step 3:** implementare. **Step 4:** → PASS.
- [ ] **Step 5: Commit** `feat(flux3-editing): stato, persistenza e Annulla`.

### Task 8: Tele e viste

**Files:**
- Create: `Sources/Flux3Editing/{ImageStage.swift,EditView.swift,MoodboardCard.swift,StartImageCard.swift,PromptCard.swift,ElementCard.swift}`, `Tests/Flux3EditingTests/RenderTests.swift`; copy+adapt `F3Components.swift` / parti di `F3CanvasCard.swift`

**Interfaces:**
- Consumes: `EditState`, `StageGeometry`, `CanvasGeometry`, `EditPalette` (T3–T7).
- Produces: `ImageStage` (tela con sfondo: parametri `geometry: StageGeometry`, `image: NSImage?`, `items: [CanvasItem]`, `selected`, gesti di disegno/spostamento/ridimensionamento, `onDraw(BBox)`, `onChange(id, BBox)`), `EditView(state:send:write:)`.
- Layout come il mockup: Moodboard e Immagine di partenza affiancate, Prompt sotto. Moodboard: `‹ ›` (disattivati ai bordi), nome file, `ref_image_N`, «n di m», badge numerico; tela con le proporzioni dell'immagine, **solo gli origini** dell'immagine mostrata. Immagine di partenza: tela con le proporzioni della Generazione, immagine posizionata da `StageGeometry` (margini a scacchi), badge 1; mostra destinazioni e riquadri locali; «Sposta» con freccia da origine a destinazione. Origine tratteggiata, destinazione piena, selezionato bianco con maniglia; clic su riquadro o mini-card seleziona entrambi. Senza immagine di partenza: «Serve un'immagine di partenza». Mini-card: id modificabile (avviso se ripetuto), menu del tipo (voci: Nuovo, Esistente, Sposta, Togli; «Da riferimento» solo come etichetta non scegliibile), `from: …`, coordinate, `desc`, elimina, frecce su/giù.

- [ ] **Step 1: test di rendering** (come `RenderTests` di F3, PNG in `I4_RENDER_DIR`-simile `F3E_RENDER_DIR`): le tre card con 2 riferimenti e 3 elementi non sono vuote e le proporzioni delle due tele sono quelle attese (Moodboard = immagine, partenza = Generazione); la tela con zoom < 0 ha i margini; i colori dei riquadri di una coppia coincidono.
- [ ] **Step 2:** → FAIL. **Step 3:** implementare le viste (testi in `L`, italiano e inglese). **Step 4:** test → PASS; guardare i PNG.
- [ ] **Step 5: Commit** `feat(flux3-editing): tele e card`.

### Task 9: Invia e Scrivi con LLM

**Files:**
- Create: `Sources/Flux3Editing/{EditSender.swift,EditWriter.swift,EditAnswerParser.swift,EditPrompts.swift,EditLanguage.swift}`, `Data/master-prompt.md`, `Tests/Flux3EditingTests/{SenderTests.swift,WriterTests.swift,AnswerParserTests.swift,LanguageTests.swift,PromptsTests.swift}`; copy+adapt da F3: `F3Sender`, `F3Writer`, `F3AnswerParser`, `F3Language`, `F3Prompts` (+ `DTHubPromptFolder`, installazione all'avvio in `Data/prompt-master-flux3-editing/`, `custom/master-prompt.md`)
- Modify: `Flux3EditingPlugin.swift` (cablare `send`, `write`)

**Interfaces:**
- Produces: `struct EditSender { func send(_ text: String) async -> Outcome }` (`contribute(["fields": ["prompt": text, "negativePrompt": ""]])`); `struct EditWriter { func write(document:system:options:) async -> EditWriteResult }`; il testo all'LLM è Markdown: `## prose` e `## element: <id>` con la `desc`; `static func preserves(original:rewritten:) -> Bool` = **ogni** token tra `<…>` dell'originale è presente e uguale, nessun id nuovo; italiano rilevato → un solo nuovo tentativo, poi resta l'originale; il risultato sostituisce i testi e prende lo snapshot; richiesta/risposta in `llm/`.
- Master prompt: spiega il formato, gli id, `<ref_image_N>`, le regole («translate to English, enrich, never touch `<…>`»), con un esempio completo.

- [ ] **Step 1: test:** `sendWritesPromptAndClearsNegative`; `sendBlockedWithProblems`; `writerKeepsTagsVerbatim` (risposta che cambia `<lamp_1>` → scartata); `writerRetriesOnceWhenItalian`; `writerKeepsOriginalOnSecondFailure`; `parserReadsProseAndElementBlocks`; `masterPromptIsInstalledAndCustomWins`; `undoAfterWriteRestoresTexts`.
- [ ] **Step 2:** → FAIL. **Step 3:** implementare. **Step 4:** → PASS.
- [ ] **Step 5: Commit** `feat(flux3-editing): Invia e Scrivi con LLM`.

### Task 10: README, build, prova a mano, briefing

**Files:**
- Modify: `Plugins/Flux3Editing/README.md` (inglese: cosa fa, i cinque tipi, numerazione, requisito app ≥ 0.3.7, FLUX.2 come segnaposto), `Plugins/README.md` (riga), `docs/superpowers/briefing-prossima-sessione.md` (non in git), nota Obsidian `DT Hub - Flux3 Editing` (cartella `~/eXydian/Progetti/`)

- [ ] **Step 1:** `swift test` di `Plugins/Flux3Editing`, di `Packages` e del kit: tutti verdi; `xcodebuild … build` compila.
- [ ] **Step 2:** `Plugins/Flux3Editing/Scripts/build.sh "$TMPDIR/f3e"`; controllo `file -b` e `codesign --verify`.
- [ ] **Step 3:** consegnare all'utente l'elenco delle prove a mano: installare il bundle (Preferenze › Plug-ins › Add…, riavvio) con l'app Debug del ramo; con immagine di partenza e 3 immagini nel Moodboard su FLUX.2 klein: disegnare sul Moodboard e vedere la coppia; spostare/ridimensionare; i cinque tipi; zoom del canvas di Control (anche < 0) e l'immagine che si muove nella tela; riordinare/spegnere un'immagine nel Moodboard (numeri e riquadri); Scrivi con LLM, Annulla, riavvio, Invia.
- [ ] **Step 4:** aggiornare README, briefing e Obsidian (sezione «Stato», «Prossimi passi»); **non** unire.
- [ ] **Step 5: Commit** `docs(flux3-editing): README e note` (solo i file tracciati, per nome).

---

## Self-review (fatta)

- **Copertura spec:** §1–§3 → T3; §4 → T1–T2, T5, T7; §5 → T4, T6, T8; §6 → T5; §7 → T9; §8 → T7; §9 → T3–T10; rischi/decisioni → Global Constraints, Review Focus e T10.
- **Coerenza dei tipi:** `EditKind`/`EditElement`/`EditDocument` (T4) usati in T5–T9; `RefImage`/`RefNumbering` (T5) in T7–T8; `StageGeometry` (T6) in T8; `DTHubImageWindow` (T2) in T6–T7.
- **Proporzione:** il codice resta da scrivere ai test e alle firme; i corpi non sono nel piano.
