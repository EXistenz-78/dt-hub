# LLM da un server LM Studio: sorgente alternativa — disegno

Data: 3 novembre 2026. Stato: da approvare (spec), poi piano.

## Obiettivo

Oggi gli LLM di DT Hub girano solo in casa, su MLX, da una cartella di modelli in formato Hugging Face. Chi ha già LM Studio con i suoi modelli deve scaricarli e tenerli due volte, e su un Mac con poca RAM non può usare i modelli che LM Studio carica senza problemi. Si aggiunge una **seconda sorgente**: il server compatibile OpenAI di LM Studio, in esecuzione sullo stesso Mac. L'utente sceglie una delle due, come già sceglie tra «server Draw Things» e «gRPCServerCLI avviato da DT Hub».

## Cosa dice l'utente (requisiti)

1. **Due metodi alternativi**: «Cartella (MLX)», il metodo attuale, e «Server LM Studio». Una sola sorgente attiva alla volta.
2. Il sistema attuale **resta il più possibile inalterato**: stessi file, stessi test, stesso comportamento per chi non cambia nulla.
3. Il server è **sempre locale** (stesso computer). Indirizzo di partenza: `http://localhost:1235/v1`.
4. Le richieste dell'LLM (Enhance, Generate, plug-in, chat) vanno al server OpenAI con le stesse opzioni di oggi.

Supposizione (da correggere se sbagliata): il caso d'uso principale è un Mac con poca RAM, dove LM Studio regge modelli più grandi di quelli che l'app riesce a caricare. Lo scopo non è sostituire MLX ma dare un'alternativa a chi ha già i suoi modelli.

## Fuori ambito (prima versione)

- Il prompt upsampler di FLUX.3 (PUP) tramite server: legge `system_prompts.json` da una cartella.
- La chiave API e gli host non locali (resta valida la frase del README «nulla di tuo esce dal Mac»).
- Lo streaming della risposta.
- Caricare o scaricare modelli in LM Studio dall'app.
- Altri server (Ollama, llama.cpp): il protocollo è lo stesso e potrebbero funzionare cambiando la porta, ma non sono provati né promessi.

## Cosa si è verificato sul server (3 novembre 2026, sola lettura)

- `GET /v1/models` elenca tutti i modelli, **embedding compresi** (`text-embedding-nomic-embed-text-v1.5`). Per ogni modello dà solo `id`, `object`, `owned_by`: nessuna informazione su visione o stato.
- `GET /api/v0/models` (API nativa di LM Studio) aggiunge `type` (visti: `llm`, `embeddings`), `state` (`loaded` / `not-loaded`), `publisher`, `compatibility_type`, `quantization`. Il valore per i modelli con visione è `vlm` (visto poi su Gemma 4, vedi sotto).
- `POST /v1/chat/completions` (3 novembre 2026): con nessun modello di chat caricato risponde HTTP 400 con `{"error":{"message":"No models loaded. Please load a model in the developer page or use the 'lms load' command.","type":"invalid_request_error",…}}`, anche se `/v1/models` elenca modelli. Quindi la forma d'errore è `error.message` e **il caricamento alla prima richiesta può essere spento in LM Studio**: l'errore di LM Studio va mostrato com'è. Per lo stesso motivo `top_k` e le immagini non si sono potuti provare.
- Verificato con il test dal vivo (3 novembre 2026, `google/gemma-4-e2b`): `type` è `vlm` per i modelli con visione; `top_k` è accettato (HTTP 200); un'immagine come parte `image_url` con data URL JPEG viene letta (risposta «Red» a un'immagine rossa); la prima richiesta carica il modello e può durare 30 s. Un modello che ragiona (Gemma 4) mette il testo in `reasoning_content` e lascia `content` vuoto se i token finiscono prima: l'app lo dice nell'errore.

## Scelte

### 1. Impostazione di sorgente

`LanguageModelSettings` ottiene:

- `backend: LanguageModelBackend` (`folder` | `lmStudio`), predefinito `folder`;
- `serverURL: String`, predefinito `http://localhost:1235/v1`;
- `serverVisionModels: Set<String>`: i modelli per cui l'utente ha acceso «legge le immagini» perché il server non lo dice.

Il decoder delle impostazioni è già indulgente (un campo mancante prende il valore predefinito): le impostazioni salvate prima di questa versione si leggono come `folder`. Nessuna migrazione.

### 2. Il modello del server è un `LanguageModelDescriptor`

Nessun campo nuovo nel descrittore. Un modello del server diventa `LanguageModelDescriptor(path: "lmstudio://" + id, name: id, sizeBytes: 0, supportsImages: …)`. Il prefisso `lmstudio://` evita che `path` sembri una cartella relativa vera (il profilo la legge con `URL(fileURLWithPath:)`). `supportsImages` è vero se `type == "vlm"` (API nativa) oppure se l'id è in `serverVisionModels`.

