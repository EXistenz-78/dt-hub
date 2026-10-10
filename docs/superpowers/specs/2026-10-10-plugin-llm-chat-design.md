# Plug-in «LLM Chat» e tre aggiunte al contratto — Design

Data: 10 ottobre 2026. Stato: approvato in chat dall'utente; da implementare in una sessione locale con Xcode e Swift.
Base: `origin/main` **0.1.5** (`5c6bf54`): «Migliora con immagini», «I2I/T2I», «pipeline-passaggi-con-valori» e Batch plus già uniti.

## 1. Obiettivo

Un plug-in per **chattare con un LLM locale** dentro DT Hub: correggere un prompt, discutere i parametri, descrivere l'immagine di partenza e le Moodboard, preparare varianti. Su comando esplicito l'LLM **applica** prompt, parametri, forza o una pipeline. **RUN lo preme sempre l'utente.**

Servono tre aggiunte piccole e compatibili al contratto 1:

1. il contesto porta **prompt, prompt negativo e forza** dell'immagine di partenza;
2. il messaggio `llm` accetta lo **storico della conversazione** (`messages`);
3. `contribute` accetta la **forza** (`strength`).

## 2. Decisioni (dell'utente, approvate in chat il 9–10 ottobre)

- **Modello scelto a mano** nel plug-in, come in Character Sheet. Si passa per nome (`model`), quindi le assegnazioni di Preferenze › LLM non contano.
- **Switch «Immagini»**: acceso manda con il messaggio l'immagine di partenza e le Moodboard accese, numerate; spento manda solo il testo. Ricorda l'ultima scelta; la prima volta è acceso. È disattivato se il modello scelto non legge immagini.
- **Azioni solo con `<INVIA>` o `<SEND>`**, scritti esattamente così (maiuscole e parentesi angolari), in qualsiasi punto del messaggio e in qualsiasi lingua dell'app. Due protezioni:
  - la regola nel system prompt;
  - un **controllo nel codice**: senza il codice nel messaggio dell'utente, qualsiasi blocco di azioni nella risposta viene ignorato.
