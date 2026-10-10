# Plug-in «Qwen 2.1 Inpainting» e `contribute.paint` — Piano di implementazione

> **Per chi esegue:** SOTTO-SKILL OBBLIGATORIA: `superpowers:subagent-driven-development` (consigliata) oppure `superpowers:executing-plans`. I passi usano la sintassi a caselle (`- [ ]`).

**Obiettivo:**
- l'app accetta `contribute.paint`, che diventa il livello Pennello di Control;
- un plug-in nuovo per Qwen Image 2.1 disegna segni colorati sull'immagine di partenza, raccoglie un testo per coppia colore + strumento e invia disegno e prompt, quest'ultimo diretto o riscritto dal PE I2I.

**Architettura:**
- **Parte A** (Task 1–2): HubKit, HubCore e App.
- **Parte B** (Task 3–8): pacchetto `Plugins/QwenInpainting`.
  - Logica pura e testata: dati, frasi, geometria, rasterizzazione, PE, stato.
  - Poi vista e collegamento.

**Tecnologie:** Swift 6.2, Swift Testing, SwiftUI, CoreGraphics, ImageIO.

**Spec:** `docs/superpowers/specs/2026-10-10-plugin-qwen-inpainting-design.md` (tabelle dei colori al §4.2 e delle frasi al §4.5).

## Vincoli globali

- **Ramo e pubblicazione:**
  - base `origin/main` 0.1.5 (`5c6bf54`), ramo nuovo (es. `plugin-qwen-inpainting`);
  - **niente unione, push o release senza via libera esplicito**;
  - file aggiunti **per nome**: mai `git add -A` né `git add docs`.
- **Test:**
  - app: `cd Packages && swift test --filter <Suite> 2>&1 | grep -E "Test run with|error:"`;
  - plug-in: `cd Plugins/QwenInpainting && swift test`.
- **Compilare l'app:** `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build`.
- **Regressioni:** i test esistenti restano verdi; gli altri plug-in compilano senza modifiche (`swift build` in ciascuno).
- **Nessun codice copiato da Pixaroma:** il comportamento viene dalla spec, il codice si scrive da zero.
- **Lingua:** commenti in inglese. Testi del plug-in nella tabella `L` (it/en); titoli delle card e frasi sempre in inglese.
- **Se «LLM Chat» è già unito**, `PluginContribution` e `ContributionStore` hanno anche `strength`: `paint` si aggiunge accanto, nello stesso stile.

## Review Focus

1. **Proporzioni:** un'immagine di partenza in verticale (es. 768×1344) produce `paint.png` 768×1344 e il livello in Control ha le stesse proporzioni, senza segni spostati (Task 2, 5).
2. **Orientamento EXIF:** una foto con orientamento EXIF diverso da 1 ha i segni dove li si è disegnati, sia nel `paint.png` sia nell'immagine fusa (Task 5).
3. **Cambio di progetto vs cambio d'immagine:** riaprendo un progetto la cui immagine è la stessa di prima, i segni **non** spariscono (Task 7).
4. **Pennellata fuori dall'immagine:** trascinare oltre il bordo del canvas dà punti limitati a 0…1, senza crash e senza punti negativi nel PNG (Task 3, 8).
5. **Invio ripetuto:** due Invia di fila sostituiscono il disegno (non lo sommano) e lasciano due passi di Annulla in Control (Task 2).

---

## Parte A — App

### Task 1: `contribute.paint` in HubKit e `ContributionStore`

**Files:** Modify `Packages/Sources/HubKit/Plugin/PluginContribution.swift`, `Packages/Sources/HubCore/Plugins/ContributionStore.swift`. Test: `Packages/Tests/HubKitTests/PluginContractTests.swift` (o un nuovo `PluginContributionPaintTests.swift`), `Packages/Tests/HubCoreTests/ContributionStoreTests.swift` (e il suo `FakeContributionTarget`).

**Interfaces — Produces:**
- `PluginContribution.paint: PluginImageRef?`, con `init(…, paint: PluginImageRef? = nil)`, incluso in `isEmpty`;
- `ContributionTarget.setPaint(_ image: PluginImageRef) throws`.

