# Depth & Pose — posa a figura intera — Piano di implementazione

> **Per chi esegue:** SOTTO-SKILL OBBLIGATORIA: `superpowers:subagent-driven-development` (consigliata) oppure `superpowers:executing-plans`. I passi usano la sintassi a caselle (`- [ ]`).

**Obiettivo:** far disegnare al plug-in Depth & Pose lo scheletro DWPose completo (corpo, viso, mani) con un modello DWPose-L convertito in Core ML, tenendo Vision come ripiego quando il modello non c'è.

**Architettura:** sei pezzi nuovi, ognuno con un compito: `DPFigure` (una persona con corpo, viso e mani), `DPSimCC` (decodifica pura), `DPCrop` (ritaglio affine 288×384, puro), `DPWholeBody` (da 133 punti COCO-WholeBody a una figura OpenPose), `DWPoseDetector` con la rete e il cercatore di riquadri dietro protocolli (`DPPoseNetwork`, `DPPersonBoxFinding`) e il disegno di viso e mani in `DPPoseRenderer`. `DPModelStore` impara un indirizzo base per modello e `DPState` gestisce due modelli indipendenti (depth e posa). Il modello della depth e tutto il resto non cambiano.

**Tecnologie:** Swift 6.2, Swift Testing, Core ML, Vision, CoreGraphics; per lo script Python: torch 2.7, onnx2torch, coremltools 9.

**Spec:** `docs/superpowers/specs/2026-10-16-depth-pose-posa-completa-design.md` (chi esegue legge anche quella; la spec madre è `…/2026-10-16-plugin-depth-pose-design.md`).

## Vincoli globali

- Si lavora sul ramo `depth-pose` (locale). **Niente unione, push o release senza via libera esplicito**; pubblicare la release `dwpose-l-coreml` è una pubblicazione e va chiesta (Task 10). File aggiunti a git **per nome**.
- Modello per struttura e stile: i file già in `Plugins/DepthPose/Sources/DepthPose/` (`DPPoseRenderer`, `DepthEstimator`/`CoreMLDepthModel`, `DPModelStore`, `DPState`). Prefisso dei tipi: `DP`. Test: `cd Plugins/DepthPose && swift test 2>&1 | grep -E "Test run with|✘|error:"`; con `DP_RENDER_DIR=cartella` le prove di disegno scrivono PNG.
- **Nessun test tocca la rete, un modello vero o Vision su una persona vera**: reti, cercatori di riquadri e scaricatori finti. Le prove vere stanno nel Task 9, dietro `DTHUB_LIVE_DEPTH=1`.
- Valori copiati dalla spec: ingresso del modello 288×384 (larghezza×altezza), margine del riquadro 1,25, 133 punti (corpo 0–16, viso 23–90, mano sinistra 91–111, mano destra 112–132), soglia dei punti 0,3, soglia della figura 0,35 (media dei punti 0–16), al massimo 12 persone, spessore `max(3, latoLungo/170)`, viso raggio `max(2, spessore×0,75)` bianco, mani linee `max(2, spessore/2)` con tinta HSV `i/20` e punti blu di raggio spessore.
- Ogni testo dell'interfaccia in italiano e inglese nella tabella `L`; il test di completezza resta verde. Commenti in inglese; README in inglese.
- Nei testi pubblici non si dice che DT Hub «sostituisce» l'interfaccia di Draw Things. Nessun dato personale (percorsi della propria cartella utente, indirizzi email) nei file, nessuna foto di una persona vera nel repo.
- Non pilotare l'interfaccia con computer-use: le prove a mano le fa l'utente.

## Decisioni prese nel piano (la spec non le fissa)

