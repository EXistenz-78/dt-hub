# Redesign della tab Control: design

Data: 2026-11-07. Stato: bozza per revisione.

## Obiettivo

Semplificare la tab Control. L'immagine di partenza si carica e si gestisce direttamente sul Canvas, e il Canvas e il
Moodboard diventano due card a tutta larghezza, una sotto l'altra. Non cambia nessuna logica di inquadratura, disegno,
importazione, Forza o Genera Prompt: cambia dove stanno e come si dispongono.

## Decisioni già prese con l'utente

- La card **Immagine** viene eliminata. Le sue funzioni passano alla card **Canvas**.
- La **lavagna** (l'area scura in modalità Canvas, con l'immagine e i margini) è la zona dove trascinare l'immagine.
  Trascinare una nuova immagine **sostituisce** la precedente: il pulsante **Sostituisci…** sparisce.
- I **badge** stanno sugli angoli della lavagna: **X** per rimuovere in alto a destra, **numero** in basso a destra.
- Sotto Zoom e Rotazione: **Forza**, **Adatta le dimensioni** e **Genera Prompt**.
- **Canvas** e **Moodboard** diventano a tutta larghezza della finestra, Canvas sopra e Moodboard sotto.
- Con il Canvas **staccato** in una finestra a parte, Forza e i due pulsanti **restano nella tab**, in una card sottile
  sotto la nota "Canvas staccato".
- Nome file, dimensioni e origine dell'immagine vanno **nella riga di informazioni sotto il Canvas**.

## Architettura

- **Elimino** `App/Control/ImageCard.swift`. Ciò che serve ancora si sposta in file nuovi o esistenti.
- **Nuovo** `App/Control/StartImageControls.swift`: il blocco Forza (con le sue note e "Automatica"), i pulsanti
  **Adatta le dimensioni** e **Genera Prompt** (con indicatore di lavoro, Annulla e riga di errore). Contiene anche
  l'enum `ControlMessage`, oggi in `ImageCard.swift`. Si usa in due posti: dentro la card Canvas e nella card sottile
  del Canvas staccato. Dipende da `generation`, `connection` e dal callback `report`, come `ImageCard`.
- **Modifico** `App/Control/CanvasStage.swift`:
  - la lavagna riceve il rilascio di file (`dropDestination(for: URL.self)`, `ControlImport.take(urls:into:)`) con il
    bordo azzurro durante il trascinamento. Il rilascio vale anche in modalità Disegno, sull'intero corpo della card;
  - sulla lavagna, in overlay: la X (`control.removeImage()`) in alto a destra e `ImageNumberBadge` in basso a destra,
    quest'ultimo solo se `FamilyTraits.of(generation.family(in:)).usesMoodboard` e `control.startImageNumber != nil`,
    come oggi;
  - lo stato vuoto (`empty`) diventa la zona di rilascio tratteggiata con il testo "Trascina qui un'immagine" e il
    pulsante **Scegli…** (`ControlImport.choose(into:)`);
  - `StartImageControls` va dopo `rotationRow` e prima di `caption`;
  - la riga `caption(for:)` comincia con nome file, dimensioni e origine (`ControlText.source(...)`), poi le righe
    che ha già.
  - L'evidenziazione `contributed(...)` delle immagini fornite da un plug-in passa dalla vecchia anteprima alla lavagna.
- **Modifico** `App/Control/ControlTabView.swift`: niente `DSCardRow` a due colonne; un `VStack` con il Canvas (o, se
  staccato, `CanvasDetachedNote` più la card sottile con `StartImageControls`) e sotto `MoodboardCard`, entrambe a
  larghezza piena.
- **Modifico** `App/Control/CanvasWindow.swift` solo se serve per la card sottile del Canvas staccato.
- La chiave dello stato aperto/chiuso `control.image` non serve più.

## Cosa si perde

La miniatura dell'immagine, da cui si poteva trascinare la copia verso il Moodboard o un'altra app (`DragOut`). Sulla
lavagna il trascinamento muove l'inquadratura, quindi quel gesto non esiste più. L'anteprima da 240 px (`thumbnail`)
non serve.

## Errori e casi limite

- Un file non importabile mostra lo stesso errore di oggi nella barra dei messaggi (`ControlMessage.error`).
- Rilasciare più file: vale il comportamento già implementato da `ControlImport.take`.
- Canvas staccato: nella tab la lavagna non c'è, quindi non c'è un punto dove rilasciare un'immagine; resta il
  pulsante **Scegli…** nella card sottile (mostrato quando non c'è un'immagine) e il rilascio nella finestra staccata.
- Senza immagine: Forza e **Adatta le dimensioni** non hanno senso e non compaiono; compaiono dopo il caricamento.
- Schermi larghi: la lavagna mantiene il rapporto del canvas e un'altezza massima; con la card a tutta larghezza può
  restare più stretta della card e centrata.

## Localizzazione

Chiavi esistenti riusate: `control.image.adapt`, `.adapt.help`, `.describe`, `.describe.help`, `.remove`,
`control.strength*`, `control.image.drop`, `control.image.choose`, `control.image.info`. Da togliere perché non più
usate: `control.image.replace`, `control.image.title`. Se serve una nuova chiave (la riga di informazioni con il nome
file), si aggiunge in italiano e inglese in `Localizable.xcstrings`.

## Test

Quasi tutto è vista. La logica che non cambia (importazione, Forza, Adatta, inquadratura, Genera Prompt) ha già i suoi
test. Il `CatalogTests` controlla che ogni chiave sia tradotta. La verifica è la build e la prova a vista con l'utente:
lavagna con e senza immagine, trascinamento di una seconda immagine, badge, Forza e pulsanti, Canvas staccato, finestra
larga e stretta.

## Fuori ambito

Il contenuto del Moodboard, la modalità Disegno e i suoi strumenti, la finestra staccata del Canvas (a parte la card
dei controlli nella tab), qualunque altra tab.
