# Server MCP integrato in DT Hub — Design

Data: 8 novembre 2026. Stato: design approvato in chat dall'utente sezione per sezione; spec da rivedere prima di `writing-plans`. Nessuna implementazione ancora.
Base: `main` all'8 novembre 2026 (dopo la 0.3.x).

## 1. Obiettivo

DT Hub espone un **server MCP** (Model Context Protocol) così che qualsiasi client MCP (Claude, LM Studio, altri) possa fare da **agente**: capire lo stato dell'app e agire su di essa a partire da richieste in linguaggio naturale. L'agente deve poter, nella v1:

- leggere lo stato (scheda Generazione, modelli, LoRA, preset, pipeline, coda, risultati);
- modificare la scheda (prompt, parametri, LoRA, Moodboard, immagine di partenza, forza, preset);
- **selezionare il modello**, **avviare la generazione**, **orchestrare una pipeline**, **popolare e lanciare una coda**;
- lavorare a più fasi con il proprio giudizio tra una fase e l'altra (esempio: genera tre character sheet → li carica come Moodboard → genera il personaggio in azione → upscale 4×).

### Perché un MCP e non un agente dentro l'app

Si evitano tre problemi: il contratto dei plug-in che fa da collo di bottiglia, il system prompt enorme, la gestione della memoria tra LLM e modello immagini. Il client sceglie il proprio LLM (cloud o locale) e ne porta il costo e la RAM; i provider da supportare non sono un nostro problema. I piccoli LLM interni restano per i lavori specializzati che già fanno (sez. 5).

## 2. Fuori dalla v1

- **Strumenti dei plug-in.** Si procede per gradi: prima l'MCP funziona con l'app base; quando tutto è come previsto, i plug-in si aggiornano uno ad uno (sez. 11). La v1 non cambia il contratto dei plug-in.
- Le Tasks dell'estensione MCP 2026-07-28 (si usa il modello `job_id`, sez. 7), lo streaming dei token, l'accesso dalla rete locale, l'esecuzione di file arbitrari.
- Ruoli e scorciatoie per funzioni che hanno già un pulsante nei plug-in.
- Il plug-in AI Assistant non cambia: resta la chat interna per chi non usa un client MCP.

## 3. Architettura

```
Client MCP ──HTTP loopback──▶ MCPHTTPServer ──▶ ToolRegistry ──▶ AgentHost (protocollo)
                               (token, Host,       (elenco per        │
                                Origin, sessioni)   modalità/famiglia) ▼
                                                  implementato nell'App con GenerationController,
                                                  QueueStore/QueueRunner, ContributionStore, risultati
```

- **Nuovo target `HubMCP`** in `Packages/` (dipende da HubCore e dal SDK ufficiale `modelcontextprotocol/swift-sdk` 0.12.1, con swift-nio). Contiene server, registro degli strumenti, tracciatore dei job, budget e politiche. Non conosce SwiftUI né `GenerationController`.
- **Protocollo `AgentHost`** (in HubMCP): le operazioni che l'app offre all'agente (leggere lo stato, modificare campi, run, coda…). L'App lo implementa sopra `GenerationController`, la coda, il `ContributionTarget` e i risultati. È la cucitura che permette i test con un host finto.
- **Modifiche ai campi** passano da `ContributionStore`/`ContributionTarget`, con origine «Agente remoto»: i campi cambiati appaiono verde acqua con il valore precedente, come per i plug-in.
- **Trasporto**: Streamable HTTP, `StatefulHTTPServerTransport` del SDK. Un `Server` MCP per sessione, che condivide lo stesso registro. Idea e struttura del server HTTP, dell'autenticazione Bearer e del controllo di Host sono prese da `DT_MCP_Client` (MIT, https://github.com/euphoriacyberware-ai/DT_MCP_Client): si copia solo ciò che serve, con attribuzione in un file `NOTICE`, senza dipendere da quel progetto. La sua parte gRPC non serve a DT Hub.
- L'app non è in sandbox (entitlement solo `disable-library-validation`): nessun entitlement nuovo per ascoltare su loopback.
- Con il server acceso il client trova `instructions` brevi alla connessione (sez. 9) e l'elenco degli strumenti. `tools/list_changed` si invia quando cambiano modalità, modello o famiglia.