- **Pulsante `<INVIA>`** (`<SEND>` con l'app in inglese): aggiunge il codice in fondo al testo che si sta scrivendo; poi si preme Invio.
- **Applicazione automatica**: nessuna anteprima né conferma. Dopo l'invio compare in chat una riga con cosa è stato inviato.
- **Azioni possibili**: prompt e negativo; parametri; peso dei LoRA; forza; pipeline (varianti di prompt, prove su un parametro, combinazioni, catene). Al massimo **20 passaggi**.
- **Escluse**: avviare RUN, cambiare modello, impostazioni avanzate, togliere Moodboard o immagine di partenza, preset.
- **Archivio per progetto**: «Nuova chat» archivia quella in corso; elenco con apri, rinomina, elimina.
- **Rinviati**: «Annulla ultimo invio», esportazione in Markdown, streaming, ciclo sui risultati generati.

## 3. Contratto: contesto

`PluginContext` (HubKit, `PluginMessages.swift`) guadagna:

```swift
public var prompt: String?           // the Generation tab's prompt; "" when empty; absent from an older app
public var negativePrompt: String?
/// The strength the start image is used with (0…1), as the Control tab shows it; absent without a start image.
public var strength: Double?
```

- `PluginRegistry` guadagna due chiusure lette a ogni invio del contesto, come `startImagePath`:
  - `@ObservationIgnored public var currentPrompts: (@MainActor () -> (prompt: String, negativePrompt: String))?`
  - `@ObservationIgnored public var startImageStrength: (@MainActor () -> Double?)?`
- `DTHubApp` le collega:
  - prompt e negativo vengono da `generation.prompt` / `generation.negativePrompt`;
  - la forza è `nil` senza immagine di partenza, altrimenti `control.inputs.effectiveStrength(editModel: generation.isEditModel(in: connection), hasMargins: control.hasMargins(canvasWidth:canvasHeight:))`, lo stesso calcolo di `ImageCard.strengthRow`.
- `prompt` e `negativePrompt` vanno **sempre** (anche vuoti) quando l'app ha la chiusura. La loro presenza dice al plug-in che l'app è abbastanza nuova.
- Nessun invio in più: il contesto parte quando parte oggi (cambio di modello o parametri, tab del plug-in mostrata).

**Kit** (`DTHubContext`): `prompt: String?`, `negativePrompt: String?`, `strength: Double?`, letti con tolleranza (`try?`, un valore sbagliato è `nil` e non fa perdere il resto).

## 4. Contratto: storico nel messaggio `llm`

- **Messaggio:** `{"type":"llm","prompt","images","system","model","options","messages":[{"role":"user"|"assistant","text"}]}`.
  - `messages` sono i turni **precedenti**, dal più vecchio; `prompt` è il messaggio nuovo; `images` vanno col messaggio nuovo.
  - Una voce con un ruolo diverso o senza `text` stringa viene saltata.
  - Senza `messages` tutto è come oggi.
- **HubKit:** `public struct LanguageModelTurn: Equatable, Sendable { public enum Role: String, Sendable { case user, assistant }; public var role: Role; public var text: String }`.
- **`LanguageModelService`:**
  - il requisito diventa `respond(to:images:options:history: [LanguageModelTurn])`;
  - un'estensione tiene `respond(to:images:options:)` (con `history: []`), così gli altri chiamanti non cambiano.
- **`MLXLanguageModelService`:**
  - con `history` vuoto, come oggi;
  - altrimenti `ChatSession(container, instructions:, history: history.map { $0.role == .user ? .user($0.text) : .assistant($0.text) }, generateParameters:, additionalContext:)`, verificato in mlx-swift-lm 3.32.3 (`ChatSession.init(_: ModelContainer, instructions:, history:, …)`), poi `respond(to: prompt, role: .user, images:…)` come oggi.
- **`LanguageModelManager.respond(to:images:options:modelNamed:history:)`:**
  - `history` con default `[]`, passato fino al servizio;
  - il controllo «immagini senza visione» resta com'è.
- **`PluginRegistry.askLanguageModel`:** la chiusura riceve anche `history: [LanguageModelTurn]`; `askModel` legge `messages`.
- **Kit:**
  - `public struct DTHubLLMTurn: Equatable, Sendable { public enum Role: String, Sendable { case user, assistant }; public var role: Role; public var text: String }`;
  - `askLanguageModel`/`askLanguageModelAnswer(…, history: [DTHubLLMTurn] = [])`;
  - `llmMessage` aggiunge `messages` solo se non vuoto.

## 5. Contratto: forza in `contribute`

- **`PluginContribution`:** `public var strength: Double?`, letto da `contribute.strength` (numero) e riportato in 0…1. È incluso in `isEmpty`.
- **`ContributionTarget`:** `func setStrength(_ value: Double)`. `GenerationController` chiama `control.setStrength(value)`.
- **`ContributionStore.receive`:**
  - la forza si applica **dopo** l'eventuale `startImage` dello stesso messaggio;
  - si applica solo se c'è un'immagine di partenza (`target.startImageID != nil`); altrimenti va in `problems`: `"strength: there is no start image."`.
- **Niente verde acqua e niente conflitti per la forza:** vince l'ultimo che scrive. È una scelta di semplicità: la forza sta in Control, non tra i campi della scheda che si colorano.
- **README del kit:** `strength` tra le chiavi di `contribute`; `prompt`, `negativePrompt`, `strength` nel contesto; `messages` nel messaggio `llm`.

## 6. Il plug-in

- **Identità:**
  - nome «LLM Chat», id `com.exiztenz.dthub.llmchat`, versione 1.0;
  - simbolo `bubble.left.and.text.bubble.right`, tutte le famiglie (`families: nil`);
  - cartella `Plugins/LLMChat`, bundle `LLMChat.dthubplugin`, entry `LLMChatEntry`, alias dei moduli `LLMChatKit` / `LLMChatDesign`.
  - Pacchetto e `Scripts/build.sh` come Batch plus.

### 6.1 Interfaccia

- **Barra in alto** (`dsPanel`):
  - menu **Modello**: tutti gli LLM di `languageModels`, testo e visione; la scelta resta finché il modello è nella cartella, altrimenti il primo;
  - switch **Immagini** (`DSCheckboxToggleStyle`), disattivato con la nota «Il modello non legge immagini» se `supportsImages` è falso;
  - pulsante **Nuova chat**;
  - menu **Chat**: le chat del progetto, la più recente in cima, con titolo e data. Scegliendone una la si apre. In fondo: «Rinomina…» e «Elimina…» per quella aperta.
- **Messaggi** (scroll, si porta in fondo a ogni messaggio nuovo):
  - **utente** a destra; se il messaggio aveva immagini, sotto «2 immagini allegate»;
  - **LLM** a sinistra, testo selezionabile, **senza** il blocco di azioni;
  - **note** del plug-in a tutta larghezza, in piccolo:
    - azione inviata in `DS.accent`;
    - errore in rosso;
    - azione ignorata in grigio.
- **Campo di testo** multilinea (`TextField(axis: .vertical)`, da 1 a 6 righe):
  - Invio manda, ⇧Invio va a capo;
  - pulsante `<INVIA>`/`<SEND>`;
  - pulsante di invio (icona `paperplane`, aiuto «Manda il messaggio»).
- **Durante l'attesa:**
  - riga «Sta scrivendo…» con **Annulla**, che smette di aspettare (la risposta, se arriva, viene scartata; il modello finisce comunque il suo lavoro nell'app);
  - campo e pulsanti disattivati.
- **Avvisi al posto del campo:**
  - plug-in spento per il lavoro in corso: «Accendi LLM Chat dal menu dei plug-in»;
  - app senza `prompt` nel contesto: «Aggiorna DT Hub (0.1.6 o successiva)»;
  - nessun LLM: «Nessun LLM nella cartella dei modelli (Preferenze › LLM)».

### 6.2 Un messaggio

1. Testo vuoto (spazi a parte) → niente.
2. **Comando:** `gate = text.contains("<INVIA>") || text.contains("<SEND>")`.
3. **Immagini**, solo se switch acceso e modello con visione: `[startImage] + moodboard` del contesto, nell'ordine. Il testo mandato all'LLM inizia con il blocco di «Migliora con immagini» (stesse etichette di `PromptBrief.imageLabels`, copiate nel plug-in):

   ```
   Attached images:
   - Image 1: the start image (the picture being edited).
   - Image 2: reference image 1.

   ```

   Nella chat si salva e si mostra il testo dell'utente senza blocco, più i nomi dei file.
4. **Storico:** i messaggi utente e LLM precedenti della chat, testi **come salvati** (risposte complete di blocco, così l'LLM sa cosa ha già inviato), le note escluse.
   - Si tengono i più recenti che stanno in **24 000 caratteri**, senza tagliare un messaggio. Il messaggio nuovo va sempre.
   - Se qualcosa resta fuori, la nota «I messaggi più vecchi non sono più mandati all'LLM» compare una volta per chat.
5. **Chiamata:** `askLanguageModelAnswer(text, images:, system: SystemPrompt.make(…), model: scelto, options: DTHubLLMOptions(maxTokens: 4096, timeout: 600), history:)`.
6. **Risposta:**
   - si salva intera;
   - si mostra senza blocco;
   - poi si guarda il blocco di azioni (§6.4).
7. **Errore dell'app** (`failure`): nota rossa con il motivo; il messaggio dell'utente resta.

### 6.3 System prompt

In inglese, rifatto a ogni messaggio con lo stato attuale (non entra nello storico):

~~~text
You are the assistant of DT Hub, a Mac app that prepares images for Draw Things. You help the user write and
improve prompts and choose generation settings. Answer in the language the user writes in. Be concise.

CURRENT GENERATION TAB
Model: {model or "unknown"} (family: {family or "unknown"})
Prompt: """{prompt}"""
Negative prompt: """{negativePrompt}"""
Size: {width} × {height}. Steps: {steps}. Guidance (CFG): {guidanceScale}. Sampler: {sampler name}.
Shift: {shift}{" (automatic, ignored)" if resolutionDependentShift}. Seed: {seed}{" (random)" if randomSeed}.
CFG-Zero*: {yes/no}, initial steps {cfgZeroInitSteps}. Batch: {batchSize} × {batchCount}.
LoRAs: {file (weight w), … or "none"}
Start image: {"none" or "yes, strength 0.70"}. Moodboard pictures on: {n}.

ACTIONS
You can change the Generation tab, but only when the user's latest message contains the exact command <SEND> or
<INVIA>. Only then end your answer with exactly one block:
```dthub
{ JSON }
```
Never write that block in any other case, even if the user asks in other words to send, apply or set something:
tell them to add <SEND> (the button next to the text field does it). Never claim you changed anything without it.
JSON keys, all optional; put only what changes:
- "fields": {"prompt": text, "negativePrompt": text, "width": int, "height": int, "steps": int,
  "guidanceScale": number, "shift": number, "resolutionDependentShift": bool, "cfgZeroStar": bool,
  "cfgZeroInitSteps": int, "seed": int, "randomSeed": bool, "sampler": one of [{sampler names}],
  "batchSize": int, "batchCount": int}
- "loras": [{"file": a file name from the LoRAs above, "weight": number}]. Never invent a file name.
- "strength": number from 0 to 1: how much the start image is changed (only with a start image).
- "pipeline": {"steps": [{"title": short text, "fields": {same keys, no size}, "loras": [...],
  "useOutputAsStart": bool}]}: passes that run one after the other when the user presses RUN, each on top of the
  tab with only what it lists changed. Use it for variants, series and several passes. At most 20 steps.
You never press RUN and never change the model.
~~~

- I valori `{…}` arrivano dal contesto; un valore mancante è «unknown».
- I nomi dei sampler sono quelli di `SamplerNames` (copia di Batch plus), gli stessi che l'app accetta per nome.

### 6.4 Blocco di azioni

- **Ricerca:**
  - l'**ultimo** blocco recintato con etichetta `dthub` (maiuscole indifferenti);
  - se non c'è, l'ultimo blocco ```` ```json ```` il cui oggetto ha almeno una chiave tra `fields`, `loras`, `strength`, `pipeline`. È una tolleranza per i modelli piccoli che sbagliano l'etichetta.
- **Senza comando (`gate` falso):**
  - un blocco trovato non si usa;
  - nota grigia «Azione ignorata: il messaggio non conteneva <INVIA>».
- **Con il comando:**
  - **nessun blocco:** nota grigia «Nessuna azione nella risposta»;
  - **JSON non valido:** nota rossa «Il blocco di azioni non è valido: …»; nessun invio e nessun nuovo tentativo automatico (basta riscrivere `<INVIA>`);
  - **valido:** il plug-in costruisce il corpo di `contribute`:
    - **`fields`:** solo le chiavi elencate al §6.3; le altre si scartano;
    - **`loras`:** voci con `file` stringa; `weight` numero se c'è;
    - **`strength`:** numero;
    - **`pipeline`:**
      - **`steps` > 20:** nota rossa «La pipeline ha N passaggi: al massimo 20» e **niente** viene inviato;
      - **nome:** «LLM Chat»;
      - **titolo** vuoto → «Passaggio k» / «Pass k»;
      - **per passo:** solo `title`, `fields` (senza `width`/`height`), `loras`, `useOutputAsStart`;
    - **corpo vuoto:** nota grigia «Nessuna azione nella risposta»;
    - **altrimenti:** `host.contribute(body)`, poi una nota con l'esito:
      - «Inviati: prompt, negativo, passi, guidance, sampler, LoRA (2), forza, pipeline (5 passaggi).», con i nomi in italiano o inglese;
      - con `conflicts` > 0, in aggiunta: «N conflitti in attesa nell'app.»;
      - `problems` dell'app elencati in rosso;
      - `error` → nota rossa con il testo.
- **Copia locale:** dopo un invio riuscito, il plug-in aggiorna la sua copia di prompt e parametri con i valori inviati, perché il contesto nuovo arriva solo al prossimo cambio di tab.

### 6.5 Archivio e stato

- Nella cartella del progetto (messaggio `project`):
  - `state.json`: `{"currentChat": uuid?, "model": name?, "includeImages": bool}`;
  - `chats/<uuid>.json`: `{"id","title","created","updated","messages":[{"id","role":"user"|"assistant"|"note","text","date","images":[nomi],"note":"action"|"error"|"ignored"|"info"}]}`.
- **Scrittura e lettura:**
  - scrittura atomica a ogni messaggio e a ogni modifica;
  - lettura tollerante: campi mancanti con il default, un file illeggibile si salta.
- **Prima del primo `project`:** tutto in memoria. L'app manda `project` subito dopo l'avvio; `adoptLegacy` non ha nulla da adottare.
- **Titolo:**
  - prima riga del primo messaggio dell'utente, senza `<INVIA>`/`<SEND>`, al massimo 40 caratteri, con «…» se tagliata;
  - senza testo: «Chat del 10 ott, 14:32»;
  - «Rinomina…» lo sostituisce.
- **«Nuova chat»:** se quella aperta ha messaggi resta nell'elenco; se ne apre una vuota, che diventa un file solo al primo messaggio.
- **«Elimina…»:** chiede conferma, cancella il file e apre la più recente rimasta oppure una vuota.
- **Riaprire una chat:**
  - si vede tutto;
  - all'LLM va la finestra del §6.2;
  - le immagini vecchie non tornano (si salvano solo i nomi): con lo switch acceso vanno quelle attuali di Control.

### 6.6 Testi

- Tabella `L` it/en come in Batch plus.
- Lingua dell'app da `Locale.preferredLanguages`: `<INVIA>` per l'italiano, `<SEND>` per l'inglese.

## 7. Compatibilità

- **App vecchia con plug-in nuovo:**
  - il contesto non ha `prompt` → avviso «Aggiorna DT Hub»;
  - `messages` e `strength` verrebbero ignorati dall'app vecchia, ma il plug-in non ci arriva.
- **Plug-in vecchi con app nuova:** chiavi in più nel contesto, ignorate; nessun cambiamento.

## 8. Test

- **HubKitTests:**
  - `PluginContext` codifica `prompt`, `negativePrompt` e `strength`, e omette la forza quando è `nil`;
  - `PluginContribution` legge `strength` e lo riporta in 0…1; un testo è ignorato; `isEmpty` con la sola forza è falso.
- **HubCoreTests:**
  - **routing:** `messages` → la chiusura riceve i turni in ordine; voci sbagliate saltate; senza `messages` lo storico è vuoto;
  - **registry:** il contesto contiene prompt, negativo e forza delle chiusure;
  - **ContributionStore:** forza con immagine applicata; senza immagine c'è il problema; `startImage` + `strength` nello stesso messaggio → applicata;
  - **manager:** lo storico arriva al servizio (fake che lo registra);
  - test esistenti verdi con il nuovo parametro.
- **Kit:**
  - `DTHubContext` con e senza i tre campi; tipi sbagliati → `nil` senza perdere il resto;
  - `llmMessage` con storico ha `messages` nell'ordine; senza storico non ha la chiave.
- **Plug-in:**
  - `CommandGate`: entrambi i codici, minuscole che non valgono, codice dentro altro testo;
  - `ActionBlock`: blocco `dthub`, ripiego `json`, nessun blocco, JSON non valido, chiavi sconosciute scartate, `width`/`height` tolti dai passi, 21 passi rifiutati, corpo vuoto;
  - `HistoryWindow`: 24 000 caratteri, messaggio nuovo sempre, note escluse;
  - `SystemPrompt`: stato, nomi dei sampler, regola;
  - `ImageLabels`;
  - `ChatStore`: salva, carica, elenca, rinomina, elimina, cambio progetto, file illeggibile;
  - `ChatTitle`;
  - riassunto dell'invio;
  - tabelle `L` complete.

## 9. Da verificare a mano

- «rendi il prompt più cinematografico» → risposta senza azioni; poi `<INVIA>` → prompt cambiato in verde acqua e nota «Inviati: prompt».
- «applica» senza codice → nessuna modifica, l'LLM ricorda il pulsante.
- «scrivi 5 varianti <INVIA>» → pipeline di 5 passaggi sul pulsante RUN; RUN produce 5 immagini.
- «abbassa la forza a 0.5 <INVIA>» con immagine di partenza → la forza in Control è 50 %.
- Con lo switch acceso e un modello con visione: «descrivi l'immagine 1». Con un modello solo testo lo switch è spento e disattivato.
- Nuova chat, rinomina, riapri, elimina; cambio progetto → chat dell'altro progetto.

## 10. Fuori ambito

- Avviare RUN; ciclo sui risultati.
- Annulla ultimo invio; esportazione.
- Streaming.
- Elenco dei LoRA installati (l'LLM vede solo quelli sulla scheda).
- Impostazioni avanzate; forza per passaggio di pipeline.
