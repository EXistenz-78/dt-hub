# Pipeline di preset create dall'utente — Piano di implementazione

> **Per chi esegue:** SOTTO-SKILL OBBLIGATORIA: `superpowers:subagent-driven-development` (consigliata) oppure `superpowers:executing-plans`. I passi usano la sintassi a caselle (`- [ ]`).

**Obiettivo:** l'utente mette in fila i suoi preset in una pipeline, la salva, la sceglie dal menu Preset e la lancia con RUN; ogni passaggio può avere modello, scala e forza propri.

**Architettura:** la logica sta in HubCore ed è coperta da test: `UserPipeline` + `UserPipelineStore` (file in `Pipelines/`), la conversione in `PluginPipeline`, le funzioni pure di dimensioni, forza e modello, e `PipelineDraft` (lo stato della finestra «Crea pipeline…»). L'app aggiunge solo l'aggancio: `GenerationController.runPipeline` usa quelle funzioni, il menu Preset e due finestre. La pipeline dell'utente occupa lo stesso posto di quella di un plug-in (`ContributionStore.pipeline`), con un'origine che la distingue.

**Tecnologie:** Swift 6.2, Swift Testing, SwiftUI (macOS 26).

**Spec:** `docs/superpowers/specs/2026-10-12-pipeline-di-preset-utente-design.md` (chi esegue legge anche quella).

## Vincoli globali

- Ramo nuovo `pipeline-utente` da `main` (`90d6b61`). **Niente unione, push o release senza via libera esplicito.** File aggiunti a git **per nome** (mai `git add -A` né `git add docs`).
- Test della logica: `cd Packages && swift test --filter <Suite> 2>&1 | grep -E "Test run with|✘|error:"`. Dopo ogni task che tocca `App/`: `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"` → `BUILD SUCCEEDED`.
- Ogni testo nuovo dell'app va in `App/Localizable.xcstrings` in **en e it** (`swift test --filter LocalizationCatalogTests` verde). I testi esatti sono nella tabella «Testi» qui sotto.
- Il contratto dei plug-in non cambia: i tre campi nuovi di `PipelineStep` **non** si leggono dal JSON; `PluginKit/` e `Plugins/` non si toccano. I test esistenti delle pipeline restano verdi.
- Limiti copiati dalla spec: `scale` 0,25–4 (mancante = 1); `strength` 0–1 (mancante = automatica); dimensioni a multipli di 64, limite 2048 oppure 8192 con HiRes/Tiled Diffusion; Salva con **almeno 2 passaggi**; cartella `~/Library/Application Support/DT Hub/Pipelines/`.
- Commenti nel codice in inglese. Niente `UserDefaults` nei test; i test `@MainActor` vanno marcati.
- Non pilotare l'interfaccia con computer-use: le prove a mano del Task 10 le fa l'utente.

## Decisioni prese nel piano (la spec non le fissa)

1. **Esempio 832×1216 × 1,5:** la spec scrive 1248×1824, che non sono multipli di 64. Con `GenerationParameters.snap` (regola della stessa spec, §5) il risultato è **1280×1856**; il piano usa questo.
2. **Un plug-in propone una pipeline mentre è attiva (ferma) quella dell'utente:** la sostituisce senza pop-up (il pop-up di oggi confronta due plug-in per nome). **Mentre una pipeline è in esecuzione nessuna pipeline si può mandare al RUN** (deciso dall'utente il 12 ottobre): quella di un plug-in è rifiutata (`ContributionStore.pipelineLocked`, il plug-in riceve il motivo), e le pipeline del menu Preset sono disattivate.
7. **Mockup** (`docs/superpowers/mockups/2026-10-12-crea-pipeline.html`): vale per il layout (griglia 26 | 1fr | 64 | 64 in un riquadro bordato, nota tra parentesi accanto alla casella). Dove contraddice la spec vince la spec: niente riga di riepilogo delle dimensioni, Salva con almeno 2 passaggi.
3. **Il RUN rilegge il file della pipeline dell'utente a ogni lancio:** così «Pipeline non leggibile» esce al RUN e una pipeline salvata di nuovo vale subito.
4. **Passaggio senza la chiave `preset`** (né `null` né testo): illeggibile, si salta. Un file senza passaggi leggibili è illeggibile.
5. **Scegliere dal menu la pipeline già attiva** la lascia attiva (si toglie con «Togli la pipeline»).
6. **`NamedJSONFolder`:** la gestione dei file per nome esce da `PresetStore` e serve a tutti e due gli store, invece di copiarla.

## Review Focus

1. **Server parcheggiato per l'LLM:** al clic su RUN il catalogo è vuoto; il controllo «Modello non installato» va fatto dopo `ensureServerForRun`, altrimenti ogni pipeline con modelli fallisce (Task 7, prova a mano 8 del Task 10).
2. **Pipeline attiva che cambia sotto i piedi:** salvata di nuovo, rinominata, eliminata, o con un preset rinominato → il RUN usa il file di adesso e il pulsante mostra i passaggi giusti (Task 4 e 8; test `syncing…` nel Task 4).
3. **Pipeline dei plug-in identiche a prima:** modello dell'header, nessuna scala, forza automatica, dimensioni della scheda per ogni passaggio (test nei Task 3 e 5; `PipelineInputsTests`, `PipelineStepValuesTests`, `PluginPresetsTests` verdi).
4. **File di pipeline scritto a mano:** `scale` 0, 100 o testo; `strength` 5; `steps` vuoto o non lista; `preset` vuoto (test nel Task 2).
5. **Virgola decimale e valori assurdi nei campi:** «1,5», «0», «abc», «150» % (test nel Task 6).

