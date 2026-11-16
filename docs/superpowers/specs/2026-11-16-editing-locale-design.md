# Editing locale: design

Data: 2026-11-16. Stato: approvato dall'utente.

## Obiettivo

Ritoccare una parte di un'immagine qualsiasi alla sua risoluzione reale e rimetterla al suo posto, raccordata nei colori.
È la procedura che Panorama 360 e Panorama 360 F3 offrono già per i panorami (estrai, ritocca, rimetti), portata a tutte
le immagini. Invece di zoomare in un visore sferico, la porzione si sceglie disegnando un riquadro sull'immagine di
partenza.

Il motivo: un modello lavora a una dimensione limitata. Rigenerare un'immagine grande per correggere un dettaglio costa
tempo e cambia anche ciò che andava bene; ritagliando, il dettaglio ha tutti i pixel che il modello può dare, e il resto
dell'immagine non si tocca.

## Decisioni prese con l'utente

- **Dove:** in Control, nella card Canvas, una terza modalità **«Editing locale»** accanto a «Canvas» e «Disegno».
- **Cosa si vede:** l'immagine di partenza intera; uno strumento traccia un riquadro che sceglie la porzione.
- **Il ritaglio diventa l'immagine di partenza temporanea**, alla sua risoluzione reale (approccio 1, sotto).
- **Reinserimento solo con un pulsante di conferma**: il ritocco può non riuscire al primo tentativo, quindi il riquadro
  resta finché non si conferma, e si può rigenerare dallo stesso ritaglio quante volte si vuole.
- **La sessione si chiude solo con Annulla esplicito o con Conferma.** Passare a Canvas o Disegno e tornare non la
  chiude.

## Proposte accettate dall'utente

- **Anteprima sul posto:** in Editing locale la card mostra l'immagine intera con il ritocco già dentro il riquadro.
  Se dallo stesso ritaglio ci sono più tentativi, le frecce ‹ › li sfogliano; si conferma quello mostrato.
- **Conferma:** l'immagine intera montata va nei Risultati, diventa la nuova immagine di partenza, il riquadro sparisce.
- **Annulla:** toglie il riquadro e rimette l'immagine di partenza originale; i tentativi restano nei Risultati.
- **Riquadro a multipli di 64:** si allarga da solo fino a lati multipli di 64 (come Pano 360): un po' più di immagine,
  niente stirato. La tab Generazione prende la dimensione del ritaglio, con HiRes (beta) acceso se un lato supera 2048.
- **Raccordo dei colori:** bordo sfumato e guadagno per canale (rosso, verde, blu) letto attorno al riquadro, così colore
  e luminosità del ritocco si allineano all'immagine intera.
- **Maschera:** se c'è una maschera di Disegno, viene ritagliata insieme all'immagine.
- **Fuori dalla prima versione:** montaggio automatico, più riquadri insieme, strumenti MCP dedicati.

## Approcci considerati

1. **Il ritaglio diventa davvero l'immagine di partenza** (scelto dall'utente). «Usa il ritaglio» mette il ritaglio come
   immagine di partenza di Control; originale, riquadro e stato di prima restano in una sessione salvata nel progetto.
   Run, coda, plug-in, agenti MCP, Forza e Disegno vedono una normale immagine di partenza e non cambiano. Costo: fuori
   dalla modalità Editing locale, la modalità Canvas mostra il ritaglio e non l'immagine intera.
