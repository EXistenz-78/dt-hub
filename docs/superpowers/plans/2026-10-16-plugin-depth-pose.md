# Plug-in Depth & Pose — Piano di implementazione

> **Per chi esegue:** SOTTO-SKILL OBBLIGATORIA: `superpowers:subagent-driven-development` (consigliata) oppure `superpowers:executing-plans`. I passi usano la sintassi a caselle (`- [ ]`).

**Obiettivo:** un plug-in che da un'immagine (file o trascinamento) crea una mappa di depth e/o uno scheletro di posa OpenPose e li manda al Moodboard.

**Architettura:** nessuna modifica all'app né al contratto 1. Tutto in `Plugins/DepthPose`, a strati: tipi e funzioni pure per la posa (`DPSkeleton`, `DPPoseRenderer`), due adattatori ai framework di Apple dietro protocolli (`VisionPoseDetector` per la posa, `CoreMLDepthModel` per la depth), `DPModelStore` per scaricare e compilare il modello, poi lo stato (`DPState`) che orchestra e la vista. Vision, Core ML e rete nei test sono finti; le prove con i modelli veri sono un passo a parte, fuori sandbox.

**Tecnologie:** Swift 6.2, Swift Testing, SwiftUI/AppKit, Vision, Core ML, ImageIO/CoreGraphics, CryptoKit, URLSession.

**Spec:** `docs/superpowers/specs/2026-10-16-plugin-depth-pose-design.md` (chi esegue legge anche quella).

## Vincoli globali

- Si lavora sul ramo `depth-pose` (già creato da `main`, contiene la spec). **Niente unione, push o release senza via libera esplicito.** File aggiunti a git **per nome**, mai `git add -A`.
- Modello per struttura, alias dei moduli, `build.sh`, tabella dei testi e test di rendering: `Plugins/SphereLight/` (Package, `Scripts/build.sh`, `SphereLightPlugin`, `SphereSender`, `Strings.swift`) e `Plugins/LoRAAdvisor/` (trascinamento in `LAListCard.drop`, rete in `LAFetcher`, cartella dati in `LAStore`, `RenderTests`). Prefisso dei tipi del plug-in: `DP`. Id `com.exiztenz.dthub.depthpose`, nome «Depth & Pose», versione `1.0`, tutte le famiglie, macOS 26.
- Test: `cd Plugins/DepthPose && swift test 2>&1 | grep -E "Test run with|✘|error:"`. Nessun test tocca la rete vera, un modello vero o Vision su una persona vera: protocolli finti e `URLProtocol` finto. Le prove con i modelli veri stanno nel Task 9, attivate da `DTHUB_LIVE_DEPTH=1`, fuori sandbox (`URLSession` va in timeout in sandbox).
- Valori copiati dalla spec: lato corto di ingresso del modello 518 px, lato lungo multiplo di 14; lato lungo massimo 2048 px; confidenza minima dei giunti 0,3; PNG a 8 bit; nomi nel Moodboard «Depth» e «Pose»; cartella dati `~/Library/Application Support/DT Hub/Data/DepthPose/`; rete solo al clic su «Scarica il modello», solo `https`, solo `huggingface.co`, `hf.co` e sottodomini.
- Ogni testo dell'interfaccia in italiano e inglese nella tabella `L`; un test controlla che le due lingue siano complete. Commenti in inglese; README in inglese.
- Nei testi pubblici non si dice che DT Hub «sostituisce» l'interfaccia di Draw Things. Nessun dato personale nei file (`/Users/existenz`, `antoniodachille`, `/Volumes/LLM`); nessuna foto di persona vera nel repo.
- Non pilotare l'interfaccia con computer-use: le prove a mano le fa l'utente.

## Decisioni prese nel piano (la spec non le fissa)

