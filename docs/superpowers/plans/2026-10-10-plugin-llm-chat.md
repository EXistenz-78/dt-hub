# Plug-in «LLM Chat» e aggiunte al contratto — Piano di implementazione

> **Per chi esegue:** SOTTO-SKILL OBBLIGATORIA: `superpowers:subagent-driven-development` (consigliata) oppure `superpowers:executing-plans`. I passi usano la sintassi a caselle (`- [ ]`).

**Obiettivo:**
- l'app manda prompt, negativo e forza nel contesto, accetta lo storico in `llm` e la forza in `contribute`;
- un plug-in nuovo, «LLM Chat», usa queste aggiunte per chattare con un LLM locale e, solo con `<INVIA>`/`<SEND>`, applicare prompt, parametri, forza o una pipeline.

**Architettura:**
- **Parte A** (Task 1–5): HubKit, HubCore, LLMBridge, App e kit; aggiunte compatibili al contratto 1.
- **Parte B** (Task 6–10): pacchetto `Plugins/LLMChat`.
  - Logica pura: comando, blocco di azioni, finestra dello storico, system prompt, archivio.
  - Poi stato, vista e collegamento.

**Tecnologie:** Swift 6.2, Swift Testing, SwiftUI, mlx-swift-lm 3.32.3 (`ChatSession(_:instructions:history:…)`).

**Spec:** `docs/superpowers/specs/2026-10-10-plugin-llm-chat-design.md` (system prompt esatto al §6.3, regole del blocco al §6.4).

## Vincoli globali

- **Ramo e pubblicazione:**
  - base `origin/main` 0.1.5 (`5c6bf54`), ramo nuovo (es. `plugin-llm-chat`);
  - **niente unione, push o release senza via libera esplicito**;
  - file aggiunti **per nome**: mai `git add -A` né `git add docs`.
- **Test:**
  - app: `cd Packages && swift test --filter <Suite> 2>&1 | grep -E "Test run with|error:"`;
  - kit: `cd PluginKit && swift test`;
  - plug-in: `cd Plugins/LLMChat && swift test`.
- **Compilare l'app:** `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build`.
- **Regressioni:**
  - i test esistenti restano verdi;
  - cambiano solo le firme toccate (chiusura `askLanguageModel`, requisito di `LanguageModelService`, `ContributionTarget`), da aggiornare nei test senza cambiare le attese;
  - gli altri plug-in (`swift build` in Sphere Light, Prompt Master, I4, Character Sheet, Batch plus) compilano senza modifiche.
- **Testi:** commenti in inglese. Testi dell'app (se servono) it/en in `Localizable.xcstrings`; testi del plug-in nella sua tabella `L`.

## Review Focus

1. **Plug-in vecchi:** senza `messages`, il messaggio `llm` si comporta esattamente come prima (Task 2–3).
2. **Comando nel codice:** una risposta con blocco di azioni, a un messaggio **senza** `<INVIA>`/`<SEND>`, non invia nulla (Task 7).
3. **Pipeline troppo lunga:** 21 passaggi → niente inviato, neanche i campi dello stesso blocco (Task 7).
4. **Forza senza immagine di partenza:** non cambia nulla e lo dice in `problems` (Task 4).
5. **App 0.1.5 con il plug-in nuovo:** avviso «Aggiorna DT Hub», nessuna chiamata all'LLM (Task 9).
6. **Cambio progetto a metà attesa:** la risposta che arriva dopo non finisce nella chat dell'altro progetto (Task 9).

---

## Parte A — App e kit

### Task 1: Contesto con prompt, negativo e forza

**Files:** Modify `Packages/Sources/HubKit/Plugin/PluginMessages.swift`, `Packages/Sources/HubCore/Plugins/PluginRegistry.swift`, `App/DTHubApp.swift`. Test: `Packages/Tests/HubKitTests/PluginContractTests.swift`, `Packages/Tests/HubCoreTests/PluginRegistryTests.swift`.