2. **L'originale resta l'immagine di partenza, il ritaglio si applica a Run** (come l'inquadratura). Canvas mostrerebbe
   sempre l'immagine intera, ma ogni lettore dell'immagine di partenza (contesto dei plug-in, MCP, coda, dimensioni,
   Forza, maschera) dovrebbe conoscere il ritaglio: basta dimenticarne uno perché un plug-in lavori sull'intera mentre
   Run usa il ritaglio. Scartato.
3. **Un plug-in a parte**, come Pano 360. Scartato: l'utente lo vuole in Control, accanto a Canvas e Disegno.

## Comportamento

### Entrare

- La modalità è disponibile solo con un'immagine di partenza. Senza, il selettore la mostra spenta.
- In Editing locale, senza sessione, la card mostra l'immagine di partenza intera (senza inquadratura, zoom né rotazione:
  il file così com'è) e il trascinamento traccia il riquadro. Il riquadro si può spostare trascinandolo dall'interno e
  ridimensionare dagli angoli; Esc lo toglie.
- Sotto l'immagine: dimensione del ritaglio dopo l'arrotondamento e posizione in pixel, e il pulsante **«Usa il
  ritaglio»**.
- **Arrotondamento:** ogni lato si allarga al multiplo di 64 successivo, attorno al centro del riquadro; se esce
  dall'immagine si sposta dentro; se l'immagine stessa è più piccola, il lato si ferma al multiplo di 64 che ci sta.
  Lato minimo 512, massimo 4096 (vedi le scelte in fondo). Un'immagine con un lato sotto 512 non permette l'Editing
  locale (il pulsante dice perché).

### Usa il ritaglio

In un passo solo, che ⌘Z annulla per intero:

- il ritaglio (pixel dell'immagine originale, nessun ridimensionamento) diventa l'immagine di partenza;
- la sessione ricorda: l'immagine originale, il riquadro in pixel dell'originale, l'inquadratura, la maschera, il
  disegno a pennello e la Forza di prima, e larghezza, altezza e HiRes della tab Generazione di prima;
- maschera e disegno, se ci sono, vengono ritagliati allo stesso riquadro;
- **la tab Generazione prende le dimensioni esatte del ritaglio in pixel** (decisione dell'utente): larghezza e altezza
  della generazione sono quelle del ritaglio, senza arrotondamenti né riduzioni; HiRes (beta) si accende se un lato
  supera 2048, perché senza HiRes la tab riduce i lati a 2048.

### Durante la sessione

- Run, coda e plug-in lavorano sul ritaglio come su qualsiasi immagine di partenza. Disegno dipinge la maschera sul
  ritaglio. Canvas mostra il ritaglio.
- **Modalità Incrementale sospesa** (decisione dell'utente): finché la sessione è aperta un risultato non diventa la nuova
  immagine di partenza, e ogni tentativo riparte dal ritaglio originale. L'interruttore resta com'è e torna ad agire
  quando la sessione si chiude. Nessun avviso a ogni Run.
- Sostituire o togliere l'immagine di partenza (trascinandone un'altra, Incolla, la X del Canvas, «Usa come immagine»
  dai Risultati, un plug-in o un agente) è rifiutato con l'avviso «Conferma o annulla prima l'Editing locale».
- **Tentativi** (decisione dell'utente): sono i risultati recenti, di immagini e non video, con **esattamente** le
  dimensioni in pixel del ritaglio. «Recenti» vuol dire usciti dall'apertura della sessione (scelta di chi scrive: un
  risultato di prima con le stesse dimensioni per caso non è un ritocco di questo ritaglio). Ognuno va nei Risultati
  come oggi. La sessione ne ricorda i file, così sopravvivono al riavvio.
- In Editing locale la card mostra l'originale intero con il tentativo scelto montato dentro il riquadro, esattamente
  come verrà confermato, a risoluzione di anteprima. Senza tentativi mostra l'originale con il riquadro tratteggiato.
- Comandi: **‹ n/m ›** per sfogliare i tentativi (si parte dal più recente; un tentativo nuovo diventa quello mostrato),
  l'interruttore **«Raccorda colori»** (acceso), **Annulla** e **Conferma e rimetti nell'immagine** (spento senza
  tentativi, con il motivo nel suggerimento).
- Un tentativo cancellato dai Risultati sparisce dall'elenco.

### Conferma

- Monta l'originale e il tentativo mostrato a risoluzione piena, salva il montaggio come nuovo risultato del progetto
  (dimensioni dell'originale, prompt del tentativo, descrizione «Editing locale» con il riquadro), lo mette come
  immagine di partenza al posto del ritaglio.
- **Gli altri tentativi vengono eliminati** (decisione dell'utente): tutti tranne quello confermato vanno nel Cestino,
  come con «Sposta nel cestino» della finestra Risultati (si recuperano dal Cestino del Finder). Il tentativo confermato
  resta nei Risultati accanto al montaggio.
- Rimette inquadratura, maschera, disegno, Forza, dimensioni e HiRes di prima. La sessione si chiude.

### Annulla

- Rimette l'immagine originale e tutto lo stato ricordato. La sessione si chiude; i tentativi restano nei Risultati.
  ⌘Z la riapre.

### Montaggio

1. Il tentativo ha già le dimensioni del ritaglio: si incolla pixel per pixel, senza ridimensionamenti.
2. **Raccordo colori** (se acceso): si confrontano la cornice del ritaglio originale e la stessa cornice del tentativo,
   una fascia interna larga quanto la sfumatura. Per ogni canale il guadagno è (media originale + 1) / (media tentativo
   + 1), limitato fra 0,2 e 5, come nella cucitura di Pano 360. Il guadagno si calcola per lato e si interpola sulla
   superficie, così un ritocco più scuro da una parte sola si raccorda bene; poi si applica a tutto il tentativo.
3. **Sfumatura:** il tentativo si incolla sull'originale con un bordo che sfuma verso l'interno, largo il 3% del lato
   corto del ritaglio, con un minimo di 8 pixel.

### Persistenza

- La sessione sta in `ControlInputs` ed è salvata con il progetto (originale e ritaglio nella cartella delle immagini di
  Control). Un file di Control senza sessione si legge come oggi.
- Cambiare progetto lascia la sessione nel suo progetto; riaprirlo la ritrova.

## Scelte di chi ha scritto il design (dopo la revisione)

- **Dimensioni del ritaglio:** lato minimo 512 (come Pano 360: sotto, i modelli rendono male), lato massimo 4096. Un
  riquadro più piccolo si allarga fino a 512 attorno al centro; uno più grande non si può tracciare oltre 4096. Le regole
  di «Entrare» valgono con questi limiti al posto di 256.
- **HiRes durante la sessione:** acceso se un lato supera 2048, spento altrimenti, anche se prima era acceso; alla fine
  della sessione torna com'era. Le altre impostazioni (Tiled Diffusion compresa) non si toccano.
- **Pipeline:** un passaggio di pipeline che finisce nei Risultati conta come tentativo solo se ha esattamente le
  dimensioni del ritaglio; un'uscita ingrandita (upscaler, passaggi 2×) non conta.
- **Tentativi fuori dalla cronologia:** l'elenco dei tentativi è salvato con la sessione ma non entra in annulla/ripeti,
  come gli interruttori del Moodboard: ⌘Z su una pennellata non fa sparire un tentativo.
- **Dimensioni della tab Generazione:** non entrano nella cronologia di Control. Seguono la sessione: ogni volta che una
  sessione si apre (anche con ⌘Z o riaprendo il progetto) la tab prende la dimensione del ritaglio; ogni volta che si
  chiude (Conferma, Annulla o ⌘Z) torna alle dimensioni ricordate all'apertura. Cambiarle a mano durante la sessione è
  permesso; alla chiusura vincono quelle ricordate.
- **⌘Z dopo Conferma:** riapre la sessione con lo stesso ritaglio e il solo tentativo confermato (gli altri sono nel
  Cestino); il montaggio resta nei Risultati. Ripeti richiude, senza altro da cestinare.
- **⌘Z dopo Annulla:** riapre la sessione con i tentativi che sono ancora nei Risultati.

## Architettura

- **HubKit:** `LocalEditSession` (Codable) dentro `ControlInputs`, opzionale.
- **HubCore, funzioni pure con test:** arrotondamento del riquadro; ritaglio di immagine, maschera e disegno; guadagno per
  canale e montaggio. Il codice si riscrive partendo da Pano 360 (`PSCutout`, `PSSeamImages`, `PSPixels.scaled`): i
  plug-in sono pacchetti a parte e non si toccano.
- **HubCore, `ControlStore`:** entrare, confermare, annullare, con annulla/ripeti; rifiuto di sostituire l'immagine
  durante la sessione.
- **App:** la conferma cestina gli altri tentativi con lo stesso percorso di «Sposta nel cestino» dei Risultati.
- **App:** terza modalità in `CanvasStage`, strumento del riquadro, anteprima, comandi; `GenerationController` raccoglie
  i tentativi, salva il montaggio come risultato e cambia dimensioni e HiRes.
- Localizzazione italiano e inglese.

## Fuori dal progetto

- Montaggio automatico a ogni risultato.
- Più riquadri contemporaneamente.
- Strumenti MCP dedicati (un agente vede comunque il ritaglio come immagine di partenza).
- Editing locale su video.
- Modifiche ai plug-in Panorama 360 e Panorama 360 F3.
