# Coda di generazioni (sidebar «Coda») — design

Data: 2026-10-27. Stato: bozza per revisione.

## 1. Scopo

Una sidebar a sinistra della finestra principale per mettere in fila generazioni. L'utente prepara Generazione e Control, preme **+** e la configurazione intera diventa una voce. Con **Start** le voci vengono eseguite una dopo l'altra: per ognuna l'app ricarica Generazione e Control com'erano e preme Run.

Richiesta dell'utente, in sintesi:
- in alto **+** e **Start**; sotto la lista; in fondo **Svuota**;
- **+** salva parametri, prompt, negativo, modello, eventuale refiner, pipeline a RUN e tutto Control (immagini incluse);
- **Start** ricarica la prima voce e avvia Run; finito il Run si passa alla successiva; la voce finita ha una spunta verde, o una X arancione se è finita con errore.

## 2. Decisioni prese con l'utente

| Tema | Decisione |
|---|---|
| Errore di una voce | La voce prende la X arancione e la coda **continua**. |
| Stop | Ferma il Run in corso **e tutta la coda**. La voce interrotta e quelle seguenti restano in attesa; Start riparte da lì. |
| Voci | Clic = ricarica in Generazione e Control (senza avviare); trascinamento = riordina; menu/tasto = elimina. Le voci eseguite restano con spunta o X. |
| Persistenza | **Per progetto, su disco**: sopravvive ai riavvii e segue il progetto aperto. Le immagini sono copie nella cartella del progetto. |
| Pipeline | Salvate le pipeline **non guidate**: quelle dell'utente (per nome del file) e quelle dei plug-in (Sphere Light, Batch+, AI Assistant) come copia dei passi. Le pipeline **guidate** (Tiled Upscale, Panorama 360 «correggi giunzione») sono rifiutate dal **+** con un avviso. |
| CU Meter | Invariato: segue lo stato attuale di Generazione e Control, non somma la coda. |
| Tab bar | Invariato. |