## Testi (chiave · it · en)

| Chiave | it | en |
|---|---|---|
| `preset.manage` (cambia) | Gestisci preset e pipeline… | Manage Presets and Pipelines… |
| `preset.manage.title` (cambia) | Preset e pipeline | Presets and Pipelines |
| `pipeline.create` | Crea pipeline… | Create Pipeline… |
| `pipeline.create.title` | Crea pipeline | Create Pipeline |
| `pipeline.invalidName` | Nome non valido | Invalid name |
| `pipeline.replaces` | Esiste già una pipeline con questo nome: verrà sostituita. | A pipeline with this name already exists: it will be replaced. |
| `pipeline.saved` | Salvata. | Saved. |
| `pipeline.chain` | Concatena i risultati | Chain the results |
| `pipeline.chain.note` | il risultato di un passaggio è l'immagine di partenza del successivo | the result of a pass is the start image of the next one |
| `pipeline.column.preset` | Preset | Preset |
| `pipeline.column.scale` | Scala | Scale |
| `pipeline.current` | Impostazioni attuali | Current Settings |
| `pipeline.current.note` | Generazione e Control al lancio | Generation and Control when it runs |
| `pipeline.noModel` | Nessun modello: quello dell'header | No model: the header's |
| `pipeline.strength.auto` | auto | auto |
| `sheet.close` | Chiudi | Close |
| `pipeline.group.presets` | Preset | Presets |
| `pipeline.group.pipelines` | Pipeline | Pipelines |
| `pipeline.missing` | manca: %@ | missing: %@ |
| `pipeline.delete` | Elimina pipeline | Delete pipeline |
| `pipeline.unreadable` | Pipeline non leggibile: %@ | Pipeline not readable: %@ |
| `pipeline.missingModel` | Modello non installato: %@ | Model not installed: %@ |

Si riusano: `control.strength` (Forza), `preset.save.name` (Nome), `preset.save.button` (Salva), `contribution.passes` (%lld passaggi), `contribution.fromPrevious`, `preset.rename.taken`, `pipeline.missingPreset`, `pipeline.unreadablePreset`.

---

### Task 1: `NamedJSONFolder` estratto da `PresetStore`

**Files:** Create `Packages/Sources/HubCore/Presets/NamedJSONFolder.swift`. Modify `Packages/Sources/HubCore/Presets/PresetStore.swift`. Test: `Packages/Tests/HubCoreTests/PresetTests.swift` (esistente, non cambia). In questo task si committano anche la spec e questo piano.

**Interfaces — Produces** (tipo interno a HubCore, `@MainActor`):

```swift
struct NamedJSONFolder {
  init(folder: URL, move: @escaping (URL, URL) throws -> Void)
  func names() -> [String]                                   // *.json senza punto iniziale, localizedStandardCompare
  func existingName(for name: String) -> String?             // esatto, poi senza spazi ai bordi, poi senza maiuscole/accenti
  func data(named actual: String) -> Data?
  func write(_ data: Data, as name: String) throws(PresetError)      // crea la cartella, scrittura atomica
  func rename(_ old: String, to newName: String) throws(PresetError) // invalidName, notFound, nameTaken, i due passi di oggi
  func remove(named name: String)
  static func isValidName(_ raw: String) -> Bool
}
```

- [ ] **Step 1:** crea il ramo `pipeline-utente`; `swift test --filter PresetStoreTests` verde prima di toccare nulla (annota il numero di test).
- [ ] **Step 2:** sposta in `NamedJSONFolder` il codice di `PresetStore` che non conosce `Preset` (elenco, `existingName`, `isValidName`, `same`, `url`, scrittura, rinomina in due passi con ripristino, cancellazione). `PresetStore` tiene la sua API pubblica identica (`PresetStore.isValidName` rimanda a `NamedJSONFolder.isValidName`) e chiama `refresh()` dopo ogni scrittura come oggi.
- [ ] **Step 3:** `swift test --filter "PresetStoreTests|PresetPromptTests|PluginPresetsTests"` → stesso numero di test, tutti verdi.
- [ ] **Step 4: Commit** — `git add` di `NamedJSONFolder.swift`, `PresetStore.swift`, della spec e di questo piano; `refactor(presets): cartella di file JSON per nome, separata da PresetStore`.

### Task 2: `UserPipeline` e `UserPipelineStore`

**Files:** Create `Packages/Sources/HubCore/Pipelines/UserPipeline.swift`, `Packages/Sources/HubCore/Pipelines/UserPipelineStore.swift`. Test: `Packages/Tests/HubCoreTests/UserPipelineTests.swift`.

