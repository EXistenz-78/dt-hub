# LLM da un server LM Studio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aggiungere il server compatibile OpenAI di LM Studio (locale) come sorgente alternativa degli LLM, scelta in Preferences › LLM, lasciando intatto il percorso MLX da cartella.

**Architecture:** `LanguageModelSettings` ottiene `backend` (`folder` | `lmStudio`). Un nuovo `OpenAICompatibleService` (solo `URLSession`) implementa `LanguageModelService`; i modelli del server sono normali `LanguageModelDescriptor` con `sizeBytes` 0, quindi router, assegnazioni e plug-in non cambiano. `LanguageModelManager` tiene due servizi e sceglie in base al backend.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, `URLSession`, ImageIO. Nessuna dipendenza nuova.

**Spec:** `docs/superpowers/specs/2026-11-03-llm-server-lmstudio-design.md`

## Global Constraints

- Il percorso `folder` resta **invariato**: tutti i test esistenti di `Packages/Tests/HubCoreTests` (in particolare `LanguageModelManagerTests`, `LanguageModelManagerAssignmentTests`, `LanguageModelSettingsTests`) passano **senza modifiche** a ogni commit.
- Indirizzo del server: solo `http`, host `localhost`, `127.0.0.1` o `[::1]`, con porta. Predefinito `http://localhost:1235/v1`.
- Nessun caso nuovo in `LanguageModelError`: gli errori del server usano `loadFailed`, `generationFailed`, `modelNotFound`, `imagesNotSupported`.
- Un modello del server: `LanguageModelDescriptor(path: "lmstudio://" + id, name: id, sizeBytes: 0, supportsImages: …)`.
- Valori predefiniti di richiesta come oggi: temperatura 0,6, 1024 token. Timeout: 300 s per la richiesta, 5 s per l'elenco dei modelli. Immagini: JPEG, lato lungo massimo 1536 px, qualità 0,85 (da confermare nella Task 3).
- `LLMBridge`, `LanguageModelScanner`, `LanguageModelRouter`, `LanguageModelAssignment`, `PluginKit` e i plug-in non si toccano.
- Testi dell'interfaccia in `App/Localizable.xcstrings`, con inglese e italiano (le chiavi `prefs.llm.*` esistenti sono il modello).
- Nei test una chiamata di rete reale da `swift test` va in timeout dentro la sandbox: i test dal vivo si lanciano con la sandbox disattivata. I test normali non usano la rete (si inietta `fetch`/`send`).
- Comandi: test `cd Packages && swift test --filter <Nome> 2>&1 | grep -E "Test run with|✘|error:"`; build app `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build`.

## Review Focus

1. **Server spento all'avvio con `lmStudio` attivo.** Ci si aspetta l'errore chiaro «LM Studio non risponde…» sui pulsanti dei prompt, non «nessun modello scelto»; le assegnazioni restano. Test nella Task 4.
2. **Cambio di sorgente con un modello caricato.** Il servizio vecchio viene scaricato, il nuovo non eredita lo stato. Test nella Task 4.
3. **Il server risponde ma restituisce HTML o JSON senza `choices`.** `generationFailed` con le prime 200 lettere, non un crash. Test nella Task 3.
4. **Modelli di embedding nell'elenco.** Non compaiono tra gli LLM, né con l'API nativa né col ripiego. Test nella Task 2.
5. **Indirizzo non locale o malformato nel campo.** Non si salva e non si usa; la preferenza lo dice. Test nella Task 1.

---

### Task 1: Impostazioni e indirizzo del server

**Files:**
- Modify: `Packages/Sources/HubCore/Language/LanguageModelSettings.swift`
- Create: `Packages/Sources/HubCore/Language/LMStudioAddress.swift`
- Test: `Packages/Tests/HubCoreTests/LMStudioSettingsTests.swift`

**Interfaces:**
- Consumes: `LanguageModelSettings` (init con parametri predefiniti, `init(from:)` indulgente con `value(_:_:)`, `CodingKeys`).
- Produces:
  - `public enum LanguageModelBackend: String, Codable, CaseIterable, Identifiable, Sendable { case folder, lmStudio; public var id: String }`
  - in `LanguageModelSettings`: `public var backend: LanguageModelBackend`, `public var serverURL: String`, `public var serverVisionModels: Set<String>`; i tre nuovi parametri in coda a `init(...)` con default `.folder`, `LMStudioAddress.defaultURL`, `[]`.
  - `public enum LMStudioAddress { static let defaultURL: String; static func validated(_ text: String) -> URL?; static func modelsURL(_ base: URL) -> URL; static func nativeModelsURL(_ base: URL) -> URL; static func chatURL(_ base: URL) -> URL }`