1. **`DPFigure.face` e le mani sono `[DPPoint]` con la confidenza**, non opzionali: il disegno applica la soglia 0,3 punto per punto; un array vuoto vuol dire «il rilevatore non dà viso/mani» (il ripiego con Vision).
2. **`DPState.modelState` resta lo stato della depth** (è usato dai test e dalla vista); la posa ha `poseModelState`; sotto c'è `modelStates: [DPModelKind: ModelState]`.
3. **La posa completa è opzionale nello stato**: `DPState.init` prende `poseModels: DPModelStore? = nil` e `makeFullPose: (@Sendable (URL) throws -> any DPFullPoseDetecting)? = nil`; senza di loro il comportamento è quello di oggi (così le prove esistenti non cambiano).
4. **Il rilevatore di riquadri è dietro un protocollo asincrono** (`DPPersonBoxFinding`), come `DPPoseDetecting`.
5. **La scritta del tasto della depth diventa «Scarica il modello della depth (200 MB)»** (e «Scarica di nuovo il modello della depth»), per distinguerlo da quello della posa.

## Review Focus

1. **Persona tagliata dal bordo o riquadro che esce dall'immagine:** il ritaglio dà nero fuori, i punti fuori dall'immagine non si disegnano, nessun errore (Task 2, 4).
2. **Immagine senza persone (paesaggio) con il ripiego a tutto fotogramma:** nessuno scheletro inventato; la figura sotto 0,35 si scarta (Task 6).
3. **Tante persone (30 riquadri):** al massimo 12, le più grandi (Task 6).
4. **Modello della posa che non si apre o che fallisce:** ripiego a Vision con la nota, il tasto «Scarica di nuovo» torna (Task 7).
5. **Due scaricamenti insieme, «Annulla» di uno solo:** stati e residui indipendenti (Task 7).
6. **Mani e viso con punteggi bassi:** nessuna mano o viso «fantasma» (soglia per punto e minimo di punti per figura) (Task 4).

---

### Task 1: figura e decodifica SimCC (funzioni pure)

**Files:** Create `Sources/DepthPose/DPFigure.swift`, `Sources/DepthPose/DPSimCC.swift`, `Tests/DepthPoseTests/DPSimCCTests.swift`.

**Interfaces:**
- Produces: `struct DPFigure: Equatable, Sendable { var body: DPPerson; var face: [DPPoint]; var leftHand: [DPPoint]; var rightHand: [DPPoint]; init(body: DPPerson, face: [DPPoint] = [], leftHand: [DPPoint] = [], rightHand: [DPPoint] = []) }`; `struct DPSimCCPeak: Equatable, Sendable { var x: Int; var y: Int; var score: Float; var isFound: Bool }` (`isFound` = `score > 0`); `enum DPSimCC { static func decode(x: [Float], y: [Float], keypoints: Int = 133) -> [DPSimCCPeak] }` (`x` e `y` sono i vettori appiattiti `keypoints × bin`; i bin si deducono dalla lunghezza).

- [ ] **Step 1: test rossi** (`DPSimCCTests`): `peakIsTheArgmaxOfEachAxis` (2 punti, x con bin 576: picco del punto 0 in 100, del punto 1 in 7; y con bin 768: picchi in 300 e 5 → `(100,300)` e `(7,5)`); `scoreIsTheMeanOfTheTwoMaxima` (massimi 0,8 e 0,6 → 0,7); `aNonPositiveScoreMeansNotFound` (tutti zero o negativi → `isFound == false`); `theBinCountsComeFromTheLength` (x di 2×576, y di 2×768 → 2 picchi; x di 1×10 con `keypoints: 1` → 1 picco); `emptyOrMismatchedInputGivesNoPeaks` (liste vuote, o lunghezza non divisibile per `keypoints` → `[]`).
- [ ] **Step 2:** `swift test` → fallisce (tipi assenti). **Step 3:** implementare i due file (`DPFigure` con valori predefiniti vuoti; `decode` a un ciclo per punto, nessuna conversione di tipo oltre `Float`). **Step 4:** verdi. **Step 5: Commit** — `feat(depth-pose): figure type and SimCC decoding`.

### Task 2: ritaglio affine

**Files:** Create `Sources/DepthPose/DPCrop.swift`, `Tests/DepthPoseTests/DPCropTests.swift`.

