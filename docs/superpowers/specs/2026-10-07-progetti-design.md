# Gestione dei progetti — Design

Data: 7 ottobre 2026. Stato: approvato in chat dall'utente; da implementare in una sessione locale con Xcode e Swift.
Base: `origin/main` a `2cec6b2` (release 0.1.1, con «Migliora Prompt» e «Genera Prompt»).

## 1. Obiettivo

Oggi DT Hub ha una sola sessione globale: prompt e parametri in `session.json`, lo stato di Control in `control.json` e `Control/`, la striscia dei risultati in `results.json`, tutto in `~/Library/Application Support/DT Hub/`, e le immagini in `<output>/yyyy-MM-dd/`.
Si aggiunge il **progetto**: una sottocartella della cartella di output che raggruppa le immagini di un lavoro e lo stato che le immagini non contengono.

Successo: l'utente crea un progetto, ci lavora, ne apre un altro e ritrova il primo com'era (immagine di partenza, maschera, disegno, Moodboard, stato dei plug-in, parametri dell'ultima immagine). Un progetto nuovo parte da zero. Solo le preferenze restano globali.

## 2. Decisioni (dell'utente, 7 ottobre)

- Un progetto è una sottocartella della cartella di output. Prompt, modello e parametri sono già nell'EXIF delle immagini (`UserComment`, il job intero): non si salvano a parte.
- Da salvare per progetto: lo stato di Control e lo stato dei plug-in.
- Un progetto nuovo riporta parametri, Control e plug-in allo stato iniziale.
- Riaprendo un progetto: Control e plug-in salvati; prompt, modello e parametri dall'ultima immagine.
- Le immagini che l'utente ha già nella radice della cartella di output restano dove sono, fuori dall'app. **Non c'è un progetto predefinito:** si lavora sempre dentro un progetto.
- Approvato in chat: il progetto nuovo mantiene il modello scelto; i preset restano globali; il primo progetto creato adotta lo stato di Control esistente; il cambio progetto è rifiutato durante un RUN; la cronologia dei risultati è per progetto.

## 3. Cartelle

```
<output>/<Nome>/                      il progetto
<output>/<Nome>/yyyy-MM-dd/HHmmss-<seed>[-n].png     come oggi (PNGImageStore non cambia)
<output>/<Nome>/.dthub/project.json   il marcatore: {"schema": 1, "created": "<ISO 8601>"}
<output>/<Nome>/.dthub/control.json   ControlInputs
<output>/<Nome>/.dthub/Control/       le copie di immagine, maschera, disegno, Moodboard
<output>/<Nome>/.dthub/results.json   la striscia dei risultati
<output>/<Nome>/.dthub/plugins/<id>/  la cartella di ciascun plug-in
```

Un progetto è una sottocartella **diretta** della cartella di output che contiene `.dthub/project.json`. Le cartelle per data nella radice non hanno il marcatore e non sono progetti. La cartella `.dthub` è nascosta nel Finder. Rinominare, spostare o eliminare un progetto si fa dal Finder; l'app non lo gestisce (YAGNI).

## 4. Nome di un progetto

Valido se, tolti gli spazi ai bordi: non è vuoto; non contiene `/` né `:`; non inizia con un punto; non supera 120 caratteri; non ha la forma `yyyy-MM-dd` (si confonderebbe con le cartelle delle immagini); non coincide, senza distinguere maiuscole e accenti, con un progetto o una cartella già presenti nella cartella di output.

## 5. Architettura

Logica in **HubCore** (testabile con `swift test`); nell'app solo collegamento e interfaccia.

```
HubCore/Projects/
  Project.swift          Project (name, folder) e i suoi percorsi (.dthub, control.json, Control/, results.json, plugins/<id>)
  ProjectName.swift      la validazione del §4
  ProjectCatalog.swift   elenca i progetti di una cartella, ne crea uno (cartelle + marcatore)
  LegacyState.swift      sposta control.json e Control/ di Application Support dentro un progetto
  ProjectImages.swift    l'ultima immagine di un progetto e il suo job
  ProjectManager.swift   @MainActor @Observable: progetto corrente, elenco, create/open, blocco, richiami
```

### 5.1 `ProjectManager`

- Stato: `current: Project?`, `projects: [Project]`, `lastError`.
- Il nome del progetto corrente è ricordato in `UserDefaults` (chiave `project.current`), relativo alla cartella di output. Se la cartella non c'è più, o non ha il marcatore, `current` è `nil`.
- `canSwitch: () -> Bool` (iniettato): falso durante un RUN, la preparazione o una pipeline. `open`/`create` con `canSwitch() == false` non fanno nulla e impostano `lastError = .busy`.
- `create(name:)`: valida, crea cartelle e marcatore, **apre** il progetto nuovo. Se è il primo progetto creato e lo stato di Control precedente esiste in Application Support, lo adotta (`LegacyState`) e lo segnala ai plug-in (`adoptLegacy`).
- `open(_ project:)`: porta Control, striscia, parametri e plug-in sul progetto. Sequenza: (1) controllo `canSwitch`; (2) `current = project`; (3) richiami nell'ordine Control → striscia dei risultati → parametri → plug-in. I richiami sono iniettati (`onOpen: (Project, OpenReason) async -> Void`), così HubCore non conosce l'app.
- `OpenReason`: `.created(adoptsLegacy: Bool)`, `.reopened`, `.launch`.
- `refresh()`: rilegge l'elenco; chiamato quando il menu si apre e quando cambia la cartella di output. Se il progetto corrente è sparito, `current = nil`.

### 5.2 Control

`ControlStore` oggi fissa `storage` e `fileURL` all'`init`. Diventano modificabili: nuovo `func switchTo(storage: any ReferenceStorage, fileURL: URL)` che azzera storia di undo/redo e notifica, ricarica da `fileURL` con le stesse regole dell'`init` (copie mancanti scartate con avviso) e spazza le copie non referenziate **solo nel nuovo storage**. Il caricamento dell'`init` diventa un metodo condiviso. All'avvio, senza progetto, il `ControlStore` punta a un posto inerte in `NSTemporaryDirectory()` e l'interfaccia è bloccata dal foglio del §7.

### 5.3 Striscia dei risultati

`GenerationSession` riceve `func switchHistory(to history: ResultsHistoryStore?) async`: svuota `results`, imposta la nuova `history`, chiama `restoreHistory()`. Rifiutata se `isRunning`. `CurrentFolderImageStore` (App) salva nella cartella del progetto corrente, non più in `OutputSettingsStore().folder()`; senza progetto lancia `ImageStoreError.cannotWrite`.

### 5.4 Parametri alla riapertura

`ProjectImages.latestJob(in project:) -> GenerationJob?`: la PNG più recente nelle cartelle `yyyy-MM-dd` del progetto (cartella per data decrescente, poi nome decrescente), con `PNGImageStore.job(in:)`. Nessuna PNG o job illeggibile → `nil`.

`GenerationController.apply(_ job: GenerationJob?, ...)`: con un job imposta prompt, negativo e parametri e, se il modello del job è nel catalogo, lo seleziona con `connection.selection.select(_:)` (senza applicare i valori consigliati, che sovrascriverebbero i parametri). Con `nil` (progetto nuovo o senza immagini): prompt e negativo vuoti, `GenerationParameters.default`, lock del rapporto spento, modello invariato.

**Riavvio dell'app:** `session.json` resta e guadagna `project: String?` (lenient). Se `project` coincide con il progetto riaperto all'avvio, si ripristina la sessione (anche il prompt non ancora generato); altrimenti vale l'EXIF come alla riapertura. Il cambio di progetto a runtime usa sempre l'EXIF.

### 5.5 Plug-in

Messaggio nuovo **App → plug-in** (contratto 1: un tipo sconosciuto riceve già `{"type":"unsupported"}`):

```json
{"type":"project","name":"Campagna","folder":"/…/Campagna/.dthub/plugins/<id>","adoptLegacy":false}
```

- Inviato a ogni plug-in **caricato** (acceso o no) quando un progetto si apre e subito dopo il caricamento all'avvio. `folder` è creata dall'app.
- Il plug-in salva il suo stato in `<folder>/state.json` (a ogni cambio, come oggi in `UserDefaults`), carica quello della cartella nuova e rinfresca la vista. File assente o illeggibile → stato iniziale.
- `adoptLegacy: true` solo al primo progetto: se la cartella non ha `state.json` e il plug-in ha uno stato vecchio in `UserDefaults`, lo scrive nel file prima di caricare. Così il lavoro di prima non va perso.
- Un plug-in che risponde `unsupported` (non aggiornato) continua col suo stato globale: l'app mostra una sola nota «Il plug-in X non separa lo stato per progetto» (non un errore).
- HubKit: `PluginProject` (Codable) e `PluginMessageType.project`. PluginKit: `DTHubProject` (Decodable) per i plug-in.
- I tre plug-in del repo (Prompt Master, Prompt Master I4, Sphere Light) vengono adattati. Le versioni vanno alzate e i `.dthubplugin.zip` della prossima release rifatti.

## 6. Flusso: aprire un progetto

1. Menu Progetto → voce. `ProjectManager.open` controlla `canSwitch`.
2. Control: `switchTo(storage: FileReferenceStorage(folder: project.controlFolder), fileURL: project.controlFile)`.
3. Striscia: `session.switchHistory(to: ResultsHistoryStore(fileURL: project.resultsFile))`.
4. Parametri: `apply(ProjectImages.latestJob(in: project))` (o la sessione, all'avvio, se coincide).
5. Plug-in: `PluginRegistry.projectChanged(project, adoptLegacy:)` invia `project` a ogni plug-in caricato.

## 7. Interfaccia

- **Menu «Progetto»** nella `HeaderBar`, prima del menu Plug-in: etichetta con il nome corrente; elenco dei progetti (spunta sul corrente), separatore, «Nuovo progetto…», «Mostra nel Finder».
- **«Nuovo progetto…»:** foglio con un campo nome, errore sotto il campo secondo il §4, pulsanti Annulla/Crea.
- **Senza progetto corrente** (primo avvio, cartella cambiata, progetto sparito): un foglio modale «Crea il primo progetto» (o «Scegli un progetto» se la cartella ne ha) sopra la finestra; RUN è disabilitato.
- **Preferenze › Output:** cambiare la cartella rilegge i progetti; il corrente diventa `nil` e compare il foglio. Il testo di nota spiega che i progetti sono le sottocartelle.
- Testi in italiano e inglese in `Localizable.xcstrings`.

## 8. Errori

- Cartella di output non scrivibile: `create` fallisce con l'errore del file system, mostrato nel foglio.
- Marcatore o `control.json` illeggibili: progetto non elencato / Control vuoto (come oggi con un `control.json` corrotto). Mai un crash.
- `state.json` di un plug-in illeggibile: stato iniziale del plug-in.
- Cambio durante RUN: voce di menu disabilitata e, se invocato lo stesso, `lastError = .busy`.

## 9. Test

HubCoreTests (`swift test` da `Packages/`): `ProjectName` (casi del §4), `ProjectCatalog` (elenco, creazione, cartelle date ignorate, marcatore), `LegacyState` (sposta, non sovrascrive, assente), `ProjectImages` (ordine, assente, illeggibile), `ControlStore.switchTo` (stati separati, undo azzerato, copie dell'altro progetto non cancellate), `GenerationSession.switchHistory`, `ProjectManager` (create/open, `canSwitch`, ricordo del corrente, progetto sparito, richiami nell'ordine), `PluginRegistry` (invio di `project` ai caricati, anche se spenti). Plug-in: round trip di `state.json`, stato iniziale, `adoptLegacy`. L'app non ha test di UI: verifica a mano (§11).

## 10. Fuori ambito (YAGNI)

Rinominare, spostare, archiviare o eliminare progetti dall'app; modelli di progetto; migrare le immagini della radice; stato dei preset per progetto; sincronizzazione tra due Mac; salvare il prompt non generato per progetto (solo all'avvio, vedi §5.4).

## 11. Da verificare a mano (Mac, DT Hub, un server)

- Creare due progetti, mettere immagine di partenza e Moodboard nel primo, passare al secondo (vuoto), tornare al primo (tutto com'era).
- Riaprire un progetto con immagini: prompt, modello e parametri dell'ultima immagine.
- Primo avvio da installazione con dati vecchi: il primo progetto adotta Control; plug-in aggiornati adottano il loro stato.
- RUN in corso: voci del menu disabilitate.
- Cambiare la cartella di output; cancellare dal Finder il progetto corrente con l'app aperta.
- Plug-in vecchio (0.1.x non aggiornato): una sola nota, nessun errore.
