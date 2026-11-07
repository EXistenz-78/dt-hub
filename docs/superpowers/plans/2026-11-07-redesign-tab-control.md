# Redesign della tab Control: piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminare la card Immagine: la lavagna del Canvas riceve il rilascio e ospita i badge, Forza e i due pulsanti passano sotto Zoom e Rotazione, e Canvas e Moodboard diventano card a tutta larghezza.

**Architecture:** Si riorganizzano i pezzi esistenti. Un nuovo `StartImageControls` raccoglie Forza, Adatta e Genera Prompt e si usa nella card Canvas e nella card sottile del Canvas staccato. `CanvasStage` riceve rilascio, badge, stato vuoto con **Scegli…** e riga di informazioni. `ControlTabView` passa da due colonne a una sola.

**Tech Stack:** Swift 6.2, SwiftUI, `App/Localizable.xcstrings`.

**Spec:** `docs/superpowers/specs/2026-11-07-redesign-tab-control-design.md`

## Global Constraints

- Nessuna logica nuova: importazione (`ControlImport`), Forza (`ControlStore.setStrength`), Adatta (`GenerationController.adaptDimensionsToImage`), Genera Prompt (`GenerationController.promptFromImage`) e inquadratura restano quelle di oggi.
- Trascinare un'immagine sulla lavagna la **sostituisce**: nessun pulsante **Sostituisci…**.
- Il badge numero compare solo se `FamilyTraits.of(generation.family(in: connection)).usesMoodboard` e `control.startImageNumber != nil`, come oggi.
- Con il Canvas staccato, Forza e i due pulsanti restano nella tab; senza immagine compare **Scegli…**.
- Stringhe in `App/Localizable.xcstrings` (en e it); riusare le chiavi esistenti. Da togliere: `control.image.replace`, `control.image.title`.
- Commit solo quando l'utente lo chiede; i passi "Commit" sono da eseguire solo se confermato. Come questo è quasi tutto vista, la verifica è build, `CatalogTests` e prova a vista dell'utente.

## Review Focus

- Un file che non è un'immagine rilasciato sulla lavagna: errore nella barra dei messaggi, l'immagine attuale resta (Task 2).
- Famiglia di modelli senza Moodboard: nessun badge numero, la X resta (Task 2).
- Immagine fornita da un plug-in: l'evidenziazione `contributed` è sulla lavagna (Task 2).
- Finestra stretta: Forza e i pulsanti non escono dalla card e vanno a capo (Task 2, Task 3).
- Canvas staccato senza immagine: nella tab c'è **Scegli…** e la finestra staccata accetta il rilascio (Task 3).

## File Structure

- Create `App/Control/StartImageControls.swift`: Forza, Adatta le dimensioni, Genera Prompt, e `ControlMessage`.
- Modify `App/Control/CanvasStage.swift`: rilascio, badge, stato vuoto, riga di informazioni, inserimento dei controlli.
- Modify `App/Control/ControlTabView.swift`: layout a una colonna e card sottile del Canvas staccato.
- Delete `App/Control/ImageCard.swift`.
- Modify `App/Localizable.xcstrings`: togliere due chiavi.

---

### Task 1: StartImageControls

**Files:**
- Create: `App/Control/StartImageControls.swift`
- Modify: `App/Control/ImageCard.swift` (solo per spostare `ControlMessage`)

