# Sidebar delle informazioni nella finestra Risultati — Piano di implementazione

> **Per chi esegue:** SOTTO-SKILL OBBLIGATORIA: `superpowers:subagent-driven-development` (consigliata) oppure `superpowers:executing-plans`. I passi usano la sintassi a caselle (`- [ ]`).

**Obiettivo:** una sidebar richiudibile nella finestra Risultati con prompt, parametri e altri dati dell'immagine selezionata.

**Architettura:** `ResultInfo` in HubCore trasforma una `GeneratedImage` in sezioni di righe (logica pura, testata con `swift test`); la vista `ResultInfoSidebar` le mostra con testo selezionabile; `ResultsView` ospita il pannello e il pulsante, con la scelta aperto/chiuso in `@AppStorage`.

**Tecnologie:** Swift 6.2, Swift Testing (`import Testing`, `@Test`, `#expect`), SwiftUI, `JSONEncoder`/`JSONSerialization`.

**Spec:** `docs/superpowers/specs/2026-10-08-risultati-sidebar-design.md` (leggerla prima: la tabella delle righe è al §4.1).

## Vincoli globali

- Base: `origin/main` (0.1.3). Ramo nuovo (es. `risultati-sidebar`). **Non si unisce in `main` e non si fa push/release senza «unisci»/via libera esplicito dell'utente.**
- Si aggiungono i file **per nome** (`git add <file>`); mai `git add -A` né `git add docs`.
- Test: `cd Packages && swift test --filter ResultInfo 2>&1 | grep -E "Test run with|error:"`. Test `@MainActor` dove serve.
- L'app si compila con `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build` (cura per la cache Metal: `cd Packages && swift package clean`).
- Testi dell'interfaccia in italiano e inglese (`Localizable.xcstrings`, `extractionState: manual`, entrambe le lingue `translated`). Commenti nel codice in inglese.
- Dopo l'unione in `main` (solo con «unisci»): ricompilare l'app dell'utente col comando sopra e dirgli di riavviarla.

## Review Focus

1. Prompt molto lungo (500 parole), con a-capo e virgolette: nessun troncamento, la sidebar scorre (Task 2).
2. Job minimo (nessun negativo, LoRA, input, extra): nessuna sezione vuota, nessuna riga con valore vuoto (Task 1).
3. Immagine non salvata (`fileURL == nil`, `saveError` valorizzato): la riga d'errore c'è, nome file e cartella no (Task 1).
4. Immagine ripristinata all'avvio (`isRestored`): stessi dati di una appena generata (Task 1, Task 3).
5. `AdvancedParameters` con un campo nuovo in futuro: compare da solo tra le avanzate se diverso dal default (Task 1).

---

## Struttura dei file

| File | Responsabilità |
|---|---|
| `Packages/Sources/HubCore/Output/ResultInfo.swift` (nuovo) | sezioni e righe da una `GeneratedImage` |
| `Packages/Tests/HubCoreTests/ResultInfoTests.swift` (nuovo) | test |
| `App/Results/ResultInfoSidebar.swift` (nuovo) | la vista della sidebar |
| `App/Results/ResultsView.swift` (modifica) | pannello a destra, pulsante, `minWidth` |
| `App/Localizable.xcstrings` (modifica) | testi it/en |

---

### Task 1: `ResultInfo`

**Files:**
- Create: `Packages/Sources/HubCore/Output/ResultInfo.swift`
- Test: `Packages/Tests/HubCoreTests/ResultInfoTests.swift`

