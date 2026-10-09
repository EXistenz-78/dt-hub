# LLM assegnati alle famiglie dei modelli — Piano di implementazione

> **Per chi esegue:** SOTTO-SKILL OBBLIGATORIA: `superpowers:subagent-driven-development` (consigliata) oppure `superpowers:executing-plans`. I passi usano la sintassi a caselle (`- [ ]`).

**Obiettivo:** ogni LLM installato ha una famiglia (o «Tutti gli altri» / «Nessuna») e un uso (Migliora / Genera / Entrambi / Solo plug-in); Migliora Prompt e Genera Prompt scelgono l'LLM da lì e usano il suo system prompt se ne ha uno; i plug-in ricevono famiglia e uso; Prompt Master li usa per il PE di Qwen Image 2.1.

**Architettura:** tipi e funzioni pure in HubCore (`LanguageModelAssignment`, riconciliazione, `LanguageModelRouter`, `LanguageModelProfile`, `LanguageModelFamilyOptions`), testati con `swift test`; il `LanguageModelManager` riconcilia e sceglie; `PromptAssistant` riceve un risolutore invece di usare sempre l'LLM scelto; Preferenze › LLM diventa un elenco con due menu per riga; due campi facoltativi in più nel contesto dei plug-in.

**Tecnologie:** Swift 6.2, Swift Testing, SwiftUI, `JSONSerialization`.

**Spec:** `docs/superpowers/specs/2026-10-09-llm-per-famiglia-design.md` (leggerla prima: regole di riconciliazione §4, scelta §5, profilo §6).

## Vincoli globali

