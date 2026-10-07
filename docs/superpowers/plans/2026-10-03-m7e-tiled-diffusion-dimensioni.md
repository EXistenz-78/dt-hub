# M7e Dimensioni fino a 8192 con il Tiled Diffusion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Con il Tiled Diffusion acceso i campi Larghezza e Altezza arrivano a 8192; spento, a 2048. Spegnerlo con dimensioni sopra 2048 le riporta a 2048 mantenendo il rapporto, in silenzio. **Si genera oltre 2048.**

**Architecture:**
- **HubKit**: `GenerationParameters` ottiene `tiledSizeRange`, `sizeLimit` (8192 con il Tiled Diffusion, 2048 senza), `snap(_:limit:)`, `fitSizeToLimit()` e `setTiledDiffusion(_:)`; `apply(ratio)`, `setWidth`/`setHeight` e `clamped()` usano il limite dei parametri stessi.
- **L'app**: la card Dimensioni legge il limite dai parametri; l'interruttore del Tiled Diffusion delle Avanzate scrive con `GenerationController.setTiledDiffusion` (che aggiorna anche il rapporto bloccato); "Adatta le dimensioni" del tab Control usa `sizeLimit`.
- **DTBridge**: invariato; una prova dal vivo conferma che il server accetta 3072×2048 con il Tiled acceso.

**Tech Stack:** Swift 6, SwiftUI, macOS 26, Xcode 27, Swift Testing, DrawThings-Swift 2.2.x (solo in DTBridge).

**Spec:** `docs/superpowers/specs/2026-10-03-tiled-diffusion-sizes-design.md`

## Global Constraints

- **Repository e dipendenze:**
  - radice `<repo>` (percorsi tra virgolette);
  - branch `m7e-tiled` da `main`;
  - macOS 26, Swift 6, Xcode 27;
  - solo DTBridge importa DrawThings-Swift.
