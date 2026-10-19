# Plug-in Tiled Upscale e pipeline guidata dal plug-in — Design

Data: 18 ottobre 2026. Stato: **da rileggere** (il disegno è stato discusso e corretto in chat con l'utente; la spec non è ancora approvata).
Base: `main` 0.3.1 (`db71744`). Si implementa in un ramo nuovo; niente unione, push o release senza via libera esplicito.

## 1. Scopo

Ingrandire un'immagine di 2×, 4× o 8× mantenendo e inventando dettaglio con un modello edit (FLUX.2 klein 9B per ora), lavorando **per tile** con un preset e un LoRA, e ricomponendo il risultato in modo che le giunzioni non si vedano.

Due parti, indipendenti nel codice:

1. **Pipeline guidata dal plug-in** (app + contratto 1): un plug-in può decidere, passo dopo passo, cosa far eseguire all'app, usando il risultato del passo precedente. Lo potranno sfruttare altri plug-in in futuro.
2. **Plug-in Tiled Upscale** (`Plugins/TiledUpscale/`), il primo a usarla.

## 2. Decisioni dell'utente (18 ottobre)

- Fattori di ingrandimento: **2×, 4×, 8×**. Un solo upscale bilineare dell'originale, mai a passate.
- **Multipli di 64 ovunque**, perché Draw Things lavora in multipli di 64 e un tile non allineato verrebbe ricampionato (la giunzione smetterebbe di essere invisibile):
  - un'immagine già in base 64 si ingrandisce di quel rapporto (un multiplo di 64 per un intero resta multiplo di 64);
  - se non lo è, **dopo** l'ingrandimento si ritaglia del minimo indispensabile per portarla a multipli di 64 (al massimo 63 px per lato, centrato).
- **Tile massimo 1024 × 1024.** Sovrapposizione **selezionabile nel plug-in: 256 (predefinita) o 320**. Il passo è `1024 − sovrapposizione` (768 o 704). I tile dell'ultima riga e dell'ultima colonna possono essere più piccoli (sempre multipli di 64).
- **Maschera** (Sfumatura 30, Margine 30, «Conserva l'originale fuori dalla maschera» acceso): lascia libera una parte della sovrapposizione verso i tile già fatti: **200 px con sovrapposizione 256, 250 px con 320** (sempre 25/32 della sovrapposizione).
- **Preset FLUX.2 klein 9B:** 4 passi, guidance 1, forza 1, sampler 16, shift 3, LoRA `f2_ultra_real_v5_pro_lora_f16` (peso predefinito 1, **regolabile nel plug-in**). Il modello è quello dell'header: il plug-in non lo cambia mai.
- **Prompt di ogni tile:** il trigger word del LoRA (dal `loraCatalog` del contesto) + ` ALSO PRESERVE COLORS AND LUMINOSITY`.
- **Qwen Image 2.1:** si aggiunge dopo come un preset in più (i LoRA non sono ancora provati); la matematica dei tile non cambia. Fino ad allora il plug-in con Qwen 2.1 è spento con un avviso.
- Le tre decisioni di comportamento della sessione (§6.4) le ha proposte l'assistente e l'utente le ha accettate con il disegno.

## 3. Geometria (modulo puro `TileGrid`)

Entrate: dimensioni dell'originale, fattore (2, 4, 8), sovrapposizione (256 o 320). Tutto in pixel interi.

1. **Immagine ingrandita:** `W' = W·k`, `H' = H·k`. Si ritaglia a `W'' = floor64(W')`, `H'' = floor64(H')`, centrato (il pixel in più a destra o in basso se il resto è dispari). Se `W` e `H` sono già multipli di 64, nessun ritaglio.
2. **Passo:** `step = 1024 − overlap`.
3. **Tile per lato:** `n = 1` se il lato è ≤ 1024; altrimenti `n = ceil((lato − 1024) / step) + 1`. L'ultimo tile parte a `step·(n−1)` e finisce al bordo: è largo `lato − step·(n−1)`, sempre in `(overlap, 1024]` e multiplo di 64. Non è mai contenuto del tutto nel precedente.
4. **Ordine:** per righe, da sinistra a destra, dall'alto in basso (`1A, 1B, …, 2A, …`). Così quando si elabora un tile i vicini a sinistra e in alto sono già composti.
5. **Totale dei passi** = `nₓ · nᵧ`, calcolato prima di partire (avviso, stima dei CU, «Passo k di N»).

Esempio con overlap 256 e un lato di 2560 + Z: tile da 0, 768, 1536, 2304; l'ultimo va da 2304 al bordo ed è largo `256 + Z`.

**Costanti in un solo punto** (`TileGrid.Constants`): tile 1024, sovrapposizioni ammesse `[256, 320]`, fattore del margine libero `25/32`. Nessun altro file assume 256 o 320; un test verifica la griglia e le maschere per entrambi i valori.

**Limiti** (costanti, regolabili): oltre 16 384 px per lato o 268 megapixel il plug-in rifiuta; oltre 100 passi o 100 megapixel avvisa e chiede conferma prima di creare la pipeline. L'immagine intera di lavoro sta in memoria (8192² RGBA ≈ 270 MB).

## 4. Maschere

Coordinate nel tile (0,0 = angolo in alto a sinistra), `free = round(overlap · 25/32)`: 200 o 250. Il PNG ha la dimensione del tile (≤ 1024, dentro il limite di `MaskBitmap`); l'area **mascherata** è quella che il modello rigenera, il resto viene ripristinato da «Conserva l'originale».

| Tile | Maschera |
| --- | --- |
| Primo (riga 1, colonna A) | nessuna: tutto il tile è nuovo |
| Resto della prima riga | da `x = free` al bordo destro, per tutta l'altezza |
| Resto della prima colonna | da `y = free` al bordo basso, per tutta la larghezza |
| Tutti gli altri | il rettangolo da `(free, free)` al bordo destro e al bordo basso; l'area libera è una L (sinistra e sopra) |

Un tile piccolo ha la maschera più stretta (almeno `overlap + 64 − free`, cioè 120 px con 256 e 134 con 320). La convenzione bianco/nero è quella di `MaskBitmap` (da verificare nel piano). Sfumatura 30 e Margine 30 fanno da giunzione.

## 5. Contratto dei plug-in (aggiunte facoltative al contratto 1)

Un plug-in che non le usa non cambia; un'app più vecchia ignora i campi nuovi (dichiarare in `PluginKit/README.md` la versione minima, da alzare alla release).

### 5.1 Pipeline guidata

Nel messaggio `contribute`, `pipeline` può essere:

```json
{ "name": "Tiled Upscale", "guided": true, "passes": 12, "estimate": { …un passo… } }
```

Senza `steps`. L'utente la vede e la lancia con RUN come ogni pipeline. `passes` è il totale dichiarato; `estimate` è un passo rappresentativo (il tile più grande) per il misuratore dei CU. Se manca `passes` o è < 1, la pipeline viene ignorata con un problema nella risposta.

### 5.2 `session.next` (app → plug-in, con risposta)

```json
{ "type": "session.next", "index": 3, "count": 12,
  "previous": { "path": "…/tempFolder/…/pass-2.png", "width": 1024, "height": 1024 } }
```

(`previous` è assente al primo passo). Risposta del plug-in, un **passo autonomo**:

```json
{ "title": "Tile 2B",
  "startImage": { "path": "…", "name": "…" },
  "mask": { "path": "…", "name": "…" },
  "maskSettings": { "blur": 30, "outset": 30, "preserveOriginal": true },
  "size": { "width": 1024, "height": 1024 },
  "preset": "TUP · FLUX.2 klein 9B",
  "fields": { "prompt": "…" },
  "loras": [ { "file": "…", "weight": 1 } ],
  "strength": 1 }
```

oppure `{"done": true}` (la sessione finisce prima del totale dichiarato, senza errore).

### 5.3 `session.end` (app → plug-in)

`{ "type": "session.end", "reason": "finished" | "stopped" | "failed" | "closed" }`. Il plug-in libera la memoria e i file del `tempFolder`.

### 5.4 Campi nuovi di `PipelineStep`

`mask` (PNG nel `tempFolder`, nelle coordinate dell'immagine di partenza, come `paint`), `maskSettings` (`MaskSettings`: Sfumatura, Margine, Conserva) e `size`. Valgono **solo** per i passi guidati; un passo statico li ignora come oggi. In un passo guidato la dimensione di `size` vale (a differenza dei campi, dove una dimensione è ignorata).

## 6. App

### 6.1 Esecuzione

`runPipeline` (`App/Generation/GenerationController.swift`) estrae il corpo del ciclo in una funzione che esegue **un** passo. Le pipeline statiche la chiamano per ogni passo di `pipeline.steps`; quella guidata la chiama dopo ogni `session.next`. Il comportamento delle pipeline statiche non cambia.

### 6.2 Un passo guidato

- Non legge né modifica la scheda Control: l'immagine di partenza e la maschera vengono dal passo, inquadrate 1:1 sulle dimensioni di `size` (nessun ricampionamento, perché il tile ha la dimensione del canvas).
- Le impostazioni di maschera del passo prevalgono su quelle della scheda.
- Il modello è sempre quello dell'header.
- Il risultato (il PNG appena generato) viene copiato nel `tempFolder` della sessione e il suo percorso va nel `session.next` successivo.

### 6.3 Interfaccia

Resta una pipeline per l'utente: RUN con «Passo k di N», Stop che chiude la sessione, nessun'altra pipeline né RUN manuale finché la sessione è aperta (regola esistente), stima dei CU sul totale dichiarato.

### 6.4 Regole di sessione

- I risultati intermedi **non** compaiono nella striscia dei Risultati; il plug-in manda alla fine l'immagine composta.
- Un passo fallito ferma tutto (`session.end` con `failed`); le immagini già fatte restano nel `tempFolder` fino alla chiusura della sessione. Nessuna ripresa nella prima versione.
- Una sola sessione alla volta.
- Cambio di progetto o di modello, o plug-in che sparisce o non risponde (timeout), chiudono la sessione con `closed` e un avviso.
- Stop: `session.end` con `stopped`.

## 7. Plug-in Tiled Upscale

`Plugins/TiledUpscale/`, id `com.exiztenz.dthub.tiledupscale`, un pacchetto con test e README come gli altri; manifest con `requiresEditModel: true`; famiglia FLUX.2 klein (9B) per la prima versione.

### 7.1 Tab

- Immagine (da scegliere o trascinare, come in Depth & Pose).
- Ingrandimento: 2× / 4× / 8×.
- Sovrapposizione: 256 (predefinita) / 320.
- Peso del LoRA (predefinito 1).
- Riepilogo prima di partire: dimensione finale dopo il ritaglio (es. «2× → 2048 × 1856»), tile per lato, **numero di passi**, avvisi di limite.
- Tasto «Prepara»: invia `contribute` con la pipeline guidata; poi l'utente preme RUN.
- Stato per progetto (`state.json`), come gli altri plug-in.

### 7.2 Esecuzione

1. All'apertura della sessione il plug-in carica l'immagine, la ingrandisce (bilineare) e la ritaglia a multipli di 64, e crea l'immagine di lavoro.
2. Per ogni `session.next`: compone il risultato precedente nell'immagine di lavoro (si incolla **tutto** il tile: fuori dalla maschera i pixel sono quelli di prima grazie a «Conserva»); ritaglia il tile successivo; scrive il PNG del tile e quello della maschera nel `tempFolder`; risponde con il passo autonomo.
3. A fine sessione (`finished`) salva l'immagine composta come PNG nella Scrivania (`Tiled Upscale 001.png`, primo numero libero, mai sovrascrivendo) e offre «Usa come immagine di partenza» (`contribute.startImage`).
4. Il prompt, il LoRA e il preset vengono dalla tabella «modello → preset» del plug-in; `registerPresets` registra il preset con la sigla `TUP · …` (come `SLR · …`), citato per nome nei passi.

Nessuna rete: il plug-in non scarica nulla.

## 8. Errori e sicurezza

- Immagine illeggibile, troppo grande o fuori limite: avviso nel tab, niente pipeline.
- Modello non supportato (non edit o senza preset in tabella): avviso, tasto «Prepara» spento.
- Il LoRA del preset non è sul server: l'app lo segnala come per ogni preset; la sessione non parte.
- Un `session.next` con risposta non valida (file mancante, `size` non multiplo di 64 o oltre 1024, maschera di dimensione diversa dal tile): la sessione si chiude con `failed` e il motivo.
- Il `tempFolder` della sessione si svuota a ogni `session.end`.

## 9. Verifica

- **`TileGrid` (test):** esempi della §3 (2560 + Z, un lato ≤ 1024, ultimo tile largo `overlap + 64`), per 256 e per 320; ritaglio centrato e nessun ritaglio se già in base 64; le quattro forme di maschera e il margine libero 200 / 250; composizione senza spostamenti di pixel.
- **Contratto (test):** lettura della pipeline guidata e del passo autonomo; campi mancanti o fuori limite; `PluginKit/README.md` aggiornato.
- **Sessione (test dell'app/HubCore con un plug-in finto):** passi eseguiti in ordine, lock, Stop, errore, chiusura con progetto cambiato, risultato che arriva al passo seguente.
- **Prova dal vivo** con server e FLUX.2 klein dietro una variabile d'ambiente (come Depth & Pose): un'immagine piccola a 2×, controllo che la giunzione sia a livello di pixel.
- **Prove a mano dell'utente:** 2× su un'immagine piccola, 4× su una media; con 256 e con 320.

## 10. Rinviati

- Ripresa di una sessione interrotta.
- Qwen Image 2.1 (preset e LoRA in attesa di prove dell'utente), altri modelli edit.
- Tile adattivi (ancorare l'ultimo tile al bordo con dimensione piena invece di un tile piccolo): se i tile piccoli rendono peggio, si cambia solo la funzione che calcola l'ultimo tile.
- Sovrapposizione libera, tile di dimensioni diverse da 1024, ingrandimenti diversi da 2/4/8.
- Risultati intermedi nei Risultati.

## 11. Da verificare nel codice, nel piano

- Convenzione della maschera (`MaskBitmap`, cosa vuol dire bianco) e come si passa una maschera per passo a `GenerationInputs`.
- Come l'app ricava la dimensione di generazione da `size` e che la card Canvas non la riporti a una cornice diversa.
- Il `tempFolder` per sessione (creazione, pulizia) e il timeout di `session.next`.
- Il numero minimo di versione dell'app da dichiarare per `guided`/`session.*` (README del kit).
