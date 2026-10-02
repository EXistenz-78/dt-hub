# Backlog

Cose decise o chieste e non ancora fatte. Si cancella una voce quando entra in un piano.

## Richieste dell'utente

- **Tab Control** (1 ottobre 2026): design scritto in `docs/superpowers/specs/2026-10-01-tab-control-design.md`, in attesa di approvazione. Tappe M7a (immagine e I2I), M7b (Moodboard), M7c (inpaint); poi Tiled Diffusion fino a 8192, outpaint (modo Contieni), M8 Plug-in.
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
- Test dell'M3 `GenerationSessionTests.reportsProgressAndPreviewWhileRunning`: a volte fallisce sotto carico (dorme 380 ms contro un passo finto di 150 ms): attendere lo stato invece di dormire.
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
