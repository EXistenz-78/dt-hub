# Plug-in Seamless Pattern — design (25 novembre 2026)

Plug-in per DT Hub che genera **immagini che si ripetono senza giunzione** (pattern) con Krea 2, Z-Image, FLUX.2 [klein] e
FLUX.3 [klein]. Il lavoro tocca tre parti: il **fork del motore** (server gRPC custom), l'**app** (codec e contratto dei
plug-in) e il **plug-in** nuovo. Compatibile MCP dalla prima versione.

## Perché

L'utente vuole pattern da usare in Photoshop e in qualunque programma di grafica che gestisca i pattern. Non serve un formato
speciale: basta un PNG i cui bordi opposti si uniscano. Oggi un'immagine "tileable" esce solo con un seed fortunato oppure con
un ritocco della giunzione; qui deve uscire **ogni volta**, per costruzione.

## Fonte

Il nodo ComfyUI **Seamless Tile Pixaroma** (`comfyui-pixaroma/nodes/node_seamless_tile.py` e `_seamless_helpers.py`).
L'idea di riportare le frequenze di posizione a un numero intero di giri segue il paper SpheRoPE (Hirschorn et al., 2026).
Implementazione nostra, in Swift. Della fonte si porta solo la parte per i transformer (RoPE) e per il VAE; la parte UNet
(SDXL / SD 1.5) **non** si porta.

## Obiettivi

1. Con il plug-in, un RUN di Krea 2, Z-Image, FLUX.2 [klein] o FLUX.3 [klein] produce un'immagine che si ripete
   in orizzontale, in verticale o in entrambe le direzioni, a scelta.
2. La giunzione è esatta: nessun ritocco a posteriori, nessuna maschera, nessun inpainting.
3. Il plug-in mostra il risultato ripetuto (anteprime) e misura la giunzione.
4. Un agente MCP può fare tutto quello che fa la tab.

## Non obiettivi

- SDXL, SD 1.5, Flux1, Ming-Image e ogni altra famiglia.
- Video.
- Mappe per materiali 3D (normal, roughness, height, AO, come il nodo *Seamless Material Pixaroma*): **versione 2**.
- Rendere seamless un'immagine già esistente.
- Esportare in formati di pattern specifici (`.pat` di Photoshop ecc.): basta il PNG.

## Anti-obiettivi (sarebbe un fallimento anche se funziona)

- **Una generazione normale che cambia anche di un bit.** Senza il plug-in, l'app manda al server esattamente i byte di oggi e
  il server calcola esattamente gli stessi tensori di oggi.
- **Un RUN seamless "nascosto"**, cioè senza che l'utente veda che il prossimo RUN sarà seamless (o il contrario).
- **Un'immagine che sembra seamless ma non lo è senza nessun avviso**: per esempio con un server che ignora il flag. Il plug-in
  deve rifiutarsi di preparare il RUN, non lasciarlo passare.

## Vincoli

- Le dimensioni in DT Hub vanno a passi di 64 px (`DimensionsCard`, `PluginSession`). Le quattro famiglie richiedono multipli
  di 16 px, quindi **nessun controllo di dimensione** nel plug-in. Il server tiene una sola verifica difensiva (vedi sotto).
- Il flag funziona solo con il **server custom** di DT Hub (fork). L'app Draw Things e i server stock non lo conoscono.
- I plug-in non generano da soli: preparano, e l'utente preme RUN (regola del contratto).
- I valori avanzati della tab (tiled decoding, tiled diffusion…) non si possono cambiare da un passo di pipeline. Perciò è
  il **server** a escluderli quando il flag è acceso.

## Approcci considerati (scelto: B)

- **A — Send to Generation, flag valido per un solo RUN.** È il gesto degli altri plug-in, ma il flag diventa uno stato
  nascosto della tab. Per provare più seed bisogna tornare ogni volta al plug-in, e restano da definire i casi in cui
  l'utente cambia modello o dimensione. Scartato perché porta proprio al "RUN seamless nascosto".
- **B — Pipeline di un passo "Run · Seamless"** (scelto). Il plug-in propone a DT Hub una pipeline di un passo che porta il
  flag. Il bottone RUN mostra "Run · Seamless", quindi lo stato è sempre visibile. Si può premere RUN quante volte si vuole,
  cambiando seed o prompt, e funziona con la coda. Si esce con *clear pipeline* o spegnendo il plug-in. Riusa il meccanismo di
  *Fix the seam* di Panorama 360.