Conseguenze, tutte senza codice nuovo:

- il controllo della memoria passa da solo (`sizeBytes` 0 × 1,2 = 0);
- router, assegnazioni per famiglia e uso, plug-in per nome e prompt buttons restano identici;
- le assegnazioni dei modelli in cartella restano nel file (`reconciled` conserva «le voci degli LLM assenti»); tornando a «Cartella» ritrovano le loro impostazioni;
- il profilo del modello (`LanguageModelProfile.load(folder:)`) legge file che per un modello del server non esistono: restituisce nil per tutti (`system_prompt*.txt`, `generation_config.json`, `system_prompts.json`) e quindi **nessun PUP**. Si verifica nel piano che nessun chiamante supponga che `path` sia una cartella.

Rischio dichiarato: se un giorno il server e la cartella hanno un modello con lo stesso nome, le assegnazioni per nome si confondono. Con una sola sorgente alla volta non può succedere.

### 3. `OpenAICompatibleService`

In `Packages/Sources/HubCore/Language/`, solo `URLSession`, nessuna dipendenza nuova; implementa `LanguageModelService`. (`LLMBridge` resta «l'unico modulo che conosce MLX»; qui non c'è nulla di MLX.)

- `load(model)`: ricorda l'id del modello. Non scarica né carica nulla in LM Studio (il server carica il modello alla prima richiesta). Controlla solo che l'id sia ancora nell'elenco.
- `unload()`: dimentica l'id. Non chiede niente al server.
- `respond(to:images:options:history:)`: `POST {serverURL}/chat/completions`, `stream: false`.
  - messaggi: `system` (se presente), poi la cronologia (`user`/`assistant`), poi l'ultimo `user`;
  - immagini: nell'ultimo messaggio come parti `image_url` con data URL JPEG in base64. Il lato lungo si porta a un massimo (valore iniziale 1536 px, qualità 0,85) per non spedire PNG da decine di MB; il valore si conferma con la prova dal vivo;
  - opzioni: `temperature`, `top_p`, `max_tokens`, `presence_penalty` come in OpenAI; `top_k` si invia; `thinking` nella prima versione è ignorato. I valori predefiniti sono quelli di oggi (temperatura 0,6, 1024 token);
  - risposta: `choices[0].message.content`. Un eventuale blocco `<think>…</think>` iniziale si toglie. Contenuto vuoto → `generationFailed`.
