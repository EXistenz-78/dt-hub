# Modalità incrementale (risultato → immagine di partenza) — Design

Data: 9 ottobre 2026. Stato: approvato in chat dall'utente; da implementare in una sessione locale con Xcode e Swift.
Base: `origin/main` a `50e8a0e` (release 0.1.3).

## 1. Obiettivo

Un interruttore che, acceso, fa diventare il risultato di ogni RUN l'immagine di partenza (card Immagine del tab Control) del RUN successivo, per lavorare in modo incrementale. Spento, tutto funziona come oggi.

## 2. Decisioni (dell'utente, 9 ottobre)

- Interruttore nell'**header della finestra principale**, accanto a RUN.
- Icona `arrowshape.bounce.right` quando è spento; `arrowshape.bounce.right.fill` in **teal** (`DS.accent`) quando è acceso.
- Help (e etichetta di accessibilità): «Incrementale: ogni risultato diventa l'immagine di partenza per la RUN successiva» / «Incremental: each result becomes the start image for the next RUN».
- Approvato in chat: con una pipeline vale l'ultima immagine; si entra in Control come «Usa come immagine» (⌘Z la toglie); niente dopo un RUN fallito, interrotto con Stop o senza immagini; forza invariata; maschera e disegno azzerati dal cambio d'immagine; interruttore globale (non per progetto) e ricordato.

## 3. Quale immagine

L'immagine **in cima alla striscia** arrivata durante il RUN, cioè `PipelineInputs.output(after:in:)` con l'id in cima prima del RUN (la stessa regola che le pipeline usano già tra un passaggio e l'altro). Con più batch è l'ultimo batch; dentro un batch è la prima immagine del batch. Con una pipeline: quella dell'ultimo passaggio, solo se tutti i passaggi sono finiti.

Nota rispetto alla discussione in chat («la prima»): con più batch la striscia mette in cima l'ultimo batch; si usa quella, coerente con le pipeline. Costo se sbagliata: con `batchCount > 1` parte dall'ultimo batch invece che dal primo.

## 4. Logica (HubCore, testata)

```swift
// HubCore/Generation/IncrementalRun.swift
public enum IncrementalRun {
  /// Il risultato da usare come immagine di partenza, o nil.
  @MainActor
  public static func output(
    enabled: Bool, phase: GenerationSession.Phase, stopped: Bool,
    before: GeneratedImage.ID?, results: [GeneratedImage]
  ) -> GeneratedImage?
}
```

Nil se `!enabled`, se `phase` è `.failed`, se `stopped`, o se `PipelineInputs.output(after: before, in: results)` è nil.

`GenerationSession` guadagna `public private(set) var lastRunWasStopped: Bool`: falso all'inizio di ogni RUN (`start`), vero quando il RUN finisce per `CancellationError` (Stop). Oggi Stop e fine normale lasciano entrambi `phase = .idle`: serve per distinguerli.

## 5. App

- `GenerationController`: `@AppStorage`-equivalente in `UserDefaults` con chiave `generation.incremental` (default `false`), esposto come `var incremental: Bool` osservabile (o `@AppStorage` direttamente nella vista e letto dal controller da `UserDefaults`: scelta di chi implementa, purché la chiave sia quella).
- RUN semplice: nel `Task` di `run(with:)`, prima di `start(...)` si ricorda `before = session.results.first?.id`; dopo `start`, `await session.waitUntilFinished()` e, se `IncrementalRun.output(...)` dà un'immagine, la si applica.
- Pipeline: `runPipeline` restituisce l'ultima immagine prodotta se tutti i passaggi sono finiti (nil altrimenti); la si applica con la stessa regola (`stopped` = `Task.isCancelled` o `session.lastRunWasStopped`).
- Applicare: come `ResultsView.useAsImage` — `control.setImage(fileURL:source: .result)` se l'immagine ha un file, altrimenti `control.setImage(_:name:source: .result)` con `results.unsaved.name`. Un `ControlError` va mostrato con `session.fail(with: .generationFailed(<testo di ControlText.error>))` (raro: file sparito o disco pieno).
- `HeaderBar`: pulsante con `DSGlassCircleButtonStyle()` tra l'impostazione e RUN; icona e colore secondo lo stato; `help` e `accessibilityLabel` dal testo del §2; `accessibilityValue` acceso/spento.
- Testi in `Localizable.xcstrings`: `header.incremental.help` (it/en del §2), `header.incremental.on` Attivo / On, `header.incremental.off` Spento / Off.

## 6. Test

HubCoreTests: `IncrementalRunTests` (spento → nil; fallito → nil; stoppato → nil; nessuna immagine nuova → nil; immagine nuova → quella in cima; `before` nil e striscia vuota prima → la prima del RUN); `GenerationSession`: `lastRunWasStopped` vero dopo `cancel()` e falso dopo un RUN completo e all'inizio del RUN seguente (con il `FakeBackend` di `GenerationSessionTests`). L'app non ha test di UI: prove a mano (§7).

## 7. Da verificare a mano

- Acceso: due RUN di fila; il secondo parte dal primo risultato (card Immagine mostra l'origine «Risultato»); ⌘Z in Control riporta l'immagine di prima.
- Stop durante il RUN: l'immagine di partenza non cambia.
- RUN fallito (server spento): non cambia.
- Batch 2×1 e 1×2: quale immagine entra.
- Una pipeline di un plug-in (Sphere Light o Character Sheet): entra l'ultima.
- Spento: nessun cambiamento rispetto a oggi.
- Icona spenta/accesa in tema chiaro e scuro; help in italiano e inglese; scelta ricordata al riavvio.

## 8. Fuori ambito

Mantenere maschera o disegno tra un passo e l'altro; scegliere quale immagine di un batch; interruttore per progetto; storia dei passi incrementali.