**Interfaces — Consumes:** `NamedJSONFolder` (Task 1), `PresetError`, `JSONValue`.
**Produces:**

```swift
public struct UserPipeline: Equatable, Sendable {
  public struct Step: Equatable, Sendable {
    public var preset: String?        // nil = «Impostazioni attuali»
    public var scale: Double          // 0.25...4
    public var strength: Double?      // 0...1, nil = automatica
    public init(preset: String?, scale: Double = 1, strength: Double? = nil)   // riporta nei limiti
  }
  public static let scaleRange = 0.25...4.0
  public var chain: Bool
  public var steps: [Step]
  public init(chain: Bool = true, steps: [Step])
  public init?(data: Data)            // nil: non è un oggetto, `steps` non è una lista, nessun passaggio leggibile
  public func data() -> Data          // prettyPrinted + sortedKeys; "preset": null scritto; "strength" solo se c'è
  public var presetNames: [String]    // senza doppioni, nell'ordine dei passaggi
}

@MainActor @Observable public final class UserPipelineStore {
  public private(set) var names: [String]
  public init(folder: URL, move: @escaping (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) })
  public static var defaultFolder: URL                       // …/DT Hub/Pipelines
  public func refresh()
  public func existingName(for name: String) -> String?
  public func contains(_ name: String) -> Bool
  public func load(named name: String) throws(PresetError) -> UserPipeline   // .notFound / .unreadable
  public func save(_ pipeline: UserPipeline, named name: String) throws(PresetError)  // sostituisce lo stesso nome
  public func delete(named name: String)
  public func rename(_ old: String, to newName: String) throws(PresetError)
  public func renamePreset(_ old: String, to newName: String)   // riscrive solo le pipeline che nominano `old`
}
```

Lettura di un passaggio: oggetto con `preset` = `null` oppure testo non vuoto (ripulito dagli spazi); `scale` numero (intero o decimale) riportato in 0,25–4, altrimenti 1; `strength` numero riportato in 0–1, altrimenti nil. Tutto il resto si salta. `chain` mancante o non booleano = `true`. `renamePreset` confronta i nomi senza distinguere maiuscole e accenti, salta i file illeggibili.

- [ ] **Step 1: Test che falliscono** (`UserPipelineTests`, `@MainActor`, cartella temporanea come in `PresetStoreTests`):
  - `readsTheSpecExample`: il JSON del §4 della spec → `chain == true`, 3 passaggi: `(nil, 1, nil)`, `("Qwen · Upscale", 2, nil)`, `("SD 1.5 · Rifinitura", 1, 0.3)`.
  - `valuesComeBackWithinTheirLimits` (**Review Focus 4**): `scale` 0 → 0.25; 100 → 4; `"big"` → 1; `strength` 5 → 1; −1 → 0; `"x"` → nil.
  - `anUnreadableStepIsSkipped`: `[{"preset":null}, 7, {"preset":""}, {"scale":2}, {"preset":"A"}]` → 2 passaggi (`nil`, `"A"`).
  - `aFileWithoutStepsIsNotAPipeline`: `{"chain":true,"steps":[]}`, `{"steps":3}`, `[]`, testo non JSON → `UserPipeline(data:) == nil`.
  - `aMissingChainIsOn`: `{"steps":[{"preset":null},{"preset":"A"}]}` → `chain == true`.
  - `writesAndReadsBack`: `UserPipeline(data: p.data()) == p`; il testo scritto contiene `"preset" : null`.
  - Store: `savesAndLoads` (file `<nome>.json` nella cartella, `names` ordinati); `invalidNamesAreRefused` (`""`, `"a/b"`, `"a:b"`, `".x"` → `.invalidName`, nessun file); `savingAnExistingNameReplacesIt` (anche `"fast"` su `"Fast"`: resta un solo file `Fast.json`); `renamingToATakenNameIsRefused` (`.nameTaken`); `capitalsAndAccentsDoNotTellNamesApart` (`existingName(for: "PIU")` trova `"Più"`); `anUnreadableFileIsListedAndFailsOnLoad` (file `Rotto.json` con `x` → in `names`, `load` lancia `.unreadable("Rotto")`); `loadOfAMissingNameIsNotFound`; `renamePresetTouchesOnlyThePipelinesThatNameIt` (pipeline A con passaggi `"Flux"`, `"Qwen"`, pipeline B con `"Altro"`: dopo `renamePreset("flux", to: "Flux 2")` A ha `"Flux 2"`, `"Qwen"` con scala e forza intatte; il file di B è byte per byte quello di prima).
- [ ] **Step 2:** `swift test --filter UserPipelineTests` → fallisce (tipi mancanti).
- [ ] **Step 3:** implementa `UserPipeline` (lettura tramite `JSONValue`, non `Codable` sintetizzato) e `UserPipelineStore` sopra `NamedJSONFolder`.
- [ ] **Step 4:** `swift test --filter UserPipelineTests` verde.
- [ ] **Step 5: Commit** — `feat(pipeline): pipeline dell'utente su file (UserPipeline, UserPipelineStore)`.

### Task 3: `PipelineStep` con modello, scala e forza; conversione