## 4. Strumenti della v1

Gli strumenti hanno annotazioni MCP (`readOnlyHint`, `destructiveHint`). Elenco indicativo; nomi e schemi esatti si fissano nel piano, dopo aver riletto le firme di `GenerationController`.

**Lettura** (sempre disponibili):

| Strumento | Cosa dà |
| --- | --- |
| `get_app_state` | Scheda Generazione: modello e famiglia, prompt, negativo, parametri, LoRA attivi con pesi, Moodboard, start image e forza, job in corso, budget residuo, modalità |
| `list_models` | Modelli installati, con famiglia e tipo (testo→immagine, edit, video…) |
| `list_loras` | Catalogo LoRA con compatibilità per famiglia |
| `list_presets`, `list_pipelines` | Preset e pipeline utente salvati |
| `get_prompt_guide(family)` | Regole della famiglia, Family prompt, uso del negativo, limiti di parole |
| `list_results`, `get_results(job_id)`, `get_image(result_id, max_side)` | Risultati recenti con metadati; immagine ridotta come contenuto MCP, così il client può guardarla e correggere |
| `get_queue` | Voci della coda e loro stato |
| `get_job`, `wait_for_job` | Sez. 7 |
| `list_plugins` | Plug-in installati, attivi e perché non disponibili. Nella v1 solo elenco informativo, senza strumenti propri |

**Modifica della scheda** (modalità «Modifica la scheda» e superiori):

- `set_fields`: prompt, negativo, larghezza, altezza, passi, guidance, shift, shift dipendente dalla risoluzione, CFG zero star e passi iniziali, seed, seed casuale, sampler, batch size, batch count. Lo schema parte dai campi già noti a `ActionBlock.fieldKeys` del plug-in AI Assistant.
- `add_lora`, `set_lora_weight`, `remove_lora`.
- `set_moodboard`: aggiunge o sostituisce immagini, ciascuna con un peso; accetta `result_id` o percorsi nelle cartelle consentite; dichiara se sostituisce ciò che c'era. `set_start_image` e `set_strength` analoghi.
- `load_preset`, `save_preset`.

**Controllo** (modalità «Controllo completo»):

