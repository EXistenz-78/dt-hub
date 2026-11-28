# Algoritmo di ingrandimento dell'immagine di partenza e tasto 1:1 (card Canvas)

Data: 28 novembre 2026. Stato: bozza da approvare.

## Perché

Un confronto su SeedVR2 7B (cartella `SeedVR2/` del repo, non in git) ha mostrato che la trama della pelle e dei capelli
dipende quasi tutta da come DT Hub porta l'immagine di partenza alla dimensione del canvas, non dai pesi (q8p o i8x):

- oggi `InputComposer.frame` ridimensiona sempre con Core Graphics (`interpolationQuality = .high`); l'output dell'app è
  riprodotto quasi al pixel dal CLI con lo stesso input (scarto medio 0,47);
- con un ingrandimento bicubico morbido (Catmull-Rom, come fa SeedVR2-MLX) la trama torna come quella di MLX; con B-spline
  la pelle è sembrata all'utente la più realistica, ma su una sola prova.

Non c'è un algoritmo migliore sempre: l'utente vuole sceglierlo volta per volta guardando il risultato, e fissare per ogni
famiglia di modelli quello che preferisce.

## Obiettivi

1. Nella card Canvas (tab Control) un **menu dell'algoritmo di ricampionamento**, visibile solo quando l'immagine non è
   1:1 rispetto al canvas.
2. Un **tasto 1:1** (`1.magnifyingglass`) che porta l'immagine alla sua dimensione reale nel canvas.
3. Un valore **Automatico** che dipende dalla famiglia del modello: di fabbrica Catmull-Rom per SeedVR2 (3B e 7B), Core
   Graphics per tutte le altre (nessun risultato esistente cambia).
4. Un'**icona accanto al menu** che salva l'algoritmo scelto come predefinito della famiglia del modello selezionato, nello
   stesso file dei default dell'utente (`recommended-overrides.json`), non in un file a parte.
5. L'algoritmo è un **parametro di Generazione**: i preset lo salvano; un preset vecchio senza il campo lascia
   l'automatico del modello; finisce nei metadati di ogni risultato e «riprendi parametri» lo ripristina.

## Non obiettivi

- «Salva come default» della tab Generazione **non** salva l'algoritmo (scelta dell'utente: sta in un'altra tab e
  cambierebbe il predefinito senza che ce ne si accorga). Il file dei default resta lo stesso, ma la sezione è separata.
- Non cambia come vengono ridimensionate maschere, disegni del Pennello, immagini della Moodboard, ControlNet.
- Il valore non va al server Draw Things: è solo di DT Hub (il server riceve l'immagine già ridimensionata).
- Nessuna scelta automatica «intelligente» per immagine.

## Anti-obiettivi

- Cambiare in silenzio i risultati degli altri modelli: l'automatico resta Core Graphics fuori da SeedVR2.
- Un preset vecchio che non si carica o che impone un algoritmo: il campo mancante vale «Automatico».

## Approcci considerati

1. **L'algoritmo è un campo dei parametri di Generazione** (in `AdvancedParameters`, accanto a `colorCalibration`).
   I preset lo salvano senza codice in più, finisce nei metadati `dthub` dei risultati, `recall_from_result` e
   `set_advanced` lo coprono. Il menu sta nella card Canvas ma scrive nei parametri. **Scelto dall'utente.**
2. **L'algoritmo è un input di Control** (accanto a `marginFill` in `ControlInputs`). Più coerente con dove sta il menu,
   ma i preset dovrebbero scrivere su Control (oggi non lo fanno mai) e servirebbe un campo a parte nei metadati. Scartato.

## Il modello dei dati

`HubKit`:

```swift
/// Come l'immagine di partenza viene portata alla dimensione del canvas.
public enum Resampling: String, Codable, Sendable, CaseIterable {
  case coreGraphics   // Core Graphics .high: quello di oggi, il più nitido
  case catmullRom     // bicubico B=0 C=0,5 (= bicubico di PIL, quello di SeedVR2-MLX)
  case mitchell       // bicubico B=C=1/3
  case bSpline        // bicubico B=1 C=0, il più morbido
  case bilinear
  case lanczos
  case nearest
}
```

`AdvancedParameters.resampling: Resampling?` — `nil` = Automatico. Decodifica tollerante: campo mancante o valore
sconosciuto → `nil`. Non entra in `ConfigurationCodec.modeledKeys` né nella configurazione Draw Things (`JobMapper`).

Valore effettivo: `parametri.advanced.resampling ?? ResamplingDefaults.value(forFamily:)`, dove i default sono, in ordine:
quello salvato dall'utente per la famiglia, poi quello di fabbrica (codice: `seedvr2_3b`, `seedvr2_7b` → `catmullRom`;
tutto il resto → `coreGraphics`), poi `coreGraphics` se la famiglia non è nota.

