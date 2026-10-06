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

## Rimandi di prompt nei preset e pipeline di preset

- **Passaggi con valori propri** (per esempio uno slider del plug-in per il peso del LoRA): per scelta no; l'utente cambia il preset.
- **Il menu «Gestisci preset…» non segna i preset dei plug-in** (lo fa solo il menu a tendina).
- **I preset di fabbrica di un plug-in non si ripristinano da soli**: per riaverli si cancella il preset e il plug-in lo ricrea al prossimo messaggio `presets`.
- **`run(with:)` e `runPipeline` non hanno test automatici** (vedi M8b): estrarre il ciclo in HubCore con un backend finto.
- **I valori di un passaggio non si vedono nel pulsante Run**: il suggerimento mostra solo i nomi dei preset.

## Rimandi di P3 (un file per preset)

- **Il menu Preset si aggiorna all'apparire della barra e quando l'app torna attiva**, non ogni volta che si apre il menu (SwiftUI non dà l'evento): un file aggiunto a mano mentre l'app è già in primo piano compare al giro successivo.
- **Il Salva non dice nulla se la scrittura fallisce** (disco pieno, permessi): `try?` ignora `cannotWrite`.
- **L'import conta come importati anche i preset scartati** (nome non valido, scrittura fallita).
- **Due file `Foo.json` e `Foo.JSON`** su un volume che distingue le maiuscole darebbero identificatori doppi nel menu.
- **Nessuna cache dell'elenco:** con migliaia di preset ogni lettura scansiona la cartella.
- **Prova dal vivo di P3 non completata dall'esecutore:** schermo bloccato durante la prova (modifica a mano di un file con l'app aperta, preset cancellato e Run, «Togli la pipeline»).

## Rimandi della revisione di M8b