- Timeout: lungo (300 s per la richiesta, 5 s per l'elenco dei modelli), perché la prima richiesta può caricare il modello.
- Errori: nessun caso nuovo in `LanguageModelError`. Server non raggiungibile → `loadFailed("…")` con un testo chiaro («LM Studio non risponde su localhost:1235. È acceso, con il server avviato?»); modello assente → `modelNotFound`; HTTP non 2xx → `generationFailed` con il messaggio del server; immagine su un modello senza visione → `imagesNotSupported` (già controllato dal gestore).

### 4. Elenco dei modelli del server

Un tipo `ServerModelList` (HubCore) interroga prima `/api/v0/models` (derivando l'indirizzo da `serverURL`: stessa origine, percorso `/api/v0/models`); se risponde, tiene `type` `llm` e `vlm` e scarta il resto. Se non risponde, ripiega su `/v1/models` e scarta gli id che contengono `embed`. L'elenco è una cache nel gestore, aggiornata con `refreshServerModels()`: all'avvio dell'app con la sorgente `lmStudio`, quando l'app torna in primo piano, all'apertura delle preferenze e al cambio di sorgente, di indirizzo o di un interruttore «legge le immagini». I pulsanti dei prompt risolvono il modello in modo sincrono (`model(for:family:)`), quindi la cache deve essere già calda: per questo l'aggiornamento al ritorno in primo piano. Se il server è spento l'elenco è vuoto e l'errore sopra spiega perché.

Validazione dell'indirizzo: schema `http`, host `localhost`, `127.0.0.1` o `[::1]`, porta presente. Qualunque altro host non si salva e la preferenza lo dice.

### 5. Il gestore sceglie il servizio

`LanguageModelManager` riceve un secondo servizio (`serverService`) e una fonte per l'elenco (`serverModels`). Nulla cambia per `backend == .folder`.

- `availableModels()`: con `folder`, lo scanner (come oggi); con `lmStudio`, la cache dei modelli del server.
- `ensureLoaded` e `ask` usano il servizio della sorgente attiva. Il controllo memoria resta nel codice ma passa da solo. `releaseImageModel` **resta com'è**: LM Studio carica il modello alla prima richiesta, e fermare il server di Draw Things gestito da DT Hub libera la RAM proprio per quel caricamento (stessa impostazione «Libera il modello immagine…» di oggi).
- Cambio di sorgente: `unload()` del servizio che era attivo, `loaded = nil`, stato `unloaded`, ricarica dell'elenco.
- `scheduleIdleUnload` con `lmStudio` non programma nulla (non c'è memoria nostra da liberare).
- `prepareForRun` con `lmStudio`: non fa nulla.

### 6. Preferenze › LLM

Come in Preferences › Draw Things: in alto un selettore «Sorgente» (`Cartella (MLX)` / `Server LM Studio`).

- `Cartella (MLX)`: la schermata di oggi, identica.
- `Server LM Studio`: campo indirizzo con pulsante «Prova» (mostra «Connesso, N modelli» o l'errore), elenco dei modelli con famiglia e uso (la stessa riga delle assegnazioni di oggi, senza dimensione), e per i modelli non riconosciuti come visione l'interruttore «Legge le immagini». Della sezione memoria resta solo «Libera il modello immagine quando si usa il modello linguistico»; «Libera al RUN» e il tempo di inattività non si mostrano, perché riguardano una memoria che non è di DT Hub. La domanda di prova e la libreria dei prompt (Enhance/Generate) restano.
- Nuove stringhe in `Localizable.xcstrings`, inglese e italiano.

## Dati e file toccati

Nuovi: `LanguageModelBackend` (in `LanguageModelSettings.swift`), `OpenAICompatibleService.swift`, `ServerModelList.swift` in `HubCore/Language/`; test in `Packages/Tests/HubCoreTests/`.

Modificati: `LanguageModelSettings.swift` (3 campi), `LanguageModelManager.swift` (secondo servizio, scelta in `availableModels`, `ensureLoaded`, `ask`, idle, `prepareForRun`), `App/DTHubApp.swift` (costruzione), `App/Preferences/LanguagePreferencesView.swift` (selettore e sezione server), `App/Localizable.xcstrings`, `README.md` (sezione «The local LLM»).

Non toccati: `LLMBridge/`, `LanguageModelScanner`, `LanguageModelRouter`, `LanguageModelAssignment`, i plug-in, `PluginKit`.

## Errori e casi limite

- Server spento all'avvio con `lmStudio` attivo: l'elenco è vuoto, le assegnazioni restano, Enhance/Generate mostrano l'errore chiaro. Non si cambia sorgente da soli.
- Il modello assegnato non c'è più nell'elenco (rimosso da LM Studio): `modelNotFound` con il nome.
- Il Mac è lo stesso di Draw Things: LM Studio e il server di Draw Things possono competere per la RAM. DT Hub può liberare il modello immagine solo se il server lo avvia lui (come oggi), e non può né misurare né liberare la memoria di LM Studio; la preferenza lo dice in una riga.
- Risposta che non è JSON o senza `choices`: `generationFailed` con le prime 200 lettere del corpo.
- Annullamento (RUN premuto durante una richiesta): la richiesta `URLSession` si annulla con il task; il gestore lancia `interrupted` come oggi.

## Test

- `OpenAICompatibleService` con un `URLProtocol` finto: forma del corpo (system, cronologia, immagine come data URL, opzioni), lettura di `content`, rimozione di `<think>`, errori HTTP, server spento, contenuto vuoto.
- `ServerModelList`: risposta nativa (`llm`, `vlm`, `embeddings`), ripiego su `/v1/models` con filtro `embed`, server spento.
- Validazione dell'indirizzo: accettati `localhost`, `127.0.0.1`, `[::1]`; respinti altri host e schemi.
- `LanguageModelManager` con due servizi finti: la sorgente decide il servizio e l'elenco; il cambio scarica il servizio vecchio; con `lmStudio` il controllo memoria non blocca e l'idle non si programma; con `folder` i test di oggi passano **senza modifiche**.
- `LanguageModelSettings`: un JSON vecchio (senza i nuovi campi) si legge come `folder`.
- Test dal vivo (`DTHUB_LIVE_SERVER=http://localhost:1235/v1`, come `DTHUB_LIVE_LLM`): elenco, una domanda di solo testo, una con immagine se esiste un modello con visione.
- Prova a mano nell'app: cambio di sorgente avanti e indietro, Enhance e Generate dal server, chat dell'AI Assistant, un plug-in.

## Da decidere nel piano (non blocca la spec)

- Il lato lungo massimo e la qualità JPEG delle immagini, dopo la prova dal vivo.
- Il nome del tipo `vlm` e se `top_k` è accettato, dopo la prova dal vivo.
- Che nessun chiamante di `LanguageModelProfile.load` supponga che `path` sia una cartella reale.
