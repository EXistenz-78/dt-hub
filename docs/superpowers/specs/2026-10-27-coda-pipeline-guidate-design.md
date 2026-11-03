# Coda di generazioni: pipeline guidate dei plug-in — design

Data: 2026-10-27. Stato: bozza per revisione. Estende `2026-10-27-coda-generazioni-design.md` (§2: le pipeline guidate erano fuori scopo).

## 1. Scopo

Mettere in coda anche le voci con una **pipeline guidata** su RUN: Tiled Upscale e Panorama 360 «correggi giunzione». Oggi il **+** le rifiuta, perché la sessione del plug-in vive solo in memoria e l'host non può ricrearla.

L'uso reale: l'utente mette in coda più lavori pesanti (un panorama ad alta risoluzione può durare ore) e lascia lavorare l'app di notte. Quindi **nessun limite di tempo fisso**, e nessuna finestra di dialogo che blocchi la coda.

## 2. Decisioni prese con l'utente

| Tema | Decisione |
|---|---|
| Approccio | **A**: istantanea dei soli **ingressi** del plug-in (immagine sorgente e scelte), con due messaggi nuovi `queue.capture` / `queue.prepare`. Non si salva mai uno stato a metà pipeline. |
| Plug-in chiuso | Se all'avvio della voce il plug-in non è aperto, la voce **fallisce** (X arancione col motivo) e la coda prosegue. L'host non lo riapre. |
| Tempo | **Nessun limite fisso** sui messaggi della coda. Si aspetta la **fine vera** del plug-in; Stop interrompe sempre l'attesa. |
| Fine voce | Come per le altre voci: un nuovo risultato nei Results. Tiled Upscale e Panorama lo mandano entrambi ai Risultati. |
| Plug-in che non conosce `queue.capture` | Risponde `unsupported`: il **+** lo rifiuta come oggi, con un avviso. |

## 3. Cosa c'è nel codice

- Una pipeline guidata (`PluginPipeline.guided != nil`) è proposta dal plug-in con `contribute {"pipeline":{"guided":true,"passes","estimate"}}` quando l'utente preme «Prepara» (Tiled Upscale) o «Correggi giunzione» (Panorama). Poi l'utente preme RUN.
- `GenerationController.runGuidedPipeline` → `GuidedSessionDriver`: per ogni passo chiede `session.next` (60 s di risposta, da contratto), esegue il passo, e alla fine manda `session.end`. Il plug-in manda il montaggio finale **dentro** `session.end` (`contribute`/`result`); la risposta di `session.end` è ignorata.
- `PluginRegistry.request(_:to:timeout:)` aspetta la risposta **o** il timeout; non reagisce all'annullamento del Task. L'host aspetta `session.end` per 5 s (`channel.request($0, pluginID, .seconds(5))`).
- **Tiled Upscale**: scelte in `state.json` (`TUChoice`: fattore, overlap, impostazioni, LoRA, istruzioni); immagine sorgente (`image`, `imageName`) solo in memoria; `prepare(confirmed:)` costruisce `TUSession` e propone la pipeline. Senza `confirmed` può mostrare la conferma «lavoro grosso» (`needsConfirmation`).
- **Panorama 360**: `prepareSeamCorrection` costruisce `PSSeamSession` dall'**ultimo risultato** (`lastResultPath`, un file che cambia a ogni generazione); composizione e maschera si calcolano da lì; il risultato del passo viene reinserito in `session.end`.
- Quando due plug-in propongono una pipeline o un'immagine di partenza, l'app apre una finestra di scelta. In coda non deve succedere.

## 4. Contratto PluginKit (aggiunta opzionale al contratto 1)

Due messaggi app → plug-in. Il plug-in che non li gestisce risponde `unsupported` (già la regola generale).

```
{"type":"queue.capture","folder":"<cartella della voce>"}
→ {"type":"ok","state":{…}}                    // oggetto JSON opaco, deciso dal plug-in
→ {"type":"error","text":"…"}                  // non può catturare ora (nessuna sessione, ecc.)

{"type":"queue.prepare","folder":"<cartella della voce>","state":{…},"model":"<file del modello>","family":"<famiglia, assente se ignota>"}
→ {"type":"ok"}                                // sessione ricostruita, pipeline proposta all'app
→ {"type":"error","text":"…"}
```

- `capture`: il plug-in scrive nella `folder` (creata dall'host) le copie dei file che gli servono (immagine sorgente) e li cita in `state` con nomi **relativi**. L'host non interpreta `state`: lo conserva e lo restituisce così com'è.
- `model` e `family` servono perché un plug-in non attivo non riceve il contesto: senza di loro cercherebbe il preset per il modello di prima, non per quello della voce. Il plug-in li applica prima di costruire la sessione.
- `prepare`: il plug-in ricarica scelte e file dalla `folder` e dallo `state`, applica lo stato come se l'utente l'avesse impostato (la scheda del plug-in mostra quello stato, come Generazione e Control mostrano quello della voce), costruisce la sessione e propone la pipeline con `contribute` come il suo «Prepara». **Non chiede conferme** (la voce era già stata approvata quando era stata messa in coda). Risponde `ok` solo a pipeline proposta e accettata dall'app.
- In `PluginKit`: costanti dei tipi e due struct `Codable` (`DTHubQueueCapture`, `DTHubQueuePrepare`) per leggere e scrivere i messaggi; documentazione nel README. Il contratto resta il numero 1.

## 5. Dati e host

HubKit:

```swift
public enum QueuedPipeline {
  case user(name: String)
  case plugin(pluginID: String, name: String, steps: [PipelineStep])
  case guided(pluginID: String, name: String, passes: Int, state: QueueSnapshot)   // nuovo
}
public struct QueueSnapshot: Codable, Equatable, Sendable   // JSON opaco del plug-in, conservato come testo JSON
```

Su disco: i file della voce stanno in `<progetto>/.dthub/Queue/<id-voce>/plugin/`. Il decodificatore di `QueuedPipeline` impara il caso `.guided`; il piano verifica che una voce con un caso sconosciuto (file scritto da una versione più nuova) non faccia perdere le altre voci della coda.

**Cattura (+).** Se la pipeline su RUN è guidata: l'host manda `queue.capture` al plug-in proprietario (`contributions.pipeline.pluginID`) con la cartella della voce. `ok` → la voce prende `.guided(...)`; `unsupported`, `error` o plug-in non caricato → nessuna voce e un avviso col motivo (il messaggio «non si possono ancora mettere in coda» diventa «questo plug-in non supporta la coda» / il testo dell'errore). Le immagini del plug-in nella cartella della voce sono cancellate insieme alla voce, come quelle di Control.