**Interfaces:**
- Consumes: `Pictures` (helper dei test, `DPImageTests.swift`).
- Produces: `struct DPCrop: Equatable, Sendable { static let width = 288, height = 384; let center: CGPoint; let scale: CGSize; var factor: Double; var translation: CGPoint; init(box: CGRect, padding: Double = 1.25); func imagePoint(binX: Double, binY: Double) -> CGPoint; func render(_ image: CGImage) -> CGImage? }`. `box` è in pixel con origine in alto a sinistra; `scale` è l'area dell'immagine mostrata (rapporto 288:384); `factor = 288 / scale.width`; `translation = (144 − factor·center.x, 192 − factor·center.y)`; `imagePoint = (bin/2/(288,384))·scale + center − scale/2`; `render` dà 288×384 RGB 8 bit, scala uniforme `factor` e traslazione `translation`, interpolazione bilineare, **nero fuori dall'immagine**.

- [ ] **Step 1: test rossi** (tolleranza 1e-4): `theThreeReferenceBoxes` (da rtmlib: (30,45,125,318) → centro (77,5; 181,5), scala (255,9375; 341,25), factor 1,125275, traslazione (56,791209; −12,237363); (0,0,320,320) → scala (400; 533,3333), 0,72, (28,8; 76,8); (10,20,210,120) → scala (250; 333,3334), 1,152, (17,28; 111,36)); `aWideBoxGrowsHeightToKeepTheRatio` e `aTallBoxGrowsWidth` (rapporto scala.width/scala.height == 0,75 sempre); `theCentreBinIsTheCentreOfTheBox` (bin (288,384) → centro) e `binZeroIsTheTopLeftOfTheArea` (bin (0,0) → centro − scala/2); `renderHasTheModelSize` (288×384); `renderPutsAKnownPixelWhereExpected` (immagine 320×320 nera con un quadrato 10×10 bianco centrato in (160,160); riquadro (0,0,320,320): il centro del ritaglio, il pixel (144,192), è bianco e un punto lontano è nero); `renderIsBlackOutsideTheImage` (riquadro che esce dall'immagine: i pixel che cadono fuori sono (0,0,0)); `aZeroSizedBoxDoesNotCrash` (riquadro 0×0 → nessun errore, `render` restituisce nil o un'immagine nera).
- [ ] **Step 2:** falliscono. **Step 3:** implementare; in CoreGraphics usare un contesto con origine in alto a sinistra e la trasformazione scala+traslazione (il test del pixel noto fissa i segni giusti). **Step 4:** verdi. **Step 5: Commit** — `feat(depth-pose): affine crop for the pose model`.

### Task 3: da 133 punti a una figura OpenPose

**Files:** Create `Sources/DepthPose/DPWholeBody.swift`, `Tests/DepthPoseTests/DPWholeBodyTests.swift`.

**Interfaces:**
- Consumes: `DPSimCCPeak`, `DPCrop`, `DPFigure`, `DPJoint`, `DPPoint`.
- Produces: `enum DPWholeBody { static let minBodyScore: Float = 0.35; static func figure(peaks: [DPSimCCPeak], crop: DPCrop, imageWidth: Int, imageHeight: Int) -> DPFigure; static func bodyScore(of peaks: [DPSimCCPeak]) -> Float }`. Le coordinate di `DPPoint` sono 0–1 sull'immagine (origine in alto a sinistra) = `crop.imagePoint(...) / (imageWidth, imageHeight)`; `confidence` = il punteggio; un punto non trovato ha `confidence` 0. `bodyScore` = media dei punteggi dei picchi 0–16.

