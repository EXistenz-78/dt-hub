# DT Hub — Design del prompt nei preset e della pipeline di preset

Data: 4 ottobre 2026 · Stato: P1 e P2 realizzate, P3 (un file per preset) da fare · Estende `2026-09-29-dt-hub-core-design.md` (§6 Preset) e `2026-10-03-plugin-design.md` (§7, §11: **sostituisce** i passaggi con `fields` e `loras` della pipeline)

## 1. Scopo

La pipeline di M8b manda all'app passaggi con i parametri dentro: l'utente li vede solo come titoli nel suggerimento del pulsante Run e non può cambiarli. Si rende la pipeline **visibile e modificabile** appoggiandola ai **preset**, che l'utente già conosce:

1. il preset contiene anche il **prompt**;
2. un plug-in può **aggiungere preset** al menu Preset;
3. la pipeline è una sequenza di **«lancia PresA, poi PresB»**, con gli ingressi che i preset non hanno (immagine di partenza, Moodboard, l'output del passaggio precedente).

Decisioni dell'utente (4 ottobre 2026):
- il prompt entra **sempre** nel preset, senza casella: chi non lo vuole svuota il campo prima di salvare;
- un preset con il prompt vuoto non tocca il prompt del tab quando si carica (come il negativo);
- i plug-in non registrano e poi leggono: il passaggio **nomina** il preset e l'app lo risolve al Run, quindi vale sempre quello che l'utente vede nel menu Preset;
- **larghezza e altezza escono dai preset, sempre** (decisione del 4 ottobre 2026): un preset non le salva e caricarlo non cambia mai il formato del canvas, che lo sceglie l'utente. Vale per tutti i preset, anche quelli già salvati e quelli importati da Draw Things. Il **modello** resta nei preset come oggi (caricare un preset dal menu lo cambia), ma nei passaggi della pipeline **si ignora**: il modello lo sceglie l'utente nell'header e un plug-in non lo cambia mai;
- un preset che non si trova non è un errore da risolvere: compare un avviso «PresA non trovato» quando si prova a lanciare la pipeline, e il Run non parte;
- un passaggio è **solo «nome del preset + ingressi»**: niente modifiche di valori dal plug-in. Gli slider come il peso del LoRA escono dal plug-in: l'utente li cambia nella Generazione e salva il preset;
- il risultato di un passaggio **non** va in automatico nel tab Control (comportamento di DT Hub che resta com'è): la pipeline lo passa al passaggio dopo con `useOutputAsStart`, e il Moodboard di un passaggio sostituisce quello del tab solo per quel passaggio. Il flusso di Sphere Light è quindi: PresA → il risultato è l'immagine di partenza e la sfera è nel Moodboard → PresB.

Fuori: passaggi con valori propri; preset condivisi tra plug-in; esportare i preset dei plug-in; un editor di pipeline nell'app; il prompt negli import di Draw Things (non lo hanno).

## 2. Il prompt nei preset

**Dimensioni.** Caricare un preset lascia larghezza e altezza del tab come sono (`PresetLoad` le ripete dal tab; se il preset spegne il Tiled Diffusion e il lato supera 2048, `fitSizeToLimit` come sempre). Salvare non le scrive più; quelle presenti nei file già salvati e negli import restano nel file ma non si usano. Le sessioni, «Riprendi parametri» e l'editor JSON non cambiano: quelli sono parametri, non preset.

`Preset` ottiene `prompt: String` (vuoto = nessuno). Salvare un preset salva il prompt del tab; caricarlo lo rimette solo se non è vuoto. `PresetLoad` ottiene `prompt: String` (il prompt del preset se non è vuoto, altrimenti quello del tab). La lettura dei file è tollerante: un preset salvato prima non ha il campo e vale vuoto. La spec principale §6 («mai il prompt») si aggiorna. L'import di `custom_configs.json` non cambia (nessun prompt).

## 3. Preset che vengono da un plug-in

- Messaggio **`presets`** (plug-in → app): `{"presets":[{"name", "fields":{…}, "loras":[…]}]}`. `fields` ha le stesse chiavi di `contribute`, `prompt` e `negativePrompt` compresi (`width` e `height` si ignorano); il resto parte dai valori predefiniti. Un preset di un plug-in non ha modello. Risposta `{"type":"ok","added":n,"existing":m}`.
- **La provenienza sta nel nome** (deciso il 4 ottobre 2026, P3): il plug-in dà ai suoi preset un nome che comincia con un suo acronimo di 2–4 lettere, un punto mediano e il nome, per esempio «SMP · Overcast» o «SLR · Match the sun». Il menu non dice altro. Un preset di un plug-in resta un preset come gli altri: l'utente lo apre, lo cambia, lo salva con lo stesso nome o lo cancella. (P1 e P2 avevano un campo `origin` e «· da <plug-in>» nel menu: P3 li toglie.)
- **Mai sovrascritto dal plug-in:** un nome già presente non si tocca, né se l'ha modificato l'utente né se è identico. Quindi un plug-in aggiornato che cambia i suoi valori di fabbrica non cambia i preset già nel menu; per riavere quelli di fabbrica l'utente cancella il preset e il plug-in lo ricrea. Un nome occupato da un preset **dell'utente** non si tocca e conta come «existing». L'app non impone l'acronimo: la convenzione sta nel README.
- Il plug-in manda `presets` quando vuole (di norma quando riceve `activate` e prima di mandare la pipeline); solo un plug-in attivo, come per `contribute`.
- Spegnere un plug-in non toglie i suoi preset.

## 4. La pipeline di preset

`pipeline: {name, steps:[{title, preset, moodboard, startImage, useOutputAsStart}]}`. Sono tolti `fields` e `loras` del passaggio. Il passaggio:
1. parte dai campi del tab;
2. cerca il preset per nome: i **parametri** del preset (sampler, passi, guidance, shift, seed e batch, LoRA, card Avanzate…) sostituiscono quelli del tab (il formato non è nel preset, §2); il **negativo** e il **prompt** del preset, se non sono vuoti, sostituiscono quelli del tab; il **modello** si ignora. Un passaggio senza `preset` esegue i campi del tab com'è;
3. gli ingressi come in M8b: `moodboard` e `startImage` del passaggio sostituiscono quelli del tab per quel passaggio (maschera del tab esclusa se la partenza è sostituita), `useOutputAsStart` prende il risultato del passaggio precedente.

**Prima di partire** il Run controlla che tutti i preset della pipeline esistano; se ne manca uno, avviso «Preset non trovato: <nomi>» (come gli altri errori di Run, nella finestra Risultati che il Run apre) e nessuna generazione parte. Il suggerimento del pulsante Run elenca i passaggi con il nome del preset, e per ognuno se parte dall'output precedente. Il pulsante «Run · N passaggi» e «Togli la pipeline» restano.

## 5. Plug-in di esempio

`Sample` passa a 1.3: manda i suoi preset («Sample · Overcast» e «Sample · Match the sun», quest'ultimo con il LoRA sun-direction e peso 0,6) e una pipeline che li nomina; lo slider del peso del LoRA esce dalla scheda. `press` ottiene `presets`.

## 6. Moduli toccati

| Modulo | Cambia |
|---|---|
| HubKit | `Preset.prompt`, dimensioni non più usate; `PipelineStep` (`preset`, senza `fields`/`loras`); messaggio `presets` |
| HubCore | `PresetStore` (aggiunta per un plug-in senza sovrascrivere), `PresetLoad` (prompt; dimensioni del tab), applicazione di un preset a un passaggio, controllo dei preset mancanti |
| App | salvataggio e caricamento con il prompt, avviso del preset mancante, suggerimento del pulsante Run |
| PluginKit | `host.registerPresets(_:)`, Sample 1.3 |

## 7. Test e verifiche

**Unitari:** preset salvato e riletto con e senza prompt, file vecchi senza prompt, caricamento che non tocca il prompt se vuoto; caricamento che non cambia larghezza e altezza (anche con un file vecchio che le ha) e che con il Tiled spento riporta un lato oltre 2048 dentro il limite; aggiunta di preset di un plug-in (nuovi, già presenti, di un utente con lo stesso nome, valori di fabbrica che non sovrascrivono), origine conservata dopo che l'utente sovrascrive; applicazione di un preset a un passaggio (formato del tab e modello ignorati, prompt e negativo vuoti = quelli del tab, LoRA e parametri sostituiti); preset mancante = nessuna generazione e avviso; messaggio `presets` letto in modo permissivo e respinto da un plug-in non attivo.
**Dal vivo:** la pipeline del Sample con i due preset: modifico PresB (peso del LoRA) e il Run usa il nuovo peso senza che il plug-in rimandi nulla; cancello PresA e compare l'avviso.

## 8. Un file per preset (P3, deciso con l'utente il 4 ottobre 2026)

Al posto di `presets.json` c'è una **cartella `Presets/`** (nella cartella di supporto dell'app) con **un file `<nome>.json` per preset**. Nessuna migrazione: l'app non è ancora uscita e `presets.json` non si legge più.
- **Il nome del preset è il nome del file**, senza `.json`; nel JSON non c'è il campo `name` (né `id`, né `origin`). I nomi seguono le regole del file system di macOS: **non possono contenere `/` né `:`** (un salvataggio con quel nome è rifiutato con un messaggio; un plug-in che lo manda lo vede contato tra gli scartati) e **maiuscole e accenti non li distinguono** (due nomi uguali a meno di questi sono lo stesso preset).
- **L'elenco** (il menu Preset, «Gestisci preset…») si ricava dai **nomi dei file**; la cartella si rilegge all'avvio, dopo ogni modifica fatta dall'app, quando la finestra torna attiva e prima di ogni lettura di un preset: l'app non tiene il contenuto dei preset in memoria.
- **Il contenuto** si legge solo quando serve: caricando un preset si legge quel file, quel momento; un file modificato a mano vale subito. Un file che non si decodifica compare nell'elenco e dà un errore («Preset non leggibile: <nome>») quando lo si carica; gli altri non sono toccati.
- **La pipeline**: al Run l'app legge **solo i preset che la pipeline nomina** e li tiene in memoria per tutto il Run. Se uno manca («Preset non trovato: <nomi>») o non si legge («Preset non leggibile: <nomi>») non parte nessun passaggio. Un preset cancellato o cambiato durante il Run non cambia più nulla: vale la copia letta all'inizio.
- Salvare scrive il file (sostituendo quello dello stesso nome), rinominare rinomina il file, cancellare lo toglie. Un plug-in aggiunge un preset solo se il file non esiste.
- Fuori: controllare la cartella mentre l'app è aperta (la rilettura avviene come sopra); una cache dell'elenco.

## 9. Tappe (sullo stesso branch `m8b-plugin`, un solo merge alla fine, deciso con l'utente)

| Tappa | Contenuto |
|---|---|
| **P1** | Il prompt nei preset (§2) |
| **P2** | Preset dei plug-in e pipeline di preset (§3–§5) |
| **P3** | Un file per preset, lettura al bisogno, nome = acronimo del plug-in, senza `origin` (§8) |

Ogni tappa ha il suo piano; la revisione indipendente, le prove dell'utente e il merge seguono P2.

## 10. Rischi aperti

- Cambia il comportamento di tutti i preset: chi aveva preset con un formato (per esempio «Verticale 1024×1536») non lo ritrova più; i rapporti restano nel menu Proporzioni della card Dimensioni.
- Un preset con Avanzate nascoste per la famiglia o con LoRA di un'altra famiglia passa dai controlli di sempre (`JobComposer`): il passaggio può girare con meno cose di quelle che il preset dice. Vale già per i preset normali.
- Il Moodboard di un passaggio non sta nel preset: se serve cambiarlo, lo cambia il plug-in (per esempio la sfera di Sphere Light).
- Cambia il formato dei passaggi di M8b, non ancora uscito dal branch: nessuna compatibilità da mantenere.
