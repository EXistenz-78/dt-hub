# DT Hub — Design del tab Control (immagine, Moodboard, inpaint)

Data: 1 ottobre 2026 · Stato: bozza da approvare · Estende `2026-09-29-dt-hub-core-design.md`

## 1. Scopo

Un tab del cuore dell'app, **Control**, collocato **prima** di Generazione, dove si preparano gli ingressi immagine di una generazione: l'**immagine di partenza** (I2I), il **Moodboard** e la **maschera di inpaint**. Alimenta il normale RUN.

Nasce da un difetto dell'interfaccia di Draw Things: le immagini di controllo sono scomode da gestire, difficili da togliere e non si vede cosa è stato caricato in quale campo. DT Hub deve farlo meglio, e permettere di **trascinare le miniature della finestra Risultati** direttamente negli ingressi.

Decisioni dell'utente (1 ottobre 2026):
- il tab è del cuore e precede la v1 dei plug-in; anticipa le voci "Riferimenti" ed "Espandi e maschera" della spec principale (§2) e va **prima di M7 Plug-in** (che diventa M8);
- prima versione: immagine di partenza, Moodboard con pesi, inpaint con pennello semplice;
- l'**outpaint** si aggiunge quando l'inpaint funziona; comporta ridimensionare l'immagine di partenza nel canvas (il modo "Contieni", sezione 5);
- Depth, Pose, Scribble, Color Palette, Custom e i ControlNet restano **fuori**: i ControlNet disponibili per DT sono per modelli vecchi (SD, Flux.1) e l'utente non ha modo di convertirne per modelli recenti;
- il Tiled Diffusion con dimensioni fino a 8192×8192 si fa **prima dell'outpaint** (voce del backlog).

## 2. Perimetro

**Dentro:**
- immagine di partenza con forza (strength) e inquadratura nel canvas;
- Moodboard: più immagini, ognuna con peso, interruttore acceso/spento, rimozione e riordino;
- maschera di inpaint con pennello e gomma, annulla/ripeti, inverti, svuota; sfumatura, margine, "conserva l'originale";
- striscia "Con Run parte", gestione unificata di ciò che è caricato;
- trascinamento da Risultati, dal Finder, incolla da appunti; menu "Usa come immagine" / "Aggiungi al Moodboard" in Risultati;
- ripristino all'avvio e annulla delle rimozioni.

**Fuori:** ControlNet e hint di Depth, Pose, Scribble, Color Palette, Custom; outpaint (arriva dopo, ma il modello dati lo prevede); selezioni (rettangolo, ellisse), riempimento, livelli; modifica dei pixel dell'immagine (non è un editor).

**Modelli Edit (Flux Kontext, Qwen Image Edit e simili):** verificato su documentazione di Draw Things e sul catalogo (campo `modifier`: `kontext`, `kontext_kv`, `qwenimage_edit_plus`, `editing`, `inpainting`). Non richiedono un tipo di ingresso nuovo: il **canvas** è l'immagine da modificare (forza 100%) e il **Moodboard** porta le reference aggiuntive; per una reference sola si usa il Moodboard con **canvas vuoto**. Ogni reference in più aumenta il tempo di render più che linearmente.

## 3. Interfaccia

**Posizione.** Il tab Control precede Generazione nella barra dei tab. All'avvio si apre l'ultimo tab usato. Il design system è quello dell'app (turchese come accento, arancio per ciò che si toglie, pannelli con raggio 19, titoli di gruppo in monospaziato maiuscolo).

**Striscia "Con Run parte"** (in alto). Un chip per ogni ingresso attivo: Immagine (con dimensioni), Maschera (con la percentuale coperta), Moodboard (con il numero). Ogni chip ha una ✕ che toglie l'ingresso; "Svuota tutto" in arancio ripulisce tutto. Qui compaiono gli avvisi (maschera senza immagine, ritaglio forte, famiglia che non usa il Moodboard, copia mancante). Cliccare un chip porta alla sua scheda.