**Interfaces:**
- Consumes: `GeneratedImage` (HubCore: `image`, `job`, `date`, `fileURL`, `saveError`, `elapsed`, `isRestored`; costruibile in test con l'`init` memberwise pubblico oppure, se non lo è, con un helper nel file di test — controllare `GenerationSession.swift:7`; se l'`init` non è pubblico, aggiungerne uno `public init(image:job:date:fileURL:saveError:elapsed:isRestored:)` senza cambiare il comportamento), `GenerationJob.promptWithTriggers`, `Sampler.displayName`, `AdvancedParameters.default`, `ElapsedText.label`, `testImage()` (`Packages/Tests/HubCoreTests/FakeBackend.swift:100`).
- Produces (usato dai Task 2–3): la `struct ResultInfo` con `Field`, `Kind`, `Row`, `Section`, `sections` e `init(_ image: GeneratedImage, locale: Locale = .current, timeZone: TimeZone = .current)` **esattamente** come nel §4.1 della spec.

- [ ] **Step 1: Scrivere i test che falliscono** (`ResultInfoTests`; helper locale `func result(job:, fileURL:, saveError:, elapsed:) -> GeneratedImage`, `Locale(identifier: "en_US")` e `TimeZone(identifier: "UTC")` nei test):
  - `minimalJobShowsOnlyThePromptAndTheModelSections`: job con solo prompt/model/parametri di default, nessun file, `date` fissa → sezioni `[.prompt, .model, .file]`; la sezione `.prompt` ha solo `prompt`; nessuna riga ha `value` vuoto (**Review Focus 2**).
  - `fullJobHasEverySectionInOrder`: job con negativo, 2 LoRA, `imageStrength 0.65`, `moodboardCount 2`, mask, una avanzata cambiata, un `extra`, `elapsed 42`, `fileURL` → `sections.map(\.kind) == [.prompt, .model, .loras, .input, .advanced, .extra, .file]`.
  - `negativePromptRowOnlyWhenNotEmpty`; `sentPromptOnlyWhenTriggersChangeThePrompt` (LoRA con trigger `"zzz"` e prompt `"a cat"` → riga `sentPrompt` con `"zzz a cat"`; senza trigger nessuna riga).
  - `sizeAndSeedAreFormattedPlainly`: `1024 × 1024` (con `×` e spazi), seed `4294967295` senza separatori anche con `Locale(identifier: "it_IT")`.
  - `shiftIsAutoWhenResolutionDependent`: `resolutionDependentShift = true` → `"auto"`; falso con `shift 3.5` → `"3.5"` (en) e `"3,5"` (it).
  - `cfgZeroRowOnlyWhenOn`.
  - `loraRowsCarryFileWeightModeAndTrigger`: `"x.ckpt · 0.8 · all"` e con trigger `"x.ckpt · 1 · all · zzz"` (il peso senza zeri inutili).
  - `maskRow`: `"blur 1.5 · outset 0 · preserve"` e senza `preserve` quando `preserveOriginal == false`.
  - `advancedListsOnlyValuesThatDiffer`: default → nessuna sezione `.advanced`; cambiando `clipSkip` e `hiresFix` → due righe `advanced(key: "clipSkip")` e `advanced(key: "hiresFix")` in ordine alfabetico di chiave (**Review Focus 5**).
  - `extraRowsPerEntry`.
  - `timeRowAbsentWithoutElapsed`; con `elapsed 41.6` → `"42sec"`.
  - `unsavedImageShowsTheErrorAndNoFile` (**Review Focus 3**): `fileURL nil`, `saveError "disk full"` → riga `notSaved = "disk full"`, nessuna `fileName`/`folder`.
  - `restoredImageGivesTheSameRows` (**Review Focus 4**): la stessa `GeneratedImage` con `isRestored = true` produce `ResultInfo` uguale.
  - `dateRowFollowsTheLocale`: la stessa `date` in `en_US` e `it_IT` dà due stringhe diverse.
