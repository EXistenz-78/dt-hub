# DT Hub — Design del cuore dell'app (v1)

Data: 29 settembre 2026 · Stato: bozza da approvare · Nome "DT Hub" provvisorio

## 1. Scopo

DT Hub è un'app nativa macOS che **sostituisce l'interfaccia di Draw Things per preparare e lanciare le generazioni**. Parla con Draw Things via gRPC e con un LLM locale (MLX) dentro l'app. Le funzioni specializzate arrivano come **plug-in**, ognuno con il proprio tab: i primi saranno Prompt Master 2.0 (PM2) e Sphere Light Reference (SLR), che oggi sono strumenti separati collegati a DT tramite appunti e script JS.

Pubblico: uso personale, poi open source (GPL-3). Nessuna scadenza.

Non è un editor su canvas: canvas infinito e livelli restano compito dell'app Draw Things.

## 2. Perimetro

**v1 (cuore dell'app):**
- generazione **T2I**;
- pannello parametri completo (tre livelli, sezione 6);
- collegamento al server gRPC di DT;
- servizio LLM (MLX) con prova nelle Preferenze;
- finestra risultati con anteprima in diretta e salvataggio automatico;
- contratto dei plug-in e menu dei plug-in (vuoto).

**Tab Control (anticipato, prima di M7; deciso con l'utente il 1 ottobre 2026):** immagine di partenza (I2I), Moodboard e inpaint con pennello semplice, in un tab del cuore davanti a Generazione. Design in `2026-10-01-tab-control-design.md`. L'outpaint lo segue quando l'inpaint funziona.

**Dopo la v1, in quest'ordine:**
1. Plug-in Prompt Master.
2. Plug-in Sphere Light.
3. Plug-in Qwen Image 2.1.
4. Galleria completa con storico e ricerca.

**Fuori dal progetto:** canvas infinito e livelli; ComfyUI; DeepL; gli script JS di DT.
**Fuori dalla v1:** il video (Wan, LTX, Hunyuan, MiniMax). I suoi campi restano raggiungibili dall'editor JSON.

## 3. Vincoli tecnici

- macOS 26, Apple Silicon, Swift 6, SwiftUI, Xcode 27.
- Progetto Xcode per l'app + pacchetti Swift locali per i moduli.
- Draw Things gira come server gRPC sulla stessa macchina: `gRPCServerCLI` standalone, oppure l'API server dell'app DT in modalità gRPC.
- Macchina di riferimento: M1 Ultra, 64 GB. Modelli DT su `/Volumes/LLM-VLM/Models`.

## 4. Architettura e moduli

```
DT Hub.xcodeproj            app SwiftUI: finestre, header, tab, preferenze
Packages/
  HubKit                    contratto: protocolli e tipi condivisi, nessuna dipendenza esterna
  HubCore                   stato globale, composizione del lavoro, esecuzione, persistenza
  DTBridge                  implementa GenerationBackend con DrawThings-Swift (gRPC)
  LLMBridge                 implementa LanguageModelService con mlx-swift-lm
  Plugins/…                 un pacchetto per plug-in (nessuno nella v1, tranne quello di test)
```

**Regole di dipendenza** (le fa rispettare il compilatore):
- i plug-in dipendono **solo** da HubKit;
- HubCore dipende da HubKit e usa DT e LLM solo tramite i protocolli `GenerationBackend` e `LanguageModelService`;
- DTBridge è l'unico modulo che importa DrawThings-Swift e gRPC; LLMBridge è l'unico che importa MLX;
- l'app collega le implementazioni all'avvio e contiene solo interfaccia e collegamenti.

Conseguenze: sostituire la libreria gRPC o il motore LLM tocca un solo modulo; HubCore e i plug-in si testano con implementazioni finte.

## 5. Integrazione con Draw Things (DTBridge)

**Libreria:** [DrawThings-Swift](https://github.com/euphoriacyberware-ai/DrawThings-Swift), licenza MIT, prodotto `DrawThingsClient`. Verificata dal vivo nello spike (appendice A). Ha un solo manutentore: resta confinata in DTBridge. Il piano di riserva è un client generato dallo schema ufficiale di draw-things-community (`imageService.proto` + `config.fbs`).

**Connessione:**
- indirizzo e porta, predefiniti `localhost:7859`;
- TLS attivo di default (è la modalità dell'API server di DT);
- shared secret opzionale, conservato nel Portachiavi.

**Gestione del server**, impostabile nelle Preferenze:
- *Collegati a un server già attivo*: si collega e basta.
- *Avvia gRPCServerCLI*: percorso del binario e cartella modelli; avviato con `--model-browser`. DT Hub lo avvia all'apertura, lo ferma alla chiusura e ne segnala l'arresto inatteso, offrendo di riavviarlo.

**Catalogo modelli:**
- la chiamata `Echo` restituisce i file installati e i metadati (serve il model browsing attivo);
- i metadati del server coprono solo i modelli importati dall'utente e vanno fusi con il catalogo pubblico di DT, che DrawThings-Swift gestisce (`ModelSpecStore`);
- ripiego finale: riconoscere la famiglia dal nome del file (`ModelFamily.detect`).

**La famiglia (`version`, es. `flux2_9b`) è la chiave di tutto il sistema.** Da essa dipendono:
- quali campi si vedono;
- quali LoRA compaiono;
- quali plug-in sono attivabili;
- in futuro, quale dialetto di prompt usa PM2.

**Generazione:**
- una richiesta gRPC in streaming, con avanzamento, anteprime e immagini finali già convertite in `CGImage`;
- una pipeline a più passaggi è una sequenza di richieste orchestrata da HubCore;
- l'annullamento (Stop) si propaga al server.

## 6. Modello dei parametri

La configurazione di DT (`GenerationConfiguration`) ha 97 campi. Un campo si mostra **solo se ha senso per la famiglia del modello scelto**.

**Livello 1 — Base, sempre visibile:**
- Modello: selettore globale nell'header.
- LoRA: più di una, con peso e modalità; si vedono solo quelle compatibili con la famiglia.
- Dimensioni: larghezza e altezza, rapporti predefiniti, blocco del rapporto; multipli di 64.
- Step, Text guidance (CFG), Sampler.
- Seed, con modalità del seed e pulsante casuale.
- Shift e "shift in base alla risoluzione", solo per le famiglie che li usano.
- Batch: numero di immagini per batch e numero di batch.
- Prompt negativo, solo per le famiglie che lo usano, dentro la card Prompt.
- Strength: compare solo quando c'è un'immagine di partenza (nella v1 può arrivare solo da un plug-in).

**Livello 2 — Avanzate, in card richiudibili:**

| Card | Campi |
|---|---|
| Refiner | modello refiner, refiner start |
| Hires fix | attivazione, dimensioni di partenza, strength |
| Upscaler e restauro | upscaler, fattore di scala, face restoration |
| Inpaint | mask blur, mask blur outset, preserve original (visibile quando esiste una maschera) |
| ControlNet | lista controlli con peso, inizio/fine, modalità |
| Guidance extra | guidance embed, speed-up with guidance embed, CFG-Zero\* e init steps, image guidance, sharpness, stochastic sampling gamma |
| Text encoder | CLIP skip, T5, testi separati CLIP-L / OpenCLIP-G / T5, zero negative prompt |
| Condizionamento SDXL | aesthetic score, dimensioni originali e di destinazione, ritaglio (solo SDXL) |
| Prestazioni | decodifica a tile, diffusione a tile, TeaCache, SOL attention, causal inference |
| Output | calibrazione del colore, artefatti di compressione |

**Livello 3 — Editor JSON:**
- la configurazione completa nel formato "Copy Configuration" di DT, con import ed export e fusione di una configurazione parziale incollata;
- tutti i 97 campi sono raggiungibili qui, compresi video, campi deprecati e modelli datati (image prior di Kandinsky, stage 2 di Würstchen).

**Preset:**
- salvataggio e caricamento di configurazioni con un nome;
- import da file: un elenco JSON di `{name, configuration}` (la forma di `custom_configs.json` e della lista pubblica di Draw Things), scelto con il pannello di apertura. `custom_configs.json` non esiste nelle versioni recenti di Draw Things, che tengono le configurazioni dell'utente in un database interno: i preset personali si portano con "Copy Configuration" incollato nell'editor JSON (verificato il 1 ottobre 2026).

**Regole di visibilità:** una tabella famiglia → campi pertinenti vive in HubCore. Se un campo nascosto ha un valore diverso dal predefinito (es. importato da JSON), la card mostra un avviso "valori nascosti attivi".

## 7. Interfaccia

**Design system:** quello di Flat Planner, già portato in SLR (`DesignSystem.swift`):
- turchese `#3EC8C8` come unico colore d'accento;
- arancio `#F09837` per ciò che si toglie;
- Liquid Glass;
- pannelli con raggio 19;
- titoli di gruppo in monospaziato maiuscolo;
- pulsanti a pillola alti 40 pt;
- un solo pulsante principale colorato per schermata.

Il file va portato in HubKit, così i plug-in lo usano.

**Finestra principale:**
```
┌──────────────────────────────────────────────────────────────┐
│ [Plug-in ▾]  [Modello ▾ · famiglia]       ● DT   [⚙︎]  [▶ RUN] │
├──────────────────────────────────────────────────────────────┤
│ [ Control ] [ Generazione ]  (+ un tab per ogni plug-in attivo) │
├──────────────────────────────────────────────────────────────┤
│  PROMPT  a tutta larghezza; sotto il prompt, il NEGATIVO      │
│          (tinta arancio, solo se la famiglia lo usa)          │
│  CONTRIBUTI PLUG-IN  solo se un plug-in ha contribuito        │
│  [ Dimensioni      ] [ Seed e batch   ]  due card per riga,    │
│  [ Campionamento   ] [ …              ]  alte come la più alta │
└──────────────────────────────────────────────────────────────┘
```

**Header:**
- *Menu plug-in*: ogni plug-in installato si attiva o disattiva a mano; è grigio se incompatibile con la famiglia del modello scelto, e diventa inattivo se si cambia modello.
- *Menu modello*: unico e globale, con la famiglia accanto al nome.
- *Pallino di stato DT*: verde = collegato; giallo = in connessione o server in avvio; rosso = non raggiungibile.
- *Preferenze*.
- *RUN*: grigio se DT non è collegato o manca il modello; durante la generazione diventa "Stop" e mostra l'avanzamento.

**Tab "Generazione":** l'unico incluso nell'app.
- Card Prompt a tutta larghezza; il prompt negativo sta **dentro la stessa card**, sotto il prompt, e compare solo per le famiglie che lo usano (deciso con l'utente, 30 settembre 2026).
- Parametri in card richiudibili, **due per riga**; le card della stessa riga hanno esattamente l'altezza della più alta. Lo stato aperto/chiuso viene ricordato.
- Ogni valore numerico si scrive oppure si cambia con le frecce; le caselle che modificano un valore stanno sulla sua stessa riga.
- Le card si costruiscono una alla volta, partendo da quelle di base.

**Finestra risultati (separata):**
- si apre al primo RUN;
- mostra l'anteprima in diretta durante gli step, poi l'immagine finale;
- sotto, una striscia con le immagini della sessione. Per ognuna: aprire, salvare, mostrare nel Finder, **riprendere i parametri**;
- ogni immagine è salvata automaticamente come PNG con prompt e configurazione incorporati;
- le miniature si trascinano nel tab Control (immagine di partenza, Moodboard) e hanno nel menu "Usa come immagine" e "Aggiungi al Moodboard".

**Preferenze:**
- *Draw Things*: modalità server, indirizzo e porta, TLS, shared secret, percorso di `gRPCServerCLI`, cartella modelli.
- *LLM*: cartella dei modelli MLX, modello scelto, scaricamento, prova.
- *Output*: cartella di salvataggio.

## 8. Contratto dei plug-in (HubKit)

Un plug-in dichiara:
- identificatore, nome, icona;
- famiglie compatibili (assente = tutte);
- la vista del proprio tab.

Riceve dal cuore dell'app:
- `LanguageModelService`;
- il catalogo di modelli e LoRA;
- la configurazione corrente in sola lettura;
- un canale per consegnare contributi.

**I contributi sono sempre visibili prima di RUN.** Un plug-in può:
- impostare uno o più parametri: compaiono nelle rispettive card, con un segno che indica quale plug-in li ha impostati;
- scrivere il prompt o il negativo;
- inserire immagine di partenza, immagini di moodboard o la maschera: compaiono **nelle schede del tab Control**, con la provenienza del plug-in, e l'utente le toglie o le cambia come le altre (design in `2026-10-01-tab-control-design.md`, §7); la card **Contributi plug-in** resta per parametri, prompt e pipeline;
- fornire una **pipeline** a più passaggi, anch'essa elencata nella card Contributi.

L'utente può modificare o rimuovere ogni contributo prima di RUN. Un plug-in **non cambia mai il modello** e non lancia generazioni da solo.

**Pipeline:** una lista ordinata di passaggi, ciascuno fatto di:
- modifiche alla configurazione (es. LoRA, step, prompt);
- ingressi: immagine di partenza, hint;
- l'indicazione se l'output del passaggio precedente diventa l'immagine di partenza.

Senza pipeline, RUN esegue un solo passaggio con la configurazione corrente.

**Conflitti:** se due plug-in attivi contribuiscono allo stesso campo o forniscono entrambi una pipeline, RUN si blocca con un messaggio che nomina i plug-in e il campo in conflitto. L'utente risolve togliendo un contributo o disattivando un plug-in.

La v1 include un **plug-in di prova**, solo nei test e in build Debug, per verificare contratto, contributi e conflitti.

## 9. Servizio LLM (LLMBridge)

- **Motore:** mlx-swift-lm (`MLXLLM`, `MLXVLM`) dentro l'app; supporta la visione.
- **Modello predefinito:** `mlx-community/Qwen3-VL-8B-Instruct-4bit` (Qwen3-VL 8B Instruct a 4 bit, 17 file, circa 5,78 GB, Apache-2.0; verificato su Hugging Face il 1 ottobre 2026).
- **Cartella dei modelli:** impostabile nelle Preferenze, predefinita `/Volumes/LLM-VLM/MLX`. Un modello è una cartella in formato Hugging Face (`config.json` e `.safetensors`), fino a due livelli sotto la cartella (anche quelle di LM Studio); i file `.ckpt` di Draw Things e di Local Code, in formato proprio, non sono utilizzabili. Lo scaricamento avviene solo su richiesta esplicita dell'utente, con un dialogo che nomina repository, dimensione e destinazione.
- **Memoria** (decisa con l'utente, 1 ottobre 2026): il modello immagine e l'LLM possono non stare insieme nella memoria di un Mac. Tre impostazioni nelle Preferenze › LLM:
  - *Libera l'LLM quando premo Run* (attiva di default sotto i 64 GB): l'LLM si ricarica al primo uso successivo;
  - *Libera il modello immagine quando uso l'LLM* (attiva di default sotto i 64 GB): solo con il server avviato da DT Hub, che si ferma prima di caricare l'LLM e riparte al Run (Draw Things non ha una chiamata per scaricare un modello da un altro server; il ricaricamento costa tempo e le scelte non si basano su dischi lenti);
  - *Libera l'LLM dopo N minuti senza usarlo* (10 di default, 0 = mai).
  Prima di caricare l'LLM, DT Hub confronta la dimensione del modello (× 1,2) con la memoria libera e, se non basta, lo dice invece di far andare il Mac in swap.
- **v1:** il servizio esiste e ha una prova nelle Preferenze (una domanda di testo, e una di visione con un'immagine scelta). Il miglioramento del prompt arriva col plug-in PM2.
- **Generazione strutturata:** lo schema JSON di MLXGuidedGeneration è disponibile per i plug-in che vogliono risposte strutturate (arriva con il contratto dei plug-in, M8).
- **Un solo compito, un modello alla volta:** tutti i modelli LLM servono allo stesso scopo, cioè migliorare i prompt, e **non ne serve mai più di uno contemporaneamente**. I plug-in non scelgono il modello: chiedono al servizio di "migliorare il prompt", e il servizio decide quale modello usare.
- **Regola di scelta del modello:**
  - **predefinito:** un modello generico, valido per tutte le famiglie, usato soprattutto da PM2;
  - **modelli dedicati:** un plug-in può registrare modelli specializzati per una famiglia, che **sostituiscono** quello generico solo quando quella famiglia è selezionata. Si registra una coppia: uno per T2I, usato se non c'è un'immagine di partenza, e uno per I2I, usato se c'è;
  - **primo caso previsto:** il plug-in Qwen Image 2.1 registrerà, per la famiglia `qwen21`, `Qwen/Qwen-Image-2.1-PE-T2I` e `Qwen/Qwen-Image-2.1-PE-I2I`. Sono fine-tune di Qwen3.5 9B, architettura `qwen3_5`, già supportata da MLXVLM;
  - se il modello dedicato manca, si usa quello generico e le Preferenze ne propongono lo scaricamento.
- **Formati:** un modello in safetensors formato Hugging Face si carica direttamente; la quantizzazione a 4 o 8 bit, consigliata per la memoria, è un'operazione una tantum.

## 10. Errori

| Situazione | Comportamento |
|---|---|
| DT non raggiungibile | pallino rosso, RUN grigio, riconnessione automatica periodica |
| Model browsing disattivato (catalogo vuoto) | avviso con istruzioni per attivarlo |
| Modello scelto non presente sul server | RUN grigio, messaggio nella card del modello |
| Generazione terminata senza immagini | trattata come errore, anche se il server risponde OK (comportamento osservato in draw-things-community issue #131) |
| Server avviato da DT Hub chiuso inaspettatamente | avviso con pulsante "Riavvia" |
| Errore in un passaggio della pipeline | stop della pipeline; il messaggio indica il passaggio; i risultati dei passaggi precedenti restano |
| Modello LLM mancante o scaricamento fallito | messaggio nelle Preferenze; le funzioni LLM dei plug-in risultano non disponibili |

## 11. Persistenza

- All'avvio si ripristinano l'ultimo prompt e gli ultimi parametri.
- Impostazioni in UserDefaults; shared secret nel Portachiavi.
- Preset, stato delle card e sessione nella cartella di supporto dell'app, in JSON.
- Immagini generate nella cartella di output, come PNG con metadati.

## 12. Localizzazione

Italiano e inglese, con i cataloghi di stringhe di Xcode. Nessun testo visibile scritto direttamente nel codice.

## 13. Test

- **HubKit e HubCore:** test automatici (Swift Testing) con `GenerationBackend` e `LanguageModelService` finti. Coprono composizione del lavoro, visibilità dei campi per famiglia, contributi e conflitti, pipeline, persistenza.
- **DTBridge:** test d'integrazione sul server vero, contrassegnati e da lanciare a mano.
- **LLMBridge:** test a mano, perché richiede il modello scaricato.
- **Interfaccia:** verifica manuale in Xcode.

## 14. Licenza

GPL-3. Le dipendenze sono compatibili:
- DrawThings-Swift, mlx-swift, mlx-swift-lm: MIT;
- grpc-swift, swift-protobuf: Apache-2.0;
- flatbuffers: Apache-2.0.

## 15. Roadmap

Ogni tappa termina con qualcosa di utilizzabile.

| Tappa | Contenuto | Esito |
|---|---|---|
| M1 Ossatura | Progetto Xcode e pacchetti; design system in HubKit; finestra con header, barra dei tab e tab Generazione vuoto; Preferenze vuote | l'app si apre con la struttura definitiva |
| M2 Collegamento DT | DTBridge: connessione, pallino di stato, catalogo con famiglie, menu modello; modalità "server già attivo" | si sceglie un modello reale da DT |
| M3 Primo T2I | Card prompt; card Dimensioni, Sampling, Seed e batch; RUN/Stop; finestra risultati con anteprima; salvataggio PNG | **prima immagine generata da DT Hub** |
| M4 Card complete | LoRA, negativo, card Avanzate, visibilità per famiglia, editor JSON, preset e import `custom_configs.json`, ripristino sessione | parità con il pannello di DT per il T2I |
| M5 Server gestito | Modalità "avvia gRPCServerCLI", arresti inattesi e riavvio | DT Hub funziona senza l'app DT aperta |
| M6 LLM | LLMBridge, scaricamento nella cartella scelta, politica di memoria, prova nelle Preferenze | l'LLM risponde, anche su immagini |
| M7 Tab Control | **M7a** immagine di partenza e I2I; **M7b** Moodboard e modelli Edit; **M7c** inpaint con pennello (design in `2026-10-01-tab-control-design.md`) | I2I, Moodboard e inpaint funzionano |
| M8 Plug-in | Contratto HubKit, menu plug-in, card Contributi, pipeline, conflitti, plug-in di prova | la v1 è completa |
| Dopo | Tiled Diffusion fino a 8192 → outpaint → PM2 → SLR → Qwen Image 2.1 → Galleria | una spec breve per ciascuno |

M4 si svolge in tre tappe, ognuna con revisione e merge (deciso con l'utente, 30 settembre 2026): **M4a** negativo, LoRA, visibilità per famiglia, ripristino sessione; **M4b** card Avanzate e avviso "valori nascosti attivi"; **M4c** editor JSON, preset, import di `custom_configs.json`.

## 16. Rischi aperti

- **DrawThings-Swift ha un solo manutentore.** Mitigazione: confinato in DTBridge; piano di riserva sullo schema ufficiale.
- **Lo schema di configurazione di DT cambia a ogni versione.** Mitigazione: livello 3 JSON sempre completo; la tabella di visibilità si aggiorna senza toccare il resto.
- **Metadati incompleti per i modelli ufficiali.** Mitigazione: fusione con il catalogo pubblico di DT e riconoscimento dal nome del file.
- **Tempi di caricamento dei modelli dal volume esterno:** circa 134 s al primo passaggio con Flux Klein f16. È un vincolo dell'hardware, non del progetto; l'interfaccia deve mostrare lo stato "caricamento modello".

## Appendice A — Esiti dello spike (28 settembre 2026)

Verificato dal vivo contro l'API server gRPC dell'app DT (porta 7859, TLS), con un programma usa e getta non conservato:

- `Echo` con model browsing: 154 file (102 LoRA), metadati per 14 modelli e 99 LoRA, ciascuno con la famiglia (`version`).
- T2I con Flux 2 Klein 9B f16, 768×768, 4 step: 134 s compreso il caricamento, anteprime in streaming ricevute.
- Passaggio SLR "match sun" via gRPC (immagine di partenza + moodboard + LoRA sun-direction 0,6): 103 s, immagine restituita e convertita in PNG. È stato verificato il collegamento, non la qualità della luce (l'immagine di moodboard usata era uno screenshot, non il render della sfera).
- Configurazione passata nel formato JSON di DT: i blocchi degli script SLR sono riusabili così come sono.