**Interfaces — Produces:**
- `PluginContext.prompt`, `.negativePrompt`, `.strength`, tutti opzionali; `init` con default `nil`;
- `PluginRegistry.currentPrompts: (@MainActor () -> (prompt: String, negativePrompt: String))?`;
- `PluginRegistry.startImageStrength: (@MainActor () -> Double?)?`.

- [ ] **Step 1: Test che falliscono.**
  - Contratto: un `PluginContext` con `prompt "a cat"`, `negativePrompt ""`, `strength 0.7` codificato ha le tre chiavi (`negativePrompt` vuoto presente); con `strength nil` la chiave manca.
  - Registry (con `FakeLoadedPlugin`): `currentPrompts = { ("a cat", "blur") }`, `startImageStrength = { 0.5 }` → il JSON ricevuto ha `prompt "a cat"`, `negativePrompt "blur"`, `strength 0.5`. Senza chiusure le chiavi mancano.
- [ ] **Step 2–4:** vedere il fallimento, implementare (`sendContext` legge le chiusure), test verdi.
- [ ] **Step 5: App** — in `DTHubApp.init`:
  - `plugins.currentPrompts = { (generation.prompt, generation.negativePrompt) }`;
  - `plugins.startImageStrength = { control.inputs.image == nil ? nil : control.inputs.effectiveStrength(editModel: generation.isEditModel(in: connection), hasMargins: control.hasMargins(canvasWidth: generation.parameters.width, canvasHeight: generation.parameters.height)) }`. Verificare che `isEditModel(in:)` e `hasMargins` siano raggiungibili da lì; altrimenti un piccolo metodo pubblico su `GenerationController` (es. `startImageStrength(in:)`) che faccia lo stesso calcolo di `ImageCard.strengthRow`.
  - Poi `xcodebuild … build`.
- [ ] **Step 6: Commit** — `feat(plugins): il contesto porta prompt, negativo e forza`.

### Task 2: Storico per l'LLM (servizio e manager)

**Files:** Modify `Packages/Sources/HubKit/Language/LanguageModel.swift` (+ `LanguageModelTurn`, nuovo file `LanguageModelTurn.swift` in HubKit/Language), `Packages/Sources/LLMBridge/MLXLanguageModelService.swift`, `Packages/Sources/HubCore/Language/LanguageModelManager.swift`. Test: `Packages/Tests/HubCoreTests/LanguageModelTests.swift` (`FakeLanguageModelService` e manager).

**Interfaces — Produces:**
- `LanguageModelTurn(role: .user|.assistant, text:)`;
- requisito `LanguageModelService.respond(to:images:options:history:)`, con l'estensione `respond(to:images:options:)` che passa `[]`;
- `LanguageModelManager.respond(to:images:options:modelNamed:history: [LanguageModelTurn] = [])` e `respond(to:images:options:model:history: = [])`.

- [ ] **Step 1: Test che falliscono.**
  - Il fake registra `history`.
  - `manager.respond(to: "now", options: .init(), modelNamed: "text-model", history: [.init(role: .user, text: "a"), .init(role: .assistant, text: "b")])` → il fake riceve i due turni in ordine.
  - Senza `history` riceve `[]`.
  - Immagini su un modello senza visione: `.imagesNotSupported`, come prima.
- [ ] **Step 2–4:** vedere il fallimento, implementare, test verdi.
  - In `MLXLanguageModelService.respond`: con `history.isEmpty` il codice di oggi; altrimenti `ChatSession(container, instructions: options.system, history: history.map(Self.message), generateParameters: …, additionalContext: …)` e lo stesso `respond(to:role:.user,images:…)`.
  - `static func message(_ turn: LanguageModelTurn) -> Chat.Message` (`.user(text)` / `.assistant(text)`), con un test in `Packages/Tests/LLMBridgeTests/MLXOptionsTests.swift` (ruoli e testi).
  - Aggiornare il commento «A new session per question: DT Hub asks single questions».
- [ ] **Step 5: Commit** — `feat(llm): storico della conversazione fino al modello`.

### Task 3: `messages` nel messaggio `llm`

**Files:** Modify `Packages/Sources/HubCore/Plugins/PluginRegistry.swift`, `App/DTHubApp.swift`. Test: `Packages/Tests/HubCoreTests/PluginRoutingTests.swift`.

