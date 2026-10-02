# DT Hub — Design del tab Control (immagine, Moodboard, inpaint)

Data: 1 ottobre 2026 · Stato: bozza da approvare · Estende `2026-09-29-dt-hub-core-design.md`

## 1. Scopo

Un tab del cuore dell'app, **Control**, collocato **prima** di Generazione, dove si preparano gli ingressi immagine di una generazione: l'**immagine di partenza** (I2I), il **Moodboard** e la **maschera di inpaint**. Alimenta il normale RUN.

Nasce da un difetto dell'interfaccia di Draw Things: le immagini di controllo sono scomode da gestire, difficili da togliere e non si vede cosa è stato caricato in quale campo. DT Hub deve farlo meglio, e permettere di **trascinare le miniature della finestra Risultati** direttamente negli ingressi.

Decisioni dell'utente (1 ottobre 2026):
- il tab è del cuore e precede la v1 dei plug-in; anticipa le voci "Riferimenti" ed "Espandi e maschera" della spec principale (§2) e va **prima di M7 Plug-in** (che diventa M8);
- prima versione: immagine di partenza, Moodboard (acceso/spento), inpaint con pennello semplice;
- l'**outpaint** si aggiunge quando l'inpaint funziona; comporta ridimensionare l'immagine di partenza nel canvas (il modo "Contieni", sezione 5);
- Depth, Pose, Scribble, Color Palette, Custom e i ControlNet restano **fuori**: i ControlNet disponibili per DT sono per modelli vecchi (SD, Flux.1) e l'utente non ha modo di convertirne per modelli recenti;
- il Tiled Diffusion con dimensioni fino a 8192×8192 si fa **prima dell'outpaint** (voce del backlog).

## 2. Perimetro

