# Pipeline di preset create dall'utente — Design

Data: 12 ottobre 2026. Stato: approvato in chat dall'utente (menu, finestre, dati ed esecuzione, mockup); da implementare in una sessione locale con Xcode e Swift.
Base: `origin/main` **0.2.0** (`90d6b61`). Estende `2026-10-04-preset-pipeline-design.md` (pipeline di preset dei plug-in) e il menu Preset (`App/Generation/Presets/`).

## 1. Obiettivo

L'utente crea pipeline mettendo in fila i suoi preset (es. «Flux2 base» → «Qwen upscale ×2»), le salva, le sceglie dal menu Preset e le lancia con RUN. Un passaggio può usare un **modello diverso**, **scalare le dimensioni** e avere una **forza propria**. La prima voce può essere **«Impostazioni attuali»**, cioè lo stato di Generazione e Control al lancio.

## 2. Decisioni (dell'utente, 12 ottobre)

- **Le nuove funzioni stanno nel menu Preset** (§3).
- **Ordine dei passaggi:** l'ordine in cui si spuntano le caselle; nella casella compare il numero del passaggio al posto del segno di spunta.
- **«Concatena i risultati»:** casella per pipeline, accesa di default. Se accesa, dal 2° passaggio il risultato del precedente è l'immagine di partenza.
- **Modello:** ogni passaggio usa il modello del suo preset; se il preset non ne ha uno, quello dell'header. Le pipeline dei **plug-in** continuano a ignorarlo.
- **Dimensioni:**
  - il 1° passaggio usa quelle di Generazione al lancio;
  - gli altri usano quelle del passaggio precedente × un **fattore di scala** per passaggio (campo `[1,5]×`, default 1).
- **Forza per passaggio:** campo `[ ] %`. Vuoto = automatica, come Control; vuoto è il default.
- **«Impostazioni attuali» è dinamica:** nella pipeline si salva solo la voce. Al lancio vale lo stato di Generazione e Control di quel momento.
- **Gestisci preset e pipeline:** la finestra di oggi elenca anche le pipeline, che si possono rinominare ed eliminare.
- **Nessun riepilogo delle dimensioni** nella finestra: le dimensioni di partenza cambiano a ogni lancio.

## 3. Menu Preset

```
Preset A
Preset B
Preset C
────────────────
Pipeline X                ✓ (quella attiva)
Pipeline Y
────────────────
Salva come preset…
Crea pipeline…
Gestisci preset e pipeline…
Importa preset da file…
```