- **«Run · 1 passaggi» / «Run · 1 passes»:** manca il plurale nel catalogo (il Sample con «Overcast» spento manda una pipeline di un passaggio).
- **Nessun test carica insieme Sample e Sample B** (la coesistenza con `moduleAliases` è provata solo dal vivo).
- **Un plug-in che rimanda il Moodboard** perde le immagini di prima anche se tutti i percorsi nuovi sono illeggibili.
- **`runPipeline` decodifica e ricodifica le immagini dei passaggi sul thread principale**, e `contribute` legge i file del plug-in sul thread principale: a canvas di 8192 l'interfaccia si ferma per qualche centinaio di millisecondi.
- **Un plug-in già caricato e spento dalle Preferenze** diventa inattivo per il lavoro subito, ma il codice resta caricato fino al riavvio (dal menu dell'header si può riattivare).

## Rimandi delle impostazioni consigliate

- **Le voci con LoRA acceleratore** (Lightning, Turbo) non sono nella tabella: la scelta resta all'utente (`docs/superpowers/reference-lora-acceleratori.md` mostra cosa cambierebbero).
- **La tabella si rigenera a mano** con `python3 Scripts/make-recommended-settings.py` quando Draw Things aggiorna la lista; i modelli nuovi hanno il valore consigliato solo dopo la rigenerazione.
- **Nessun avviso né annullamento** quando cambiare modello cambia i valori.
- **Il menu dei modelli non ha test automatici**; la logica sta in `ModelSelection.choose`.
- **Il ripiego di famiglia prende i valori della voce `version`**, spesso il distillato (Z-Image, ERNIE, Krea, FLUX.2 Klein): un fine-tune di un modello base prende 8 o 4 passi e CFG 1. Valutare di limitare `families` a `v1` e `sdxl_base_v0.9` (o a un elenco scelto).
- **Un sampler sconosciuto** in una voce: lo script lo accetta, Swift scarta la voce e il modello ricade sulla famiglia. Lo script dovrebbe rifiutare i sampler fuori da 0–19, o Swift non ripiegare quando la chiave del modello c'è.
- **`applying` riduce anche `cfgZeroInitSteps`** (via `clamped()`) e tornando a un modello con più passi non lo ripristina.
- **`selectingWithoutChoosingKeepsTheValues`** controlla solo il file scelto, non i parametri.

## Rimandi del plug-in Sphere Light

- **Non è firmato né notarizzato** e non c'è una pagina di download: la distribuzione ad altri è un lavoro a parte.
- **Il LoRA e Klein 9B devono essere installati:** il plug-in non li controlla (se mancano lo dice Draw Things).
- **La colla** (`SLRState`, le viste, `SphereLightPlugin`) non ha test automatici; la logica sta in `SphereSender`, `SLRMessages`, `SLRStore` e `DesktopSaver`.
- **«Run · 1 passaggi»** quando la pipeline ha un solo passaggio: la stringa `header.run.pipeline` dell'app non ha il singolare.
- **L'app standalone `LightDirectionApp`** resta com'è e non si sviluppa più: le correzioni al renderer vanno fatte nel plug-in.
- **Lo `strength` 1 dello script non si riproduce:** il contratto 1 non ha una chiave per lo strength; un valore esplicito nel tab Control vale per entrambi i passaggi (Klein è un modello Edit e lo forza al 100%).
- **Il passaggio «Overcast» usa il Moodboard del tab** (come lo script): con una sfera già nel Moodboard, Klein la legge come riferimento nel primo passaggio. Si può dare al passaggio `"moodboard": []` se l'app lo tratta come «nessuno» (da verificare).
- **«Invia a Generazione» e «Solo la sfera» scrivono lo stesso file:** una pipeline in attesa gira con l'ultima sfera mandata.
- **`SphereSender.describe`** ignora i `problems` della risposta di `contribute` e un `error` senza testo dice «Nessuna risposta»; un errore di scrittura nella cartella delle immagini dice «Calcolo non riuscito».
- **`DesktopSaver`** va in overflow con un file chiamato `Sphere Light 9223372036854775807.png` (usare `addingReportingOverflow`).
- **Stringhe `active`/`inactive`** di `Strings.swift` inutilizzate; test da rafforzare: l'ordine preset → pipeline, i segnaposto uguali nelle due lingue, `describe` con `problems`, valori salvati fuori intervallo.

## Rimandi del design system nel kit

- **Il kit non riesporta il design system:** un plug-in prende due prodotti con due alias (vedi `PluginKit/README.md`). Se in futuro SwiftPM propaga l'alias, si può riesportare.
- **L'esempio `Sample` non usa il design system** (resta con i controlli standard).
- **`DSStatusDot` resta in `HubKit`** perché dipende da `ConnectionStatus`.
- **Commenti da correggere:** `PluginKit/Package.swift` e il README del kit dicono che `DTHubDesign` è «SwiftUI only, senza classi Objective-C», ma `DSWindowConfigurator` ha una sottoclasse di `NSView` (è il motivo per cui l'alias serve).
- **Spec del design system:** §6 dice ancora che la risoluzione di `PluginKit` in Xcode è da provare (è provata); §5 nomina `DS.accent` mentre il test usa `DS.panelRadius`.
- **Il cambio di tab tra due plug-in** non ha un test automatico (è una riga di interfaccia, provata dal vivo).


## Rimandi del contratto `llm` (tappa 1 di Prompt Master)

- **Le immagini date all'LLM arrivano a 512 × 512:** `ChatSession` ridimensiona le immagini a quella misura per impostazione predefinita (`processing: .init(resize:)`). Va bene per descrivere; per l'I2I dei PE di Qwen (immagine di partenza) si deve vedere con la prova dal vivo se basta, altrimenti `LanguageModelOptions` ottiene una misura massima.
- **Nessun annullamento:** una richiesta `llm` non si può interrompere dal plug-in; un modello con il thinking acceso può metterci minuti.
- **`refreshContext` rilegge la cartella dei modelli** a ogni cambio di tab (una scansione di due livelli): se pesasse, si memorizza l'elenco finché la cartella o le impostazioni non cambiano.
- **Il solo Moodboard conta come T2I** (scelta dell'utente, 5 ottobre 2026): le sue immagini non vanno al PE T2I. Se in prova dal vivo Qwen 2.1 con il solo Moodboard si comporta da I2I, si cambia `PEPlanner` (una riga).
- **Un booleano dove ci vuole un numero** (`"maxTokens": true`) viene letto come 1 e non ignorato (`number()` di `LanguageModelOptions` non scarta i `CFBoolean`; `flag()` sì). Test da aggiungere con la correzione.
- **`languageModels: []`** si manda con la cartella dei modelli vuota, mentre le altre chiavi del contesto si omettono quando non hanno niente da dire; il README e i commenti dicono due cose un po' diverse.
- **Due domande insieme a modelli diversi** (due plug-in, o un doppio clic) non si vedono tra loro: possono caricare due modelli insieme. Esisteva già con lo stesso modello; il caricamento per nome lo rende un po' più probabile.
- **Un plug-in futuro che contribuisce un Moodboard a ogni contesto** ne rimanderebbe uno nuovo a ogni invio (le immagini cambiano id, il contesto si rimanda): nessun plug-in lo fa oggi.
- **`startImage` è il file salvato**, senza ritaglio né disegno del Brush: se il PE deve vedere l'immagine incorniciata è una scelta di prodotto.

## Rimandi del plug-in Prompt Master (tappa 2)

- **I master prompt sono provvisori:** quelli di `flux2`, `qwen_image_2.1`, `hidream_i1` e `cosmos2.5_2b` sono scritti senza ricerca, gli altri nove partono dalle note del vecchio PM tradotte; la revisione con le fonti online (spec §9) arriva come nuovo `master-prompts.json`.
- **Lo Shuffle non pesca i termini personali** e sostituisce tutta la selezione, personali compresi.
- **I termini a evitare** (categoria «negative_terms») vanno all'LLM in un elenco a parte; nelle famiglie senza negativo l'LLM li trasforma in descrizione positiva. Non c'è un campo negativo scritto a mano.
- **Il pulsante «Scrivi prompt» non si può annullare** (il contratto non lo prevede); il PE con il thinking può metterci minuti.
- **Il formato suggerito dal PE** (`wh_ratio`) si applica solo con il pulsante «Applica» (stessa area, multipli di 64, tra 64 e 4096); non c'è un'applicazione automatica.
- **Il kit non ha un `init` pubblico per `DTHubLanguageModel`:** i test lo costruiscono da JSON.
- **La colla** (`PromptMasterPlugin`, le viste) non ha test automatici; la logica sta in `PMWriter`, `PMState`, `PEPlanner`, `TermTree` e gli altri tipi puri. Il tab è stato visto in un PNG disegnato fuori dall'app, non dal vivo nella finestra.
- **Il PE T2I è provato** (modello 4 bit della comunità: carica in 17 s, risponde in 44 s con thinking); un modello generico più grande dell'8B per i master prompt e il PE nell'app dall'interfaccia dipendono dalla prova dell'utente.

- **Una risposta fatta solo di virgolette** (`""`) o un JSON con `"prompt": "  "` diventa un prompt vuoto (o il testo del JSON) e finisce nella Generazione: `AnswerParser` dovrebbe dare nil.
- **Un clic su una freccia durante la ricerca** cambia lo stato aperto/chiuso salvato senza che si veda; `toggleOpen` non dovrebbe fare nulla mentre la lista è filtrata.
- **`custom-terms.json` illeggibile:** i termini personali spariscono senza una riga di stato all'avvio (il file non si tocca); la spec §3 chiede un avviso.
- **«Tag booru» acceso su `sdxl_base_v0.9` e `v1`:** il testo del booru dice «solo tag, niente frasi» dopo il master prompt che chiede un JSON con `negative`; un modello piccolo può rispondere con i soli tag e il negativo non si scrive. Da riscrivere nella revisione dei master prompt.
- **`make-prompt-data.py`:** l'asserzione sul testo delle stringhe Swift cerca `"""#`, che `json.dumps` non produce mai; il rischio vero è `\#`.
- **Una `schema` 2 nella cartella dati** si segnala di solito come «non si legge» e non come «layout sconosciuto» (si decodifica prima come schema 1).
- **Ogni riga della lista osserva tutto `PMState`:** a ogni tasto nella descrizione si ridisegnano le righe aperte e si salva in `UserDefaults`; non misurato.
- **Il cestino dei termini personali** è sempre visibile, non solo al passaggio del mouse (spec §4).

## Lunghezze dei master prompt (verificate il 5 ottobre 2026)

Prima i master prompt davano «lunghezze obiettivo» prese dalle note del vecchio PM, tra cui due non confermate dalle fonti. Ora ogni famiglia ha una lunghezza abituale (`words`) e un massimo (`maxWords`) che segue il limite vero dell'encoder di testo, con un margine, e il motivo (`lengthNote`). Il master prompt dice «aim for X; never beyond N».

| Famiglia | Abituale → massimo | Limite vero e fonte |
|---|---|---|
| FLUX.1 | 80–250 → 300 parole | T5-XXL, 512 token (≈350 parole), il resto cade ([FLUX.1-dev, discussione 43](https://huggingface.co/black-forest-labs/FLUX.1-dev/discussions/43), [Draw Things wiki](https://wiki.drawthings.ai/wiki/Prompting_Base_Model_Basics): «10–250 parole») |
| FLUX.2 (dev, klein 9B/4B) | 60–250 → 300 | `MAX_LENGTH = 512` ([DeepWiki flux2](https://deepwiki.com/black-forest-labs/flux2/3.2-text-encoders)) |
| Krea 2 | 40–150 → 300 | 512 token; oltre 640 immagini nere o corrotte ([ComfyUI #14782](https://github.com/Comfy-Org/ComfyUI/issues/14782)) |
| Qwen Image / 2.1 | 80–250 → 450 | `max_sequence_length` 1024 di predefinito ([diffusers](https://huggingface.co/docs/diffusers/main/api/pipelines/qwenimage)); fino a ≈500 parole secondo il notebook «Modelli generazione immagini» |
| Z-Image | 100–250 → 300 | 512 token di predefinito, fino a 1024; «funziona meglio con prompt lunghi e dettagliati» ([scheda ufficiale](https://huggingface.co/Tongyi-MAI/Z-Image-Turbo/discussions/8), [mflux #810](https://github.com/mflux-community/mflux/pull/810)) |
| SDXL | 30–55 → 60 | 77 token per encoder CLIP (notebook) |
| SD 1.5 | 20–35 tag → 40 | 77 token CLIP, troncamento rigido (notebook) |
| ERNIE-Image | 50–150 → 300 | ≈2048 caratteri **solo dal notebook**; la scheda ufficiale ([baidu/ERNIE-Image](https://huggingface.co/baidu/ERNIE-Image)) non indica nessun limite |
| HiDream-I1 | 40–90 → 150 | la pipeline di riferimento legge 128 token (CLIP 77) e tronca ([issue #18](https://github.com/HiDream-ai/HiDream-I1/issues/18), [HF discussione 40](https://huggingface.co/HiDream-ai/HiDream-I1-Full/discussions/40)); alcuni strumenti arrivano a 256 (SD.Next). **Prove deboli**: nessuna dichiarazione ufficiale sulla capacità vera del modello; tetto prudente |
| Anima (Cosmos 2.5) | 30–120 → 300 | `max_sequence_length` 512 ([SGLang](https://lmsysorg.mintlify.app/cookbook/diffusion/CircleStone/Anima)) |

- **Corretto rispetto a prima:** Z-Image non ha un limite di 800 caratteri e non perde attenzione dopo 75 token (affermazioni del vecchio PM che le fonti non confermano); FLUX, FLUX.2, Krea, Z-Image ed ERNIE potevano avere prompt molto più lunghi di «60–150 parole»; HiDream invece va **accorciato** (80 → 40–90 parole abituali, massimo 150).
- **Criterio:** il limite è dell'encoder di testo del modello e dell'implementazione di riferimento, non del programma che lo esegue; Draw Things è stato usato solo come riscontro (FLUX.1, HiDream). Un programma può comunque imporre un tetto proprio più basso.
- **Non verificato:** come Draw Things tratta i prompt oltre 77 token su SD/SDXL (concatenazione a blocchi o troncamento) e se imposta un limite proprio per le famiglie a 512 token; il massimo di Qwen Image 2.1 (assunto uguale a Qwen Image); i consigli di *efficacia* (cosa rende un prompt migliore, oltre al limite) restano da rivedere nella ricerca della spec §9.


## Rimandi della tappa 3 di Prompt Master

- **Il PE I2I** (riscrive istruzioni di modifica di un'immagine, con `<image1>`, `<image2>`…, e risponde con `wh_ratio` o `ratio_follow`) è per un plug-in dedicato a Qwen Image 2.1; il contratto ha già `startImage` e `moodboard` nel `context`.
- **La richiesta al PE ignora i termini da evitare** (non ha un negativo); per Qwen 2.1 la categoria dei termini da evitare è comunque nascosta.
- **La risposta del PE ha paragrafi separati da righe vuote:** vanno nel campo Prompt così come sono; se Draw Things li trattasse male, `AnswerParser` potrebbe unirli.
- **«Applica» legge la dimensione dal `context`** (`parameters.width` e `.height`); dopo la revisione l'app rimanda il contesto anche quando l'utente cambia la dimensione a mano (`PluginContextKey`).
- **Il PE T2I è una conversione della comunità** (`prithivMLmods`, 4 bit): non si è confrontata la qualità con il modello originale.
- **Il PE può superare il massimo di parole:** nella prova dal vivo ha scritto 694 parole per una richiesta densa (il suo prompt ne chiede 400–500, il massimo di Qwen 2.1 è 500). Non si taglia (si perderebbe la frase finale) né si rifà (altri 45 s): si potrebbe avvisare nella riga di stato dopo ogni scrittura («Prompt di 694 parole: questo modello ne legge circa 500; la fine può essere ignorata»), con `maxWords` dei dati, per tutte le famiglie.
- **«Applica» compare anche per un rapporto illeggibile** («2.35:1», «16x9»): la spec vuole che non compaia; premendolo dice che non si può applicare. Basterebbe tenere `suggestedRatio` solo se `RatioSize.parse` lo legge.
- **Se la famiglia cambia mentre il PE scrive** (fino a 900 s), a fine scrittura il formato suggerito torna a comparire sotto la nuova famiglia: si dovrebbe impostarlo solo se la famiglia è ancora quella della richiesta.
- **`applyRatio` moltiplica larghezza × altezza** senza controllare l'overflow; i valori vengono dai parametri dell'app, già limitati.
- **Un termine personale con a capo dentro** non viene ripulito: finisce così com'è nella richiesta all'LLM (non rompe nessuna struttura che leggiamo noi).

## Rimandi della tappa 1 di Prompt Master I4

- **Il canvas non c'è ancora** (tappa 2): la posizione di un elemento si scrive come quattro numeri; un testo che non si legge torna a quello di prima.
- **Senza l'LLM** (tappa 3) il JSON porta i nomi inglesi delle voci uniti da virgole e i testi come scritti; la descrizione generale e il background restano nella lingua dell'utente.
- **Il negativo vuoto** (`negativePrompt: ""`): l'app lo scarta se la famiglia non legge il negativo (`JobComposer`); verificare dal vivo che per `ideogram_4` il campo si svuoti davvero.
- **Un solo `family`**: il plug-in non legge il `context` (il tab è grigio sulle altre famiglie dal manifesto); la dimensione della Generazione serve al canvas nella tappa 2.
- **Il database è copiato in due plug-in** (Prompt Master e I4, due copie incorporate): `Scripts/make-i4-data.py` lo rilegge da `Plugins/PromptMaster/Data/`; un modulo condiviso si estrae se un terzo plug-in lo chiede.
- **La finestra «Rivedi JSON» non controlla che il testo sia JSON valido:** è una finestra di modifica, non un importatore (decisione dell'utente).
- **Nessun termine personale, nessuna ricerca** nelle liste (non richiesti).
- **I colori** si scelgono con il selettore di sistema; non c'è un campo per scrivere l'esadecimale.
- **La colla** (`PromptMasterI4Plugin`, le viste) non ha test automatici; la logica sta nei tipi puri. Il tab è stato visto in un PNG disegnato fuori dall'app (`RenderTests`).

## Rimandi della revisione della tappa 1 di Prompt Master I4

- **`ideogram4.json` scritto a mano non si controlla** per id di categoria ripetuti (la stessa categoria due volte in un campo, o in due campi): la lista mostrerebbe id doppi e lo Shuffle potrebbe pescare due voci della stessa categoria.
- **Un `ideogram4.json` più vecchio dell'incorporato** si ignora senza avviso (come in Prompt Master): dopo un aggiornamento del plug-in che alza la versione, un file modificato dall'utente smette di valere senza dirlo.
- ~~`BBox.parse` spezza i decimali~~ (corretto nella tappa 2: i decimali si arrotondano).
- **Accessibilità:** le card degli elementi si aprono solo con il clic sull'intestazione (non da tastiera/VoiceOver); i pulsanti con solo icona (su, giù, togli, + e × dei colori) hanno solo il tooltip; i selettori di colore non hanno un nome.
- **Le palette usano l'indice come identità:** togliere un colore mentre il pannello colori di un altro è aperto fa modificare il colore che ha preso quel posto (non crasha: gli indici sono controllati).
- **Test:** i golden byte per byte sono solo quello dell'esempio Foto della spec vecchia; l'esempio Arte e gli altri casi si controllano per posizione delle chiavi e per valore.
- **`JSONEditor` lascia `smartInsertDeleteEnabled` acceso** (incollando una parola dentro una stringa può aggiungere uno spazio); l'annullamento (Cmd-Z) dopo «Ripristina dai campi» non è stato provato.
- **I campi di prosa** (descrizione, testo verbatim) seguono le sostituzioni di sistema (virgolette tipografiche, trattini lunghi): il testo di una scritta potrebbe averle.
- **Codice non usato:** `I4Catalog.term(_:)` (solo test), `I4Sender.Outcome.sent`, `LoadedData.fromFile`.
- **Piccoli:** «1 conflitti» (plurale), un background che finisce con «,» dà «,,» nel JSON, un termine Text & Lettering sparito dal vocabolario sparisce senza dirlo dalla `desc`, le avvertenze sui dati spariscono al primo «Invia».
- **I test di Prompt Master (`pm-state-*`) lasciano file di preferenze** in `~/Library/Preferences` (quelli di I4 usano una memoria in RAM).

## Rimandi della tappa 2 di Prompt Master I4 (il canvas)

- **I gesti si sono provati con eventi mouse sintetici** su una finestra mai mostrata (disegno, spostamento, ridimensionamento, clic sull'etichetta, clic sul vuoto); con una card aperta (c'è un campo di testo) quel banco di prova non riceve i gesti, quindi **il caso «scrivo nel campo posizione e poi disegno sul canvas» va visto con il mouse vero**.
- **Il cursore non cambia** sulle maniglie e sui riquadri (resta la freccia).
- **Nessun controllo da tastiera** sul canvas (spostare un riquadro con le frecce, selezionarlo con Tab) né etichette per VoiceOver sui riquadri.
- **La dimensione si legge dal `context`** (`parameters.width` e `.height`); l'app lo rimanda quando cambiano (`PluginContextKey`).
- **Le maniglie sono quadrati di 10 punti** con un raggio di presa di 12: su un riquadro molto piccolo gli angoli si sovrappongono (vince l'ordine nordovest, nordest, sudovest, sudest).
- **Un riquadro è sempre dentro la griglia**, ma più grande del canvas visibile non può essere: non c'è zoom.
- **Un elemento senza posizione non ha etichetta** (decisione dell'utente): il tipo si cambia solo dopo avergli dato i numeri della posizione, oppure lo si toglie e si rifà; non c'è «Disegna».

## Rimandi della revisione della tappa 2 di Prompt Master I4

- **Il ridimensionamento fa saltare l'angolo sul puntatore** (la nuova posizione è quella assoluta del puntatore, non l'angolo di partenza più lo spostamento): premendo una maniglia a 8–12 punti dall'angolo il riquadro si accorcia subito di quel tanto.
- **Un riquadro selezionato piccolo non si sposta:** sotto circa 17 punti per lato ogni punto è entro 12 punti da un angolo, quindi ogni trascinamento ridimensiona; per spostarlo si toglie prima la selezione. Lo stesso su un canvas molto stretto (rapporto 1:4).
- **Un gesto annullato dal sistema** (vista tolta a metà, mouse-up perso) lascia lo stato `drag` della vista: il gesto successivo ne riusa modo e punto di partenza. Rimedio: ripartire se `startLocation` cambia, o `@GestureState`.
- **Con un rapporto 1:4 o 4:1 il canvas è molto stretto o basso** (75 punti di larghezza): le etichette, larghe 70–84 punti, restano attaccate a sinistra e coprono gran parte dei riquadri piccoli.
- **Un elemento tolto o cambiato di tipo durante un gesto** lascia una selezione su un id che non c'è più: innocuo (gli id non si riusano), non raggiungibile con un solo mouse.
- **Se la dimensione del canvas cambia a metà gesto** (finestra ridimensionata, Generazione cambiata) il risultato usa la geometria nuova con punti della vecchia.
- **Uno scorrimento animato verso la card selezionata** non è provato con più di una dozzina di elementi.

## Rimandi della tappa 3 di Prompt Master I4 (Scrivi con LLM)

- **Provato dal vivo solo con l'8B** (Qwen3-VL 8B 4 bit, thinking spento): 24 prove su 24 con tutti i tag; un modello più piccolo (il 2B) o un altro 8B non sono provati. Il master prompt sta in `ideogram4.json` e si rivede senza ricompilare.
- **Le frasi aggiungono ogni tanto un dettaglio che non c'era** («con un cacciavite in mano», «dall'alto e dai lati»): il master prompt lo vieta e non sempre basta; con la regola 7 l'8B ne inventa meno, ma non zero.
- **Le parole stampate da una scritta non si mandano** (il modello le scrive nella frase): la frase di una scritta non sa quanto è lunga la parola né di che lingua è.
- **Non c'è un modo di scrivere un solo campo** a richiesta (un pulsante per campo): si riscrive tutto quello che è da riscrivere; per rifare un campo già riscritto lo si cambia.
- **Il ripiego chiede un campo per volta, in sequenza**: con molti campi mancanti dura quanto quelli (3–12 secondi l'uno con l'8B); non c'è annullamento (il contratto non lo prevede).
- **Una frase arrivata dopo che l'ingresso è cambiato** si salva come da riscrivere (corretto), ma non si dice all'utente che è successo.
- **Il JSON del ripiego usa la stessa temperatura (0,6)**: due scritture di fila danno frasi diverse.
- **La tabella «Cosa riceve l'LLM»** mostra i campi in inglese (nomi dei tag) anche con l'interfaccia in italiano.
- **Il test dal vivo** (`ZZLiveCases`, `ZZCases`) è temporaneo e non si committa: serve il modello su disco.

## Rimandi della revisione della tappa 3 di Prompt Master I4

- **Un tag annidato** (`<element_1>A <b>bold</b> cup.</element_1>`) lascia i tag interni nella frase; il testo fuori da una recinzione che non apre la risposta entra nella frase di una risposta senza tag; `&amp;` e `&lt;` non si decodificano.
- **Il ripiego si ferma solo se anche la richiesta intera è fallita:** se la richiesta intera risponde e poi l'app fallisce (o scade) per ogni campo mancante, si chiede lo stesso ogni campo, fino a 600 secondi ciascuno, senza annullamento e con «Invia» spento.
- **Le parole in italiano e in inglese si mescolano nella riga di stato:** i campi che falliscono si nominano con i titoli inglesi («Lighting, E1 · obj»), il motivo dell'app è quello dell'app, e «1 frasi scritte» è al plurale; `L.Key.nothingToWrite` non è usata.
- **La riga dei pulsanti a 340 punti** (la larghezza minima della colonna) va a capo («Rivedi / JSON», «Sto scriven…»): serve circa 380 punti per stare su una riga.
- **Un modello che copia il contenuto del blocco** («Mood: melancholic») o scambia il contenuto fra i tag non si riconosce.
- **Dopo 600 secondi di attesa** non si sa se l'app continua a generare: le richieste del ripiego si accodano dietro.
- **`PromptMasterI4Plugin.write()` non ha un test proprio** (la logica è in `I4Writer` e `I4State`).


## Idee dell'utente (da fare)

- **Zoom con la rotella sull'immagine** (6 ottobre 2026): sull'immagine del Disegno, nella card Canvas e nella sua finestra separata, la rotella (e il pizzico) ingrandisce e rimpicciolisce l'immagine, per disegnare i dettagli con la Pencil o con le dita. Da decidere nel disegno: lo zoom è solo di vista (maschera e disegno restano alle dimensioni del canvas), come si sposta l'immagine ingrandita (trascinamento a due dita o barra spaziatrice), e come si torna alla vista intera.