- [ ] **Step 1: test rossi** con picchi finti (un picco per indice con un punteggio che identifica l'indice, ad esempio `0,01·indice + 0,1`): `eachCocoIndexGoesToTheRightOpenPoseJoint` (nose←0, rightEye←2, leftEye←1, rightEar←4, leftEar←3, rightShoulder←6, leftShoulder←5, rightElbow←8, leftElbow←7, rightWrist←10, leftWrist←9, rightHip←12, leftHip←11, rightKnee←14, leftKnee←13, rightAnkle←16, leftAnkle←15); `theNeckIsTheMidpointOfTheShouldersWithTheLowerScore`; `theFaceIsIndices23To90` (68 punti, il primo ha il punteggio dell'indice 23); `handsAreTheTwoBlocksOf21` (sinistra 91–111, destra 112–132); `feetAreNotUsed` (gli indici 17–22 non compaiono); `coordinatesAreNormalisedOnTheImage` (con un `DPCrop` noto e un picco al bin centrale → (centro/dimensioni)); `aNotFoundPeakHasZeroConfidence`; `bodyScoreIsTheMeanOfThe17` (picchi 0–16 a 0,6 e il resto a 0,1 → 0,6); `tooFewPeaksGiveAnEmptyFigure` (meno di 133 picchi → figura senza corpo, viso né mani).
- [ ] **Step 2:** falliscono. **Step 3:** implementare con una tabella fissa degli indici. **Step 4:** verdi. **Step 5: Commit** — `feat(depth-pose): COCO-WholeBody to an OpenPose figure`.

### Task 4: disegno di viso e mani

**Files:** Modify `Sources/DepthPose/DPPoseRenderer.swift`, `Tests/DepthPoseTests/DPPoseRendererTests.swift`.

**Interfaces:**
- Consumes: `DPFigure`, `DPSkeleton`, i colori e lo spessore già nel renderer.
- Produces: `static func render(_ figures: [DPFigure], width: Int, height: Int) -> CGImage?` (la `render(_ people: [DPPerson], …)` esistente la chiama con `DPFigure(body:)`: le sue prove non cambiano); `static let handEdges: [(Int, Int)]` (le 20 ossa della spec); `static func hsv(_ hue: Double) -> (UInt8, UInt8, UInt8)` (saturazione e valore 1); `static func isDrawable(_ figure: DPFigure) -> Bool` (almeno un osso del corpo, oppure un viso con ≥ 10 punti sopra 0,3, oppure una mano con ≥ 5).

- [ ] **Step 1: test rossi** (aggiungere a `DPPoseRendererTests`, immagine 200×200, figura con il corpo del test esistente più viso/mani): `handEdgeColoursFollowTheHue` (osso 0 al punto medio = (255,0,0); osso 10 = (0,255,255), tolleranza 3); `handPointsAreBlueAndBiggerThanTheEdges` (centro di un punto = (0,0,255)); `faceDotsAreWhite` (centro di un punto del viso = (255,255,255)); `faceIsDrawnOverTheHandsAndHandsOverTheBones` (un punto del viso sopra un osso di mano è bianco; un osso di mano sopra un osso del corpo ha il colore HSV pieno, non lo 0,6); `lowConfidencePointsAreNotDrawn` (confidenza 0,29 → nero); `aHandNeedsFivePointsAndAFaceTen` (mano con 4 punti e viso con 9 non rendono la figura disegnabile; con 5 e 10 sì); `aFaceOnlyFigureIsDrawn` (corpo vuoto + viso da 20 punti → immagine non nil); `pointsOutsideTheImageAreSkipped` (coordinate −0,5 e 1,5: nessun errore, nessun pixel fuori); `emptyHandAndFaceArraysChangeNothing` (come oggi); `thePreviousBodyTestsStillPass`.
- [ ] **Step 2:** falliscono. **Step 3:** implementare nell'ordine della spec §5 (ossa del corpo a 0,6 → punti del corpo → ossa e punti delle mani → punti del viso); `hsv` con la conversione HSV→RGB standard. **Step 4:** verdi. **Step 5: Commit** — `feat(depth-pose): draw face and hands like DWPose`.

### Task 5: manifest e indirizzo base per modello

**Files:** Modify `Sources/DepthPose/DPModelStore.swift`, `Tests/DepthPoseTests/DPModelStoreTests.swift`.