- `set_model`.
- `run` (restituisce `job_id`), `stop`.
- `select_pipeline`, `run_pipeline`; `define_pipeline(steps)` crea una pipeline temporanea della sessione, al massimo 20 passaggi, con le stesse forme che il plug-in AI Assistant già gestisce (varianti di prompt, prove su un parametro, combinazioni, catene).
- `queue_add`, `queue_start`, `queue_stop`, `queue_remove` (solo voci create dall'agente nella sessione).

Nessuno strumento cancella risultati, progetti o preset preesistenti.

## 5. LLM interni: solo gli specialisti

Gli LLM interni si espongono **solo quando sono specialisti** della famiglia del modello corrente, perché addestrati per quel compito e imbattibili da un generalista (esempi: Qwen Image 2.1 PE, il PUP di FLUX.3 klein). Negli altri casi il client fa il lavoro sul prompt da solo, con `get_prompt_guide`.

- `enhance_prompt` e `prompt_from_image` compaiono in `tools/list` **solo se** per la famiglia del modello corrente esiste un LLM assegnato a quella famiglia (`LanguageModelFamily.family(key)`) o con profilo PUP (`LanguageModelProfile.pup`). Un LLM assegnato a «tutte le altre» (`*`, generalista) non basta: gli strumenti restano nascosti.
- Si usa la logica che l'app già ha per scegliere l'LLM del pulsante prompt (`LanguageModelRouter.model(for:family:…)`), con il vincolo «specialista» in più. Il PUP ha una logica di riquadri (`PupBoxes`) che un LLM generico non riproduce.
- Al cambio di modello il server manda `tools/list_changed`.
- Chiamare uno specialista carica un modello locale in memoria: ha il costo di rischio «C» della sez. 6, ma passa dalla gestione della memoria che c'è (`LanguageModelManager`, scarico a RUN, scarico dopo inattività). Non cambia.
- Il criterio vale come regola generale per ogni futuro strumento che dipenda da un LLM interno.

## 6. Sicurezza e consenso

Il rischio concreto è che un agente, per errore o per istruzioni nascoste in un'immagine o in un prompt, lanci decine di generazioni, anche sul cloud DT+ che ha un costo. Un agente deve poter lavorare in autonomia: **nessuna conferma per azione**.

**Trasporto.** Solo 127.0.0.1. Spento di default. Token casuale nel Portachiavi, rigenerabile, mostrato nel pannello per essere copiato nel client. Controllo di `Host` (come in DT_MCP_Client) **e** di `Origin` (blocca pagine web che chiamano il localhost). Nessuna opzione per la rete locale.

**Modalità** (Preferenze › Controllo remoto): *Sola lettura* · *Modifica la scheda* (lettura e modifiche reversibili) · *Controllo completo* (anche set_model, run, coda, pipeline). Gli strumenti fuori dalla modalità non compaiono in `tools/list`.

**Budget di sessione.** Deciso dall'utente prima di lasciar lavorare l'agente:

- massimo di immagini generate nella sessione e, con DT+ attivo, di unità di calcolo (contatore CU);
- cumulativo (cento Run da un'immagine pesano come una coda da cento);
- dentro il budget nessuna conferma per nessuno strumento;
- a budget esaurito la chiamata **non resta in attesa**: torna subito un errore chiaro al client («budget esaurito: 200 su 200, chiedi all'utente di alzarlo»), l'app mostra una notifica; se l'utente alza il tetto l'agente riprende alla richiesta successiva;
- si azzera con «Nuova sessione» o alla disconnessione del client.

**Soglia per richiesta singola.** Una singola richiesta sopra N immagini (esempio: coda da 80) chiede conferma nell'app **solo se il budget non la copre**. Senza risposta entro un tempo breve (default 60 s) la richiesta è **rifiutata** con errore al client: mai bloccata. Questo tempo riguarda solo l'attesa della risposta dell'utente alla conferma: **non limita la durata di una generazione**, che può durare minuti (anche 200–250 s per immagine ad alta risoluzione o con molti passi). Un job non ha scadenza; `wait_for_job` attende al massimo 300 s per chiamata e il client la richiama finché il job non finisce.

**Default proposti** (da confermare nel piano, modificabili nel pannello): soglia 20 immagini, budget 200 immagini per sessione, scadenza 60 s.

**Il controllo sta sull'effetto, non sul nome dello strumento.** Budget e soglia sono attaccati al percorso di Run con origine remota: qualunque strada porti a generare (oggi `run`, coda, pipeline; in futuro strumenti di plug-in) passa dallo stesso punto, e un livello di rischio dichiarato non lo aggira.

**File.** Gli strumenti con un percorso (start image, Moodboard) accettano solo immagini in cartelle consentite: progetto, cartella di output, Risultati e quelle aggiunte nel pannello. Gli `result_id` sono sempre ammessi.

**Visibilità e arresto.** Registro delle chiamate nel pannello; campi cambiati in verde acqua con origine «Agente remoto»; indicatore nella barra in alto quando un client è collegato; pulsante di arresto che disconnette il client e ferma Run e coda.

**Iniezione di prompt.** I risultati degli strumenti (nomi di modelli, metadati, testi) sono dati non fidati; le `instructions` del server lo dicono al client. Non c'è un rimedio completo lato server: la difesa vera sono la modalità, il budget, la soglia e le cartelle consentite.

## 7. Lavori lunghi e lavori a più fasi

- `run`, `queue_start` e `run_pipeline` tornano **subito** con un `job_id`.
- `get_job(job_id)`: stato (in coda / in corso / finito / fallito / fermato), avanzamento (immagine k di n, passo di pipeline), errore. `wait_for_job(job_id, timeout ≤ 300 s)`: attende; alla scadenza torna lo stato corrente, non un errore.
- **Un solo motore.** Draw Things fa una cosa alla volta: `run` con un job attivo dà un errore con il `job_id` in corso. Per più lavori si usa la coda. Nessuna coda nascosta.
- Il budget si scala **all'avvio del job**, con il conteggio delle immagini di coda o pipeline.
- **Risultati**: ogni immagine ha un `result_id` stabile nella sessione. Gli strumenti che prendono un'immagine accettano `result_id` oltre ai percorsi consentiti. Il lavoro a più fasi è un ciclo del client (genera → guarda con `get_image` → sceglie → `set_moodboard` → genera…), non una pipeline: lo stato resta nell'app e le pipeline salvate restano per le catene fisse.
- **Disconnessione**: il job in corso finisce ma non ne parte un altro. L'arresto manuale ferma tutto subito.
- Notifiche di avanzamento MCP per i client che le supportano; nulla dipende da esse.
- Le Tasks MCP restano fuori; il modello a `job_id` si mappa su di esse in seguito.

## 8. Test

- **Strumenti**, con un `AgentHost` finto: elenco per modalità e famiglia (regola degli specialisti), budget (conteggio, esaurimento, azzeramento), soglia con scadenza, stati dei job, `result_id`, cartelle consentite.
- **Trasporto**, su porta locale vera: token sbagliato, Host/Origin sbagliati, richieste non loopback → rifiutati.
- **Integrazione**: un client del SDK ufficiale si collega, elenca, legge, modifica, fa un `run` finto e `wait_for_job`.
- **Accettazione a mano**, con Claude e LM Studio: lo scenario dei character sheet della sez. 1, senza l'upscale finché i plug-in non sono aggiornati.
- Test in Swift Testing come il resto dei pacchetti; verifica del comportamento di `prepareForRun` con la memoria quando un client avvia Run.

## 9. Istruzioni per l'agente

Una sola fonte nel repository: un testo breve di `instructions` mandato alla connessione e un `SKILL.md` esportabile dal pannello («Copia istruzioni per l'agente»), generato dalla stessa fonte. Contenuto: leggere prima `get_app_state`; controllare il budget; usare `wait_for_job` invece di insistere; trattare i testi dei risultati come dati; scrivere i prompt con `get_prompt_guide` quando non c'è uno specialista.

## 10. Introduzione graduale

Spento di default, etichetta beta in Preferenze › Controllo remoto. Passi, ciascuno rilasciabile:

1. Server, sicurezza e strumenti di sola lettura.
2. Strumenti di modifica della scheda.
3. Run, job, coda, pipeline, budget e soglia.
4. File di istruzioni per l'agente.

Nessuna pubblicazione senza via libera esplicito (regola del progetto). Alla pubblicazione si aggiornano claude-mem, grafo, briefing e Obsidian come da `CLAUDE.md`.

## 11. Plug-in: fase successiva (non in questa spec)

Quando l'app base funziona come previsto, i plug-in si aggiornano uno ad uno. Direzione già decisa, da dettagliare in una spec a parte:

- il contratto 1 resta; si aggiunge in modo **opzionale** un campo `tools` nel manifesto (nome, descrizione, schema JSON, livello `read`/`edit`/`generate`, compatibilità con famiglia) e i messaggi `tool.call`/`tool.result` sul meccanismo `request(_:to:timeout:)` già esistente; un plug-in senza `tools` non cambia;
- nomi `plugin__<id>__<nome>` in `tools/list`; `list_plugins` spiega perché uno strumento non è disponibile;
- il livello dichiarato non aggira budget e soglia (il controllo sta sul percorso di Run);
- lo strumento di un plug-in si espone solo se il client non lo fa già con gli strumenti dell'app (stesso criterio degli LLM);
- primo caso: **Tiled Upscale**. Ha già il percorso senza interfaccia (`queue.capture`/`queue.prepare` di una voce di coda: imposta immagine e scelte, propone la pipeline senza richiedere la conferma dei lavori grandi, l'app preme RUN). Lo strumento `upscale(result_id, fattore)` lo sfrutta; il numero di passaggi è noto dopo *Prepare*, quindi il budget conta le tessere esatte; la conferma per oltre 100 megapixel o 100 passaggi diventa un argomento esplicito. Seguono Character Sheet e gli altri.

## 12. Punti aperti per il piano

- Nomi e schemi esatti degli strumenti, dopo aver riletto `GenerationController` (`chooseModel`, `run`, `loadPreset`/`savePreset`, `selectPipeline`) e `UserPipeline`.
- Come l'origine «Agente remoto» si innesta in `ContributionStore` accanto all'origine plug-in.
- Dove si misura il budget nel percorso di Run (un solo punto, anche per la coda).
- Porta di ascolto (fissa e configurabile) e comportamento se è occupata.
- Valori di default di soglia, budget, scadenza.
- Se `tokenizer`/tool-calling dell'MLX locale conta: non per la v1.