- **Gruppo delle pipeline:** compare solo se ce n'è almeno una, ordinato per nome. La pipeline attiva sul RUN ha il segno di spunta.
- **Scelta di una pipeline:**
  - diventa la pipeline del RUN, al posto di quella di un plug-in senza pop-up (è una scelta esplicita dell'utente);
  - il pulsante RUN mostra «Run · N passaggi»; il suo aiuto elenca i passaggi col nome della pipeline;
  - «Togli la pipeline» la toglie, come oggi.
- **Stato «attiva»:** è solo in memoria, come per le pipeline dei plug-in; non sopravvive al riavvio.
- **Abilitazione:**
  - «Crea pipeline…» è disattivata senza preset;
  - «Gestisci preset e pipeline…» è disattivata senza preset e senza pipeline.
- **Testi:**
  - it: «Crea pipeline…», «Gestisci preset e pipeline…»;
  - en: «Create Pipeline…», «Manage Presets and Pipelines…».

## 4. Dati

- **Cartella** `~/Library/Application Support/DT Hub/Pipelines/`, un file `<nome>.json` per pipeline, come i preset (`PresetStore`).
- **Nomi:** stesse regole e stessi controlli dei preset (`PresetStore.isValidName`; maiuscole e accenti non distinguono). Sono separati dai nomi dei preset: una pipeline e un preset possono chiamarsi uguale.

```json
{"chain": true, "steps": [
  {"preset": null},
  {"preset": "Qwen · Upscale", "scale": 2},
  {"preset": "SD 1.5 · Rifinitura", "scale": 1, "strength": 0.3}
]}
```

- **Campi:**
  - `preset: null` = «Impostazioni attuali»;
  - `scale` mancante = 1, riportato in 0,25–4;
  - `strength` mancante = automatica, riportata in 0–1.
- **Lettura tollerante:** un passaggio illeggibile si salta; un file illeggibile compare nell'elenco e dà errore quando lo si usa (come i preset).
- **Store:** `UserPipelineStore` (HubCore), con API come `PresetStore`: `names`, `refresh()`, `load(named:)`, `save(_:named:)`, `delete(named:)`, `rename(_:to:)`, `existingName(for:)`.
- **Rinomina di un preset** in Gestisci: dopo una rinomina riuscita, l'app aggiorna anche le pipeline che lo nominano, con `UserPipelineStore.renamePreset(_:to:)`. `PresetStore` non conosce le pipeline.
- **Cancellazione di un preset:** le pipeline restano invariate; in Gestisci compaiono con «manca: <nomi>», e al RUN il preset mancante dà l'avviso di sempre.

## 5. Esecuzione

Una pipeline dell'utente diventa la pipeline del RUN, cioè un `PluginPipeline` con `PipelineStep`. `PipelineStep` (HubKit) guadagna tre campi, che **non** si leggono dal JSON dei plug-in:

```swift
public var usesPresetModel: Bool = false   // true per i passaggi di una pipeline dell'utente
public var scale: Double = 1               // dal 2° passaggio
public var strength: Double? = nil         // nil = automatica
```

`PipelineContribution` dice da dove viene la pipeline (plug-in oppure utente con il nome della pipeline), così l'aiuto del RUN e la voce del menu la riconoscono.

Per ogni passaggio (`GenerationController.runPipeline`):

- **Campi:**
  - passaggio senza preset («Impostazioni attuali»): la scheda com'è;
  - con preset: `PipelinePresets.fields` come oggi.
- **Modello:**
  - con `usesPresetModel` e un preset con un modello, il modello del preset;
  - altrimenti quello dell'header.
  - La famiglia, il controllo «modello Edit», il controllo del RUN (`RunAvailability`) e `JobComposer` usano **il modello del passaggio**.
- **Dimensioni:**
  - **1° passaggio:** larghezza e altezza della scheda al lancio;
  - **dal 2°:** quelle del passaggio precedente × `scale`, arrotondate al multiplo di 64 più vicino (`GenerationParameters.snap`);
  - **limite:** `parameters.sizeLimit` del passaggio, cioè 8192 se HiRes (beta) o il Tiled Diffusion sono attivi nei suoi parametri, altrimenti 2048. Le proporzioni si conservano anche quando un lato tocca il limite.
- **Ingressi:**
  - `useOutputAsStart = chain`, dal 2° passaggio;
  - il 1° passaggio usa Control com'è;
  - senza concatenazione, ogni passaggio usa Control com'è.
- **Forza:** con un'immagine di partenza, `strength` del passaggio se c'è, altrimenti quella automatica di oggi (`PipelineInputs.strength`). Nel 1° passaggio e in «Impostazioni attuali», in qualunque posizione, vale sempre Control.

**Prima del primo passaggio**, se manca qualcosa non parte nulla. Il RUN controlla e mostra, come oggi, nella finestra Risultati:
- «Preset non trovato: …»;
- «Preset non leggibile: …»;
- **novità:** «Modello non installato: …» per un modello di preset che non è nel catalogo del server;
- **novità:** «Pipeline non leggibile: <nome>».

## 6. Finestra «Crea pipeline…»

Il layout è quello del mockup approvato (`ManagePresetsSheet` come base: stesso stile, larghezza ~500).

- **In alto:**
  - campo **Nome**;
  - sotto, in rosso: «Nome non valido» oppure «Esiste già una pipeline con questo nome: verrà sostituita.».
- **Casella «Concatena i risultati»**, accesa, con la nota «il risultato di un passaggio è l'immagine di partenza del successivo».
- **Elenco** con intestazione `# | Preset | Scala | Forza`:
  - **prima riga fissa «Impostazioni attuali»**, in corsivo, con la nota «Generazione e Control al lancio»;
  - poi i preset in ordine di nome, con il **nome non modificabile** e il modello in piccolo sotto (oppure «Nessun modello: quello dell'header»);
  - **casella:** vuota se non spuntata; spuntata mostra il **numero** del passaggio. Togliendo una spunta, i numeri dopo scalano;
  - **Scala:** campo numerico con «×» fuori dal campo. Disattivato per il passaggio 1 (mostra «—») e per le righe non spuntate;
  - **Forza:** campo numerico con «%» fuori dal campo; vuoto con «auto» come segnaposto. Disattivato per il passaggio 1, per la riga «Impostazioni attuali» (segue Control) e per le righe non spuntate;
  - un valore non valido (vuoto in Scala, fuori limite, lettere) ha il bordo rosso e disattiva Salva.
- **In basso:**
  - **Chiudi**: chiude senza salvare, senza conferma;
  - **Salva** (primario): attivo con un nome valido e **almeno 2 passaggi**. Scrive la pipeline (sostituendo quella con lo stesso nome), lascia la finestra aperta e mostra «Salvata.» al posto dell'avviso.

## 7. Finestra «Gestisci preset e pipeline…»

È la `ManagePresetsSheet` di oggi, con due gruppi titolati:
- **Preset:** come oggi (nome modificabile, modello sotto, cestino).
- **Pipeline:** nome modificabile, sotto «N passaggi», cestino. Se nomina preset che non esistono, sotto c'è in rosso «manca: <nomi>».

Rinominare o eliminare la pipeline attiva sul RUN aggiorna o toglie la pipeline del RUN.

## 8. Test

- **HubCore:**
  - **`UserPipelineStore`:** salva e rilegge; nomi non validi; nome già esistente (salvare sostituisce, rinominare rifiuta); maiuscole e accenti; file illeggibile; passaggio illeggibile saltato; `scale` e `strength` riportati nei limiti; `renamePreset` aggiorna solo le pipeline che lo nominano.
  - **Conversione** pipeline dell'utente → `PluginPipeline`: «Impostazioni attuali» = passaggio senza preset; `useOutputAsStart` dal 2° passaggio solo con `chain`; `usesPresetModel` acceso.
  - **Dimensioni** dei passaggi (funzione pura `PipelineSizes.sizes(first:scales:limits:)`):
    - 1024×1024 con scale [—, 2, 1] → 1024, 2048, 2048;
    - limite 2048 con scale 3 → 2048 sul lato lungo, proporzioni conservate, multipli di 64;
    - con HiRes → fino a 8192;
    - 832×1216 × 1,5 → 1248×1824.
  - **Forza:** con `strength` 0,3 e immagine dal passaggio precedente → 0,3; vuota → automatica; nel 1° passaggio vale Control.
  - **Modello:** preset con modello → quello; senza → header; per una pipeline di plug-in → sempre header. Modello del preset non nel catalogo → errore prima del 1° passaggio.
  - **Pipeline di plug-in:** `PipelineStep` letto dal JSON non ha mai `usesPresetModel`, `scale` o `strength`.
- **App** (a mano):
  - ordine per spunta e numeri che scalano;
  - Salva con nome esistente;
  - menu con il gruppo Pipeline e la spunta;
  - RUN di Flux2 → Qwen ×2 con concatenazione: secondo risultato al doppio delle dimensioni, col modello Qwen;
  - rinomina di un preset → la pipeline lo segue;
  - cancellazione di un preset → «manca:» in Gestisci e avviso al RUN.

## 9. Fuori ambito

- Modificare i passaggi di una pipeline salvata: si ricrea con lo stesso nome e la si sostituisce.
- Lo stesso preset due volte nella stessa pipeline.
- Moodboard per passaggio.
- Esportare o importare pipeline.
- Mostrare le pipeline dell'utente ai plug-in.
- Ricordare la pipeline attiva dopo un riavvio.
