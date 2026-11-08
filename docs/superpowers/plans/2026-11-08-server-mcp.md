# Server MCP integrato in DT Hub — Piano di implementazione

> **Per chi esegue:** SUB-SKILL OBBLIGATORIA: usare superpowers:subagent-driven-development (consigliata) o superpowers:executing-plans per realizzare il piano task per task. I passi usano la sintassi a caselle (`- [ ]`).

**Obiettivo:** DT Hub espone un server MCP su loopback con cui un client (Claude, LM Studio…) legge lo stato dell'app, modifica la scheda Generazione e avvia generazioni, pipeline e code, dentro un budget deciso dall'utente.

**Architettura:** nuovo target `HubMCP` in `Packages/` (server HTTP, registro degli strumenti, sicurezza, budget, job) che conosce solo HubKit/HubCore e un protocollo `AgentHost`; l'App lo implementa (`App/Agent/`) sopra `GenerationController`, `QueueStore`/`QueueRunner`, `ContributionStore` e i risultati. Le modifiche ai campi passano da `ContributionStore` con origine «Agente remoto».

**Stack:** Swift 6.2 (macOS 26), `modelcontextprotocol/swift-sdk` 0.12.1 (`StatefulHTTPServerTransport`), swift-nio, Keychain, Swift Testing, SwiftUI.

**Spec:** `docs/superpowers/specs/2026-11-08-server-mcp-design.md`

## Vincoli globali

Valgono per ogni task (valori copiati dallo spec).