- [ ] **Step 1: Test che falliscono.**
  - **Lettura:**
    - `{"paint":{"path":"/tmp/x/paint.png"}}` → `paint?.path == "/tmp/x/paint.png"` e `paint?.name == "paint.png"`;
    - con `"name":"Qwen 2.1 Inpainting"` → nome tenuto;
    - `{"paint":"x"}` → nil;
    - solo `paint` → `isEmpty == false`.
  - **Store**, con `FakeContributionTarget` che registra `paintCalls` e può lanciare:
    - con immagine di partenza → `paintCalls.count == 1`, `problems` vuoto;
    - senza → nessuna chiamata, `problems == ["paint: there is no start image."]`;
    - target che lancia `ControlError.unreadable("paint.png")` → `problems` contiene `"paint.png:"`;
    - `startImage` e `paint` nello stesso messaggio → `setStartImage` prima di `setPaint`.
- [ ] **Step 2: Vedere il fallimento.**
- [ ] **Step 3: Implementare.** Lettura con `PluginImageRef(object["paint"])`; nello store, dopo il blocco di `startImage`, `if let image = contribution.paint { guard target.startImageID != nil … try target.setPaint(image) }`. Nessun marchio, nessun conflitto.
- [ ] **Step 4: Test verdi** (`--filter Contribution`, `--filter PluginContract`).
- [ ] **Step 5: Commit** — `feat(plugins): contribute.paint`.

### Task 2: Il PNG diventa il livello Pennello

**Files:** Modify `Packages/Sources/HubCore/Control/PaintBitmap.swift`, `App/Generation/GenerationController.swift`, `PluginKit/README.md`. Test: `Packages/Tests/HubCoreTests/PaintBitmapTests.swift`.

**Interfaces:**
- Consumes: `ContributionTarget.setPaint` (Task 1).
- Produces: `PaintBitmap.fitted(from image: CGImage, width: Int, height: Int) -> PaintBitmap?`, che ridisegna l'immagine stirata a `width × height` e torna ad alpha non premoltiplicato come `init?(image:)`. Il codice comune va in una funzione privata condivisa.

- [ ] **Step 1: Test che falliscono.**
  - Un `CGImage` 2048×1024 trasparente con un quadrato 64×64 rosso pieno nell'angolo in alto a sinistra → `fitted(…, width: 1024, height: 512)` ha:
    - `width == 1024`, `height == 512`;
    - in (4, 4) colore (255, 0, 0) e alpha 255;
    - in (600, 300) alpha 0.
  - Con `width` o `height` 0 → nil.
  - Attenzione all'asse y: in `PaintBitmap` la riga 0 è in alto, come in `init?(image:)`.
- [ ] **Step 2–4:** vedere il fallimento, implementare, test verdi (`--filter PaintBitmap`).
- [ ] **Step 5: App.** In `extension GenerationController: ContributionTarget`, `func setPaint(_ image: PluginImageRef) throws`:
  1. legge con `Self.read(image)` e decodifica in `CGImage` con `CGImageSourceCreateWithData`; se fallisce, `ControlError.unreadable(image.name)`;
  2. `guard let size = control.maskSize`, altrimenti ritorna senza fare nulla (lo store ha già controllato);
  3. `PaintBitmap.fitted(from:width:height:)` con `size`;
  4. `try control.commitPaint(bitmap)`.

  Poi `xcodebuild … build`.
- [ ] **Step 6: README del kit.** In `contribute`, dopo `startImage`, la voce `paint` (`{"path","name"}`, PNG con trasparenza nel `tempFolder`):
  - diventa il livello Pennello della card Canvas, sopra l'immagine di partenza;
  - sostituisce il disegno che c'era (Annulla di Control lo riporta);
  - è adattato alle proporzioni dell'immagine;
  - al RUN l'app lo unisce all'immagine;
  - serve un'immagine di partenza, altrimenti va in `problems`;
  - non si colora e non apre conflitti: vince l'ultimo plug-in che scrive.