**Interfaces:**
- Produces: `struct StartImageControls: View { init(generation: GenerationController, connection: DrawThingsConnection, report: @escaping (ControlMessage) -> Void) }` e `enum ControlMessage: Equatable { case error(String); case adapted(Size) }`, spostato da `ImageCard.swift` senza cambiare i casi.
- Con immagine (`control.inputs.image != nil`) mostra, in ordine: la riga Forza (stesso contenuto e note di `ImageCard.strengthRow`), poi **Adatta le dimensioni** e **Genera Prompt** (con `ProgressView` mentre `generation.assistant.working == .describe`, `PromptAssistUndo` e `PromptAssistError(assistant:hiding: .emptyPrompt)`), in una riga che va a capo quando manca spazio. Senza immagine mostra solo il pulsante **Scegli…** (`control.image.choose`, `DSPillButtonStyle(prominent: true)`, azione `ControlImport.choose(into:)` con l'eventuale errore passato a `report(.error(_))`).

- [ ] **Step 1: Create `StartImageControls`** copiando da `ImageCard` il contenuto di `strengthRow` e dei due pulsanti, con i bottoni in un `ViewThatFits` o `HStack` che va a capo (decisione: `FlowLayout`-free, due `HStack` in un `VStack` basta). Sposta `ControlMessage` nel nuovo file e toglilo da `ImageCard.swift`.
- [ ] **Step 2: Build** `xcodebuild -project DTHub.xcodeproj -scheme DTHub -configuration Debug build`. Expected: BUILD SUCCEEDED (`ImageCard` continua a esistere e a compilare).
- [ ] **Step 3: Commit** (se confermato): `git add App/Control && git commit -m "Control: controlli dell'immagine di partenza in un componente"`

### Task 2: CanvasStage: rilascio, badge, stato vuoto, informazioni

**Files:**
- Modify: `App/Control/CanvasStage.swift`

**Interfaces:**
- Consumes: `StartImageControls(generation:connection:report:)`, `ControlMessage`, `ControlImport.take(urls:into:)`, `ControlImport.choose(into:)`, `ImageNumberBadge(number:)`, `View.contributed(_ isContributed: Bool)`, `ControlText.source(_:plugins:)`.
- Produces: `CanvasStage` con un nuovo parametro `connection: DrawThingsConnection`; i punti d'uso (`ControlTabView`, `CanvasWindowView`) vengono aggiornati nel Task 3 e qui.

- [ ] **Step 1: Aggiungere `let connection: DrawThingsConnection` a `CanvasStage`** e passarlo dai due punti d'uso (`ControlTabView.content`, `CanvasWindowView`). Build. Expected: BUILD SUCCEEDED.
- [ ] **Step 2: Rilascio.** Un modificatore privato `imageDrop(isTargeted:)` che applica `dropDestination(for: URL.self)` chiamando `ControlImport.take(urls:into: control)` e passando l'eventuale stringa a `report(.error(_))`, con bordo `DS.accent` di 2 pt quando `isTargeted`. Applicarlo al corpo della card (`VStack` in `card`) e a `windowContent`, così vale in modalità Canvas e Disegno e nella finestra staccata.
- [ ] **Step 3: Badge sulla lavagna.** In `stageContent(for:)`, in overlay sulla lavagna: in alto a destra un pulsante `xmark.circle.fill` (azione `control.removeImage()`, etichetta `control.image.remove`) e in basso a destra `ImageNumberBadge(number:)` con le condizioni dei Global Constraints; distanza dal bordo 8 pt. Applicare `.contributed(contributions?.startImage?.id == image.id)` alla lavagna (con `@Environment(ContributionStore.self)` come in `ImageCard`).
- [ ] **Step 4: Stato vuoto.** `empty` diventa la zona tratteggiata con `control.image.drop` e il pulsante **Scegli…** (`ControlImport.choose(into:)`), mantenendo `aspectRatio` e `frame(maxHeight: 300)`.
- [ ] **Step 5: Controlli e informazioni.** Inserire `StartImageControls(...)` dopo `rotationRow` e prima di `caption(for:)`. In `caption(for:)` aggiungere come prima riga `Text("\(image.name) · \(String(format: String(localized: "control.image.info"), image.pixelWidth, image.pixelHeight, ControlText.source(image.source, plugins: plugins)))")` (con `@Environment(PluginRegistry.self) private var plugins: PluginRegistry?`), in `.font(.caption)`, `.lineLimit(2)`.
- [ ] **Step 6: Altezza della lavagna.** Sostituire il `330` di `sized(ratio:)` con una costante `private static let chromeHeight: Double` più alta (Forza e pulsanti occupano righe in più), partendo da 460, da tarare a vista nel Task 3.
- [ ] **Step 7: Build.** Expected: BUILD SUCCEEDED.
- [ ] **Step 8: Commit** (se confermato): `git add App/Control && git commit -m "Canvas: rilascio dell'immagine, badge, stato vuoto e informazioni"`

### Task 3: Layout della tab, card sottile, pulizia

**Files:**
- Modify: `App/Control/ControlTabView.swift`, `App/Localizable.xcstrings`
- Delete: `App/Control/ImageCard.swift`

**Interfaces:**
- Consumes: `CanvasStage(generation:connection:report:detach:)`, `CanvasDetachedNote`, `StartImageControls`, `MoodboardCard(generation:connection:report:)`.

- [ ] **Step 1: Layout.** In `ControlTabView.content` sostituire `DSCardRow { … }` con un `VStack(spacing: DS.groupGap)`: se `canvasWindow.isOpen`, `CanvasDetachedNote()` seguita da una card sottile (`.dsPanel()`) con `StartImageControls`; altrimenti `CanvasStage` a tutta larghezza. Poi `MoodboardCard` a tutta larghezza. Passare `connection` a `CanvasStage`.
- [ ] **Step 2: Eliminare `ImageCard.swift`** e togliere dalle stringhe `control.image.replace` e `control.image.title` (script Python sul JSON, come per le chiavi aggiunte: nessun riordino del file).
- [ ] **Step 3: Build** e `swift test --package-path Packages --filter CatalogTests`. Expected: BUILD SUCCEEDED, test passati.
- [ ] **Step 4: Suite completa** `swift test --package-path Packages`. Expected: tutto PASS.
- [ ] **Step 5: Prova a vista (utente).** Aprire la build di debug e controllare: senza immagine (zona tratteggiata e **Scegli…**); trascinare un'immagine dal Finder; trascinarne una seconda (sostituisce, e la notifica "sostituita" compare); X e numero sui due angoli; Forza, Adatta, Genera Prompt sotto Zoom e Rotazione; modalità Disegno con rilascio; Canvas staccato (card sottile con i controlli); finestra larga e stretta; Moodboard sotto a tutta larghezza. Tarare `chromeHeight` se la lavagna risulta troppo alta o bassa.
- [ ] **Step 6: Commit** (se confermato): `git add App docs && git commit -m "Control: tab a una colonna, card Immagine eliminata"`