- Solo **127.0.0.1**, **spento di default**; token casuale nel Portachiavi, rigenerabile; controllo di `Host` **e** `Origin`; nessuna opzione per la rete locale.
- Modalità: *Sola lettura* · *Modifica la scheda* · *Controllo completo*. Gli strumenti fuori dalla modalità **non compaiono** in `tools/list`.
- **Nessuna conferma per azione.** Budget di sessione cumulativo (immagini e, con DT+, unità di calcolo); a budget esaurito la chiamata torna **subito** con errore, mai in attesa.
- Default proposti: soglia **20** immagini, budget **200** immagini per sessione, scadenza conferma **60 s**. La scadenza riguarda solo la risposta dell'utente: **non limita una generazione**.
- `run`, `queue_start`, `run_pipeline` tornano subito con `job_id`; `wait_for_job` attende **≤ 300 s** per chiamata e alla scadenza restituisce lo stato, non un errore. Un solo motore: `run` con job attivo → errore con il `job_id` in corso.
- `define_pipeline`: al massimo **20 passaggi**. Nessuno strumento cancella risultati, progetti o preset preesistenti; `queue_remove` solo voci create dall'agente nella sessione.
- `enhance_prompt` / `prompt_from_image` compaiono **solo** se il modello corrente ha un LLM specialista (assegnazione `.family(corrente)` o profilo PUP); un LLM «tutte le altre» (`*`) non basta.
- Il controllo di budget sta sul **percorso di Run con origine remota**, non sul nome dello strumento.
- Percorsi file solo in cartelle consentite (progetto, output, Risultati, aggiunte dall'utente); `result_id` sempre ammessi.
- Nessun entitlement nuovo (l'app non è in sandbox). Codice preso da `DT_MCP_Client` (MIT) → attribuzione in `NOTICE`; non si dipende da quel progetto.
- Ogni testo visibile in italiano e inglese in `App/Localizable.xcstrings` (`CatalogTests`).
- Nessuna pubblicazione senza via libera esplicito dell'utente.

## Review Focus

Casi che lo spec lascia impliciti e che un utente incontrerà; ciascuno ha il test nel task indicato.

1. **Due richieste di Run quasi simultanee** non devono passare entrambe il controllo del budget (Task 5).
2. **Porta occupata** all'accensione: errore chiaro nel pannello, l'app non si blocca né chiude (Task 8, 12).
3. **`set_model` o `run` mentre un job è in corso** (anche avviato a mano con RUN): errore con il `job_id`, nessuno stato a metà (Task 10).
4. **`result_id` sconosciuto/scaduto e percorsi fuori dalle cartelle** (inclusi `..` e collegamenti simbolici): errore chiaro, nessuna lettura (Task 9).
5. **Disconnessione del client a metà job**: il job finisce, non ne parte un altro, il budget non si azzera finché l'utente non lo chiede o la sessione non termina (Task 6, 10).

## Mappa dei file

Crea:
- `Packages/Sources/HubMCP/AgentHost.swift` — protocollo e tipi valore tra server e app.
- `.../AccessMode.swift`, `RemoteControlSettings.swift` — modalità e impostazioni persistite.
- `.../Security/TokenStore.swift`, `RequestGuard.swift` — token (Keychain) e controllo di richiesta.
- `.../Policy/BudgetLedger.swift`, `ConsentGate.swift` — budget e conferma sopra soglia.
- `.../Jobs/JobTracker.swift` — stati dei job, `wait_for_job`.
- `.../Tools/ToolRegistry.swift`, `ReadTools.swift`, `EditTools.swift`, `ControlTools.swift`, `ResultCatalog.swift`, `PathPolicy.swift`.
- `.../Server/MCPHTTPServer.swift`, `AgentInstructions.swift`.
- `Packages/Tests/HubMCPTests/…` — un file di test per unità.
- `App/Agent/AppAgentHost.swift`, `RemoteControlModel.swift`, `RemoteControlPreferencesView.swift`, `RemoteControlIndicator.swift`.
- `NOTICE` (radice del repository).

Modifica: `Packages/Package.swift`, `DTHub.xcodeproj/project.pbxproj` (prodotto HubMCP nel target), `App/DTHubApp.swift`, `App/Preferences/PreferencesView.swift`, `App/Generation/GenerationController.swift` (punto di Run remoto), `App/Localizable.xcstrings`, `README.md`.

Traguardi rilasciabili (spec §10): **M1** = Task 1–8 + 11 (parte lettura) + 12; **M2** = Task 9; **M3** = Task 10; **M4** = Task 13. Si lavora su un ramo `feature/server-mcp`.

---

### Task 1: Target HubMCP e dipendenze

**Files:**
- Modify: `Packages/Package.swift`
- Create: `Packages/Sources/HubMCP/HubMCP.swift`, `Packages/Tests/HubMCPTests/SmokeTests.swift`, `NOTICE`

**Interfaces:**
- Produces: modulo `HubMCP` importabile; prodotto `.library(name: "HubMCP", …)`.

- [ ] **Step 1: Leggere come il SDK 0.12.1 usa `StatefulHTTPServerTransport`** (esempio/test nel suo repository, tag 0.12.1) e annotare in un commento di `HubMCP.swift` firma di `handleRequest`, tipi di richiesta/risposta e gestione delle sessioni. Il Task 8 dipende da queste firme.
- [ ] **Step 2: Test che fallisce** — `SmokeTests`: `@Test func moduleNameIsHubMCP()` con `#expect(HubMCP.moduleName == "HubMCP")`.
- [ ] **Step 3: Eseguire** `cd Packages && swift test --filter HubMCPTests` — atteso: errore di compilazione (target mancante).
- [ ] **Step 4: Aggiungere** dipendenze `swift-sdk` `.upToNextMinor(from: "0.12.1")` e `swift-nio`, target `HubMCP` (dipende da `HubKit`, `HubCore`, `MCP`, NIO), `testTarget(name: "HubMCPTests", dependencies: ["HubMCP","HubCore","HubKit"])`; `enum HubMCP { static let moduleName = "HubMCP" }`; `NOTICE` con attribuzione MIT a `DT_MCP_Client`.
- [ ] **Step 5: Eseguire** lo stesso comando — atteso: PASS.
- [ ] **Step 6: Commit** `feat(mcp): target HubMCP e dipendenze`.

---

### Task 2: AgentHost e tipi valore

**Files:**
- Create: `Packages/Sources/HubMCP/AgentHost.swift`, `AccessMode.swift`, `RemoteControlSettings.swift`
- Test: `Packages/Tests/HubMCPTests/SettingsTests.swift`

**Interfaces:**
- Produces:
  - `public enum AccessMode: String, Codable, Sendable, Comparable { case readOnly, editFields, full }` (ordine in quest'ordine).
  - `public struct RemoteControlSettings: Codable, Equatable, Sendable { var enabled = false; var port: UInt16 = 8765; var mode: AccessMode = .readOnly; var confirmThreshold = 20; var imageBudget = 200; var cuBudget: Int? = nil; var confirmTimeoutSeconds = 60; var allowedFolders: [String] = [] }` con decodifica tollerante (campo mancante → default) come `LanguageModelSettings`, e `clamped()` (soglia ≥ 1, budget ≥ 1, scadenza 5…600).
  - `public struct RemoteControlSettingsStore { init(defaults: UserDefaults = .standard); func load() -> RemoteControlSettings; func save(_:) }`.
  - `@MainActor public protocol AgentHost: AnyObject` con i membri indicati sotto; tipi valore `AgentState`, `AgentModel(file,name,family,kind)`, `AgentLoRA(file,name,families)`, `AgentResult(id,path,prompt,model,date)`, `AgentRunPlan(images:Int, estimatedCU:Int?)`, `AgentError` (`.busy(jobID:String?)`, `.invalid(String)`, `.unavailable(String)`).
  - Membri di `AgentHost` — lettura: `state() -> AgentState`, `models() -> [AgentModel]`, `loras() -> [AgentLoRA]`, `presetNames() -> [String]`, `pipelineNames() -> [String]`, `promptGuide(family: String) -> String?`, `currentFamily: String? { get }`, `hasSpecialistLLM: Bool { get }`, `results() -> [AgentResult]`, `resultImage(id: String, maxSide: Int) -> Data?`, `queueEntries() -> [AgentQueueEntry]`. Modifica: `setFields(_ f: [String: AgentValue]) throws(AgentError) -> [String]`, `addLoRA(file: String, weight: Double) throws(AgentError)`, `setLoRAWeight(file:weight:)`, `removeLoRA(file:)`, `setMoodboard(_ items: [AgentImage], replace: Bool) async throws(AgentError)`, `setStartImage(_ image: AgentImage) async throws(AgentError)`, `setStrength(_ v: Double)`, `loadPreset(named:) -> String?`, `savePreset(named:) throws(AgentError)`. Controllo: `setModel(file: String) throws(AgentError)`, `planRun() -> AgentRunPlan`, `startRun() throws(AgentError)`, `stop()`, `runPipeline(named:) throws(AgentError) -> AgentRunPlan`, `definePipeline(steps: [AgentPipelineStep]) throws(AgentError)`, `queueAdd() throws(AgentError) -> UUID`, `queueStart() throws(AgentError) -> AgentRunPlan`, `queueStop()`, `queueRemove(id: UUID) throws(AgentError)`, `enhancePrompt() async throws(AgentError) -> String`, `promptFromImage() async throws(AgentError) -> String`. Avanzamento: `var onJobEvent: ((AgentJobEvent) -> Void)? { get set }` con `AgentJobEvent` = `.started(images:Int)`, `.progress(done:Int,total:Int,pass:(Int,Int)?)`, `.finished(resultIDs:[String])`, `.failed(String)`, `.stopped`.
  - `AgentValue` = enum `string/int/double/bool` Codable; `AgentImage` = enum `result(id:String)` / `path(String)` con `weight: Double?`.

- [ ] **Step 1: Test che fallisce** — `SettingsTests`: `defaultsAreOffAndReadOnly` (`enabled == false`, `mode == .readOnly`, soglia 20, budget 200, scadenza 60); `missingFieldsTakeDefaults` (JSON `{"enabled":true}` → resto default); `clampedKeepsRanges` (soglia 0 → 1, scadenza 9999 → 600); `accessModeOrdering` (`.readOnly < .editFields < .full`); `storeRoundTrips` con `UserDefaults(suiteName:)` usa e getta.
- [ ] **Step 2: Eseguire** `swift test --filter SettingsTests` — atteso: FAIL (tipi non definiti).
- [ ] **Step 3: Implementare** i tipi nei file indicati; `AgentHost` solo dichiarazioni.
- [ ] **Step 4: Eseguire** lo stesso comando — atteso: PASS.
- [ ] **Step 5: Commit** `feat(mcp): AgentHost, modalità e impostazioni`.

---

### Task 3: Token e controllo delle richieste

**Files:**
- Create: `Packages/Sources/HubMCP/Security/TokenStore.swift`, `RequestGuard.swift`
- Test: `Packages/Tests/HubMCPTests/RequestGuardTests.swift`, `TokenStoreTests.swift`

**Interfaces:**
- Produces:
  - `public protocol SecretStorage: Sendable { func read(_ key: String) -> String?; func write(_ key: String, _ value: String) }`; `KeychainSecretStorage` (Security.framework, servizio `ai.dthub.mcp`); `InMemorySecretStorage` per i test.
  - `public struct TokenStore { init(storage: any SecretStorage); func token() -> String` (lo genera 32 byte casuali in base64url alla prima lettura); `func regenerate() -> String` }`.
  - `public struct RequestGuard { init(token: String, port: UInt16); func check(authorization: String?, host: String?, origin: String?) -> GuardDecision }`; `enum GuardDecision: Equatable { case allow, unauthorized, forbiddenHost, forbiddenOrigin }`.

- [ ] **Step 1: Test che falliscono** — `RequestGuardTests`: `acceptsBearerTokenWithLoopbackHost` (host `127.0.0.1:8765`, `localhost:8765`, `[::1]:8765`); `rejectsMissingOrWrongToken` → `.unauthorized` (anche con spazi o maiuscole diverse nello schema `Bearer`: la comparazione del token è esatta); `rejectsForeignHost` (`evil.com`, `127.0.0.1.evil.com`) → `.forbiddenHost`; `rejectsAnyBrowserOrigin` (`https://example.com`, `null`) → `.forbiddenOrigin`; `allowsMissingOrigin` (i client non-browser non lo mandano). `TokenStoreTests`: `tokenIsStableUntilRegenerated`, `regenerateChangesToken`, `tokenHasAtLeast43Characters`.
- [ ] **Step 2: Eseguire** `swift test --filter "RequestGuardTests|TokenStoreTests"` — atteso: FAIL.
- [ ] **Step 3: Implementare**; confronto del token a tempo costante; si adatta il controllo di Host di `MCPHTTPServer.swift` di DT_MCP_Client (lista `127.0.0.1`, `localhost`, `[::1]`) aggiungendo l'Origin.
- [ ] **Step 4: Eseguire** — atteso: PASS.
- [ ] **Step 5: Commit** `feat(mcp): token nel Portachiavi e controllo di Host/Origin`.

---

### Task 4: Percorsi consentiti

**Files:**
- Create: `Packages/Sources/HubMCP/Tools/PathPolicy.swift`
- Test: `Packages/Tests/HubMCPTests/PathPolicyTests.swift`

**Interfaces:**
- Produces: `public struct PathPolicy { init(roots: [URL]); func resolve(_ path: String) -> URL? }` — restituisce l'URL canonico (`resolvingSymlinksInPath`, `standardized`) solo se dentro una radice e se è un'immagine (estensione png/jpg/jpeg/webp/heic).

- [ ] **Step 1: Test che falliscono** (cartella temporanea): `insideRootIsResolved`; `dotDotEscapeIsRefused` (`root/../outside.png`); `symlinkToOutsideIsRefused`; `nonImageExtensionIsRefused` (`.txt`); `relativePathIsRefused`; `rootPrefixTrickIsRefused` (`/tmp/root-evil/x.png` con radice `/tmp/root`).
- [ ] **Step 2: Eseguire** `swift test --filter PathPolicyTests` — atteso: FAIL.
- [ ] **Step 3: Implementare** confrontando componenti di percorso, non prefissi di stringa.
- [ ] **Step 4: Eseguire** — atteso: PASS.
- [ ] **Step 5: Commit** `feat(mcp): cartelle consentite per i file`.

---

### Task 5: Budget e conferma sopra soglia

**Files:**
- Create: `Packages/Sources/HubMCP/Policy/BudgetLedger.swift`, `ConsentGate.swift`
- Test: `Packages/Tests/HubMCPTests/BudgetLedgerTests.swift`, `ConsentGateTests.swift`

**Interfaces:**
- Consumes: `RemoteControlSettings` (Task 2).
- Produces:
  - `@MainActor public final class BudgetLedger { init(settings: @escaping @MainActor () -> RemoteControlSettings); var usedImages: Int { get }; var usedCU: Int { get }; var isConfirmed: Bool { get }; func confirm(); func reserve(images: Int, cu: Int?) -> BudgetResult; func refund(images: Int, cu: Int?); func reset() }`; `enum BudgetResult: Equatable { case granted; case exhausted(used: Int, limit: Int, unit: BudgetUnit) }`; `enum BudgetUnit { case images, computeUnits }`. `reserve` è sincrono su MainActor: due chiamate di seguito vedono il conteggio aggiornato.
  - `public protocol ConsentPrompter: AnyObject { @MainActor func ask(_ summary: String, timeoutSeconds: Int) async -> Bool }` (false = rifiuto **o** scadenza).
  - `@MainActor public final class ConsentGate { init(ledger: BudgetLedger, settings: …, prompter: any ConsentPrompter); func authorize(_ plan: AgentRunPlan, summary: String) async -> AuthorizeResult }`; `enum AuthorizeResult: Equatable { case allowed; case denied(String) }`.
- **Regola decisa nel piano** (lo spec la lascia ambigua): il tetto di budget (200) vale sempre. La soglia chiede conferma solo se `plan.images > confirmThreshold` **e** il budget non è ancora stato confermato dall'utente per la sessione (`ledger.isConfirmed == false`); `confirm()` si chiama dal pannello («Autorizza questa sessione») o modificando il budget. Così «una coda da 80» chiede la prima volta e, una volta autorizzata la sessione, non blocca più.

- [ ] **Step 1: Test che falliscono** — `BudgetLedgerTests`: `reserveWithinLimitIsGranted`; `reserveBeyondLimitIsExhaustedWithoutChangingUsed`; `twoConsecutiveReservesCannotBothPassTheLastSlots` (budget 10, due richieste da 6 → la seconda `.exhausted`); `refundGivesImagesBack`; `resetClearsUsageAndConfirmation`; `cuBudgetAppliesOnlyWhenSet`. `ConsentGateTests` (con `FakePrompter`): `belowThresholdNeverAsks`; `aboveThresholdUnconfirmedAsksAndAllowsOnYes`; `aboveThresholdConfirmedBudgetDoesNotAsk`; `noAnswerWithinTimeoutIsDenied` (il fake non risponde, scadenza 1 s con orologio iniettato o `timeoutSeconds: 0`) → `.denied` con testo che nomina la scadenza; `exhaustedBudgetIsDeniedWithoutAsking` con testo «budget esaurito: 200 su 200».
- [ ] **Step 2: Eseguire** `swift test --filter "BudgetLedgerTests|ConsentGateTests"` — atteso: FAIL.
- [ ] **Step 3: Implementare**; l'attesa con scadenza con `withThrowingTaskGroup` (prompt vs `Task.sleep`), annullando l'altro ramo.
- [ ] **Step 4: Eseguire** — atteso: PASS.
- [ ] **Step 5: Commit** `feat(mcp): budget di sessione e conferma sopra soglia`.

---

### Task 6: Tracciatore dei job

**Files:**
- Create: `Packages/Sources/HubMCP/Jobs/JobTracker.swift`
- Test: `Packages/Tests/HubMCPTests/JobTrackerTests.swift`

**Interfaces:**
- Consumes: `AgentJobEvent` (Task 2).
- Produces: `@MainActor public final class JobTracker { init(); var activeJobID: String? { get }; func begin(kind: JobKind, images: Int) throws(AgentError) -> String; func apply(_ event: AgentJobEvent); func status(_ id: String) -> JobStatus?; func wait(_ id: String, timeoutSeconds: Int) async -> JobStatus?; func clientDisconnected(); var acceptsNewJobs: Bool { get } }`; `enum JobKind { case run, queue, pipeline }`; `struct JobStatus: Equatable { id, kind, state: JobState, done: Int, total: Int, pass: (Int,Int)?, resultIDs: [String], error: String? }`; `enum JobState { case running, finished, failed, stopped }`.
- `begin` con un job attivo → `.busy(jobID:)`. `wait` restituisce lo stato corrente alla scadenza (cap 300 s). Dopo `clientDisconnected()` il job attivo finisce ma `acceptsNewJobs == false` fino a una nuova connessione.

- [ ] **Step 1: Test che falliscono** — `beginWhileActiveThrowsBusyWithCurrentID`; `progressEventsUpdateDoneAndTotal`; `finishedEventStoresResultIDs`; `waitReturnsAsSoonAsJobFinishes`; `waitReturnsRunningStateAtTimeoutNotAnError` (timeout 0); `waitCapsAt300Seconds` (richiesta 9999 → cap, verificato su una proprietà `effectiveTimeout(for:)`); `disconnectLetsRunningJobFinishButBlocksNewOnes` (**Review Focus 5**); `unknownJobIsNil`.
- [ ] **Step 2: Eseguire** `swift test --filter JobTrackerTests` — atteso: FAIL.
- [ ] **Step 3: Implementare** `wait` con continuazioni svegliate da `apply` e da un `Task.sleep` di timeout.
- [ ] **Step 4: Eseguire** — atteso: PASS.
- [ ] **Step 5: Commit** `feat(mcp): tracciatore dei job con wait_for_job`.

---

### Task 7: Registro degli strumenti e strumenti di lettura

**Files:**
- Create: `Packages/Sources/HubMCP/Tools/ToolRegistry.swift`, `ReadTools.swift`
- Test: `Packages/Tests/HubMCPTests/ToolRegistryTests.swift`, `ReadToolsTests.swift`, `FakeAgentHost.swift` (supporto di test)

**Interfaces:**
- Consumes: `AgentHost`, `AccessMode`, `JobTracker`, `BudgetLedger`.
- Produces:
  - `public enum ToolLevel { case read, edit, control }`; `public struct ToolSpec { name: String; description: String; inputSchema: Value; level: ToolLevel; readOnly: Bool; destructive: Bool; handler: @MainActor (Value) async throws -> ToolOutput }`; `ToolOutput` = testo e/o immagini (`.text(String)`, `.image(Data, mime)`).
  - `@MainActor public final class ToolRegistry { init(host: any AgentHost, settings: @escaping @MainActor () -> RemoteControlSettings, jobs: JobTracker, ledger: BudgetLedger, gate: ConsentGate, paths: @escaping @MainActor () -> PathPolicy); func visibleTools() -> [ToolSpec]; func call(_ name: String, arguments: Value) async -> ToolResult; var onListChanged: (() -> Void)? { get set }; func hostDidChange() }` — `visibleTools()` filtra per modalità e, per `enhance_prompt`/`prompt_from_image`, per `host.hasSpecialistLLM`; una chiamata a uno strumento non visibile restituisce errore «non disponibile in questa modalità» (non «sconosciuto»).
  - Strumenti di lettura (nomi dello spec §4): `get_app_state`, `list_models`, `list_loras`, `list_presets`, `list_pipelines`, `get_prompt_guide`, `list_results`, `get_results`, `get_image`, `get_queue`, `get_job`, `wait_for_job`, `list_plugins` (solo elenco informativo).
  - `FakeAgentHost` in `Tests/HubMCPTests` registra le chiamate e restituisce dati fissi.

- [ ] **Step 1: Test che falliscono** — `ToolRegistryTests`: `readOnlyModeListsOnlyReadTools`; `editModeAddsEditTools`; `fullModeAddsControlTools`; `callingHiddenToolSaysNotAvailableInThisMode`; `specialistToolsHiddenWhenHostHasNoSpecialist`; `specialistToolsShownWhenHostHasSpecialist`; `hostDidChangeFiresListChangedWhenSpecialistAvailabilityChanges`; `everyToolHasAnnotationsMatchingItsLevel` (read → `readOnly == true`). `ReadToolsTests`: `getAppStateIncludesModeBudgetAndActiveJob`; `getPromptGuideForUnknownFamilyIsClearError`; `getImageReturnsImageContentAndRespectsMaxSide`; `getImageUnknownResultIDIsClearError` (**Review Focus 4**); `waitForJobReturnsStatusNotErrorAtTimeout`.
- [ ] **Step 2: Eseguire** `swift test --filter "ToolRegistryTests|ReadToolsTests"` — atteso: FAIL.
- [ ] **Step 3: Implementare** il registro (tabella di `ToolSpec`) e i gestori di lettura; gli schemi JSON degli argomenti sono dichiarati accanto a ogni strumento.
- [ ] **Step 4: Eseguire** — atteso: PASS.
- [ ] **Step 5: Commit** `feat(mcp): registro degli strumenti e lettura`.

---

### Task 8: Server HTTP e integrazione con un client

**Files:**
- Create: `Packages/Sources/HubMCP/Server/MCPHTTPServer.swift`, `AgentInstructions.swift`
- Test: `Packages/Tests/HubMCPTests/ServerIntegrationTests.swift`

**Interfaces:**
- Consumes: `ToolRegistry`, `RequestGuard`, `TokenStore`, annotazioni dal Task 1 (firme del SDK).
- Produces: `@MainActor public final class MCPHTTPServer { init(registry: ToolRegistry, tokens: TokenStore, instructions: String); func start(port: UInt16) async throws(MCPServerError); func stop() async; var isRunning: Bool { get }; var onClientCountChanged: ((Int) -> Void)? { get set } }`; `enum MCPServerError: Error { case portInUse(UInt16); case failed(String) }`. `AgentInstructions.text: String` — testo breve delle `instructions` (Task 13 lo estende, qui un testo base di 5 righe).
- Ascolto solo su `127.0.0.1`. Un `Server` MCP per sessione, tutti sullo stesso registro; `tools/list` e `tools/call` leggono il registro; `onListChanged` → notifica `tools/list_changed` alle sessioni aperte. Adattare `MCPHTTPServer.swift` di DT_MCP_Client (bind loopback, Bearer, sessioni) usando `RequestGuard`.

- [ ] **Step 1: Test che falliscono** (porta effimera, `FakeAgentHost`): `rejectsRequestWithoutToken` (401); `rejectsForeignOrigin` (403); `clientListsOnlyReadToolsInReadOnlyMode`; `clientCallsGetAppState`; `clientSeesInstructions`; `portInUseThrowsPortInUse` (**Review Focus 2**: si occupa la porta con un socket di prova); `stopClosesTheListener`; `listChangedIsDeliveredWhenModeChanges`. Il client è `MCP.Client` del SDK su `HTTPClientTransport`.
- [ ] **Step 2: Eseguire** `swift test --filter ServerIntegrationTests` — atteso: FAIL.
- [ ] **Step 3: Implementare** il server; l'avvio con porta occupata deve restituire l'errore tipizzato, non crashare.
- [ ] **Step 4: Eseguire** — atteso: PASS.
- [ ] **Step 5: Commit** `feat(mcp): server HTTP loopback con sessioni`.

---

### Task 9: Strumenti di modifica e risultati (M2)

**Files:**
- Create: `Packages/Sources/HubMCP/Tools/EditTools.swift`, `ResultCatalog.swift`
- Test: `Packages/Tests/HubMCPTests/EditToolsTests.swift`

**Interfaces:**
- Consumes: `PathPolicy` (Task 4), `AgentHost`.
- Produces: strumenti `set_fields`, `add_lora`, `set_lora_weight`, `remove_lora`, `set_moodboard`, `set_start_image`, `set_strength`, `load_preset`, `save_preset` (livello `.edit`, `destructive == false`). `ResultCatalog` (`@MainActor`): `func resolve(_ image: AgentImage) throws(AgentError) -> AgentImage` — `result(id:)` valido nella sessione, oppure `path` passato da `PathPolicy`; altrimenti `.invalid`.
- `set_fields` accetta le chiavi: `prompt, negativePrompt, width, height, steps, guidanceScale, shift, resolutionDependentShift, cfgZeroStar, cfgZeroInitSteps, seed, randomSeed, sampler, batchSize, batchCount` (stesse di `ActionBlock.fieldKeys` del plug-in AI Assistant); chiave sconosciuta → errore che elenca quelle valide. `set_moodboard` dichiara nella risposta se ha sostituito immagini già presenti.

- [ ] **Step 1: Test che falliscono** — `setFieldsForwardsKnownKeysAndReportsApplied`; `setFieldsRejectsUnknownKeyListingValidOnes`; `setFieldsRejectsWrongTypeForKey` (`steps: "dieci"`); `setMoodboardResolvesResultIDsAndSaysWhenItReplaced`; `setMoodboardWithUnknownResultIDIsClearError`; `setMoodboardWithPathOutsideRootsIsRefused`; `addLoRAWithUnknownFileIsClearError`; `setStrengthOutOfRangeIsRejected` (valido 0…1); `editToolsAreHiddenInReadOnlyMode`.
- [ ] **Step 2: Eseguire** `swift test --filter EditToolsTests` — atteso: FAIL.
- [ ] **Step 3: Implementare** i gestori e `ResultCatalog` (id = identificativo stabile fornito da `AgentResult.id`).
- [ ] **Step 4: Eseguire** — atteso: PASS.
- [ ] **Step 5: Commit** `feat(mcp): strumenti di modifica della scheda`.

---

### Task 10: Strumenti di controllo: modello, run, pipeline, coda (M3)

**Files:**
- Create: `Packages/Sources/HubMCP/Tools/ControlTools.swift`
- Test: `Packages/Tests/HubMCPTests/ControlToolsTests.swift`

**Interfaces:**
- Consumes: `ConsentGate`, `BudgetLedger`, `JobTracker`, `AgentHost`.
- Produces: strumenti `set_model`, `run`, `stop`, `run_pipeline`, `define_pipeline`, `queue_add`, `queue_start`, `queue_stop`, `queue_remove`, e (visibili solo con specialista) `enhance_prompt`, `prompt_from_image` (livello `.control`).
- Flusso comune di `run`/`run_pipeline`/`queue_start`: (1) `jobs.acceptsNewJobs` e nessun job attivo, altrimenti `.busy`; (2) `plan = host.planRun()` (o quello della pipeline/coda); (3) `gate.authorize(plan, summary:)`; se `.denied` → errore; (4) `ledger.reserve`; se esaurito → errore immediato; (5) `jobs.begin`; (6) `host.startRun()` — se fallisce, `ledger.refund` e job chiuso `failed`; (7) risposta `{job_id, images}`. Gli eventi `host.onJobEvent` alimentano `JobTracker`. `define_pipeline` rifiuta > 20 passaggi. `queue_remove` accetta solo id aggiunti dall'agente nella sessione.

- [ ] **Step 1: Test che falliscono** — `runStartsJobAndReturnsJobIDImmediately`; `runWhileJobActiveReturnsBusyWithJobID` (**Review Focus 3**); `runWhileUserStartedRunByHandReturnsBusy` (host che fallisce con `.busy(jobID: nil)`); `setModelWhileJobActiveIsRefused`; `runBeyondBudgetFailsImmediatelyWithUsedAndLimit`; `runAboveThresholdWithUnconfirmedBudgetAsksOnce`; `runRefundsBudgetWhenHostFailsToStart`; `definePipelineRejects21Steps` e accetta 20; `queueRemoveRefusesEntriesNotAddedByAgent`; `twoConcurrentRunCallsOnlyOneStarts` (**Review Focus 1**: due `call("run")` in un `async let`); `stopCallsHostAndMarksJobStopped`.
- [ ] **Step 2: Eseguire** `swift test --filter ControlToolsTests` — atteso: FAIL.
- [ ] **Step 3: Implementare** secondo il flusso sopra.
- [ ] **Step 4: Eseguire** — atteso: PASS.
- [ ] **Step 5: Commit** `feat(mcp): modello, run, pipeline e coda con budget`.

---

### Task 11: Adattatore dell'app (AppAgentHost)

**Files:**
- Create: `App/Agent/AppAgentHost.swift`
- Modify: `App/Generation/GenerationController.swift` (punto di Run remoto), `DTHub.xcodeproj/project.pbxproj` (prodotto `HubMCP` nel target `DTHub`)
- Test: `Packages/Tests/HubCoreTests` solo per ciò che sta in HubCore; l'adattatore si prova con la verifica a mano del Task 14 e `xcodebuild`.

**Interfaces:**
- Consumes: `AgentHost` (Task 2); `GenerationController` (`prompt`, `negativePrompt`, `parameters`, `session.results`, `session.phase`, `session.isRunning`, `canRun(with:)`, `run(with:) -> Bool`, `stop()`, `chooseModel(_:in:)`, `selectPipeline(named:)`, `loadPreset(named:with:)`, `savePreset(named:with:)`, `addLoRA`, `removeLoRA`, `setStrength`, `control`), `ContributionStore.receive(_:from:)`, `QueueStore`/`QueueRunner`, `LanguageModelManager.model(for:family:)`.
- Produces: `@MainActor final class AppAgentHost: AgentHost { init(generation: GenerationController, connection: DrawThingsConnection, queueStore: QueueStore, queueRunner: QueueRunner, languageModel: LanguageModelManager) }`.
- Decisioni di integrazione:
  - **Origine «Agente remoto»**: le modifiche ai campi usano `contributions.receive(_, from: "dthub.remote-agent")` così i campi diventano verde acqua con il valore precedente. Verificare la forma di `PluginContribution` in `ContributionStore.swift:132` e che il nome mostrato nel tooltip sia «Agente remoto» (stringa localizzata, non l'id).
  - **Run remoto**: `startRun()` chiama `generation.run(with:)`; l'avanzamento si ricava da `session.phase` e da `pipelinePass`/`isPipelineRunning` con osservazione (`withObservationTracking` o il meccanismo già usato dal `QueueRunner`); la fine si segnala con `session.waitUntilFinished()`.
  - **`hasSpecialistLLM`**: `true` solo se `languageModel.model(for: .enhance, family: currentFamily)` risolve a un modello la cui assegnazione è `.family(chiave)` per la famiglia corrente o il cui `LanguageModelProfile` è PUP; `*` → `false`.
  - **`planRun()`**: immagini = `parameters.batchCount × parameters.batchSize` (per pipeline: somma dei passaggi; per coda: somma delle voci in attesa; per guidata: passaggi stimati), CU da `cuPasses(in:)` quando DT+ è attivo.
  - La coda e la pipeline temporanea usano `QueueStore.add`/`UserPipeline` esistenti; nessuna cancellazione di dati preesistenti.

- [ ] **Step 1: Aggiungere** `HubMCP` come dipendenza del target `DTHub` nel progetto Xcode (prodotto della libreria locale `Packages`).
- [ ] **Step 2: Implementare** `AppAgentHost` per la parte di **lettura** (stato, modelli, LoRA, preset, pipeline, risultati, `resultImage`, coda) — M1.
- [ ] **Step 3: Eseguire** `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"` — atteso: `BUILD SUCCEEDED`.
- [ ] **Step 4: Commit** `feat(mcp): AppAgentHost in sola lettura` (traguardo M1).
- [ ] **Step 5: Implementare** modifica (campi, LoRA, Moodboard, start image, strength, preset) — M2; **build** come sopra; commit `feat(mcp): AppAgentHost modifica`.
- [ ] **Step 6: Implementare** controllo (`setModel`, `startRun`, `stop`, pipeline, coda, specialisti, eventi di job) — M3; **build** come sopra; commit `feat(mcp): AppAgentHost controllo`.

---

### Task 12: Pannello «Controllo remoto», indicatore e arresto

**Files:**
- Create: `App/Agent/RemoteControlModel.swift`, `RemoteControlPreferencesView.swift`, `RemoteControlIndicator.swift`
- Modify: `App/Preferences/PreferencesView.swift` (nuova `Tab("prefs.tab.remote", systemImage: "network")`), `App/DTHubApp.swift` (creazione e collegamento), `App/MainWindow/…` (indicatore nella barra), `App/Localizable.xcstrings`
- Test: `Packages/Tests/CatalogTests` (stringhe it/en)

**Interfaces:**
- Consumes: `RemoteControlSettingsStore`, `TokenStore`, `MCPHTTPServer`, `BudgetLedger`, `JobTracker`, `ConsentPrompter`.
- Produces: `@MainActor @Observable final class RemoteControlModel` — `settings`, `isRunning`, `lastError: String?`, `connectedClients: Int`, `callLog: [CallLogEntry]` (ultime 200), `func setEnabled(_:)`, `func regenerateToken()`, `func authorizeSession()` (= `ledger.confirm()`), `func resetSession()`, `func killSwitch()` (disconnette i client, `stop()`, ferma la coda, `jobs.clientDisconnected()`), e conforma a `ConsentPrompter` mostrando un riquadro con **Consenti / Rifiuta** e la dicitura «avviare 12 immagini con FLUX.2 klein».
- Pannello: interruttore (spento di default), porta, modalità, soglia, budget immagini e CU, scadenza conferma, cartelle consentite, token con «Copia» e «Rigenera», snippet di configurazione da copiare per il client, «Autorizza questa sessione», «Nuova sessione», registro delle chiamate. Indicatore nella barra in alto con client collegati e pulsante di arresto. Errore di porta occupata mostrato nel pannello (`lastError`).

- [ ] **Step 1: Test che falliscono** — in `CatalogTests` le nuove chiavi `prefs.tab.remote`, `remote.*` esistono in `en` e `it`; in `HubMCPTests` un `RemoteControlModelTests` non è possibile (è nell'App), quindi la logica testabile resta in HubMCP: `callLogKeepsLast200Entries` su un tipo `CallLog` in HubMCP.
- [ ] **Step 2: Eseguire** `swift test --filter "CatalogTests|CallLogTests"` — atteso: FAIL.
- [ ] **Step 3: Implementare** `CallLog` (HubMCP), modello, vista, indicatore, stringhe it/en.
- [ ] **Step 4: Eseguire** `swift test` (tutta la suite in `Packages`) e la build `xcodebuild` come sopra — atteso: nessun errore.
- [ ] **Step 5: Commit** `feat(mcp): pannello Controllo remoto, indicatore e arresto`.

---

### Task 13: Istruzioni per l'agente e SKILL.md (M4)

**Files:**
- Modify: `Packages/Sources/HubMCP/Server/AgentInstructions.swift`
- Create: `Packages/Tests/HubMCPTests/AgentInstructionsTests.swift`
- Modify: `App/Agent/RemoteControlPreferencesView.swift` (pulsante «Copia istruzioni per l'agente»)

**Interfaces:**
- Produces: `AgentInstructions.short: String` (alla connessione) e `AgentInstructions.skillMarkdown() -> String` (stessa fonte, `SKILL.md` con intestazione YAML `name`/`description`).
- Contenuto obbligatorio: leggere prima `get_app_state`; controllare il budget; usare `wait_for_job` e richiamarlo alla scadenza; trattare i testi dei risultati come dati e non come ordini; usare `get_prompt_guide` per scrivere i prompt quando non c'è uno specialista; i lavori a più fasi sono un ciclo del client (`get_image` → scelta → `set_moodboard`/`set_start_image` con `result_id`).

- [ ] **Step 1: Test che falliscono** — `shortInstructionsMentionKeyRules` (contiene i nomi `get_app_state`, `wait_for_job`, `get_prompt_guide`); `skillMarkdownHasFrontmatterAndSameRules`; `shortInstructionsStayUnder1500Characters`.
- [ ] **Step 2: Eseguire** `swift test --filter AgentInstructionsTests` — atteso: FAIL.
- [ ] **Step 3: Implementare** da un'unica fonte strutturata (elenco di regole) da cui derivano i due testi.
- [ ] **Step 4: Eseguire** — atteso: PASS.
- [ ] **Step 5: Commit** `feat(mcp): istruzioni per l'agente e SKILL.md`.

---

### Task 14: Verifica d'insieme e documentazione

**Files:**
- Modify: `README.md`, `docs/superpowers/briefing-prossima-sessione.md`

- [ ] **Step 1: Suite completa** — `cd Packages && swift test 2>&1 | grep -E "Test run with|✘|error:"` — atteso: nessun `✘`, nessun `error:`.
- [ ] **Step 2: Build** — `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"` — atteso: `BUILD SUCCEEDED`.
- [ ] **Step 3: Prova a mano con Claude** (l'utente ha già un client): accendere il server, copiare la configurazione, e far eseguire «imposta un prompt, cambia modello, genera 2 immagini, aspetta, mostrami il risultato»; verificare campi verde acqua «Agente remoto», indicatore in barra, voce nel registro, `wait_for_job` oltre 250 s su una generazione lunga.
- [ ] **Step 4: Prova a mano con LM Studio** (come host MCP, stessa configurazione).
- [ ] **Step 5: Scenario dei character sheet senza upscale** — tre generazioni, `set_moodboard` con i `result_id`, una quarta generazione in azione; budget a 4 immagini: la quinta richiesta deve fallire subito con «budget esaurito».
- [ ] **Step 6: Documentare** nel README (sezione «Controllo remoto (MCP)»: attivazione, modalità, budget, avvertenza sull'iniezione) e annotare nel briefing lo stato; **non** pubblicare: la pubblicazione richiede il via libera esplicito dell'utente e i passi di `CLAUDE.md`.
- [ ] **Step 7: Commit** `docs(mcp): README e briefing`.

---

## Autorevisione

- **Copertura dello spec:** §3 architettura → Task 1, 2, 8, 11; §4 strumenti → Task 7, 9, 10; §5 specialisti → Task 7 (visibilità) e 11 (`hasSpecialistLLM`); §6 sicurezza → Task 3, 4, 5, 12; §7 job → Task 6, 10; §8 test → ogni task + Task 14; §9 istruzioni → Task 13; §10 introduzione graduale → traguardi M1–M4; §11 plug-in → fuori dal piano per decisione dell'utente; §12 punti aperti → risolti nei task (porta 8765 con errore se occupata, origine `dthub.remote-agent`, punto di misura del budget nel flusso comune di Task 10, default in Task 2).
- **Punto da confermare con l'utente:** la regola della soglia (Task 5) è una scelta di piano per riconciliare lo spec con l'esempio «coda da 80».
- **Rischio dichiarato:** le firme esatte di `StatefulHTTPServerTransport` e il meccanismo di osservazione dell'avanzamento in `AppAgentHost` si fissano leggendo il codice nel Task 1 (Step 1) e nel Task 11; il resto dei task non ne dipende.
