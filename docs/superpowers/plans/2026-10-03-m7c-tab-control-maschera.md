# M7c Tab Control — Maschera e inpaint — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Il tab Control ha una sola card **Canvas** con due modalità. **Canvas**: l'immagine intera con il ritaglio, trascinabile (come in M7a). **Disegno**: il canvas come parte a Draw Things, con una toolbar di icone: **Maschera +** e **Maschera −** (la gomma di Draw Things: dipingono e tolgono l'area da rigenerare) e **Pennello** (disegna a colori sull'immagine, in uno strato a parte); Inverti, Svuota, Annulla/Ripeti, Colore, Dimensione; Sfumatura, Margine e "Conserva l'originale" come in Draw Things. Il RUN manda immagine (con il disegno sopra), maschera e impostazioni, e **l'inpaint funziona**. Il tratto è fluido e curvo.

**Architecture:**
- **HubKit** riceve `MaskSettings`, `MaskReference`, `PaintReference`, i campi `mask`/`maskSettings`/`paint` di `ControlInputs`, `GenerationInputs.mask`/`enableInpainting`, `GenerationJob.maskSettings` e `ModelCapabilities.needsInpaintControl`.
- **DTBridge** manda la maschera e le impostazioni nella richiesta (`JobMapper`).
- **HubCore** riceve `MaskBitmap` e `PaintBitmap` (buffer con pennello, gomma, inverti, PNG, geometria vista→maschera, rettangolo toccato), `MaskOverlay` e `PaintOverlay` (immagini per lo schermo aggiornate solo nel rettangolo toccato), `StrokeSmoother` (tratto curvo), `InputComposer` (maschera e disegno nello stesso ritaglio dell'immagine), le operazioni dello store (ogni tratto è un passo della cronologia), gli ingressi del RUN e `CanvasDrawing` (maschera e disegno mentre si disegna).
- **L'app** unisce Canvas e Maschera in `CanvasStage` (due modalità, strati separati), aggiunge i chip nella striscia e i collegamenti nel RUN; il tab passa alla card l'altezza della finestra, così le immagini crescono con essa.

**Tech Stack:** Swift 6, SwiftUI (`Canvas`), macOS 26, Xcode 27, Swift Testing, ImageIO, DrawThings-Swift 2.2.x (solo in DTBridge).

**Spec:** `docs/superpowers/specs/2026-10-01-tab-control-design.md` (sezioni 3, 4, 6, 9; aggiornata il 3 ottobre 2026 con le decisioni sotto).

## Global Constraints

- **Repository e dipendenze:**
  - radice `/Users/existenz/Software developement/DT Hub` (percorsi tra virgolette);
  - branch `m7c-maschera` da `main`;
  - macOS 26, Swift 6, Xcode 27;
  - solo DTBridge importa DrawThings-Swift.
- **Maschera netta, senza morbidezza del pennello** (misurato nel client: un pixel con alfa < 255 è «da rigenerare», altrimenti no; non ci sono mezzi toni). Il bordo si ammorbidisce con la Sfumatura (`maskBlur`) di Draw Things.
- **Misurato dal vivo il 3 ottobre 2026** (SD 1.5 Juggernaut Reborn e FLUX.2 klein, immagine blu con la metà destra mascherata, «papaveri rossi»): la sinistra resta identica e la destra si rigenera a forza 100% (rosso 0,58 e 0,54); a forza 70% la parte mascherata resta blu; `enableInpainting` acceso o spento dà risultati identici. **Quindi: forza automatica 100% con la maschera** (una scelta dell'utente vince) e `enableInpainting` **solo per i modelli con `modifier` `inpainting`** (regola del client; quei modelli non sono installati, la regola per loro non è provata).
- **La maschera e il disegno appartengono all'immagine:** cambiare o togliere l'immagine di partenza li toglie (si annulla); senza immagine non si leggono dal file salvato. Una maschera o un disegno vuoti non esistono (cancellare tutto = niente).
- **Dimensione di lavoro:** il rapporto dell'immagine, lato lungo al massimo 1024 pixel (`MaskBitmap.workingSize`). Al RUN si scala al canvas con interpolazione alta nello stesso ritaglio dell'immagine e si taglia a metà (`InputComposer.mask`).
- **Cronologia unica:** ogni tratto (maschera o Pennello), Inverti e Svuota sono passi della cronologia del tab (20, ⌘Z); ogni passo scrive un PNG nuovo nella cartella `Control` e lo stato tiene il riferimento (`MaskReference`, `PaintReference`); le copie si spazzano come le altre. Le impostazioni della maschera (Sfumatura, Margine, Conserva) **non** sono passi.
- **Nel PNG salvato** finiscono le impostazioni della maschera (`maskSettings` nel job) solo se il RUN aveva una maschera; "Riprendi parametri" le rimette.
- **Stringhe:** ogni testo visibile in `App/Localizable.xcstrings` (en + it), senza riformattare il catalogo; mai una stringa vuota come titolo di un controllo (il test del catalogo la segnala).
- **La logica sta in HubCore (testata); le viste si verificano con la compilazione e con la prova dal vivo (Task 9).**
- **Blocchi `diff`:** sono le modifiche ai file che esistono già su `main`; si salvano in un file e si applicano dalla radice con `git apply --whitespace=nowarn <file>`. I blocchi di codice dei file nuovi si salvano così come sono.
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Se l'app dell'utente è in esecuzione non lanciare altre istanze** (stesso identificatore, stessi dati): compilare con `-derivedDataPath /tmp/…` e chiedere all'utente di chiuderla prima della verifica dal vivo (Task 9).
- **Nomi come in Draw Things (deciso con l'utente, 3 ottobre 2026):** la gomma è ciò che dipinge la maschera, il pennello disegna sull'immagine. Quindi **Maschera +** (dipinge), **Maschera −** (toglie), **Pennello** (colore sull'immagine).
- **Il Pennello è uno strato a parte** (`PaintBitmap`, RGBA a 1024 px al massimo, PNG con trasparenza): il file dell'immagine non si tocca; al RUN si sovrappone all'immagine nello stesso ritaglio (`InputComposer.frame(…, paint:)`). Bordo netto con un pixel di antialiasing; un pixel tiene la copertura più forte (ripassare non ispessisce il bordo). Niente gomma per il disegno: Annulla e "Svuota disegno".
- **Fluidità (misurata nella build Debug):** ricostruire l'anteprima intera a ogni evento costava 94 ms; si aggiorna solo il rettangolo toccato (circa 2 ms per evento). Le immagini per lo schermo (`MaskOverlay`, `PaintOverlay`) e le bitmap stanno in `CanvasDrawing` (classe, in modo che il buffer cambi sul posto); immagine, disegno e maschera sono **strati separati** nella vista, non un unico `Canvas` ridisegnato.
- **Tratto curvo:** `StrokeSmoother` passa per i punti medi dei segmenti e si piega verso i punti intermedi (curva quadratica); è un po' dietro il puntatore e `finish` lo porta all'ultimo punto.
- **Interfaccia (decisa con l'utente provando il prototipo):** una sola card Canvas; selettore Canvas/Disegno largo quanto la card; strumenti e comandi come una riga di sole icone con i nomi nei suggerimenti; nessun testo esplicativo; l'immagine è centrata e prende tutta la larghezza che l'altezza della finestra permette (`controlViewportHeight`).
- **Fuori da M7c:** outpaint e modo «Contieni», Tiled Diffusion 8192 (da rimisurare la fluidità), avviso per una maschera tutta fuori dal ritaglio, gomma per il disegno del Pennello, plug-in.

## Review Focus

- **Coordinate:** il punto della vista → pixel della maschera passa dal ritaglio (`MaskBitmap.point(forViewPoint:…)`), il disegno ha la stessa dimensione di lavoro e le stesse conversioni, e la maschera e il disegno del RUN seguono lo stesso ritaglio dell'immagine (test `MaskGeometryTests`, `theMaskFollowsTheCut`, `paintAtTheTopOfTheMaskIsAtTheTopOfTheCanvas`, `theDrawingIsPutOverTheImageInTheSameCut`, Task 3–4). Un ritaglio forte con la maschera dipinta fuori dal ritaglio (possibile solo spostando il ritaglio dopo) manda una maschera vuota: è nei fuori-perimetro, il revisore dica se lo ritiene da correggere.
- **Maschera o disegno vuoti = niente:** cancellare tutto toglie il riferimento e il chip (test `anEmptyMaskIsNoMask`, `anEmptyDrawingIsNoDrawing`, `invertingAMaskDrawnNothingPaintsEverything`, Task 5).
- **Immagine cambiata o tolta:** maschera e disegno vanno via e tornano con Annulla; non si leggono senza immagine (test `theMaskGoesWithTheImage`, `theDrawingGoesWithTheImage`, `aMaskWithoutAnImageIsNotKept`, `aDrawingWithoutAnImageIsNotKept`, Task 1 e 5).
- **Copia sparita all'avvio:** maschera o disegno si scartano con un avviso, l'immagine resta (test `aMaskWhoseCopyIsGoneIsDroppedWithANotice`, `theDrawingSurvivesARestartAndALostCopyIsDropped`, Task 5).
- **Immagine enorme:** maschera e disegno restano a 1024 pixel e l'immagine si decodifica alla dimensione che serve al canvas (test `theMaskIsDrawnAtTheWorkingSizeOfTheImage`, Task 5).
- **Pennello ai bordi e fuori:** non scrive fuori dal buffer e restituisce il rettangolo toccato (test `theBrushStaysInsideTheMask`, `theBrushStaysInsideTheDrawing`, `aStrokeReportsTheRectangleItTouched`, Task 3).
- **Aggiornamento parziale = ricostruzione intera:** `MaskOverlay`/`PaintOverlay` aggiornate a rettangoli danno gli stessi byte della ricostruzione (test `updatingOnlyWhatAStrokeTouchedGivesTheSameOverlayAsRebuilding`, Task 3).
- **Tratto curvo:** passa per i punti medi, non taglia né supera gli angoli, finisce sull'ultimo punto (test `StrokeSmootherTests`, `aSparseStrokeIsCurvedNotCornered`, Task 3 e 6).
- **Cronologia:** i passi di maschera, disegno e immagini condividono i 20; una copia usata dalla cronologia non si cancella (test `eachStrokeIsAStepOfTheHistory`, `eachDrawingStrokeIsAStepOfTheHistory`, `theCopiesOfOldMasksAreSweptWhenNothingRefersToThem`, Task 5).
- **`CanvasDrawing`:** un tratto fatto lì non si rilegge dallo store; annulla/ripeti sì (test `aStrokeCommittedHereIsNotReadBack`, `undoAndRedoBringTheMaskBack`, Task 6).
- **Vista:** `CanvasStage` non ha test (codice di vista): il revisore controlli a occhio la mappatura dei gesti, la differenza tra le due modalità (il trascinamento del ritaglio resta solo in Canvas) e che l'altezza della finestra arrivi alle immagini.
- **`enableInpainting` per i modelli inpainting** non è provato dal vivo (nessun modello inpainting installato): il revisore controlli la regola contro il client.

---

### Task 1: Tipi della maschera (HubKit)

**Files:**
- Modify: `Packages/Sources/HubKit/Control/ControlInputs.swift`, `Packages/Sources/HubKit/Generation/GenerationJob.swift`, `Packages/Sources/HubKit/Catalog/ModelCapabilities.swift`
- Test: `Packages/Tests/HubKitTests/MaskContractTests.swift` (nuovo)

**Interfaces:**
- Produces (HubKit, `public`):
  - `struct MaskSettings: Equatable, Codable, Sendable` (`blur: Double` 1,5; `outset: Int` 0; `preserveOriginal: Bool` true; `static let blurRange = 0.0...30.0`, `outsetRange = 0...100`; `clamped()`; lettura permissiva che applica i limiti);
  - `struct MaskReference: Equatable, Codable, Sendable` (`fileName: String`, `coverage: Double` 0…1) e `struct PaintReference: Equatable, Codable, Sendable` (`fileName: String`, il PNG del disegno del Pennello);
  - `ControlInputs.mask: MaskReference?`, `paint: PaintReference?` (lette solo se c'è l'immagine) e `maskSettings: MaskSettings`; l'iniziatore ha `mask: MaskReference? = nil, maskSettings: MaskSettings = MaskSettings(), paint: PaintReference? = nil`; `effectiveStrength(editModel:)` dà 1,0 anche con una maschera;
  - `GenerationInputs.mask: CGImage?` (trasparente = da rigenerare) e `enableInpainting: Bool`; `init(image:hints:mask:enableInpainting:)`; `isEmpty` considera la maschera;
  - `GenerationJob.maskSettings: MaskSettings?` (nil senza maschera; lettura permissiva; l'iniziatore ha `maskSettings: MaskSettings? = nil`);
  - `ModelCapabilities.needsInpaintControl: Bool` (`modifier == "inpainting"`).
- Consumes: `ControlInputs`, `GenerationInputs`, `GenerationJob`, `ModelCapabilities` (M7a/b).

- [ ] **Step 1: Creare il ramo e scrivere i test**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git switch main && git switch -c m7c-maschera
```

```swift
import Foundation
import Testing

@testable import HubKit

struct MaskContractTests {
  @Test func maskSettingsStartAtDrawThingsDefaults() {
    let settings = MaskSettings()
    #expect(settings.blur == 1.5 && settings.outset == 0 && settings.preserveOriginal)
  }

  @Test func savedInputsWithoutAMaskStillLoad() throws {
    let old = Data(#"{"framing":{"mode":"fill","offsetX":0,"offsetY":0}}"#.utf8)
    let inputs = try JSONDecoder().decode(ControlInputs.self, from: old)
    #expect(inputs.mask == nil)
    #expect(inputs.maskSettings == MaskSettings())
  }

  @Test func aMaskWithoutAnImageIsNotKept() throws {
    let json = Data(#"{"mask":{"fileName":"x.png","coverage":0.2}}"#.utf8)
    #expect(try JSONDecoder().decode(ControlInputs.self, from: json).mask == nil)
  }

  @Test func aDrawingWithoutAnImageIsNotKept() throws {
    let json = Data(#"{"paint":{"fileName":"x.png"}}"#.utf8)
    #expect(try JSONDecoder().decode(ControlInputs.self, from: json).paint == nil)
    let withImage = Data(
      #"{"image":{"id":"7CB25000-FFE8-4BF4-B1F5-EB90BFCD8837","name":"a.png","pixelWidth":8,"pixelHeight":8,"source":{"result":{}},"fileName":"a.png"},"paint":{"fileName":"x.png"}}"#
        .utf8)
    #expect(try JSONDecoder().decode(ControlInputs.self, from: withImage).paint == PaintReference(fileName: "x.png"))
  }

  @Test func damagedMaskSettingsFallBackToTheDefaults() throws {
    let json = Data(#"{"maskSettings":{"blur":"lots","outset":999}}"#.utf8)
    let settings = try JSONDecoder().decode(ControlInputs.self, from: json).maskSettings
    #expect(settings.blur == 1.5)
    #expect(settings.outset == MaskSettings.outsetRange.upperBound)
  }

  @Test func aJobCarriesTheMaskSettingsAndOldJobsLoad() throws {
    var job = GenerationJob(prompt: "x", model: "m", parameters: GenerationParameters())
    #expect(job.maskSettings == nil)
    job.maskSettings = MaskSettings(blur: 3, outset: 4, preserveOriginal: false)
    let back = try JSONDecoder().decode(GenerationJob.self, from: JSONEncoder().encode(job))
    #expect(back.maskSettings == job.maskSettings)
    let old = Data(#"{"prompt":"x","model":"m","parameters":{}}"#.utf8)
    #expect(try JSONDecoder().decode(GenerationJob.self, from: old).maskSettings == nil)
  }

  @Test func onlyAnInpaintingModelNeedsTheInpaintControl() {
    func capabilities(_ modifier: String?) -> ModelCapabilities {
      ModelCapabilities(
        guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
        clipSkip: false, nativeSize: nil, modifier: modifier)
    }
    #expect(capabilities("inpainting").needsInpaintControl)
    #expect(!capabilities("kontext").needsInpaintControl)
    #expect(!capabilities(nil).needsInpaintControl)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter HubKitTests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'MaskSettings' in scope`.

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/HubKit/Control/ControlInputs.swift b/Packages/Sources/HubKit/Control/ControlInputs.swift
index b881766..c49716d 100644
--- a/Packages/Sources/HubKit/Control/ControlInputs.swift
+++ b/Packages/Sources/HubKit/Control/ControlInputs.swift
@@ -63,6 +63,63 @@ public struct Framing: Equatable, Codable, Sendable {
   }
 }
 
+/// What Draw Things does with the inpaint mask (tab Control spec §3). The defaults are Draw Things'.
+public struct MaskSettings: Equatable, Codable, Sendable {
+  /// How much the edge of the mask is softened (`maskBlur`).
+  public var blur: Double
+  /// How far the area around the mask is taken in (`maskBlurOutset`).
+  public var outset: Int
+  /// Keeps the original pixels outside the mask after the generation (`preserveOriginalAfterInpaint`).
+  public var preserveOriginal: Bool
+
+  public static let blurRange = 0.0...30.0
+  public static let outsetRange = 0...100
+
+  public init(blur: Double = 1.5, outset: Int = 0, preserveOriginal: Bool = true) {
+    self.blur = blur
+    self.outset = outset
+    self.preserveOriginal = preserveOriginal
+  }
+
+  public func clamped() -> MaskSettings {
+    MaskSettings(
+      blur: min(Self.blurRange.upperBound, max(Self.blurRange.lowerBound, blur)),
+      outset: min(Self.outsetRange.upperBound, max(Self.outsetRange.lowerBound, outset)),
+      preserveOriginal: preserveOriginal)
+  }
+
+  public init(from decoder: any Decoder) throws {
+    let container = try decoder.container(keyedBy: CodingKeys.self)
+    blur = (try? container.decodeIfPresent(Double.self, forKey: .blur)) ?? 1.5
+    outset = (try? container.decodeIfPresent(Int.self, forKey: .outset)) ?? 0
+    preserveOriginal = (try? container.decodeIfPresent(Bool.self, forKey: .preserveOriginal)) ?? true
+    self = clamped()
+  }
+}
+
+/// The inpaint mask the tab holds: a PNG copy in the Control folder, drawn in the start image's
+/// own coordinates (so it follows the framing), and how much of the image it covers.
+public struct MaskReference: Equatable, Codable, Sendable {
+  public let fileName: String
+  /// 0…1, the share of the image the mask covers.
+  public let coverage: Double
+
+  public init(fileName: String, coverage: Double) {
+    self.fileName = fileName
+    self.coverage = coverage
+  }
+}
+
+/// The drawing the tab holds over the start image (the Brush tool): a PNG with transparency in the
+/// Control folder, in the image's own coordinates, put over the image when a RUN is prepared.
+public struct PaintReference: Equatable, Codable, Sendable {
+  public let fileName: String
+
+  public init(fileName: String) {
+    self.fileName = fileName
+  }
+}
+
 /// One image of the Moodboard (tab Control spec §3): its picture and the switch. Every picture
 /// that is on counts the same: Draw Things gives the same weight to every picture above 0 on the
 /// models that read the Moodboard (measured, 2 October 2026), so there are no shares yet (§4.1).
@@ -92,14 +149,24 @@ public struct ControlInputs: Equatable, Codable, Sendable {
   /// The Moodboard, in the order of the thumbnails.
   public var moodboard: [MoodboardEntry]
   public var framing: Framing
-  /// nil = automatic: 100 % for the Edit models, 70 % for the others (at 100 % a normal image-
-  /// to-image ignores the image). The user's choice, once made, wins.
+  /// The inpaint mask, over the start image. Never without it: the mask goes when the image goes.
+  public var mask: MaskReference?
+  public var maskSettings: MaskSettings
+  /// The Brush drawing over the start image. Like the mask, it goes when the image goes.
+  public var paint: PaintReference?
+  /// nil = automatic: 100 % for the Edit models and with a mask (the painted area is regenerated
+  /// whole), 70 % for the others (at 100 % a normal image-to-image ignores the image). The
+  /// user's choice, once made, wins.
   public var strength: Double?
 
   public init(
     image: ReferenceImage? = nil, framing: Framing = Framing(), strength: Double? = nil,
-    moodboard: [MoodboardEntry] = []
+    moodboard: [MoodboardEntry] = [], mask: MaskReference? = nil, maskSettings: MaskSettings = MaskSettings(),
+    paint: PaintReference? = nil
   ) {
+    self.paint = paint
+    self.mask = mask
+    self.maskSettings = maskSettings
     self.image = image
     self.framing = framing
     self.strength = strength
@@ -108,7 +175,7 @@ public struct ControlInputs: Equatable, Codable, Sendable {
 
   /// The strength that is sent and shown, within 0…1.
   public func effectiveStrength(editModel: Bool) -> Double {
-    min(1, max(0, strength ?? (editModel ? 1.0 : 0.7)))
+    min(1, max(0, strength ?? (editModel || mask != nil ? 1.0 : 0.7)))
   }
 
   /// Lenient, like the other saved files: a missing or unreadable field takes its default.
@@ -117,6 +184,10 @@ public struct ControlInputs: Equatable, Codable, Sendable {
     image = try? container.decodeIfPresent(ReferenceImage.self, forKey: .image)
     framing = (try? container.decodeIfPresent(Framing.self, forKey: .framing)) ?? Framing()
     strength = try? container.decodeIfPresent(Double.self, forKey: .strength)
+    // A mask belongs to an image: one without it is not kept.
+    mask = image == nil ? nil : try? container.decodeIfPresent(MaskReference.self, forKey: .mask)
+    maskSettings = (try? container.decodeIfPresent(MaskSettings.self, forKey: .maskSettings)) ?? MaskSettings()
+    paint = image == nil ? nil : try? container.decodeIfPresent(PaintReference.self, forKey: .paint)
     moodboard = ((try? container.decodeIfPresent([Lossy<MoodboardEntry>].self, forKey: .moodboard)) ?? [])
       .compactMap(\.value)
   }
@@ -126,17 +197,23 @@ public struct ControlInputs: Equatable, Codable, Sendable {
 /// `Codable`: images do not go into the PNG metadata.
 public struct GenerationInputs: Sendable {
   public var image: CGImage?
+  /// The inpaint mask at the canvas size: transparent pixels are regenerated, opaque ones kept.
+  public var mask: CGImage?
+  /// Asks Draw Things for its inpaint control (see `JobMapper`).
+  public var enableInpainting: Bool
   /// The Moodboard's pictures that are on, in order.
   public var hints: [GenerationHint]
 
-  public init(image: CGImage? = nil, hints: [GenerationHint] = []) {
+  public init(image: CGImage? = nil, hints: [GenerationHint] = [], mask: CGImage? = nil, enableInpainting: Bool = false) {
     self.image = image
     self.hints = hints
+    self.mask = mask
+    self.enableInpainting = enableInpainting
   }
 
   public static let none = GenerationInputs()
 
-  public var isEmpty: Bool { image == nil && hints.isEmpty }
+  public var isEmpty: Bool { image == nil && mask == nil && hints.isEmpty }
 }
 
 /// One Moodboard picture of a RUN: encoded image data (PNG) and its weight (1: all count the same).
```

```diff
diff --git a/Packages/Sources/HubKit/Generation/GenerationJob.swift b/Packages/Sources/HubKit/Generation/GenerationJob.swift
index 1beba2d..5f406a9 100644
--- a/Packages/Sources/HubKit/Generation/GenerationJob.swift
+++ b/Packages/Sources/HubKit/Generation/GenerationJob.swift
@@ -12,10 +12,12 @@ public struct GenerationJob: Equatable, Codable, Sendable {
   public var imageStrength: Double?
   /// How many Moodboard pictures went with this RUN (0 without a Moodboard).
   public var moodboardCount: Int
+  /// What Draw Things does with the mask; nil when the RUN has no mask.
+  public var maskSettings: MaskSettings?
 
   public init(
     prompt: String, negativePrompt: String = "", model: String, parameters: GenerationParameters,
-    imageStrength: Double? = nil, moodboardCount: Int = 0
+    imageStrength: Double? = nil, moodboardCount: Int = 0, maskSettings: MaskSettings? = nil
   ) {
     self.prompt = prompt
     self.negativePrompt = negativePrompt
@@ -23,6 +25,7 @@ public struct GenerationJob: Equatable, Codable, Sendable {
     self.parameters = parameters
     self.imageStrength = imageStrength
     self.moodboardCount = moodboardCount
+    self.maskSettings = maskSettings
   }
 
   /// What Draw Things receives: the trigger words of the job's LoRAs, in order, then the
@@ -42,6 +45,7 @@ public struct GenerationJob: Equatable, Codable, Sendable {
     parameters = try container.decode(GenerationParameters.self, forKey: .parameters)
     imageStrength = try? container.decodeIfPresent(Double.self, forKey: .imageStrength)
     moodboardCount = (try? container.decodeIfPresent(Int.self, forKey: .moodboardCount)) ?? 0
+    maskSettings = try? container.decodeIfPresent(MaskSettings.self, forKey: .maskSettings)
   }
 }
 
```

```diff
diff --git a/Packages/Sources/HubKit/Catalog/ModelCapabilities.swift b/Packages/Sources/HubKit/Catalog/ModelCapabilities.swift
index 0156d00..e14c42b 100644
--- a/Packages/Sources/HubKit/Catalog/ModelCapabilities.swift
+++ b/Packages/Sources/HubKit/Catalog/ModelCapabilities.swift
@@ -19,6 +19,10 @@ public struct ModelCapabilities: Equatable, Sendable {
   /// `inpainting`, `depth`… nil when the spec has none.
   public var modifier: String?
 
+  /// An inpainting model (SD inpainting, FLUX Fill...): Draw Things wants its inpaint control for
+  /// the mask. The other models take a mask without it (measured on SD 1.5 and FLUX.2 klein).
+  public var needsInpaintControl: Bool { modifier == "inpainting" }
+
   /// Edit and in-context models: the canvas image is the one to modify, and the Moodboard
   /// brings extra references (tab Control spec §2).
   public var isEditModel: Bool {
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v started`
Expected: HubKit `63 tests … passed` (7 nuovi), HubCore 238, DTBridge 57, Catalog 6, LLMBridge 6 (totale **370**).

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: tipi della maschera (impostazioni, riferimento, ingressi, job, controllo inpaint)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: La maschera nella richiesta a Draw Things (DTBridge)

**Files:**
- Modify: `Packages/Sources/DTBridge/JobMapper.swift`
- Test: `Packages/Tests/DTBridgeTests/JobMapperTests.swift`

**Interfaces:**
- Consumes: `GenerationInputs.mask`/`enableInpainting`, `GenerationJob.maskSettings`, `MaskSettings` (Task 1).
- Produces: `JobMapper.request(for:inputs:)` con un'immagine e una maschera imposta `request.mask`, `maskBlur`, `maskBlurOutset` (limitati), `preserveOriginalAfterInpaint` (da `job.maskSettings`, o i valori predefiniti di Draw Things senza) e `enableInpainting = inputs.enableInpainting`. Una maschera **senza immagine non parte** (la richiesta resta senza maschera e senza modifiche alla configurazione).

- [ ] **Step 1: Scrivere i test che falliscono**

```diff
diff --git a/Packages/Tests/DTBridgeTests/JobMapperTests.swift b/Packages/Tests/DTBridgeTests/JobMapperTests.swift
index dfea68a..76dd755 100644
--- a/Packages/Tests/DTBridgeTests/JobMapperTests.swift
+++ b/Packages/Tests/DTBridgeTests/JobMapperTests.swift
@@ -96,6 +96,53 @@ struct JobMapperTests {
     }
   }
 
+  @Test func sendsTheMaskWithItsSettings() throws {
+    let image = try #require(TestImages.make(width: 64, height: 48))
+    let mask = try #require(TestImages.make(width: 64, height: 48))
+    var job = GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: GenerationParameters(width: 64, height: 48))
+    job.imageStrength = 1
+    job.maskSettings = MaskSettings(blur: 4, outset: 12, preserveOriginal: false)
+    let request = try JobMapper.request(for: job, inputs: GenerationInputs(image: image, mask: mask))
+    #expect(request.mask === mask)
+    #expect(request.configuration.maskBlur == 4)
+    #expect(request.configuration.maskBlurOutset == 12)
+    #expect(!request.configuration.preserveOriginalAfterInpaint)
+    // No inpaint control unless the model needs it.
+    #expect(!request.configuration.enableInpainting)
+    let control = try JobMapper.request(for: job, inputs: GenerationInputs(image: image, mask: mask, enableInpainting: true))
+    #expect(control.configuration.enableInpainting)
+  }
+
+  @Test func aMaskWithoutSettingsGetsDrawThingsDefaults() throws {
+    let image = try #require(TestImages.make(width: 32, height: 32))
+    let mask = try #require(TestImages.make(width: 32, height: 32))
+    let job = GenerationJob(prompt: "x", model: "m.ckpt", parameters: GenerationParameters(width: 64, height: 64))
+    let request = try JobMapper.request(for: job, inputs: GenerationInputs(image: image, mask: mask))
+    #expect(request.configuration.maskBlur == 1.5)
+    #expect(request.configuration.maskBlurOutset == 0)
+    #expect(request.configuration.preserveOriginalAfterInpaint)
+  }
+
+  @Test func aMaskWithoutAnImageIsNotSent() throws {
+    let mask = try #require(TestImages.make(width: 32, height: 32))
+    var job = GenerationJob(prompt: "x", model: "m.ckpt", parameters: .default)
+    job.maskSettings = MaskSettings(blur: 9, outset: 9, preserveOriginal: false)
+    let request = try JobMapper.request(for: job, inputs: GenerationInputs(mask: mask, enableInpainting: true))
+    #expect(request.mask == nil)
+    #expect(request.configuration.maskBlur != 9)
+    #expect(!request.configuration.enableInpainting)
+  }
+
+  @Test func theMaskSettingsAreClampedBeforeTheyAreSent() throws {
+    let image = try #require(TestImages.make(width: 32, height: 32))
+    let mask = try #require(TestImages.make(width: 32, height: 32))
+    var job = GenerationJob(prompt: "x", model: "m.ckpt", parameters: .default)
+    job.maskSettings = MaskSettings(blur: 900, outset: 900, preserveOriginal: true)
+    let request = try JobMapper.request(for: job, inputs: GenerationInputs(image: image, mask: mask))
+    #expect(request.configuration.maskBlur == Float(MaskSettings.blurRange.upperBound))
+    #expect(request.configuration.maskBlurOutset == Int32(MaskSettings.outsetRange.upperBound))
+  }
+
   @Test func sendsTheNegativePromptAndTheLoRAs() {
     let parameters = GenerationParameters(loras: [
       LoRASelection(file: "style.safetensors", weight: 0.75, mode: .base), LoRASelection(file: "detail.safetensors"),
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter DTBridgeTests 2>&1 | grep -E "error:|Expectation failed" | grep -v started | head -3`
Expected: i test della maschera falliscono (aspettativa non soddisfatta: `request.mask` è nil).

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/DTBridge/JobMapper.swift b/Packages/Sources/DTBridge/JobMapper.swift
index ab6489c..33311f3 100644
--- a/Packages/Sources/DTBridge/JobMapper.swift
+++ b/Packages/Sources/DTBridge/JobMapper.swift
@@ -1,3 +1,4 @@
+import CoreGraphics
 import DrawThingsClient
 import HubKit
 
@@ -18,6 +19,16 @@ enum JobMapper {
     // The start image and its strength come from the Control tab, after the JSON editor's
     // extra settings: they win. Without an image the RUN stays text-to-image.
     if inputs.image != nil, let strength = job.imageStrength { configuration.strength = Float(strength) }
+    // The mask needs an image under it; Draw Things regenerates the transparent pixels.
+    var mask: CGImage?
+    if let drawn = inputs.mask, inputs.image != nil {
+      let settings = (job.maskSettings ?? MaskSettings()).clamped()
+      configuration.maskBlur = Float(settings.blur)
+      configuration.maskBlurOutset = Int32(settings.outset)
+      configuration.preserveOriginalAfterInpaint = settings.preserveOriginal
+      configuration.enableInpainting = inputs.enableInpainting
+      mask = drawn
+    }
     var hints = HintBuilder()
     for hint in inputs.hints { hints.addMoodboardImage(hint.imageData, weight: Float(hint.weight)) }
     let built: [HintProto]
@@ -28,7 +39,7 @@ enum JobMapper {
     }
     return GenerationRequest(
       prompt: job.promptWithTriggers, negativePrompt: job.negativePrompt,
-      configuration: configuration, image: inputs.image, hints: built)
+      configuration: configuration, image: inputs.image, mask: mask, hints: built)
   }
 
   /// The Draw Things configuration for a model and parameters: clamped, the Advanced cards
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v started`
Expected: DTBridge `61 tests … passed`; totale 63 + 238 + 61 + 6 + 6 = **374**.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: la maschera e le sue impostazioni partono per Draw Things

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Maschera e disegno come buffer (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Control/MaskBitmap.swift`, `MaskOverlay.swift`, `PaintBitmap.swift`, `PaintOverlay.swift`, `StrokeSmoother.swift`
- Test: `Packages/Tests/HubCoreTests/MaskBitmapTests.swift`, `PaintBitmapTests.swift`, `StrokeSmootherTests.swift` (nuovi)

**Interfaces:**
- Produces (HubCore, `public`):
  - `struct MaskBitmap: Equatable, Sendable`: `width`, `height`, `pixels` (255 = da rigenerare), `static let maxSide = 1024`, `init(width:height:)`, `static workingSize(imageWidth:imageHeight:)`, `isEmpty`, `coverage`, `@discardableResult mutating stroke(from:to:radius:erase:) -> CGRect` (pennello rotondo, un pixel di antialiasing, restituisce il rettangolo toccato o `.zero`), `invert()`, `clear()`, `pngData()`, `init?(image: CGImage)`, `point(forViewPoint:viewSize:crop:imageWidth:)`, `brushRadius(diameter:canvasWidth:crop:imageWidth:)`, `grayImage()` (interno);
  - `final class MaskOverlay`: `init?(width:height:red:green:blue:opacity:)`, `rebuild(from:)`, `update(from:rect:)`, `image()` (l'anteprima colorata della maschera, aggiornata a rettangoli);
  - `struct PaintBitmap: Equatable, Sendable`: RGBA con alfa non premoltiplicato, `init(width:height:)`, `isEmpty`, `alpha(x:y:)`, `color(x:y:)`, `@discardableResult mutating stroke(from:to:radius:red:green:blue:) -> CGRect`, `clear()`, `cgImage()`, `pngData()`, `init?(image:)`;
  - `final class PaintOverlay`: `init?(width:height:)`, `rebuild(from:)`, `update(from:rect:)`, `image()`;
  - `struct StrokeSmoother: Equatable, Sendable`: `isActive`, `mutating add(_:spacing:) -> [CGPoint]` (i punti da unire con segmenti: curva quadratica tra i punti medi), `mutating finish() -> [CGPoint]`.

- [ ] **Step 1: Scrivere i test che falliscono**

```swift
import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing

@testable import HubCore

struct MaskBitmapTests {
  func painted(_ bitmap: MaskBitmap, _ x: Int, _ y: Int) -> Bool { bitmap.pixels[y * bitmap.width + x] >= 128 }

  @Test func theWorkingSizeKeepsTheRatioAndCapsTheLongestSide() {
    #expect(MaskBitmap.workingSize(imageWidth: 4000, imageHeight: 2000) == (1024, 512))
    #expect(MaskBitmap.workingSize(imageWidth: 600, imageHeight: 800) == (600, 800))
    #expect(MaskBitmap.workingSize(imageWidth: 1000, imageHeight: 3000) == (341, 1024))
  }

  @Test func aNewMaskIsEmpty() {
    let mask = MaskBitmap(width: 40, height: 30)
    #expect(mask.isEmpty)
    #expect(mask.coverage == 0)
  }

  @Test func theBrushPaintsARoundSpot() {
    var mask = MaskBitmap(width: 100, height: 100)
    mask.stroke(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 50), radius: 10, erase: false)
    #expect(painted(mask, 50, 50))
    #expect(painted(mask, 58, 50))
    #expect(!painted(mask, 62, 50))
    // Round, not square: the corner of the square around the spot is clear.
    #expect(!painted(mask, 58, 58))
    #expect(!mask.isEmpty)
  }

  @Test func aStrokeLeavesNoGapBetweenItsEnds() {
    var mask = MaskBitmap(width: 200, height: 40)
    mask.stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 180, y: 20), radius: 4, erase: false)
    for x in 20...180 { #expect(painted(mask, x, 20)) }
    #expect(!painted(mask, 100, 30))
  }

  @Test func theEraserTakesPaintAwayAndLeavesTheRest() {
    var mask = MaskBitmap(width: 100, height: 100)
    mask.stroke(from: CGPoint(x: 20, y: 50), to: CGPoint(x: 80, y: 50), radius: 8, erase: false)
    mask.stroke(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 50), radius: 8, erase: true)
    #expect(!painted(mask, 50, 50))
    #expect(painted(mask, 30, 50))
    #expect(painted(mask, 70, 50))
  }

  @Test func theBrushStaysInsideTheMask() {
    var mask = MaskBitmap(width: 50, height: 50)
    mask.stroke(from: CGPoint(x: -30, y: -30), to: CGPoint(x: 5, y: 5), radius: 6, erase: false)
    mask.stroke(from: CGPoint(x: 45, y: 45), to: CGPoint(x: 90, y: 90), radius: 6, erase: false)
    #expect(painted(mask, 0, 0))
    #expect(painted(mask, 49, 49))
    mask.stroke(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 600, y: 600), radius: 6, erase: false)
  }

  @Test func invertingSwapsPaintedAndClear() {
    var mask = MaskBitmap(width: 20, height: 20)
    mask.stroke(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5), radius: 3, erase: false)
    let before = mask.coverage
    mask.invert()
    #expect(abs(mask.coverage - (1 - before)) < 0.01)
    #expect(!painted(mask, 5, 5))
    #expect(painted(mask, 19, 19))
  }

  @Test func clearingEmptiesTheMask() {
    var mask = MaskBitmap(width: 20, height: 20)
    mask.invert()
    #expect(mask.coverage == 1)
    mask.clear()
    #expect(mask.isEmpty)
  }

  @Test func theCoverageIsTheShareOfPaintedPixels() {
    var mask = MaskBitmap(width: 10, height: 10)
    for y in 0..<10 { mask.stroke(from: CGPoint(x: 0.5, y: Double(y) + 0.5), to: CGPoint(x: 4.5, y: Double(y) + 0.5), radius: 0.6, erase: false) }
    #expect(mask.coverage > 0.4 && mask.coverage < 0.6)
  }

  @Test func aPNGBringsTheSameMaskBack() throws {
    var mask = MaskBitmap(width: 64, height: 48)
    mask.stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 30), radius: 5, erase: false)
    let data = try #require(mask.pngData())
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let back = try #require(MaskBitmap(image: image))
    #expect(back.width == 64 && back.height == 48)
    #expect(back == mask)
  }
  @Test func aStrokeReportsTheRectangleItTouched() {
    var mask = MaskBitmap(width: 100, height: 100)
    let dirty = mask.stroke(from: CGPoint(x: 30, y: 40), to: CGPoint(x: 60, y: 40), radius: 5, erase: false)
    #expect(dirty.minX <= 25 && dirty.maxX >= 65 && dirty.minY <= 35 && dirty.maxY >= 45)
    #expect(dirty.width < 60 && dirty.height < 20)
    // A segment out of the mask touches nothing.
    #expect(mask.stroke(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 600, y: 600), radius: 5, erase: false) == .zero)
  }
}

struct MaskOverlayTests {
  func bytes(_ overlay: MaskOverlay) throws -> [UInt8] {
    let image = try #require(overlay.image())
    return Array(try #require(image.dataProvider?.data as Data?))
  }

  @Test func theOverlayIsClearWhereNothingIsPainted() throws {
    var mask = MaskBitmap(width: 10, height: 10)
    mask.stroke(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5), radius: 2, erase: false)
    let overlay = try #require(MaskOverlay(width: 10, height: 10, red: 255, green: 140, blue: 0, opacity: 0.5))
    overlay.rebuild(from: mask)
    let image = try #require(overlay.image())
    #expect(image.width == 10 && image.height == 10)
    let data = try bytes(overlay)
    #expect(data[3] == 0)  // top-left corner: nothing painted
    let centre = (5 * 10 + 5) * 4
    #expect(data[centre + 3] > 100)
    #expect(data[centre] > data[centre + 2])  // orange: more red than blue
  }

  @Test func updatingOnlyWhatAStrokeTouchedGivesTheSameOverlayAsRebuilding() throws {
    var mask = MaskBitmap(width: 120, height: 80)
    let incremental = try #require(MaskOverlay(width: 120, height: 80, red: 255, green: 140, blue: 0, opacity: 0.55))
    for step in 0..<8 {
      let start = CGPoint(x: 10 + Double(step) * 12, y: 20 + Double(step) * 5)
      let dirty = mask.stroke(from: start, to: CGPoint(x: start.x + 20, y: start.y + 3), radius: 6, erase: step % 3 == 2)
      incremental.update(from: mask, rect: dirty)
    }
    let whole = try #require(MaskOverlay(width: 120, height: 80, red: 255, green: 140, blue: 0, opacity: 0.55))
    whole.rebuild(from: mask)
    #expect(try bytes(incremental) == bytes(whole))
  }

  @Test func anOverlayOfAnotherSizeIsLeftAlone() throws {
    let overlay = try #require(MaskOverlay(width: 10, height: 10, red: 1, green: 2, blue: 3, opacity: 1))
    var mask = MaskBitmap(width: 20, height: 20)
    mask.invert()
    overlay.rebuild(from: mask)
    #expect(try bytes(overlay).allSatisfy { $0 == 0 })
  }
}

struct MaskGeometryTests {
  @Test func theWholeImageInTheViewMapsCornerToCorner() {
    let mask = MaskBitmap(width: 100, height: 50)
    let crop = CGRect(x: 0, y: 0, width: 200, height: 100)
    let view = CGSize(width: 400, height: 200)
    #expect(mask.point(forViewPoint: .zero, viewSize: view, crop: crop, imageWidth: 200) == CGPoint(x: 0, y: 0))
    #expect(mask.point(forViewPoint: CGPoint(x: 400, y: 200), viewSize: view, crop: crop, imageWidth: 200) == CGPoint(x: 100, y: 50))
    #expect(mask.point(forViewPoint: CGPoint(x: 200, y: 100), viewSize: view, crop: crop, imageWidth: 200) == CGPoint(x: 50, y: 25))
  }

  @Test func aCutShowsOnlyItsPartOfTheMask() {
    let mask = MaskBitmap(width: 100, height: 50)
    // The right half of a 200×100 image fills the view.
    let crop = CGRect(x: 100, y: 0, width: 100, height: 100)
    let view = CGSize(width: 100, height: 100)
    #expect(mask.point(forViewPoint: .zero, viewSize: view, crop: crop, imageWidth: 200) == CGPoint(x: 50, y: 0))
    #expect(mask.point(forViewPoint: CGPoint(x: 100, y: 100), viewSize: view, crop: crop, imageWidth: 200) == CGPoint(x: 100, y: 50))
  }

  @Test func theBrushIsMeasuredOnTheCanvas() {
    let mask = MaskBitmap(width: 512, height: 512)
    // A 1024-pixel image shown whole on a 1024 canvas, mask at half size: a 100 px brush is 25 mask px of radius.
    let crop = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    #expect(mask.brushRadius(diameter: 100, canvasWidth: 1024, crop: crop, imageWidth: 1024) == 25)
    // A cut of half the image on the same canvas magnifies it: the same brush covers half as much of the image.
    let cut = CGRect(x: 0, y: 0, width: 512, height: 1024)
    #expect(mask.brushRadius(diameter: 100, canvasWidth: 1024, crop: cut, imageWidth: 1024) == 12.5)
  }
}
```

```swift
import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import HubCore

struct PaintBitmapTests {
  @Test func aNewDrawingIsEmpty() {
    #expect(PaintBitmap(width: 20, height: 10).isEmpty)
  }

  @Test func theBrushDrawsARoundSpotInTheChosenColour() {
    var paint = PaintBitmap(width: 100, height: 100)
    paint.stroke(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 50), radius: 10, red: 200, green: 30, blue: 20)
    #expect(!paint.isEmpty)
    #expect(paint.alpha(x: 50, y: 50) == 255)
    let colour = paint.color(x: 50, y: 50)
    #expect(colour.red == 200 && colour.green == 30 && colour.blue == 20)
    #expect(paint.alpha(x: 58, y: 50) == 255)
    #expect(paint.alpha(x: 63, y: 50) == 0)
    #expect(paint.alpha(x: 58, y: 58) == 0)
  }

  @Test func aNewColourPaintsOverTheOldOne() {
    var paint = PaintBitmap(width: 60, height: 20)
    paint.stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 10), radius: 5, red: 255, green: 0, blue: 0)
    paint.stroke(from: CGPoint(x: 30, y: 10), to: CGPoint(x: 30, y: 10), radius: 5, red: 0, green: 0, blue: 255)
    #expect(paint.color(x: 30, y: 10).blue == 255)
    #expect(paint.color(x: 15, y: 10).red == 255)
  }

  @Test func goingOverTheSamePlaceAgainKeepsTheEdgeAsItWas() {
    var once = PaintBitmap(width: 60, height: 30)
    once.stroke(from: CGPoint(x: 10, y: 15), to: CGPoint(x: 50, y: 15), radius: 6, red: 10, green: 20, blue: 30)
    var twice = once
    twice.stroke(from: CGPoint(x: 10, y: 15), to: CGPoint(x: 50, y: 15), radius: 6, red: 10, green: 20, blue: 30)
    #expect(once == twice)
  }

  @Test func theBrushStaysInsideTheDrawing() {
    var paint = PaintBitmap(width: 30, height: 30)
    paint.stroke(from: CGPoint(x: -20, y: -20), to: CGPoint(x: 3, y: 3), radius: 5, red: 1, green: 2, blue: 3)
    paint.stroke(from: CGPoint(x: 400, y: 400), to: CGPoint(x: 500, y: 500), radius: 5, red: 1, green: 2, blue: 3)
    #expect(paint.alpha(x: 0, y: 0) == 255)
  }

  @Test func clearingEmptiesTheDrawing() {
    var paint = PaintBitmap(width: 20, height: 20)
    paint.stroke(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 15, y: 15), radius: 3, red: 9, green: 9, blue: 9)
    paint.clear()
    #expect(paint.isEmpty)
  }

  @Test func aPNGBringsTheDrawingBack() throws {
    var paint = PaintBitmap(width: 64, height: 48)
    paint.stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 30), radius: 6, red: 220, green: 40, blue: 10)
    let data = try #require(paint.pngData())
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let back = try #require(PaintBitmap(image: image))
    #expect(back.width == 64 && back.height == 48)
    // The core of the stroke comes back exactly; the empty corner is still empty.
    #expect(back.alpha(x: 30, y: 20) == 255)
    #expect(back.color(x: 30, y: 20).red == 220 && back.color(x: 30, y: 20).green == 40)
    #expect(back.alpha(x: 60, y: 2) == 0)
  }

  @Test func updatingOnlyWhatAStrokeTouchedGivesTheSameOverlayAsRebuilding() throws {
    var paint = PaintBitmap(width: 120, height: 80)
    let incremental = try #require(PaintOverlay(width: 120, height: 80))
    for step in 0..<6 {
      let start = CGPoint(x: 10 + Double(step) * 15, y: 15 + Double(step) * 8)
      let dirty = paint.stroke(
        from: start, to: CGPoint(x: start.x + 25, y: start.y + 4), radius: 6, red: UInt8(40 * step), green: 90, blue: 200)
      incremental.update(from: paint, rect: dirty)
    }
    let whole = try #require(PaintOverlay(width: 120, height: 80))
    whole.rebuild(from: paint)
    func bytes(_ overlay: PaintOverlay) throws -> [UInt8] {
      Array(try #require(overlay.image()?.dataProvider?.data as Data?))
    }
    #expect(try bytes(incremental) == bytes(whole))
  }

  @Test func aStrokeReportsTheRectangleItTouched() {
    var paint = PaintBitmap(width: 100, height: 100)
    let dirty = paint.stroke(from: CGPoint(x: 30, y: 40), to: CGPoint(x: 60, y: 40), radius: 5, red: 1, green: 2, blue: 3)
    #expect(dirty.minX <= 25 && dirty.maxX >= 65 && dirty.width < 60 && dirty.height < 20)
    #expect(paint.stroke(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 600, y: 600), radius: 5, red: 1, green: 2, blue: 3) == .zero)
  }
}
```

```swift
import CoreGraphics
import Foundation
import Testing

@testable import HubCore

struct StrokeSmootherTests {
  @Test func theFirstPointIsAPointAlone() {
    var smoother = StrokeSmoother()
    #expect(!smoother.isActive)
    #expect(smoother.add(CGPoint(x: 5, y: 7), spacing: 2) == [CGPoint(x: 5, y: 7)])
    #expect(smoother.isActive)
  }

  @Test func aStraightLineStaysStraight() {
    var smoother = StrokeSmoother()
    _ = smoother.add(CGPoint(x: 0, y: 10), spacing: 2)
    let points = smoother.add(CGPoint(x: 20, y: 10), spacing: 2) + smoother.add(CGPoint(x: 40, y: 10), spacing: 2)
    #expect(points.allSatisfy { abs($0.y - 10) < 0.0001 })
    // And it goes forward only.
    let xs = points.map(\.x)
    #expect(xs == xs.sorted())
  }

  @Test func theStrokePassesThroughTheMiddlesOfTheSegments() {
    var smoother = StrokeSmoother()
    _ = smoother.add(CGPoint(x: 0, y: 0), spacing: 2)
    let first = smoother.add(CGPoint(x: 40, y: 0), spacing: 2)
    #expect(first.first == CGPoint(x: 0, y: 0))
    #expect(first.last == CGPoint(x: 20, y: 0))
    let second = smoother.add(CGPoint(x: 40, y: 40), spacing: 2)
    #expect(second.first == CGPoint(x: 20, y: 0))
    #expect(second.last == CGPoint(x: 40, y: 20))
  }

  @Test func aCornerIsRoundedNotCutOrOvershot() {
    var smoother = StrokeSmoother()
    _ = smoother.add(CGPoint(x: 0, y: 0), spacing: 2)
    _ = smoother.add(CGPoint(x: 40, y: 0), spacing: 2)
    let curve = smoother.add(CGPoint(x: 40, y: 40), spacing: 2)
    // Between the two middles the curve bends toward the corner (40, 0) without reaching it.
    let nearest = curve.map { hypot($0.x - 40, $0.y - 0) }.min() ?? 0
    #expect(nearest > 1 && nearest < 10)
    #expect(curve.allSatisfy { $0.x <= 40.0001 && $0.y >= -0.0001 })
  }

  @Test func theCurveIsMadeOfShortSteps() {
    var smoother = StrokeSmoother()
    _ = smoother.add(CGPoint(x: 0, y: 0), spacing: 3)
    let curve = smoother.add(CGPoint(x: 300, y: 0), spacing: 3)
    for (a, b) in zip(curve, curve.dropFirst()) { #expect(hypot(b.x - a.x, b.y - a.y) <= 6) }
  }

  @Test func finishingTakesTheStrokeToTheLastPointAndStartsOver() {
    var smoother = StrokeSmoother()
    _ = smoother.add(CGPoint(x: 0, y: 0), spacing: 2)
    _ = smoother.add(CGPoint(x: 40, y: 0), spacing: 2)
    #expect(smoother.finish() == [CGPoint(x: 20, y: 0), CGPoint(x: 40, y: 0)])
    #expect(!smoother.isActive)
    #expect(smoother.finish().isEmpty)
    // A tap is a dot.
    var tap = StrokeSmoother()
    _ = tap.add(CGPoint(x: 3, y: 3), spacing: 2)
    #expect(tap.finish() == [CGPoint(x: 3, y: 3)])
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter "MaskBitmapTests|PaintBitmapTests|StrokeSmootherTests" 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'MaskBitmap' in scope`.

- [ ] **Step 3: Implementare**

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The inpaint mask as the tab draws it (tab Control spec §3): one byte per pixel, 255 where the
/// picture is to be regenerated. It lives at a working size (the start image's ratio, its longest
/// side at most 1024 px) so the brush stays fluent on any image; a RUN scales it to the canvas.
/// Draw Things takes a mask with no shades, so the brush has no softness: the edge is softened
/// there (`MaskSettings.blur`).
public struct MaskBitmap: Equatable, Sendable {
  public let width: Int
  public let height: Int
  public private(set) var pixels: [UInt8]

  /// Longest side of the working mask.
  public static let maxSide = 1024

  public init(width: Int, height: Int) {
    self.width = max(width, 1)
    self.height = max(height, 1)
    pixels = [UInt8](repeating: 0, count: self.width * self.height)
  }

  /// The working size for an image: its ratio, the longest side at most `maxSide`.
  public static func workingSize(imageWidth: Int, imageHeight: Int) -> (width: Int, height: Int) {
    let longest = max(imageWidth, imageHeight, 1)
    let scale = min(1, Double(maxSide) / Double(longest))
    return (max(1, Int((Double(imageWidth) * scale).rounded())), max(1, Int((Double(imageHeight) * scale).rounded())))
  }

  /// True when nothing is painted.
  public var isEmpty: Bool { !pixels.contains { $0 >= 128 } }

  /// The share of the whole mask that is painted, 0…1.
  public var coverage: Double {
    Double(pixels.reduce(0) { $0 + ($1 >= 128 ? 1 : 0) }) / Double(pixels.count)
  }

  // MARK: Drawing

  /// Paints (or erases) a round brush of `radius` pixels along the segment from `start` to `end`,
  /// in mask pixels. The edge has one pixel of antialiasing. Returns the rectangle of pixels that
  /// may have changed (empty when the segment is outside the mask), so a view can update only that.
  @discardableResult
  public mutating func stroke(from start: CGPoint, to end: CGPoint, radius: Double, erase: Bool) -> CGRect {
    let radius = max(radius, 0.5)
    let length = hypot(end.x - start.x, end.y - start.y)
    let steps = max(1, Int((length / max(radius / 3, 0.5)).rounded(.up)))
    var dirty = CGRect.null
    for step in 0...steps {
      let t = Double(step) / Double(steps)
      let area = stamp(
        at: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t), radius: radius,
        erase: erase)
      dirty = dirty.union(area)
    }
    return dirty.isNull ? .zero : dirty
  }

  private mutating func stamp(at center: CGPoint, radius: Double, erase: Bool) -> CGRect {
    let minX = max(0, Int((center.x - radius - 1).rounded(.down)))
    let maxX = min(width - 1, Int((center.x + radius + 1).rounded(.up)))
    let minY = max(0, Int((center.y - radius - 1).rounded(.down)))
    let maxY = min(height - 1, Int((center.y + radius + 1).rounded(.up)))
    guard minX <= maxX, minY <= maxY else { return .null }
    for y in minY...maxY {
      for x in minX...maxX {
        // The pixel's centre against the circle; one pixel of edge is partly covered.
        let distance = hypot(Double(x) + 0.5 - center.x, Double(y) + 0.5 - center.y)
        let cover = min(1, max(0, radius + 0.5 - distance))
        guard cover > 0 else { continue }
        let index = y * width + x
        if erase {
          pixels[index] = UInt8(Double(pixels[index]) * (1 - cover))
        } else {
          pixels[index] = max(pixels[index], UInt8((cover * 255).rounded()))
        }
      }
    }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
  }

  public mutating func invert() {
    for index in pixels.indices { pixels[index] = 255 - pixels[index] }
  }

  public mutating func clear() {
    pixels = [UInt8](repeating: 0, count: pixels.count)
  }

  // MARK: Files

  public func pngData() -> Data? {
    guard let image = grayImage() else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }

  /// A mask read back from its PNG (any image: it is drawn in grey at the PNG's own size).
  public init?(image: CGImage) {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: width * height)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return nil }
    self.width = width
    self.height = height
    pixels = bytes
  }

  func grayImage() -> CGImage? {
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  // MARK: From the screen

  /// Where a point of the paint view falls in the mask. The view shows the cut `crop` (in the start
  /// image's pixels) of the image `imageWidth` pixels wide, and fills `viewSize`.
  public func point(forViewPoint point: CGPoint, viewSize: CGSize, crop: CGRect, imageWidth: Int) -> CGPoint {
    guard viewSize.width > 0, viewSize.height > 0, imageWidth > 0 else { return .zero }
    let toMask = Double(width) / Double(imageWidth)
    return CGPoint(
      x: (crop.minX + point.x / viewSize.width * crop.width) * toMask,
      y: (crop.minY + point.y / viewSize.height * crop.height) * toMask)
  }

  /// The brush's radius in mask pixels for a brush `diameter` wide in canvas pixels.
  public func brushRadius(diameter: Double, canvasWidth: Int, crop: CGRect, imageWidth: Int) -> Double {
    guard canvasWidth > 0, imageWidth > 0 else { return 0 }
    return diameter / 2 * (crop.width / Double(canvasWidth)) * (Double(width) / Double(imageWidth))
  }
}
```

```swift
import CoreGraphics
import Foundation

/// The mask as a translucent colour over the picture, for the screen. It is kept between strokes
/// and only the pixels a stroke touched are rewritten (`update`), so painting stays fluent: the
/// whole picture is rebuilt only when a mask is read (`rebuild`).
public final class MaskOverlay {
  public let width: Int
  public let height: Int
  private let context: CGContext
  private let red: Double
  private let green: Double
  private let blue: Double
  private let opacity: Double

  public init?(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8, opacity: Double) {
    guard width > 0, height > 0,
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    self.width = width
    self.height = height
    self.context = context
    self.red = Double(red)
    self.green = Double(green)
    self.blue = Double(blue)
    self.opacity = opacity
  }

  /// Rewrites the whole overlay from the mask (which must have the overlay's size).
  public func rebuild(from mask: MaskBitmap) {
    update(from: mask, rect: CGRect(x: 0, y: 0, width: width, height: height))
  }

  /// Rewrites the pixels inside `rect` (mask pixels) from the mask.
  public func update(from mask: MaskBitmap, rect: CGRect) {
    guard mask.width == width, mask.height == height, let data = context.data else { return }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    let minX = max(0, Int(rect.minX.rounded(.down)))
    let maxX = min(width, Int(rect.maxX.rounded(.up)))
    let minY = max(0, Int(rect.minY.rounded(.down)))
    let maxY = min(height, Int(rect.maxY.rounded(.up)))
    guard minX < maxX, minY < maxY else { return }
    for y in minY..<maxY {
      for x in minX..<maxX {
        let value = mask.pixels[y * width + x]
        let base = (y * width + x) * 4
        if value == 0 {
          bytes[base] = 0
          bytes[base + 1] = 0
          bytes[base + 2] = 0
          bytes[base + 3] = 0
        } else {
          let alpha = Double(value) / 255 * opacity
          bytes[base] = UInt8((red * alpha).rounded())
          bytes[base + 1] = UInt8((green * alpha).rounded())
          bytes[base + 2] = UInt8((blue * alpha).rounded())
          bytes[base + 3] = UInt8((alpha * 255).rounded())
        }
      }
    }
  }

  /// A snapshot of the overlay as it is now.
  public func image() -> CGImage? { context.makeImage() }
}
```

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What the Brush tool draws over the start image (tab Control spec §3): RGBA, 8 bits, straight
/// (not premultiplied) alpha, at the same working size as the mask (the image's ratio, the longest
/// side at most `MaskBitmap.maxSide`). It is a layer of its own: the start image's file is not
/// touched, and a RUN puts the drawing over the image (`InputComposer.frame`).
public struct PaintBitmap: Equatable, Sendable {
  public let width: Int
  public let height: Int
  /// R, G, B, A for each pixel, row by row.
  public private(set) var pixels: [UInt8]

  public init(width: Int, height: Int) {
    self.width = max(width, 1)
    self.height = max(height, 1)
    pixels = [UInt8](repeating: 0, count: self.width * self.height * 4)
  }

  /// True when nothing is drawn.
  public var isEmpty: Bool {
    for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] > 0 { return false }
    return true
  }

  public func alpha(x: Int, y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }

  public func color(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
    let base = (y * width + x) * 4
    return (pixels[base], pixels[base + 1], pixels[base + 2])
  }

  /// Draws a round, hard brush of `radius` pixels along the segment, in layer pixels. The edge has
  /// one pixel of antialiasing; a pixel keeps the strongest cover it got, so going over the same
  /// place again does not thicken the edge. Returns the rectangle of pixels that may have changed
  /// (empty when the segment is outside the layer).
  @discardableResult
  public mutating func stroke(
    from start: CGPoint, to end: CGPoint, radius: Double, red: UInt8, green: UInt8, blue: UInt8
  ) -> CGRect {
    let radius = max(radius, 0.5)
    let length = hypot(end.x - start.x, end.y - start.y)
    let steps = max(1, Int((length / max(radius / 3, 0.5)).rounded(.up)))
    var dirty = CGRect.null
    for step in 0...steps {
      let t = Double(step) / Double(steps)
      let area = stamp(
        at: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t), radius: radius,
        red: red, green: green, blue: blue)
      dirty = dirty.union(area)
    }
    return dirty.isNull ? .zero : dirty
  }

  private mutating func stamp(at center: CGPoint, radius: Double, red: UInt8, green: UInt8, blue: UInt8) -> CGRect {
    let minX = max(0, Int((center.x - radius - 1).rounded(.down)))
    let maxX = min(width - 1, Int((center.x + radius + 1).rounded(.up)))
    let minY = max(0, Int((center.y - radius - 1).rounded(.down)))
    let maxY = min(height - 1, Int((center.y + radius + 1).rounded(.up)))
    guard minX <= maxX, minY <= maxY else { return .null }
    for y in minY...maxY {
      for x in minX...maxX {
        let distance = hypot(Double(x) + 0.5 - center.x, Double(y) + 0.5 - center.y)
        let cover = min(1, max(0, radius + 0.5 - distance))
        guard cover > 0 else { continue }
        let base = (y * width + x) * 4
        let now = Double(pixels[base + 3]) / 255
        if cover >= now {
          pixels[base] = red
          pixels[base + 1] = green
          pixels[base + 2] = blue
          pixels[base + 3] = UInt8((cover * 255).rounded())
        } else {
          // The edge of a new stroke over an older, stronger one: the colour leans toward the new one.
          pixels[base] = UInt8((Double(pixels[base]) * (1 - cover) + Double(red) * cover).rounded())
          pixels[base + 1] = UInt8((Double(pixels[base + 1]) * (1 - cover) + Double(green) * cover).rounded())
          pixels[base + 2] = UInt8((Double(pixels[base + 2]) * (1 - cover) + Double(blue) * cover).rounded())
        }
      }
    }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
  }

  public mutating func clear() {
    pixels = [UInt8](repeating: 0, count: pixels.count)
  }

  // MARK: Files and images

  /// The drawing as an image with straight alpha: to show, to put over the start image.
  public func cgImage() -> CGImage? {
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  public func pngData() -> Data? {
    guard let image = cgImage() else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }

  /// A drawing read back from its PNG, at the PNG's own size.
  public init?(image: CGImage) {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return nil }
    // Back to straight alpha.
    for base in stride(from: 0, to: bytes.count, by: 4) where bytes[base + 3] > 0 && bytes[base + 3] < 255 {
      let alpha = Double(bytes[base + 3]) / 255
      for channel in 0..<3 { bytes[base + channel] = UInt8(min(255, (Double(bytes[base + channel]) / alpha).rounded())) }
    }
    self.width = width
    self.height = height
    pixels = bytes
  }
}
```

```swift
import CoreGraphics
import Foundation

/// The Brush drawing as an image for the screen, kept between strokes: only the pixels a stroke
/// touched are rewritten (`update`), the whole picture is rebuilt only when a drawing is read.
public final class PaintOverlay {
  public let width: Int
  public let height: Int
  private let context: CGContext

  public init?(width: Int, height: Int) {
    guard width > 0, height > 0,
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    self.width = width
    self.height = height
    self.context = context
  }

  public func rebuild(from paint: PaintBitmap) {
    update(from: paint, rect: CGRect(x: 0, y: 0, width: width, height: height))
  }

  /// Rewrites the pixels inside `rect` (layer pixels) from the drawing (which must have the overlay's size).
  public func update(from paint: PaintBitmap, rect: CGRect) {
    guard paint.width == width, paint.height == height, let data = context.data else { return }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    let minX = max(0, Int(rect.minX.rounded(.down)))
    let maxX = min(width, Int(rect.maxX.rounded(.up)))
    let minY = max(0, Int(rect.minY.rounded(.down)))
    let maxY = min(height, Int(rect.maxY.rounded(.up)))
    guard minX < maxX, minY < maxY else { return }
    for y in minY..<maxY {
      for x in minX..<maxX {
        let base = (y * width + x) * 4
        let alpha = Int(paint.pixels[base + 3])
        // Premultiplied for the screen.
        bytes[base] = UInt8((Int(paint.pixels[base]) * alpha + 127) / 255)
        bytes[base + 1] = UInt8((Int(paint.pixels[base + 1]) * alpha + 127) / 255)
        bytes[base + 2] = UInt8((Int(paint.pixels[base + 2]) * alpha + 127) / 255)
        bytes[base + 3] = UInt8(alpha)
      }
    }
  }

  public func image() -> CGImage? { context.makeImage() }
}
```

```swift
import CoreGraphics
import Foundation

/// Turns the few points a mouse gives into a smooth stroke: the stroke passes through the middles
/// of the segments and bends toward the points between them (a quadratic curve for each pair), so a
/// slow frame rate does not show as corners. The curve is a little behind the pointer, and
/// `finish` takes it to the last point.
public struct StrokeSmoother: Equatable, Sendable {
  private var last: CGPoint?
  private var lastMid: CGPoint?

  public init() {}

  /// True from the first point to `finish`.
  public var isActive: Bool { last != nil }

  /// Adds a point; returns the points to join with straight segments, the first one where the
  /// stroke was (a point alone for the very first). `spacing` is about how far apart the points
  /// of a curve are, in the same pixels as the points.
  public mutating func add(_ point: CGPoint, spacing: Double) -> [CGPoint] {
    guard let previous = last, let from = lastMid else {
      last = point
      lastMid = point
      return [point]
    }
    let mid = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
    last = point
    lastMid = mid
    let chord = hypot(previous.x - from.x, previous.y - from.y) + hypot(mid.x - previous.x, mid.y - previous.y)
    let steps = min(64, max(1, Int((chord / max(spacing, 0.5)).rounded(.up))))
    var points = [from]
    for step in 1...steps {
      let t = Double(step) / Double(steps)
      let a = (1 - t) * (1 - t)
      let b = 2 * (1 - t) * t
      let c = t * t
      points.append(CGPoint(x: a * from.x + b * previous.x + c * mid.x, y: a * from.y + b * previous.y + c * mid.y))
    }
    return points
  }

  /// Ends the stroke: the points from where it was to the last point added.
  public mutating func finish() -> [CGPoint] {
    defer {
      last = nil
      lastMid = nil
    }
    guard let last, let lastMid else { return [] }
    return last == lastMid ? [last] : [lastMid, last]
  }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v started`
Expected: HubCore `270 tests … passed` (32 nuovi: 17 + 9 + 6); totale 63 + 270 + 61 + 6 + 6 = **406**.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: maschera e disegno come buffer (pennello, gomma, inverti, PNG, anteprime aggiornate a rettangoli, tratto curvo)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Maschera e disegno per il canvas (HubCore)

**Files:**
- Modify: `Packages/Sources/HubCore/Control/InputComposer.swift`
- Test: `Packages/Tests/HubCoreTests/MaskComposerTests.swift` (nuovo)

**Interfaces:**
- Consumes: `MaskBitmap`, `PaintBitmap` (Task 3), `FramingMath.cropRect`, `Framing`.
- Produces:
  - `InputComposer.mask(_ mask: MaskBitmap, imageWidth:imageHeight:toWidth:height:framing:) -> CGImage?`: RGBA premoltiplicato della dimensione esatta del canvas, **trasparente dove si rigenera** (maschera ≥ 128 dopo la scala) e opaco altrove, nello stesso ritaglio dell'immagine; `nil` se una dimensione è zero;
  - `InputComposer.frame(_:toWidth:height:framing:paint:)` con `paint: PaintBitmap? = nil`: il disegno si sovrappone all'immagine nello stesso ritaglio.

- [ ] **Step 1: Scrivere i test che falliscono**

```swift
import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing

@testable import HubCore

struct MaskComposerTests {
  /// Alpha of the pixel at (x, y), counted from the top-left.
  func alpha(_ image: CGImage, _ x: Int, _ y: Int) -> Int {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return Int(bytes[3])
  }

  /// A 100×50 mask whose right half is painted.
  func rightHalf() -> MaskBitmap {
    var mask = MaskBitmap(width: 100, height: 50)
    for x in 50..<100 { mask.stroke(from: CGPoint(x: Double(x) + 0.5, y: 0), to: CGPoint(x: Double(x) + 0.5, y: 50), radius: 0.7, erase: false) }
    return mask
  }

  @Test func thePaintedHalfIsTransparentAndTheRestOpaque() throws {
    let canvas = try #require(InputComposer.mask(rightHalf(), imageWidth: 200, imageHeight: 100, toWidth: 200, height: 100, framing: Framing()))
    #expect(canvas.width == 200 && canvas.height == 100)
    #expect(alpha(canvas, 20, 50) == 255)
    #expect(alpha(canvas, 180, 50) == 0)
  }

  @Test func theMaskFollowsTheCut() throws {
    // A square canvas over a 2:1 image shows its left half (offset −1): the painted half is out.
    let left = try #require(InputComposer.mask(rightHalf(), imageWidth: 200, imageHeight: 100, toWidth: 64, height: 64, framing: Framing(offsetX: -1)))
    #expect(alpha(left, 10, 32) == 255 && alpha(left, 54, 32) == 255)
    // Offset 1 shows the right half: all of it is painted.
    let right = try #require(InputComposer.mask(rightHalf(), imageWidth: 200, imageHeight: 100, toWidth: 64, height: 64, framing: Framing(offsetX: 1)))
    #expect(alpha(right, 10, 32) == 0 && alpha(right, 54, 32) == 0)
  }

  @Test func theMaskIsScaledToTheCanvasWithAHardEdge() throws {
    let canvas = try #require(InputComposer.mask(rightHalf(), imageWidth: 200, imageHeight: 100, toWidth: 400, height: 200, framing: Framing()))
    var shades = Set<Int>()
    for x in stride(from: 0, to: 400, by: 7) { shades.insert(alpha(canvas, x, 100)) }
    #expect(shades == [0, 255])
  }

  @Test func paintAtTheTopOfTheMaskIsAtTheTopOfTheCanvas() throws {
    var mask = MaskBitmap(width: 100, height: 100)
    for x in 0..<100 { mask.stroke(from: CGPoint(x: Double(x) + 0.5, y: 0.5), to: CGPoint(x: Double(x) + 0.5, y: 20.5), radius: 0.7, erase: false) }
    let canvas = try #require(InputComposer.mask(mask, imageWidth: 100, imageHeight: 100, toWidth: 100, height: 100, framing: Framing()))
    #expect(alpha(canvas, 50, 5) == 0)
    #expect(alpha(canvas, 50, 90) == 255)
  }

  @Test func theDrawingIsPutOverTheImageInTheSameCut() throws {
    // A 200×100 white image framed on a 100×100 canvas, the cut on its right half; a mark at the
    // left of the drawing is out of the cut, a mark at the right is in.
    let context = CGContext(
      data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
    let white = try #require(context.makeImage())
    var paint = PaintBitmap(width: 100, height: 50)
    paint.stroke(from: CGPoint(x: 10, y: 25), to: CGPoint(x: 10, y: 25), radius: 4, red: 255, green: 0, blue: 0)
    paint.stroke(from: CGPoint(x: 80, y: 25), to: CGPoint(x: 80, y: 25), radius: 4, red: 255, green: 0, blue: 0)
    let framed = try #require(
      InputComposer.frame(white, toWidth: 100, height: 100, framing: Framing(offsetX: 1), paint: paint))
    func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int) {
      var bytes = [UInt8](repeating: 0, count: 4)
      let one = CGContext(
        data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      one.draw(framed, in: CGRect(x: -x, y: -(framed.height - 1 - y), width: framed.width, height: framed.height))
      return (Int(bytes[0]), Int(bytes[1]))
    }
    // The mark at 80/100 of the image width is at (160 − 100) / 100 = 0.6 of the canvas.
    #expect(pixel(60, 50).g < 40 && pixel(60, 50).r > 215)
    // Elsewhere the image stays white.
    #expect(pixel(20, 50).g > 240)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter MaskComposerTests 2>&1 | grep -E "error:" | head -2`
Expected: `type 'InputComposer' has no member 'mask'`.

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/HubCore/Control/InputComposer.swift b/Packages/Sources/HubCore/Control/InputComposer.swift
index 0c36a4c..c0d7bc8 100644
--- a/Packages/Sources/HubCore/Control/InputComposer.swift
+++ b/Packages/Sources/HubCore/Control/InputComposer.swift
@@ -1,11 +1,16 @@
 import CoreGraphics
+import Foundation
 import HubKit
 
 /// Prepares the Control tab's images for a RUN (tab Control spec §6).
 public enum InputComposer {
   /// The start image cut and scaled to the exact canvas size, opaque. nil when the context cannot
   /// be made (a size of zero).
-  public static func frame(_ image: CGImage, toWidth width: Int, height: Int, framing: Framing) -> CGImage? {
+  /// With `paint` (the Brush drawing, in the image's own coordinates) it is put over the image in
+  /// the same cut.
+  public static func frame(
+    _ image: CGImage, toWidth width: Int, height: Int, framing: Framing, paint: PaintBitmap? = nil
+  ) -> CGImage? {
     guard width > 0, height > 0 else { return nil }
     let crop = FramingMath.cropRect(
       imageWidth: image.width, imageHeight: image.height, canvasWidth: width, canvasHeight: height, framing: framing)
@@ -21,6 +26,44 @@ public enum InputComposer {
       x: -crop.minX * scale, y: -(Double(image.height) - crop.maxY) * scale,
       width: Double(image.width) * scale, height: Double(image.height) * scale)
     context.draw(image, in: drawn)
+    if let layer = paint?.cgImage() { context.draw(layer, in: drawn) }
     return context.makeImage()
   }
+
+  /// The mask for the canvas, in the same cut as the start image: transparent where the picture is
+  /// regenerated, opaque where it is kept (what the client wants). The mask is scaled with the same
+  /// smoothing as the image and then cut at half, so its edge is clean at any scale.
+  public static func mask(
+    _ mask: MaskBitmap, imageWidth: Int, imageHeight: Int, toWidth width: Int, height: Int, framing: Framing
+  ) -> CGImage? {
+    guard width > 0, height > 0, imageWidth > 0, imageHeight > 0, let gray = mask.grayImage() else { return nil }
+    let crop = FramingMath.cropRect(
+      imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: width, canvasHeight: height, framing: framing)
+    var bytes = [UInt8](repeating: 0, count: width * height)
+    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
+      guard
+        let context = CGContext(
+          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
+          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
+      else { return false }
+      context.interpolationQuality = .high
+      let scale = Double(width) / crop.width
+      context.draw(
+        gray,
+        in: CGRect(
+          x: -crop.minX * scale, y: -(Double(imageHeight) - crop.maxY) * scale, width: Double(imageWidth) * scale,
+          height: Double(imageHeight) * scale))
+      return true
+    }
+    guard drawn else { return nil }
+    // Transparent (0) where regenerated; black, premultiplied, so the colour channels stay 0.
+    var rgba = [UInt8](repeating: 0, count: width * height * 4)
+    for index in bytes.indices where bytes[index] < 128 { rgba[index * 4 + 3] = 255 }
+    guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
+    return CGImage(
+      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
+      space: CGColorSpaceCreateDeviceRGB(),
+      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
+      decode: nil, shouldInterpolate: false, intent: .defaultIntent)
+  }
 }
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v started`
Expected: HubCore `275 tests … passed`; totale **411**.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: la maschera e il disegno nello stesso ritaglio dell'immagine

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Maschera e disegno nello store e negli ingressi del RUN (HubCore)

**Files:**
- Modify: `Packages/Sources/HubCore/Control/ControlStore.swift`, `Packages/Sources/HubCore/Generation/JobComposer.swift`
- Test: `Packages/Tests/HubCoreTests/ControlStoreMaskTests.swift` (nuovo), `Packages/Tests/HubCoreTests/FamilyTraitsTests.swift`

**Interfaces:**
- Consumes: `MaskBitmap`, `PaintBitmap`, `InputComposer.mask`/`frame(…paint:)`, i tipi del Task 1.
- Produces:
  - `ControlNotice.maskCleared`, `.maskMissingAtLaunch`, `.paintCleared`, `.paintMissingAtLaunch`;
  - `ControlStore.maskBitmap() -> MaskBitmap?`, `paintBitmap() -> PaintBitmap?`, `maskSize: (width: Int, height: Int)?` (nil senza immagine), `commitMask(_:)`, `commitPaint(_:)` (`throws(ControlError)`, un passo della cronologia; vuoti = niente; niente senza immagine), `invertMask() throws(ControlError)`, `clearMask()`, `clearPaint()` (con avviso e annulla), `setMaskSettings(_:)` (limitata, non è un passo);
  - cambiare o togliere l'immagine toglie maschera e disegno; un avvio senza la copia li scarta con l'avviso; la pulizia delle copie considera maschere e disegni di stato e cronologia;
  - `PendingInputs.render()` aggiunge `GenerationInputs.mask` (al canvas, nel ritaglio) e mette il disegno sopra l'immagine;
  - `JobComposer.batches(…, maskSettings: MaskSettings? = nil, …)` lo registra in ogni job.

- [ ] **Step 1: Scrivere i test che falliscono**

```swift
import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing

@testable import HubCore

@MainActor
struct ControlStoreMaskTests {
  func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ControlStoreMaskTests-\(UUID())", isDirectory: true)
  }

  func store(in root: URL) -> ControlStore {
    ControlStore(
      storage: FileReferenceStorage(folder: root.appendingPathComponent("Control", isDirectory: true)),
      fileURL: root.appendingPathComponent("control.json"))
  }

  func copies(in root: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Control").path)) ?? []).sorted()
  }

  func withImage(_ root: URL, width: Int = 400, height: Int = 300) throws -> ControlStore {
    let store = store(in: root)
    try store.setImage(data: pictureData(width: width, height: height), name: "a.png", source: .pasteboard)
    return store
  }

  func spot(_ store: ControlStore, at point: CGPoint = CGPoint(x: 50, y: 50), radius: Double = 10) -> MaskBitmap {
    let size = store.maskSize!
    var bitmap = store.maskBitmap() ?? MaskBitmap(width: size.width, height: size.height)
    bitmap.stroke(from: point, to: point, radius: radius, erase: false)
    return bitmap
  }

  @Test func theMaskIsDrawnAtTheWorkingSizeOfTheImage() throws {
    let store = try withImage(folder(), width: 4000, height: 2000)
    let size = try #require(store.maskSize)
    #expect(size.width == 1024 && size.height == 512)
  }

  @Test func aCommittedMaskIsKeptAndComesBackFromDisk() throws {
    let root = folder()
    let store = try withImage(root)
    try store.commitMask(spot(store))
    let reference = try #require(store.inputs.mask)
    #expect(reference.coverage > 0)
    let back = try #require(store.maskBitmap())
    #expect(back.width == 400 && back.height == 300)
    #expect(back.pixels[50 * back.width + 50] >= 128)
    #expect(copies(in: root).contains(reference.fileName))
  }

  @Test func eachStrokeIsAStepOfTheHistory() throws {
    let store = try withImage(folder())
    try store.commitMask(spot(store, at: CGPoint(x: 50, y: 50)))
    let first = store.inputs.mask
    try store.commitMask(spot(store, at: CGPoint(x: 300, y: 200)))
    #expect(store.inputs.mask != first)
    store.undo()
    #expect(store.inputs.mask == first)
    let back = try #require(store.maskBitmap())
    #expect(back.pixels[200 * back.width + 300] < 128)
    store.undo()
    #expect(store.inputs.mask == nil)
    store.redo()
    store.redo()
    #expect(store.inputs.mask != first)
  }

  @Test func anEmptyMaskIsNoMask() throws {
    let store = try withImage(folder())
    try store.commitMask(spot(store))
    var bitmap = try #require(store.maskBitmap())
    bitmap.clear()
    try store.commitMask(bitmap)
    #expect(store.inputs.mask == nil)
  }

  @Test func committingAnEmptyMaskWithoutOneChangesNothing() throws {
    let store = try withImage(folder())
    let size = try #require(store.maskSize)
    try store.commitMask(MaskBitmap(width: size.width, height: size.height))
    #expect(store.inputs.mask == nil)
    #expect(store.canUndo)  // only the image's step
    store.undo()
    #expect(store.inputs.image == nil)
  }

  @Test func invertingAMaskDrawnNothingPaintsEverything() throws {
    let store = try withImage(folder())
    try store.invertMask()
    #expect(try #require(store.inputs.mask).coverage == 1)
    try store.invertMask()
    #expect(store.inputs.mask == nil)
  }

  @Test func clearingTheMaskSaysSoAndCanBeUndone() throws {
    let store = try withImage(folder())
    try store.commitMask(spot(store))
    let reference = store.inputs.mask
    store.clearMask()
    #expect(store.inputs.mask == nil)
    #expect(store.notice == .maskCleared)
    store.undo()
    #expect(store.inputs.mask == reference)
  }

  @Test func theMaskGoesWithTheImage() throws {
    let root = folder()
    let store = try withImage(root)
    try store.commitMask(spot(store))
    try store.setImage(data: pictureData(width: 200, height: 200), name: "b.png", source: .pasteboard)
    #expect(store.inputs.mask == nil)
    store.undo()
    #expect(store.inputs.mask != nil)
    store.removeImage()
    #expect(store.inputs.mask == nil)
  }

  @Test func withoutAnImageThereIsNothingToDraw() throws {
    let store = store(in: folder())
    #expect(store.maskSize == nil)
    try store.commitMask(MaskBitmap(width: 10, height: 10))
    try store.invertMask()
    #expect(store.inputs.mask == nil)
  }

  @Test func theMaskSurvivesARestart() throws {
    let root = folder()
    do {
      let store = try withImage(root)
      try store.commitMask(spot(store))
      store.setMaskSettings(MaskSettings(blur: 4, outset: 8, preserveOriginal: false))
    }
    let again = store(in: root)
    #expect(again.inputs.mask != nil)
    #expect(again.inputs.maskSettings == MaskSettings(blur: 4, outset: 8, preserveOriginal: false))
    #expect(again.maskBitmap() != nil)
  }

  @Test func aMaskWhoseCopyIsGoneIsDroppedWithANotice() throws {
    let root = folder()
    do {
      let store = try withImage(root)
      try store.commitMask(spot(store))
      let name = try #require(store.inputs.mask?.fileName)
      try FileManager.default.removeItem(at: root.appendingPathComponent("Control").appendingPathComponent(name))
    }
    let again = store(in: root)
    #expect(again.inputs.mask == nil)
    #expect(again.inputs.image != nil)
    #expect(again.notice == .maskMissingAtLaunch)
  }

  @Test func theCopiesOfOldMasksAreSweptWhenNothingRefersToThem() throws {
    let root = folder()
    let store = try withImage(root)
    try store.commitMask(spot(store, at: CGPoint(x: 50, y: 50)))
    try store.commitMask(spot(store, at: CGPoint(x: 100, y: 100)))
    let image = try #require(store.inputs.image).fileName
    #expect(copies(in: root).count == 3)  // image + the two masks (the first one is in the history)
    store.clear()
    store.undo()
    #expect(copies(in: root).count == 3)
    #expect(copies(in: root).contains(image))
  }

  @Test func theMaskSettingsAreClamped() throws {
    let store = try withImage(folder())
    store.setMaskSettings(MaskSettings(blur: 500, outset: -4, preserveOriginal: true))
    #expect(store.inputs.maskSettings.blur == MaskSettings.blurRange.upperBound)
    #expect(store.inputs.maskSettings.outset == 0)
  }

  @Test func withAMaskTheAutomaticStrengthIsFull() throws {
    let store = try withImage(folder())
    #expect(store.inputs.effectiveStrength(editModel: false) == 0.7)
    try store.commitMask(spot(store))
    #expect(store.inputs.effectiveStrength(editModel: false) == 1.0)
    store.setStrength(0.4)
    #expect(store.inputs.effectiveStrength(editModel: false) == 0.4)
  }

  @Test func aRunGetsTheMaskAtTheCanvasSizeNextToTheImage() async throws {
    let store = try withImage(folder(), width: 400, height: 300)
    try store.commitMask(spot(store, at: CGPoint(x: 20, y: 20), radius: 15))
    let pending = store.pendingInputs(canvasWidth: 256, canvasHeight: 192)
    let inputs = try await Task.detached { try pending.render() }.value
    let mask = try #require(inputs.mask)
    #expect(mask.width == 256 && mask.height == 192)
    #expect(inputs.image?.width == 256)
    #expect(inputs.isEmpty == false)
  }

  @Test func withoutAMaskARunHasNone() async throws {
    let store = try withImage(folder())
    let pending = store.pendingInputs(canvasWidth: 128, canvasHeight: 96)
    let inputs = try await Task.detached { try pending.render() }.value
    #expect(inputs.mask == nil)
  }

  // MARK: The Brush drawing

  func drawing(_ store: ControlStore, at point: CGPoint = CGPoint(x: 50, y: 50)) -> PaintBitmap {
    let size = store.maskSize!
    var bitmap = store.paintBitmap() ?? PaintBitmap(width: size.width, height: size.height)
    bitmap.stroke(from: point, to: point, radius: 10, red: 200, green: 20, blue: 20)
    return bitmap
  }

  @Test func aCommittedDrawingIsKeptAndComesBackFromDisk() throws {
    let root = folder()
    let store = try withImage(root)
    try store.commitPaint(drawing(store))
    let reference = try #require(store.inputs.paint)
    let back = try #require(store.paintBitmap())
    #expect(back.width == 400 && back.height == 300)
    #expect(back.alpha(x: 50, y: 50) == 255)
    #expect(copies(in: root).contains(reference.fileName))
  }

  @Test func eachDrawingStrokeIsAStepOfTheHistory() throws {
    let store = try withImage(folder())
    try store.commitPaint(drawing(store, at: CGPoint(x: 50, y: 50)))
    let first = store.inputs.paint
    try store.commitPaint(drawing(store, at: CGPoint(x: 300, y: 200)))
    store.undo()
    #expect(store.inputs.paint == first)
    store.undo()
    #expect(store.inputs.paint == nil)
    store.redo()
    #expect(store.inputs.paint == first)
  }

  @Test func anEmptyDrawingIsNoDrawing() throws {
    let store = try withImage(folder())
    let size = try #require(store.maskSize)
    try store.commitPaint(PaintBitmap(width: size.width, height: size.height))
    #expect(store.inputs.paint == nil)
    try store.commitPaint(drawing(store))
    try store.commitPaint(PaintBitmap(width: size.width, height: size.height))
    #expect(store.inputs.paint == nil)
  }

  @Test func clearingTheDrawingSaysSoAndCanBeUndone() throws {
    let store = try withImage(folder())
    try store.commitPaint(drawing(store))
    let reference = store.inputs.paint
    store.clearPaint()
    #expect(store.inputs.paint == nil)
    #expect(store.notice == .paintCleared)
    store.undo()
    #expect(store.inputs.paint == reference)
  }

  @Test func theDrawingAndTheMaskAreIndependent() throws {
    let store = try withImage(folder())
    try store.commitPaint(drawing(store))
    try store.commitMask(spot(store))
    store.clearMask()
    #expect(store.inputs.paint != nil)
    store.clearPaint()
    #expect(store.inputs.mask == nil)
  }

  @Test func theDrawingGoesWithTheImage() throws {
    let store = try withImage(folder())
    try store.commitPaint(drawing(store))
    try store.setImage(data: pictureData(width: 200, height: 200), name: "b.png", source: .pasteboard)
    #expect(store.inputs.paint == nil)
    store.undo()
    #expect(store.inputs.paint != nil)
    store.removeImage()
    #expect(store.inputs.paint == nil)
  }

  @Test func theDrawingSurvivesARestartAndALostCopyIsDropped() throws {
    let root = folder()
    var name = ""
    do {
      let store = try withImage(root)
      try store.commitPaint(drawing(store))
      name = try #require(store.inputs.paint?.fileName)
    }
    #expect(store(in: root).inputs.paint?.fileName == name)
    try FileManager.default.removeItem(at: root.appendingPathComponent("Control").appendingPathComponent(name))
    let again = store(in: root)
    #expect(again.inputs.paint == nil)
    #expect(again.inputs.image != nil)
    #expect(again.notice == .paintMissingAtLaunch)
  }

  @Test func aRunGetsTheImageWithTheDrawingOnIt() async throws {
    let store = try withImage(folder(), width: 400, height: 300)
    try store.commitPaint(drawing(store, at: CGPoint(x: 200, y: 150)))
    let pending = store.pendingInputs(canvasWidth: 400, canvasHeight: 300)
    let inputs = try await Task.detached { try pending.render() }.value
    let image = try #require(inputs.image)
    // The picture is solid (0.2, 0.6, 0.9); the middle of it carries the red mark.
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -200, y: -(300 - 1 - 150), width: 400, height: 300))
    #expect(bytes[0] > 150 && bytes[2] < 80)
  }
}
```

```diff
diff --git a/Packages/Tests/HubCoreTests/FamilyTraitsTests.swift b/Packages/Tests/HubCoreTests/FamilyTraitsTests.swift
index 962b796..fc80361 100644
--- a/Packages/Tests/HubCoreTests/FamilyTraitsTests.swift
+++ b/Packages/Tests/HubCoreTests/FamilyTraitsTests.swift
@@ -91,6 +91,15 @@ struct JobComposerTests {
     #expect(compose(family: nil, .default).allSatisfy { $0.moodboardCount == 0 })
   }
 
+  @Test func everyBatchRecordsTheMaskSettings() {
+    let settings = MaskSettings(blur: 4, outset: 6, preserveOriginal: false)
+    let jobs = JobComposer.batches(
+      prompt: "fox", negativePrompt: "", model: "m.ckpt", family: nil, parameters: GenerationParameters(batchCount: 2),
+      catalog: catalog, maskSettings: settings) { 7 }
+    #expect(jobs.count == 2 && jobs.allSatisfy { $0.maskSettings == settings })
+    #expect(compose(family: nil, .default).allSatisfy { $0.maskSettings == nil })
+  }
+
   @Test func everyBatchRecordsTheStrengthOfTheStartImage() {
     let parameters = GenerationParameters(batchCount: 2)
     let withImage = JobComposer.batches(
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter "ControlStoreMaskTests|FamilyTraitsTests" 2>&1 | grep -E "error:" | head -2`
Expected: `value of type 'ControlStore' has no member 'commitMask'`.

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/HubCore/Control/ControlStore.swift b/Packages/Sources/HubCore/Control/ControlStore.swift
index 6c08df4..8e08af9 100644
--- a/Packages/Sources/HubCore/Control/ControlStore.swift
+++ b/Packages/Sources/HubCore/Control/ControlStore.swift
@@ -11,6 +11,14 @@ public enum ControlNotice: Equatable, Sendable {
   case removed(name: String)
   case replaced(name: String)
   case cleared
+  /// The mask was emptied.
+  case maskCleared
+  /// At launch the copy of the saved mask was gone.
+  case maskMissingAtLaunch
+  /// The Brush drawing was emptied.
+  case paintCleared
+  /// At launch the copy of the saved drawing was gone.
+  case paintMissingAtLaunch
   /// At launch the copy of the saved image was gone.
   case missingAtLaunch(name: String)
 }
@@ -55,6 +63,14 @@ public final class ControlStore {
       loaded.framing = Framing()
       notice = .missingAtLaunch(name: image.name)
     }
+    if let mask = loaded.mask, !storage.exists(mask.fileName) {
+      loaded.mask = nil
+      notice = .maskMissingAtLaunch
+    }
+    if let paint = loaded.paint, !storage.exists(paint.fileName) {
+      loaded.paint = nil
+      notice = .paintMissingAtLaunch
+    }
     for entry in loaded.moodboard where !storage.exists(entry.image.fileName) {
       loaded.moodboard.removeAll { $0.id == entry.id }
       notice = .missingAtLaunch(name: entry.image.name)
@@ -90,6 +106,8 @@ public final class ControlStore {
     var next = inputs
     next.image = image
     next.framing = Framing()
+    next.mask = nil  // drawn over the other picture
+    next.paint = nil
     let replaced = inputs.image
     commit(next)
     notice = replaced.map { .replaced(name: $0.name) }
@@ -115,6 +133,8 @@ public final class ControlStore {
     var next = inputs
     next.image = nil
     next.framing = Framing()
+    next.mask = nil
+    next.paint = nil
     commit(next)
     notice = .removed(name: image.name)
   }
@@ -126,6 +146,91 @@ public final class ControlStore {
     notice = .cleared
   }
 
+  // MARK: Mask
+
+  /// The mask as it is drawn, nil when there is none.
+  public func maskBitmap() -> MaskBitmap? {
+    guard let mask = inputs.mask, let image = storage.image(named: mask.fileName, maxPixel: MaskBitmap.maxSide)
+    else { return nil }
+    return MaskBitmap(image: image)
+  }
+
+  /// The size a mask over the start image is drawn at; nil without an image.
+  public var maskSize: (width: Int, height: Int)? {
+    inputs.image.map { MaskBitmap.workingSize(imageWidth: $0.pixelWidth, imageHeight: $0.pixelHeight) }
+  }
+
+  /// Takes the mask as drawn (one step of the history). An empty mask is no mask. Nothing without
+  /// a start image.
+  public func commitMask(_ bitmap: MaskBitmap) throws(ControlError) {
+    guard inputs.image != nil else { return }
+    var next = inputs
+    if bitmap.isEmpty {
+      guard inputs.mask != nil else { return }
+      next.mask = nil
+    } else {
+      guard let data = bitmap.pngData() else { throw .cannotSave("mask") }
+      let stored = try storage.save(data, name: "mask.png")
+      next.mask = MaskReference(fileName: stored.fileName, coverage: bitmap.coverage)
+    }
+    commit(next)
+  }
+
+  /// Paints what was clear and clears what was painted (a mask not drawn yet becomes everything).
+  public func invertMask() throws(ControlError) {
+    guard let size = maskSize else { return }
+    var bitmap = maskBitmap() ?? MaskBitmap(width: size.width, height: size.height)
+    bitmap.invert()
+    try commitMask(bitmap)
+  }
+
+  public func clearMask() {
+    guard inputs.mask != nil else { return }
+    var next = inputs
+    next.mask = nil
+    commit(next)
+    notice = .maskCleared
+  }
+
+  /// How Draw Things treats the mask; not part of the history.
+  public func setMaskSettings(_ settings: MaskSettings) {
+    inputs.maskSettings = settings.clamped()
+    save()
+  }
+
+  // MARK: Drawing (the Brush)
+
+  /// The drawing as it is, nil when there is none.
+  public func paintBitmap() -> PaintBitmap? {
+    guard let paint = inputs.paint, let image = storage.image(named: paint.fileName, maxPixel: MaskBitmap.maxSide)
+    else { return nil }
+    return PaintBitmap(image: image)
+  }
+
+  /// Takes the drawing as it is (one step of the history). An empty drawing is no drawing. Nothing
+  /// without a start image.
+  public func commitPaint(_ bitmap: PaintBitmap) throws(ControlError) {
+    guard inputs.image != nil else { return }
+    var next = inputs
+    if bitmap.isEmpty {
+      guard inputs.paint != nil else { return }
+      next.paint = nil
+    } else {
+      guard let data = bitmap.pngData() else { throw .cannotSave("drawing") }
+      let stored = try storage.save(data, name: "drawing.png")
+      next.paint = PaintReference(fileName: stored.fileName)
+    }
+    commit(next)
+  }
+
+  public func clearPaint() {
+    guard inputs.paint != nil else { return }
+    var next = inputs
+    next.paint = nil
+    commit(next)
+    notice = .paintCleared
+  }
+
   // MARK: Moodboard
 
   /// Adds a picture to the Moodboard (on, at the end).
@@ -297,8 +402,9 @@ public final class ControlStore {
   public func pendingInputs(canvasWidth: Int, canvasHeight: Int, includeMoodboard: Bool = true) -> PendingInputs {
     let sent = inputs.moodboard.filter(\.isOn).map { (image: $0.image, weight: 1.0) }
     return PendingInputs(
-      storage: storage, image: inputs.image, framing: inputs.framing, canvasWidth: canvasWidth,
-      canvasHeight: canvasHeight, moodboard: includeMoodboard ? sent : [])
+      storage: storage, image: inputs.image, mask: inputs.image == nil ? nil : inputs.mask,
+      paint: inputs.image == nil ? nil : inputs.paint, framing: inputs.framing,
+      canvasWidth: canvasWidth, canvasHeight: canvasHeight, moodboard: includeMoodboard ? sent : [])
   }
 
   // MARK: Private
@@ -363,6 +469,8 @@ public final class ControlStore {
     var referenced = Set<String>()
     for state in undoStack + redoStack + [inputs] {
       if let image = state.image { referenced.insert(image.fileName) }
+      if let mask = state.mask { referenced.insert(mask.fileName) }
+      if let paint = state.paint { referenced.insert(paint.fileName) }
       for entry in state.moodboard { referenced.insert(entry.image.fileName) }
     }
     for name in storage.allFileNames() where !referenced.contains(name) { storage.remove(name) }
@@ -373,6 +481,8 @@ public final class ControlStore {
 public struct PendingInputs: Sendable {
   let storage: any ReferenceStorage
   let image: ReferenceImage?
+  let mask: MaskReference?
+  let paint: PaintReference?
   let framing: Framing
   let canvasWidth: Int
   let canvasHeight: Int
@@ -397,10 +507,25 @@ public struct PendingInputs: Sendable {
     let scale = max(Double(canvasWidth) / Double(image.pixelWidth), Double(canvasHeight) / Double(image.pixelHeight))
     let longest = max(image.pixelWidth, image.pixelHeight)
     let maxPixel = scale < 1 ? Int((Double(longest) * scale).rounded(.up)) + 1 : longest
+    var layer: PaintBitmap?
+    if let paint {
+      guard let stored = storage.image(named: paint.fileName, maxPixel: MaskBitmap.maxSide),
+        let bitmap = PaintBitmap(image: stored)
+      else { throw .unreadable(image.name) }
+      layer = bitmap
+    }
     guard let decoded = storage.image(named: image.fileName, maxPixel: maxPixel),
-      let framed = InputComposer.frame(decoded, toWidth: canvasWidth, height: canvasHeight, framing: framing)
+      let framed = InputComposer.frame(
+        decoded, toWidth: canvasWidth, height: canvasHeight, framing: framing, paint: layer)
+    else { throw .unreadable(image.name) }
+    guard let mask else { return GenerationInputs(image: framed, hints: hints) }
+    guard let stored = storage.image(named: mask.fileName, maxPixel: MaskBitmap.maxSide),
+      let bitmap = MaskBitmap(image: stored),
+      let scaled = InputComposer.mask(
+        bitmap, imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, toWidth: canvasWidth,
+        height: canvasHeight, framing: framing)
     else { throw .unreadable(image.name) }
-    return GenerationInputs(image: framed, hints: hints)
+    return GenerationInputs(image: framed, hints: hints, mask: scaled)
   }
 }
 
```

```diff
diff --git a/Packages/Sources/HubCore/Generation/JobComposer.swift b/Packages/Sources/HubCore/Generation/JobComposer.swift
index ee1fd51..d996075 100644
--- a/Packages/Sources/HubCore/Generation/JobComposer.swift
+++ b/Packages/Sources/HubCore/Generation/JobComposer.swift
@@ -9,7 +9,7 @@ public enum JobComposer {
   public static func batches(
     prompt: String, negativePrompt: String, model: String, family: String?,
     parameters: GenerationParameters, catalog: ModelCatalog, imageStrength: Double? = nil,
-    moodboardCount: Int = 0, randomSeed draw: () -> UInt32 = { UInt32.random(in: .min ... .max) }
+    moodboardCount: Int = 0, maskSettings: MaskSettings? = nil, randomSeed draw: () -> UInt32 = { UInt32.random(in: .min ... .max) }
   ) -> [GenerationJob] {
     let traits = FamilyTraits.of(family)
     var sent = parameters
@@ -20,7 +20,7 @@ public enum JobComposer {
     return sent.batchesForRun(randomSeed: draw).map {
       GenerationJob(
         prompt: prompt, negativePrompt: negative, model: model, parameters: $0, imageStrength: imageStrength,
-        moodboardCount: moodboardCount)
+        moodboardCount: moodboardCount, maskSettings: maskSettings)
     }
   }
 
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubCore `300 tests … passed` (25 nuovi); totale **436**.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: maschera e disegno nello store (un passo per tratto, copie, ripristino) e negli ingressi del RUN

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `CanvasDrawing` — maschera e disegno mentre si disegna (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Control/CanvasDrawing.swift`
- Test: `Packages/Tests/HubCoreTests/CanvasDrawingTests.swift` (nuovo)

**Interfaces:**
- Consumes: `ControlStore` (Task 5), `MaskBitmap`/`MaskOverlay`, `PaintBitmap`/`PaintOverlay`, `StrokeSmoother` (Task 3).
- Produces: `enum DrawingTool { maskAdd, maskRemove, brush }` e `@MainActor @Observable final class CanvasDrawing`: `maskImage`, `paintImage` (`CGImage?` per lo schermo), `sync(with:)` (rilegge dallo store solo se immagine, maschera o disegno sono cambiati; un tratto appena consegnato non si rilegge), `isStroking`, `stroke(tool:to:viewSize:crop:imageWidth:canvasWidth:diameter:color:)` (aggiorna solo il rettangolo toccato; strumento e colore valgono dal primo punto del tratto), `endStroke(into:) throws(ControlError)` (porta il tratto all'ultimo punto e lo consegna allo store).

- [ ] **Step 1: Scrivere i test che falliscono**

```swift
import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct CanvasDrawingTests {
  func store() throws -> ControlStore {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CanvasDrawingTests-\(UUID())", isDirectory: true)
    let store = ControlStore(
      storage: FileReferenceStorage(folder: root.appendingPathComponent("Control", isDirectory: true)),
      fileURL: root.appendingPathComponent("control.json"))
    try store.setImage(data: pictureData(width: 400, height: 300), name: "a.png", source: .pasteboard)
    return store
  }

  let crop = CGRect(x: 0, y: 0, width: 400, height: 300)
  let view = CGSize(width: 400, height: 300)

  func drag(
    _ drawing: CanvasDrawing, _ tool: DrawingTool, through points: [CGPoint], into control: ControlStore,
    color: (red: UInt8, green: UInt8, blue: UInt8) = (200, 20, 20)
  ) throws {
    for point in points {
      drawing.stroke(
        tool: tool, to: point, viewSize: view, crop: crop, imageWidth: 400, canvasWidth: 400, diameter: 20, color: color)
    }
    try drawing.endStroke(into: control)
  }

  @Test func withoutAnImageThereIsNothingToShow() throws {
    let drawing = CanvasDrawing()
    let empty = ControlStore(
      storage: FileReferenceStorage(folder: FileManager.default.temporaryDirectory.appendingPathComponent("CD-\(UUID())")),
      fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("cd-\(UUID()).json"))
    drawing.sync(with: empty)
    #expect(drawing.maskImage == nil && drawing.paintImage == nil)
    // Drawing does nothing.
    drawing.stroke(tool: .maskAdd, to: .zero, viewSize: view, crop: crop, imageWidth: 400, canvasWidth: 400, diameter: 10, color: (0, 0, 0))
    #expect(!drawing.isStroking)
  }

  @Test func aMaskStrokeShowsAtOnceAndEndsInTheStore() throws {
    let control = try store()
    let drawing = CanvasDrawing()
    drawing.sync(with: control)
    #expect(drawing.maskImage == nil)
    drawing.stroke(tool: .maskAdd, to: CGPoint(x: 100, y: 100), viewSize: view, crop: crop, imageWidth: 400, canvasWidth: 400, diameter: 20, color: (0, 0, 0))
    #expect(drawing.isStroking)
    #expect(drawing.maskImage != nil)
    #expect(control.inputs.mask == nil)  // not yet: the stroke is not over
    drawing.stroke(tool: .maskAdd, to: CGPoint(x: 200, y: 100), viewSize: view, crop: crop, imageWidth: 400, canvasWidth: 400, diameter: 20, color: (0, 0, 0))
    try drawing.endStroke(into: control)
    #expect(!drawing.isStroking)
    let reference = try #require(control.inputs.mask)
    #expect(reference.coverage > 0)
    let bitmap = try #require(control.maskBitmap())
    // The stroke reaches the last point (the end is carried to it) and the middle.
    #expect(bitmap.pixels[100 * bitmap.width + 200] >= 128)
    #expect(bitmap.pixels[100 * bitmap.width + 150] >= 128)
    #expect(bitmap.pixels[250 * bitmap.width + 50] == 0)
  }

  @Test func aStrokeCommittedHereIsNotReadBack() throws {
    let control = try store()
    let drawing = CanvasDrawing()
    drawing.sync(with: control)
    try drag(drawing, .maskAdd, through: [CGPoint(x: 50, y: 50), CGPoint(x: 120, y: 60)], into: control)
    let shown = drawing.maskImage
    drawing.sync(with: control)
    #expect(drawing.maskImage === shown)
  }

  @Test func undoAndRedoBringTheMaskBack() throws {
    let control = try store()
    let drawing = CanvasDrawing()
    drawing.sync(with: control)
    try drag(drawing, .maskAdd, through: [CGPoint(x: 50, y: 50), CGPoint(x: 120, y: 60)], into: control)
    control.undo()
    drawing.sync(with: control)
    #expect(drawing.maskImage == nil)
    control.redo()
    drawing.sync(with: control)
    #expect(drawing.maskImage != nil)
  }

  @Test func theEraserTakesTheMaskAway() throws {
    let control = try store()
    let drawing = CanvasDrawing()
    drawing.sync(with: control)
    try drag(drawing, .maskAdd, through: [CGPoint(x: 50, y: 150), CGPoint(x: 350, y: 150)], into: control)
    let before = try #require(control.inputs.mask).coverage
    try drag(drawing, .maskRemove, through: [CGPoint(x: 150, y: 150), CGPoint(x: 250, y: 150)], into: control)
    #expect(try #require(control.inputs.mask).coverage < before)
  }

  @Test func theBrushDrawsInTheChosenColour() throws {
    let control = try store()
    let drawing = CanvasDrawing()
    drawing.sync(with: control)
    try drag(drawing, .brush, through: [CGPoint(x: 100, y: 100), CGPoint(x: 220, y: 100)], into: control, color: (10, 200, 30))
    #expect(drawing.paintImage != nil)
    #expect(control.inputs.mask == nil)
    let layer = try #require(control.paintBitmap())
    #expect(layer.alpha(x: 150, y: 100) == 255)
    #expect(layer.color(x: 150, y: 100).green == 200)
  }

  @Test func aSparseStrokeIsCurvedNotCornered() throws {
    let control = try store()
    let drawing = CanvasDrawing()
    drawing.sync(with: control)
    // Three far-apart points: a straight join would pass (200, 50) → (200, 250) with a sharp corner at (200, 50);
    // the smoothed stroke does not reach the corner pixel with a thin brush.
    for point in [CGPoint(x: 20, y: 50), CGPoint(x: 200, y: 50), CGPoint(x: 200, y: 250)] {
      drawing.stroke(tool: .brush, to: point, viewSize: view, crop: crop, imageWidth: 400, canvasWidth: 400, diameter: 6, color: (255, 0, 0))
    }
    try drawing.endStroke(into: control)
    let layer = try #require(control.paintBitmap())
    #expect(layer.alpha(x: 20, y: 50) == 255)  // starts at the first point
    #expect(layer.alpha(x: 200, y: 250) == 255)  // and the end reaches the last one
    #expect(layer.alpha(x: 200, y: 50) == 0)  // the corner is rounded off
    // The curve goes from the middle (110, 50) through the corner's side to the middle (200, 150): at its
    // own middle it is at (177.5, 75).
    #expect(layer.alpha(x: 177, y: 75) == 255)
  }

  @Test func aNewImageStartsClean() throws {
    let control = try store()
    let drawing = CanvasDrawing()
    drawing.sync(with: control)
    try drag(drawing, .maskAdd, through: [CGPoint(x: 50, y: 50), CGPoint(x: 120, y: 60)], into: control)
    try drag(drawing, .brush, through: [CGPoint(x: 50, y: 50), CGPoint(x: 120, y: 60)], into: control)
    try control.setImage(data: pictureData(width: 100, height: 100), name: "b.png", source: .pasteboard)
    drawing.sync(with: control)
    #expect(drawing.maskImage == nil && drawing.paintImage == nil)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter CanvasDrawingTests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'CanvasDrawing' in scope`.

- [ ] **Step 3: Implementare**

```swift
import CoreGraphics
import Foundation
import HubKit
import Observation

/// What the Draw mode of the canvas draws with.
public enum DrawingTool: Hashable, Sendable {
  /// Paints the mask: the area to regenerate.
  case maskAdd
  /// Takes mask away.
  case maskRemove
  /// Draws in colour on the image.
  case brush
}

/// The mask and the Brush drawing while they are being drawn (tab Control spec §3): read from the
/// store, changed by the tools a point at a time, given back to the store when the stroke ends.
/// The images for the screen (`maskImage`, `paintImage`) are updated in place, so a stroke costs a
/// few milliseconds whatever the size of the picture.
@MainActor
@Observable
public final class CanvasDrawing {
  /// The mask as a translucent orange, nil when there is no mask.
  public private(set) var maskImage: CGImage?
  /// The Brush drawing, nil when there is none.
  public private(set) var paintImage: CGImage?

  @ObservationIgnored private var mask: MaskBitmap?
  @ObservationIgnored private var paint: PaintBitmap?
  @ObservationIgnored private var maskOverlay: MaskOverlay?
  @ObservationIgnored private var paintOverlay: PaintOverlay?
  @ObservationIgnored private var loaded: Key?
  @ObservationIgnored private var smoother = StrokeSmoother()
  @ObservationIgnored private var strokeTool = DrawingTool.maskAdd
  @ObservationIgnored private var strokeRadius = 1.0
  @ObservationIgnored private var strokeColor: (red: UInt8, green: UInt8, blue: UInt8) = (255, 0, 0)

  private struct Key: Equatable {
    let image: UUID?
    let mask: String?
    let paint: String?
  }

  /// The orange of the mask on the screen.
  private static let maskColor: (red: UInt8, green: UInt8, blue: UInt8) = (255, 140, 0)

  public init() {}

  /// Reads the mask and the drawing from the store when the image, the mask or the drawing changed
  /// under us (undo, redo, clear, a new image); what was just drawn here is already on screen.
  public func sync(with control: ControlStore) {
    let key = Key(
      image: control.inputs.image?.id, mask: control.inputs.mask?.fileName, paint: control.inputs.paint?.fileName)
    guard key != loaded else { return }
    guard let size = control.maskSize else {
      mask = nil
      paint = nil
      maskOverlay = nil
      paintOverlay = nil
      maskImage = nil
      paintImage = nil
      loaded = key
      return
    }
    let bitmap = control.maskBitmap() ?? MaskBitmap(width: size.width, height: size.height)
    let buffer = MaskOverlay(
      width: size.width, height: size.height, red: Self.maskColor.red, green: Self.maskColor.green,
      blue: Self.maskColor.blue, opacity: 0.55)
    if !bitmap.isEmpty { buffer?.rebuild(from: bitmap) }
    mask = bitmap
    maskOverlay = buffer
    maskImage = bitmap.isEmpty ? nil : buffer?.image()
    let layer = control.paintBitmap() ?? PaintBitmap(width: size.width, height: size.height)
    let layerBuffer = PaintOverlay(width: size.width, height: size.height)
    if !layer.isEmpty { layerBuffer?.rebuild(from: layer) }
    paint = layer
    paintOverlay = layerBuffer
    paintImage = layer.isEmpty ? nil : layerBuffer?.image()
    loaded = key
  }

  /// True while a stroke is under way.
  public var isStroking: Bool { smoother.isActive }

  /// Continues a stroke (or starts it) at a point of the view. The view shows the cut `crop` (in the
  /// start image's pixels) of the image `imageWidth` pixels wide, and fills `viewSize`; `diameter`
  /// is the tool's size in canvas pixels. A new `tool` or `color` takes effect with the next stroke.
  public func stroke(
    tool: DrawingTool, to point: CGPoint, viewSize: CGSize, crop: CGRect, imageWidth: Int, canvasWidth: Int,
    diameter: Double, color: (red: UInt8, green: UInt8, blue: UInt8)
  ) {
    guard let reference = mask, imageWidth > 0, viewSize.width > 0, viewSize.height > 0 else { return }
    if !smoother.isActive {
      strokeTool = tool
      strokeColor = color
      strokeRadius = reference.brushRadius(diameter: diameter, canvasWidth: canvasWidth, crop: crop, imageWidth: imageWidth)
    }
    let target = reference.point(forViewPoint: point, viewSize: viewSize, crop: crop, imageWidth: imageWidth)
    draw(smoother.add(target, spacing: max(strokeRadius / 2, 1)))
  }

  /// Ends the stroke and gives what was drawn to the store (one step of its history).
  public func endStroke(into control: ControlStore) throws(ControlError) {
    guard smoother.isActive else { return }
    draw(smoother.finish())
    switch strokeTool {
    case .maskAdd, .maskRemove:
      if let mask { try control.commitMask(mask) }
    case .brush:
      if let paint { try control.commitPaint(paint) }
    }
    loaded = Key(
      image: control.inputs.image?.id, mask: control.inputs.mask?.fileName, paint: control.inputs.paint?.fileName)
  }

  /// Strokes along the points, then refreshes the picture of the layer that changed.
  private func draw(_ points: [CGPoint]) {
    guard let first = points.first else { return }
    var dirty = CGRect.null
    // A single point is a dot: stroked from itself to itself.
    let rest = points.count > 1 ? Array(points.dropFirst()) : [first]
    switch strokeTool {
    case .maskAdd, .maskRemove:
      guard var bitmap = mask else { return }
      mask = nil  // the one reference, so the buffer is changed in place
      var from = first
      for to in rest {
        dirty = dirty.union(bitmap.stroke(from: from, to: to, radius: strokeRadius, erase: strokeTool == .maskRemove))
        from = to
      }
      mask = bitmap
      maskOverlay?.update(from: bitmap, rect: dirty)
      maskImage = maskOverlay?.image()
    case .brush:
      guard var layer = paint else { return }
      paint = nil
      var from = first
      for to in rest {
        dirty = dirty.union(
          layer.stroke(
            from: from, to: to, radius: strokeRadius, red: strokeColor.red, green: strokeColor.green,
            blue: strokeColor.blue))
        from = to
      }
      paint = layer
      paintOverlay?.update(from: layer, rect: dirty)
      paintImage = paintOverlay?.image()
    }
  }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubCore `308 tests … passed` (8 nuovi); totale **444**.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: CanvasDrawing — maschera e disegno mentre si disegna, aggiornati sul posto

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: I testi della maschera (catalogo)

**Files:**
- Modify: `App/Localizable.xcstrings` (23 chiavi nuove)
- Test: `Packages/Tests/CatalogTests/LocalizationCatalogTests.swift` (esistente)

**Interfaces:**
- Produces: le chiavi `control.strip.mask`, `control.strip.paint`, `control.stage.mode.*`, `control.tool.*`, `control.brush.color`, `control.paint.clear`, `control.mask.*`, `control.redo`, `control.notice.maskCleared`, `control.notice.maskMissing`, `control.notice.paintCleared`, `control.notice.paintMissing`, `control.strength.mask`, usate dalle viste del Task 8.

- [ ] **Step 1: Aggiungere le chiavi senza riformattare il catalogo**

Salvare lo script seguente in un file temporaneo ed eseguirlo dalla radice del repository (`python3 <file>`):

```python
import json
p = 'App/Localizable.xcstrings'
d = json.load(open(p))
new = {
    "control.strip.mask": ("Mask", "Maschera"),
    "control.stage.mode.canvas": ("Canvas", "Canvas"),
    "control.stage.mode.draw": ("Draw", "Disegno"),
    "control.tool.maskAdd": ("Mask +", "Maschera +"),
    "control.tool.maskRemove": ("Mask −", "Maschera −"),
    "control.tool.brush": ("Brush", "Pennello"),
    "control.brush.color": ("Colour", "Colore"),
    "control.paint.clear": ("Clear drawing", "Svuota disegno"),
    "control.strip.paint": ("Drawing", "Disegno"),
    "control.notice.paintCleared": ("Drawing cleared.", "Disegno svuotato."),
    "control.notice.paintMissing": ("The saved drawing was gone and was dropped.", "Il disegno salvato non c'era più ed è stato scartato."),
    "control.mask.size": ("Size", "Dimensione"),
    "control.mask.invert": ("Invert", "Inverti"),
    "control.mask.clear": ("Clear", "Svuota"),
    "control.mask.blur": ("Blur", "Sfumatura"),
    "control.mask.outset": ("Margin", "Margine"),
    "control.mask.preserve": ("Keep the original outside the mask", "Conserva l'originale fuori dalla maschera"),
    "control.mask.blur.help": ("How much the edge of the mask is softened.", "Quanto si ammorbidisce il bordo della maschera."),
    "control.mask.outset.help": ("How far the area around the mask is taken into the render.", "Quanto dell'area intorno alla maschera entra nel render."),
    "control.redo": ("Redo", "Ripeti"),
    "control.notice.maskCleared": ("Mask cleared.", "Maschera svuotata."),
    "control.notice.maskMissing": ("The saved mask was gone and was dropped.", "La maschera salvata non c'era più ed è stata scartata."),
    "control.strength.mask": ("With a mask the strength is 100%: the painted area is regenerated whole.", "Con la maschera la forza è al 100%: l'area dipinta viene rigenerata per intero."),
}
for key, (en, it) in new.items():
    assert key not in d['strings'], key
    d['strings'][key] = {"extractionState": "manual", "localizations": {
        "en": {"stringUnit": {"state": "translated", "value": en}},
        "it": {"stringUnit": {"state": "translated", "value": it}}}}
d['strings'] = dict(sorted(d['strings'].items()))
open(p, 'w').write(json.dumps(d, ensure_ascii=False, indent=2))
```

Run: `cd "/Users/existenz/Software developement/DT Hub" && git diff --stat App/Localizable.xcstrings | tail -1`
Expected: `1 file changed, 391 insertions(+)` e nessuna riga tolta.

- [ ] **Step 2: Verificare il catalogo**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter CatalogTests 2>&1 | grep -E "Test run with|Missing|Not in"`
Expected: `6 tests … passed` (le chiavi non ancora usate non sono un errore).

- [ ] **Step 3: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add App/Localizable.xcstrings && git commit -m "feat: testi della maschera (it, en)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: La card Canvas con il Disegno e i collegamenti (App)

**Files:**
- Modify: `App/Control/CanvasStage.swift` (riscritta: la card unica), `ControlStrip.swift`, `ControlTabView.swift`, `ControlText.swift`, `ImageCard.swift`, `App/Generation/GenerationController.swift`

**Interfaces:**
- Consumes: tutto ciò che producono i Task 1–7; `CanvasDrawing`, `DrawingTool`, `GenerationController.selectedModel(in:)` (esistente).
- Produces:
  - `CanvasStage(generation:report:)`: una sola card con il selettore Canvas/Disegno largo quanto la card; **Canvas** = come in M7a (immagine intera con il ritaglio oscurato, trascinamento per scegliere la parte, dimensioni e perdita) più disegno e maschera in sola vista; **Disegno** = il canvas come parte a Draw Things, strati separati (immagine, disegno, maschera) e cerchio dello strumento, con la toolbar di icone (Maschera + e Maschera − con la gomma e un + o un −, Pennello, poi Inverti e Svuota oppure Colore e Svuota disegno, in fondo Annulla e Ripeti), il cursore Dimensione, e Sfumatura, Margine e "Conserva l'originale" con gli strumenti maschera o quando c'è una maschera; le immagini prendono tutta la larghezza della card fino a quanto l'altezza della finestra permette (`sized(ratio:)`, `controlViewportHeight`);
  - `ControlTabView` passa l'altezza della finestra con un valore d'ambiente e la scheda sostituisce Canvas e Maschera di prima;
  - il chip "Disegno" e il chip "Maschera N%" nella striscia (✕ = `clearPaint`/`clearMask`);
  - il testo della forza che dice «con la maschera 100%»;
  - il RUN: `maskSettings` nel job solo con una maschera, `enableInpainting` dal modello (`needsInpaintControl`), "Riprendi parametri" rimette le impostazioni.

Questo task è codice di vista: la verifica è la compilazione (Step 3) e la prova dal vivo (Task 9).

- [ ] **Step 1: Riscrivere la card**

```swift
import AppKit
import HubCore
import HubKit
import SwiftUI

/// The canvas (spec: tab Control §3, §5), in two modes. **Canvas** shows the start image with the
/// part that is cut off darkened; dragging moves the cut along the axis that is cropped. **Draw**
/// shows the canvas as Draw Things will get it, with the tools: Mask + (paints the area to
/// regenerate, in orange), Mask − (takes it away) and Brush (draws in colour on the image).
/// Each stroke is one step of the tab's history (⌘Z).
struct CanvasStage: View {
  let generation: GenerationController
  /// Reports what went wrong while drawing.
  let report: (ControlMessage) -> Void

  private enum Mode: Hashable {
    case canvas, draw
  }

  @State private var picture: CGImage?
  @State private var mode = Mode.canvas
  @State private var tool = DrawingTool.maskAdd
  @State private var dragStart: Framing?
  /// The mask and the drawing while they are drawn (the images are updated in place).
  @State private var drawing = CanvasDrawing()
  @State private var hover: CGPoint?
  @State private var brushColor = Color.red
  @State private var brushRGB: (red: UInt8, green: UInt8, blue: UInt8) = (255, 59, 48)
  /// The tools' diameter in canvas pixels.
  @AppStorage("control.brushSize") private var brushSize = 96.0

  /// The height of the tab's window: the pictures grow with it.
  @Environment(\.controlViewportHeight) private var viewportHeight

  private var control: ControlStore { generation.control }
  private var canvasWidth: Int { generation.parameters.width }
  private var canvasHeight: Int { generation.parameters.height }
  /// What the drawing was read from: when it changes (undo, redo, clear, a new image) it is read again.
  private var key: [String?] {
    [control.inputs.image?.id.uuidString, control.inputs.mask?.fileName, control.inputs.paint?.fileName]
  }

  var body: some View {
    DSCollapsibleCard(
      String(localized: "control.stage.title"), systemImage: "rectangle.dashed",
      isExpanded: generation.cards.binding("control.stage")
    ) {
      VStack(spacing: DS.rowGap) {
        if let image = control.inputs.image {
          modePicker
          if mode == .draw { tools }
          if mode == .canvas {
            stage(for: image)
            caption(for: image)
          } else {
            drawArea(for: image)
            if tool != .brush || control.inputs.mask != nil { maskSettings }
          }
        } else {
          empty
        }
      }
    }
    .task(id: control.inputs.image?.id) {
      guard let request = control.previewRequest(maxPixel: 1400) else { return picture = nil }
      picture = await Task.detached { request.render() }.value
    }
    .task(id: key) { drawing.sync(with: control) }
    .onChange(of: brushColor) { brushRGB = rgb(of: brushColor) }
  }

  /// The two modes, as wide as the card: the top of the card's hierarchy.
  private var modePicker: some View {
    HStack(spacing: 2) {
      modeButton("control.stage.mode.canvas", .canvas)
      modeButton("control.stage.mode.draw", .draw)
    }
    .padding(2)
    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.08)))
  }

  private func modeButton(_ label: LocalizedStringResource, _ value: Mode) -> some View {
    Button {
      mode = value
    } label: {
      Text(label).font(.callout.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(mode == value ? DS.accent : Color.clear))
        .foregroundStyle(mode == value ? Color.white : Color.primary)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var empty: some View {
    ZStack {
      RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
        .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
      Text("control.stage.empty").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        .padding()
    }
    .aspectRatio(Double(canvasWidth) / Double(max(canvasHeight, 1)), contentMode: .fit)
    .frame(maxHeight: 300)
  }

  // MARK: Canvas mode

  /// A picture area of the given ratio as large as the card and the window allow, centered: a
  /// rectangle that takes the card's width (up to what the window's height allows for this ratio) and
  /// puts the content over it.
  private func sized<Content: View>(ratio: Double, @ViewBuilder content: () -> Content) -> some View {
    let tallest = max(340, viewportHeight - 330)
    return Color.clear
      .aspectRatio(ratio, contentMode: .fit)
      .frame(maxWidth: tallest * ratio)
      .overlay { content() }
      .frame(maxWidth: .infinity)
  }

  private func stage(for image: ReferenceImage) -> some View {
    sized(ratio: Double(image.pixelWidth) / Double(max(image.pixelHeight, 1))) {
      stageContent(for: image)
    }
  }

  private func stageContent(for image: ReferenceImage) -> some View {
    GeometryReader { geometry in
      let size = geometry.size
      let crop = FramingMath.cropRect(
        imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
        canvasHeight: canvasHeight, framing: control.inputs.framing)
      let rect = CGRect(
        x: crop.minX / Double(image.pixelWidth) * size.width, y: crop.minY / Double(image.pixelHeight) * size.height,
        width: crop.width / Double(image.pixelWidth) * size.width,
        height: crop.height / Double(image.pixelHeight) * size.height)
      ZStack {
        if let picture {
          Image(decorative: picture, scale: 1).resizable().interpolation(.high)
        } else {
          Color.primary.opacity(0.08)
        }
        if let paintImage = drawing.paintImage { Image(decorative: paintImage, scale: 1).resizable().interpolation(.high) }
        if let maskImage = drawing.maskImage { Image(decorative: maskImage, scale: 1).resizable().interpolation(.high) }
        Path { path in
          path.addRect(CGRect(origin: .zero, size: size))
          path.addRect(rect)
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        Rectangle().strokeBorder(DS.accent, lineWidth: 2).frame(width: rect.width, height: rect.height)
          .position(x: rect.midX, y: rect.midY)
      }
      .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
      .contentShape(Rectangle())
      .gesture(
        DragGesture()
          .onChanged { value in
            let start = dragStart ?? control.inputs.framing
            dragStart = start
            move(from: start, by: value.translation, in: size, image: image, crop: crop)
          }
          .onEnded { _ in dragStart = nil })
    }
  }

  /// The cut follows the pointer along the cropped axis; the other axis has nothing to move.
  private func move(from start: Framing, by translation: CGSize, in size: CGSize, image: ReferenceImage, crop: CGRect) {
    let slackX = Double(image.pixelWidth) - crop.width
    let slackY = Double(image.pixelHeight) - crop.height
    var x = start.offsetX
    var y = start.offsetY
    if slackX > 0.5 {
      x += translation.width * (Double(image.pixelWidth) / size.width) / (slackX / 2)
    }
    if slackY > 0.5 {
      y += translation.height * (Double(image.pixelHeight) / size.height) / (slackY / 2)
    }
    control.setOffset(x: x, y: y)
  }

  @ViewBuilder private func caption(for image: ReferenceImage) -> some View {
    let loss = FramingMath.loss(
      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
      canvasHeight: canvasHeight)
    VStack(alignment: .leading, spacing: 2) {
      Text(
        String(
          format: String(localized: "control.stage.size"), canvasWidth, canvasHeight)
      )
      .font(.caption).foregroundStyle(.secondary)
      if let axis = loss.axis {
        Text(
          String(
            format: String(localized: axis == .vertical ? "control.stage.loss.vertical" : "control.stage.loss.horizontal"),
            Int((loss.fraction * 100).rounded()))
        )
        .font(.caption).foregroundStyle(.secondary)
        Text("control.stage.drag").font(.caption).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: Draw mode: tools

  /// One row like a toolbar: the tools, then what belongs to the tool chosen (invert and clear for the
  /// mask, the colour and clear for the Brush), and Undo and Redo at the end. Icons only: the names
  /// are in the tooltips.
  private var tools: some View {
    VStack(alignment: .leading, spacing: DS.controlGap) {
      HStack(spacing: DS.controlGap) {
        HStack(spacing: 2) {
          toolButton("eraser", badge: "plus", "control.tool.maskAdd", .maskAdd)
          toolButton("eraser", badge: "minus", "control.tool.maskRemove", .maskRemove)
          toolButton("paintbrush.pointed", badge: nil, "control.tool.brush", .brush)
        }
        Divider().frame(height: 18)
        if tool == .brush {
          ColorPicker(String(localized: "control.brush.color"), selection: $brushColor, supportsOpacity: false)
            .labelsHidden()
            .frame(width: 44)
            .help(String(localized: "control.brush.color"))
          iconButton("trash", "control.paint.clear", tint: DS.remove, enabled: control.inputs.paint != nil) {
            control.clearPaint()
          }
        } else {
          iconButton("circle.lefthalf.filled", "control.mask.invert") {
            attempt { () throws(ControlError) in try control.invertMask() }
          }
          iconButton("trash", "control.mask.clear", tint: DS.remove, enabled: control.inputs.mask != nil) {
            control.clearMask()
          }
        }
        Spacer(minLength: 0)
        iconButton("arrow.uturn.backward", "control.undo", enabled: control.canUndo) { control.undo() }
        iconButton("arrow.uturn.forward", "control.redo", enabled: control.canRedo) { control.redo() }
      }
      CardRow(label: String(localized: "control.mask.size")) {
        Slider(value: $brushSize, in: 8...512, step: 1).frame(minWidth: 120)
      } control: {
        Text(verbatim: "\(Int(brushSize)) px").font(.callout).monospacedDigit().foregroundStyle(.secondary)
          .frame(width: 64, alignment: .trailing)
      }
    }
  }

  private func toolButton(
    _ systemImage: String, badge: String?, _ label: LocalizedStringResource, _ value: DrawingTool
  ) -> some View {
    Button {
      tool = value
    } label: {
      HStack(spacing: 1) {
        Image(systemName: systemImage).font(.system(size: 14, weight: .medium))
        if let badge { Image(systemName: badge).font(.system(size: 9, weight: .heavy)) }
      }
      .frame(width: 38, height: 26)
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tool == value ? DS.accent : Color.clear)
        )
        .foregroundStyle(tool == value ? Color.white : Color.primary)
    }
    .buttonStyle(.plain)
    .help(String(localized: label))
    .accessibilityLabel(Text(label))
  }

  private func iconButton(
    _ systemImage: String, _ label: LocalizedStringResource, tint: Color = .primary, enabled: Bool = true,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage).font(.system(size: 14, weight: .medium))
        .frame(width: 30, height: 26)
        .foregroundStyle(enabled ? tint : Color.secondary.opacity(0.5))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .help(String(localized: label))
    .accessibilityLabel(Text(label))
  }

  private var maskSettings: some View {
    let binding = Binding(get: { control.inputs.maskSettings }, set: { control.setMaskSettings($0) })
    return VStack(alignment: .leading, spacing: DS.controlGap) {
      CardRow(label: String(localized: "control.mask.blur")) {
        Slider(
          value: Binding(get: { binding.wrappedValue.blur }, set: { binding.wrappedValue.blur = $0 }),
          in: MaskSettings.blurRange, step: 0.5
        )
        .frame(minWidth: 120)
      } control: {
        Text(verbatim: binding.wrappedValue.blur.formatted(.number.precision(.fractionLength(1))))
          .font(.callout).monospacedDigit().foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
      }
      .help(String(localized: "control.mask.blur.help"))
      CardRow(label: String(localized: "control.mask.outset")) {
        Slider(
          value: Binding(
            get: { Double(binding.wrappedValue.outset) }, set: { binding.wrappedValue.outset = Int($0.rounded()) }),
          in: Double(MaskSettings.outsetRange.lowerBound)...Double(MaskSettings.outsetRange.upperBound), step: 1
        )
        .frame(minWidth: 120)
      } control: {
        Text(verbatim: "\(binding.wrappedValue.outset)")
          .font(.callout).monospacedDigit().foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
      }
      .help(String(localized: "control.mask.outset.help"))
      Toggle(
        isOn: Binding(
          get: { binding.wrappedValue.preserveOriginal }, set: { binding.wrappedValue.preserveOriginal = $0 })
      ) {
        Text("control.mask.preserve")
      }
    }
  }

  // MARK: Draw mode: painting

  private func drawArea(for image: ReferenceImage) -> some View {
    let crop = FramingMath.cropRect(
      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
      canvasHeight: canvasHeight, framing: control.inputs.framing)
    return sized(ratio: Double(canvasWidth) / Double(max(canvasHeight, 1))) {
      GeometryReader { geometry in
        painting(image: image, crop: crop, size: geometry.size)
      }
    }
  }

  /// The picture, the drawing and the mask are layers of their own, so a stroke only changes the
  /// layer it draws on; the cursor ring moves over them.
  private func painting(image: ReferenceImage, crop: CGRect, size: CGSize) -> some View {
    // The whole image, placed so that the cut fills the view: what shows is what is sent.
    let scale = size.width / crop.width
    let frame = CGSize(width: Double(image.pixelWidth) * scale, height: Double(image.pixelHeight) * scale)
    let origin = CGPoint(x: -crop.minX * scale, y: -crop.minY * scale)
    func layer(_ picture: CGImage?) -> some View {
      Group {
        if let picture { Image(decorative: picture, scale: 1).resizable().interpolation(.high) }
      }
      .frame(width: frame.width, height: frame.height)
      .position(x: origin.x + frame.width / 2, y: origin.y + frame.height / 2)
    }
    return ZStack(alignment: .topLeading) {
      Color.primary.opacity(0.08)
      layer(picture)
      layer(drawing.paintImage)
      layer(drawing.maskImage)
      if let hover {
        let radius = brushSize / 2 * size.width / Double(max(canvasWidth, 1))
        ZStack {
          Circle().stroke(Color.black.opacity(0.6), lineWidth: 2.5)
          Circle().stroke(Color.white, lineWidth: 1.2)
        }
        .frame(width: radius * 2, height: radius * 2)
        .position(hover)
        .allowsHitTesting(false)
      }
    }
    .frame(width: size.width, height: size.height)
    .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
    .contentShape(Rectangle())
    .onContinuousHover { phase in
      switch phase {
      case .active(let point): hover = point
      case .ended: hover = nil
      }
    }
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          hover = value.location
          drawing.stroke(
            tool: tool, to: value.location, viewSize: size, crop: crop, imageWidth: image.pixelWidth,
            canvasWidth: canvasWidth, diameter: brushSize, color: brushRGB)
        }
        .onEnded { _ in
          attempt { () throws(ControlError) in try drawing.endStroke(into: control) }
        })
  }

  private func rgb(of color: Color) -> (red: UInt8, green: UInt8, blue: UInt8) {
    let converted = NSColor(color).usingColorSpace(.sRGB) ?? .red
    func byte(_ value: CGFloat) -> UInt8 { UInt8(min(255, max(0, (value * 255).rounded()))) }
    return (byte(converted.redComponent), byte(converted.greenComponent), byte(converted.blueComponent))
  }

  private func attempt(_ action: () throws(ControlError) -> Void) {
    do { try action() } catch { report(.error(ControlText.error(error))) }
  }
}
```

- [ ] **Step 2: Applicare le modifiche ai file esistenti**

```diff
diff --git a/App/Control/ControlStrip.swift b/App/Control/ControlStrip.swift
index b95b593..905f7a9 100644
--- a/App/Control/ControlStrip.swift
+++ b/App/Control/ControlStrip.swift
@@ -22,6 +22,16 @@ struct ControlStrip: View {
             detail: "\(image.pixelWidth)×\(image.pixelHeight)",
             remove: { control.removeImage() })
         }
+        if control.inputs.paint != nil {
+          chip(
+            systemImage: "paintbrush", title: String(localized: "control.strip.paint"), detail: "",
+            remove: { control.clearPaint() })
+        }
+        if let mask = control.inputs.mask {
+          chip(
+            systemImage: "paintbrush.pointed", title: String(localized: "control.strip.mask"),
+            detail: "\(max(1, Int((mask.coverage * 100).rounded())))%", remove: { control.clearMask() })
+        }
         if !control.inputs.moodboard.isEmpty {
           chip(
             systemImage: "square.grid.2x2", title: String(localized: "control.strip.moodboard"),
```

```diff
diff --git a/App/Control/ControlTabView.swift b/App/Control/ControlTabView.swift
index db5ed10..e993a65 100644
--- a/App/Control/ControlTabView.swift
+++ b/App/Control/ControlTabView.swift
@@ -2,8 +2,8 @@ import HubCore
 import HubKit
 import SwiftUI
 
-/// The Control tab (spec: tab Control): what goes into a RUN besides the prompt. In this first
-/// step the start image; the Moodboard and the mask come next.
+/// The Control tab (spec: tab Control): what goes into a RUN besides the prompt: the start image,
+/// the Moodboard and the inpaint mask.
 struct ControlTabView: View {
   let generation: GenerationController
   let connection: DrawThingsConnection
@@ -14,6 +14,13 @@ struct ControlTabView: View {
   private var control: ControlStore { generation.control }
 
   var body: some View {
+    // The window's height goes down to the cards, so the pictures can grow with it.
+    GeometryReader { proxy in
+      content.environment(\.controlViewportHeight, proxy.size.height)
+    }
+  }
+
+  private var content: some View {
     ScrollView {
       VStack(spacing: DS.groupGap) {
         ControlStrip(generation: generation, connection: connection)
@@ -23,7 +30,7 @@ struct ControlTabView: View {
             ImageCard(generation: generation, connection: connection) { message = $0 }
             MoodboardCard(generation: generation, connection: connection) { message = $0 }
           }
-          CanvasStage(generation: generation)
+          CanvasStage(generation: generation) { message = $0 }
         }
       }
       .padding(.bottom, DS.groupGap)
@@ -94,3 +101,15 @@ struct ControlTabView: View {
     .dsPanel()
   }
 }
+
+private struct ControlViewportHeightKey: EnvironmentKey {
+  static let defaultValue: Double = 700
+}
+
+extension EnvironmentValues {
+  /// The height of the Control tab's window.
+  var controlViewportHeight: Double {
+    get { self[ControlViewportHeightKey.self] }
+    set { self[ControlViewportHeightKey.self] = newValue }
+  }
+}
```

```diff
diff --git a/App/Control/ControlText.swift b/App/Control/ControlText.swift
index bc137a8..e8dba95 100644
--- a/App/Control/ControlText.swift
+++ b/App/Control/ControlText.swift
@@ -26,6 +26,10 @@ enum ControlText {
     case .replaced(let name): String(format: String(localized: "control.notice.replaced"), name)
     case .cleared: String(localized: "control.notice.cleared")
     case .missingAtLaunch(let name): String(format: String(localized: "control.notice.missing"), name)
+    case .maskCleared: String(localized: "control.notice.maskCleared")
+    case .maskMissingAtLaunch: String(localized: "control.notice.maskMissing")
+    case .paintCleared: String(localized: "control.notice.paintCleared")
+    case .paintMissingAtLaunch: String(localized: "control.notice.paintMissing")
     }
   }
 
```

```diff
diff --git a/App/Control/ImageCard.swift b/App/Control/ImageCard.swift
index b9291c1..1232d98 100644
--- a/App/Control/ImageCard.swift
+++ b/App/Control/ImageCard.swift
@@ -122,6 +122,8 @@ struct ImageCard: View {
       HStack(spacing: DS.controlGap) {
         if edit {
           Text("control.strength.edit").font(.caption).foregroundStyle(.secondary)
+        } else if control.inputs.mask != nil, control.inputs.strength == nil {
+          Text("control.strength.mask").font(.caption).foregroundStyle(.secondary)
         }
         if control.inputs.strength != nil {
           Button("control.strength.auto") { control.setStrength(nil) }
```

```diff
diff --git a/App/Generation/GenerationController.swift b/App/Generation/GenerationController.swift
index aa6ab27..21d02d5 100644
--- a/App/Generation/GenerationController.swift
+++ b/App/Generation/GenerationController.swift
@@ -198,7 +198,8 @@ final class GenerationController {
       prompt: prompt, negativePrompt: negativePrompt, model: model, family: family(in: connection),
       parameters: parameters, catalog: connection.monitor.catalog,
       imageStrength: inputs.image == nil ? nil : control.inputs.effectiveStrength(editModel: isEditModel(in: connection)),
-      moodboardCount: inputs.hints.count)
+      moodboardCount: inputs.hints.count,
+      maskSettings: inputs.mask == nil ? nil : control.inputs.maskSettings)
     if parameters.randomSeed, let first = batches.first { parameters.seed = first.parameters.seed }
     session.start(batches, inputs: inputs, backend: backend, monitor: connection.monitor)
   }
@@ -211,7 +212,9 @@ final class GenerationController {
       canvasWidth: parameters.width, canvasHeight: parameters.height,
       includeMoodboard: FamilyTraits.of(family(in: connection)).usesMoodboard)
     do {
-      return try await Task.detached { try pending.render() }.value
+      var inputs = try await Task.detached { try pending.render() }.value
+      inputs.enableInpainting = selectedModel(in: connection)?.capabilities.needsInpaintControl ?? false
+      return inputs
     } catch {
       let text = (error as? ControlError).map(ControlText.error) ?? error.localizedDescription
       session.fail(with: .generationFailed(text))
@@ -252,6 +255,7 @@ final class GenerationController {
     parameters = result.job.parameters
     if lockRatio { lockedRatio = currentRatio }
     if let strength = result.job.imageStrength { control.setStrength(strength) }
+    if let settings = result.job.maskSettings { control.setMaskSettings(settings) }
     connection.selection.select(result.job.model)
   }
 
```

- [ ] **Step 3: Compilare e provare**

Run: `cd "/Users/existenz/Software developement/DT Hub" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath /tmp/m7c-dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; cd Packages && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|Missing|Not in" | grep -v "started\|reportsFailures"`
Expected: `** BUILD SUCCEEDED **` (in una cartella a parte, per non toccare un'app aperta); test HubKit 63, HubCore 308, DTBridge 61, Catalog 6, LLMBridge 6 = **444** passati.

- [ ] **Step 4: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add App && git commit -m "feat: card Canvas con due modalità — Disegno con Maschera +/−, Pennello a colori, strumenti a icone, strati, chip nella striscia, RUN con inpaint

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Verifica dal vivo

**Files:**
- Modify: `Packages/Tests/DTBridgeTests/LiveServerTests.swift` (una prova con server vero, inattiva senza variabile d'ambiente)

- [ ] **Step 1: Aggiungere la prova dal vivo**

```diff
diff --git a/Packages/Tests/DTBridgeTests/LiveServerTests.swift b/Packages/Tests/DTBridgeTests/LiveServerTests.swift
index 1d716dc..dd20e29 100644
--- a/Packages/Tests/DTBridgeTests/LiveServerTests.swift
+++ b/Packages/Tests/DTBridgeTests/LiveServerTests.swift
@@ -140,6 +140,73 @@ struct LiveServerTests {
     print("LIVE z-image moodboard: right minus left plain \(rightMinusLeft(plain)) guided \(rightMinusLeft(guided))")
   }
 
+  /// Inpainting, measured on SD 1.5 (Juggernaut Reborn) and FLUX.2 klein: a solid blue picture whose
+  /// right half is masked is asked to become red poppies. The left half stays as it was and the
+  /// right half is regenerated, at strength 100 % and without the inpaint control (which changed
+  /// nothing on these models: measured with it on and off). At strength 70 % the masked half
+  /// stayed blue, so the tab's automatic strength with a mask is 100 %.
+  @Test(.enabled(if: address != nil))
+  func aMaskKeepsTheOutsideAndRegeneratesTheInside() async throws {
+    let backend = try await liveBackend()
+    let models = try await backend.fetchCatalog().models
+    let cases: [(label: String, file: String, steps: Int, guidance: Double)] = [
+      ("sd15", models.first { $0.file.hasPrefix("juggernaut_reborn") }?.file ?? "", 12, 4),
+      ("klein", models.first { $0.family == "flux2_9b" }?.file ?? "", 4, 1),
+    ]
+    let source = try #require(solid(red: 0, green: 0, blue: 255, size: 512))
+    let sourceLeft = blueShare(try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 256, height: 512))))
+    let mask = halfMask(size: 512)
+    var ran = 0
+    for item in cases where !item.file.isEmpty {
+      var job = GenerationJob(
+        prompt: "a field of bright red poppies", model: item.file,
+        parameters: GenerationParameters(
+          width: 512, height: 512, steps: item.steps, guidanceScale: item.guidance, sampler: .ddimTrailing, seed: 7,
+          randomSeed: false))
+      job.imageStrength = 1.0
+      job.maskSettings = MaskSettings()
+      let out = try await run(backend, job, GenerationInputs(image: source, mask: mask))
+      let left = try #require(out.cropping(to: CGRect(x: 0, y: 0, width: 256, height: 512)))
+      let right = try #require(out.cropping(to: CGRect(x: 256, y: 0, width: 256, height: 512)))
+      print("LIVE inpaint \(item.label): left blue \(blueShare(left)) (source \(sourceLeft)) right red \(redShare(right))")
+      #expect(abs(blueShare(left) - sourceLeft) < 0.03)
+      #expect(redShare(right) > 0.3)
+      ran += 1
+    }
+    await backend.shutdown()
+    #expect(ran > 0, "needs Juggernaut Reborn or a FLUX.2 klein model on the server")
+  }
+
+  /// 512×512, the right half transparent (to regenerate), the left half opaque (to keep).
+  private func halfMask(size: Int) -> CGImage {
+    let context = CGContext(
+      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
+      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
+    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
+    context.fill(CGRect(x: 0, y: 0, width: size / 2, height: size))
+    return context.makeImage()!
+  }
+
+  private func averageColor(_ image: CGImage) -> (r: Double, g: Double, b: Double) {
+    var bytes = [UInt8](repeating: 0, count: 4)
+    let context = CGContext(
+      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
+      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
+    context.interpolationQuality = .medium
+    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
+    return (Double(bytes[0]) / 255, Double(bytes[1]) / 255, Double(bytes[2]) / 255)
+  }
+
+  private func redShare(_ image: CGImage) -> Double {
+    let c = averageColor(image)
+    return c.r / max(c.r + c.g + c.b, 0.001)
+  }
+
+  private func blueShare(_ image: CGImage) -> Double {
+    let c = averageColor(image)
+    return c.b / max(c.r + c.g + c.b, 0.001)
+  }
+
   private func liveBackend() async throws -> DrawThingsBackend {
     let parts = try #require(Self.address?.split(separator: ":"))
     return DrawThingsBackend(host: String(parts[0]), port: Int(parts[1]) ?? 7859, useTLS: true, sharedSecret: nil)
```

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: DTBridge `62 tests … passed` (la prova è inattiva), totale **445**.

- [ ] **Step 2: Provarla con un server vero**

Serve il server di Draw Things con i modelli di `/Volumes/LLM-VLM/Models` (Juggernaut Reborn, FLUX.2 klein). Si avvia a mano, solo per la prova, **e solo se l'app dell'utente non sta usando la porta**: qui la 7861.

```bash
(nohup "$HOME/Applications/DrawThings-CLI/gRPCServerCLI-macOS" /Volumes/LLM-VLM/Models --address 127.0.0.1 --port 7861 --model-browser > /tmp/m7c-server.log 2>&1 &); sleep 6
cd "/Users/existenz/Software developement/DT Hub/Packages" && DTHUB_LIVE_DT=localhost:7861 swift test --filter aMaskKeepsTheOutside 2>&1 | grep -E "LIVE|passed|failed|error:" | grep -v started
pkill -TERM -f gRPCServerCLI
```

Expected: due righe `LIVE inpaint …: left blue X (source X) right red …` con X uguali (la parte fuori dalla maschera non cambia) e il rosso a destra sopra 0,3; il test passa. Può volerci qualche minuto (carica i modelli dal disco esterno).

- [ ] **Step 3: Provare l'app**

Chiedere all'utente di chiudere il suo DT Hub se è aperto. Per non toccare i suoi dati: salvare `~/Library/Application Support/DT Hub` (`cp -R`) e le preferenze (`defaults export com.exiztenz.DTHub /tmp/m7c-defaults.plist`); preparare una immagine di prova (768×512, una casa su un prato) in `Control/` e un `control.json` con quell'immagine; in `session.json` canvas 768×512, 12 passi, modello Juggernaut Reborn; cartella di output temporanea (`defaults write com.exiztenz.DTHub output.folder /tmp/dthub-m7c-out`). Aprire l'app compilata in una cartella a parte.

Checklist:
1. Il tab Control ha **una sola** card Canvas, con il selettore Canvas/Disegno a tutta larghezza e l'immagine centrata e grande (cresce con la finestra); in Canvas il trascinamento sposta il ritaglio quando i rapporti sono diversi.
2. In Disegno la toolbar mostra tre strumenti a icone (gomma con +, gomma con −, pennello), con i nomi nei suggerimenti; il cerchio dello strumento segue il puntatore.
3. Maschera +: un tratto lo colora in arancio e fa comparire il chip "Maschera N%"; la Forza mostra 100 con la frase «Con la maschera la forza è al 100%…».
4. Run: il PNG salvato rigenera solo la zona dipinta (il resto è identico) e nei metadati ha `"maskSettings":{"blur":1.5,"outset":0,"preserveOriginal":true}` e `"imageStrength":1`.
5. Inverti colora tutto il resto; Annulla lo toglie; Maschera − cancella dove si passa; Svuota toglie la maschera (avviso e Annulla).
6. Pennello: un tratto a colori sull'immagine (colore scelto con il selettore) con il chip "Disegno"; Svuota disegno e Annulla; il tratto è curvo anche con pochi punti; con Run il disegno è sopra l'immagine inviata.
7. Chiudere e riaprire l'app: maschera e disegno sono ancora lì.
8. Tratti lunghi con una finestra grande: la fluidità è accettabile (si annota a occhio).

- [ ] **Step 4: Pulizia** (sempre, anche se qualcosa non va)

Fermare app e server, ripristinare la cartella `DT Hub` e le preferenze salvate, togliere `output.folder` e la cartella `/tmp/dthub-m7c-out`; rimettere `workspace.selectedTab` e `drawThings.selectedModel` dell'utente.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "test: prova dal vivo dell'inpaint (SD 1.5 e FLUX.2 klein)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Fine della M7c

Esito atteso sul branch `m7c-maschera`:
- **445 test verdi** (1 prova dal vivo in più inattiva senza `DTHUB_LIVE_DT`, provata con il server);
- build Xcode pulita;
- l'inpaint funziona dall'app: si dipinge la maschera sul canvas, il RUN rigenera solo quella zona, il Pennello disegna a colori sull'immagine, tutto si annulla, tutto torna all'avvio.

Poi: revisione indipendente, correzioni, prove dell'utente (**lasciare l'app aperta**), merge. Dopo M7c: Tiled Diffusion 8192, outpaint, M8 Plug-in.