- [ ] **Step 7: Suite e prova (Review Focus 5).**
  - `cd Packages && swift test`;
  - `swift build` negli altri plug-in.
  - Prova a mano: con l'esempio del kit (`Examples/Sample`) o con un JSON di prova, due `contribute.paint` di fila → il secondo disegno sostituisce il primo, e due Annulla in Control tornano a nessun disegno.
- [ ] **Step 8: Commit** — `feat(control): il disegno di un plug-in nel livello Pennello`.

---

## Parte B — Plug-in `Plugins/QwenInpainting`

Struttura dei sorgenti in `Sources/QwenInpainting/`:

| File | Contenuto |
| --- | --- |
| `QwenInpaintingPlugin.swift` | manifest, `handle`, entry |
| `Marks.swift` | `MarkTool`, `MarkColor` (con `rgb` e `swatch`), `Mark`, `CardKey` |
| `Cards.swift` | card, titoli, frasi, prompt composto |
| `MarkGeometry.swift` | percorsi |
| `Rasterizer.swift` | `paint.png` e `fused.png` |
| `PromptEnhancer.swift` | scelta del PE, system prompt, testo, ripiego |
| `InpaintingState.swift` | `ObservableObject`: stato, Annulla, salvataggio, invio |
| `InpaintingStore.swift` | `state.json` per progetto |
| `CanvasView.swift` | canvas e gesti |
| `InpaintingView.swift` | barra, card, riga di invio |
| `Strings.swift` | tabella `L` |

### Task 3: Pacchetto, dati, card e frasi

**Files:**
- Create: `Plugins/QwenInpainting/Package.swift`, `Scripts/build.sh`, `Sources/QwenInpainting/Marks.swift`, `Cards.swift`, `Strings.swift` (voci iniziali).
- Test: `Tests/QwenInpaintingTests/CardsTests.swift`, `MarksTests.swift`.