**Files:** Modify `Packages/Sources/HubKit/Plugin/PluginContribution.swift`, `Packages/Sources/HubCore/Pipelines/UserPipeline.swift`. Test: `Packages/Tests/HubKitTests/PipelineStepTests.swift`, `Packages/Tests/HubCoreTests/UserPipelineTests.swift`.

**Interfaces — Produces:**

```swift
// PipelineStep (HubKit): tre proprietà in più e tre parametri in fondo a init, con questi default
public var usesPresetModel: Bool = false
public var scale: Double = 1
public var strength: Double? = nil

// UserPipeline (HubCore)
public func pluginPipeline(named name: String) -> PluginPipeline
```

Conversione: `PluginPipeline(name: name, steps:)`; per ogni passaggio `title = ""`, `preset = step.preset ?? ""`, `usesPresetModel = true`, `useOutputAsStart = chain && indice > 0`; `scale` = quella del passaggio, ma **1 per il primo**; `strength` = quella del passaggio, ma **nil per il primo e per «Impostazioni attuali»**.

- [ ] **Step 1: Test che falliscono:**
  - HubKit `aStepFromJSONNeverHasTheUserPipelineFields` (**Review Focus 3**): `{"title":"A","preset":"P","usesPresetModel":true,"scale":2,"strength":0.3}` → `usesPresetModel == false`, `scale == 1`, `strength == nil`.
  - HubCore `convertsToARunPipeline`: `UserPipeline(chain: true, steps: [.init(preset: nil, scale: 3, strength: 0.5), .init(preset: "Q", scale: 2), .init(preset: nil, scale: 1.5, strength: 0.4), .init(preset: "R", strength: 0.3)])` → nome passato; `preset` `["", "Q", "", "R"]`; `useOutputAsStart` `[false, true, true, true]`; `scale` `[1, 2, 1.5, 1]`; `strength` `[nil, nil, nil, 0.3]`; `usesPresetModel` tutti `true`.
  - `withoutChainNoPassTakesThePreviousOutput`: `chain: false` → `useOutputAsStart` tutti `false`.
- [ ] **Step 2–4:** vedere il fallimento, implementare, `swift test --filter "PipelineStepTests|UserPipelineTests"` verde.
- [ ] **Step 5: Commit** — `feat(pipeline): passaggi con modello del preset, scala e forza`.

### Task 4: origine della pipeline in `ContributionStore`

**Files:** Modify `Packages/Sources/HubCore/Plugins/ContributionStore.swift`. Test: `Packages/Tests/HubCoreTests/ContributionStoreTests.swift`.

**Interfaces — Consumes:** `UserPipelineStore`, `UserPipeline.pluginPipeline(named:)`.
**Produces:**

```swift
public struct PipelineContribution: Equatable, Sendable {
  public enum Source: Equatable, Sendable { case plugin(String), user(String) }
  public let source: Source
  public let pipeline: PluginPipeline
  public init(pluginID: String, pipeline: PluginPipeline)
  public init(userPipeline name: String, pipeline: PluginPipeline)
  public var pluginID: String?            // nil per una pipeline dell'utente
  public var userPipelineName: String?    // nil per una pipeline di plug-in
}

// ContributionStore
public func setUserPipeline(_ pipeline: PluginPipeline, named name: String)
/// Realigns the active user pipeline with its file. `renamedTo` when its file was just renamed.
public func syncUserPipeline(with store: UserPipelineStore, renamedTo newName: String? = nil)
```

`setUserPipeline` sostituisce la pipeline attiva di chiunque e toglie i conflitti in attesa con soggetto `.pipeline`. In `receive`, il conflitto nasce solo se la pipeline attiva è di **un altro plug-in**; su una dell'utente il plug-in scrive direttamente (decisione 2). `syncUserPipeline`: niente se la pipeline attiva non è dell'utente; altrimenti rilegge `newName ?? nome attivo` dallo store e la rimette col nome scritto nella cartella; se non si legge più, la toglie. `forget(_:)` e `removePipeline()` restano come sono.

- [ ] **Step 1: Test che falliscono:**
  - `theUsersPipelineReplacesAPluginsWithoutAConflict`: plug-in `a` manda una pipeline; `setUserPipeline(p, named: "Mia")` → `pipeline?.userPipelineName == "Mia"`, `pipeline?.pluginID == nil`, `conflicts.isEmpty`.
  - `choosingAUsersPipelineDropsAPendingPipelineConflict`: `a` e `b` mandano due pipeline (un conflitto), poi `setUserPipeline` → `conflicts.isEmpty`.
  - `aPluginReplacesTheUsersPipelineWithoutAConflict`: `setUserPipeline`, poi `receive` di `a` → `pipeline?.pluginID == "a"`, nessun conflitto.
  - `forgettingAPluginKeepsTheUsersPipeline`.
  - `syncingFollowsARenamedFile` (**Review Focus 2**): store con `"Mia"` attiva; `store.rename("Mia", to: "Tua")`, `syncUserPipeline(with: store, renamedTo: "Tua")` → `userPipelineName == "Tua"`.
  - `syncingReloadsAChangedFile`: attiva a 2 passaggi; `store.save` con 3 passaggi sullo stesso nome; `syncUserPipeline(with: store)` → 3 passaggi.
  - `syncingRemovesADeletedPipeline`: `store.delete`, sync → `pipeline == nil`.
  - `syncingLeavesAPluginsPipelineAlone`.
