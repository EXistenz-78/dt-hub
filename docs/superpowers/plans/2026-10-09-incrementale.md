# Modalità incrementale — Piano di implementazione

> **Per chi esegue:** SOTTO-SKILL OBBLIGATORIA: `superpowers:subagent-driven-development` (consigliata) oppure `superpowers:executing-plans`. I passi usano la sintassi a caselle (`- [ ]`).

**Obiettivo:** interruttore nell'header: acceso, il risultato di ogni RUN diventa l'immagine di partenza di Control.

**Architettura:** la decisione «quale immagine, e se» è una funzione pura in HubCore (`IncrementalRun.output`) che riusa `PipelineInputs.output`; `GenerationSession` distingue Stop dalla fine normale; `GenerationController` attende la fine del RUN e applica; `HeaderBar` ha il pulsante.

**Tecnologie:** Swift 6.2, Swift Testing, SwiftUI.

**Spec:** `docs/superpowers/specs/2026-10-09-incrementale-design.md`.

## Vincoli globali

- Base: `origin/main` (0.1.3). Ramo nuovo (es. `incrementale`). **Niente unione in `main`, push o release senza via libera esplicito.**
- File aggiunti **per nome**; mai `git add -A` né `git add docs`.
- Test: `cd Packages && swift test --filter <Suite> 2>&1 | grep -E "Test run with|error:"`; test `@MainActor`.
- App: `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build`.
- Testi it/en in `Localizable.xcstrings` (`extractionState: manual`). Commenti in inglese.

## Review Focus

1. Stop durante il RUN con alcune immagini già arrivate (batch multipli): nessun cambiamento dell'immagine di partenza (Task 1, Task 2).
2. Interruttore spento: il comportamento di RUN e pipeline non cambia di una virgola (Task 1, Task 3).
3. Risultato non salvato su disco (`fileURL == nil`): entra lo stesso, dall'immagine in memoria (Task 3).
4. RUN fallito dopo un batch riuscito: niente cambio (Task 1).
5. Stop durante la preparazione (prima che il RUN parta): nessun cambio, nessun blocco (Task 3).

---

### Task 1: `GenerationSession.lastRunWasStopped` e `IncrementalRun`

**Files:**
- Modify: `Packages/Sources/HubCore/Generation/GenerationSession.swift`
- Create: `Packages/Sources/HubCore/Generation/IncrementalRun.swift`
- Test: `Packages/Tests/HubCoreTests/IncrementalRunTests.swift`, nuovi casi in `GenerationSessionTests.swift`

**Interfaces:**
- Consumes: `PipelineInputs.output(after:in:)`, `GenerationSession.Phase`, `GeneratedImage`.
- Produces: `public private(set) var lastRunWasStopped: Bool` in `GenerationSession`; `IncrementalRun.output(enabled:phase:stopped:before:results:) -> GeneratedImage?` (firma nella spec §4).

- [ ] **Step 1: Test che falliscono**:
  - `GenerationSessionTests`: dopo `start` + `cancel()` + `waitUntilFinished()` → `lastRunWasStopped == true`; un RUN completo → `false`; l'inizio di un nuovo RUN lo riporta a `false` anche se il precedente era stoppato; un RUN fallito → `false` (il fallimento è in `phase`).
  - `IncrementalRunTests` (immagini con `testImage()` e un job di prova): `enabled false` → nil; `phase .failed` → nil (**Review Focus 4**); `stopped true` → nil anche con immagini nuove (**Review Focus 1**); nessuna immagine nuova (`results.first?.id == before`) → nil; immagine nuova → `results.first`; `before nil` e `results` con un elemento → quello.
- [ ] **Step 2: Vedere il fallimento** — `swift test --filter IncrementalRun` e `--filter GenerationSession`.
- [ ] **Step 3: Implementare** (`lastRunWasStopped = false` dove `start` imposta la fase `.running`; `true` nel `catch is CancellationError`).
- [ ] **Step 4: Test verdi.**
- [ ] **Step 5: Commit** — `feat(generation): RUN interrotto riconoscibile e scelta del risultato incrementale`.

---

### Task 2: Applicare il risultato nel `GenerationController`

**Files:**
- Modify: `App/Generation/GenerationController.swift`