1. **Coordinate dei giunti**: `DPPoint` ha `x`, `y` in 0–1 con l'origine **in alto a sinistra** (Vision usa l'origine in basso a sinistra: la inverte solo `VisionPoseDetector`).
2. **Una persona si disegna** solo se ha almeno un osso con entrambi gli estremi sopra la soglia; altrimenti si salta (e se non resta nessuno, «nessuna persona trovata»).
3. **Ossa a metà opacità**: come negli esempi di OpenPose per i ControlNet, l'osso è il colore × 0,6 sul nero, il punto è il colore pieno.
4. **Orientamento EXIF applicato** quando si apre l'immagine (altrimenti Vision e il modello vedono una persona sdraiata).
5. **Nomi dei file di uscita** in `tempFolder`: `com.exiztenz.dthub.depthpose-depth.png` e `…-pose.png` (come Sphere Light).
6. **Risultati vecchi scartati**: ogni «Crea» porta un numero di generazione; se nel frattempo l'immagine o il progetto sono cambiati, il risultato si butta.

## Review Focus

1. **Foto ruotata con EXIF, con trasparenza, CMYK o enorme (12000 px):** la posa e la depth non devono uscire ruotate, né far esplodere la memoria (Task 4, 5).
2. **Persona tagliata dal bordo o con pochi giunti:** nessun crash, nessun osso con un estremo inventato (Task 2, 3).
3. **Scaricamento interrotto, «Annulla», doppio clic, app chiusa a metà:** niente cartelle a metà, nessuno scaricamento doppio; i resti di una volta prima si cancellano all'avvio (Task 6).
4. **Immagine sostituita mentre «Crea» lavora:** il risultato di prima non finisce accanto alla nuova immagine né nel Moodboard (Task 7).
5. **Plug-in spento, `tempFolder` assente, Moodboard che risponde con `problems`:** il tasto lo dice, non sembra rotto (Task 7, 8).

---

### Task 1: scheletro del pacchetto e testi

**Files:** Create `Plugins/DepthPose/Package.swift`, `Scripts/build.sh`, `Sources/DepthPose/DepthPosePlugin.swift`, `Sources/DepthPose/Strings.swift`, `Tests/DepthPoseTests/StringsTests.swift`, `Tests/DepthPoseTests/PluginTests.swift`.

**Interfaces:**
- Produces: `DepthPosePlugin: DTHubPlugin` (manifest id `com.exiztenz.dthub.depthpose`, name `Depth & Pose`, version `1.0`, symbol `figure.stand`, `families: nil`), `DepthPoseEntry: DTHubPluginEntry` (`@objc(DepthPoseEntry)`), `enum L` con `Key` (`CaseIterable`), `L.text(_:italian:)`, `L.format(_:_:italian:)`, `L.isDefined(_:italian:)`, `L.systemIsItalian`.

- [ ] **Step 1: test rossi.** `StringsTests`: per ogni `L.Key.allCases` e per le due lingue `L.isDefined` è vero (come `Plugins/SphereLight` / Batch plus). `PluginTests`: `manifest.id == "com.exiztenz.dthub.depthpose"`, `manifest.version == "1.0"`, `manifest.families == nil`; `handle` di un tipo sconosciuto risponde `{"type":"unsupported"}`.
- [ ] **Step 2:** `swift test` → fallisce (target assente).
- [ ] **Step 3:** copiare la struttura di `Plugins/SphereLight/Package.swift` con alias `DepthPoseKit` / `DepthPoseDesign`; `Scripts/build.sh` come quello di Sphere Light (`VERSION="1.0"`, `DepthPose.dthubplugin`, id sopra, entry `DepthPoseEntry`). `Strings.swift`: tutte le chiavi dei Task seguenti, già con italiano e inglese: `dropHere, open, mode, depth, pose, both, create, sendToMoodboard, downloadModel, redownload, cancel, downloading(%d%%), depthMissing, creating, created, sent, sentWithConflicts, noFolder, notAnswered, unreadableImage, noPerson, poseOnlyBecauseNoModel, downloadFailed, modelDamaged, active, inactive`. `DepthPosePlugin.handle` risponde `unsupported` per ora; la vista è un `Text` provvisorio.
- [ ] **Step 4:** `swift test` → verde.
- [ ] **Step 5: Commit** — `feat(depth-pose): package skeleton and strings`.

### Task 2: giunti e scheletro (funzioni pure)

**Files:** Create `Sources/DepthPose/DPSkeleton.swift`, `Tests/DepthPoseTests/DPSkeletonTests.swift`.