- [ ] **Step 0: Ramo e documenti**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git switch -c feature/llm-lmstudio
git add docs/superpowers/specs/2026-11-03-llm-server-lmstudio-design.md docs/superpowers/plans/2026-11-03-llm-server-lmstudio.md
git commit -m "LLM da server LM Studio: spec e piano"
```

- [ ] **Step 1: Scrivere i test (devono fallire)** in `LMStudioSettingsTests.swift`:
  - `validatedAcceptsOnlyLocalHttpWithAPort`: `validated("http://localhost:1235/v1")`, `"http://127.0.0.1:1235/v1"`, `"http://[::1]:1235/v1"` non sono nil; `"http://192.168.1.5:1235/v1"`, `"https://localhost:1235/v1"`, `"http://localhost/v1"` (senza porta), `"localhost:1235"`, `""` sono nil.
  - `validatedDropsATrailingSlashAndSpaces`: `validated("  http://localhost:1235/v1/ ")?.absoluteString == "http://localhost:1235/v1"`.
  - `urlsAreBuiltFromTheBase`: da `http://localhost:1235/v1`: `chatURL` = `…/v1/chat/completions`, `modelsURL` = `…/v1/models`, `nativeModelsURL` = `http://localhost:1235/api/v0/models`.
  - `oldSettingsLoadAsFolder`: decodificare `{"folder":"/x"}` dà `backend == .folder`, `serverURL == LMStudioAddress.defaultURL`, `serverVisionModels.isEmpty`.
  - `theNewFieldsRoundTrip`: `LanguageModelSettings(backend: .lmStudio, serverURL: "http://localhost:1234/v1", serverVisionModels: ["a"])` codificato e decodificato è uguale.

- [ ] **Step 2: Eseguire e vedere fallire** — `cd Packages && swift test --filter LMStudioSettingsTests 2>&1 | grep -E "Test run with|✘|error:"` → errore di compilazione (tipi mancanti).

- [ ] **Step 3: Implementare** `LanguageModelBackend` e i tre campi (con `CodingKeys` e lettura indulgente `value(.backend, fallback.backend)` ecc.) in `LanguageModelSettings.swift`; `LMStudioAddress` in `LMStudioAddress.swift`. `validated` usa `URLComponents`: scheme `http`, `host` in `["localhost","127.0.0.1","::1"]`, `port != nil`; toglie spazi e la `/` finale del percorso.

- [ ] **Step 4: Eseguire** lo stesso comando e poi `swift test --filter LanguageModelSettingsTests` → tutti passano.

- [ ] **Step 5: Commit**

```bash
git add Packages/Sources/HubCore/Language Packages/Tests/HubCoreTests/LMStudioSettingsTests.swift
git commit -m "LLM server: sorgente nelle impostazioni e validazione dell'indirizzo"
```

---

### Task 2: Elenco dei modelli del server

**Files:**
- Create: `Packages/Sources/HubCore/Language/ServerModelList.swift`
- Test: `Packages/Tests/HubCoreTests/ServerModelListTests.swift`

**Interfaces:**
- Consumes: `LMStudioAddress.modelsURL(_:)`, `.nativeModelsURL(_:)`; `LanguageModelDescriptor`, `LanguageModelError` (HubKit).
- Produces:
  - `public struct ServerModelList: Sendable { public var fetch: @Sendable (URL) async throws -> Data; public init(fetch:); public static let live: ServerModelList; public func models(base: URL, visionModels: Set<String>) async throws -> [LanguageModelDescriptor] }`
  - `public static let idPrefix = "lmstudio://"` e `public static func descriptor(id: String, vision: Bool) -> LanguageModelDescriptor` (`path: idPrefix + id`, `name: id`, `sizeBytes: 0`).
  - `live` usa `URLSession.shared` con timeout 5 s.