- [ ] **Step 2–4:** vedere il fallimento, implementare, `swift test --filter "ContributionStoreTests|ContributionReviewTests"` verde. L'app non compila finché `ContributionText.pipelineHelp` usa `pluginID` come `String`: mettici un `?? ""` provvisorio (lo riscrive il Task 8) e verifica con `xcodebuild`.
- [ ] **Step 5: Commit** — `feat(pipeline): la pipeline del RUN sa da chi viene`.

### Task 5: dimensioni, forza e modello di un passaggio

**Files:** Create `Packages/Sources/HubCore/Pipelines/PipelineSizes.swift`. Modify `Packages/Sources/HubCore/Plugins/PipelineInputs.swift`, `Packages/Sources/HubCore/Plugins/PipelinePresets.swift`. Test: Create `Packages/Tests/HubCoreTests/PipelineSizesTests.swift`; Modify `PipelineInputsTests.swift`, `PluginPresetsTests.swift`.

**Interfaces — Produces:**

```swift
public enum PipelineSizes {
  /// `size` × `scale`; if the long side passes `limit` both sides shrink by the same factor; then each side snaps to 64.
  public static func scaled(_ size: Size, by scale: Double, limit: Int) -> Size
  /// One size per pass. `scales[0]` is ignored: the first pass is `first`, fitted to `limits[0]`.
  public static func sizes(first: Size, scales: [Double], limits: [Int]) -> [Size]
}

// PipelineInputs: un parametro in più in fondo, default nil
public static func strength(tab: ControlInputs, replacesStart: Bool, editModel: Bool, hasMargins: Bool, step: Double? = nil) -> Double

// PipelinePresets
public static func model(for step: PipelineStep, presets: [String: Preset], header: String?) -> String?
public static func missingModels(in pipeline: PluginPipeline, presets: [String: Preset], catalog: ModelCatalog) -> [String]
```

`scaled` usa `GenerationParameters.snap(_:limit:)` sui lati già ridotti in proporzione (`scaled(size, by: 1, limit:)` è il «rientra nel limite» del primo passaggio). `strength`: con `step` non nil ritorna `step` riportato in 0–1; altrimenti il calcolo di oggi. `model`: con `usesPresetModel` e un preset il cui `model` non è vuoto, quel modello; altrimenti `header`. `missingModels`: i modelli di preset (solo passaggi con `usesPresetModel`) che `catalog.model(forFile:)` non trova, senza doppioni, nell'ordine dei passaggi.

- [ ] **Step 1: Test che falliscono:**
  - `PipelineSizesTests`: 1024×1024, scale `[1, 2, 1]`, limiti `[2048, 2048, 2048]` → 1024², 2048², 2048²; 1024×1024 × 3 limite 2048 → 2048×2048; 832×1216 × 3 limite 2048 → **1408×2048**; 1024×1024, scale `[1, 4, 4]`, limiti `[2048, 8192, 8192]` → 1024², 4096², 8192²; 832×1216 × 1,5 limite 2048 → **1280×1856** (decisione 1); 64×64 × 0,25 → 64×64; primo passaggio 4096×2048 con limite 2048 → 2048×1024; un passaggio con limite 2048 dopo uno a 4096² con scala 1 → 2048².
  - `PipelineInputsTests`: `strength(tab: forza 0.7 a mano, replacesStart: true, editModel: false, hasMargins: false, step: 0.3) == 0.3`; `step: nil` → il valore di oggi (0.7 automatica senza forza a mano); `step: 1.4` → 1; i test esistenti non cambiano.
  - `PluginPresetsTests` (catalogo con un modello `flux.ckpt`, costruito come in `RunAvailabilityTests`): passaggio `usesPresetModel` con preset `model: "qwen.ckpt"` → `"qwen.ckpt"`; preset senza modello → header; passaggio senza preset → header; stesso preset ma `usesPresetModel == false` (plug-in) → header (**Review Focus 3**); `missingModels` → `["qwen.ckpt"]` una volta sola anche se due passaggi lo nominano, `[]` per la pipeline di un plug-in e quando il modello è `flux.ckpt`.
- [ ] **Step 2–4:** vedere il fallimento, implementare, `swift test --filter "PipelineSizesTests|PipelineInputsTests|PluginPresetsTests|PipelineStepValuesTests"` verde.
- [ ] **Step 5: Commit** — `feat(pipeline): dimensioni, forza e modello per passaggio`.

### Task 6: `PipelineDraft`, lo stato di «Crea pipeline…»

**Files:** Create `Packages/Sources/HubCore/Pipelines/PipelineDraft.swift`. Test: `Packages/Tests/HubCoreTests/PipelineDraftTests.swift`.

**Interfaces — Consumes:** `UserPipeline`, `PresetStore.isValidName`.
**Produces:**