**Scheda Immagine** (sinistra):
- miniatura con ✕ sempre visibile, nome, dimensioni, provenienza ("da Risultati", "dal Finder", "da <plug-in>");
- pulsanti "Sostituisci" e "Usa le dimensioni" (vedi §5);
- cursore **Forza** 0–100% con campo numerico. **Automatica** finché l'utente non la sceglie: 100% per i modelli Edit (la scheda dice "Modello Edit: l'immagine viene modificata, forza al 100%"), 70% per gli altri, perché con un I2I normale a 100% l'immagine viene ignorata. Una scelta dell'utente vince; "Automatica" la riporta al valore del modello;
- zona di rilascio: trascinare un'immagine la imposta; se ce n'era una, la sostituisce con annulla.

**Scheda Moodboard** (sinistra, sotto):
- griglia di miniature; ognuna ha ✕ sempre visibile, **occhio** (spegne senza cancellare: la miniatura si attenua), cursore della **quota** con valore digitabile;
- **le quote sono fette di una torta da 100%, non valori indipendenti** (deciso con l'utente, 2 ottobre 2026): la somma delle immagini accese fa sempre 100%. Una sola immagine vale 100%, due 50–50, tre 33–33–33 (34–33–33 con l'arrotondamento), e ogni quota resta modificabile per dare a un'immagine più peso delle altre;
- una **barra a fette** sotto il titolo della scheda mostra la torta (una fetta per immagine, nell'ordine delle miniature); i cursori e la barra si muovono insieme;
- un pulsante **Equilibra** riporta tutte le quote uguali;
- riordino trascinando le miniature;
- **regola di rilascio** (deciso con l'utente): rilasciare un'immagine **su una miniatura già inserita la sostituisce**; rilasciarla **in qualsiasi altro punto della scheda aggiunge**. Vale per le immagini dal Finder, da Risultati e per quelle trascinate dalla scheda Immagine;
- avviso quando le reference sono più di tre (tempo di render);
- le immagini del Moodboard sono riferimenti di stile e di contenuto, **non entrano nel canvas**: il loro rapporto non ha nessun legame con quello del canvas e non si ritagliano né si adattano mai (deciso con l'utente, 1 ottobre 2026);
- il Moodboard è usabile con le famiglie moderne (Qwen Image 2.1, Flux.2 e simili hanno I2I intrinseco e un modello con visione che interpreta le reference da solo). La scheda è grigia, con la spiegazione, **solo per le famiglie vecchie note** che richiederebbero un IP-Adapter o un ControlNet (SD 1.x e 2.x, SDXL, SSD-1B): una famiglia moderna o sconosciuta la mostra attiva.

**Pannello Maschera** (destra):
- anteprima del **canvas così come parte a Draw Things** (ritaglio compreso), con la maschera sovrapposta in arancio (area dipinta = area che verrà rigenerata);
- strumenti: Pennello, Gomma, Annulla, Ripeti, Inverti, Svuota; cursori Dimensione e Morbidezza;
- parametri di Draw Things: Sfumatura (`maskBlur`), Margine (`maskBlurOutset`), casella "Conserva l'originale fuori dalla maschera" (`preserveOriginalAfterInpaint`);
- senza immagine il pannello è vuoto con "Carica un'immagine per disegnare la maschera".

**Annulla.** Ogni rimozione, sostituzione o svuotamento si annulla con ⌘Z e con un avviso "Rimossa · Annulla" che dura qualche secondo.

**Finestra Risultati.** Le miniature della striscia diventano trascinabili (come file e come tipo interno dell'app) e hanno nel menu contestuale "Usa come immagine" e "Aggiungi al Moodboard". Il dettaglio resta com'è.

## 4. Modello dei dati

**HubKit** (tipi `Sendable`; i salvati sono `Codable` con lettura permissiva, come `GenerationParameters`):
- `ReferenceImage`: `id`, `source` (file, risultato, appunti, plug-in), nome, dimensioni in pixel, nome del file della copia.
- `Framing`: modo (`fill`; `contain` in seguito) e spostamento normalizzato dentro il canvas.
- `MaskSettings`: sfumatura, margine, conserva l'originale.
- `MoodboardEntry`: `id`, `ReferenceImage`, **peso grezzo** (≥ 0, il rapporto relativo che l'utente ha dato) e acceso/spento. Le **quote** mostrate e inviate non si salvano: si calcolano dal peso grezzo delle sole voci accese (§4.1).
- `ControlInputs`: immagine opzionale con `Framing` e forza (nil = automatica), maschera opzionale (riferimento al file) con `MaskSettings`, lista di `MoodboardEntry`.
- `GenerationInputs` (non `Codable`, non finisce nei PNG): immagine già inquadrata alla dimensione esatta del canvas, maschera (pixel **trasparenti = da rigenerare**, come vuole il client), lista di hint con tipo e peso.
- Il protocollo backend diventa `generate(_ job: GenerationJob, inputs: GenerationInputs)`; `GenerationJob` non cambia, e gli ingressi vuoti riproducono il T2I di oggi.

**Copie su disco.** Ogni immagine aggiunta viene **copiata** in `~/Library/Application Support/DT Hub/Control/<uuid>.<estensione>`. Così togliere o spostare l'originale, o l'immagine di Risultati, non rompe l'ingresso. La copia si cancella quando l'ingresso viene tolto o svuotato e le orfane si spazzano all'avvio. La maschera è un PNG a 8 bit **in coordinate dell'immagine**, nella stessa cartella: segue il ritaglio se lo si sposta.

**Persistenza.** `control.json` nella cartella di supporto, separato da `session.json`, ripristinato all'avvio come il prompt (spec principale §11). Una copia mancante fa scartare la voce con un avviso nella striscia.

**Memoria.** I pixel stanno su disco; le immagini si decodificano con ImageIO alla dimensione necessaria (miniature al volo, ritaglio al momento del RUN), perché una foto da 50 megapixel non deve stare intera in memoria. L'annulla/ripeti della maschera usa istantanee limitate a 20; quello delle voci usa copie del valore `ControlInputs` (leggero: contiene riferimenti, non pixel).

### 4.1 Quote del Moodboard

Le immagini del Moodboard sono **fette di una torta da 100**. Si salva per ognuna un peso grezzo ≥ 0; la **quota** è il peso grezzo diviso la somma dei pesi grezzi delle sole immagini **accese**, in percentuale (`MoodboardShares`, funzione pura in HubCore):
- **Numeri interi, somma esatta 100:** si arrotonda col metodo del resto più grande, quindi tre immagini uguali sono 34–33–33 (la prima di cui il resto è maggiore, a parità l'ordine delle miniature).
- **Immagine aggiunta:** prende la quota di una fetta uguale (100 ÷ numero di immagini accese); le altre si riducono **in proporzione**, conservando il loro rapporto. Da 50–50 a tre immagini: 33–33–33; da 70–30 a tre (l'ultima è la nuova): 47–20–33.
- **Immagine tolta:** le altre crescono in proporzione fino a riempire 100.
- **Quota modificata** (cursore o campo): l'immagine prende il valore scelto (0–100) e le altre si ridistribuiscono in proporzione sul resto (100 − valore). Se tutte le altre sono a zero, si dividono il resto in parti uguali. A 100 le altre vanno a 0.
- **Occhio spento:** l'immagine esce dalla torta (non conta nella somma) e le altre si ricalcolano; riaccesa, rientra con il suo peso grezzo. La sua quota mostrata è "—".
- **Tutti i pesi grezzi a zero:** quote uguali.
- **Equilibra:** imposta tutti i pesi grezzi a 1.
- **Cosa parte:** per ogni immagine accesa, un hint `shuffle` con peso = quota ÷ 100 (una sola immagine: 1,0). Che Draw Things usi i pesi così come sono, o li normalizzi a sua volta, si controlla dal vivo nel piano di M7b, senza cambiare il comportamento visibile.
- **La forza dell'immagine di partenza** (scheda Immagine) è un'altra cosa: non fa parte della torta.

## 5. Inquadratura: rapporto diverso dal canvas

Il canvas è dato dalle Dimensioni di Generazione. Tre modi di inquadrare l'immagine:
1. **Riempi (predefinito).** Il canvas resta com'è, l'immagine lo riempie e si ritaglia. La miniatura mostra il ritaglio (parti perse oscurate) e il dettaglio ("immagine 1:1 → canvas 4:3, si perde il 25% sopra e sotto"); trascinando l'immagine nel riquadro si sceglie quale parte tenere. Un ritaglio forte (oltre un terzo dell'immagine) produce un avviso nella striscia.
2. **Adatta le dimensioni.** Un pulsante esplicito, sempre disponibile: porta le Dimensioni di Generazione al rapporto dell'immagine, con **area simile** a quella corrente, multipli di 64 e nei limiti del momento (2048; 8192 con il Tiled Diffusion). È un'azione con annulla e **non si ripete da sola**.
3. **Contieni (arriva con l'outpaint).** L'immagine sta tutta nel canvas e i margini sono area da rigenerare: è la stessa cosa dell'outpaint. Il modello dati lo prevede (`Framing`); l'interfaccia lo abilita con l'outpaint.

Se il rapporto delle Dimensioni cambia dopo il caricamento, il ritaglio si ricalcola al volo. Il **Moodboard** non ha il problema: le reference sono riferimenti di stile e non entrano nel canvas, quindi il loro rapporto è ininfluente.

## 6. Dal tab al RUN

- **`InputComposer`** (HubCore): funzione pura da `ControlInputs` e dimensioni del canvas a `GenerationInputs`: ritaglia e scala l'immagine alla dimensione esatta, rende la maschera nello stesso riquadro (alfa 0 dove si rigenera), prepara gli hint dei Moodboard accesi, ciascuno con la propria quota (somma 1) come peso. Si prova con immagini generate nei test.
- **DTBridge** (`JobMapper`): riempie `image`, `mask`, hint (`HintBuilder`, tipo `shuffle` per il Moodboard) e imposta `strength`, `maskBlur`, `maskBlurOutset`, `preserveOriginalAfterInpaint`, e `enableInpainting` quando serve (da verificare, §9). `HintBuilder` e `ImageHelpers` della libreria si usano **solo** in DTBridge.
- **Più batch:** tutti riusano gli stessi ingressi.
- **Nel PNG salvato** finiscono forza, sfumatura, margine, e numero e quote delle reference (non le immagini). "Riprendi parametri" da Risultati ripristina questi numeri.
- **Blocchi in RUN:** una maschera senza immagine. Il resto sono avvisi.
- **Visibilità per famiglia** (come le card avanzate, dalla tabella del catalogo): il tab ricava dal `modifier` e dalla famiglia del modello cosa è sensato (forza 100% per i modelli Edit, Moodboard grigio solo per le famiglie vecchie note, `enableInpainting`). Una famiglia sconosciuta mostra tutto e non blocca nulla.

## 7. Plug-in (M8)

Le immagini che i plug-in propongono (in particolare Prompt Master e Sphere Light) **arrivano in queste stesse schede**, con la provenienza del plug-in; la card "Contributi" della spec principale (§8) perde la parte immagini. Se due plug-in vogliono lo stesso ingresso (l'immagine, o la maschera) c'è conflitto e RUN si blocca con un messaggio che li nomina, come già previsto.

## 8. Errori

Tutti i messaggi sono localizzati (it, en), senza testo tecnico grezzo.
- Immagine illeggibile o formato non supportato: non entra; avviso con il nome del file.
- Disco pieno o cartella non scrivibile nella copia: errore chiaro, nessuna voce a metà.
- Copia sparita all'avvio: voce scartata con avviso.
- Maschera senza immagine: RUN bloccato con il motivo.
- Il server rifiuta gli ingressi: passano dagli errori della spec principale (§10).

## 9. Test e verifiche

**Unitari (HubCore):**
- inquadratura: 1:1 in 4:3, 3:4 in 4:3, stesso rapporto, "Adatta le dimensioni" con arrotondamento a 64 e limiti;
- compositore: misura dei pixel reali (ritaglio giusto, maschera trasparente dove va, hint dei soli Moodboard accesi);
- maschera: pennello, gomma, morbidezza, inverti, svuota; annulla/ripeti con limite di memoria;
- store: aggiunta e copia, rimozione e pulizia, ripristino, copie mancanti, annulla delle rimozioni;
- regola di rilascio del Moodboard (sostituisce o aggiunge);
- quote del Moodboard (§4.1): somma sempre 100 con numeri interi, uno/due/tre/sette immagini, aggiunta e rimozione che conservano i rapporti, modifica di una quota, immagine spenta e riaccesa, tutte a zero, un'immagine al 100%.

**DTBridge:** mappatura di forza, maschera, hint e `enableInpainting` nel `JobMapper`.

**Dal vivo con un server vero**, con un modello leggero: una I2I, un inpaint e un Moodboard. Una sola verifica aperta, da risolvere nel piano di M7c leggendo il client e provando: **quando serve `enableInpainting`** (modelli senza `modifier` inpainting). Le altre due domande (rapporto del Moodboard, famiglie che lo usano) hanno già risposta dall'utente e dalla documentazione di Draw Things.

**A mano (utente):** trascinamenti, pennello, ripristino all'avvio.

## 10. Moduli e confini

| Modulo | Cosa riceve |
|---|---|
| HubKit | I tipi della sezione 4; il protocollo backend con gli ingressi |
| HubCore | `ControlStore` (stato, annulla/ripeti, persistenza), `ReferenceStorage` (copie su disco, finto nei test), `FramingMath`, `InputComposer`, `MaskBitmap` (buffer a 8 bit con pennello, gomma, morbidezza, inverti), le regole per famiglia, la regola di rilascio, `MoodboardShares` (la matematica delle quote, §4.1) |
| DTBridge | `JobMapper` esteso; l'unico che usa `HintBuilder` |
| App | `ControlTabView`, striscia, schede Immagine e Moodboard, `MaskStage` (SwiftUI `Canvas` con gesto di disegno), trascinamento (`Transferable`), modifiche a Risultati, `WorkspaceState` con due tab del cuore |

Le regole di dipendenza della spec principale (§4) non cambiano.

## 11. Tappe

Ognuna con piano, revisione indipendente e merge, come M4.

| Tappa | Contenuto | Esito |
|---|---|---|
| **M7a** | Tab Control davanti a Generazione, striscia, scheda Immagine (Riempi, Adatta le dimensioni, forza), copie e ripristino, trascinamento da Risultati, dal Finder e incolla, "Usa come immagine" in Risultati, RUN con I2I | **l'I2I funziona** |
| **M7b** | Scheda Moodboard (pesi, interruttore, regole di rilascio, riordino), "Aggiungi al Moodboard", visibilità per famiglia | **Moodboard e modelli Edit** |
| **M7c** | Pannello maschera con pennello semplice, parametri di maschera, `enableInpainting` | **l'inpaint funziona** |
| Poi | Tiled Diffusion fino a 8192; outpaint (modo Contieni e margini); **M8 Plug-in** (l'attuale M7) | |

## 12. Rischi aperti

- **Comportamento di Draw Things da verificare** (sezione 9): quando serve `enableInpainting`.
- **Prestazioni del pennello** su canvas grandi (fino a 2048×2048 oggi, 8192 con il Tiled Diffusion): il buffer e il disegno devono restare fluidi; si misura in M7c e, se serve, si disegna su una versione ridotta con rendering finale alla dimensione piena.
- **Moodboard su famiglie vecchie:** richiede un controllo (IP-Adapter/ControlNet) che DT Hub non gestisce; la scheda è grigia e non invia hint inutili. L'elenco delle famiglie vecchie è una tabella nel catalogo, aggiornabile senza toccare il resto; una famiglia nuova non elencata mostra il Moodboard attivo.
- **Spazio su disco delle copie:** nessun limite nella prima versione; "Svuota tutto" e la rimozione liberano lo spazio.