- **I limiti:** `sizeRange = 64...2048` (normale), `tiledSizeRange = 64...8192` (Tiled Diffusion acceso); lati sempre multipli di 64. Le dimensioni dell'Hires fix e `JobComposer` restano a 2048 (`snap` senza limite).
- **Spegnere il Tiled Diffusion** con il lato lungo sopra 2048: tutte e due le dimensioni in scala perché il lato lungo valga 2048, arrotondando a 64, minimo 64; **senza avvisi**. Accenderlo non tocca le dimensioni.
- **`clamped()`** limita un lato alla volta al limite dei parametri stessi (come prima, ma con il limite che segue l'interruttore): sessione, preset, "Riprendi parametri" e editor JSON passano da lì.
- **Fuori da M7e:** altri upscaler; la dimensione di lavoro di maschera e disegno (1024); Hires fix oltre 2048; avvisi o blocchi per la memoria; la fluidità del pennello a 8192.
- **Nessuna stringa nuova** (il catalogo non cambia).
- **La logica sta in HubKit (testata); le viste si verificano con la compilazione.**
- **Blocchi `diff`:** sono le modifiche ai file che esistono già; si salvano in un file e si applicano dalla radice con `git apply --whitespace=nowarn <file>`. I blocchi di codice dei file nuovi si salvano così come sono.
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Se l'app dell'utente è aperta** non lanciare altre istanze (stesso identificatore): compilare con `-derivedDataPath /tmp/m7e-dd`.

## Review Focus

- **Rapporto bloccato:** spegnendo il Tiled Diffusion con il blocco del rapporto attivo, `lockedRatio` deve seguire le nuove dimensioni (è codice del controller, senza test: il revisore lo controlli a occhio in `GenerationController.setTiledDiffusion`).
- **Sessioni e preset grandi:** un file con dimensioni oltre 2048 e il Tiled spento si legge a 2048 per lato; con il Tiled acceso resta (test `aSavedSessionReadsWithTheLimitOfItsOwnSwitch`, Task 1).
- **Rapporti estremi:** 8192×64 non fa scendere il lato corto sotto 64 (test `fittingKeepsTheRatioAndTheLongSideIsTheLimit`, Task 1); ritratto e orizzontale riducono allo stesso modo.
- **Preset dei rapporti e blocco del rapporto a 8192:** raggiungono il limite senza superarlo (test `aLockedRatioAndTheRatioPresetsReachTheLimit`, Task 1).
- **"Adatta le dimensioni" con il Tiled acceso:** usa 8192 (test `theLimitOfTheMomentIs8192WithTheTiledDiffusion`, Task 2).
- **Hires fix con un canvas oltre 2048:** le sue dimensioni predefinite si fermano a 2048 (fuori perimetro); il revisore dica se lo ritiene da correggere.

---

### Task 1: Il limite che segue il Tiled Diffusion (HubKit)

**Files:**
- Modify: `Packages/Sources/HubKit/Generation/GenerationParameters.swift`
- Test: `Packages/Tests/HubKitTests/TiledSizesTests.swift` (nuovo)

**Interfaces:**
- Produces (HubKit, `public`, su `GenerationParameters`):
  - `static let tiledSizeRange = 64...8192`; `var sizeLimit: Int` (8192 se `advanced.tiledDiffusion`, altrimenti 2048);
  - `static func snap(_ size: Double, limit: Int = sizeRange.upperBound) -> Int` (il multiplo di 64 più vicino, tra 64 e `limit`);
  - `mutating func fitSizeToLimit()` (se il lato lungo supera `sizeLimit`, scala tutte e due le dimensioni perché il lato lungo valga il limite, con `snap` e minimo 64; altrimenti niente);
  - `mutating func setTiledDiffusion(_ on: Bool)` (imposta `advanced.tiledDiffusion`, poi `fitSizeToLimit()`);
  - `apply(_ ratio:)`, `setWidth(_:keepingRatio:)`, `setHeight(_:keepingRatio:)` e `clamped()` usano `sizeLimit` del parametro stesso.
- Consumes: `GenerationParameters`, `AdvancedParameters.tiledDiffusion`, `AspectRatio` (esistenti).

- [ ] **Step 1: Creare il ramo e scrivere i test**

```bash
cd "<repo>" && git switch main && git switch -c m7e-tiled
```

```swift
import Foundation
import Testing

@testable import HubKit

struct TiledSizesTests {
  func parameters(_ width: Int, _ height: Int, tiled: Bool) -> GenerationParameters {
    var parameters = GenerationParameters(width: width, height: height)
    parameters.advanced.tiledDiffusion = tiled
    return parameters
  }

  @Test func theLimitFollowsTheTiledDiffusion() {
    #expect(parameters(1024, 1024, tiled: false).sizeLimit == 2048)
    #expect(parameters(1024, 1024, tiled: true).sizeLimit == 8192)
    #expect(GenerationParameters.tiledSizeRange == 64...8192)
  }

  @Test func snapStopsAtTheLimitItIsGiven() {
    #expect(GenerationParameters.snap(5000) == 2048)
    #expect(GenerationParameters.snap(5000, limit: 8192) == 4992)
    #expect(GenerationParameters.snap(9000, limit: 8192) == 8192)
    #expect(GenerationParameters.snap(10, limit: 8192) == 64)
  }

  @Test func clampedKeepsWhatTheLimitAllows() {
    let tiled = parameters(4096, 3000, tiled: true).clamped()
    #expect(tiled.width == 4096 && tiled.height == 3008)
    let plain = parameters(4096, 3000, tiled: false).clamped()
    #expect(plain.width == 2048 && plain.height == 2048)
    let huge = parameters(9999, 20_000, tiled: true).clamped()
    #expect(huge.width == 8192 && huge.height == 8192)
  }

  @Test func aLockedRatioAndTheRatioPresetsReachTheLimit() {
    var tiled = parameters(4096, 2048, tiled: true)
    tiled.setWidth(6000, keepingRatio: 2)
    #expect(tiled.height == 3008)
    var plain = parameters(1024, 512, tiled: false)
    plain.setWidth(4000, keepingRatio: 2)
    #expect(plain.height == 1984)  // 4000 / 2 = 2000, snapped to 1984
    var preset = parameters(8192, 8192, tiled: true)
    preset.apply(AspectRatio(width: 16, height: 9))
    #expect(preset.width == 8192 && preset.height == 4608)
  }

  @Test func fittingKeepsTheRatioAndTheLongSideIsTheLimit() {
    func fitted(_ width: Int, _ height: Int) -> (Int, Int) {
      var p = parameters(width, height, tiled: false)
      p.fitSizeToLimit()
      return (p.width, p.height)
    }
    #expect(fitted(4096, 2048) == (2048, 1024))
    #expect(fitted(8192, 4096) == (2048, 1024))
    #expect(fitted(4000, 3000) == (2048, 1536))
    #expect(fitted(3000, 4000) == (1536, 2048))
    #expect(fitted(8192, 64) == (2048, 64))  // the short side never goes under 64
    #expect(fitted(2048, 1024) == (2048, 1024))  // already within
    var tiled = parameters(8192, 4096, tiled: true)
    tiled.fitSizeToLimit()
    #expect(tiled.width == 8192 && tiled.height == 4096)
  }

  @Test func turningTheTiledDiffusionOffBringsTheSizeBack() {
    var parameters = parameters(4096, 2048, tiled: true)
    parameters.setTiledDiffusion(false)
    #expect(parameters.advanced.tiledDiffusion == false)
    #expect(parameters.width == 2048 && parameters.height == 1024)
  }

  @Test func turningItOnLeavesTheSizeAlone() {
    var parameters = parameters(1024, 512, tiled: false)
    parameters.setTiledDiffusion(true)
    #expect(parameters.advanced.tiledDiffusion)
    #expect(parameters.width == 1024 && parameters.height == 512)
  }

  @Test func aSavedSessionReadsWithTheLimitOfItsOwnSwitch() throws {
    let big = Data(#"{"width": 4096, "height": 2048, "advanced": {"tiledDiffusion": true}}"#.utf8)
    let kept = try JSONDecoder().decode(GenerationParameters.self, from: big).clamped()
    #expect(kept.width == 4096 && kept.height == 2048)
    let plain = Data(#"{"width": 4096, "height": 2048}"#.utf8)
    let limited = try JSONDecoder().decode(GenerationParameters.self, from: plain).clamped()
    #expect(limited.width == 2048 && limited.height == 2048)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter HubKitTests 2>&1 | grep -E "error:" | head -2`
Expected: `value of type 'GenerationParameters' has no member 'sizeLimit'`.

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/HubKit/Generation/GenerationParameters.swift b/Packages/Sources/HubKit/Generation/GenerationParameters.swift
index be33528..004a207 100644
--- a/Packages/Sources/HubKit/Generation/GenerationParameters.swift
+++ b/Packages/Sources/HubKit/Generation/GenerationParameters.swift
@@ -102,12 +102,37 @@ public struct GenerationParameters: Equatable, Codable, Sendable {
 
   /// Allowed ranges, used by the cards and by `clamped()`.
   public static let sizeRange = 64...2048
+  /// The sizes allowed with the Tiled Diffusion on (spec: dimensioni fino a 8192).
+  public static let tiledSizeRange = 64...8192
   public static let stepsRange = 1...150
   public static let guidanceRange = 0.0...50.0
   public static let shiftRange = 0.0...20.0
   public static let batchSizeRange = 1...4
   public static let batchCountRange = 1...100
 
+  /// The largest side allowed now: 8192 with the Tiled Diffusion on, 2048 without.
+  public var sizeLimit: Int {
+    advanced.tiledDiffusion ? Self.tiledSizeRange.upperBound : Self.sizeRange.upperBound
+  }
+
+  /// Turns the Tiled Diffusion on or off. Turning it off with a side above 2048 brings the size back
+  /// within it (`fitSizeToLimit`).
+  public mutating func setTiledDiffusion(_ on: Bool) {
+    advanced.tiledDiffusion = on
+    fitSizeToLimit()
+  }
+
+  /// Scales both sides, keeping the ratio, so that the long side is the limit; sides in multiples of
+  /// 64 and at least 64. Nothing when the size is within the limit already.
+  public mutating func fitSizeToLimit() {
+    let limit = sizeLimit
+    let long = max(width, height)
+    guard long > limit else { return }
+    let scale = Double(limit) / Double(long)
+    width = Self.snap(Double(width) * scale, limit: limit)
+    height = Self.snap(Double(height) * scale, limit: limit)
+  }
+
   /// Portrait ↔ landscape. One mutation: `swap(&p.width, &p.height)` on an observed property
   /// is two overlapping accesses to the same struct and crashes at run time.
   public mutating func swapDimensions() {
@@ -117,32 +142,32 @@ public struct GenerationParameters: Equatable, Codable, Sendable {
   /// Applies an aspect ratio keeping the long side and the orientation (portrait stays portrait).
   public mutating func apply(_ ratio: AspectRatio) {
     let long = max(width, height)
-    let short = Self.snap(Double(long) * Double(ratio.height) / Double(ratio.width))
+    let short = Self.snap(Double(long) * Double(ratio.height) / Double(ratio.width), limit: sizeLimit)
     if height > width {
-      (width, height) = (short, Self.snap(Double(long)))
+      (width, height) = (short, Self.snap(Double(long), limit: sizeLimit))
     } else {
-      (width, height) = (Self.snap(Double(long)), short)
+      (width, height) = (Self.snap(Double(long), limit: sizeLimit), short)
     }
   }
 
   /// Sets the width; with a ratio (width ÷ height) the height follows to keep it.
   public mutating func setWidth(_ newWidth: Int, keepingRatio ratio: Double?) {
     width = newWidth
-    if let ratio, ratio > 0 { height = Self.snap(Double(newWidth) / ratio) }
+    if let ratio, ratio > 0 { height = Self.snap(Double(newWidth) / ratio, limit: sizeLimit) }
   }
 
   /// Sets the height; with a ratio (width ÷ height) the width follows to keep it.
   public mutating func setHeight(_ newHeight: Int, keepingRatio ratio: Double?) {
     height = newHeight
-    if let ratio, ratio > 0 { width = Self.snap(Double(newHeight) * ratio) }
+    if let ratio, ratio > 0 { width = Self.snap(Double(newHeight) * ratio, limit: sizeLimit) }
   }
 
   /// The same parameters forced into the allowed ranges; sizes rounded to the nearest multiple
   /// of 64, as the size fields do when editing ends.
   public func clamped() -> GenerationParameters {
     var copy = self
-    copy.width = Self.snap(Double(width))
-    copy.height = Self.snap(Double(height))
+    copy.width = Self.snap(Double(width), limit: sizeLimit)
+    copy.height = Self.snap(Double(height), limit: sizeLimit)
     copy.steps = min(max(steps, Self.stepsRange.lowerBound), Self.stepsRange.upperBound)
     copy.guidanceScale = min(max(guidanceScale, Self.guidanceRange.lowerBound), Self.guidanceRange.upperBound)
     copy.cfgZeroInitSteps = min(max(cfgZeroInitSteps, 0), copy.steps)
@@ -157,9 +182,9 @@ public struct GenerationParameters: Equatable, Codable, Sendable {
     return copy
   }
 
-  /// Nearest multiple of 64 inside `sizeRange`.
-  public static func snap(_ size: Double) -> Int {
+  /// Nearest multiple of 64 from 64 to `limit` (2048 unless given).
+  public static func snap(_ size: Double, limit: Int = sizeRange.upperBound) -> Int {
     let rounded = Int((size / 64).rounded()) * 64
-    return min(max(rounded, sizeRange.lowerBound), sizeRange.upperBound)
+    return min(max(rounded, sizeRange.lowerBound), limit)
   }
 }
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubKit `76 tests … passed` (8 nuovi), HubCore 343, DTBridge 64, Catalog 6, LLMBridge 6 (totale **495**). Se `reportsProgressAndPreviewWhileRunning` (M3) fallisce una volta sotto carico, è la flakiness nota: rilanciare.

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: il limite delle dimensioni segue il Tiled Diffusion (2048 / 8192), spegnerlo riporta la dimensione dentro 2048

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: I campi, l'interruttore e "Adatta le dimensioni" (app)

**Files:**
- Modify: `App/Generation/Cards/DimensionsCard.swift`, `App/Generation/Advanced/AdvancedCardView.swift`, `App/Generation/GenerationController.swift`
- Test: `Packages/Tests/HubCoreTests/FramingTests.swift`

**Interfaces:**
- Consumes: `GenerationParameters.sizeLimit`, `snap(_:limit:)`, `setTiledDiffusion(_:)` (Task 1), `FramingMath.adaptedSize(…limit:)` (già parametrico).
- Produces: `GenerationController.setTiledDiffusion(_ on: Bool)` (chiama `parameters.setTiledDiffusion(on)` e, con il blocco del rapporto, aggiorna `lockedRatio`); i campi della card Dimensioni con intervallo `64…sizeLimit` e `commit` che arrotonda con `snap(_, limit: sizeLimit)`; l'interruttore delle Avanzate che scrive con `controller.setTiledDiffusion`; `adaptDimensionsToImage()` che passa `limit: parameters.sizeLimit`.

- [ ] **Step 1: Scrivere il test**

```diff
diff --git a/Packages/Tests/HubCoreTests/FramingTests.swift b/Packages/Tests/HubCoreTests/FramingTests.swift
index 98f7703..a9c58e5 100644
--- a/Packages/Tests/HubCoreTests/FramingTests.swift
+++ b/Packages/Tests/HubCoreTests/FramingTests.swift
@@ -62,6 +62,17 @@ struct FramingMathTests {
   }
 }
 
+struct AdaptedSizeLimitTests {
+  @Test func theLimitOfTheMomentIs8192WithTheTiledDiffusion() {
+    // 4:1 at the area of 6000×4000: 9798×2449 before the limit.
+    let plain = FramingMath.adaptedSize(imageWidth: 4000, imageHeight: 1000, currentWidth: 6000, currentHeight: 4000)
+    #expect(plain.width == 2048)
+    let tiled = FramingMath.adaptedSize(
+      imageWidth: 4000, imageHeight: 1000, currentWidth: 6000, currentHeight: 4000, limit: 8192)
+    #expect(tiled == Size(width: 8192, height: 2432))
+  }
+}
+
 struct InputComposerTests {
   /// An image whose left half is red and right half is blue.
   func twoTone(width: Int = 200, height: Int = 100) -> CGImage {
```

- [ ] **Step 2: Provarlo**

Run: `cd "<repo>/Packages" && swift test --filter AdaptedSizeLimit 2>&1 | grep -E "✘ Test|Test run with|error:" | grep -v started`
Expected: **passa già**: `adaptedSize` aveva il limite come parametro; il test fissa il comportamento che il controller usa da questo task (non c'è un passo rosso per questa parte).

- [ ] **Step 3: Collegare l'app**

```diff
diff --git a/App/Generation/Cards/DimensionsCard.swift b/App/Generation/Cards/DimensionsCard.swift
index ee6918f..29d6501 100644
--- a/App/Generation/Cards/DimensionsCard.swift
+++ b/App/Generation/Cards/DimensionsCard.swift
@@ -17,8 +17,8 @@ struct DimensionsCard: View {
             value: Binding(
               get: { controller.parameters.width },
               set: { controller.parameters.setWidth($0, keepingRatio: controller.lockedRatio) }),
-            range: GenerationParameters.sizeRange, step: 64,
-            commit: { GenerationParameters.snap(Double($0)) })
+            range: GenerationParameters.sizeRange.lowerBound...controller.parameters.sizeLimit, step: 64,
+            commit: { GenerationParameters.snap(Double($0), limit: controller.parameters.sizeLimit) })
         }
         CardRow(label: String(localized: "card.dimensions.height")) {
           IntField(
@@ -26,8 +26,8 @@ struct DimensionsCard: View {
             value: Binding(
               get: { controller.parameters.height },
               set: { controller.parameters.setHeight($0, keepingRatio: controller.lockedRatio) }),
-            range: GenerationParameters.sizeRange, step: 64,
-            commit: { GenerationParameters.snap(Double($0)) })
+            range: GenerationParameters.sizeRange.lowerBound...controller.parameters.sizeLimit, step: 64,
+            commit: { GenerationParameters.snap(Double($0), limit: controller.parameters.sizeLimit) })
         }
         HStack(spacing: DS.controlGap) {
           Menu {
```

```diff
diff --git a/App/Generation/Advanced/AdvancedCardView.swift b/App/Generation/Advanced/AdvancedCardView.swift
index c6d209c..9043ebb 100644
--- a/App/Generation/Advanced/AdvancedCardView.swift
+++ b/App/Generation/Advanced/AdvancedCardView.swift
@@ -239,7 +239,10 @@ struct AdvancedCardView: View {
     if advanced.wrappedValue.tiledDecoding {
       TileRows(width: advanced.decodingTileWidth, height: advanced.decodingTileHeight, overlap: advanced.decodingTileOverlap)
     }
-    Toggle(isOn: advanced.tiledDiffusion) { Text("advanced.field.tiledDiffusion") }
+    Toggle(
+      isOn: Binding(
+        get: { controller.parameters.advanced.tiledDiffusion }, set: { controller.setTiledDiffusion($0) })
+    ) { Text("advanced.field.tiledDiffusion") }
       .toggleStyle(DSCheckboxToggleStyle())
     if advanced.wrappedValue.tiledDiffusion {
       TileRows(width: advanced.diffusionTileWidth, height: advanced.diffusionTileHeight, overlap: advanced.diffusionTileOverlap)
```

```diff
diff --git a/App/Generation/GenerationController.swift b/App/Generation/GenerationController.swift
index 38f3f1e..25561a2 100644
--- a/App/Generation/GenerationController.swift
+++ b/App/Generation/GenerationController.swift
@@ -242,11 +242,18 @@ final class GenerationController {
     let previous = Size(width: parameters.width, height: parameters.height)
     let adapted = FramingMath.adaptedSize(
       imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, currentWidth: previous.width,
-      currentHeight: previous.height)
+      currentHeight: previous.height, limit: parameters.sizeLimit)
     restoreDimensions(adapted)
     return previous
   }
 
+  /// The Tiled Diffusion switch of the Advanced card: turning it off brings the dimensions back within
+  /// 2048, keeping the ratio, and a ratio lock follows the new size.
+  func setTiledDiffusion(_ on: Bool) {
+    parameters.setTiledDiffusion(on)
+    if lockRatio { lockedRatio = currentRatio }
+  }
+
   func restoreDimensions(_ size: Size) {
     parameters.width = size.width
     parameters.height = size.height
```

- [ ] **Step 4: Compilare e provare**

Run: `cd "<repo>" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath /tmp/m7e-dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; cd Packages && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: `** BUILD SUCCEEDED **`; test HubKit 76, HubCore 344, DTBridge 64, Catalog 6, LLMBridge 6 = **496** passati.

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add App Packages && git commit -m "feat: campi delle dimensioni fino a 8192 con il Tiled Diffusion, interruttore che riporta la dimensione, Adatta le dimensioni con il limite del momento

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Verifica dal vivo e documenti

**Files:**
- Modify: `Packages/Tests/DTBridgeTests/LiveServerTests.swift` (una prova con server vero, inattiva senza variabile d'ambiente), `docs/superpowers/specs/2026-10-03-tiled-diffusion-sizes-design.md`

- [ ] **Step 1: Aggiungere la prova dal vivo**

```diff
diff --git a/Packages/Tests/DTBridgeTests/LiveServerTests.swift b/Packages/Tests/DTBridgeTests/LiveServerTests.swift
index 4a139c4..ff7917d 100644
--- a/Packages/Tests/DTBridgeTests/LiveServerTests.swift
+++ b/Packages/Tests/DTBridgeTests/LiveServerTests.swift
@@ -270,6 +270,25 @@ struct LiveServerTests {
     #expect(difference > 0.005, "the top margin looks like stretched stripes")
   }
 
+  /// A size above 2048 with the Tiled Diffusion on (and the Tiled Decoding), measured on SD 1.5
+  /// (Juggernaut Reborn): 3072×2048 in 8 steps comes back at the size asked for.
+  @Test(.enabled(if: address != nil))
+  func aSizeAbove2048RunsWithTheTiledDiffusion() async throws {
+    let backend = try await liveBackend()
+    let models = try await backend.fetchCatalog().models
+    let file = try #require(models.first { $0.file.hasPrefix("juggernaut_reborn") }?.file, "needs Juggernaut Reborn")
+    var parameters = GenerationParameters(
+      width: 3072, height: 2048, steps: 8, guidanceScale: 4, sampler: .ddimTrailing, seed: 3, randomSeed: false)
+    parameters.setTiledDiffusion(true)
+    parameters.advanced.tiledDecoding = true
+    #expect(parameters.width == 3072 && parameters.height == 2048)
+    let job = GenerationJob(prompt: "a foggy mountain valley, photograph", model: file, parameters: parameters)
+    let out = try await run(backend, job, .none)
+    await backend.shutdown()
+    print("LIVE tiled: \(out.width)×\(out.height)")
+    #expect(out.width == 3072 && out.height == 2048)
+  }
+
   /// 512×512, the right half transparent (to regenerate), the left half opaque (to keep).
   private func halfMask(size: Int) -> CGImage {
     let context = CGContext(
```

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: DTBridge `65 tests … passed` (la prova è inattiva), totale **497**.

- [ ] **Step 2: Provarla con un server vero**

Serve il server di Draw Things con i modelli di `/Volumes/LLM-VLM/Models` (Juggernaut Reborn). Si avvia a mano, solo per la prova, **e solo se non c'è già un `gRPCServerCLI` che l'utente usa** (`pgrep -fl gRPCServerCLI`): qui la porta 7881.

```bash
(nohup "$HOME/Applications/DrawThings-CLI/gRPCServerCLI-macOS" /Volumes/LLM-VLM/Models --address 127.0.0.1 --port 7881 --model-browser > /tmp/m7e-server.log 2>&1 &); sleep 8
cd "<repo>/Packages" && DTHUB_LIVE_DT=127.0.0.1:7881 swift test --filter aSizeAbove2048 2>&1 | grep -E "LIVE|passed|failed|error:" | grep -v started
pkill -TERM -f "gRPCServerCLI-macOS /Volumes/LLM-VLM/Models --address 127.0.0.1 --port 7881"
```

Expected: `LIVE tiled: 3072×2048` e il test passa (circa due minuti).

- [ ] **Step 3: Aggiornare la spec**

```bash
cd "<repo>" && python3 - <<'PY'
p = 'docs/superpowers/specs/2026-10-03-tiled-diffusion-sizes-design.md'
s = open(p).read()
s = s.replace("Stato: bozza da approvare", "Stato: realizzata (M7e)")
old = "Si verifica dal vivo con un server vero che una generazione oltre 2048 con il Tiled Diffusion acceso parta e finisca (SD 1.5, passi pochi), e che i campi dell'invio siano quelli attesi."
new = "Verificato dal vivo il 3 ottobre 2026: SD 1.5 (Juggernaut Reborn), 3072×2048, 8 passi, Tiled Diffusion e Tiled Decoding accesi: il server accetta e restituisce un'immagine della dimensione chiesta."
assert old in s
s = s.replace(old, new)
open(p, 'w').write(s)
PY
git diff --stat docs
```

Expected: una riga di statistica sulla sola spec delle dimensioni (2 righe cambiate).

- [ ] **Step 4: Commit**

```bash
cd "<repo>" && git add Packages docs && git commit -m "test: prova dal vivo delle dimensioni oltre 2048 con il Tiled Diffusion (SD 1.5, 3072×2048), spec realizzata

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Fine della M7e

Esito atteso sul branch `m7e-tiled`:
- **497 test verdi** (1 prova dal vivo in più, inattiva senza `DTHUB_LIVE_DT`, provata con il server);
- build Xcode pulita;
- con il Tiled Diffusion acceso le dimensioni arrivano a 8192 e il server genera oltre 2048; spegnerlo riporta le dimensioni dentro 2048 mantenendo il rapporto.

Poi: revisione indipendente, correzioni, prove dell'utente (**lasciare l'app aperta**), merge. Dopo M7e: M8 Plug-in, Galleria.