- [ ] **Step 1: Test (falliscono)** in `ServerModelListTests.swift`, con `fetch` finto che risponde per URL:
  - `nativeListKeepsLlmAndVlmAndDropsEmbeddings`: JSON nativo con `{"id":"a","type":"llm"},{"id":"v","type":"vlm"},{"id":"e","type":"embeddings"}` → nomi `["a","v"]`; `v.supportsImages`, `!a.supportsImages`; `a.sizeBytes == 0`; `a.path == "lmstudio://a"`.
  - `visionTogglesMarkAModelAsReadingImages`: `visionModels: ["a"]` → `a.supportsImages`.
  - `fallsBackToTheOpenAIListWhenTheNativeOneFails`: il fetch lancia per `/api/v0/models`; `/v1/models` dà `a`, `text-embedding-nomic-embed-text-v1.5` → solo `a` (Review Focus 4).
  - `bothFailingThrowsLoadFailedWithAPlainSentence`: tutti i fetch lanciano → `LanguageModelError.loadFailed` il cui testo contiene `localhost:1235`.
  - `isSortedByName`: ids `b`, `a` → `["a","b"]`.

- [ ] **Step 2: Vedere fallire** — `swift test --filter ServerModelListTests …` → errore di compilazione.

- [ ] **Step 3: Implementare** `ServerModelList`: prima la nativa (`{"data":[{"id","type"}]}`; accetta `llm`/`vlm`), se la richiesta o la lettura falliscono ripiega su `/v1/models` scartando gli id che contengono `embed` (minuscolo). Messaggio d'errore in inglese: «LM Studio does not answer on \(host):\(port). Is it running, with its server started?».

- [ ] **Step 4: Eseguire** → passano.

- [ ] **Step 5: Commit** — `git add Packages && git commit -m "LLM server: elenco dei modelli (API nativa e ripiego OpenAI)"`.

---

### Task 3: Il servizio OpenAI compatibile

**Files:**
- Create: `Packages/Sources/HubCore/Language/OpenAICompatibleService.swift`
- Test: `Packages/Tests/HubCoreTests/OpenAICompatibleServiceTests.swift`

**Interfaces:**
- Consumes: `LMStudioAddress.chatURL(_:)`, `ServerModelList`, `LanguageModelService`, `LanguageModelOptions`, `LanguageModelTurn`.
- Produces:
  - `public protocol ServerLanguageModelService: LanguageModelService { func configure(address: URL, visionModels: Set<String>) async; func models() async throws -> [LanguageModelDescriptor] }`
  - `public actor OpenAICompatibleService: ServerLanguageModelService` con `public init(list: ServerModelList = .live, send: @escaping @Sendable (URLRequest) async throws -> (Data, Int) = OpenAICompatibleService.liveSend)`.
  - interni testabili: `static func body(model: String, prompt: String, imageDataURLs: [String], options: LanguageModelOptions, history: [LanguageModelTurn]) throws -> Data`, `static func answer(from data: Data) throws -> String`, `static func imageDataURL(for url: URL, maxPixel: Int) -> String?`.
- `load(model)`: ricorda `model.name`, errore `modelNotFound(name)` se non è nell'ultimo elenco noto (se l'elenco è ancora vuoto non controlla). `unload()`: dimentica. `respond(...)`: senza modello caricato → `loadFailed("No model is loaded.")`.

- [ ] **Step 1: Verifica con il server vero** (fuori sandbox, prima del codice). Con `curl -s localhost:1235/v1/chat/completions -d '{"model":"phonon-40m-multilingual","messages":[{"role":"user","content":"Reply: pong"}],"max_tokens":20,"temperature":0,"top_k":20}'` annotare nella sezione «Cosa si è verificato» della spec: se `top_k` è accettato (200 o 400), la forma della risposta. Se è disponibile un modello con visione, provare anche un messaggio con `{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,…"}}` e annotare il `type` che LM Studio dà a quel modello in `/api/v0/models`; altrimenti annotare «non verificato: nessun modello con visione». Se `top_k` dà 400, `body` non lo invia.