**Interfaces — Produces:**
- `MarkTool`, `MarkColor` (`CaseIterable` nell'ordine della spec §4.2), `MarkColor.rgb: (UInt8, UInt8, UInt8)`;
- `Mark(tool:color:width:points:)`, con `Mark.clamped() -> Mark` che limita i punti a 0…1 e la larghezza a 4…128;
- `CardKey(color:tool:)`, con `rawValue` `"red:box"` e `init?(rawValue:)`;
- `Cards.keys(of marks: [Mark]) -> [CardKey]` (ordine del primo segno), `Cards.count(of key: CardKey, in marks: [Mark]) -> Int`;
- `Cards.title(_ key: CardKey, count: Int) -> String`, `Cards.sentence(_ key: CardKey, count: Int, text: String) -> String?`;
- `Cards.prompt(marks: [Mark], texts: [String: String]) -> String` (testi indicizzati per `CardKey.rawValue`);
- `Cards.removeLine = "Remove all the colored marks and keep everything else the same."`.

- [ ] **Step 1:** `Package.swift` e `build.sh` come Batch plus (id `com.exiztenz.dthub.qweninpainting`, nome `QwenInpainting`, entry `QwenInpaintingEntry`, alias `QwenInpaintingKit`/`QwenInpaintingDesign`).
- [ ] **Step 2: Test che falliscono.**
  - **`keys`:**
    - box verde + sketch verde → `[green:box, green:sketch]`;
    - due box verdi → `[green:box]`;
    - box verde + box rosso → `[green:box, red:box]`;
    - sketch rosso, box verde, sketch rosso → `[red:sketch, green:box]`.
  - **Titoli:**
    - `(red, box, 1)` → `"INSIDE red box"`, `(red, box, 2)` → `"INSIDE red boxes"`;
    - `(blue, circle, 2)` → `"INSIDE blue circles"`, `(green, sketch, 2)` → `"INSIDE green sketches"`;
    - `(green, arrow, 1)` → `"WHERE green arrow points"`, `(green, arrow, 3)` → `"WHERE green arrows point"`.
  - **Frasi:**
    - `(red, box, 2, "make them blue")` → `"Inside the red boxes: make them blue."`;
    - `(green, arrow, 1, "  add a cat\n here ")` → `"Where the green arrow points: add a cat here."`;
    - testo che finisce con `!` → nessun punto aggiunto;
    - testo vuoto o di soli spazi → nil.
  - **Prompt:**
    - due card con testo → le due frasi nell'ordine delle card, uno spazio, poi `removeLine`;
    - nessun testo → `""`;
    - un testo di una coppia senza segni → ignorato.
  - **`Mark.clamped`:** punto (−0.2, 1.5) → (0, 1); larghezza 200 → 128.
  - **Colori:** 9 casi nell'ordine della spec; `purple.rgb == (128, 0, 255)`.
- [ ] **Step 3–4:** implementare, test verdi.
- [ ] **Step 5: Commit** — `feat(qwen-inpainting): pacchetto, segni, card e frasi`.

### Task 4: Geometria

**Files:** Create `Sources/QwenInpainting/MarkGeometry.swift`. Test: `MarkGeometryTests.swift`.

**Interfaces — Produces:** `MarkGeometry.paths(for mark: Mark, in size: CGSize, imageWidth: Double) -> (stroke: CGPath, fill: CGPath?, lineWidth: CGFloat)`, con `lineWidth = mark.width × size.width / imageWidth`.

- [ ] **Step 1: Test che falliscono.**
  - **box** da (0.1, 0.1) a (0.6, 0.6) in 100×100 → `stroke.boundingBoxOfPath == CGRect(10, 10, 50, 50)`; angoli invertiti (trascinamento verso l'alto a sinistra) → stesso rettangolo.
  - **circle** → `boundingBoxOfPath` uguale al rettangolo.
  - **arrow** da (0, 0.5) a (1, 0.5) in 100×100, `width 10`, `imageWidth 100`:
    - la punta (`fill`) ha `boundingBoxOfPath.maxX == 100`;
    - lunghezza della punta = `max(10 × 4, 12) = 40` ≤ 2/3 × 100;
    - l'asta finisce alla base della punta.
  - **Freccia corta** lunga 15 → punta lunga ≤ 10.
  - **sketch:**
    - un punto → percorso non vuoto (tondino di diametro `lineWidth`);
    - tre punti → passa per il primo e l'ultimo.
  - **Scala:** `lineWidth` con `size.width 500` e `imageWidth 1000` = metà di `width`.
- [ ] **Step 2–4:** implementare (quadratiche per i punti medi come da spec §4.3; semiapertura della punta 25°), test verdi.
- [ ] **Step 5: Commit** — `feat(qwen-inpainting): geometria dei segni`.

### Task 5: Rasterizzazione

**Files:** Create `Sources/QwenInpainting/Rasterizer.swift`. Test: `RasterizerTests.swift`.

**Interfaces:**
- Consumes: `MarkGeometry.paths` (Task 4).
- Produces:
  - `Rasterizer.imageSize(at path: String) -> CGSize?`, la dimensione **orientata**;
  - `Rasterizer.orientedImage(at path: String, maxSide: Int?) -> CGImage?`;
  - `Rasterizer.paint(_ marks: [Mark], size: CGSize) -> CGImage?`;
  - `Rasterizer.fused(start: CGImage, paint: CGImage, maxSide: Int) -> CGImage?`;
  - `Rasterizer.writePNG(_ image: CGImage, to url: URL) throws`.

- [ ] **Step 1: Test che falliscono.**
  - **`paint`:** box rosso da (0.25, 0.25) a (0.75, 0.75), `width 4`, `size 200×100` → in (50, 50) il pixel è (255, 0, 0, 255) (bordo sinistro, a metà altezza); in (100, 50) alpha 0 (centro); in (2, 2) alpha 0. Letto con un `CGContext` RGBA, riga 0 in alto.
  - **Orientamento (Review Focus 2):** un JPEG 100×50 scritto con orientamento EXIF 6 (ruotato) →
    - `imageSize == 50×100`;
    - `orientedImage` è 50×100.
    - Usare `CGImageSourceCreateThumbnailAtIndex` con `kCGImageSourceCreateThumbnailWithTransform` e `kCGImageSourceThumbnailMaxPixelSize` = lato lungo, o `maxSide`.
  - **Verticale (Review Focus 1):** `paint(_, size: 768×1344)` dà 768×1344.
  - **Fusa:** start bianco 3000×1500 + paint con box rosso → lato lungo 1536 e il pixel del bordo rosso.
  - **Punti fuori limite (Review Focus 4):** un segno con punti già limitati a 0/1 si disegna senza errori.
- [ ] **Step 2–4:** implementare (`CGContext` RGBA premoltiplicato, antialias acceso, `setStrokeColor` dal colore del segno, `addPath`/`strokePath` e `fillPath` per la punta; y del contesto invertita per avere le coordinate dall'alto), test verdi.
- [ ] **Step 5: Commit** — `feat(qwen-inpainting): disegno in PNG e immagine fusa`.

### Task 6: PE I2I

**Files:** Create `Sources/QwenInpainting/PromptEnhancer.swift`. Test: `PromptEnhancerTests.swift`.

**Interfaces — Produces:**
- `PromptEnhancer.model(in models: [DTHubLanguageModel]) -> DTHubLanguageModel?`;
- `PromptEnhancer.systemPrompt(for model: DTHubLanguageModel) -> String`;
- `PromptEnhancer.request(composed: String) -> String`;
- `PromptEnhancer.cleaned(_ answer: String) -> String?`;
- `PromptEnhancer.builtInSystem` (testo esatto della spec §4.6).

- [ ] **Step 1: Test che falliscono.**
  - **`model`:**
    - fra `b-pe (qwen_image_2.1, i2i, visione)`, `a-pe (qwen_image_2.1, i2i, visione)`, `c (qwen_image_2.1, t2i, visione)`, `d (*, i2i, visione)`, `e (qwen_image_2.1, i2i, senza visione)` → `a-pe`;
    - lista senza candidati → nil.
  - **`systemPrompt`** con una cartella temporanea:
    - con `system_prompt_i2i.txt` e `system_prompt.txt` → il primo;
    - con solo `system_prompt.txt` → quello;
    - con nessuno → `builtInSystem`.
  - **`request("X")`** → `"X\n\nKeep every reference to the colored marks and the instruction to remove them."`.
  - **`cleaned`:**
    - `"  \"Inside…\"  "` → `"Inside…"`;
    - `"   "` → nil.
- [ ] **Step 2–4:** implementare, test verdi.
- [ ] **Step 5: Commit** — `feat(qwen-inpainting): PE I2I`.

### Task 7: Stato, archivio, invio

**Files:** Create `Sources/QwenInpainting/InpaintingStore.swift`, `InpaintingState.swift`, `QwenInpaintingPlugin.swift`; completare `Strings.swift`. Test: `InpaintingStoreTests.swift`, `InpaintingStateTests.swift`, `StringsTests.swift`.

**Interfaces:**
- Consumes: Task 3–6.
- Produces:
  - `InpaintingSession: Codable` con `startImage: String?`, `marks: [Mark]`, `texts: [String: String]`, `tool: MarkTool = .box`, `color: MarkColor = .red`, `width: Double = 16`, `usePE: Bool = true`. Lettura tollerante; i segni illeggibili si saltano (decodifica per voce con `try?`).
  - `InpaintingStore(folder: URL?)` con `load() -> InpaintingSession?` e `save(_:)`; con `folder == nil` lavora in memoria.
  - `InpaintingState: ObservableObject`:
    - pubblicati: `session`, `context: DTHubContext?`, `active`, `status`, `statusIsError`, `isSending`;
    - metodi:
      - `apply(context:)`, `switchProject(folder:)`;
      - `add(_ mark: Mark)`, `undo()`, `redo()`, `clearAll()`;
      - `setText(_:for:)`;
      - `send(ask: Ask, contribute: Contribute) async`, dove `Ask = (String, [String], String, String) async -> DTHubLLMAnswer` (testo, immagini, system, modello) e `Contribute = ([String: Any]) async -> [String: Any]?`;
    - calcolate: `canUndo`, `canRedo`, `cards: [(key: CardKey, count: Int)]`, `composedPrompt`, `enhancer: DTHubLanguageModel?`, `canSend`.

- [ ] **Step 1: Test che falliscono.**
  - **Archivio:**
    - salva e ricarica uguale;
    - un segno con `tool` sconosciuto si salta, gli altri restano;
    - due cartelle separate;
    - file illeggibile → nil.
  - **Annulla:**
    - `add` × 3, `undo` × 2 → 1 segno;
    - `redo` → 2;
    - un `add` dopo `undo` svuota Ripeti;
    - 120 `add` → al massimo 100 `undo`;
    - `clearAll` si annulla con un `undo`.
  - **Cambio d'immagine:**
    - `apply(context:)` con `startImage` diverso da `session.startImage` → `marks` vuoti, `canUndo == false`, `texts` invariati, `session.startImage` aggiornato;
    - con lo stesso percorso → segni intatti;
    - con `startImage` assente dopo uno presente → segni svuotati.
  - **Progetto (Review Focus 3):** `switchProject` su una cartella con `startImage "/a.png"` e 2 segni, poi `apply(context:)` con `startImage "/a.png"` → i 2 segni restano.
  - **Testi:** `setText("x", for: red:box)` resta in `session.texts` dopo un `undo` che toglie l'ultimo box rosso; ricompare con un nuovo box rosso.
  - **Invio senza PE:**
    - con `contribute` finto: il corpo ha `paint.path` che esiste su disco (PNG delle dimensioni dell'immagine di partenza di prova) e `fields.prompt == composedPrompt`;
    - senza testi il corpo **non** ha `fields`.
  - **Invio con PE** (contesto con un modello `qwen_image_2.1`/`i2i`/visione, `usePE` acceso):
    - `ask` riceve `request(composed:)`, un'immagine (`fused.png` esistente), il system prompt e il nome del modello;
    - risposta `"Better."` → `fields.prompt == "Better."`;
    - risposta `failure("no memory")` → `fields.prompt == composedPrompt` e `status` contiene `"no memory"`;
    - con `usePE` spento → `ask` non chiamato.
  - **Esiti:**
    - `{"type":"ok","conflicts":1}` → stato «Inviato. 1 conflitti…» / «Sent. 1 conflict(s)…»;
    - `{"type":"error","text":"x"}` → `statusIsError` e `"x"`;
    - `nil` → «Nessuna risposta dall'app».
  - **`canSend`:**
    - falso senza immagine, senza segni, con `active == false` o durante `isSending`;
    - vero altrimenti.
  - **Testi:** `L` completa in it e en.
- [ ] **Step 2–4:** implementare, test verdi.
  - L'immagine di partenza di prova nei test è un PNG scritto in una cartella temporanea.
  - `QwenInpaintingPlugin.handle`:
    - `context` → `apply`;
    - `project` → `switchProject`;
    - `activate`/`deactivate` → `active`;
    - altro → `unsupported`.
  - Il plug-in passa a `send`:
    - `{ host.askLanguageModelAnswer($0, images: $1, system: $2, model: $3, options: DTHubLLMOptions(maxTokens: 2048, timeout: 600)) }`;
    - `host.contribute`.
- [ ] **Step 5: Commit** — `feat(qwen-inpainting): stato per progetto, Annulla e invio`.

### Task 8: Vista, README, elenco dei plug-in

**Files:**
- Create: `Sources/QwenInpainting/CanvasView.swift`, `InpaintingView.swift`, `Plugins/QwenInpainting/README.md`.
- Modify: `Plugins/README.md` (tabella, link di download `QwenInpainting.dthubplugin.zip`, conteggio dei plug-in), `README.md` alla radice se elenca i plug-in.

- [ ] **Step 1: `CanvasView`.**
  - **Immagine:** quella di partenza (`Rasterizer.orientedImage(at:maxSide: 2048)`, ricaricata quando cambia il percorso), adattata con proporzioni conservate.
  - **Segni:** disegnati in un `Canvas` SwiftUI con `MarkGeometry.paths` nella dimensione mostrata.
  - **Gesto:** un `DragGesture(minimumDistance: 0)` che converte le coordinate in frazioni dell'immagine, limitate a 0…1 (**Review Focus 4**):
    - per il pennello aggiunge i punti più lontani di 1 px dal precedente, al massimo 4 000;
    - per gli altri strumenti tiene inizio e fine;
    - mostra il segno in corso;
    - alla fine `state.add(mark)`, se lo spostamento totale è ≥ 3 px.
  - **Senza immagine:** il testo della spec §4.4.
- [ ] **Step 2: `InpaintingView`.**
  - Barra come la spec §4.4: pulsanti degli strumenti come `toolButton` di `CanvasStage`, 9 tondini con anello, cestino con `confirmationDialog`, Annulla/Ripeti, riga Spessore con slider 4…128.
  - Card con tondino, titolo e `TextField(axis: .vertical)` con `lineLimit(2...6)`.
  - Riga di invio con anteprima, casella PE, Invia e stato.
  - Avviso col plug-in spento. Componenti di `DTHubDesign`.
- [ ] **Step 3: Build.** `swift build`; `Scripts/build.sh /tmp/out` produce `QwenInpainting.dthubplugin`.
- [ ] **Step 4: README del plug-in** (inglese, come Batch plus):
  - cosa fa;
  - gli strumenti e i 9 colori;
  - le card per colore + strumento, con titoli e frasi;
  - l'invio (livello Pennello, Prompt; PE I2I se assegnato a «Qwen Image 2.1 · I2I»);
  - i segni che spariscono col cambio d'immagine;
  - lo stato per progetto;
  - i requisiti: DT Hub 0.1.6 o successiva, solo Qwen Image 2.1.
  - Ispirazione dichiarata: «inspired by the Sketch node of ComfyUI-Pixaroma», senza codice di quel progetto.
  - Il testo non dice che DT Hub «sostituisce» l'interfaccia di Draw Things.
- [ ] **Step 5: Elenco** — riga nella tabella di `Plugins/README.md`:
  - Works with: «**Qwen Image 2.1** only»;
  - What it does: «Draw boxes, circles, arrows and sketches in nine colours on the start image and write what to change for each colour and tool; it sends the drawing to the Brush layer and writes the prompt, directly or through Qwen's PE I2I.»;
  - più il link di download e il conteggio dei plug-in.
- [ ] **Step 6: Suite completa.**
  - `cd Packages && swift test`;
  - `swift test` in `Plugins/QwenInpainting`;
  - `swift build` negli altri plug-in;
  - `xcodebuild … build`.
- [ ] **Step 7: Prove a mano** (lista all'utente): spec §7, più i Review Focus 1–5.
- [ ] **Step 8: Commit** — `feat(qwen-inpainting): vista, README e elenco dei plug-in`.
- [ ] **Step 9: Messaggio finale** (briefing §6):
  - cosa provare;
  - **«Decisioni che ho preso»**, ognuna col suo costo se sbagliata:
    - nome e simbolo;
    - viola 128,0,255;
    - il disegno sostituisce quello in Control;
    - il livello al massimo a 1024 px;
    - la riga aggiunta al PE;
    - nessun avviso con un'app vecchia;
    - le scelte d'interfaccia prese durante la scrittura;
  - **«Rinviati»** (spec §8);
  - via libera prima di unire, push o release. La release deve includere `QwenInpainting.dthubplugin.zip` e alzare la versione dell'app, perché il plug-in richiede «0.1.6 o successiva».

---

## Autorevisione

- **Copertura:**
  - spec §3 → Task 1–2;
  - §4.1 → Task 3;
  - §4.2 → Task 3;
  - §4.3 → Task 4;
  - §4.4 → Task 8;
  - §4.5 → Task 3;
  - §4.6 → Task 6–7;
  - §4.7 → Task 5, 7;
  - §4.8 → Task 7;
  - §4.9 → Task 7;
  - §5 → Task 1–7;
  - §6 → Task 8 (README);
  - §7 → Task 8.
- **Tipi:**
  - `Mark`/`CardKey` (Task 3) → Task 4–8;
  - `MarkGeometry.paths` (Task 4) → `Rasterizer` (Task 5) e `CanvasView` (Task 8);
  - `PromptEnhancer` (Task 6) → `InpaintingState.send` (Task 7);
  - `ContributionTarget.setPaint` (Task 1) → `GenerationController` (Task 2).
- **Ordine:** la Parte A può essere unita da sola. Il plug-in funziona solo con un'app che ha la Parte A.