## Il file dei default

`recommended-overrides.json` riceve una sezione nuova accanto a `models` e `families`:

```json
{
  "models": { ... },
  "families": { ... },
  "resampling": { "seedvr2_7b": "bSpline" }
}
```

- `RecommendedSettings` la legge e la riscrive (`encoded()`), senza toccarne il formato attuale; un valore sconosciuto
  si salta. Un file senza la sezione è valido (vuota).
- Le versioni vecchie dell'app ignorano la chiave; ma una versione vecchia che risalva il file la perde (accettato).
- `ModelDefaults` espone `resampling(forFamily:)`, `saveResampling(_:forFamily:)`, `resetResampling(forFamily:)`.
- `RecommendedSettings.json` del bundle non cambia (lo genera `Scripts/make-recommended-settings.py`): il valore di
  fabbrica per SeedVR2 sta nel codice.

## Il rendering

`InputComposer.frame` riceve `resampling: Resampling` (default `.coreGraphics`, così chi non lo passa non cambia):

- `.coreGraphics`: il codice di oggi.
- bicubici: Core Image `CIBicubicScaleTransform` con B e C indicati sopra; `.lanczos`: `CILanczosScaleTransform`;
  `.bilinear` e `.nearest`: Core Image con il campionamento corrispondente. Verificato: `CIBicubicScaleTransform`
  B=0 C=0,5 coincide con il bicubico di PIL (scarto medio 0,16 su 255).
- La scala, il ritaglio, la rotazione, i margini (`edges`/`gray`/`green`) e il disegno del Pennello restano quelli di
  oggi: cambia solo il filtro che porta l'immagine alla scala. Con i metodi Core Image l'immagine si ridimensiona prima
  alla scala del canvas e poi si disegna come oggi (posizione, rotazione, bordi estesi).
- Riduzione: quando l'algoritmo non è Core Graphics, `framedStartImageRender` e `generationInputs` (ControlStore) leggono
  il file a piena dimensione invece del `maxPixel` ridotto, altrimenti la riduzione la farebbe ImageIO e non l'algoritmo.

Chi passa l'algoritmo: `ControlStore.generationInputs` (RUN), `framedStartImage`/`framedStartImageRender` (plug-in che
disegnano sull'immagine incorniciata) e la chiave `framedStartImageKey` (deve includere l'algoritmo). Non lo passa
`PipelineInputs` dei plug-in: resta Core Graphics.

## La card Canvas

```
 ┌──────────────────────────────────────────────┐
 │                 canvas …                     │
 │ [1:1]                                    (1) │   ← 1.magnifyingglass, angolo in basso a sinistra
 └──────────────────────────────────────────────┘
 Zoom      ───────●────────────────  -50  ↺
 Rotazione ───────────●────────────   0°  ↺
 [⤓] [Ingrandimento: Automatico (Catmull-Rom) ▾]   [Automatico (Bordi estesi + maschera) ▾]
 Forza     ──────────────────────●──  100
```