**Interfaces — Produces:** `PluginRegistry.askLanguageModel: (@MainActor (_ prompt: String, _ images: [URL], _ options: LanguageModelOptions, _ modelName: String?, _ history: [LanguageModelTurn]) async throws -> String)?`; `static func turns(_ value: Any?) -> [LanguageModelTurn]` (puro, `nonisolated`).

- [ ] **Step 1: Test che falliscono.**
  - `{"type":"llm","prompt":"now","messages":[{"role":"user","text":"a"},{"role":"assistant","text":"b"}]}` → la chiusura riceve due turni in ordine.
  - Voci saltate: `{"role":"system","text":"x"}`, `{"role":"user"}`, `"text"`, `{"role":"user","text":5}`.
  - Senza `messages` → `[]` (**Review Focus 1**).
  - I test esistenti con la chiusura a 5 argomenti, attese invariate.
- [ ] **Step 2–4:** vedere il fallimento, implementare, test verdi. In `DTHubApp`: `plugins.askLanguageModel = { prompt, images, options, name, history in try await languageModel.respond(to: prompt, images: images, options: options, modelNamed: name, history: history) }`; `xcodebuild … build`.
- [ ] **Step 5: Commit** — `feat(plugins): storico della chat nel messaggio llm`.

### Task 4: `strength` in `contribute`

**Files:** Modify `Packages/Sources/HubKit/Plugin/PluginContribution.swift`, `Packages/Sources/HubCore/Plugins/ContributionStore.swift`, `App/Generation/GenerationController.swift`. Test: `Packages/Tests/HubKitTests/` (test delle contribution: file esistente o `PluginContributionStrengthTests.swift`), `Packages/Tests/HubCoreTests/ContributionStoreTests.swift` (+ `FakeContributionTarget` nello stesso file).

**Interfaces — Produces:** `PluginContribution.strength: Double?` (init con default `nil`); `ContributionTarget.setStrength(_ value: Double)`.

- [ ] **Step 1: Test che falliscono.**
  - Lettura: `{"strength":0.45}` → 0.45; `1.7` → 1; `-1` → 0; `"0.5"` → nil; `{"strength":0.3}` da solo → `isEmpty == false`.
  - Store con target finto:
    - con immagine di partenza → `setStrength(0.45)` chiamato, `problems` vuoto;
    - senza → non chiamato, `problems == ["strength: there is no start image."]` (**Review Focus 4**);
    - `startImage` + `strength` nello stesso messaggio → immagine prima, poi forza applicata.
- [ ] **Step 2–4:** vedere il fallimento, implementare (`GenerationController.setStrength` → `control.setStrength(value)`), test verdi; `xcodebuild … build`.
- [ ] **Step 5: Commit** — `feat(plugins): la forza dell'immagine di partenza da contribute`.

### Task 5: Kit e README del kit

**Files:** Modify `PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift`, `PluginKit/README.md`. Test: `PluginKit/Tests/DTHubPluginKitTests/DTHubPluginKitTests.swift`.

**Interfaces — Produces:**
- `DTHubContext.prompt`, `.negativePrompt`, `.strength`, letti con `try?`;
- `DTHubLLMTurn`;
- `askLanguageModel`/`askLanguageModelAnswer(…, history: [DTHubLLMTurn] = [])`;
- `llmMessage(prompt:images:system:model:options:history:)`.

- [ ] **Step 1: Test che falliscono.**
  - Contesto con i tre campi → letti. Senza → `nil`. `strength: "alta"` → `nil` e il resto c'è.
  - `llmMessage` con due turni → `messages == [["role":"user","text":"a"],["role":"assistant","text":"b"]]`; senza turni la chiave manca.
- [ ] **Step 2–4:** vedere il fallimento, implementare, test verdi.
- [ ] **Step 5: README** — sezione «Messages (contract 1)»:
  - `prompt`, `negativePrompt`, `strength` nel contesto (con il significato e «absent from older apps»);
  - `messages` nel messaggio `llm` (turni precedenti, dal più vecchio; le immagini vanno col `prompt`);
  - `strength` in `contribute` (0–1, solo con un'immagine di partenza, l'ultimo che scrive vince, non si colora).