**Dentro:**
- immagine di partenza con forza (strength) e inquadratura nel canvas;
- Moodboard: più immagini, ognuna con interruttore acceso/spento, rimozione e riordino; tutte contano allo stesso modo (nessun peso, vedi §4.1);
- maschera di inpaint (Maschera +, Maschera −), Pennello a colori sull'immagine (strato a parte), annulla/ripeti, inverti, svuota; sfumatura, margine, "conserva l'originale";
- (la striscia "Con Run parte" prevista all'inizio è stata tolta il 3 ottobre 2026: nel tab è già tutto in vista;)
- trascinamento da Risultati, dal Finder, incolla da appunti; menu "Usa come immagine" / "Aggiungi al Moodboard" in Risultati;
- ripristino all'avvio e annulla delle rimozioni.

**Fuori:** ControlNet e hint di Depth, Pose, Scribble, Color Palette, Custom; outpaint (arriva dopo, ma il modello dati lo prevede); selezioni (rettangolo, ellisse), riempimento, livelli; modifica dei pixel dell'immagine (non è un editor).

**Modelli Edit (Flux Kontext, Qwen Image Edit e simili):** verificato su documentazione di Draw Things e sul catalogo (campo `modifier`: `kontext`, `kontext_kv`, `qwenimage_edit_plus`, `editing`, `inpainting`). Non richiedono un tipo di ingresso nuovo: il **canvas** è l'immagine da modificare (forza 100%) e il **Moodboard** porta le reference aggiuntive; per una reference sola si usa il Moodboard con **canvas vuoto**. Ogni reference in più aumenta il tempo di render più che linearmente.

## 3. Interfaccia

**Posizione.** Il tab Control precede Generazione nella barra dei tab. All'avvio si apre l'ultimo tab usato. Il design system è quello dell'app (turchese come accento, arancio per ciò che si toglie, pannelli con raggio 19, titoli di gruppo in monospaziato maiuscolo).

**Niente striscia di riepilogo** (deciso con l'utente il 3 ottobre 2026, dopo averla provata): nel tab è già tutto a portata di sguardo. Gli avvisi stanno nella card di cui parlano: più di tre immagini accese nel Moodboard (riga arancione nella card), ritaglio forte (la riga "si perde il N%" della card Canvas diventa arancione sopra un terzo), famiglia che non usa il Moodboard (la card è grigia con la spiegazione). Non c'è più "Svuota tutto": ogni card si svuota da sola.

**Scheda Immagine** (sinistra):
- miniatura con ✕ sempre visibile, nome, dimensioni, provenienza ("da Risultati", "dal Finder", "da <plug-in>");
- pulsanti "Sostituisci" e "Usa le dimensioni" (vedi §5);
- cursore **Forza** 0–100% con campo numerico. **Automatica** finché l'utente non la sceglie: 100% per i modelli Edit (la scheda dice "Modello Edit: l'immagine viene modificata, forza al 100%"), 70% per gli altri, perché con un I2I normale a 100% l'immagine viene ignorata. Una scelta dell'utente vince; "Automatica" la riporta al valore del modello;
- zona di rilascio: trascinare un'immagine la imposta; se ce n'era una, la sostituisce con annulla.

**Scheda Moodboard** (sinistra, sotto):
- griglia di miniature; ognuna ha ✕ sempre visibile e **occhio** (spegne senza cancellare: la miniatura si attenua e l'immagine non parte);
- **tutte le immagini accese contano allo stesso modo**, e la scheda lo dice ("Ogni immagine accesa conta allo stesso modo"). Niente cursori, percentuali, barra a fette o "Equilibra": misurato il 2 ottobre 2026 (in Draw Things dall'utente e dal vivo da DT Hub) su FLUX.2 klein e Qwen Image Edit 2511, **qualsiasi valore sopra lo 0 dà lo stesso risultato** (lo 0 equivale a ignorare l'immagine). Le quote della torta (§4.1) sono rimandate finché un modello non le rispetta;
- niente riordino: con pesi uguali l'ordine non conta e il gesto non funzionava (tolto il 3 ottobre 2026; `moveMoodboardImage` resta nello store se un modello userà l'ordine);
- **regola di rilascio** (deciso con l'utente): rilasciare un'immagine **su una miniatura già inserita la sostituisce**; rilasciarla **in qualsiasi altro punto della scheda aggiunge**. Vale per le immagini dal Finder, da Risultati e per quelle trascinate dalla scheda Immagine;
- avviso quando le reference sono più di tre (tempo di render);
- le immagini del Moodboard sono riferimenti di stile e di contenuto, **non entrano nel canvas**: il loro rapporto non ha nessun legame con quello del canvas e non si ritagliano né si adattano mai (deciso con l'utente, 1 ottobre 2026);
- **quando il Moodboard è attivo:** i modelli recenti che fanno insieme T2I e I2I (FLUX.2, Qwen Image 2.1, in futuro Ideogram 4.5) leggono le reference da soli, senza suffissi o modifier che li distinguano: per questo la scheda **non** usa il `modifier` del catalogo. È grigia, con la spiegazione, solo per le famiglie di una **lista di dati** (`FamilyTraits.withoutMoodboard`) che non lo leggono: SD 1.x e 2.x, SDXL, SSD-1B (servirebbe un IP-Adapter o un ControlNet) e Z Image (misurata: il risultato è identico con e senza reference). Una famiglia nuova o sconosciuta la mostra attiva: nascondere ciò che un modello usa è peggio che mostrare ciò che ignora. La lista si aggiorna man mano che si provano le famiglie;

**Card Canvas** (destra), una sola card con **due modalità**, scelte da un selettore largo quanto la card in cima (gerarchia visiva); immagine e selettore sono centrati:
- **Canvas:** l'immagine intera con la parte che non parte oscurata e il riquadro del ritaglio; trascinando si sceglie quale parte tenere quando i rapporti sono diversi (§5), con le dimensioni e la perdita sotto. Vi si vedono, senza poterli modificare, la maschera (arancio) e il disegno;
- **Disegno:** il **canvas così come parte a Draw Things** (ritaglio compreso). Una riga come una toolbar, solo icone (i nomi nei suggerimenti al passaggio del mouse): **Maschera +** e **Maschera −** (una gomma con un + o un − accanto), **Pennello**; poi ciò che appartiene allo strumento: per le maschere **Inverti** e **Svuota** (cestino arancio), per il Pennello il **selettore Colore** e il cestino che svuota il disegno; in fondo alla riga **Annulla** e **Ripeti** (frecce). Sotto, il cursore **Dimensione** (diametro in pixel del canvas, uguale per i tre strumenti). Il cerchio dello strumento segue il puntatore. Nessun testo esplicativo;
- **nomi come in Draw Things** (deciso con l'utente il 3 ottobre 2026): in Draw Things la gomma è ciò che dipinge la maschera e il pennello disegna sull'immagine; quindi **Maschera +** dipinge l'area da rigenerare (arancio), **Maschera −** la toglie, **Pennello** disegna a colori sull'immagine;
- **Pennello:** il disegno è uno **strato a parte** (PNG con trasparenza, nelle coordinate dell'immagine, alla stessa dimensione di lavoro della maschera): il file dell'immagine non si tocca; si annulla come il resto, torna all'avvio, va via con l'immagine; al RUN si sovrappone all'immagine nello stesso ritaglio. Pennello rotondo con bordo netto (un pixel di antialiasing), colore scelto dall'utente (rosso all'inizio). Per togliere un tratto: Annulla o "Svuota disegno";
- **niente Morbidezza** (3 ottobre 2026): Draw Things riceve una maschera senza sfumature (un pixel è da rigenerare o no), quindi la morbidezza del pennello non cambierebbe nulla; il bordo si ammorbidisce con la Sfumatura;
- parametri di Draw Things (sotto l'immagine, con gli strumenti maschera o quando c'è una maschera): Sfumatura (`maskBlur`, 0–30, predefinita 1,5), Margine (`maskBlurOutset`, 0–100, predefinito 0), casella "Conserva l'originale fuori dalla maschera" (`preserveOriginalAfterInpaint`, predefinita accesa);
- **forza automatica 100% con la maschera** (misurato il 3 ottobre 2026: a 70% l'area mascherata resta quasi com'era), come per i modelli Edit; una scelta dell'utente vince. Con il solo disegno resta 70%;
- **dimensione dell'immagine:** prende tutta la larghezza della card, fino a quanto l'altezza della finestra lascia per quel rapporto; cresce con la finestra;
- **tratto fluido:** il tratto passa per i punti medi dei segmenti tra i punti del mouse e si piega verso i punti intermedi (curva quadratica), così pochi eventi non fanno spigoli; è un po' dietro il puntatore e al rilascio arriva all'ultimo punto;
- senza immagine la card mostra solo il riquadro vuoto con il suo testo; cambiare o togliere l'immagine di partenza toglie maschera e disegno (disegnati su un'altra immagine); si annulla.

**Annulla.** Ogni rimozione, sostituzione o svuotamento di immagini e Moodboard si annulla con ⌘Z e con un avviso "Rimossa · Annulla" che dura qualche secondo. **I messaggi galleggiano sopra le card** (con un'ombra) invece di stare nella colonna, così quando compaiono o spariscono non spostano nulla (un canvas che si muove sotto il cursore mentre si disegna è inaccettabile). Maschera e disegno svuotati non hanno messaggio: bastano le frecce Annulla/Ripeti della toolbar.

**Finestra Risultati.** Le miniature della striscia diventano trascinabili (come file e come tipo interno dell'app) e hanno nel menu contestuale "Usa come immagine" e "Aggiungi al Moodboard". Il dettaglio resta com'è.

## 4. Modello dei dati

**HubKit** (tipi `Sendable`; i salvati sono `Codable` con lettura permissiva, come `GenerationParameters`):
- `ReferenceImage`: `id`, `source` (file, risultato, appunti, plug-in), nome, dimensioni in pixel, nome del file della copia.
- `Framing`: modo (`fill`; `contain` in seguito) e spostamento normalizzato dentro il canvas.
- `MaskSettings`: sfumatura, margine, conserva l'originale (con i limiti sopra).
- `MaskReference`: il file PNG della maschera e quanta parte dell'immagine copre (per mostrarla nella card).
- `PaintReference`: il file PNG del disegno del Pennello.
- `MoodboardEntry`: `id` (quello dell'immagine), `ReferenceImage` e acceso/spento. Il peso arriverà con le quote (§4.1). Gli ingressi del RUN portano un `GenerationHint` per ogni immagine accesa, con peso 1.
- `ControlInputs`: immagine opzionale con `Framing` e forza (nil = automatica), maschera opzionale (riferimento al file) con `MaskSettings`, lista di `MoodboardEntry`.
- `GenerationInputs` (non `Codable`, non finisce nei PNG): immagine già inquadrata alla dimensione esatta del canvas, maschera (pixel **trasparenti = da rigenerare**, come vuole il client), lista di hint con tipo e peso.
- Il protocollo backend diventa `generate(_ job: GenerationJob, inputs: GenerationInputs)`; `GenerationJob` non cambia, e gli ingressi vuoti riproducono il T2I di oggi.

**Copie su disco.** Ogni immagine aggiunta viene **copiata** in `~/Library/Application Support/DT Hub/Control/<uuid>.<estensione>`. Così togliere o spostare l'originale, o l'immagine di Risultati, non rompe l'ingresso. La copia si cancella quando l'ingresso viene tolto o svuotato e le orfane si spazzano all'avvio. La maschera è un PNG a 8 bit **in coordinate dell'immagine**, nella stessa cartella: segue il ritaglio se lo si sposta. Si disegna a una **dimensione di lavoro** (il rapporto dell'immagine, lato lungo al massimo 1024 pixel) così il pennello resta fluido su qualunque immagine; al RUN si scala al canvas con la stessa interpolazione dell'immagine e si taglia a metà (maschera netta).

**Persistenza.** `control.json` nella cartella di supporto, separato da `session.json`, ripristinato all'avvio come il prompt (spec principale §11). Una copia mancante fa scartare la voce con un avviso.

**Memoria.** I pixel stanno su disco; le immagini si decodificano con ImageIO alla dimensione necessaria (miniature al volo, ritaglio al momento del RUN), perché una foto da 50 megapixel non deve stare intera in memoria. **Ogni tratto di pennello (o inverti, svuota) è un passo della stessa cronologia del tab** (20 passi, ⌘Z): ogni passo scrive un nuovo PNG della maschera e lo stato ne tiene il riferimento; le copie non più referenziate si spazzano. La cronologia usa copie del valore `ControlInputs` (leggero: contiene riferimenti, non pixel).

### 4.1 Quote del Moodboard (rimandate)

Progettate il 2 ottobre 2026 e **non realizzate**: le immagini del Moodboard sarebbero fette di una torta da 100 (una sola immagine 100, due 50–50, tre 34–33–33; quota modificabile con le altre che si ridistribuiscono in proporzione; l'immagine spenta esce dalla torta; "Equilibra"; barra a fette), con un peso grezzo salvato per immagine e un hint `shuffle` con peso = quota ÷ 100. Non si fanno perché sui modelli che leggono il Moodboard Draw Things le ignora: tutte le immagini con peso sopra 0 contano uguale. Si riprendono se un modello o un adattatore le rispetterà (per esempio Qwen Image 2.1, da provare, o i ControlNet della voce D). Il progetto è in questa sezione della storia di git (commit del 2 ottobre 2026).

## 5. Inquadratura: rapporto diverso dal canvas

Il canvas è dato dalle Dimensioni di Generazione. Tre modi di inquadrare l'immagine:
1. **Riempi (predefinito).** Il canvas resta com'è, l'immagine lo riempie e si ritaglia. La miniatura mostra il ritaglio (parti perse oscurate) e il dettaglio ("immagine 1:1 → canvas 4:3, si perde il 25% sopra e sotto"); trascinando l'immagine nel riquadro si sceglie quale parte tenere. Un ritaglio forte (oltre un terzo dell'immagine) produce l'avviso arancione della card Canvas.
2. **Adatta le dimensioni.** Un pulsante esplicito, sempre disponibile: porta le Dimensioni di Generazione al rapporto dell'immagine, con **area simile** a quella corrente, multipli di 64 e nei limiti del momento (2048; 8192 con il Tiled Diffusion). È un'azione con annulla e **non si ripete da sola**.
3. **Contieni (arriva con l'outpaint).** L'immagine sta tutta nel canvas e i margini sono area da rigenerare: è la stessa cosa dell'outpaint. Il modello dati lo prevede (`Framing`); l'interfaccia lo abilita con l'outpaint.

Se il rapporto delle Dimensioni cambia dopo il caricamento, il ritaglio si ricalcola al volo. Il **Moodboard** non ha il problema: le reference sono riferimenti di stile e non entrano nel canvas, quindi il loro rapporto è ininfluente.

## 6. Dal tab al RUN

- **`InputComposer`** (HubCore): funzione pura da `ControlInputs` e dimensioni del canvas a `GenerationInputs`: ritaglia e scala l'immagine alla dimensione esatta, rende la maschera nello stesso riquadro (alfa 0 dove si rigenera), prepara gli hint dei Moodboard accesi (immagini ridotte a 1024 px e codificate in PNG, peso 1 per tutte). Si prova con immagini generate nei test.
- **DTBridge** (`JobMapper`): riempie `image`, `mask`, hint (`HintBuilder`, tipo `shuffle` per il Moodboard) e imposta `strength`, `maskBlur`, `maskBlurOutset`, `preserveOriginalAfterInpaint`, e `enableInpainting` **solo per i modelli con `modifier` `inpainting`** (misurato il 3 ottobre 2026: su SD 1.5 e FLUX.2 klein la maschera funziona uguale con e senza; il client lo documenta «per i modelli che ne hanno bisogno», e quelli con `modifier` `inpainting` non sono installati qui, quindi per loro la regola segue il client, non è provata). `HintBuilder` e `ImageHelpers` della libreria si usano **solo** in DTBridge.
- **Più batch:** tutti riusano gli stessi ingressi.
- **Nel PNG salvato** finiscono forza, sfumatura, margine, e il numero delle reference del Moodboard (non le immagini). "Riprendi parametri" da Risultati ripristina questi numeri.
- **Blocchi in RUN:** nessuno. Una maschera senza immagine non può esistere (la maschera va con l'immagine); il resto sono avvisi.
- **Visibilità per famiglia** (come le card avanzate, dalla tabella del catalogo): il tab ricava dal `modifier` del modello la forza automatica (100% per i modelli Edit) e `enableInpainting`; il Moodboard si decide dalla **famiglia**, con una lista di dati (§3), non dal `modifier`. Una famiglia sconosciuta mostra tutto e non blocca nulla.

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
- Moodboard: aggiunta, sostituzione, rimozione e annulla, interruttore, riordino, persistenza, copie mancanti, avvisi (più di tre immagini, famiglia che lo ignora), ingressi del RUN (hint delle sole immagini accese, ridotte a 1024 px).

**DTBridge:** mappatura di forza, maschera, hint e `enableInpainting` nel `JobMapper`.

**Dal vivo con un server vero**, con un modello leggero: una I2I, un inpaint e un Moodboard. `enableInpainting` è risolto (§6). Misurato il 3 ottobre 2026 su SD 1.5 (Juggernaut Reborn) e FLUX.2 klein: con la maschera sulla metà destra di un'immagine blu, la metà sinistra resta identica e la destra si rigenera (quota di rosso 0,58 e 0,54) a forza 100%; a forza 70% la parte mascherata resta blu; `enableInpainting` acceso o spento non cambia nulla.

**A mano (utente):** trascinamenti, pennello, ripristino all'avvio.

## 10. Moduli e confini

| Modulo | Cosa riceve |
|---|---|
| HubKit | I tipi della sezione 4; il protocollo backend con gli ingressi |
| HubCore | `ControlStore` (stato, annulla/ripeti, persistenza), `ReferenceStorage` (copie su disco, finto nei test), `FramingMath`, `InputComposer`, `MaskBitmap` (buffer a 8 bit con pennello, gomma, inverti; restituisce il rettangolo toccato), `MaskOverlay` e `PaintOverlay` (l'immagine per lo schermo, aggiornata solo nel rettangolo toccato), `PaintBitmap` (strato RGBA del Pennello), `StrokeSmoother` (il tratto curvo), `CanvasDrawing` (maschera e disegno mentre si disegna: tratti, immagini per lo schermo, consegna allo store), le regole per famiglia, la regola di rilascio, la lista delle famiglie che ignorano il Moodboard (`FamilyTraits`) |
| DTBridge | `JobMapper` esteso; l'unico che usa `HintBuilder` |
| App | `ControlTabView` (con i messaggi che galleggiano), schede Immagine e Moodboard, `CanvasStage` (la card unica con le due modalità; immagine, disegno e maschera sono strati separati con il gesto di disegno), trascinamento (`Transferable`), modifiche a Risultati, `WorkspaceState` con due tab del cuore |

Le regole di dipendenza della spec principale (§4) non cambiano.

## 11. Tappe

Ognuna con piano, revisione indipendente e merge, come M4.

| Tappa | Contenuto | Esito |
|---|---|---|
| **M7a** | Tab Control davanti a Generazione, (striscia, poi tolta,) scheda Immagine (Riempi, Adatta le dimensioni, forza), copie e ripristino, trascinamento da Risultati, dal Finder e incolla, "Usa come immagine" in Risultati, RUN con I2I | **l'I2I funziona** |
| **M7b** | Scheda Moodboard (interruttore, regole di rilascio, riordino), "Aggiungi al Moodboard", visibilità per famiglia | **Moodboard** |
| **M7c** | Pannello maschera con pennello semplice, parametri di maschera, `enableInpainting` | **l'inpaint funziona** |
| Poi | Tiled Diffusion fino a 8192; outpaint (modo Contieni e margini); **M8 Plug-in** (l'attuale M7) | |

## 12. Rischi aperti

- **Comportamento di Draw Things da verificare** (sezione 9): quando serve `enableInpainting`.
- **Prestazioni del pennello** (misurate il 3 ottobre 2026 nella build Debug): ricostruire tutta l'anteprima della maschera a ogni evento costava 94 ms; con l'aggiornamento del solo rettangolo toccato un evento costa circa 2 ms. Il disegno e la maschera stanno a una dimensione di lavoro di 1024 pixel e l'immagine, il disegno e la maschera sono strati separati (un tratto cambia solo il suo). Con il Tiled Diffusion a 8192 la dimensione di lavoro resta 1024: da rimisurare quando si farà.
- **Moodboard e famiglie:** quali famiglie lo leggono si scopre provandole (FLUX.2 klein, Qwen Image Edit 2511 sì; Z Image no; Qwen Image 2.1 e i futuri da provare). La lista delle famiglie che lo ignorano è dati, aggiornabile senza toccare il resto; una famiglia nuova non elencata mostra il Moodboard attivo.
- **Spazio su disco delle copie:** nessun limite nella prima versione; "Svuota tutto" e la rimozione liberano lo spazio.
