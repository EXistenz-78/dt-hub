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