**Interfaces:**
- Produces:
  - `enum DPJoint: Int, CaseIterable { case nose, neck, rightShoulder, rightElbow, rightWrist, leftShoulder, leftElbow, leftWrist, rightHip, rightKnee, rightAnkle, leftHip, leftKnee, leftAnkle, rightEye, leftEye, rightEar, leftEar }` (l'ordine è quello di OpenPose a 18 punti: **non cambiarlo**).
  - `struct DPPoint: Equatable, Sendable { var x: Double; var y: Double; var confidence: Double }` (coordinate 0–1, origine in alto a sinistra).
  - `typealias DPPerson = [DPJoint: DPPoint]`.
  - `enum DPSkeleton { static let minConfidence = 0.3; static let bones: [(DPJoint, DPJoint)]; static func points(of person: DPPerson) -> [DPJoint: CGPoint]; static func drawableBones(of person: DPPerson) -> [(DPJoint, DPJoint)] }`.

- [ ] **Step 1: test rossi** (con giunti finti): `bonesAreTheSeventeenOfOpenPose` (`bones.count == 17`; le coppie, per indice, sono (1,2) (1,5) (2,3) (3,4) (5,6) (6,7) (1,8) (8,9) (9,10) (1,11) (11,12) (12,13) (1,0) (0,14) (14,16) (0,15) (15,17), in quest'ordine); `jointBelowThresholdIsDropped` (confidenza 0,29 fuori, 0,3 dentro); `missingNeckIsTheMidpointOfTheShoulders` (e se manca una spalla il collo resta assente); `existingNeckIsKept`; `rightAndLeftAreNotSwapped` (un punto `rightShoulder` resta `rightShoulder`); `boneNeedsBothEnds` (solo `rightShoulder` e `rightElbow` → una sola osso drawable); `personWithOneJointHasNoBones`.
- [ ] **Step 2:** i test falliscono (tipi assenti).
- [ ] **Step 3:** implementare i tipi e le due funzioni; `points(of:)` restituisce i giunti sopra soglia più il collo ricavato; `drawableBones(of:)` filtra `bones` sui punti restituiti.
- [ ] **Step 4:** verdi. **Step 5: Commit** — `feat(depth-pose): OpenPose skeleton from joints`.

### Task 3: disegno dello scheletro

**Files:** Create `Sources/DepthPose/DPPoseRenderer.swift`, `Tests/DepthPoseTests/DPPoseRendererTests.swift`.

**Interfaces:**
- Consumes: `DPPerson`, `DPSkeleton`.
- Produces: `enum DPPoseRenderer { static let colors: [(UInt8, UInt8, UInt8)]; static func thickness(forLongSide: Int) -> Int; static func render(_ people: [DPPerson], width: Int, height: Int) -> CGImage?; static func pngData(_ image: CGImage) -> Data? }`. `render` restituisce `nil` se nessuna persona ha un osso disegnabile.

Colori RGB (18, nell'ordine; l'osso *i* di `DPSkeleton.bones` usa il colore *i*, il giunto di indice *k* il colore *k*): `(255,0,0) (255,85,0) (255,170,0) (255,255,0) (170,255,0) (85,255,0) (0,255,0) (0,255,85) (0,255,170) (0,255,255) (0,170,255) (0,85,255) (0,0,255) (85,0,255) (170,0,255) (255,0,255) (255,0,170) (255,0,85)`. Spessore = `max(3, longSide / 170)`; osso = linea di quello spessore con colore × 0,6, giunto = cerchio pieno di raggio = spessore con colore pieno, sopra le ossa; fondo nero opaco.

- [ ] **Step 1: test rossi** su un'immagine 200×200 con una persona nota: `backgroundIsBlack` (angolo (0,0) = nero); `jointIsTheFullColour` (il pixel al centro di `neck` = `colors[1]`); `boneMidpointIsSixtyPercentOfItsColour` (punto medio dell'osso 0 = `colors[0]` × 0,6 ±2 per canale); `jointsAreDrawnOverBones`; `twoPeopleAreBothDrawn`; `boneWithAMissingEndIsNotDrawn`; `noDrawablePersonReturnsNil`; `thicknessIsProportionalWithAMinimum` (`thickness(forLongSide: 100) == 3`, `…(1700) == 10`); `pngDataIsAPNGOfTheSameSize`.
- [ ] **Step 2:** falliscono. **Step 3:** implementare con `CGContext` RGB 8 bit, origine in alto a sinistra (invertire l'asse del contesto una volta), niente anti-aliasing necessario per i test ma sì per l'uscita (`setShouldAntialias(true)`; i test leggono pixel al centro delle forme).
- [ ] **Step 4:** verdi. **Step 5: Commit** — `feat(depth-pose): draw the OpenPose skeleton`.

### Task 4: apertura dell'immagine e posa con Vision

**Files:** Create `Sources/DepthPose/DPImage.swift`, `Sources/DepthPose/VisionPoseDetector.swift`, `Tests/DepthPoseTests/DPImageTests.swift`, `Tests/DepthPoseTests/VisionPoseDetectorTests.swift`.

**Interfaces:**
- Produces:
  - `enum DPImage { static let maxLongSide = 2048; static func load(data: Data) -> CGImage?; static func load(file: URL) -> CGImage? }`: ImageIO, **orientamento EXIF applicato**, ridotto a `maxLongSide` se più grande, sempre RGB a 8 bit con fondo nero sotto la trasparenza.
  - `protocol DPPoseDetecting: Sendable { func people(in image: CGImage) async throws -> [DPPerson] }`.
  - `struct VisionPoseDetector: DPPoseDetecting` e `static func joint(for name: VNHumanBodyPoseObservation.JointName) -> DPJoint?` (`nil` per `root`), `static func person(from observation: VNHumanBodyPoseObservation) -> DPPerson` (inverte la y).

- [ ] **Step 1: test rossi.** `DPImageTests` con immagini sintetiche create nel test: `largeImageIsReducedToTheLimit` (4000×3000 → 2048×1536), `smallImageIsKept`, `exifOrientationIsApplied` (un JPEG 40×20 con orientamento 6 diventa 20×40), `transparentImageGetsBlackBackground`, `garbageDataReturnsNil`. `VisionPoseDetectorTests`: `everyVisionJointMapsExceptRoot` (per `neck, nose, leftShoulder…` il `DPJoint` ha lo stesso nome; `.root` → nil); `visionOnABlankImageFindsNoOne` (immagine nera 128×128 → `[]`).
- [ ] **Step 2:** falliscono. **Step 3:** implementare; `people(in:)` esegue `VNDetectHumanBodyPoseRequest` con `VNImageRequestHandler(cgImage:)` fuori dal main actor; i punti con confidenza 0 si omettono.
- [ ] **Step 4:** verdi. **Step 5: Commit** — `feat(depth-pose): image loading and Vision body pose`.

### Task 5: depth

**Files:** Create `Sources/DepthPose/DepthEstimator.swift`, `Sources/DepthPose/CoreMLDepthModel.swift`, `Tests/DepthPoseTests/DepthEstimatorTests.swift`.

**Interfaces:**
- Produces:
  - `protocol DPDepthModel: Sendable { func predict(_ image: CGImage) throws -> CGImage }` (ingresso: l'immagine già a dimensione d'ingresso; uscita: grigi, di qualunque dimensione).
  - `struct DepthEstimator { var model: any DPDepthModel; var invertsModelOutput = false; static func inputSize(forWidth: Int, height: Int) -> (width: Int, height: Int); func depthMap(for image: CGImage) throws -> CGImage }`.
  - `struct CoreMLDepthModel: DPDepthModel { init(compiledModel: URL) throws }` (ingresso `image`, uscita `depth`, `computeUnits = .all`).

- [ ] **Step 1: test rossi** con un `DPDepthModel` finto che registra la dimensione ricevuta e restituisce un gradiente a una dimensione diversa: `inputSizeHasShortSide518AndLongSideMultipleOf14` (1024×768 → `(686, 518)`, perché 1024/768 × 518 = 690,7 e il multiplo di 14 più vicino è 686; 768×1024 → `(518, 686)`; 500×500 → `(518, 518)`); `outputIsResizedToTheInputImage`; `outputIsNormalisedFrom0To255` (modello finto con valori 10…40 → minimo 0, massimo 255); `flatOutputDoesNotDivideByZero` (tutti uguali → immagine uniforme, nessun crash); `invertingFlipsNearAndFar` (`invertsModelOutput = true` inverte i pixel); `nearIsBright` (modello finto che dà valori alti = vicino → il pixel più alto resta 255).
- [ ] **Step 2:** falliscono. **Step 3:** implementare; l'interpolazione è bilineare (`CGContext.interpolationQuality = .high`); la normalizzazione si fa sul risultato già riportato alle dimensioni originali; il lavoro pesante va fuori dal main actor. `CoreMLDepthModel` crea un `CVPixelBuffer` BGRA alla dimensione d'ingresso, chiama `MLModel.prediction`, legge il `CVPixelBuffer` di `depth` in grigi 8 bit (se il tipo di uscita non è un'immagine, errore chiaro).
- [ ] **Step 4:** verdi. **Step 5: Commit** — `feat(depth-pose): depth estimation behind a model protocol`.

### Task 6: il modello — posizione, scaricamento, compilazione

**Files:** Create `Sources/DepthPose/DPModelStore.swift`, `Sources/DepthPose/DPDownloader.swift`, `Tests/DepthPoseTests/DPModelStoreTests.swift`, `Tests/DepthPoseTests/DPDownloaderTests.swift`.

**Interfaces:**
- Produces:
  - `struct DPModelFile: Sendable { let path: String; let size: Int64; let sha256: String? }` e `enum DPModelManifest { static let baseURL: URL; static let depthAnythingSmallF16: [DPModelFile] }` con i tre file della spec §6 (le due dimensioni e lo sha256 di `weight.bin` `fa60d9b6a155734f59029ebb882fd54e549bfaee3539c1a9cbd2cbbab64a0fed`; `Manifest.json` 617 byte e `model.mlmodel` 399.433 byte senza sha256), `baseURL = https://huggingface.co/apple/coreml-depth-anything-v2-small/resolve/main/`.
  - `enum DPHosts { static func isAllowed(_ url: URL) -> Bool }` (https, `huggingface.co`, `hf.co` e sottodomini).
  - `protocol DPFileDownloading: Sendable { func download(_ url: URL, to file: URL, progress: @Sendable (Int64) -> Void) async throws }` e `final class DPDownloader: DPFileDownloading` (sessione effimera, niente cookie né cache, timeout di richiesta 60 s e di risorsa 20 min, reindirizzamento verso un host non ammesso rifiutato).
  - `struct DPModelStore { init(folder: URL, files: [DPModelFile] = DPModelManifest.depthAnythingSmallF16, downloader: any DPFileDownloading = DPDownloader(), compile: @Sendable (URL) throws -> URL = { try MLModel.compileModel(at: $0) }, validate: @Sendable (URL) -> Bool = { (try? MLModel(contentsOf: $0)) != nil }); static var defaultFolder: URL; var compiledURL: URL; func isPresent() -> Bool; func install(progress: @Sendable (Double) -> Void) async throws; func cleanUpLeftovers() }` e `enum DPModelError: Error, Equatable { case notAllowed, wrongSize(String), wrongChecksum(String), compileFailed, cancelled, network(String) }`.

- [ ] **Step 1: test rossi** con un `DPFileDownloading` finto che scrive byte noti (manifest di test con file piccoli e sha256 calcolato nel test) e cartelle temporanee: `installDownloadsVerifiesCompilesAndMoves` (alla fine `isPresent()`, la compilata è in `compiledURL`, la cartella temporanea è sparita); `wrongSizeFailsAndLeavesNothing`; `wrongChecksumFailsAndLeavesNothing`; `cancelLeavesNothing` (task annullato → `.cancelled`); `compileFailureLeavesNothing`; `presentNeedsAModelThatOpens` (cartella compilata presente ma `validate` falso → `isPresent()` falso); `progressGoesFromZeroToOne`; `cleanUpLeftoversRemovesTemporaryFolders`; `aSecondInstallWhileOneRunsIsRefused` (stessa istanza; la seconda chiamata lancia senza scaricare di nuovo); `reinstallReplacesADamagedModel`. `DPDownloaderTests` con `URLProtocol` finto: `redirectToAnotherHostIsRefused`, `redirectToAHuggingFaceSubdomainIsFollowed`, `httpErrorFails`, `nonHTTPSIsRefused`; `hostsAllowList` (`huggingface.co`, `cdn-lfs.huggingface.co`, `cas-bridge.xethub.hf.co` sì; `evilhuggingface.co`, `huggingface.co.evil.com`, `http://huggingface.co` no).
- [ ] **Step 2:** falliscono. **Step 3:** implementare. `install` scarica in `<folder>/.download-<uuid>/`, controlla dimensione (e sha256 a blocchi di 1 MB con CryptoKit, dove c'è), compila il `.mlpackage` ricostruito con la sua struttura di cartelle, sposta compilata e pacchetto in `<folder>` con una sostituzione atomica, cancella la temporanea (anche in caso di errore o annullamento). Il blocco contro il doppio scaricamento è un flag nell'istanza (attore o `OSAllocatedUnfairLock`).
- [ ] **Step 4:** verdi. **Step 5: Commit** — `feat(depth-pose): download, verify and compile the depth model`.

### Task 7: invio al Moodboard, stato per progetto e orchestrazione

**Files:** Create `Sources/DepthPose/DPMessages.swift`, `Sources/DepthPose/DPStore.swift`, `Sources/DepthPose/DPState.swift`, `Tests/DepthPoseTests/DPMessagesTests.swift`, `Tests/DepthPoseTests/DPStoreTests.swift`, `Tests/DepthPoseTests/DPStateTests.swift`.

**Interfaces:**
- Consumes: tutto dei Task 2–6.
- Produces:
  - `enum DPMode: String, Codable, CaseIterable { case depth, pose, both }`.
  - `enum DPMessages { static let depthName = "Depth"; static let poseName = "Pose"; static let depthFile = "com.exiztenz.dthub.depthpose-depth.png"; static let poseFile = "com.exiztenz.dthub.depthpose-pose.png"; static func moodboard(depthPath: String?, posePath: String?) -> [[String: Any]] }` (solo le voci con un percorso, nell'ordine depth, pose).
  - `struct DPStore { var folder: URL?; var defaults: UserDefaults; func load() -> DPMode; func save(_ mode: DPMode); func adoptLegacy() }` come `SLRStore` (file `state.json` nella cartella del progetto; senza cartella, `UserDefaults`).
  - `@MainActor final class DPState: ObservableObject` con `@Published var mode: DPMode`, `image: CGImage?`, `imageName: String`, `depthImage/poseImage: CGImage?`, `status: String`, `modelState: ModelState` (`.missing, .downloading(Double), .ready, .damaged`), `isWorking`, `active`, `tempFolder: String?`; `init(store: DPStore, models: DPModelStore, detector: any DPPoseDetecting, makeDepth: @escaping @Sendable (URL) throws -> DepthEstimator, italian: Bool)`; metodi `setImage(data:name:)`, `setImage(file:)`, `create() async`, `send(contribute: @MainActor ([String: Any]) async -> [String: Any]?) async`, `downloadModel() async`, `cancelDownload()`, `switchProject(folder:adoptLegacy:)`, `apply(context: Data)`, `refreshModelState()`.

- [ ] **Step 1: test rossi.** `DPMessagesTests`: `onlyTheGivenMapsAreSent` (depth sola, pose sola, tutte e due in quest'ordine, nessuna → `[]`); i nomi e i percorsi. `DPStoreTests` (come `SLRStoreProjectTests`): predefinito `.both`; salva/rilegge in `state.json`; file illeggibile → `.both`; `adoptLegacy` una volta sola. `DPStateTests` con detector e modello finti: `createWithBothMakesBothMaps`; `createWithDepthOnlyDoesNotRunVision`; `createWithPoseOnlyWorksWithoutTheModel`; `bothWithoutTheModelMakesOnlyThePoseAndSaysSo` (`poseOnlyBecauseNoModel`); `depthOnlyWithoutTheModelAsksToDownload`; `noPersonSaysSoAndKeepsTheDepth`; `unreadableImageSaysSo`; `replacingTheImageClearsTheMaps`; **`aResultThatArrivesAfterANewImageIsDiscarded`** (detector che aspetta; si cambia immagine; poi si sblocca); `sendWritesThePNGsInTempFolderAndContributesOnlyTheChosenMaps`; `sendWithoutTempFolderSaysSo` e non chiama `contribute`; `sendReportsConflictsAndErrors` (`conflicts: 2` → `sentWithConflicts`, `problems: ["p"]` → la riga contiene "p", `{"type":"error","text":"x"}` → "x", `nil` → `notAnswered`); `sendIsDisabledWhenNothingWasCreated`; `modelStateFollowsTheStore` (`.missing` → durante l'installazione `.downloading` con avanzamento → `.ready`; fallimento → `.missing` con `downloadFailed`; modello che non si apre → `.damaged`); `switchProjectKeepsOnlyTheMode` (cambia progetto: immagine e mappe vuote, modo come salvato); `contextSetsTempFolder`.
- [ ] **Step 2:** falliscono. **Step 3:** implementare. `create()` incrementa un numero di generazione e confronta alla fine; il lavoro di Vision e di Core ML va in `Task.detached`; i PNG si scrivono in `tempFolder` solo all'invio, non alla creazione; `makeDepth(compiledURL)` si chiama solo quando serve e solo se il modello è `.ready`.
- [ ] **Step 4:** verdi. **Step 5: Commit** — `feat(depth-pose): state, per-project mode and Moodboard messages`.

### Task 8: vista, trascinamento e collegamento all'app

**Files:** Create `Sources/DepthPose/DPView.swift`, `Tests/DepthPoseTests/RenderTests.swift`; Modify `Sources/DepthPose/DepthPosePlugin.swift`.

**Interfaces:**
- Consumes: `DPState`, `L`, `DS` (`DSPillButtonStyle`, `DSPanelHeader`, `dsPanel`, `DSGroupHeader`).
- Produces: `struct DPView: View` (stato e tre azioni: `create`, `send`, `download`); `DepthPosePlugin` completo: `makeViewController`, `start(host:)` (che chiama `models.cleanUpLeftovers()` e `refreshModelState()`), `handle` per `context` (`DTHubContext.tempFolder`), `project` (`DTHubProject` → `switchProject`), `activate`/`deactivate` (`state.active`), altrimenti `unsupported`; `host.contribute(["moodboard": …])` per l'invio; `host.notice` per gli errori che non stanno nella riga di stato.

- [ ] **Step 1: test rossi** (`RenderTests` come in LoRA Advisor: PNG in `DP_RENDER_DIR` se impostata, altrimenti si controlla solo che qualcosa sia disegnato): tab vuoto; con immagine e le due mappe; con modello mancante (il tasto «Scarica il modello» c'è); con modello presente (il tasto **non** c'è); in scaricamento (barra e «Annulla»); italiano e inglese. Prove di logica sulla vista tramite lo stato: `downloadButtonIsVisibleOnlyWhenTheModelIsNotReady`, `depthSegmentIsDisabledWhileTheModelIsMissing`, `createIsDisabledWithoutAnImage`, `sendIsDisabledWithoutMapsOrWhenInactive`.
- [ ] **Step 2:** falliscono. **Step 3:** vista in un solo tab sul modello di `SphereLightView`: colonna di sinistra con zona di trascinamento (`.onDrop(of: [.image, .fileURL, .url])` come `LAListCard.drop`: prima i dati d'immagine, poi il file; un indirizzo da solo non si segue) e «Apri…» (`NSOpenPanel`), selettore a tre voci, «Crea», «Manda al Moodboard», riga di stato; a destra il pannello con le due anteprime affiancate («Depth», «Pose») o l'immagine di partenza.
- [ ] **Step 4:** verdi; `swift build -c release` senza avvisi. **Step 5: Commit** — `feat(depth-pose): the tab, drag and drop, and the app wiring`.

### Task 9: prove con i modelli veri (fuori sandbox)

**Files:** Create `Tests/DepthPoseTests/LiveTests.swift` (attivi solo con `DTHUB_LIVE_DEPTH=1`).

- [ ] **Step 1:** `liveDownloadMatchesTheManifest`: `DPModelStore` vero in una cartella temporanea scarica i tre file da Hugging Face; dimensioni e sha256 corrispondono; la compilazione riesce; `isPresent()`.
- [ ] **Step 2:** `liveDepthOfASyntheticScene`: una scena sintetica (sfondo lontano, un rettangolo grande «vicino» in primo piano) → il rettangolo è **più chiaro** dello sfondo. Se il test dice il contrario, `DepthEstimator.invertsModelOutput` va impostato a `true` nella costruzione di `makeDepth` del plug-in e il test fissa la convenzione. Misurare e annotare il tempo di una predizione.
- [ ] **Step 3:** `liveVisionOnAStickFigureDoesNotCrash`: Vision su un'immagine sintetica (nessuna foto reale nel repo) risponde senza errori (l'elenco può essere vuoto). Il controllo con una persona vera lo fa l'utente (prova a mano 5).
- [ ] **Step 4:** lanciare dalla shell fuori sandbox: `cd Plugins/DepthPose && DTHUB_LIVE_DEPTH=1 swift test --filter LiveTests 2>&1 | grep -E "Test run with|✘|error:"`; riportare nel messaggio finale i tempi e l'esito dell'orientamento. **Step 5: Commit** — `test(depth-pose): live probes behind DTHUB_LIVE_DEPTH`.

### Task 10: documentazione, bundle e prove a mano

**Files:** Create `Plugins/DepthPose/README.md`; Modify `Plugins/README.md`, `README.md`; alla fine `docs/superpowers/backlog.md`, `docs/superpowers/briefing-prossima-sessione.md` e la nota Obsidian (locali, non in git).

- [ ] **Step 1:** `Plugins/DepthPose/README.md` (inglese, sul modello di quello di LoRA Advisor): cosa fa, selettore, dove stanno i dati, sezione **«Network»** (solo il tasto «Download model», solo `huggingface.co`, tre file, 50 MB, nient'altro lascia il Mac; il secondo plug-in a usare la rete), limiti (una immagine alla volta, solo corpo, lato lungo 2048), come si costruisce. `Plugins/README.md`: riga in tabella e link allo zip, e la frase «The only plug-in that uses the network» di LoRA Advisor va corretta. `README.md`: il plug-in nell'elenco e in «Repository layout».
- [ ] **Step 2: verifica completa:** `swift test` in `Plugins/DepthPose`, `Packages` e `PluginKit` tutti verdi; `git status` senza file estranei; controllo dei dati personali nel diff (`git diff main..HEAD -U0 | grep "^+" | grep -i "/Users/existenz\|antoniodachille\|/Volumes/LLM"` vuoto).
- [ ] **Step 3: Commit** — `docs(depth-pose): README of the plug-in and of the plug-ins`.
- [ ] **Step 4:** costruire il bundle (`Plugins/DepthPose/Scripts/build.sh "$TMPDIR/dp"`), verificarlo (`file -b …/Contents/MacOS/DepthPose` → «shared library»; `codesign --verify --deep --strict`) e dare all'utente il comando per installarlo (con `rm -rf` prima, briefing §3).
- [ ] **Step 5: prove a mano per l'utente** (da dare così com'è): 1) il tab senza modello mostra «Scarica il modello» e «Depth» è spenta; 2) scaricare: avanzamento, poi il tasto sparisce e «Depth» si accende; «Annulla» a metà non lascia niente; 3) trascinare un'immagine dal Finder e dal browser; 4) «Crea» con Depth, con Pose, con Entrambe; 5) una foto con una persona intera, una tagliata, una con due persone, una senza nessuno; 6) «Manda al Moodboard» e controllo nel Moodboard (e che un secondo invio sostituisce); 7) usare le mappe con il LoRA/modello di Klein; 8) cambiare progetto: il selettore resta, l'immagine no; 9) chiudere e riaprire DT Hub con il modello già scaricato: il tasto non c'è.
- [ ] **Step 6:** aggiornare backlog (rinviati della spec §12), briefing e Obsidian (nota madre e nota nuova `DT Hub - Depth & Pose`); messaggio finale nel formato del briefing §6 e richiesta di via libera per l'unione.