**Ripristino (Start e clic sulla voce).** Prima il modello, i parametri e Control, poi `removePipeline()` (così non c'è conflitto di pipeline), poi `queue.prepare`. Se il plug-in non è caricato, non risponde `ok` o risponde `error` → la voce fallisce con il motivo. Un clic a mano sulla voce fa solo il ripristino: se il plug-in non è aperto, avviso e basta.

**Esecuzione.** `runQueueEntryAndWait` resta com'è per il Run; per una voce guidata cambiano due cose:
1. **Fine vera.** L'invio di `session.end` aspetta il ritorno del gestore del plug-in **senza limite di tempo** (il plug-in manda il montaggio dentro il gestore). Solo così il montaggio finale esiste quando la coda legge i Results, e la voce successiva non parte con il plug-in ancora occupato.
2. **Stop.** L'attesa è annullabile: Stop (o un plug-in che si scarica) la interrompe. Una voce interrotta torna `pending` e, alla ripartenza, rifà `prepare` dal passo 0.

`PluginRegistry.request` guadagna una variante senza timeout e sensibile all'annullamento (`withTaskCancellationHandler`); `session.next` resta a 60 s come da contratto (la sessione ricostruita risponde subito: il lavoro pesante è del Run dell'app).

## 6. Plug-in

- **Tiled Upscale**: `capture` copia l'immagine sorgente nella `folder` e restituisce `{factor, overlap, settings, loraWeights, extraPrompt, image: "<nome file>", imageName}`. `prepare` ricarica l'immagine e le scelte (le scrive anche in `state.json`) e chiama `prepare(confirmed: true)`.
- **Panorama 360**: `capture` copia l'ultimo risultato (il panorama sorgente) nella `folder`; lo `state` contiene il nome del file. `prepare` costruisce `PSSeamSession` da quel file e propone la pipeline (stessa strada di `prepareSeamCorrection`, ma dal file della voce invece che da `lastResultPath`).
- Nessuno dei due salva lo stato a metà pipeline: i tile e la maschera si ricalcolano durante il Run.
- Sono bundle separati: vanno ricompilati e reinstallati in `~/Library/Application Support/DT Hub/Plug-ins/`; la versione di ciascuno sale.

## 7. Flussi ed errori

- **+** con pipeline guidata e plug-in aperto → voce con etichetta «pipeline: nome». Plug-in chiuso, `unsupported`, `error` → avviso, nessuna voce.
- **Start**: voce guidata e plug-in chiuso → X arancione («il plug-in non è aperto»), si prosegue.
- **Montaggio assente** (plug-in ha chiuso con `failed`/`stopped`, nessun risultato nuovo) → X con «nessun risultato», come oggi.
- **Stop durante la pipeline** → `session.end(stopped)`, la voce torna `pending`.
- **Chiusura dell'app o cambio progetto a coda in corso**: invariato (il cambio progetto è bloccato; alla riapertura `running` torna `pending`).
- **Finestre**: la coda non apre mai conferme del plug-in; la pipeline su RUN è rimossa prima di `prepare`, quindi nessuna scelta tra due plug-in.

## 8. Test

HubKit / HubCore (`swift test` in `Packages`):
- `QueuedPipeline.guided` e `QueueSnapshot`: round-trip JSON, tolleranza ai campi mancanti, snapshot opaco restituito identico.
- `PluginRegistry.request` senza timeout: ritorna alla risposta; annullato a metà ritorna subito `nil`; plug-in non caricato → `nil` subito.
- `QueueRunner` con host finto: voce guidata ok; plug-in chiuso (X, si prosegue); `prepare` che fallisce; Stop a metà (torna `pending`).
- Controller / cattura: pipeline guidata + `ok` → voce; `unsupported`/`error`/chiuso → nessuna voce con messaggio.

PluginKit: round-trip delle due struct. Plug-in (ciascuno nei propri test): `capture` → `prepare` ricostruisce una sessione equivalente (Tiled Upscale: stesse scelte e stessa griglia di tile; Panorama: stesso piano e stessa maschera), senza conferme.

App: build Debug; prova a mano con una voce Tiled Upscale e una Panorama (anche con un plug-in chiuso, per vedere la X).

## 9. Rischi

- **Gestore di `session.end` che non ritorna mai** (bug del plug-in): senza timeout la coda resta ferma. Si esce con Stop; il motivo è nel README del contratto («rispondi quando hai finito»).
- **Plug-in vecchi**: senza `queue.capture` restano rifiutati (nessuna regressione).
- **Stato del plug-in sovrascritto dal ripristino**: la scheda del plug-in mostra lo stato della voce, come fanno Generazione e Control. Da dire nell'avviso/README, non da evitare.
- **Disco**: ogni voce guidata copia un'immagine (un panorama può essere grande); Svuota ed elimina la liberano.