- [ ] **Step 6: Suite e compilazione.**
  - `cd Packages && swift test`;
  - `swift build` in ogni plug-in esistente;
  - `xcodebuild … build`.
- [ ] **Step 7: Commit** — `feat(kit): prompt, forza e storico nel kit`.

---

## Parte B — Plug-in `Plugins/LLMChat`

Struttura dei sorgenti in `Sources/LLMChat/`:

| File | Contenuto |
| --- | --- |
| `LLMChatPlugin.swift` | manifest, `handle`, entry |
| `ChatModel.swift` | `ChatMessage`, `Chat`, `ChatSettings` (Codable tolleranti) |
| `ChatStore.swift` | `state.json`, `chats/` |
| `CommandGate.swift` | rilevamento di `<INVIA>`/`<SEND>` |
| `ActionBlock.swift` | ricerca, validazione, corpo di `contribute`, riassunto |
| `HistoryWindow.swift` | turni da mandare entro il budget |
| `ImageLabels.swift` | blocco delle immagini allegate |
| `SystemPrompt.swift` | testo della spec §6.3 |
| `SamplerNames.swift` | copia di Batch plus |
| `ChatTitle.swift` | titolo automatico della chat |
| `LLMChatState.swift` | `ObservableObject` della tab |
| `LLMChatView.swift` | la vista |
| `Strings.swift` | tabella `L` it/en |

### Task 6: Pacchetto, modello dei dati, archivio

**Files:** Create `Plugins/LLMChat/Package.swift`, `Scripts/build.sh`, `Sources/LLMChat/ChatModel.swift`, `ChatStore.swift`, `ChatTitle.swift`, `Strings.swift` (prime voci), test `Tests/LLMChatTests/ChatStoreTests.swift`, `ChatTitleTests.swift`.

**Interfaces — Produces:**
- `ChatMessage{id: UUID, role: .user|.assistant|.note, text, date, images: [String], note: .action|.error|.ignored|.info?}`;
- `Chat{id, title, created, updated, messages}`;
- `ChatSettings{currentChat: UUID?, model: String?, includeImages: Bool = true}`;
- `ChatStore(folder: URL?)` con:
  - `loadSettings()`, `save(_ settings:)`;
  - `list() -> [ChatSummary]` (id, title, updated; ordinato per `updated` decrescente);
  - `load(_ id:) -> Chat?`, `save(_ chat:)`, `delete(_ id:)`;
  - con `folder == nil` lavora in memoria;
- `ChatTitle.make(from:date:italian:)`.

- [ ] **Step 1:** `Package.swift` come Batch plus (alias `LLMChatKit`, `LLMChatDesign`); `build.sh` come Batch plus (id `com.exiztenz.dthub.llmchat`, nome `LLMChat`, entry `LLMChatEntry`).
- [ ] **Step 2: Test che falliscono.**
  - Archivio in una cartella temporanea: salva e ricarica una chat uguale; `list` in ordine di `updated`; `delete` toglie il file; un file `chats/x.json` illeggibile non compare e non fa fallire `list`; `state.json` illeggibile → `ChatSettings()` con `includeImages == true`; due cartelle (due progetti) non si vedono a vicenda.
  - Titolo:
    - `"Rendi il prompt più cupo <INVIA>\naltro"` → `"Rendi il prompt più cupo"`;
    - 60 caratteri → 40 + `"…"`;
    - solo `"<SEND>"` → `"Chat del …"` / `"Chat of …"` con la data.
- [ ] **Step 3–4:** implementare, test verdi.
- [ ] **Step 5: Commit** — `feat(llm-chat): pacchetto, chat e archivio per progetto`.

### Task 7: Comando e blocco di azioni

**Files:** Create `Sources/LLMChat/CommandGate.swift`, `ActionBlock.swift`, `SamplerNames.swift`. Test: `CommandGateTests.swift`, `ActionBlockTests.swift`.