**Interfaces:**
- Produces: `DPModelStore.init(folder:files:packageName:baseURL:downloader:compile:validate:)` con `baseURL: URL = DPModelManifest.baseURL` (le chiamate esistenti restano valide); in `DPModelManifest`: `static let dwposeLBaseURL = URL(string: "https://github.com/EXistenz-78/dt-hub/releases/download/dwpose-l-coreml/")!`, `static let dwposeLPackageName = "DWPoseL384F16.mlpackage"`, `static let dwposeLF16: [DPModelFile]` (spec §6: i tre file, con `asset` `DWPoseL384F16-Manifest.json`, `…-model.mlmodel`, `…-weight.bin`, dimensioni 617 / 139.633 / 67.199.424 e gli sha256 della spec).

- [ ] **Step 1: test rossi:** `theDWPoseManifestIsTheOneOfTheConvertedModel` (dimensioni, 64 caratteri di sha256 per file, il sha256 dei pesi `64691178575c974d0e5ccb59051a385546a54b78f3d42d63786ccca067d15810`, percorsi che iniziano per `DWPoseL384F16.mlpackage/`, gli `asset`, e `DPHosts.isAllowed(dwposeLBaseURL + asset)` per ognuno); `aStoreAsksForTheFilesUnderItsOwnBaseURL` (uno scaricatore finto che registra gli URL completi: con `baseURL` di prova gli URL cominciano per quel valore; senza, per `DPModelManifest.baseURL`).
- [ ] **Step 2:** falliscono. **Step 3:** aggiungere il parametro e lo stesso uso al posto di `DPModelManifest.baseURL` dentro `install`; aggiungere le tre costanti. **Step 4:** verdi (tutta la suite). **Step 5: Commit** — `feat(depth-pose): per-model base URL and the DWPose-L manifest`.

### Task 6: rilevatore di tutto il corpo

**Files:** Create `Sources/DepthPose/DWPoseDetector.swift`, `Sources/DepthPose/CoreMLPoseNetwork.swift`, `Tests/DepthPoseTests/DWPoseDetectorTests.swift`.

**Interfaces:**
- Consumes: `DPCrop`, `DPSimCC`, `DPWholeBody`, `DPFigure`.
- Produces: `protocol DPFullPoseDetecting: Sendable { func figures(in image: CGImage) async throws -> [DPFigure] }`; `protocol DPPoseNetwork: Sendable { func simcc(for crop: CGImage) throws -> (x: [Float], y: [Float]) }` (ingresso 288×384); `protocol DPPersonBoxFinding: Sendable { func boxes(in image: CGImage) async throws -> [CGRect] }` (pixel, origine in alto a sinistra); `struct VisionPersonBoxFinder: DPPersonBoxFinding` (`VNDetectHumanRectanglesRequest`, `upperBodyOnly = false`, riquadri convertiti in pixel con la y capovolta); `struct DWPoseDetector: DPFullPoseDetecting { var network: any DPPoseNetwork; var boxFinder: any DPPersonBoxFinding; static let maxPeople = 12; func figures(in image: CGImage, boxes: [CGRect]) throws -> [DPFigure]; func figures(in image: CGImage) async throws -> [DPFigure] }`; `struct CoreMLPoseNetwork: DPPoseNetwork { init(compiledModel: URL) throws }` (ingresso `image` BGRA 288×384, uscite `simcc_x` e `simcc_y` in `MLMultiArray` float16 o float32 → `[Float]`; unità `.all`).