```swift
public struct PipelineDraft: Equatable, Sendable {
  public enum Row: Hashable, Sendable { case current, preset(String) }
  public enum Strength: Equatable, Sendable { case automatic, value(Double), invalid }
  public var name = ""
  public var chain = true
  public private(set) var order: [Row]            // le righe spuntate, nell'ordine delle spunte
  public var scaleText: [Row: String]             // riga assente = "1"
  public var strengthText: [Row: String]          // riga assente = ""
  public init()
  public mutating func toggle(_ row: Row)
  public func number(of row: Row) -> Int?         // 1-based; nil se non spuntata
  public func editsScale(_ row: Row) -> Bool      // spuntata e non prima
  public func editsStrength(_ row: Row) -> Bool   // spuntata, non prima, non .current
  public static func scale(_ text: String) -> Double?       // nil: vuoto, non numero, fuori da 0.25...4
  public static func strength(_ text: String) -> Strength   // percentuale 0…100 → 0…1; vuoto = .automatic
  public func isScaleValid(_ row: Row) -> Bool    // true per le righe che non modificano la scala
  public func isStrengthValid(_ row: Row) -> Bool
  public var hasValidName: Bool
  public var canSave: Bool                        // nome valido, almeno 2 passaggi, ogni valore valido
  public var pipeline: UserPipeline?              // nil con meno di 2 passaggi o un valore non valido
}
```

I numeri accettano la virgola e il punto. Togliere una spunta lascia i testi della riga (se la si rispunta tornano).

- [ ] **Step 1: Test che falliscono:**
  - `theOrderIsTheOrderOfTheTicks`: toggle `B`, `.current`, `A` → numeri 1, 2, 3; `number(of: .preset("C")) == nil`.
  - `untickingMovesTheLaterNumbersUp`: dopo, toggle `.current` → `B` 1, `A` 2.
  - `scaleParsing` (**Review Focus 5**): `"1,5"` e `"1.5"` → 1.5; `"2"` → 2; `""`, `"abc"`, `"0"`, `"5"`, `"-1"` → nil; `"0,25"` → 0.25; `"4"` → 4.
  - `strengthParsing`: `""` e `"  "` → `.automatic`; `"30"` → `.value(0.3)`; `"12,5"` → `.value(0.125)`; `"0"` → `.value(0)`; `"100"` → `.value(1)`; `"150"`, `"-1"`, `"abc"` → `.invalid`.
  - `theFirstPassAndCurrentSettingsDoNotEditStrength`: ordine `A`, `.current`, `B` → `editsScale` `[false, true, true]`, `editsStrength` `[false, false, true]`.
  - `canSaveNeedsANameTwoPassesAndValidValues`: 1 passaggio → false; 2 passaggi e nome `"X"` → true; nome `"a/b"` → false; `scaleText[B] = ""` → false; lo stesso testo non valido su una riga non spuntata o sulla prima → true.
  - `buildsThePipeline`: ordine `.current`, `A` (scala `"2"`), `B` (forza `"30"`), `chain = false` → `UserPipeline(chain: false, steps: [(nil, 1, nil), ("A", 2, nil), ("B", 1, 0.3)])`; un testo di scala o forza lasciato sul primo passaggio non entra nella pipeline.
- [ ] **Step 2–4:** vedere il fallimento, implementare, `swift test --filter PipelineDraftTests` verde.
- [ ] **Step 5: Commit** — `feat(pipeline): stato della finestra Crea pipeline`.

### Task 7: il RUN esegue una pipeline dell'utente

**Files:** Modify `App/Generation/GenerationController.swift` (`run`, `runPipeline`, `renderInputs`), `App/Localizable.xcstrings` (`pipeline.unreadable`, `pipeline.missingModel`).

**Interfaces — Consumes:** Task 2–5. **Produces** (per i Task 8–10):

```swift
let userPipelines = UserPipelineStore(folder: UserPipelineStore.defaultFolder)   // accanto a `presets`
```