- **Opzioni tecniche scartate per il VAE:** decode a tile con margine avvolto e ritaglio (come il nodo in caso di memoria
  scarsa). Dà una giunzione quasi esatta, non esatta, e richiede più codice. Si sceglie il **decode intero** con wrap; il
  margine si potrà aggiungere più avanti se serve.

## Come funziona (decisioni prese)

### 1. Fork del motore (server gRPC custom)

**Configurazione.** Nuovo campo in `Libraries/DataModels/Sources/config.fbs`, in fondo alla tabella (compatibilità FlatBuffers):

```
seamless_tile: byte = 0;   // 0 off, 1 left-right, 2 up-down, 3 both
```

Il default 0 rende il comportamento identico a oggi per ogni client che non lo manda.

**Famiglie.** Il campo viene letto **solo** per `.krea2`, `.zImage`, `.flux2`, `.flux2_9b`, `.flux2_4b`, `.flux3_5b`. Per ogni
altra versione si ignora: Ming usa anche `ZImageRotaryPositionEmbedding`, quindi questa seconda protezione, oltre al plug-in,
è voluta.

**RoPE a toro.** Le quattro funzioni `Krea2RotaryPositionEmbedding`, `ZImageRotaryPositionEmbedding`,
`Flux2RotaryPositionEmbedding` e `Flux3RotaryPositionEmbedding` ricevono un parametro opzionale (es.
`seamless: SeamlessAxes? = nil`). Con `nil` il codice resta quello di oggi. Con il flag acceso, solo per gli **assi altezza e
larghezza dei token dell'immagine**:

```
ω_k   = 1 / θ^(2k/dim)                               // la frequenza di oggi
giri  = round(ω_k · P / 2π);  se ω_k·P/2π < min_turns → giri = 0
ω'_k  = giri · 2π / P
angolo = (pos mod P) · ω'_k                           // in Double
```

`P` è il periodo **nelle unità di posizione della funzione**: `gridHeight` / `gridWidth` per Krea 2, Z-Image e FLUX.2;
`gridHeight · 0.5` / `gridWidth · 0.5` per FLUX.3, che usa posizioni `y·0.5, x·0.5`. Costanti attuali: θ = 1000 (Krea 2),
256 (Z-Image), 2000 (FLUX.2), 10000 (FLUX.3).

`min_turns` di partenza, presi dal nodo: **Z-Image 1.0**, **Krea 2, FLUX.2, FLUX.3 0.5**. Si tarano con i test (vedi
"Verifica").

Restano invariati:
- l'asse 0 (frame / indice) e, per FLUX.2, l'asse 3;
- i token di testo;
- per Krea 2, le immagini di riferimento: stessa griglia, stesso trattamento degli assi y/x, frame diverso;
- le chiamate da `LoRAImporter`, `ModelImporter` e `LoRATrainer`, che non passano il parametro.

Il periodo segue la griglia **di ogni passo**: con HiRes fix il primo passo e il secondo hanno griglie diverse e ciascuno usa la
sua.

**VAE con wrap.** Due decoder ricevono un parametro opzionale `wrap` (default spento = grafo di oggi):
- **`Decoder`** (`Autoencoder.swift`): copre Z-Image (ramo 16 canali, `FirstStage.swift` intorno alla riga 373) e
  FLUX.2 / FLUX.3 (ramo 32 canali, intorno alla riga 533). Che sia anche il decoder di Flux1/SD3 non conta: per loro il flag non
  si legge.
- **`WanDecoderCausal3D`** (`WanVAE.swift`): usato da Krea 2 (ramo intorno alla riga 687). Si avvolge solo il padding
  spaziale; il padding temporale causale resta com'è, perché l'immagine è un solo frame.

Con il wrap acceso, ogni convoluzione che ha un bordo sull'asse avvolto riceve un input allargato con le righe/colonne del lato
opposto (slice + concat, come `wrap_pad` del nodo), e il suo bordo su quell'asse va a 0. Il bordo sull'altro asse resta quello
di oggi. Un decoder costruito con il wrap è un **grafo diverso**: non si riusa l'`existingDecoder` in cache quando il wrap
cambia.

**Decode intero.** Con il flag acceso il server **ignora il tiled decoding** e decodifica in un colpo solo. Se la memoria non
basta, la generazione fallisce con un messaggio chiaro, non con un decode a tile senza wrap.