**Fuori scopo di questa versione**: stato dei plug-in guidati (richiederebbe `queue.capture` / `queue.prepare` nel PluginKit e l'implementazione in Tiled Upscale e Panorama 360, un lavoro a parte). La struttura della voce lascia posto a un campo opzionale futuro, senza costruirlo ora.

## 3. Cosa c'è nel codice

- `Preset` (HubKit) = modello, prompt, negativo, `GenerationParameters`. `PresetStore` lo salva come file ma **scarta la dimensione** (`withoutSize`); la voce deve invece tenerla, quindi non passa dal `PresetStore`.
- `ControlInputs` è `Codable`; le immagini sono file nello `ReferenceStorage` di Control (`<progetto>/.dthub/Control/`), gestite da `ControlStore` con garbage collection: ciò che non è referenziato da `inputs` o dalla cronologia Undo viene cancellato. Le copie della voce vanno quindi **fuori** da quella cartella.
- Il progetto ha `.dthub/` (`Project.stateFolder`): `control.json`, `Control/`, `results.json`, `plugins/<id>/`. La coda sta in `.dthub/Queue/`.
- `GenerationController.run(with:)` ritorna subito: avvia `preparation` (un `Task`). Il Run semplice finisce con `session.waitUntilFinished()`; le pipeline sono interamente dentro `preparation`. La fine si legge da `session.phase` (`.failed`) e `session.lastRunWasStopped`.
- `PluginPipeline` / `PipelineStep` (HubKit) **non** sono `Codable`; contengono `FieldOverlay`, `[LoRASelection]` e `PluginImageRef` (nome + **percorso di un file**, ad esempio la sfera di Sphere Light nella cartella temporanea del plug-in).
- Una pipeline utente si rimette su RUN con `generation.selectPipeline(named:)`; una di plug-in con `ContributionStore` (serve un metodo pubblico per impostarne una non guidata, vedi §5).

## 4. Dati

HubKit (puri, testabili):

```swift
public struct QueueEntry: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var createdAt: Date
  public var status: QueueStatus          // .pending / .running / .done / .failed(String)
  public var preset: Preset               // modello, prompt, negativo, parametri (dimensione inclusa)
  public var lockRatio: Bool
  public var control: ControlInputs       // file name relativi alla cartella della voce
  public var pipeline: QueuedPipeline?    // nil = nessuna pipeline su RUN
}

public enum QueuedPipeline: Codable, Equatable, Sendable {
  case user(name: String)                                   // riletta dal file allo Start
  case plugin(pluginID: String, name: String, steps: [PipelineStep])  // copia dei passi
}
```

- `Preset` è già `Codable` (senza `name`, che qui resta vuoto). Il refiner è dentro `GenerationParameters`, come per i preset.
- `PipelineStep` e le sue parti diventano `Codable` (conformità scritta a mano, tollerante come gli altri formati salvati). `PluginImageRef.path` viene riscritto sul percorso della copia nella cartella della voce.
- `QueueStatus.running` non è mai salvato: al caricamento una voce `running` torna `pending`.

Su disco, per progetto:

```
<progetto>/.dthub/Queue/queue.json              [QueueEntry]
<progetto>/.dthub/Queue/<id-voce>/<file>.png    copie di start, mask, paint, moodboard,
                                                 e immagini dei passi della pipeline
```

## 5. Componenti

**HubCore**
- `QueueStore` (`@MainActor @Observable`): `entries`, `add`, `remove`, `move`, `clear`, `setStatus`; legge e scrive `queue.json` (atomico); `switchTo(folder:)` per seguire il progetto, come `ControlStore.switchTo`. Cancellare una voce o svuotare rimuove la sua cartella.
- `ControlStore`: due metodi nuovi.
  - `captureForQueue(into:)` → copia i file referenziati da `inputs` nella cartella data e ritorna `ControlInputs` coi nomi relativi;
  - `restoreFromQueue(_ inputs:, from:)` → copia i file nello storage di Control e applica lo stato in **un solo** `commit` (quindi annullabile con Undo e protetto dalla garbage collection).
- `QueueRunner` (`@MainActor @Observable`): macchina a stati `idle / running(entryID) / stopping`. Prende un `QueueHost` (protocollo, per i test):

```swift
protocol QueueHost {
  func canRun() -> Bool
  func restore(_ entry: QueueEntry) -> String?        // nil = ok; testo = errore di ricarica
  func runAndWait() async -> QueueRunOutcome          // .finished / .failed(String) / .stopped
  func stop()
}
```

  Ciclo: prende la prima voce `pending`; la segna `running`; `restore`; se fallisce → `.failed` e prosegue; `runAndWait`; `.finished` → `.done`; `.failed(m)` → `.failed(m)` e prosegue; `.stopped` → la voce torna `pending` e il ciclo si ferma. Finite le voci, torna `idle`.
- `ContributionStore.setPipeline(_:pluginID:)`: metodo pubblico per mettere su RUN una pipeline non guidata di un plug-in, con la stessa guardia `pipelineLocked` di `setUserPipeline`.

**App**
- `GenerationController` implementa `QueueHost` (o un piccolo adattatore):
  - `capture(connection)` → `QueueEntry` (rifiuta con un messaggio se `contributions.pipeline?.pipeline.guided != nil`);
  - `restore`: modello via `connection.selection.select`, parametri/prompt/negativo/`lockRatio`, Control con `restoreFromQueue`, pipeline (`selectPipeline(named:)`, `setPipeline`, oppure `removePipeline()` se la voce non ne ha);
  - `runAndWait`: `run(with:)`; `await preparation?.value`; `await session.waitUntilFinished()`; poi legge `session.phase` e `lastRunWasStopped`.
  - `isBusyForProjectSwitch()` include la coda in esecuzione.
- `QueueSidebar` (SwiftUI): in `MainWindowView`, a sinistra a tutta altezza sotto l'header, con un pulsante nell'header della finestra principale (`HeaderBar`, icona sidebar) per aprirla e chiuderla; stato aperto/chiuso e larghezza si ricordano tra i riavvii (approvato dall'utente). Riga: numero, prompt su una riga, modello, stato (in attesa, in corso con progress, ✓ verde, ✕ arancione con il motivo nel tooltip), etichetta «pipeline: nome». **Svuota** chiede conferma ed è disattivato a coda in corso. Start diventa **Stop** durante la coda.
- Stringhe in `Localizable.xcstrings` (it/en).
- `DTHubApp`: crea `QueueStore`/`QueueRunner` e li ricollega in `onOpen` (insieme a `control.switchTo`).

## 6. Flussi ed errori

- **+**: richiede modello e progetto aperti. Se la pipeline su RUN è guidata → avviso «Le pipeline guidate dei plug-in non si possono ancora mettere in coda», nessuna voce. Se la copia di un'immagine fallisce → nessuna voce, messaggio.
- **Start**: se non ci sono voci `pending` → messaggio. Se `canRun` è falso (server, modello, run già in corso) → messaggio e non parte.
- **Voce non ricaricabile** (modello assente dal catalogo, immagine o preset della pipeline mancante, pipeline utente non più leggibile): `.failed(motivo)`, si prosegue.
- **Errore in Run** (`session.phase == .failed`, preset di una pipeline mancante, plug-in chiuso): `.failed(motivo)`, si prosegue.
- **Stop**: `stop()` del controller + la coda si ferma; la voce in corso torna `pending`.
- **Chiusura dell'app o cambio progetto a coda in corso**: il cambio progetto è bloccato (`isBusyForProjectSwitch`). Alla chiusura una voce `running` viene riletta come `pending`.
- **Ricarica a mano** (clic su una voce): come `restore`, ma solo a coda ferma; non avvia nulla.
- Durante la coda Generazione e Control restano modificabili; la voce successiva li sovrascrive. **+** durante la coda aggiunge in fondo (cattura lo stato attuale).

## 7. Test

HubKit / HubCore (`swift test` in `Packages`):
- `QueueEntry` e `QueuedPipeline`: round-trip JSON, tolleranza ai campi mancanti, `PipelineStep` `Codable` incluso `PluginImageRef`.
- `QueueStore`: aggiungi / rimuovi / sposta / svuota, persistenza su disco, `running` riletto come `pending`, `switchTo` di un altro progetto, pulizia delle cartelle.
- `ControlStore.captureForQueue` / `restoreFromQueue`: immagini, mask, paint, moodboard e framing identici; un solo passo di Undo; i file sopravvivono alla garbage collection.
- `QueueRunner` con un `QueueHost` finto: tutte ok; errore a metà (X e si prosegue); Stop (voce in corso `pending`, le altre intatte); voce non ricaricabile; `canRun` falso; coda vuota.

App: build Debug; prova a mano con due voci (una con Control e moodboard, una con pipeline utente).

## 8. Rischi

- **`PipelineStep` Codable** è la parte più delicata (molti campi, `FieldOverlay` con valori eterogenei). Si copre con test di round-trip sui casi reali di Sphere Light e Batch+.
- **Fine del Run**: la pipeline normale e il Run semplice finiscono in punti diversi di `preparation`; il piano deve verificare con test che `runAndWait` non ritorni prima della fine di una pipeline.
- **Spazio su disco**: ogni voce copia le immagini; `Svuota` ed elimina le liberano.