- [ ] **Step 1: `run(with:)`.** Se la pipeline attiva ha `userPipelineName`, rileggila da `userPipelines` (decisione 3): se non si legge, `session.fail(with: .generationFailed(«Pipeline non leggibile: <nome>»))` e `return true`; se si legge, usa `loaded.pluginPipeline(named:)` e rimettila nello store con `setUserPipeline`. Poi `PipelinePresets.load` come oggi. Passa a `runPipeline` l'intera `PluginPipeline`.
- [ ] **Step 2: `runPipeline`**, in quest'ordine:
  - **prima del primo passaggio** (siamo dopo `ensureServerForRun`, quindi il catalogo c'è — **Review Focus 1**): `PipelinePresets.missingModels` non vuoto → `session.fail` con «Modello non installato: <nomi separati da virgola>» e fine;
  - **modello del passaggio:** `PipelinePresets.model(for:presets:header: connection.selection.selectedFile)`; da quel file il `CatalogModel` (`catalog.model(forFile:)`) dà famiglia, `isEditModel` e `needsInpaintControl`. `RunAvailability.blocker`, `JobComposer.batches(model:family:)`, `FamilyTraits…usesMoodboard`, `PipelineInputs.strength(editModel:)` e `renderInputs` usano **questo** modello, non quello dell'header;
  - **`renderInputs(in:parameters:model:)`** prende il `CatalogModel?` del passaggio (il RUN semplice passa `selectedModel(in:)`);
  - **dimensioni:** solo per i passaggi con `usesPresetModel` (pipeline dell'utente), dal 2° in poi: `PipelineSizes.scaled(precedente, by: pass.scale, limit: used.parameters.sizeLimit)` scritto in `used.parameters.width/height` prima di `renderInputs`; il 1° tiene quelle che dà `PipelinePresets.fields`. Per le pipeline dei plug-in niente cambia;
  - **forza:** `PipelineInputs.strength(…, step: pass.strength)`.
- [ ] **Step 3:** aggiungi le due chiavi a `Localizable.xcstrings` (tabella «Testi»).
- [ ] **Step 4:** `swift test --filter LocalizationCatalogTests` verde; `xcodebuild … build` → `BUILD SUCCEEDED`; `cd Packages && swift test 2>&1 | grep -E "Test run with|✘|error:"` tutto verde.
- [ ] **Step 5: Commit** — `feat(pipeline): il RUN esegue le pipeline dell'utente`.

### Task 8: menu Preset e pulsante RUN

**Files:** Modify `App/Generation/Presets/PresetBar.swift`, `App/Generation/GenerationController.swift`, `App/Plugins/ContributionText.swift`, `App/Localizable.xcstrings`.

**Interfaces — Produces** (in `GenerationController`):

```swift
/// Makes a saved pipeline the pipeline of the RUN; the text of the problem when its file cannot be read.
func selectPipeline(named name: String) -> String?
/// After a pipeline or a preset was saved, renamed or deleted.
func syncActivePipeline(renamedTo newName: String? = nil)   // contributions?.syncUserPipeline(with: userPipelines, renamedTo:)
```

- [ ] **Step 1: Menu** (ordine della spec §3): preset; `Divider` e gruppo delle pipeline solo se `userPipelines.names` non è vuoto, con il segno di spunta su quella il cui nome è `contributions?.pipeline?.userPipelineName`; `Divider`; «Salva come preset…», «Crea pipeline…» (disattivata senza preset), «Gestisci preset e pipeline…» (disattivata senza preset **e** senza pipeline), «Importa preset da file…». La scelta chiama `selectPipeline`; un errore va in `importMessage` («Pipeline non leggibile: <nome>»). `userPipelines.refresh()` dove oggi c'è `presets.refresh()`. «Crea pipeline…» apre per ora un foglio vuoto col solo titolo (lo riempie il Task 9).
- [ ] **Step 2: `ContributionText.pipelineHelp`:** prima riga = nome del plug-in (come oggi) oppure, per l'utente, il nome della pipeline. Righe dei passaggi di una pipeline dell'utente: `N. <nome del preset>` oppure `N. Impostazioni attuali`, più ` ← dal risultato precedente` se `useOutputAsStart`. Le pipeline dei plug-in restano come oggi. Il titolo «Run · N passaggi» e «Togli la pipeline» in `HeaderBar` non cambiano.
- [ ] **Step 3:** chiavi `pipeline.create`, `pipeline.current`, e i nuovi valori di `preset.manage` e `preset.manage.title`.
- [ ] **Step 4:** `swift test --filter LocalizationCatalogTests` verde; `xcodebuild … build` → `BUILD SUCCEEDED`.
- [ ] **Step 5: Commit** — `feat(pipeline): le pipeline nel menu Preset`.

### Task 9: finestra «Crea pipeline…»

**Files:** Create `App/Generation/Presets/PipelineSheets.swift` (`CreatePipelineSheet`; il progetto usa cartelle sincronizzate: il file nuovo entra nel target da solo). Modify `App/Generation/Presets/PresetBar.swift`, `App/Localizable.xcstrings`.

**Interfaces — Consumes:** `PipelineDraft` (Task 6), `controller.presets`, `controller.userPipelines`, `controller.syncActivePipeline()`.

- [ ] **Step 1: Vista** secondo la spec §6, stile di `ManagePresetsSheet` (`DSBackground`, `DSPillButtonStyle`, `DS.rowGap`), larghezza 500, `@State var draft = PipelineDraft()`:
  - titolo; campo Nome; sotto, in `DS.remove`: «Nome non valido» (nome non vuoto e non valido) oppure «Esiste già una pipeline…» (`userPipelines.contains`); dopo un salvataggio, al loro posto «Salvata.» in secondario, finché il `draft` non cambia;
  - casella «Concatena i risultati» con la nota in piccolo;
  - intestazione `# | Preset | Scala | Forza`; prima riga `.current` in corsivo con la sua nota; poi `controller.presets.names`, nome non modificabile e sotto il modello del preset (letto una volta, `presets.preset(named:)?.model`) oppure «Nessun modello: quello dell'header»;
  - casella di spunta disegnata a mano: vuota, oppure col numero `draft.number(of:)`; il clic chiama `draft.toggle`;
  - Scala: campo legato a `draft.scaleText[row]` con «×» fuori; mostra «—» ed è disattivato se `!draft.editsScale(row)`; Forza: campo legato a `draft.strengthText[row]`, segnaposto «auto», «%» fuori, disattivato se `!draft.editsStrength(row)`; bordo `DS.remove` quando `!isScaleValid` / `!isStrengthValid`;
  - in basso «Chiudi» (`.cancelAction`, chiude senza conferma) e «Salva» (primario, `.disabled(!draft.canSave)`): `userPipelines.save(draft.pipeline!, named: draft.name)`, poi `controller.syncActivePipeline()`; la finestra resta aperta. Un errore di scrittura compare in rosso al posto di «Salvata.».
- [ ] **Step 2:** le chiavi della tabella «Testi» che servono qui (`pipeline.create.title`, `pipeline.invalidName`, `pipeline.replaces`, `pipeline.saved`, `pipeline.chain`, `pipeline.chain.note`, `pipeline.column.preset`, `pipeline.column.scale`, `pipeline.current.note`, `pipeline.noModel`, `pipeline.strength.auto`, `sheet.close`).
- [ ] **Step 3:** `swift test --filter LocalizationCatalogTests` verde; `xcodebuild … build` → `BUILD SUCCEEDED`.
- [ ] **Step 4: Commit** — `feat(pipeline): finestra Crea pipeline`.

### Task 10: «Gestisci preset e pipeline…», verifica finale

**Files:** Modify `App/Generation/Presets/PresetSheets.swift`, `App/Localizable.xcstrings`; alla fine `docs/superpowers/backlog.md` e `docs/superpowers/briefing-prossima-sessione.md` (locali, **non** in git).

- [ ] **Step 1: `ManagePresetsSheet`** con due gruppi titolati (`pipeline.group.presets`, `pipeline.group.pipelines`); il secondo compare solo se c'è almeno una pipeline, «Nessun preset salvato» resta sotto il primo.
  - `PresetRow` riceve il `controller`: dopo una rinomina riuscita `controller.userPipelines.renamePreset(vecchio, to: nuovo)` e `controller.syncActivePipeline()`. La cancellazione di un preset non tocca le pipeline (spec §4).
  - `PipelineRow` nuova: nome modificabile (`userPipelines.rename`, errori con `PresetBar.text(of:)`), sotto «N passaggi» (`contribution.passes`) oppure, in `DS.remove`, «manca: <nomi>» per i `presetNames` che `controller.presets.contains` non trova (ricalcolato quando cambiano i preset); per un file illeggibile «Pipeline non leggibile: <nome>»; cestino (`pipeline.delete`). Dopo la rinomina `controller.syncActivePipeline(renamedTo: nuovo)`; dopo il cestino `controller.syncActivePipeline()`.
- [ ] **Step 2:** chiavi `pipeline.group.presets`, `pipeline.group.pipelines`, `pipeline.missing`, `pipeline.delete`.
- [ ] **Step 3: Verifica completa:** `cd Packages && swift test 2>&1 | grep -E "Test run with|✘|error:"` (tutti verdi, più dei 721 di partenza); `xcodebuild … build` → `BUILD SUCCEEDED`; `git status` senza file estranei; controllo dei dati personali nel diff del ramo (comando del briefing, §3) vuoto.
- [ ] **Step 4: Commit** — `feat(pipeline): le pipeline in Gestisci preset e pipeline`.
- [ ] **Step 5: Prove a mano per l'utente** (dopo aver ricompilato l'app Debug; elenco da dargli così com'è):
  1. Crea pipeline: spunta tre righe in ordine sparso → numeri 1, 2, 3; togli la 2ª spunta → la 3ª diventa 2.
  2. Scala «abc» o vuota → bordo rosso e Salva spento; «1,5» accettato; Forza spenta sul passaggio 1 e su «Impostazioni attuali».
  3. Salva con un nome che esiste → avviso rosso, poi «Salvata.»; la finestra resta aperta.
  4. Menu Preset: gruppo delle pipeline con la spunta su quella scelta; RUN mostra «Run · N passaggi» e l'aiuto elenca i passaggi; «Togli la pipeline» la toglie.
  5. RUN di Flux2 → Qwen ×2 con concatenazione: secondo risultato al doppio delle dimensioni, col modello Qwen (sidebar dei Risultati); l'header resta su Flux2.
  6. Rinomina un preset in Gestisci → la pipeline lo segue (aiuto del RUN e RUN funzionante).
  7. Elimina un preset → «manca: …» in Gestisci e «Preset non trovato: …» al RUN.
  8. Con il server parcheggiato per l'LLM (dopo un Migliora Prompt), RUN di una pipeline con due modelli: parte senza «Modello non installato».
  9. Una pipeline di Sphere Light o Batch plus funziona come prima; mandarla mentre è attiva una pipeline dell'utente la sostituisce.
  10. Un preset con un modello che il server non ha → «Modello non installato: …», nessun passaggio parte.
- [ ] **Step 6:** aggiorna il backlog (rinviati: i punti del §9 della spec) e il briefing; poi messaggio finale nel formato del briefing §6 e richiesta di via libera per l'unione.