**Tiled diffusion.** Con il flag acceso il server **ignora il tiled diffusion**: un modello valutato a tile spezzerebbe il toro.

**Verifica difensiva.** Se la griglia di latent non è compatibile (per esempio non è divisibile per il patch), il server rifiuta
la generazione con un errore che lo dice. Non fa mai una generazione normale al posto di quella seamless.

### 2. App (DT Hub)

- **Codec** (`DTBridge/ConfigurationCodec.swift`): il campo si scrive **solo** quando il job lo porta. Un job normale produce
  gli stessi byte di oggi.
- **Non è un `AdvancedField`**: non compare nella tab Generazione, nei preset né in `set_advanced` dell'MCP generale.
- **Contratto dei plug-in, due aggiunte** (in `PluginKit/README.md`):
  1. **Passo di pipeline**: chiave nuova `"seamless": "both" | "leftRight" | "upDown"`. Vale solo per quel passo. L'app la
     rifiuta con un `problem` se il server attivo non è quello custom o se la famiglia del modello non è una delle quattro.
  2. **Contesto**: chiave nuova `customServer: true|false` (assente in un'app più vecchia). Vale `true` quando il server è
     quello gestito con il binario incluso nell'app (`ManagedServerSettings.usesBundledServer()` in modalità gestita). Un server
     remoto, l'app Draw Things o un altro gRPC valgono `false`.
  3. **Ritiro della pipeline**: oggi un plug-in può proporre una pipeline ma non toglierla. Serve un messaggio con cui un
     plug-in ritira **la propria** pipeline proposta, senza toccare quella di un altro plug-in o dell'utente.
- **Plug-in spento o famiglia non supportata** (scelta mia): se il plug-in si spegne, anche perché l'utente passa a un modello
  di un'altra famiglia, l'app toglie la pipeline seamless. Il bottone torna "Run" e non resta mai un "Run · Seamless" su un
  modello che non lo supporta.
- **Coda**: un'entry creata con "Run · Seamless" attivo conserva il flag.

### 3. Il plug-in

**Nome**: *Seamless Pattern*. Famiglie: Krea 2, Z-Image, FLUX.2 [klein] 9B e 4B, FLUX.3 [klein]. Su ogni altra famiglia la
tab è nascosta (regola già in vigore per i plug-in). Stato salvato per progetto: modo, vista, ultimo risultato mostrato.

**Interfaccia:**

```
┌ Seamless Pattern ─────────────────────────────────┐
│ Repeat:  (●) Both  ( ) Left-right  ( ) Up-down    │
│ [ Prepare Run · Seamless ]   [ Stop seamless ]    │
├───────────────────────────────────────────────────┤
│ Last result    View: Tile | 2×2 | 3×3 | Offset |  │
│ ┌──────────┐         Half-drop | Half-brick       │
│ │  ░▒▓▒░   │   Seam:  ←→ PASS    ↑↓ PASS          │
│ └──────────┘   [ Save PNG… ]  [ Show in Finder ]  │
└───────────────────────────────────────────────────┘
```

- **Repeat**: Both / Left-right / Up-down.
- **Prepare Run · Seamless**: propone la pipeline di un passo con il flag. Il passo non cambia i campi della tab: prompt, seed,
  dimensione, LoRA e preset restano quelli dell'utente. Cambiare il modo con la pipeline già proposta la ripropone.
- **Stop seamless**: toglie la pipeline proposta dal plug-in (lo stesso effetto di *clear pipeline*). Spegnere il plug-in ha
  lo stesso effetto.
- **Anteprima**: mostra l'ultimo risultato. *Tile* è l'immagine; *2×2* e *3×3* la ripetono; *Offset* la sposta di mezzo tile
  in tutte e due le direzioni, così gli angoli si incontrano al centro; *Half-drop* sono 3 colonne con quella centrale scesa di
  mezzo tile; *Half-brick* sono 3 righe con quella centrale spostata di mezzo tile. Si può trascinarci un'immagine dai Results
  o dal Finder per vederla ripetuta.
- **Seam**: il controllo della giunzione del nodo, portato in Swift (`seam_check`). Per ogni direzione confronta il salto di
  colore sulla linea di wrap con quello delle linee interne ogni 4 px. **PASS** se la linea di wrap non è la peggiore,
  **WARN** se è la peggiore ma entro 1,25 volte la seconda, **FAIL** se spicca, **N/A** sotto 64 px. Per la direzione non
  richiesta mostra solo il valore, senza giudizio.
- **Save PNG…** salva il tile (l'immagine, non la vista). **Show in Finder** apre il file del risultato.
- **Server non custom**: la tab mostra solo un avviso che lo spiega; tutto il resto è disattivato.

**Flusso tipico**: scegli il modello (una delle quattro famiglie) → scrivi il prompt nella tab Generazione → nel plug-in
*Prepare Run · Seamless* → il bottone dice "Run · Seamless" → RUN, più volte se vuoi → guardi le viste e il Seam nel plug-in →
*Save PNG…* → in Photoshop *Edit › Define Pattern*.

**MCP** (strumenti `plugin__seamlesspattern__<tool>`, regole di
`docs/superpowers/specs/2026-11-08-server-mcp-design.md`, con una sezione nuova lì):
- `get_status` (read): modo, se la pipeline è proposta, `customServer`, famiglia del modello, ultimo risultato e il suo Seam.
- `set_mode` (edit): `both | leftRight | upDown`.
- `prepare_run` (edit, `startsRun`): propone la pipeline. Il RUN lo fa l'agente con `run_pipeline`, come per gli altri
  plug-in.
- `stop` (edit): toglie la pipeline.
- `check_seam` (read): il Seam di un `result_id` dato.

Come per ogni plug-in nuovo: file `SPTools.swift` con i suoi test, paragrafo «For AI agents (MCP)» nel README del plug-in,
riga in `Plugins/README.md` e in `README.md` («Plug-in tools»), test sul bundle reale in `RealPluginToolsTests.swift`.

## Verifica

- **Invarianza.** Con il flag spento, i tensori RoPE delle quattro funzioni sono identici byte per byte a quelli di oggi (test
  nel fork). Il codec di un job normale scrive gli stessi byte di oggi (test nell'app).
- **Matematica.** Per ogni famiglia, con il flag acceso: l'angolo in posizione `P` è uguale a quello in 0, e la RoPE dei token
  di testo è invariata.
- **Wrap del decoder.** Un latent periodico, decodificato e poi spostato di metà larghezza con `roll`, non mostra salti al
  centro: il Seam dà PASS.
- **Risultati reali.** Per ognuna delle quattro famiglie, una serie di prompt (texture, fantasie, scene) a 1024 e 1536 px,
  modo Both. Si guarda il Seam e si controlla a occhio il caso "tile ripetuto più volte dentro il tile" (il problema che ha
  portato `min_turns` a 1.0 per Z-Image). Si correggono i `min_turns` se serve.
- **Plug-in.** Test del modello del plug-in, di `seam_check` (casi PASS / WARN / FAIL / N/A) e delle viste. Bundle reale per
  gli strumenti MCP.

## Lasciato a chi costruisce

- I nomi esatti di tipi e parametri nel fork (`SeamlessAxes`, `wrap`…) e il punto preciso in cui il flag passa da
  `GenerationConfiguration` alle funzioni RoPE e ai decoder.
- Come portare il wrap dentro `WanDecoderCausal3D`, che ha conv causali 3D, mantenendo il grafo di oggi quando il wrap è spento.
- Il messaggio d'errore esatto per la memoria insufficiente senza tiled decoding e per la griglia non compatibile.
- Il nome breve del plug-in negli identificativi (`seamlesspattern`, prefisso `SP`).
- Il testo dell'avviso per il server non custom e i tooltip, in inglese come gli altri plug-in.

## Punti da verificare nell'implementazione (non decisioni)

- **Start image e Moodboard.** Il passo della pipeline esegue la tab così com'è. Se c'è una start image, il risultato è un
  image-to-image con il toro: probabilmente funziona, ma la start image non è seamless. Lo si prova; se peggiora i risultati, il
  plug-in mostra un avviso quando la tab ha una start image.
- **Refiner.** Se il preset usa un refiner di un'altra famiglia, il flag vale solo per i passi delle quattro famiglie. Lo si
  prova.
- **Versione del server custom.** Un binario custom più vecchio non conosce il campo e lo ignorerebbe. L'app rilascia il
  plug-in insieme al server che lo supporta; se esiste un modo economico di chiedere la versione al server, `customServer` lo
  usa.