- **Tasto 1:1.** Imposta lo zoom per cui un pixel dell'immagine è un pixel del canvas (`zoom = 100·log4(larghezza della
  finestra di riempimento / larghezza del canvas)`, entro −100…+100), lasciando spostamento e rotazione. Spento quando è
  già 1:1 o quando il valore uscirebbe dal range dello zoom. Aiuto: «Dimensione reale (1:1)».
- **1:1 vuol dire** che la finestra di ritaglio è larga quanto il canvas entro mezzo pixel, e senza rotazione (una
  rotazione ricampiona comunque).
- **Riga dei menu.** Oggi la riga «Riempimento margini» ha la parte sinistra vuota. A sinistra va il menu dell'algoritmo
  con l'icona, quando l'immagine non è 1:1; a destra resta il menu dei margini, quando ci sono margini. Se serve solo
  uno dei due, la riga mostra solo quello; se nessuno, la riga non c'è. Ogni menu porta il suo nome nel titolo
  («Ingrandimento: …», il menu dei margini come oggi) e nell'aiuto.
- **Voci del menu:** «Automatico (X)» con X l'algoritmo effettivo per la famiglia, poi i sette metodi con un nome breve
  (Core Graphics, Catmull-Rom, Mitchell, B-spline, Bilineare, Lanczos, Nearest). Se la famiglia ha un default salvato
  dall'utente, in fondo: «Torna al predefinito di fabbrica per <famiglia>».
- **Icona salva** (`square.and.arrow.down`, a sinistra del menu): salva l'algoritmo selezionato come predefinito della
  famiglia del modello nell'header. Spenta con «Automatico» selezionato, senza modello, o quando l'algoritmo è già quello
  predefinito della famiglia. Aiuto: «Usa <algoritmo> come predefinito per <famiglia>». Dopo il salvataggio una riga
  di conferma come quella di «Salva come default».
- Il menu scrive `parameters.advanced.resampling`; cambiare modello non lo tocca (un valore esplicito resta esplicito).

## Preset, metadati, MCP

- I preset salvano `parameters`, quindi l'algoritmo esplicito; con «Automatico» il campo manca. Un preset vecchio si
  carica come oggi e l'algoritmo resta Automatico.
- I metadati `dthub` dei risultati contengono i parametri, quindi l'algoritmo; `recall_from_result` lo ripristina.
- MCP: `set_advanced` accetta `resampling` (uno dei sette nomi o `"automatic"`), `get_advanced` lo mostra; testo
  degli strumenti aggiornato.

## Test

- `Resampling` e `AdvancedParameters`: decodifica tollerante (mancante, sconosciuto → nil), andata e ritorno.
- Default per famiglia: utente > fabbrica > Core Graphics; SeedVR2 → Catmull-Rom; altre famiglie → Core Graphics.
- `RecommendedSettings`: legge e riscrive la sezione `resampling`; file vecchio senza sezione; voce sconosciuta saltata.
- `InputComposer.frame`: con `.coreGraphics` identico a oggi; con `.catmullRom` vicino al bicubico di riferimento su
  un'immagine di prova; margini e rotazione invariati.
- Preset vecchio senza campo → Automatico.
- Calcolo dello zoom 1:1 e del riconoscimento 1:1 (con e senza rotazione, immagini orizzontali e verticali).

## Lasciato a chi costruisce

- Nomi delle stringhe localizzate (italiano e inglese) e testi d'aiuto esatti.
- Come implementare bilineare e nearest in Core Image (filtri o campionatore), purché il risultato sia quello del nome.
- Dettagli di layout della riga (spaziature), restando nello stile delle altre righe della card.

## Scelte mie (da controllare)

- Sette metodi; tolto «Core Image predefinito» del test perché quasi uguale a Catmull-Rom.
- Icona salva `square.and.arrow.down`; ripristino del predefinito di fabbrica come voce in fondo al menu.
- Una rotazione diversa da 0 conta come «non 1:1» e mostra il menu.
- I plug-in che costruiscono la propria immagine (`PipelineInputs`) restano su Core Graphics.
- Riduzione con l'algoritmo scelto: si legge l'immagine a piena dimensione.