- [ ] **Step 1: test rossi** con una rete finta (restituisce vettori in cui ogni punto ha un picco di valore `v` al bin centrale `(288, 384)`) e un cercatore finto: `oneFigurePerBox` (3 riquadri → 3 figure, nell'ordine); `noBoxesMeansTheWholeImage` (cercatore vuoto → un riquadro = l'immagine intera, una figura); `aFigureBelowTheBodyScoreIsDropped` (picchi 0,2 → nessuna figura; 0,9 → una); `anImageWithNoPersonGivesNothing` (rete con picchi 0,1 e cercatore vuoto → `[]`); `atMostTwelveAndTheBiggestFirst` (30 riquadri di aree diverse → 12 figure, quelle dei 12 riquadri più grandi); `theBoxesAreUsedAsGiven` (`figures(in:boxes:)` passa a `DPCrop` esattamente il riquadro: il punto centrale della figura è il centro del riquadro); `anErrorOfTheNetworkIsThrown`; `aBoxOutsideTheImageStillWorks` (riquadro che esce dall'immagine → nessun errore).
- [ ] **Step 2:** falliscono. **Step 3:** implementare: `figures(in:boxes:)` ordina per area decrescente, prende i primi 12, per ognuno `DPCrop(box:)`, `render`, rete, `DPSimCC.decode`, `DPWholeBody.figure`, scarta se `bodyScore < minBodyScore`; `figures(in:)` cerca i riquadri e, se vuoti, usa `CGRect(0,0,w,h)`. **Step 4:** verdi. **Step 5: Commit** — `feat(depth-pose): whole-body detector (DWPose-L) behind protocols`.

### Task 7: stato con due modelli

**Files:** Modify `Sources/DepthPose/DPState.swift`, `Tests/DepthPoseTests/DPStateTests.swift`.

**Interfaces:**
- Consumes: `DPFullPoseDetecting`, `DPFigure`, `DPPoseRenderer.render(_ figures:…)`, `DPModelStore`.
- Produces: `enum DPModelKind: Hashable, Sendable { case depth, pose }`; in `DPState`: `init(…, poseModels: DPModelStore? = nil, makeFullPose: (@Sendable (URL) throws -> any DPFullPoseDetecting)? = nil, …)`; `@Published private(set) var modelStates: [DPModelKind: ModelState]`; `var modelState: ModelState` (depth, come oggi); `var poseModelState: ModelState`; `var showsPoseDownloadButton: Bool` (solo se `poseModels != nil` e lo stato è `.missing` o `.damaged`); `func downloadModel(_ kind: DPModelKind = .depth) async`; `func cancelDownload(_ kind: DPModelKind = .depth)`; `refreshModelState()` e `prepare()` valgono per tutti e due i modelli.
- Comportamento di «Crea» con Posa: se `poseModelState == .ready` e `makeFullPose` c'è → `figures(in:)` del rilevatore (fuori dall'attore principale); se fallisce → `poseModelState = .damaged`, nota `poseModelDamaged` e ripiego a Vision; altrimenti Vision, con ogni persona avvolta in `DPFigure(body:)`.

