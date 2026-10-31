# Esplora: galleria globale — piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aggiungere alla finestra Risultati la tab «Esplora»: griglia globale di tutte le immagini di tutti i progetti e delle cartelle extra, con ricerca sui metadati, preferiti e anteprima con la barra spaziatrice; togliere il seed dalla riga in basso.

**Architecture:** La logica (indice, ricerca, preferiti, cartelle extra, modello osservabile) sta in `Packages/Sources/HubCore/Gallery/` ed è testata con `swift test`. La vista sta in `App/Results/` (nuovo `ExploreView.swift`) e riusa `ResultInfoSidebar`, `ResultInfo`, le azioni di `GenerationController` e `ResultSelection` (reso generico). Le immagini della galleria diventano `GeneratedImage` «ripristinate» da file, così sidebar, Riprendi parametri, Usa come immagine e Moodboard funzionano senza altro codice.

**Tech Stack:** Swift 6, SwiftUI/AppKit, ImageIO, Swift Testing (`@Test`, `#expect`), `QLPreviewPanel` (Quartz).

**Spec:** `docs/superpowers/specs/2026-10-31-esplora-galleria-globale-design.md` (mockup: `docs/superpowers/mockups/esplora-mockup.html`).

## Global Constraints

- Si risponde e si scrive in italiano (testi dell'interfaccia in `App/Localizable.xcstrings`, italiano e inglese come le altre chiavi).
- Lavoro sul ramo `feature/risultati-esplora`; nessuna unione in `main`, nessun push, senza un esplicito via libera dell'utente.
- `git add` sempre per nome di file, mai `git add -A` (nel repo ci sono file non tracciati di altri lavori); ogni commit finisce con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Test dei pacchetti: `swift test` da `Packages`. Build dell'app: `xcodebuild -project DTHub.xcodeproj -scheme DTHub -configuration Debug -destination 'platform=macOS' -derivedDataPath build build`.
- Miniature della griglia 108 pt (strip: 72 pt, +50%); caricate a 216 px.
- Ricerca: parole tutte presenti (AND), senza maiuscole/accenti, ritardo 200 ms.
- File dell'app in `~/Library/Application Support/DT Hub/`: `gallery-folders.json`, `gallery-index.json`, `favorites.json` (scrittura atomica). L'app non è in sandbox.
- Nei testi pubblici non si dice che DT Hub «sostituisce» l'interfaccia di Draw Things.
- Test-first (RED poi GREEN) per tutto ciò che sta nei pacchetti.

## Review Focus

- Le cartelle nascoste (`.dthub` contiene copie PNG di Control) non devono finire in galleria: test nell'Task 3.
- Un PNG illeggibile o senza metadati entra lo stesso (col nome file) e non blocca la scansione: Task 3.
- Un file spostato/cancellato fuori dall'app esce dall'indice al giro dopo e dai preferiti a vista: Task 3 e 6.
- Cancellare dalla galleria un'immagine che è anche nella strip Risultati non deve lasciare una voce fantasma nella strip: Task 9.
- Filtro/ricerca che nasconde la selezione: la selezione si riduce a ciò che è visibile, mai a una voce invisibile: Task 6.

---

### Task 1: `ResultSelection` generico

**Files:**
- Modify: `Packages/Sources/HubCore/Generation/ResultSelection.swift`
- Modify: `App/Results/ResultsView.swift` (riga 13: `@State private var picks = ResultSelection()` → `ResultSelection<GeneratedImage.ID>()`)
- Test: `Packages/Tests/HubCoreTests/ResultSelectionTests.swift`

**Interfaces:**
- Produces: `public struct ResultSelection<ID: Hashable & Sendable>: Equatable, Sendable` con gli stessi membri di oggi (`ids: Set<ID>`, `primary: ID?`, `anchor: ID?`, `init()`, `init(only: ID?)`, `click`, `step`, `selectAll`, `afterRemoval`, `keepOnly`), tutti sugli `ID` generici. Nessun metodo nuovo: ↑/↓ nella griglia usano `step(±columns, order:)`.

- [ ] **Step 1: Write the failing test** — in `ResultSelectionTests`: `stepByAFullRowMovesDownAndStopsAtTheEnd` con `order` di 5 `Int` (`ResultSelection<Int>(only: 0)`, `step(3, order: [0,1,2,3,4])` → primary 3; ancora `step(3,…)` → 4, `step(-3,…)` da 1 → 0) e `worksWithStringIds` (`ResultSelection(only: "a.png")` + `click("c.png", command: true, shift: false, order: ["a.png","b.png","c.png"])` → `ids == ["a.png","c.png"]`).
- [ ] **Step 2: Run** `cd Packages && swift test --filter ResultSelectionTests` — Expected: FAIL (non compila: tipo non generico).
- [ ] **Step 3: Rendere generica** la struct sostituendo `UUID` con `ID` in tutto il file; `ResultsView` usa `ResultSelection<GeneratedImage.ID>()`.
- [ ] **Step 4: Run** `swift test` completo da `Packages` e build dell'app — Expected: tutti i test verdi (compresi `ResultSelectionTests` e `ResultsNavigationTests` esistenti), build ok.
- [ ] **Step 5: Commit** `git add Packages/Sources/HubCore/Generation/ResultSelection.swift Packages/Tests/HubCoreTests/ResultSelectionTests.swift App/Results/ResultsView.swift` — «ResultSelection: generico sull'id (per la galleria)».

### Task 2: Cartelle extra e preferiti (store su file)

**Files:**
- Create: `Packages/Sources/HubCore/Gallery/GalleryStores.swift`
- Test: `Packages/Tests/HubCoreTests/GalleryStoresTests.swift`

**Interfaces:**
- Produces:
  - `public struct GalleryFoldersStore: Sendable { public init(fileURL: URL); public static var defaultFileURL: URL; public func load() -> [URL]; public func save(_ folders: [URL]) }` — file JSON con array di percorsi (`gallery-folders.json`); file mancante o rotto = `[]`.
  - `public struct FavoritesStore: Sendable { public init(fileURL: URL); public static var defaultFileURL: URL; public func load() -> Set<String>; public func save(_ paths: Set<String>) }` — `favorites.json`, percorsi come stringhe.
  - Entrambi: `defaultFileURL` = Application Support / `DT Hub` / nome file; `save` crea la cartella e scrive `.atomic`; un errore di scrittura non lancia (come `ResultsHistoryStore`).

- [ ] **Step 1: Write the failing tests** — `foldersRoundTrip` (salva due URL, `load()` li restituisce nello stesso ordine), `missingOrBrokenFileIsEmpty` (file assente → `[]`; file con `"{"` → `[]` per entrambi gli store), `favoritesRoundTrip` (insieme di tre percorsi), `saveCreatesTheFolder` (fileURL in sottocartella non esistente).
- [ ] **Step 2: Run** `swift test --filter GalleryStoresTests` — Expected: FAIL (tipi non definiti).
- [ ] **Step 3: Implement** i due store in `GalleryStores.swift` seguendo `ResultsHistoryStore` (JSONEncoder/Decoder, cartella `DT Hub`).
- [ ] **Step 4: Run** `swift test --filter GalleryStoresTests` — Expected: PASS.
- [ ] **Step 5: Commit** `git add Packages/Sources/HubCore/Gallery/GalleryStores.swift Packages/Tests/HubCoreTests/GalleryStoresTests.swift` — «Galleria: store delle cartelle extra e dei preferiti».

### Task 3: Indice della galleria (`GalleryEntry`, `GalleryIndex`)

**Files:**
- Create: `Packages/Sources/HubCore/Gallery/GalleryIndex.swift`
- Modify: `Packages/Sources/HubCore/Output/ImageStore.swift` (aggiungere `PNGImageStore.description(in:)`)
- Test: `Packages/Tests/HubCoreTests/GalleryIndexTests.swift`

**Interfaces:**
- Consumes: `ProjectCatalog(outputFolder:).projects()`, `ProjectImages.allImages(in:)`, `PNGImageStore.comment(in:)`, `PNGImageStore.videoURL(forPoster:)`.
- Produces:
  - `PNGImageStore.description(in url: URL) -> String?` — il PNG «Description» (`kCGImagePropertyPNGDescription`).
  - `public struct GalleryEntry: Codable, Equatable, Identifiable, Sendable { public let path: String; public let date: Date; public let project: String; public let searchText: String; public let fileSize: Int; public let modified: Date; public var id: String { path }; public var url: URL }`
  - `public struct GalleryIndex: Sendable { public init(cacheURL: URL); public static var defaultCacheURL: URL; public func cached() -> [GalleryEntry]; public func refresh(outputFolder: URL, extraFolders: [URL]) -> [GalleryEntry] }` — `refresh` è sincrono e pesante (si chiama da `Task.detached`); scrive la cache a fine giro; restituisce le voci ordinate per `date` decrescente.
  - `public static func searchKey(_ text: String) -> String` (su `GalleryEntry`): minuscolo e senza accenti (`folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)`).

- [ ] **Step 1: Write the failing tests** (cartelle temporanee, immagini con `PNGImageStore(folder:).save(testImage(), job:…)`; due progetti creati con `ProjectCatalog.create`):
  - `indexesEveryProjectAndNamesTheProject` (3 immagini in 2 progetti → 3 voci, `project` giusto, ordine per data decrescente).
  - `searchTextHoldsPromptAndModel` (job con prompt «luna piena» e model «flux2.ckpt» → `searchText` contiene `luna piena` e `flux2`, e vale la `searchKey` accentata: prompt «Città» → contiene `citta`).
  - `secondRefreshRereadsOnlyChangedFiles` (conta le letture con un contatore iniettato: `refresh(…, reader:)` — il lettore dei metadati è un parametro interno `@Sendable (URL) -> String` di default reale; al secondo giro 0 letture, dopo aver aggiunto un file 1).
  - `removedFileLeavesTheIndex`.
  - `hiddenFoldersAreSkippedInExtraFolders` (cartella extra con `.dthub/Control/x.png` e `a.png` → solo `a.png`).
  - `extraFolderInsideTheOutputIsNotCountedTwice`.
  - `unreadablePNGStillEnters` (file `.png` con byte casuali → voce con `searchText` = nome file).
  - `cacheSurvivesBetweenInstances` (`cached()` di una nuova istanza = ultimo risultato).
  - `descriptionIsReadBack` (`PNGImageStore.description(in:)` = prompt salvato).
- [ ] **Step 2: Run** `swift test --filter GalleryIndexTests` — Expected: FAIL.
- [ ] **Step 3: Implement.** Fonti: per ogni `Project` del catalogo `ProjectImages.allImages(in: project.folder)`; per ogni cartella extra un `FileManager.enumerator` con `.skipsHiddenFiles` filtrando `.png`. Dedup per percorso standardizzato (`standardizedFileURL.path`). `searchText` = `searchKey(description + " " + comment + " " + project + " " + nome file)`. Riuso della voce se `path`, `fileSize` e `modified` coincidono con la cache. Il nome di progetto di un file in cartella extra è il nome della cartella extra.
- [ ] **Step 4: Run** `swift test --filter GalleryIndexTests` — Expected: PASS.
- [ ] **Step 5: Commit** `git add Packages/Sources/HubCore/Gallery/GalleryIndex.swift Packages/Sources/HubCore/Output/ImageStore.swift Packages/Tests/HubCoreTests/GalleryIndexTests.swift` — «Galleria: indice incrementale delle immagini».

### Task 4: Ricerca e filtro preferiti

**Files:**
- Create: `Packages/Sources/HubCore/Gallery/GalleryFilter.swift`
- Test: `Packages/Tests/HubCoreTests/GalleryFilterTests.swift`

**Interfaces:**
- Consumes: `GalleryEntry` (Task 3), `GalleryEntry.searchKey`.
- Produces: `public enum GalleryFilter { public static func apply(_ entries: [GalleryEntry], query: String, onlyFavorites: Bool, favorites: Set<String>) -> [GalleryEntry] }` — conserva l'ordine; query vuota o solo spazi = nessun filtro di testo.

- [ ] **Step 1: Write the failing tests:** `allTermsMustMatch` («flux luna» trova solo la voce con entrambe), `ignoresCaseAndAccents` («CITTA» trova «Città»), `blankQueryKeepsEverything`, `favoritesOnlyCombinesWithText`, `keepsTheOrder`. Le voci si costruiscono direttamente (`GalleryEntry(path:…)` con `searchText` scelto).
- [ ] **Step 2: Run** `swift test --filter GalleryFilterTests` — Expected: FAIL.
- [ ] **Step 3: Implement** `apply`: divide `searchKey(query)` sugli spazi, richiede `searchText.contains` per ogni parola.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `git add Packages/Sources/HubCore/Gallery/GalleryFilter.swift Packages/Tests/HubCoreTests/GalleryFilterTests.swift` — «Galleria: ricerca per parole e filtro preferite».

### Task 5: `GeneratedImage` da file

**Files:**
- Modify: `Packages/Sources/HubCore/Generation/GenerationSession.swift` (estrarre il corpo di `restoredImage(_:)`, righe ~263-277)
- Test: `Packages/Tests/HubCoreTests/GeneratedImageFromFileTests.swift`

**Interfaces:**
- Produces: `extension GeneratedImage { public static func fromFile(_ url: URL, date: Date, maxPixel: Int) -> GeneratedImage? }` — nil se il PNG non ha un job leggibile o non si decodifica; altrimenti `isRestored = true`, `elapsed`, e per i video `videoURL`/`videoSeconds` come oggi. `restoredImage` la chiama con `restoredThumbnailSize`.

- [ ] **Step 1: Write the failing tests:** `buildsFromAnImageSavedByTheStore` (job e `fileURL` e `isRestored == true`, immagine con lato ≤ `maxPixel`), `nilForAPNGWithoutAJob` (PNG scritto con `CGImageDestination` senza metadati), `restoreHistoryStillWorks` (i test esistenti di `GenerationSessionTests` restano verdi).
- [ ] **Step 2: Run** `swift test --filter GeneratedImageFromFileTests` — Expected: FAIL.
- [ ] **Step 3: Implement** spostando il codice esistente in `fromFile` (nessun cambio di comportamento).
- [ ] **Step 4: Run** `swift test` completo da `Packages` — Expected: tutto verde.
- [ ] **Step 5: Commit** `git add Packages/Sources/HubCore/Generation/GenerationSession.swift Packages/Tests/HubCoreTests/GeneratedImageFromFileTests.swift` — «GeneratedImage.fromFile: base per la galleria».

### Task 6: `GalleryModel` (stato osservabile)

**Files:**
- Create: `Packages/Sources/HubCore/Gallery/GalleryModel.swift`
- Test: `Packages/Tests/HubCoreTests/GalleryModelTests.swift`

**Interfaces:**
- Consumes: `GalleryFoldersStore`, `FavoritesStore` (Task 2), `GalleryIndex`, `GalleryFilter` (Tasks 3-4), `ResultSelection<String>` (Task 1).
- Produces: `@MainActor @Observable public final class GalleryModel`:
  - `public init(outputFolder: URL, folders: GalleryFoldersStore, favorites: FavoritesStore, index: GalleryIndex)`
  - stato: `public private(set) var entries: [GalleryEntry]`, `public private(set) var isIndexing: Bool`, `public private(set) var extraFolders: [URL]`, `public private(set) var favorites: Set<String>`, `public var query: String`, `public var onlyFavorites: Bool`, `public var selection: ResultSelection<String>`
  - `public var visible: [GalleryEntry]` (applica `GalleryFilter`)
  - azioni: `public func refresh() async` (mostra subito `index.cached()`, poi `Task.detached` con `index.refresh`), `public func setOutputFolder(_ url: URL)`, `public func addFolder(_ url: URL)`, `public func removeFolder(_ url: URL)` (entrambe salvano e rifanno `refresh`), `public func toggleFavorite(_ path: String)`, `public func removeEntries(_ paths: Set<String>)` (toglie da `entries`, dai preferiti e dalla selezione, salva), `public func clampSelection()` (riduce la selezione alle voci di `visible`; con selezione vuota e `visible` non vuoto non sceglie nulla da sola).

- [ ] **Step 1: Write the failing tests:** `refreshShowsTheCacheFirstThenTheScan`, `addingAFolderPersistsAndIndexesIt` (nuovo `GalleryModel` sullo stesso store ritrova la cartella), `removingAFolderDropsItsImages`, `toggleFavoritePersists`, `visibleFollowsQueryAndFavorites`, `removeEntriesDropsFavoritesAndSelection`, `clampSelectionKeepsOnlyVisible` (selezione di due, la query nasconde una → resta una).
- [ ] **Step 2: Run** `swift test --filter GalleryModelTests` — Expected: FAIL.
- [ ] **Step 3: Implement** il modello (azioni sincrone sullo stato, scansione fuori dal main actor).
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `git add Packages/Sources/HubCore/Gallery/GalleryModel.swift Packages/Tests/HubCoreTests/GalleryModelTests.swift` — «Galleria: modello osservabile».

### Task 7: Tab «Risultati/Esplora» e seed tolto

**Files:**
- Modify: `App/Results/ResultsView.swift` (stato `tab`, riga in basso, rimozione del seed in `actions(for:)`, righe ~413-427)
- Create: `App/Results/ExploreView.swift` (segnaposto: `Text("Esplora")`, completato nel Task 8)
- Modify: `App/Localizable.xcstrings` (chiavi `results.tab.results` «Risultati»/«Results», `results.tab.explore` «Esplora»/«Explore»)

**Interfaces:**
- Produces: `enum ResultsTab { case results, explore }` (in `ResultsView.swift`); `ResultsView` ha `@State private var tab: ResultsTab = .results`; la riga dei pulsanti è disegnata **sempre** (anche con `session.results` vuota, in Esplora), con a sinistra le due tab (`Button` con `DSTabButtonStyle(isSelected:)`, testo e non solo icona), poi «N selezionate» e gli errori, e a destra i pulsanti di oggi. Il seed non compare più.
- `ExploreView` per ora: `struct ExploreView: View { let controller: GenerationController; let connection: DrawThingsConnection; var body: some View }`.

- [ ] **Step 1: Verificare lo stato attuale** — build (`xcodebuild … build`) ok prima di toccare.
- [ ] **Step 2: Implement** il layout: in `.results` il corpo è quello di oggi (area immagine, stato, strip); in `.explore` il corpo è `ExploreView`. La riga in basso è lo stesso componente per entrambe: in `.results` con la logica di `actions(for:)` meno il seed (se `session.results` è vuota la riga mostra solo le tab, come oggi non c'era riga: i pulsanti a destra solo se c'è un risultato); in `.explore` i pulsanti arriveranno dal Task 9.
- [ ] **Step 3: Run build** — Expected: ok. Aprire l'app Debug: le due tab si vedono, «Risultati» identica a prima salvo il seed, «Esplora» mostra il segnaposto.
- [ ] **Step 4: Commit** `git add App/Results/ResultsView.swift App/Results/ExploreView.swift App/Localizable.xcstrings` — «Risultati: tab Risultati/Esplora al posto del seed».

### Task 8: Griglia di Esplora (celle, ricerca, stelle, cartelle)

**Files:**
- Modify: `App/Results/ExploreView.swift`
- Create: `App/Results/GalleryThumbnails.swift`
- Modify: `App/Results/ResultsView.swift` (crea e passa il `GalleryModel`)
- Modify: `App/Localizable.xcstrings`

**Interfaces:**
- Consumes: `GalleryModel` (Task 6), `PNGImageStore.image(at:maxPixel:)`.
- Produces:
  - `final class GalleryThumbnails { static let shared; func image(for url: URL, maxPixel: Int) async -> CGImage? }` — `NSCache<NSString, CGImage-box>` con `totalCostLimit` (≈ 200 MB), decodifica fuori dal main actor.
  - `ExploreView` riceve `model: GalleryModel` (creato in `ResultsView` con `outputFolder: controller.outputFolder` e gli store di default; `model.setOutputFolder` quando cambia `controller.outputFolder`); parte con `.task { await model.refresh() }` e rifà `refresh()` quando cambia `session.results.first?.id`.
  - Barra superiore: `+` (`NSOpenPanel`, `canChooseDirectories`, solo cartelle → `model.addFolder`), `Menu` «Cartelle Extra ▾» (voci per le cartelle con «Elimina», o testo «Nessuna cartella aggiunta»), spazio, `Toggle`/pulsante `star` (acceso = `onlyFavorites`; solo icona, `help` «Solo preferite»), `TextField` «Cerca nei metadati…» con ritardo di 200 ms (`.task(id: draft)` con `Task.sleep`) che scrive `model.query`; margine a destra per il pulsante sidebar. Stato «Indicizzo…» discreto se `model.isIndexing`.
  - Griglia: `LazyVGrid(columns: [GridItem(.adaptive(minimum: 108, maximum: 108), spacing: 8)])` in `ScrollView`; cella 108×108 con `DS.boxRadius`, bordo `DS.accent` 2 pt se selezionata, stella in alto a sinistra (`toggleFavorite`), nome del progetto in basso al passaggio del mouse, segnaposto finché la miniatura non arriva. Vuota: `ContentUnavailableView` («Nessuna immagine corrisponde» / «Nessuna immagine nelle cartelle»).
  - Selezione: clic con ⌘/⇧ come `ResultsView.click`, `⌘A` (`.onCommand(selectAll)`), frecce con `ArrowKeyMonitor` esteso (vedi sotto) → `model.selection.step(delta, order:)`, ↑/↓ = `±columns`; `columns` si calcola da `GeometryReader` (`max(1, Int((width + 8) / 116))`). `model.clampSelection()` quando cambiano `query`/`onlyFavorites`/`entries`. Pulsante sidebar come in `imageArea` (stesso `@AppStorage("results.sidebar.open")`).
- `ArrowKeyMonitor` in `ResultsView.swift`: renderlo non privato (`struct ArrowKeyMonitor`, livello modulo, in `App/Results/KeyMonitors.swift` insieme a `DeleteKeyMonitor`) e farlo gestire anche i codici 125 (↓ → +) e 126 (↑ → −) tramite un secondo callback opzionale `onVertical: ((Int) -> Void)?`; in Risultati resta com'è (nessun `onVertical`).

- [ ] **Step 1: Implement** `GalleryThumbnails`, la barra superiore, la griglia e la selezione; spostare i monitor in `KeyMonitors.swift` (solo spostamento + `onVertical`).
- [ ] **Step 2: Build** — Expected: ok, nessun warning nuovo.
- [ ] **Step 3: Prova a mano** nell'app Debug: Esplora mostra le immagini dei progetti (celle da 108 pt), la ricerca per parole (prompt, modello, LoRA) filtra, stella e filtro ★ funzionano e restano al riavvio, «+» aggiunge una cartella e il menu la toglie, ⌘/⇧-clic, ⌘A e le quattro frecce.
- [ ] **Step 4: Commit** `git add App/Results/ExploreView.swift App/Results/GalleryThumbnails.swift App/Results/KeyMonitors.swift App/Results/ResultsView.swift App/Localizable.xcstrings` — «Esplora: griglia, ricerca, preferiti e cartelle extra».

### Task 9: Azioni sulla selezione, sidebar, menu contestuale, trascinamento, cestino

**Files:**
- Modify: `App/Results/ExploreView.swift`, `App/Results/ResultsView.swift`
- Create: `App/Results/GalleryActions.swift`

**Interfaces:**
- Consumes: `GeneratedImage.fromFile` (Task 5), `ResultInfoSidebar(image:selectionCount:)`, `controller.control.setImage(fileURL:source:)`, `controller.control.addMoodboardImage(fileURL:source:)`, `controller.resume(_:with:)`, `PNGImageStore(folder:).trash(_:)`, `session.remove(_:)`.
- Produces: `@MainActor enum GalleryActions` con
  - `static func image(for entry: GalleryEntry) async -> GeneratedImage?` (usa `fromFile(maxPixel: 2048)` fuori dal main actor; serve a sidebar e a Riprendi parametri);
  - `static func trash(_ entries: [GalleryEntry], controller: GenerationController, model: GalleryModel) -> [String]` — prima `session.remove` per i risultati della strip il cui `fileURL.path` coincide, poi `PNGImageStore(folder:).trash` per gli altri, poi `model.removeEntries`; restituisce i messaggi d'errore.
- La riga dei pulsanti in Esplora: «Usa come immagine» e «Riprendi parametri» (solo con una immagine e job leggibile; altrimenti disattivi), «Aggiungi al Moodboard», Finder (`NSWorkspace.activateFileViewerSelecting`), Cestino; «N selezionate» e gli errori accanto alle tab. La sidebar mostra `ResultInfoSidebar(image:selectionCount:)` con l'immagine caricata dell'immagine primaria. Menu contestuale della cella = quello della strip (Usa come immagine solo se una; Moodboard; Cestino) sui `targets` (la selezione se la cella ne fa parte, altrimenti la cella). Trascinamento: `.draggable(containerItemID:)` + `.dragContainer(for:)` come la strip, con `DraggedResult` (rendere non privato, in `KeyMonitors.swift` o file proprio). ⌫ (`DeleteKeyMonitor`) attivo dopo un clic nella griglia.

- [ ] **Step 1: Implement** `GalleryActions` e collegare i pulsanti, il menu, il trascinamento e ⌫.
- [ ] **Step 2: Build** — Expected: ok.
- [ ] **Step 3: Prova a mano:** Usa come immagine, Moodboard (più immagini), Riprendi parametri (i campi del Control si riempiono e il modello viene scelto), Finder, Cestino di un'immagine che è anche nella strip Risultati (la strip la perde, nessuna voce fantasma), trascinamento di una selezione multipla su Control, sidebar con prompt/modello/LoRA.
- [ ] **Step 4: Commit** `git add App/Results/GalleryActions.swift App/Results/ExploreView.swift App/Results/ResultsView.swift App/Results/KeyMonitors.swift` — «Esplora: azioni sulla selezione, sidebar, trascinamento e cestino».

### Task 10: Anteprima con la barra spaziatrice (Quick Look)

**Files:**
- Create: `App/Results/QuickLookMonitor.swift`
- Modify: `App/Results/ExploreView.swift`, `App/Localizable.xcstrings` (se serve un'etichetta di accessibilità)

**Interfaces:**
- Produces: `struct QuickLookMonitor: NSViewRepresentable { var url: URL?; var isEnabled: Bool }` — monitor locale `.keyDown` per la barra spaziatrice (keyCode 49) come `ArrowKeyMonitor`: agisce solo se `isEnabled`, la finestra è quella e chiave, `!(firstResponder is NSText)` e senza modificatori; con `url != nil` fa apparire/sparire `QLPreviewPanel.shared()`; se il pannello è già visibile lo chiude. Il coordinatore è `QLPreviewPanelDataSource` con un solo elemento (`QLPreviewItem` = l'URL, non il PNG di un video: il suo MP4 se esiste); quando `url` cambia a pannello aperto fa `reloadData()`. Esc chiude (comportamento del pannello).
- In `ExploreView`: `QuickLookMonitor(url: <file della sola immagine selezionata>, isEnabled: tab attiva e selezione di una sola immagine)`; con più immagini selezionate o nessuna, `url` è nil e lo spazio non fa nulla. Il campo di ricerca che ha il fuoco non riceve interferenze (c'è `NSText` come first responder).

- [ ] **Step 1: Implement** il monitor e collegarlo.
- [ ] **Step 2: Build** — Expected: ok.
- [ ] **Step 3: Prova a mano:** spazio con una immagine → anteprima; spazio o Esc → si chiude; con due immagini selezionate non succede nulla; scrivendo uno spazio nel campo di ricerca non si apre nulla; frecce a pannello aperto → l'anteprima segue la selezione; in «Risultati» lo spazio non fa nulla.
- [ ] **Step 4: Commit** `git add App/Results/QuickLookMonitor.swift App/Results/ExploreView.swift App/Localizable.xcstrings` — «Esplora: anteprima con la barra spaziatrice».

### Task 11: Verifica finale e documenti

**Files:**
- Modify: `docs/superpowers/briefing-prossima-sessione.md` (nuova sezione «Esplora» in fondo: ramo, cosa fa, file nuovi, limiti: preferiti legati al percorso, indice in `gallery-index.json`)

- [ ] **Step 1: Run** `cd Packages && swift test` — Expected: tutto verde (il numero dei test sale rispetto ai 1029 di HubCore + altri).
- [ ] **Step 2: Build Debug** con il comando dei vincoli — Expected: `BUILD SUCCEEDED`, nessun warning nuovo.
- [ ] **Step 3: Prova a mano completa** secondo la lista dei Task 8-10 e dello spec (§Test), compreso il riavvio dell'app (preferiti, cartelle extra e indice restano) e una cartella extra con PNG non creati da DT Hub.
- [ ] **Step 4: Aggiornare il briefing** e committare `git add docs/superpowers/briefing-prossima-sessione.md` — «Briefing: Esplora».
- [ ] **Step 5: Dire all'utente** che il ramo è pronto per la prova e che l'unione in `main` (e poi la ricompilazione dell'app Debug) aspetta il suo «unisci».