- [ ] **Step 2: Vedere il fallimento** — `cd Packages && swift test --filter ResultInfoTests 2>&1 | grep -E "Test run with|error:"` → errore di compilazione (`ResultInfo` non esiste).
- [ ] **Step 3: Implementare `ResultInfo.swift`** con la tabella del §4.1. Decisioni di dettaglio: numeri con `Double.formatted(.number.precision(.fractionLength(0...2)).locale(locale))`; le avanzate si ricavano codificando `parameters.advanced` e `AdvancedParameters.default` con `JSONEncoder` + `JSONSerialization` e confrontando chiave per chiave (valore mostrato come `String(describing:)` normalizzato: booleani `true/false`, stringhe senza virgolette, numeri come sopra); `extra` con `JSONEncoder` compatto sul `JSONValue`; `folder` = `fileURL.deletingLastPathComponent().path`; la data con `Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale, timeZone: timeZone)`. Le sezioni senza righe sono omesse.
- [ ] **Step 4: Test verdi** — stesso comando dello Step 2.
- [ ] **Step 5: Commit** — `git add Packages/Sources/HubCore/Output/ResultInfo.swift Packages/Tests/HubCoreTests/ResultInfoTests.swift` (più `GenerationSession.swift` se serve l'`init` pubblico) · `git commit -m "feat(results): ResultInfo, i dati di un'immagine per la sidebar"`.

---

### Task 2: Vista della sidebar e testi

**Files:**
- Create: `App/Results/ResultInfoSidebar.swift`
- Modify: `App/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ResultInfo` (Task 1), `DSGroupHeader(title:)`, `DS.*`.
- Produces: `struct ResultInfoSidebar: View { let image: GeneratedImage?; let selectionCount: Int }` — larghezza propria 300 pt, usata dal Task 3.

L'app non ha test di UI: la verifica è la compilazione (Step 3) e le prove a mano (Task 3).

- [ ] **Step 1: Implementare `ResultInfoSidebar`**:
  - `image == nil` → `ContentUnavailableView` piccolo con la chiave `results.info.none`.
  - Altrimenti `ScrollView` → `VStack(alignment: .leading)` con, se `selectionCount > 1`, la riga secondaria `results.info.multi` (formato con il numero); poi per ogni sezione di `ResultInfo(image)` un `DSGroupHeader(title:)` (titolo da `Kind`) e le sue righe.
  - Riga: etichetta (`Text(label(for: field))`, `.caption`, `.secondary`) e valore (`Text(verbatim: value)`, `.textSelection(.enabled)`); per `prompt`, `negativePrompt`, `sentPrompt` font `.body` a tutta larghezza; per le altre `.system(.callout, design: .monospaced)`. Il pulsante «Copia» **non** c'è.
  - Etichette: `label(for: Field)` per i campi fissi; per `advanced(key:)` e `extra(key:)` l'etichetta è la chiave stessa (`Text(verbatim:)`).
  - Frame: `.frame(width: 300)`, sfondo trasparente (quello della finestra).
- [ ] **Step 2: Testi** in `Localizable.xcstrings` (it / en): sezioni `results.info.section.prompt` Prompt / Prompt, `.model` Modello / Model, `.loras` LoRA / LoRAs, `.input` Input / Input, `.advanced` Avanzate / Advanced, `.extra` Extra / Extra, `.file` File / File; campi `results.info.field.prompt` Prompt / Prompt, `.sentPrompt` Inviato a Draw Things / Sent to Draw Things, `.negativePrompt` Prompt negativo / Negative prompt, `.model` Modello / Model, `.size` Dimensioni / Size, `.seed` Seed / Seed, `.steps` Passi / Steps, `.guidance` Guidance / Guidance, `.sampler` Sampler / Sampler, `.shift` Shift / Shift, `.cfgZero` CFG-Zero* (passi iniziali) / CFG-Zero* (init steps), `.lora` LoRA / LoRA, `.imageStrength` Forza dell'immagine / Image strength, `.moodboard` Immagini Moodboard / Moodboard images, `.mask` Maschera / Mask, `.time` Tempo / Time, `.date` Data / Date, `.fileName` Nome file / File name, `.folder` Cartella / Folder, `.notSaved` Non salvata / Not saved; messaggi `results.info.none` Nessuna immagine selezionata / No image selected, `results.info.multi` %d immagini selezionate: dati della principale / %d images selected: showing the main one; `results.info.toggle` Mostra o nascondi le informazioni / Show or hide the information.
- [ ] **Step 3: Compilare** — `xcodebuild … build 2>&1 | tail -20` → `BUILD SUCCEEDED` (la vista non è ancora collegata).
- [ ] **Step 4: Commit** — `git add App/Results/ResultInfoSidebar.swift App/Localizable.xcstrings` · `git commit -m "feat(results): vista della sidebar delle informazioni"`.

---

### Task 3: Collegamento in `ResultsView`, prove e chiusura

**Files:**
- Modify: `App/Results/ResultsView.swift`, `README.md` (una riga)

**Interfaces:**
- Consumes: `ResultInfoSidebar(image:selectionCount:)` (Task 2); in `ResultsView` esistono `selected` (`GeneratedImage?`), `picks.ids` e `imageArea`.
- Produces: nulla per altri task.

- [ ] **Step 1: Pannello e preferenza** in `ResultsView`:
  - `@AppStorage("results.sidebar.open") private var sidebarOpen = true`.
  - Il `body` attuale (`VStack`) diventa il contenuto principale di un `HStack(spacing: 0)`: a destra, se `sidebarOpen`, un `Divider()` e `ResultInfoSidebar(image: selected, selectionCount: picks.ids.count)`.
  - `.frame(minWidth: sidebarOpen ? 820 : 520, idealWidth: …, minHeight: 560, idealHeight: 820)`: la larghezza ideale cresce di 300 quando la sidebar è aperta.
  - I modificatori già presenti (`padding`, `background`, `tint`, `onChange`, `DeleteKeyMonitor`, `task`) restano sul contenitore, come oggi.
- [ ] **Step 2: Pulsante**: in `imageArea`, un `.overlay(alignment: .topTrailing)` con `Button { sidebarOpen.toggle() } label: { Image(systemName: "sidebar.trailing") }`, `.buttonStyle(DSGlassCircleButtonStyle())`, `.help(String(localized: "results.info.toggle"))`, `.accessibilityLabel` uguale, `.padding(10)`.
- [ ] **Step 3: Compilare** — `xcodebuild …` → `BUILD SUCCEEDED`; poi `cd Packages && swift test 2>&1 | grep -E "Test run with|error:"` → nessun fallimento.
- [ ] **Step 4: Prove a mano** (dare all'utente la lista, non pilotare l'interfaccia): tutte le voci del §8 della spec.
- [ ] **Step 5: README** — in «What DT Hub adds» una riga in inglese: «**Result details** — a collapsible sidebar in the Results window shows the prompt, settings, LoRAs and timing saved in the selected image.» · `git add README.md` · `git commit -m "feat(results): sidebar delle informazioni; README"` (il commit del Task 3 include `ResultsView.swift`).
- [ ] **Step 6: Messaggio finale all'utente**, formato del briefing §6: cosa è stato fatto e cosa provare; «Decisioni che ho preso» (sezione Avanzate; pulsante senza scorciatoia; con costo se sbagliate); «Rinviati» (PNG esterni, confronto tra due immagini, modifica dei valori, con il file di backlog); richiesta esplicita di via libera prima di unire in `main` e prima di ogni push o release.

---

## Autorevisione

- **Copertura della spec:** §3–4.1 → Task 1; §4.2 → Task 2; §4.3 → Task 3; §5 casi limite → test del Task 1 e Review Focus; §6 test → Task 1; §8 prove a mano → Task 3.
- **Coerenza dei tipi:** `ResultInfo`/`Field`/`Kind`/`Row`/`Section` nascono nel Task 1 e sono usati identici nel Task 2; `ResultInfoSidebar(image:selectionCount:)` nasce nel Task 2 ed è chiamata uguale nel Task 3.
- **Proporzione:** il piano non scrive corpi di funzione, solo firme, test e valori fissati dalla spec.
