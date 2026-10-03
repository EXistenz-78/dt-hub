# Backlog

Cose decise o chieste e non ancora fatte. Si cancella una voce quando entra in un piano.

## Richieste dell'utente

- **Tab Control** (1 ottobre 2026): design scritto in `docs/superpowers/specs/2026-10-01-tab-control-design.md`, in attesa di approvazione. Tappe M7a (immagine e I2I), M7b (Moodboard), M7c (inpaint); poi outpaint (M7d, slider Zoom; ordine invertito il 3 ottobre 2026), Tiled Diffusion fino a 8192, M8 Plug-in.
- **Tiled Diffusion e dimensioni fino a 8192×8192** (1 ottobre 2026, 20:41): con `tiledDiffusion` acceso il limite delle dimensioni deve salire a 8192. Oggi `GenerationParameters.sizeRange` è fisso a 64…2048 (HubKit). Da pensare: il limite dipende dal toggle (in `AdvancedParameters`), il ritaglio quando lo si spegne, i campi e le frecce, i preset dei rapporti, la validazione dell'editor JSON, `JobMapper`.

## Rimandi di M6 (revisione indipendente, tutti Minor)

- L'idle non si riarma quando Chiedi fallisce prima del caricamento (`LanguageModelManager.respond`: i controlli vanno prima di `idleTask?.cancel()`).
- Cambiare i minuti di inattività non riprogramma il timer già partito (`settings.didSet` → `scheduleIdleUnload()`).
- `MemoryProbe.live` somma due volte le pagine speculative (`free_count` le include già).
- `LanguageModelScanner` non segue i collegamenti simbolici (cartelle-modello collegate non elencate; file collegati misurati come il collegamento).
- Ogni Chiedi riscansiona tutta la cartella dei modelli sul thread principale (`selectedModel()`): leggere solo il percorso scelto.
- Chiamate `respond` sovrapposte non sono messe in coda (oggi c'è un solo chiamante; in M7 i plug-in potrebbero chiamare insieme).
- Prove dal vivo non rifatte sul ramo finale (schermo bloccato): Run con server parcheggiato, Stop durante "Libero la memoria…", ⌘Q senza server rimasto. Vanno provate a mano.

## Rimandato per scelta

- **Quote del Moodboard** (spec Control §4.1, 2 ottobre 2026): fette di una torta da 100 con barra, cursori ed Equilibra. Non fatte perché sui modelli che leggono il Moodboard Draw Things le ignora (FLUX.2 klein, Qwen Image Edit 2511: ogni valore sopra 0 dà lo stesso risultato; provato in Draw Things dall'utente e dal vivo da DT Hub). Da riprovare con Qwen Image 2.1 (encoder con visione) e con i ControlNet della voce D.
- **Famiglie che leggono il Moodboard:** Z Image no (misurato); Qwen Image 2.1, Ideogram 4/4.5 e altre da provare; si aggiorna `FamilyTraits.withoutMoodboard`.

## Rimandi di M8a (plug-in scaricabili, revisione indipendente)

- Spegnere un plug-in già caricato lascia l'etichetta "Acceso — caricato" accanto all'interruttore spento (il pulsante Riavvia compare, ma l'etichetta non lo dice); l'interruttore legge il file di impostazioni invece di uno stato osservato.
- Un plug-in acceso che non si carica (dopo `Bundle.load()`) non ha l'interruttore nelle Preferenze e il suo codice si ricarica a ogni avvio: l'unica uscita senza cancellarlo è ⌥. Mostrare l'interruttore ogni volta che il plug-in è tra gli accesi.
- "Gestisci i plug-in…" dell'header apre le Preferenze ma non sul pannello Plug-in (il `TabView` non ha una selezione).
- Trascinare sulle Preferenze qualcosa che non è un `.dthubplugin` (un `.zip` scaricato da GitHub, per esempio) non dà nessun messaggio: dovrebbe dire "non è un plug-in leggibile".
- Il view controller di un plug-in è uno solo: con ⌘N (una seconda finestra che condivide lo stato) il tab del plug-in può restare vuoto nella prima. Disattivare "Nuova finestra" o ospitare la vista solo nella finestra attiva.
- Fuori perimetro, accettati: crash o blocco dentro il codice del plug-in (rischio accettato nella spec, ⌥ all'avvio); classi Objective-C con lo stesso nome se più plug-in collegano `DTHubPluginKit` in modo statico (solo avvisi nel log); nessuna conferma prima di "Rimuovi"; quarantena da verificare su un file scaricato davvero; menu dell'header che elenca i plug-in caricati e non gli accesi; `context` solo all'attivazione e al cambio di modello.

## Rimandi della selezione multipla dei Risultati (revisione indipendente, 3 ottobre 2026)

- "Aggiungi al Moodboard" su molte immagini legge i file uno dopo l'altro: se subito dopo si cestinano, quelli già spostati non si leggono; inoltre `useError = firstError` può cancellare il messaggio della cancellazione. Leggere tutto prima di restituire il controllo, o non azzerare l'errore.
- I messaggi di errore del Cestino ripetono il nome del file (Foundation lo include già) e con molti file rifiutati diventano illeggibili in due righe: raggruppare le ragioni uguali e aggiungere il suggerimento (`.help`).
- Test mancanti: un file rifiutato resta in `results.json`; una voce vecchia dello storico non nella striscia sopravvive a una rimozione.
- Accettati: nessuna conferma prima del Cestino e nessun annulla (c'è "Rimetti a posto"); ⇧-clic sostituisce la selezione con l'intervallo; un clic destro fuori dalla selezione non la cambia; "Sposta nel cestino" (pulsante) e "Cestino" (suggerimento) con maiuscole diverse.

## Test con attese a tempo rimasti (3 ottobre 2026)

I test di sessione dell'M3 (`GenerationSessionTests`) sono stati resi deterministici (il finto backend lascia passare un aggiornamento solo quando il test lo decide, il test aspetta la condizione). Restano con pause fisse e margini piccoli, non ancora instabili: `ConnectionMonitorTests` (100 ms), `LanguageModelTests` (100–150 ms), `ManagedServerTests` (60–80 ms). Da convertire allo stesso modo se cominciano a fallire.

## Rimandi di M7e (dimensioni fino a 8192)

- `GenerationController.setTiledDiffusion` riscrive il rapporto bloccato anche quando le dimensioni non sono cambiate (un 16:9 arrotondato a 1,7 diventa 5:3 accendendo il Tiled): aggiornarlo solo se la dimensione cambia.
- "Annulla" della barra "dimensioni adattate" del tab Control (`restoreDimensions`) può rimettere dimensioni sopra il limite se nel frattempo si sono ripresi i parametri di un risultato col Tiled spento: chiamare `fitSizeToLimit()` alla fine.
- L'editor JSON e l'import dei preset rifiutano dimensioni sopra 2048 quando il JSON spegne il Tiled, mentre l'interruttore le riduce da solo; la spec dice che passano da `clamped()`: ridurre alla lettura o correggere il testo.
- Manca il test di `setHeight` con rapporto bloccato al limite (simmetrico a `setWidth`).
- **Non provato dal vivo**: un'immagine di partenza (I2I, inpaint, outpaint) a 8192²: il client ora ammette 1 GiB per messaggio, ma il limite di ricezione del server non è verificato.
- Fuori perimetro, accettati: maschera e disegno a dimensione di lavoro 1024 (a 8192 i bordi sono sgranati), pennello al massimo 512 px (poco su 8192), picco di memoria della maschera al Run a 8192², Tiled Decoding che non si accende insieme al Tiled Diffusion, nessun avviso di memoria.

## Rimandi di M7d (outpaint)

- **Klein e il grigio** (prova dell'utente): con FLUX.2 klein, margini grigi pieni e il prompt "expand the image" (senza accennare al colore) funzionano meglio che bordi estesi + maschera. Il riempimento automatico oggi dà `edges` a Klein senza LoRA; valutare un default diverso per i modelli Edit senza LoRA.
- Il riempimento automatico riconosce un LoRA di outpaint dalla parola "outpaint" nel nome o nel trigger: un LoRA senza la parola va scelto a mano dal menu.
- Soglia della maschera sul bordo dei margini diversa di una frazione di pixel (copertura 0,29 invece di 0,5) a seconda che esista una maschera dipinta (`InputComposer.mask`: riempie a 0 e poi disegna la maschera in grigio).
- `GenerationController` legge `hasMargins` e il riempimento dallo stato attuale dopo la preparazione asincrona del RUN: se lo zoom cambia in quel momento, forza e maschera possono non coincidere. Meglio ricavarli dagli ingressi già composti.
- L'anteprima dello stage è decodificata una volta a 1400 px: a zoom +100 si vedono circa 350 px ingranditi (sfocata). Decodificare per fascia di zoom o solo la finestra.
- Sfumatura, Margine e "Conserva l'originale" stanno solo in Disegno e si nascondono con il Pennello senza maschera: chi fa solo outpaint con lo slider può non trovarli.
- Testi vecchi: la documentazione di `CanvasStage` (dice che il drag muove il ritaglio), il commento di `LiveServerTests` ("grigio nell'immagine") e il nome del test `aRunWithMarginsGetsTheMaskAndTheGreyImage…`.
- Fuori perimetro, accettati: foto enormi decodificate a piena risoluzione con zoom +100; maschera dipinta tutta fuori dalla finestra; "Riprendi parametri" che salva la forza 1,0 di una corsa con margini; "Adatta le dimensioni" che mantiene lo zoom; Edit e inpainting veri con i margini non provati (`enableInpainting`); pennello nei margini.

## Rimandi di M7c (revisione indipendente, tutti Minor)

- All'avvio, se manca la copia dell'immagine, maschera e disegno restano (`ControlStore.init`): vanno scartati con l'immagine; e l'avviso "immagine mancante" può essere coperto da quello della maschera.
- Un PNG di maschera o disegno che esiste ma non si legge fa dire al RUN che l'immagine di partenza è illeggibile (`PendingInputs.render`): nominare la maschera o il disegno, o scartarli con un avviso.
- ⌘Z o ⌘V a metà tratto: se `onEnded` non arriva, lo `StrokeSmoother` resta attivo e il tratto dopo parte con un segmento dritto, strumento e colore vecchi (azzerarlo in `CanvasDrawing.sync`).
- I tratti che non cambiano nulla (Maschera − su zona vuota, Maschera + su zona già dipinta) diventano passi della cronologia e scrivono un PNG uguale.
- Dopo Maschera − i valori 1–127 al bordo non contano ma `MaskOverlay` li mostra (fino a circa il 27% di arancio): possono restare anelli tenui.
- Il cerchio del pennello può restare sull'ultimo punto se il tratto finisce fuori dalla vista (ordine degli eventi hover di SwiftUI non verificato).
- Una maschera dipinta e poi spostata fuori dal ritaglio (spostando il ritaglio) manda una maschera parziale o vuota: avviso da aggiungere. Un tratto che esce dalla vista, invece, si ferma al bordo del ritaglio.
- `enableInpainting` per i modelli con `modifier` `inpainting` segue la regola del client ma non è provato (nessun modello inpainting installato): da provare quando ce n'è uno; se il server rifiuta il controllo, spegnerlo.
- Gomma per il disegno del Pennello (oggi: Annulla o "Svuota disegno").
- Rimisurare la fluidità del pennello con il Tiled Diffusion a 8192 (la dimensione di lavoro resta 1024).
- Una card chiusa lascia nella colonna uno spazio vuoto alto (`DSCardRow` dà a ogni card l'altezza della riga).
- Non provato dal vivo nell'app: un Run con il disegno del Pennello acceso (coperto da test: `aRunGetsTheImageWithTheDrawingOnIt`).

## Rimandi di M7b (revisione indipendente, tutti Minor)

- Trascinare la miniatura dell'immagine di partenza nel Moodboard la chiama col nome UUID della copia e mostra il percorso della copia come origine (`take`/`takeMoodboard` devono riconoscere gli URL delle copie dell'app); rilasciarla sulla propria scheda sostituisce l'immagine con se stessa.
- Più file rilasciati su una miniatura: il primo la sostituisce, gli altri sono scartati senza avviso; una sostituzione il cui bersaglio sparisce durante la lettura cade in silenzio.
- Il chip "Moodboard N" della striscia compare anche con tutte le immagini spente o con una famiglia che ignora il Moodboard.
- Annulla/ripeti riportano ancora forza e inquadratura dell'immagine di partenza dallo snapshot (comportamento di M7a); solo interruttori e ordine del Moodboard sono mantenuti.
- **Riordino per trascinamento tolto** (3 ottobre 2026): non funzionava (rilasci annidati) e con pesi uguali non serve. `ControlStore.moveMoodboardImage` e i suoi test restano; se un modello userà l'ordine, va ricollegato con un unico `Transferable` enum.
- Non provati da automazione, provati a mano dall'utente: rilasci dal Finder e da Risultati sulla scheda e sulle miniature.

## Rimandi di M7a (revisione indipendente, tutti Minor)

- La notifica del tab Control che sparisce dopo 8 secondi cancella anche la successiva (`ControlTabView`: la cancellazione di `Task.sleep` è ignorata).
- L'immagine del RUN si incornicia con le dimensioni del momento; se larghezza o altezza cambiano durante la decodifica, i batch sono composti con quelle nuove e la configurazione non coincide con l'immagine (`GenerationController.renderInputs`/`start`).
- Un'immagine trascinata dalla striscia di Risultati si chiama "dal Finder" invece di "da Risultati" (serve un `Transferable` dell'app).
- Il ⌘Z nascosto del tab Control vince sull'annulla del campo Forza quando ha il focus.
- Un PNG con trasparenza arriva a Draw Things su nero, mentre l'anteprima la mostra trasparente.
- "Usa come immagine" in Risultati non dà conferma e non ripiega sull'immagine in memoria se il file salvato non c'è più.
- `control.json` si scrive a ogni tick dello slider/trascinamento (da ritardare come il file di sessione); `setImage(fileURL:)` legge tutto il file trascinato prima di controllarne il tipo.
- Un file JPEG/HEIC/TIFF troncato con intestazione leggibile si importa e fallisce solo al RUN ("Non riesco a leggere…"); il controllo vale per il PNG.
- Risultati precedenti alla striscia persistente non sono nella striscia: eventuale scansione della cartella di uscita.
- ⌘V nel tab Control (focus sul tab) e incolla dal browser: corretti ma non provati da automazione; provati a mano dall'utente.

## Rimandi precedenti

- M5: espansione di `~` nei percorsi, una cartella accettata come programma, `PortProbe` che blocca, una riga di log in inglese.
- M4c: `enableInpainting` in più, LoRA duplicate, preset come sovrapposizioni.

## Rimandi di M8b (contributi dei plug-in)

- **Cosa un plug-in non può ancora contribuire:** il modello (per scelta), le card Avanzate, la forza dell'immagine di partenza e la maschera. Servono messaggi nuovi (additivi: il contratto resta 1).
- **I segni non si salvano:** al riavvio i valori restano ma non c'è più il teal né la pipeline; il Moodboard di un plug-in diventa «da <plug-in>» senza teal.
- **`runPipeline` non ha test automatici:** la prova è dal vivo (Task 7); estrarre il ciclo in HubCore con un backend finto lo renderebbe provabile.
- **Il pop-up mostra i valori lunghi (i prompt) troncati** sul pulsante.
- **La domanda al modello linguistico non si può annullare** dal plug-in (la risposta può tardare fino a 300 secondi).