- [ ] **Step 1: test rossi** (rig con un secondo `DPModelStore` finto per la posa, `FakeFullDetector` che restituisce figure con viso e mani, uno scaricatore finto per modello): `fullPoseIsUsedWhenItsModelIsReady` (la figura disegnata include viso e mani: `Vision` non chiamato); `visionIsTheFallbackWithoutTheModel` (modello della posa mancante → `FakeDetector` di Vision chiamato, nessuna nota); `aFailingFullDetectorFallsBackToVisionWithANote` (fallisce → `poseModelState == .damaged`, nota, posa creata con Vision); `theTwoDownloadsAreIndependent` (si avvia il download della depth con un cancello, poi quello della posa: terminano separatamente; `cancelDownload(.depth)` non cambia `poseModelState`); `cancellingOneLeavesTheOtherUntouched`; `aPoseDownloadFailureShowsTheReasonAndStaysMissing`; `aPoseModelPackageFoundInTheFolderIsCompiledAtLaunch` (come per la depth); `prepareRefreshesBothModels`; `showsPoseDownloadButtonOnlyWhenTheModelIsMissingOrDamagedAndAStoreExists` (senza `poseModels`, mai); `withoutPoseModelsTheOldBehaviourIsUnchanged` (le prove esistenti restano verdi senza modifiche).
- [ ] **Step 2:** falliscono. **Step 3:** implementare (`modelStates`, un `Task` di installazione per tipo, `WeakState` per l'avanzamento come oggi, `reason(for:)` invariato). **Step 4:** verdi (tutta la suite). **Step 5: Commit** — `feat(depth-pose): two independent models in the state`.

### Task 8: vista, testi e collegamento al plug-in

**Files:** Modify `Sources/DepthPose/DPView.swift`, `Sources/DepthPose/Strings.swift`, `Sources/DepthPose/DepthPosePlugin.swift`, `Tests/DepthPoseTests/RenderTests.swift`, `Tests/DepthPoseTests/StringsTests.swift`.

**Interfaces:**
- Consumes: `DPState` (Task 7), `DPModelManifest.dwposeL*`, `DWPoseDetector`, `CoreMLPoseNetwork`, `VisionPersonBoxFinder`.
- Produces: `DPViewActions.download: (DPModelKind) -> Void` e `cancel: (DPModelKind) -> Void`; nuove chiavi `L`: `downloadPoseModel` («Download the full-pose model (64 MB)» / «Scarica il modello della posa completa (64 MB)»), `redownloadPoseModel`, `poseModelDamaged`; `downloadModel` e `redownload` passano a «…della depth…» (200 MB); il plug-in crea lo stato con `poseModels: DPModelStore(packageName: DPModelManifest.dwposeLPackageName, files: DPModelManifest.dwposeLF16, baseURL: DPModelManifest.dwposeLBaseURL)` e `makeFullPose: { DWPoseDetector(network: try CoreMLPoseNetwork(compiledModel: $0), boxFinder: VisionPersonBoxFinder()) }`.

- [ ] **Step 1: test rossi:** `StringsTests`: la completezza delle due lingue (già c'è) e `theDepthButtonSaysDepthAndTheSize` («depth» e «200 MB» in entrambe le lingue), `thePoseButtonSaysTheSize` («64 MB»). `RenderTests`: la sezione dei modelli disegnata con entrambi i modelli mancanti, con la depth pronta e la posa in scaricamento, con tutti e due pronti (nessun tasto); resta il controllo sui colori distinti.
- [ ] **Step 2:** falliscono. **Step 3:** la sezione dei modelli diventa due righe (una per tipo), ognuna come l'attuale: barra + «Annulla» in scaricamento, tasto se manca o è danneggiato, niente se pronto; i tasti chiamano `actions.download(.depth/.pose)`. **Step 4:** verdi; `swift build -c release` senza avvisi. **Step 5: Commit** — `feat(depth-pose): the pose model download in the tab`.

### Task 9: script di conversione e prove con i modelli veri

**Files:** Create `Plugins/DepthPose/Scripts/convert_pose_model.py`; Modify `Plugins/DepthPose/Scripts/requirements-convert.txt`; Modify `Tests/DepthPoseTests/LiveTests.swift`.

- [ ] **Step 1:** `convert_pose_model.py PERCORSO.onnx OUT.mlpackage` come nella spec §8 (rimedio ai `Clip`, avvolgimento con normalizzazione, `ct.convert`); in testa, la nota della licenza Apache-2.0 e dei requisiti. `requirements-convert.txt`: aggiungere `onnx` e `onnx2torch`, lasciando `torch==2.7.0`.
- [ ] **Step 2:** ricreare il pacchetto con lo script (modello di partenza `dw-ll_ucoco_384.onnx` di `yzd-v/DWPose`, scaricato fuori dal repo) in una cartella temporanea; controllare che i **pesi** abbiano lo stesso sha256 della spec (`64691178…`); i due file piccoli cambiano a ogni conversione: **la release usa i file già con gli hash della spec** (copiati dal pacchetto dello spike in `build/pose-model/` con i nomi piatti `DWPoseL384F16-…` e verificati).
- [ ] **Step 3: prove live** (nuovo `LiveTests`, abilitate da `DTHUB_LIVE_DEPTH=1`; `DP_LIVE_POSE_DIR` = cartella che contiene `DWPoseL384F16.mlpackage` nel percorso dei file del manifest): `thePosePackageMatchesTheManifestCompilesAndOpens` (`installLocalPackage` con il manifest vero); `thePoseModelFindsAFullBodyInAPhoto` (con `DP_LIVE_POSE_PHOTO` = foto di prova, se impostata: almeno una figura, 68 punti del viso e 21+21 delle mani con confidenza media > 0,5); `aSceneWithoutPeopleGivesNoFigure` (scena sintetica a pavimento, già nei test: `DWPoseDetector` con `VisionPersonBoxFinder` → `[]`); `visionFindsThePersonBoxInAPhoto` (con la foto: almeno un riquadro). Con `DP_LIVE_POSE_GOLDEN` (JSON dei punti di onnxruntime per la foto e i riquadri) un confronto facoltativo con tolleranza 6 px, riquadri passati a `figures(in:boxes:)`.
- [ ] **Step 4:** lanciare dalla shell fuori sandbox: `cd Plugins/DepthPose && DTHUB_LIVE_DEPTH=1 DP_LIVE_POSE_DIR=<cartella> DP_LIVE_POSE_PHOTO=<foto> swift test --filter LiveTests 2>&1 | grep -E "LIVE|Test run with|✘|Expectation failed|error:"`; riportare tempi e punteggi nel messaggio finale. **Step 5: Commit** — `feat(depth-pose): script that converts DWPose-L to Core ML and live probes`.

### Task 10: documentazione, release del modello e prove a mano

**Files:** Modify `Plugins/DepthPose/README.md`, `Plugins/README.md`, `README.md`, la spec madre (§5.2 e §13); alla fine, locali: `docs/superpowers/backlog.md`, `docs/superpowers/briefing-prossima-sessione.md` e le note Obsidian.

- [ ] **Step 1:** `Plugins/DepthPose/README.md`: la sezione «Pose» riscritta (DWPose-L con viso e mani, Vision come ripiego, riquadri da Vision o immagine intera, limiti), «The pose model» (tasto, 64 MB, cartella, licenza Apache-2.0 con attribuzione a IDEA-Research / DWPose e a `yzd-v/DWPose`), «Network» (due modelli, sempre solo GitHub), lo script di conversione. `Plugins/README.md` e `README.md`: la riga del plug-in aggiornata. Spec madre: nota in §5.2 («superato dalla spec della posa completa») e voce in §13.
- [ ] **Step 2: verifica completa:** `swift test` in `Plugins/DepthPose`, `Packages` e `PluginKit` verdi; `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build` → `BUILD SUCCEEDED`; controllo dei dati personali nel diff (il comando del briefing §3) vuoto. **Step 3: Commit** — `docs(depth-pose): README for the full pose`.
- [ ] **Step 4: release dei file del modello (SOLO con il via libera esplicito dell'utente):** `gh release create dwpose-l-coreml --repo EXistenz-78/dt-hub --target main --latest=false` con i tre file di `build/pose-model/`, un `DWPoseL384F16-NOTICE.md` (Apache-2.0, attribuzione a IDEA-Research DWPose / Zhendong Yang et al., pesi `yzd-v/DWPose`, modifiche: convertito in Core ML F16, ingresso fisso 288×384, normalizzazione inclusa; nessun limite di uso commerciale per questo modello) e note in inglese; verificare `releases/latest` ancora `v0.2.3`, i quattro asset (200) e **un download vero con gli sha256** della spec, e lanciare `DP_LIVE_DOWNLOAD=1` per il download del plug-in.
- [ ] **Step 5:** costruire il bundle (`Scripts/build.sh`), dare all'utente il comando di installazione e le **prove a mano**: 1) senza il modello della posa il tab mostra il tasto «Scarica il modello della posa completa (64 MB)» e la posa funziona ancora con Vision; 2) scaricare il modello: tasto e barra; 3) «Crea» con Posa su una foto con una persona intera: corpo, viso a puntini e mani; 4) foto con più persone; 5) persona tagliata dal bordo; 6) un'illustrazione; 7) un paesaggio senza nessuno: nessuno scheletro; 8) i due scaricamenti insieme.
- [ ] **Step 6:** aggiornare backlog (rinviati della spec §11), briefing e Obsidian (nota `DT Hub - Depth & Pose`); messaggio finale nel formato del briefing §6 e richiesta di via libera per l'unione.