**Interfaces — Produces:**
- `CommandGate.isOpen(_ userText: String) -> Bool`;
- `ActionBlock.find(in reply: String) -> String?` (testo JSON del blocco) e `ActionBlock.strip(_ reply: String) -> String` (risposta senza il blocco);
- `ActionBlock.body(from json: String) -> Result<[String: Any], ActionBlock.Problem>`, con `Problem` = `.invalidJSON(String)`, `.tooManySteps(Int)`, `.empty`;
- `ActionBlock.summary(of body: [String: Any], answer: [String: Any]?, italian: Bool) -> (text: String, isError: Bool)`.

- [ ] **Step 1: Test che falliscono.**
  - **Comando:**
    - `"ok <INVIA>"` e `"<SEND> go"` → aperto;
    - `"<invia>"`, `"invia"`, `"send"`, `"<INVIA"` → chiuso.
  - **Ricerca:**
    - blocco ```` ```dthub ```` (anche `DTHub`) trovato;
    - due blocchi `dthub` → l'ultimo;
    - solo ```` ```json ```` con `fields` → trovato;
    - ```` ```json ```` senza chiavi note → nil;
    - nessun blocco → nil;
    - `strip` toglie il blocco e gli spazi in eccesso.
  - **Corpo:**
    - `fields` con `prompt`, `steps`, `foo` → `foo` scartato;
    - `loras` senza `file` scartato;
    - `strength` numero tenuto;
    - pipeline di 3 passi con `width` nei `fields` → `width` tolto, titoli vuoti → `"Passaggio 2"`/`"Pass 2"`, nome `"LLM Chat"`;
    - 21 passi → `.tooManySteps(21)` anche se ci sono `fields` (**Review Focus 3**);
    - `{}` o solo chiavi sconosciute → `.empty`;
    - testo non JSON → `.invalidJSON`.
  - **Riassunto:**
    - corpo con prompt, steps, 2 LoRA, strength, pipeline di 5 → `"Inviati: prompt, passi, LoRA (2), forza, pipeline (5 passaggi)."`;
    - `conflicts: 1` aggiunge la frase dei conflitti;
    - `type: error` → testo dell'app con `isError`;
    - `problems` elencati con `isError`.
- [ ] **Step 2–4:** implementare (JSON con `JSONSerialization`; le chiavi ammesse dei `fields` sono quelle della spec §6.3), test verdi.
- [ ] **Step 5: Commit** — `feat(llm-chat): comando <INVIA> e blocco di azioni`.

### Task 8: Storico, immagini, system prompt

**Files:** Create `Sources/LLMChat/HistoryWindow.swift`, `ImageLabels.swift`, `SystemPrompt.swift`. Test: `HistoryWindowTests.swift`, `ImageLabelsTests.swift`, `SystemPromptTests.swift`.

**Interfaces — Produces:**
- `HistoryWindow.turns(of messages: [ChatMessage], budget: Int = 24_000) -> (turns: [DTHubLLMTurn], trimmed: Bool)`;
- `ImageLabels.block(hasStart: Bool, references: Int) -> String?`;
- `SystemPrompt.make(context: DTHubContext, samplerNames: [String]) -> String`.

- [ ] **Step 1: Test che falliscono.**
  - **Storico:**
    - note escluse;
    - ruoli giusti;
    - con messaggi da 10 000 caratteri e budget 24 000 → gli ultimi due, `trimmed == true`;
    - un solo messaggio più lungo del budget → nessun turno, `trimmed == true` (il messaggio nuovo va comunque come `prompt`).
  - **Immagini:**
    - `(true, 2)` → il blocco della spec §6.2 con tre righe e riga vuota finale;
    - `(false, 1)` → `"Image 1: reference image 1."`;
    - `(false, 0)` → nil.
  - **System prompt**, con un `DTHubContext` decodificato da JSON di esempio (prompt, negativo, parametri con 1 LoRA, strength 0.7):
    - contiene il prompt fra `"""`;
    - contiene `"Sampler: DPM++ 2M Karras"` per `sampler 0`;
    - contiene `"strength 0.70"` e il nome del LoRA;
    - contiene `"<SEND>"`, `"<INVIA>"` e `"At most 20 steps"`.
    - Senza parametri ha `"unknown"` al posto dei valori.
- [ ] **Step 2–4:** implementare con il testo esatto della spec §6.3, test verdi.
- [ ] **Step 5: Commit** — `feat(llm-chat): storico, immagini numerate e system prompt`.

### Task 9: Stato della tab e plug-in

**Files:** Create `Sources/LLMChat/LLMChatState.swift`, `LLMChatPlugin.swift`; completare `Strings.swift`. Test: `LLMChatStateTests.swift`, `StringsTests.swift`.

**Interfaces — Produces:** `LLMChatState: ObservableObject`.
- **Stato pubblicato:**
  - `context: DTHubContext?`;
  - `chat: Chat`;
  - `summaries: [ChatSummary]`;
  - `settings: ChatSettings`;
  - `draft: String`;
  - `isWaiting: Bool`;
  - `active: Bool`.
- **Metodi:**
  - `apply(context:)`;
  - `switchProject(folder:)`;
  - `newChat()`;
  - `open(_ id:)`;
  - `rename(_ title:)`;
  - `deleteCurrent()`;
  - `insertCommand(italian:)`;
  - `cancelWait()`;
  - `send(using ask: Ask, contribute: Contribute) async`.

    Qui `Ask = (String, [String], String, String, [DTHubLLMTurn]) async -> DTHubLLMAnswer`, cioè prompt, immagini, system, modello e storico; `Contribute = ([String: Any]) async -> [String: Any]?`. Si iniettano per i test.
- **Proprietà calcolate:**
  - `blocker: String?`: plug-in spento / app vecchia / nessun LLM;
  - `resolvedModel`;
  - `imagesAvailable`.

- [ ] **Step 1: Test che falliscono** (con `ask` e `contribute` finti):
  - **messaggio senza comando:**
    - `ask` riceve il testo, system prompt e modello;
    - la risposta con blocco `dthub` → `contribute` **non** chiamato, nota `ignored` (**Review Focus 2**);
  - **messaggio con `<INVIA>`:**
    - `contribute` chiamato con il corpo atteso;
    - nota `action` con il riassunto;
    - la copia locale del prompt nel contesto aggiornata;
  - **immagini:**
    - switch acceso, modello con visione, contesto con partenza e 1 Moodboard → `ask` riceve 2 percorsi e il testo inizia con il blocco;
    - nella chat il messaggio salvato non ha il blocco e ha `images` coi nomi;
    - switch spento → nessuna immagine;
    - modello senza visione → nessuna immagine, anche se lo switch è acceso;
  - **`failure("…")`** → nota `error`, messaggio dell'utente tenuto;
  - **contesto senza `prompt`** → `blocker` dice «Aggiorna DT Hub» e `send` non chiama `ask` (**Review Focus 5**);
  - **`cancelWait()` durante l'attesa** → la risposta che arriva dopo non viene aggiunta;
  - **cambio progetto durante l'attesa** → la risposta non entra né nella chat nuova né in quella vecchia; la vecchia resta come salvata (**Review Focus 6**). Usare un numero di generazione che `switchProject`, `newChat`, `open` e `cancelWait` incrementano;
  - **archivio:**
    - `newChat` con chat non vuota → la vecchia è in `summaries`, quella aperta è vuota;
    - `deleteCurrent` → apre la più recente rimasta;
    - `settings` salvate al cambio di modello e dello switch;
  - **testi:** `L` completa in it e en.
- [ ] **Step 2–4:** implementare, test verdi.
  - `LLMChatPlugin.handle`:
    - `context` → `apply`;
    - `project` → `switchProject`;
    - `activate`/`deactivate` → `active`;
    - altro → `unsupported`.
  - `send` usa `host.askLanguageModelAnswer(…, options: DTHubLLMOptions(maxTokens: 4096, timeout: 600), history:)` e `host.contribute`.
- [ ] **Step 5: Commit** — `feat(llm-chat): stato della tab, invio e azioni`.

### Task 10: Vista, README, elenco dei plug-in

**Files:** Create `Sources/LLMChat/LLMChatView.swift`, `Plugins/LLMChat/README.md`. Modify `Plugins/README.md` (sei plug-in: tabella, link di download `LLMChat.dthubplugin.zip`, frase «keep their state per project»), `README.md` alla radice se elenca i plug-in.

- [ ] **Step 1: Vista** secondo la spec §6.1:
  - barra con Modello, Immagini (nota quando è disattivato), Nuova chat e menu Chat (Rinomina con un `alert` con `TextField`, Elimina con `confirmationDialog`);
  - messaggi in `ScrollViewReader` che scende all'ultimo;
  - campo `TextField(axis: .vertical)` con `lineLimit(1...6)`: Invio manda, ⇧Invio va a capo (`onKeyPress`);
  - pulsante del comando, pulsante di invio;
  - riga «Sta scrivendo…» con Annulla;
  - avvisi di `blocker` al posto del campo.
  - Componenti di `DTHubDesign` come Batch plus.
- [ ] **Step 2: Build** — `swift build` del plug-in; `Scripts/build.sh /tmp/out` produce `LLMChat.dthubplugin`.
- [ ] **Step 3: README** del plug-in (inglese, come quello di Batch plus):
  - cosa fa;
  - il comando `<SEND>`/`<INVIA>` e il pulsante;
  - cosa può cambiare e cosa no (niente RUN, modello, avanzate);
  - immagini e switch;
  - archivio per progetto;
  - requisiti (DT Hub 0.1.6 o successiva, un LLM nella cartella dei modelli; per le immagini un modello con visione).
  - Il testo non dice che DT Hub «sostituisce» l'interfaccia di Draw Things.
- [ ] **Step 4: Elenco** — riga nella tabella di `Plugins/README.md` («**All families**» — «Chat with a local LLM about the prompt and the settings; with the `<SEND>` command it writes the prompt, the parameters, the strength or a pipeline.»), link di download, conteggio dei plug-in.
- [ ] **Step 5: Suite completa.**
  - `cd Packages && swift test`;
  - `cd PluginKit && swift test`;
  - `swift test` in `Plugins/LLMChat` e in Batch plus;
  - `xcodebuild … build`.
- [ ] **Step 6: Prove a mano** (lista all'utente): spec §9.
- [ ] **Step 7: Commit** — `feat(llm-chat): vista, README e elenco dei plug-in`.
- [ ] **Step 8: Messaggio finale** (briefing §6):
  - cosa provare;
  - **«Decisioni che ho preso»**, ognuna col suo costo se sbagliata:
    - nome e simbolo;
    - forza senza verde acqua e senza conflitti;
    - nessun nuovo tentativo automatico su JSON non valido;
    - budget di 24 000 caratteri;
    - modello e switch per progetto;
    - `maxTokens` 4096;
    - tolleranza ```` ```json ````;
  - **«Rinviati»** (spec §10);
  - via libera prima di unire, push o release. La release deve includere `LLMChat.dthubplugin.zip` e alzare la versione dell'app, perché il plug-in richiede «0.1.6 o successiva»: se la versione scelta è un'altra, aggiornare il testo.

---

## Autorevisione

- **Copertura:**
  - spec §3 → Task 1, 5;
  - §4 → Task 2, 3, 5;
  - §5 → Task 4, 5;
  - §6.1 → Task 10;
  - §6.2 → Task 8, 9;
  - §6.3 → Task 8;
  - §6.4 → Task 7, 9;
  - §6.5 → Task 6, 9;
  - §6.6 → Task 6, 9;
  - §7 → Task 9;
  - §8 → tutti;
  - §9 → Task 10.
- **Tipi:**
  - `LanguageModelTurn` (Task 2) → chiusura del registry (Task 3);
  - `DTHubLLMTurn` (Task 5) → `HistoryWindow` (Task 8) e `Ask` (Task 9);
  - `DTHubContext.prompt` (Task 5) → `blocker` e `SystemPrompt` (Task 8–9);
  - `ActionBlock` (Task 7) → `send` (Task 9).
- **Ordine:** la Parte A va unita prima della Parte B, o insieme nello stesso ramo; il plug-in compila solo con il kit del Task 5.