- [ ] **Step 2: Test (falliscono)** in `OpenAICompatibleServiceTests.swift`:
  - `bodyPutsSystemHistoryAndTheQuestionInOrder`: messaggi `[system, user(h1), assistant(h2), user(prompt)]`, `model`, `stream == false`, `temperature == 0.6` e `max_tokens == 1024` di default.
  - `bodyMapsTheOptions`: `LanguageModelOptions(temperature: 0.2, topP: 0.9, presencePenalty: 0.5, maxTokens: 50)` → `temperature`, `top_p`, `presence_penalty`, `max_tokens`; `thinking` non compare nel corpo.
  - `imagesGoInTheLastUserMessageAsDataURLs`: con `imageDataURLs: ["data:image/jpeg;base64,AAA"]` l'ultimo messaggio ha `content` array con una parte `text` e una `image_url`.
  - `answerReadsTheFirstChoiceAndStripsAThinkBlock`: `"<think>x</think>\n pong "` → `"pong"`.
  - `answerWithoutChoicesOrEmptyThrowsGenerationFailed`: HTML, `{}` e contenuto vuoto → `.generationFailed` (con le prime 200 lettere del corpo per l'HTML) (Review Focus 3).
  - `imageDataURLShrinksALargePicture`: un PNG 3000×2000 scritto in cartella temporanea → data URL che inizia con `data:image/jpeg;base64,` e il JPEG decodificato ha lato lungo ≤ 1536.
  - `respondSendsToTheChatURLAndMapsHttpErrors`: `send` finto registra la richiesta (`POST`, URL `…/v1/chat/completions`, timeout 300); stato 500 con `{"error":{"message":"boom"}}` → `.generationFailed` che contiene `boom`; `send` che lancia `URLError(.cannotConnectToHost)` → `.loadFailed` con `localhost:1235`.
  - `respondWithoutALoadedModelFails` e `loadOfAnUnknownModelIsModelNotFound`.

- [ ] **Step 3: Vedere fallire** — `swift test --filter OpenAICompatibleServiceTests …` → errore di compilazione.

- [ ] **Step 4: Implementare** il protocollo e l'actor. `body` costruisce un dizionario e lo serializza con `JSONSerialization`; l'immagine con `CGImageSource` + `kCGImageSourceThumbnailMaxPixelSize` + `CGImageDestination` JPEG qualità 0,85. `answer` rimuove un blocco iniziale `<think>…</think>` (regex con `.dotMatchesLineSeparators`) e fa `trimmingCharacters`. `liveSend` usa `URLSession.shared` con `timeoutInterval` 300.

- [ ] **Step 5: Eseguire** i test della task → passano; poi `swift test --filter LanguageModelManager` per vedere che nulla del resto è rotto.

- [ ] **Step 6: Test dal vivo** (fuori sandbox, saltato se manca la variabile): in `OpenAICompatibleServiceLiveTests.swift`, `@Test(.enabled(if: ProcessInfo.processInfo.environment["DTHUB_LIVE_SERVER"] != nil))`: legge l'elenco, carica il primo modello `llm`, chiede «Reply with exactly one word: pong» con `temperature: 0` e si aspetta che la risposta contenga `pong` (senza distinzione di maiuscole). Lanciarlo con `DTHUB_LIVE_SERVER=http://localhost:1235/v1 swift test --filter OpenAICompatibleServiceLiveTests`.

- [ ] **Step 7: Commit** — `git add Packages docs/superpowers/specs && git commit -m "LLM server: servizio OpenAI compatibile"`.

---

### Task 4: Il gestore sceglie la sorgente

**Files:**
- Modify: `Packages/Sources/HubCore/Language/LanguageModelManager.swift`
- Test: `Packages/Tests/HubCoreTests/LanguageModelManagerServerTests.swift`

**Interfaces:**
- Consumes: `ServerLanguageModelService`, `OpenAICompatibleService`, `LMStudioAddress.validated(_:)`, `LanguageModelBackend`, `FakeLanguageModelService` e `LanguageModelManagerTests` (helper `folder()`, `manager(...)`) già nei test.
- Produces:
  - `init(...)` ottiene in coda `serverService: any ServerLanguageModelService = OpenAICompatibleService()` (le chiamate esistenti compilano senza cambiare).
  - `public private(set) var serverModels: [LanguageModelDescriptor]`, `public private(set) var serverError: LanguageModelError?`, `public func refreshServerModels() async`.
  - `availableModels()` con `lmStudio` ritorna `serverModels`.
  - `model(for:family:needs:)` con `lmStudio`, elenco vuoto e `serverError != nil` ritorna `.failure(serverError)`.
  - `ensureLoaded`/`ask` usano il servizio del backend attivo; `unload()` scarica il servizio che ha il modello (`loadedBackend`); `scheduleIdleUnload()` e `prepareForRun()` non fanno nulla con `lmStudio`; `releaseImageModel` resta com'è.
- Nel test: `actor FakeServerService: ServerLanguageModelService` (nello stesso file) con `listed: [LanguageModelDescriptor]`, `listError: LanguageModelError?`, `loads`, `unloads`, `answer`, `configured: [(URL, Set<String>)]`.

- [ ] **Step 1: Test (falliscono)** in `LanguageModelManagerServerTests.swift` (`@MainActor struct`, riusa `LanguageModelManagerTests()` come helper):
  - `serverBackendListsTheServerModelsAfterARefresh`: backend `lmStudio`, `serverURL` valido, fake con modelli `a` e `v`; prima del refresh `availableModels()` è vuoto, dopo ha `["a","v"]`; il fake ha ricevuto `configure` con l'indirizzo e i `serverVisionModels`.
  - `aQuestionGoesToTheServerServiceNotToMLX`: assegnazione `a` = `.allOthers`/`.both`; `respond(to:)` → `serverService.loads == ["a"]`, il `FakeLanguageModelService` MLX non ha `loads` né `questions`.
  - `theMemoryCheckNeverBlocksAServerModel`: `available: 0` nell'helper → la richiesta passa.
  - `theServerModelIsNotUnloadedByIdleOrRun`: `idle: 1` (un minuto = 40 ms), attesa 250 ms → `unloads == 0`; `prepareForRun()` con `freeAtRun: true` → `unloads == 0`.
  - `switchingBackendUnloadsTheOldService`: domanda con `folder` (MLX fake `loads == 1`), poi `settings.backend = .lmStudio`, refresh, nuova domanda → MLX fake `unloads == 1` (Review Focus 2).
  - `aServerThatIsOffGivesTheClearError`: fake con `listError = .loadFailed("LM Studio does not answer…")`; dopo il refresh `serverError` è quell'errore e `respond(to:)` lancia lo stesso errore, non `.noModelSelected` (Review Focus 1); le assegnazioni dei modelli di cartella sono intatte.
  - `theImageModelIsStillReleasedBeforeAServerModelLoads`: `freeImage: true` e `release` che conta → 1 chiamata.
  - `profileOfAServerModelIsEmpty`: `LanguageModelProfile.load(folder: URL(fileURLWithPath: "lmstudio://x"))` non ha `pup` né prompt (nessun crash).
  - `anInvalidAddressEmptiesTheListWithAnError`: `serverURL = "http://example.com:1/v1"` → `serverModels` vuoto, `serverError != nil`, il fake non riceve `configure`.

- [ ] **Step 2: Vedere fallire** — `swift test --filter LanguageModelManagerServerTests …` → errore di compilazione.

- [ ] **Step 3: Implementare** in `LanguageModelManager.swift`: il secondo servizio, `loadedBackend`, `refreshServerModels()` (valida l'indirizzo, `configure`, `models()`, aggiorna `serverModels`/`serverError`), la scelta del servizio in `ensureLoaded`/`ask` (con `configure` prima di `load` per `lmStudio`), `unload()` sul servizio di `loadedBackend`, `guard settings.backend == .folder` in `scheduleIdleUnload()` e `prepareForRun()`, e il ramo in `availableModels()` e `model(for:family:needs:)`. Un modello caricato con un backend diverso dall'attivo si scarica prima di caricare l'altro.

- [ ] **Step 4: Eseguire** — `swift test --filter LanguageModelManager` (tutti, vecchi e nuovi) → passano; poi `cd Packages && swift test 2>&1 | grep -E "Test run with|✘|error:"` per l'intero pacchetto.

- [ ] **Step 5: Commit** — `git add Packages && git commit -m "LLM server: il gestore sceglie tra cartella MLX e server LM Studio"`.

---

### Task 5: App, Preferenze, testi e README

**Files:**
- Modify: `App/DTHubApp.swift`, `App/Preferences/LanguagePreferencesView.swift`, `App/Localizable.xcstrings`, `README.md`
- Nessun test unitario nuovo (la logica è nelle task 1–4); la verifica è la build e la prova a mano sotto.

**Interfaces:**
- Consumes: `LanguageModelManager.refreshServerModels()`, `.serverModels`, `.serverError`, `LanguageModelSettings.backend/serverURL/serverVisionModels`, `LMStudioAddress.validated(_:)`.
- Produces: nessuna API; chiavi di stringa nuove (en/it):
  `prefs.llm.backend` («Source» / «Sorgente»), `prefs.llm.backend.folder` («Folder (MLX)» / «Cartella (MLX)»), `prefs.llm.backend.lmStudio` («LM Studio server» / «Server LM Studio»), `prefs.llm.server.address` («Address» / «Indirizzo»), `prefs.llm.server.invalid` («Only localhost, 127.0.0.1 or [::1], with a port.» / «Solo localhost, 127.0.0.1 o [::1], con la porta.»), `prefs.llm.server.test` («Test» / «Prova»), `prefs.llm.server.connected` («Connected, %d models» / «Connesso, %d modelli»), `prefs.llm.server.vision` («Reads images» / «Legge le immagini»), `prefs.llm.server.note` (una riga: LM Studio e Draw Things dividono la RAM; DT Hub libera il modello immagine solo se il server lo avvia lui).

- [ ] **Step 1: Selettore e sezione server.** In `LanguagePreferencesView.body`: in cima un `Section` con `Picker("prefs.llm.backend", selection: $manager.settings.backend)` (voci `LanguageModelBackend.allCases`). Con `.folder` il corpo resta quello di oggi (`folderSection`, `PromptLibrarySection`, `memorySection`, `testSection`). Con `.lmStudio`: una `serverSection` (campo indirizzo che al submit valida con `LMStudioAddress.validated` e mostra `prefs.llm.server.invalid` se nil; pulsante «Prova» che chiama `await manager.refreshServerModels()` e mostra `prefs.llm.server.connected` o `manager.serverError?.plainText`; per ogni modello l'esistente `modelRow` più, per i modelli senza visione, un `Toggle("prefs.llm.server.vision")` che aggiorna `serverVisionModels` e rifà il refresh), poi `PromptLibrarySection()`, `memorySection` ridotta al solo interruttore «Libera il modello immagine…» (nascondere «Libera al RUN» e il tempo di inattività), e `testSection`.

- [ ] **Step 2: Aggiornare l'elenco al momento giusto.** In `LanguagePreferencesView`: `.onChange(of: manager.settings.backend)` e `.onAppear` chiamano `Task { await manager.refreshServerModels(); refresh() }`. In `DTHubApp`: un `Task { await languageModel.refreshServerModels() }` all'avvio e lo stesso a ogni `NSApplication.didBecomeActiveNotification` (`.onReceive` sulla scena principale).

- [ ] **Step 3: Stringhe** nel formato di `prefs.llm.freeAtRun` (`extractionState: "manual"`, `localizations` `en` e `it`, `state: "translated"`), tutte le chiavi sopra.

- [ ] **Step 4: README** — nella sezione «The local LLM» aggiungere un paragrafo: la sorgente alternativa «LM Studio server» (locale, `http://localhost:1235/v1`, modelli del server assegnabili per famiglia e uso come gli altri, nessun prompt upsampler di FLUX.3 con questo metodo, LM Studio carica il modello alla prima richiesta e la sua RAM non è gestita da DT Hub). La frase «nothing is sent» resta vera: l'indirizzo è solo locale.

- [ ] **Step 5: Build** — `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"` → `BUILD SUCCEEDED`.

- [ ] **Step 6: Prova a mano** con LM Studio acceso su `localhost:1235`: (a) con «Cartella (MLX)» tutto come prima; (b) passare a «Server LM Studio», «Prova» mostra «Connesso, 1 modelli», il modello compare senza il modello di embedding, assegnarlo a «tutti gli altri · entrambi»; (c) *Enhance Prompt* risponde dal server; (d) la chat dell'AI Assistant e un plug-in con LLM rispondono; (e) spegnere LM Studio, *Enhance Prompt* mostra l'errore «LM Studio does not answer…»; (f) tornare a «Cartella (MLX)» e verificare che le assegnazioni dei modelli MLX siano rimaste. Annotare ciò che non torna.

- [ ] **Step 7: Commit**

```bash
git add App README.md
git commit -m "LLM server: selettore di sorgente, preferenze, stringhe e README"
```

---

## Self-review

- **Copertura della spec:** sorgente e campi (T1), elenco dei modelli (T2), servizio e prove sul server (T3), gestore, cambio di sorgente, memoria/idle/RUN e profilo del modello (T4), preferenze, avvio e ritorno in primo piano, stringhe, README (T5). Fuori ambito rispettato (nessun PUP, chiave API, host remoti, streaming).
- **Coerenza dei tipi:** `LMStudioAddress.validated/modelsURL/nativeModelsURL/chatURL` (T1) sono usati in T2, T3, T4; `ServerModelList.models(base:visionModels:)` (T2) è chiamato da `OpenAICompatibleService.models()` (T3); `ServerLanguageModelService.configure(address:visionModels:)` e `models()` (T3) sono quelli che T4 chiama e che `FakeServerService` implementa.
- **Rischio rimasto:** la forma delle richieste con immagini e il `type` dei modelli con visione non sono verificati finché non c'è un modello con visione; la T3 Step 1 lo registra, la T5 Step 6 lo prova a mano.