**Interfaces:**
- Consumes: Task 1; `control.setImage(fileURL:source:)` e `control.setImage(_:name:source:)` (come in `ResultsView.useAsImage`); `ControlText.error(_:)`.
- Produces: `var incremental: Bool` (persistito in `UserDefaults`, chiave `generation.incremental`, default `false`), usato dal Task 3.

- [ ] **Step 1: Proprietà** `incremental` con `didSet` che scrive `UserDefaults.standard` e lettura nell'`init` (o `@ObservationIgnored` + `@AppStorage` nella vista: vedi spec §5; la chiave è fissa).
- [ ] **Step 2: RUN semplice**: nel `Task` di `run(with:)`, ramo senza pipeline: `let before = session.results.first?.id` prima di `start(with:inputs:)`; dopo, `await session.waitUntilFinished()`; poi `if let made = IncrementalRun.output(enabled: incremental, phase: session.phase, stopped: session.lastRunWasStopped, before: before, results: session.results) { await useAsStart(made) }`. Uno Stop durante la preparazione esce prima di `start` come oggi (**Review Focus 5**).
- [ ] **Step 3: Pipeline**: `runPipeline` restituisce `GeneratedImage?` = l'ultimo `made` solo se il ciclo arriva alla fine (ogni `return` anticipato restituisce `nil`); nel `Task` di `run`, se `incremental` e il valore non è nil e `!Task.isCancelled`, `await useAsStart(made)`.
- [ ] **Step 4: `private func useAsStart(_ result: GeneratedImage) async`**: stesso corpo di `ResultsView.useAsImage` (file se c'è, altrimenti immagine in memoria con `String(localized: "results.unsaved.name")`, **Review Focus 3**); un `ControlError` → `session.fail(with: .generationFailed(ControlText.error(error)))`.
- [ ] **Step 5: Compilare** — `xcodebuild … build` → `BUILD SUCCEEDED`.
- [ ] **Step 6: Commit** — `feat(generation): modalità incrementale nel controller`.

---

### Task 3: Pulsante nell'header, testi, prove

**Files:**
- Modify: `App/MainWindow/HeaderBar.swift`, `App/Localizable.xcstrings`, `README.md` (una riga)

**Interfaces:**
- Consumes: `generation.incremental` (Task 2).

- [ ] **Step 1: Pulsante** in `HeaderBar.body`, tra il `SettingsLink` e `runButton`: `Button { generation.incremental.toggle() } label: { Image(systemName: generation.incremental ? "arrowshape.bounce.right.fill" : "arrowshape.bounce.right").foregroundStyle(generation.incremental ? DS.accent : .primary) }`, `.buttonStyle(DSGlassCircleButtonStyle())`, `.help(String(localized: "header.incremental.help"))`, `.accessibilityLabel(String(localized: "header.incremental.help"))`, `.accessibilityValue(String(localized: generation.incremental ? "header.incremental.on" : "header.incremental.off"))`.
- [ ] **Step 2: Testi** (it / en): `header.incremental.help` «Incrementale: ogni risultato diventa l'immagine di partenza per la RUN successiva» / «Incremental: each result becomes the start image for the next RUN»; `header.incremental.on` Attivo / On; `header.incremental.off` Spento / Off.
- [ ] **Step 3: Compilare e suite** — `xcodebuild … build`; `cd Packages && swift test 2>&1 | grep -E "Test run with|error:"`.
- [ ] **Step 4: Prove a mano** (lista all'utente): §7 della spec.
- [ ] **Step 5: README** — in «What DT Hub adds» (inglese): «**Incremental mode** — a header switch makes each result the start image of the next RUN.» · commit `feat(app): pulsante della modalità incrementale; README` (con `HeaderBar.swift` e `Localizable.xcstrings`).
- [ ] **Step 6: Messaggio finale** (briefing §6): cosa provare; «Decisioni che ho preso» (immagine in cima con più batch; errore di Control mostrato come fallimento del RUN; con costi); «Rinviati» (spec §8); via libera prima di unire, push o release.

---

## Autorevisione

- **Copertura:** spec §3–4 → Task 1; §5 → Task 2–3; §6 → Task 1; §7 → Task 3.
- **Tipi:** `lastRunWasStopped` e `IncrementalRun.output` (Task 1) usati identici nel Task 2; `incremental` (Task 2) letto nel Task 3.