- Base: `origin/main` (0.1.3). Ramo nuovo (es. `llm-per-famiglia`). **Non si unisce in `main` e non si fa push/release senza «unisci»/via libera esplicito dell'utente.**
- Si aggiungono i file **per nome** (`git add <file>`); mai `git add -A` né `git add docs`.
- Test: `cd Packages && swift test --filter <Suite> 2>&1 | grep -E "Test run with|error:"`; plug-in: `cd Plugins/PromptMaster && swift test 2>&1 | grep -E "Test run with|error:"`.
- `LanguageModelManager` e `PromptAssistant` sono `@MainActor`: test marcati `@MainActor`. Niente `UserDefaults.standard` nei test (suite con nome unico, come in `LanguageModelManagerTests.manager(...)`).
- **I test esistenti di `LanguageModelManagerTests` e `PromptAssistantTests` restano verdi senza modifiche** (salvo la firma dell'`init` di `PromptAssistant`, vedi Task 5).
- L'app si compila con `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build`.
- Testi in italiano e inglese (`Localizable.xcstrings`, `extractionState: manual`). Commenti nel codice in inglese.
- `LanguageModelError` non cambia (contratto dei plug-in).
- Dopo l'unione (solo con «unisci»): ricompilare l'app dell'utente, reinstallare Prompt Master (`rm -rf` della vecchia versione prima di `cp -R`).

## Review Focus

1. Aggiornamento da 0.1.3 con un LLM scelto e nessuna assegnazione: i tasti continuano a usare quell'LLM (Task 3).
2. Un solo LLM nella cartella: funziona senza toccare le Preferenze (Task 3).
3. Genera Prompt quando l'unico LLM disponibile per il posto non legge immagini: `.imagesNotSupported`, non «nessun LLM» (Task 2).
4. Disco esterno dei modelli non montato: le assegnazioni non si perdono e tornano quando il disco ricompare (Task 3).
5. `system_prompt.txt` vuoto, solo spazi, o `generation_config.json` rotto: comportamento come senza file (Task 4).

---

## Struttura dei file

| File | Responsabilità |
|---|---|
| `Packages/Sources/HubCore/Language/LanguageModelAssignment.swift` (nuovo) | `LanguageModelFamily`, `LanguageModelUse`, `LanguageModelAssignment`, riconciliazione |
| `Packages/Sources/HubCore/Language/LanguageModelRouter.swift` (nuovo) | scelta dell'LLM e `shadowed` |
| `Packages/Sources/HubCore/Language/LanguageModelProfile.swift` (nuovo) | system prompt e `generation_config.json` |
| `Packages/Sources/HubCore/Language/LanguageModelFamilyOptions.swift` (nuovo) | voci del menu Famiglia |
| `Packages/Sources/HubKit/Language/LanguageModel.swift` (modifica) | `LanguageModelTask` |
| `Packages/Sources/HubCore/Language/LanguageModelSettings.swift`, `LanguageModelManager.swift` (modifica) | `assignments`, riconciliazione, scelta senza nome |
| `Packages/Sources/HubCore/PromptAssist/PromptBrief.swift`, `PromptAssistant.swift` (modifica) | richieste con system prompt proprio, risolutore |
| `Packages/Sources/HubKit/Plugin/PluginMessages.swift`, `PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift`, `PluginKit/README.md` (modifica) | `family`, `use` nel contesto |
| `App/Preferences/LanguagePreferencesView.swift`, `App/Generation/GenerationController.swift`, `App/DTHubApp.swift`, `App/Localizable.xcstrings` (modifica) | interfaccia e collegamento |
| `Plugins/PromptMaster/Sources/PromptMaster/PEPlanner.swift` (modifica) | PE dall'assegnazione |

---

### Task 1: Tipi dell'assegnazione e impostazioni

**Files:**
- Create: `Packages/Sources/HubCore/Language/LanguageModelAssignment.swift`
- Modify: `Packages/Sources/HubKit/Language/LanguageModel.swift` (aggiungere `LanguageModelTask`), `Packages/Sources/HubCore/Language/LanguageModelSettings.swift`
- Test: `Packages/Tests/HubCoreTests/LanguageModelAssignmentTests.swift`

**Interfaces:**
- Produces (spec §3):
  ```swift
  public enum LanguageModelTask: Equatable, Sendable { case enhance, describe }               // HubKit
  public enum LanguageModelFamily: Hashable, Codable, Sendable { case none, allOthers, family(String) }
  public enum LanguageModelUse: String, Codable, Sendable, CaseIterable {
    case enhance, describe, both, pluginsOnly
    public func covers(_ task: LanguageModelTask) -> Bool
  }
  public struct LanguageModelAssignment: Equatable, Codable, Sendable {
    public var family: LanguageModelFamily; public var use: LanguageModelUse
    public init(family: LanguageModelFamily, use: LanguageModelUse)
  }
  // LanguageModelSettings: public var assignments: [String: LanguageModelAssignment]   (init con default [:])
  ```

- [ ] **Step 1: Test che falliscono**: `LanguageModelFamily` codifica come stringa singola `""`, `"*"`, `"qwen_image_2.1"` e torna uguale; una stringa sconosciuta qualunque è `.family(<stringa>)`; `LanguageModelUse.covers`: `enhance` copre solo `.enhance`, `describe` solo `.describe`, `both` entrambi, `pluginsOnly` nessuno; `LanguageModelSettings` vecchio (JSON senza `assignments`) decodifica con `assignments == [:]` e `selectedModel` intatto; round trip con due assegnazioni.
- [ ] **Step 2: Vedere il fallimento** — `swift test --filter LanguageModelAssignmentTests`.
- [ ] **Step 3: Implementare** (`Codable` di `LanguageModelFamily` a mano con `singleValueContainer`; `assignments` nella decodifica lenient di `LanguageModelSettings`).
- [ ] **Step 4: Test verdi**, poi `swift test --filter LanguageModel` (i test vecchi restano verdi).
- [ ] **Step 5: Commit** — `feat(llm): assegnazione di famiglia e uso agli LLM`.

---

### Task 2: `LanguageModelRouter`

**Files:**
- Create: `Packages/Sources/HubCore/Language/LanguageModelRouter.swift`
- Test: `Packages/Tests/HubCoreTests/LanguageModelRouterTests.swift`

**Interfaces:**
- Consumes: Task 1, `LanguageModelDescriptor`.
- Produces:
  ```swift
  public enum LanguageModelRouter {
    public static func model(for task: LanguageModelTask, family: String?, models: [LanguageModelDescriptor],
                             assignments: [String: LanguageModelAssignment]) -> Result<LanguageModelDescriptor, LanguageModelError>
    public static func shadowed(models: [LanguageModelDescriptor], assignments: [String: LanguageModelAssignment]) -> Set<String>
  }
  ```

- [ ] **Step 1: Test che falliscono** (descrittori costruiti a mano; nomi `pe-t2i` testo, `pe-i2i` visione, `vl` visione, `txt` testo):
  - assegnazioni `pe-t2i: qwen_image_2.1·enhance`, `vl: *·both` → `enhance` su `qwen_image_2.1` = `pe-t2i`; `describe` su `qwen_image_2.1` = `vl`; `enhance` su `flux2` = `vl`; `family nil` → `vl`.
  - `pe-i2i: qwen_image_2.1·pluginsOnly` non viene mai scelto.
  - `pe-i2i: qwen_image_2.1·describe` → `describe` su `qwen_image_2.1` = `pe-i2i`.
  - solo `txt: *·both` → `describe` = `.failure(.imagesNotSupported)` (**Review Focus 3**); `enhance` = `txt`.
  - nessuna assegnazione → `.failure(.noModelSelected)`; solo `none` → idem.
  - due LLM `a`, `b` su `*·both` → vince `a`; `shadowed == ["b"]`; con `a: *·enhance`, `b: *·both` → `shadowed` vuoto (b vince su describe).
  - un'assegnazione per un nome non presente tra i modelli è ignorata.
- [ ] **Step 2: Vedere il fallimento.**
- [ ] **Step 3: Implementare** secondo la spec §5. `shadowed`: per ogni modello assegnato (famiglia ≠ none, uso ≠ pluginsOnly) e per ogni compito che il suo uso copre, se `model(for:family:...)` sulla sua famiglia (o `nil` per `allOthers`) restituisce un altro nome, il modello è in ombra **solo se non vince su nessun compito**.
- [ ] **Step 4: Test verdi.**
- [ ] **Step 5: Commit** — `feat(llm): scelta dell'LLM per famiglia e compito`.

---

### Task 3: Riconciliazione e `LanguageModelManager`

**Files:**
- Modify: `Packages/Sources/HubCore/Language/LanguageModelAssignment.swift` (funzione `reconciled`), `Packages/Sources/HubCore/Language/LanguageModelManager.swift`
- Test: `Packages/Tests/HubCoreTests/LanguageModelReconcileTests.swift`; nuovi casi in `LanguageModelTests.swift` (struct `LanguageModelManagerTests`, helper `manager(...)` e `folder()` esistenti)

**Interfaces:**
- Consumes: Task 1–2.
- Produces:
  ```swift
  public enum LanguageModelAssignments {
    public static func reconciled(_ settings: LanguageModelSettings, models: [LanguageModelDescriptor],
                                  downloaded: String? = nil) -> [String: LanguageModelAssignment]
  }
  // LanguageModelManager
  public func reconcileAssignments(downloaded: String? = nil)   // calcola, assegna a settings.assignments se cambia (che salva)
  public func model(for task: LanguageModelTask, family: String?) -> Result<LanguageModelDescriptor, LanguageModelError>
  ```
  `respond(to:images:options:modelNamed:)` senza nome: `reconcileAssignments()` poi `model(for: images.isEmpty ? .enhance : .describe, family: nil)`; un errore va in `state = .failed(...)` come oggi per `.noModelSelected`. Nuovo overload `respond(to:images:options:model: LanguageModelDescriptor)` usato dal Task 5 (stessa logica di caricamento, senza scelta).

- [ ] **Step 1: Test che falliscono** (`reconciled`, funzione pura):
  - migrazione: `assignments` vuoto, `selectedModel` = percorso di `vl` presente → `vl: *·both` (**Review Focus 1**); `selectedModel` che non esiste → nessuna migrazione.
  - un solo modello `only` senza voce o su `none`, nessuno su `*` → `only: *·both` (**Review Focus 2**); un solo modello su `qwen_image_2.1·enhance` → resta così (un'assegnazione a una famiglia non si tocca mai).
  - `downloaded: "mlx-community/Qwen3-VL-8B-Instruct-4bit"` con nessuno su `*` → quel modello `*·both`; con qualcuno già su `*` → `none·both`.
  - un modello presente senza voce → `none·both`; un'assegnazione di un modello assente resta (**Review Focus 4**).
  - (manager) i test esistenti con `selectedModel` restano verdi; nuovo: un manager con due modelli e `assignments` `vision-model: *·describe`, `text-model: *·enhance` → `respond(to:)` carica `text-model`, `respond(to:images:)` carica `vision-model`; `reconcileAssignments()` salva le assegnazioni nel negozio (rileggendo con un secondo `LanguageModelSettingsStore` sulla stessa suite).
- [ ] **Step 2: Vedere il fallimento.**
- [ ] **Step 3: Implementare.** In `respond` senza nome: prima `reconcileAssignments()`, poi il router; per un nome esplicito il comportamento non cambia.
- [ ] **Step 4: Test verdi** — `swift test --filter LanguageModel`.
- [ ] **Step 5: Commit** — `feat(llm): riconciliazione delle assegnazioni e scelta nel manager`.

---

### Task 4: `LanguageModelProfile`

**Files:**
- Create: `Packages/Sources/HubCore/Language/LanguageModelProfile.swift`
- Test: `Packages/Tests/HubCoreTests/LanguageModelProfileTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct LanguageModelProfile: Equatable, Sendable {
    public struct Generation: Equatable, Sendable { public var temperature: Double?; public var topP: Double?; public var topK: Int? }
    public var generation: Generation?
    public func systemPrompt(for task: LanguageModelTask) -> String?
    public static func load(folder: URL, read: (URL) -> Data? = { try? Data(contentsOf: $0) }) -> LanguageModelProfile
  }
  ```

- [ ] **Step 1: Test che falliscono** (cartella temporanea): con solo `system_prompt.txt` → stesso testo per i due compiti, spazi ai bordi tolti; con `system_prompt_t2i.txt` e `system_prompt.txt` → `enhance` usa t2i, `describe` usa il generico; con `system_prompt_i2i.txt` → `describe` lo usa; file vuoto o solo spazi → come assente (**Review Focus 5**); `generation_config.json` `{"temperature":0.7,"top_p":0.8,"top_k":20,"max_new_tokens":512}` → `Generation(0.7, 0.8, 20)`; JSON rotto → `generation == nil`; JSON con solo `temperature` → gli altri `nil`; cartella vuota → tutto `nil`.
- [ ] **Step 2: Vedere il fallimento.**
- [ ] **Step 3: Implementare.**
- [ ] **Step 4: Test verdi.**
- [ ] **Step 5: Commit** — `feat(llm): system prompt e impostazioni dalla cartella dell'LLM`.

---

### Task 5: `PromptBrief` e `PromptAssistant` con l'LLM scelto

**Files:**
- Modify: `Packages/Sources/HubCore/PromptAssist/PromptBrief.swift`, `Packages/Sources/HubCore/PromptAssist/PromptAssistant.swift`, `App/Generation/GenerationController.swift` (creazione dell'assistente)
- Test: `Packages/Tests/HubCoreTests/PromptBriefTests.swift`, `PromptAssistantTests.swift` (nuovi casi; aggiornare la sola costruzione dell'assistente)

**Interfaces:**
- Consumes: Task 2–4.
- Produces:
  ```swift
  // PromptBrief
  public static func enhance(_ current: PromptPair, ownSystem: String, generation: LanguageModelProfile.Generation?) -> PromptRequest
  public static func describe(imageAt url: URL, ownSystem: String, generation: LanguageModelProfile.Generation?) -> PromptRequest
  // PromptAssistant
  public struct Choice: Sendable { public let model: LanguageModelDescriptor; public let profile: LanguageModelProfile }
  public typealias Resolve = @MainActor (LanguageModelTask, String?) -> Result<Choice, LanguageModelError>
  public typealias Respond = @MainActor (String, [URL], LanguageModelOptions, LanguageModelDescriptor) async throws(LanguageModelError) -> String
  public init(resolve: @escaping Resolve, respond: @escaping Respond)
  ```
  Con un system prompt proprio (`choice.profile.systemPrompt(for:)` non nil) si usano le due funzioni nuove; altrimenti quelle di oggi. Un errore di `resolve` diventa `failure = .model(error)` senza chiamare `respond`.

- [ ] **Step 1: Test che falliscono**:
  - `PromptBrief.enhance(_, ownSystem:, generation:)`: `prompt == current.prompt` (nessuna istruzione dell'app), `images` vuoto, `options == LanguageModelOptions(system: ownSystem, temperature: g.temperature, topP: g.topP, topK: g.topK, maxTokens: 16384, thinking: true)`; con `generation nil` temperatura/topP/topK `nil`.
  - `PromptBrief.describe(imageAt:, ownSystem:, generation:)`: `prompt == "Describe this image as a prompt for an image-generation model."`, `images == [url]`, stesse opzioni.
  - `PromptAssistant`: con `resolve` che dà un modello **senza** system prompt → la richiesta è quella di oggi (`PromptBrief.enhance(current, family:)`) e `respond` riceve quel modello; **con** system prompt → richiesta con `ownSystem`; `resolve` che fallisce con `.noModelSelected` → `failure == .model(.noModelSelected)` e `respond` mai chiamato; la famiglia passata a `resolve` è quella dell'operazione; il compito è `.enhance` / `.describe`.
  - I test esistenti di `PromptAssistantTests` restano con le stesse attese, cambiando solo la costruzione (un `resolve` che dà sempre un modello finto senza profilo).
- [ ] **Step 2: Vedere il fallimento.**
- [ ] **Step 3: Implementare.** In `GenerationController.init`: `resolve` = `{ task, family in languageModel.model(for: task, family: family).map { Choice(model: $0, profile: LanguageModelProfile.load(folder: URL(fileURLWithPath: $0.path, isDirectory: true))) } }` (chiamare `languageModel.reconcileAssignments()` prima della scelta, dentro `model(for:family:)` o qui); `respond` = l'overload `respond(to:images:options:model:)` del Task 3.
- [ ] **Step 4: Test verdi** — `swift test --filter Prompt`; poi `xcodebuild … build`.
- [ ] **Step 5: Commit** — `feat(prompt-assist): l'LLM della famiglia, con il suo system prompt`.

---

### Task 6: Preferenze › LLM

**Files:**
- Create: `Packages/Sources/HubCore/Language/LanguageModelFamilyOptions.swift`, `Packages/Tests/HubCoreTests/LanguageModelFamilyOptionsTests.swift`
- Modify: `App/Preferences/LanguagePreferencesView.swift`, `App/Preferences/PreferencesView.swift` (se serve passare `connection` per il catalogo), `App/Localizable.xcstrings`

**Interfaces:**
- Consumes: Task 1–3, `PromptGuides.all` (`label`), `connection.monitor.catalog` (famiglie dei modelli).
- Produces: `public enum LanguageModelFamilyOptions { public static func list(catalogFamilies: [String]) -> [(key: String, label: String)] }`.

- [ ] **Step 1: Test che falliscono** (`LanguageModelFamilyOptionsTests`): senza catalogo → le 13 famiglie di `PromptGuides` con la loro `label`, ordinate per `label` (`localizedStandardCompare`); con `["flux2_9b", "wan_v2.1", "wan_v2.1"]` → in più una voce `("wan_v2.1", "wan_v2.1")`, una sola volta, nessun doppione di `flux2_9b`.
- [ ] **Step 2: Vedere il fallimento.** **Step 3: Implementare** la funzione. **Step 4: Test verdi.**
- [ ] **Step 5: Vista** (spec §7): togliere il `Picker("prefs.llm.model")` e la logica di `refresh()` su `selectedModel`; `refresh()` chiama `manager.reconcileAssignments()` e rilegge i modelli; `.onChange(of: download.completed)` chiama `manager.reconcileAssignments(downloaded: RecommendedLanguageModel.folderName)`. Una riga per modello (`ForEach(models)`): `Text(verbatim: model.name)`, dimensione, `Image(systemName: "eye")` se `supportsImages`, `Picker` Famiglia (`.none` «Nessuna», `Divider`, le voci di `LanguageModelFamilyOptions.list`, `Divider`, `.allOthers` «Tutti gli altri») legato a `manager.settings.assignments[model.name]`, `Picker` Uso (4 voci, disattivato se `.none`); se `LanguageModelRouter.shadowed(...)` contiene il nome, `Image(systemName: "exclamationmark.triangle")` in `DS.remove` con `.help`. Nota sotto l'elenco (spec §7).
- [ ] **Step 6: Testi** (it / en): `prefs.llm.family` Famiglia / Family, `prefs.llm.family.none` Nessuna / None, `prefs.llm.family.all` Tutti gli altri / All others, `prefs.llm.use` Uso / Use, `prefs.llm.use.enhance` Migliora prompt / Enhance prompt, `prefs.llm.use.describe` Genera prompt / Generate prompt, `prefs.llm.use.both` Entrambi / Both, `prefs.llm.use.plugins` Solo plug-in / Plug-ins only, `prefs.llm.shadowed` Un altro LLM ha la precedenza per questa famiglia e questo uso. / Another LLM takes precedence for this family and use., `prefs.llm.assign.note` (spec §7); **cambiare** `llm.error.noModel` in «Nessun LLM assegnato per questa famiglia: sceglilo in Preferenze › LLM.» / «No LLM is assigned to this family: choose one in Settings › LLM.»; togliere le chiavi non più usate (`prefs.llm.model`, `prefs.llm.model.none` se nessun altro le usa).
- [ ] **Step 7: Compilare** — `xcodebuild … build` → `BUILD SUCCEEDED`.
- [ ] **Step 8: Commit** — `feat(prefs): elenco degli LLM con famiglia e uso`.

---

### Task 7: Famiglia e uso nel contesto dei plug-in

**Files:**
- Modify: `Packages/Sources/HubKit/Plugin/PluginMessages.swift` (`PluginLanguageModel`), `PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift` (`DTHubLanguageModel`), `PluginKit/README.md`, `App/DTHubApp.swift` (la closure `plugins.languageModels`)
- Test: `Packages/Tests/HubKitTests` (codifica), `Packages/Tests/HubCoreTests/PluginRegistryTests.swift` (il contesto porta i campi)

**Interfaces:**
- Produces: `PluginLanguageModel` e `DTHubLanguageModel` con `public var family: String?` e `public var use: String?` (init con default `nil`, decodifica che accetta l'assenza). Valori: `family` = `"*"` per `allOthers`, la chiave per `.family(k)`, assente per `.none`; `use` = `"enhance"`, `"describe"`, `"both"`, `"plugins"`. Una funzione in HubCore `LanguageModelAssignment.pluginFields -> (family: String?, use: String?)` per non ripetere la mappa.

- [ ] **Step 1: Test che falliscono**: codifica di `PluginLanguageModel` con e senza i due campi (assenti nel JSON quando `nil`); `DTHubLanguageModel` decodifica un JSON vecchio (senza i campi) e uno nuovo; `pluginFields` per le 4×3 combinazioni rilevanti (`none` → `family` nil e `use` comunque valorizzato).
- [ ] **Step 2: Vedere il fallimento.** **Step 3: Implementare**; in `DTHubApp` la closure mappa `languageModel.settings.assignments[$0.name]` con `pluginFields`. **Step 4: Test verdi**; `PluginKit/README.md`: nella voce `languageModels` di `context` aggiungere `family` e `use` con i valori.
- [ ] **Step 5: Commit** — `feat(plugins): famiglia e uso degli LLM nel contesto`.

---

### Task 8: Prompt Master usa l'assegnazione

**Files:**
- Modify: `Plugins/PromptMaster/Sources/PromptMaster/PEPlanner.swift`, versione del plug-in (dove la definisce `Scripts/build.sh` o il manifest; minore +1)
- Test: `Plugins/PromptMaster/Tests/PromptMasterTests/PEPlannerTests.swift` (helper `plan(...)` esistente)

**Interfaces:**
- Consumes: `DTHubLanguageModel.family`/`use` (Task 7).
- Produces: `PEPlanner.plan(...)` con la stessa firma; ordine nuovo: (1) modelli con `family == "qwen_image_2.1"` e `use` in `["enhance","both"]` che hanno un system prompt nella cartella (stessi file di oggi, `systemFileNames`) → il più grande per `folderSize`; (2) altrimenti il comportamento attuale per nome.

- [ ] **Step 1: Test che falliscono**: un modello chiamato `my-enhancer` (nessun marcatore) con `family "qwen_image_2.1"`, `use "enhance"` e `system_prompt.txt` → `.enhancer` con quel modello; lo stesso senza `system_prompt.txt` e un altro `qwen_image_2_1_pe_t2i` con file → si usa quello per nome (ripiego); `use "pluginsOnly"`/`"describe"` → non scelto dall'assegnazione; famiglia diversa → nessun effetto. I test esistenti restano verdi.
- [ ] **Step 2: Vedere il fallimento** — `cd Plugins/PromptMaster && swift test --filter PEPlannerTests`.
- [ ] **Step 3: Implementare.** **Step 4: Test verdi**, suite completa del plug-in.
- [ ] **Step 5: Commit** — `feat(promptmaster): il PE di Qwen Image 2.1 dall'assegnazione dell'LLM`.

---

### Task 9: Chiusura

- [ ] **Step 1: Suite** — `cd Packages && swift test`; `cd Plugins/PromptMaster && swift test`; `xcodebuild … build`.
- [ ] **Step 2: Prove a mano** (lista all'utente, non pilotare l'interfaccia): §12 della spec, **prima** la verifica di `generation_config.json` nelle cartelle dei PE.
- [ ] **Step 3: README** — in «LLM» (inglese): «Each installed LLM can be assigned to a model family and a use (enhance, generate, both, plug-ins only); a dedicated LLM's own `system_prompt.txt` is used when present.» Riga nel README di Prompt Master: «The Qwen Image 2.1 enhancer is the LLM assigned to that family in Settings › LLM (its folder name is only a fallback).» · commit `docs: README, LLM per famiglia`.
- [ ] **Step 4: Messaggio finale all'utente** (briefing §6): cosa provare; «Decisioni che ho preso» (riuso di `.noModelSelected`; risoluzione dei doppioni; `none·both` come default delle righe nuove; con costi); «Rinviati» (system prompt modificabili, più famiglie per LLM, Character Sheet); via libera prima di unire, push o release (con Prompt Master rifatto alla nuova versione).

---

## Autorevisione

- **Copertura della spec:** §3 → Task 1; §4 → Task 3; §5 → Task 2–3; §6 → Task 4–5; §7 → Task 6; §8 → Task 7–8; §9 → Task 3, 6; §10 → Task 1–8; §12 → Task 9.
- **Coerenza dei tipi:** `LanguageModelTask` (Task 1, HubKit) è usato da Router (2), Manager (3), Profile (4), Assistant (5); `LanguageModelManager.model(for:family:)` e `respond(...model:)` (Task 3) sono chiamati nel Task 5; `pluginFields` (Task 7) produce le stringhe lette nel Task 8.
- **Regola «un solo LLM»:** vale per un modello senza voce o su `none`; un'assegnazione a una famiglia non si tocca mai (spec §4.2).
