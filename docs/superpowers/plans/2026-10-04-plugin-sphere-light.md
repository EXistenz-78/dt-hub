# Plug-in Sphere Light Reference — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Il primo plug-in vero di DT Hub: **Sphere Light Reference (SLR)**, un tab con le luci e la sfera dell'app standalone `LightDirectionApp`, che manda la sfera al Moodboard e una pipeline di due preset («SLR · Overcast», «SLR · Match the sun») al pulsante Run.

**Architecture:**
- Un pacchetto Swift **in questo repository**, `Plugins/SphereLight/`, con la struttura di `PluginKit/Examples/Sample` (libreria dinamica, kit con `moduleAliases` `SphereLightKit`, bundle fatto da `PluginKit/Scripts/make-bundle.sh`).
- Logica pura e provata: `SphereRenderer` e `LightParams` (copiati dall'app standalone), `SLRMessages` (JSON dei preset e della pipeline), `L` (stringhe it/en), `SLRStore` (memoria), `DesktopSaver`, `SphereSender` (il lavoro dei due pulsanti, con la comunicazione con l'app passata come chiusure).
- Colla senza test automatici: `SLRState`, le viste, `SphereLightPlugin` (messaggi `context`/`activate`/`deactivate`).

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, macOS 26, Swift Testing, `DTHubPluginKit`.

**Spec:** `docs/superpowers/specs/2026-10-04-plugin-sphere-light-design.md`.

## Global Constraints

- **Repository:** radice `<repo>` (percorsi tra virgolette); branch `sphere-light` da `main`; il pacchetto sta in `Plugins/SphereLight/` e si prova da lì con `swift test`. Il plug-in non importa HubKit né altro di DT Hub: parla con l'app solo con il kit (selettori e JSON, contratto 1).
- **Identità:** identificatore `com.exiztenz.dthub.spherelight` (= `manifest.id` = `CFBundleIdentifier`), nome «Sphere Light», versione 1.0, simbolo `lightbulb.max`, classe principale `SphereLightEntry`, `families: ["flux2_9b"]`.
- **Preset:** nomi `SLR · Overcast` e `SLR · Match the sun` (acronimo, punto mediano, nome); valori dello script: passi 4, guidance 1, sampler 16, shift 3, batch 1, CFG-Zero* spento; solo il secondo ha il LoRA `flux_2_sun_direction_lora_v1_lora_f16.ckpt` a peso 0,6; **né dimensioni né modello**. Prompt: «make it an overcast day, remove the shadows» e «match light direction, colors and intensity from the reference image 2».
- **Pipeline:** con la casella Overcast accesa due passaggi (il secondo con `useOutputAsStart: true`), spenta uno solo; la sfera sta nel Moodboard del passaggio «Match the sun». Il pulsante «Solo la sfera nel Moodboard» manda solo `moodboard`.
- **La sfera parte solo con un pulsante**, mai da sola. Sfera finale 1024×1024 con 16 campioni d'ombra; anteprima 220×220 con 10, ricalcolata 60 ms dopo l'ultimo movimento.
- **Salvataggio sulla Scrivania** (casella, spenta all'inizio): `Sphere Light NNN.png`, primo numero libero, mai sovrascritto; se fallisce si dice e l'invio continua.
- **Niente risorse nel bundle:** le stringhe (italiano e inglese) stanno nel codice. Niente `DesignSystem` dell'app standalone: controlli standard di SwiftUI.
- **Memoria:** `UserDefaults` con la chiave `com.exiztenz.dthub.spherelight.state.v1`; **i test non toccano mai le preferenze vere né la vera Scrivania** (suite di prova e cartelle temporanee).
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Blocchi `diff`:** modifiche ai file già esistenti, da salvare in un file e applicare dalla radice con `git apply --whitespace=nowarn <file>`; i blocchi dei file nuovi si salvano così come sono.
- **L'app di prova** condivide le preferenze con quella dell'utente e i processi hanno lo stesso identificatore: **se l'app dell'utente è aperta non pilotare le finestre**; annotare e rimettere `drawThings.selectedModel` e `workspace.selectedTab`.
- **Fuori:** Prompt Master e Qwen Image 2.1; modificare l'app standalone; uno slider del peso del LoRA; il pulsante «Script» e il campo degli appunti; firma, notarizzazione e distribuzione.

## Review Focus

- **Senza la cartella delle immagini non parte niente** (né sfera, né copia sulla Scrivania, né messaggi): test `withoutAPictureFolderNothingIsSent`, Task 4.
- **Un salvataggio sulla Scrivania che fallisce non blocca l'invio** e lo dice: test `aFailedDesktopSaveIsReportedAndTheSendGoesOn`, Task 4.
- **Una memoria rovinata, vuota o con più di tre luci non rompe l'avvio:** test `aSavedSessionWithoutLightsOrWithGarbageCountsAsNone` e `moreThanThreeSavedLightsAreCutToThree`, Task 3.
- **Un preset cancellato dall'utente torna** premendo «Invia a Generazione» (i preset si offrono di nuovo prima della pipeline; l'app non tocca i nomi che ha): test `thePipelineGoesWithTheSphereAndThePresetsAreOfferedFirst`, Task 4. Il solo Moodboard non offre preset: test `onlyTheMoodboardOffersNoPresetsAndSendsOnlyTheSphere`.
- **Plug-in spento, conflitti o app che non risponde:** la riga di stato dice cosa è successo (test `conflictsAnErrorAndNoAnswerAreSaid`, Task 4); i pulsanti sono spenti finché il plug-in non è attivo (prova dal vivo, Task 6).
- **Numeri di file oltre 999** (`Sphere Light 1000.png`) e **file con lo stesso nome della sfera** sono coperti dal formato `%03d` e dal `.withoutOverwriting`; la sfera in `tempFolder` si riscrive sempre (il contratto sostituisce quella di prima).

---

### Task 1: Il pacchetto e il renderer della sfera

**Files:**
- Create: `Plugins/SphereLight/Package.swift`, `Plugins/SphereLight/Sources/SphereLight/Models.swift`, `Plugins/SphereLight/Sources/SphereLight/SphereRenderer.swift`, `Plugins/SphereLight/Tests/SphereLightTests/SphereRendererTests.swift`

**Interfaces:**
- Produces (internal, nel target `SphereLight`): `Vec3`; `LightParams` (`id`, `rotationDeg`, `elevationDeg`, `intensity`, `hardness`, `color`; `static makeDefault(index:)`: 0, 1 e 2 sono le tre luci predefinite); `SphereRenderer.render(width:height:lights:shadowSampleCount:) -> [UInt8]` (RGB8, nessuna luce = tutto nero), `nsImage(fromRGB8:width:height:)`, `pngData(fromRGB8:width:height:)`.
- Il codice di `Models.swift` e `SphereRenderer.swift` è copiato dall'app standalone (`<Sphere Light standalone app>/Sources/LightDirectionApp`) senza cambiare la logica; manca solo `dataURL`.

- [ ] **Step 1: Creare il branch e scrivere il test**

```bash
cd "<repo>" && git switch main && git switch -c sphere-light && mkdir -p Plugins/SphereLight/Sources/SphereLight Plugins/SphereLight/Tests/SphereLightTests Plugins/SphereLight/Scripts
```

**`Plugins/SphereLight/Tests/SphereLightTests/SphereRendererTests.swift`** (file nuovo o riscritto per intero):

```swift
import AppKit
import SwiftUI
import Testing

@testable import SphereLight

@Suite("SphereRenderer")
struct SphereRendererTests {
  private let size = 96

  private func light(rotation: Double, elevation: Double = 20) -> LightParams {
    LightParams(
      rotationDeg: rotation, elevationDeg: elevation, intensity: 1.5, hardness: 0.65, color: .white)
  }

  /// The mean grey of a rectangle of the picture (fractions of its width and height).
  private func brightness(_ pixels: [UInt8], x: ClosedRange<Double>, y: ClosedRange<Double>) -> Double {
    var sum = 0.0
    var count = 0.0
    for py in Int(y.lowerBound * Double(size))..<Int(y.upperBound * Double(size)) {
      for px in Int(x.lowerBound * Double(size))..<Int(x.upperBound * Double(size)) {
        let i = (py * size + px) * 3
        sum += Double(pixels[i]) + Double(pixels[i + 1]) + Double(pixels[i + 2])
        count += 3
      }
    }
    return sum / count
  }

  @Test func theBufferHasThreeBytesPerPixel() {
    let pixels = SphereRenderer.render(width: size, height: size, lights: [light(rotation: 90)], shadowSampleCount: 4)
    #expect(pixels.count == size * size * 3)
  }

  @Test func noLightsGivesABlackPicture() {
    let pixels = SphereRenderer.render(width: 8, height: 8, lights: [], shadowSampleCount: 4)
    #expect(pixels == [UInt8](repeating: 0, count: 8 * 8 * 3))
  }

  @Test func theSideTheLightComesFromIsBrighter() {
    let left = 0.36...0.48
    let right = 0.52...0.64
    let rows = 0.36...0.45
    let fromRight = SphereRenderer.render(width: size, height: size, lights: [light(rotation: 90)], shadowSampleCount: 4)
    let fromLeft = SphereRenderer.render(width: size, height: size, lights: [light(rotation: -90)], shadowSampleCount: 4)
    #expect(brightness(fromRight, x: right, y: rows) > brightness(fromRight, x: left, y: rows) + 20)
    #expect(brightness(fromLeft, x: left, y: rows) > brightness(fromLeft, x: right, y: rows) + 20)
  }

  @Test func differentLightsGiveDifferentPictures() {
    let a = SphereRenderer.render(width: 48, height: 48, lights: [light(rotation: 90)], shadowSampleCount: 4)
    let b = SphereRenderer.render(width: 48, height: 48, lights: [light(rotation: -90)], shadowSampleCount: 4)
    #expect(a != b)
  }

  @Test func thePNGDecodesToTheSameSize() throws {
    let pixels = SphereRenderer.render(width: 64, height: 64, lights: [light(rotation: 45)], shadowSampleCount: 4)
    let png = try #require(SphereRenderer.pngData(fromRGB8: pixels, width: 64, height: 64))
    let rep = try #require(NSBitmapImageRep(data: png))
    #expect(rep.pixelsWide == 64 && rep.pixelsHigh == 64)
  }

  @Test func theDefaultLightsAreTheOnesOfTheApp() {
    #expect(LightParams.makeDefault(index: 0).rotationDeg == -135)
    #expect(LightParams.makeDefault(index: 1).elevationDeg == 55)
    #expect(LightParams.makeDefault(index: 2).hardness == 0.3)
  }
}
```

Run: `cd "<repo>/Plugins/SphereLight" && swift test 2>&1 | grep -E "error" | head -2`
Expected: un errore: il pacchetto non esiste ancora (manca `Package.swift`).

- [ ] **Step 2: Implementare**

**`Plugins/SphereLight/Package.swift`** (file nuovo o riscritto per intero):

```swift
// swift-tools-version: 6.2
import PackageDescription

// The Sphere Light Reference plug-in of DT Hub (docs/superpowers/specs/2026-10-04-plugin-sphere-light-design.md).
let package = Package(
  name: "SphereLight",
  platforms: [.macOS(.v26)],
  products: [.library(name: "SphereLight", type: .dynamic, targets: ["SphereLight"])],
  targets: [
    .target(name: "SphereLight"),
    .testTarget(name: "SphereLightTests", dependencies: ["SphereLight"]),
  ]
)
```

**`Plugins/SphereLight/Sources/SphereLight/Models.swift`** (file nuovo o riscritto per intero):

```swift
import SwiftUI

/// A 3D vector for the ray tracer.
struct Vec3 {
  var x: Double
  var y: Double
  var z: Double

  static let zero = Vec3(x: 0, y: 0, z: 0)

  var length: Double { (x * x + y * y + z * z).squareRoot() }

  func normalized() -> Vec3 {
    let len = length
    guard len > 0 else { return self }
    return Vec3(x: x / len, y: y / len, z: z / len)
  }

  func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }

  func cross(_ o: Vec3) -> Vec3 {
    Vec3(x: y * o.z - z * o.y, y: z * o.x - x * o.z, z: x * o.y - y * o.x)
  }

  static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
  static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
  static func * (a: Vec3, s: Double) -> Vec3 { Vec3(x: a.x * s, y: a.y * s, z: a.z * s) }
}

/// One light's editable parameters. Intensity (brightness) and hardness (shadow-edge sharpness) are independent.
struct LightParams: Identifiable, Equatable {
  let id: UUID
  var rotationDeg: Double
  var elevationDeg: Double
  var intensity: Double  // 0.2...3
  var hardness: Double  // 0 (soft) ... 1 (hard)
  var color: Color

  init(
    id: UUID = UUID(), rotationDeg: Double, elevationDeg: Double, intensity: Double,
    hardness: Double, color: Color
  ) {
    self.id = id
    self.rotationDeg = rotationDeg
    self.elevationDeg = elevationDeg
    self.intensity = intensity
    self.hardness = hardness
    self.color = color
  }

  /// The lights a new session starts with (index 0, 1) and the one the "+" button adds (index 2).
  static func makeDefault(index: Int) -> LightParams {
    switch index {
    case 0:
      return LightParams(
        rotationDeg: -135, elevationDeg: 27, intensity: 1.5, hardness: 0.65, color: .white)
    case 1:
      return LightParams(
        rotationDeg: 70, elevationDeg: 55, intensity: 0.7, hardness: 0.4, color: .white)
    default:
      return LightParams(
        rotationDeg: 175, elevationDeg: 25, intensity: 0.6, hardness: 0.3, color: .white)
    }
  }
}
```

**`Plugins/SphereLight/Sources/SphereLight/SphereRenderer.swift`** (file nuovo o riscritto per intero):

```swift
import AppKit
import SwiftUI

// ---------------------------------------------------------------------------
// CPU ray tracer -- direct Swift port of the DT script's renderSphereImageMulti
// (same camera, same sphere+ground-plane scene, same soft-shadow disk
// sampling), with one deliberate change: shadow softness ("Hardness") is now
// its own independent per-light parameter instead of being derived from
// Intensity (BASE_ANGULAR_RADIUS / intensity in the original script).
//
// Hardness drives BOTH shadows a light casts:
// - the shadow it casts ON THE GROUND PLANE (cast shadow): via angularRadius,
//   which widens/narrows the disk-sampled penumbra, same as before.
// - the shadow it casts on the SPHERE ITSELF, at the day/night terminator
//   (self-shadow): via a smoothstep band of the same angularRadius width
//   around n·l = 0, instead of a hard `max(0, n·l)` cutoff. Low hardness
//   softens both edges together; high hardness sharpens both together.
// ---------------------------------------------------------------------------
enum SphereRenderer {

  private struct PreparedLight {
    var dir: Vec3
    var basisT: Vec3
    var basisB: Vec3
    var intensity: Double
    var color: (r: Double, g: Double, b: Double)
    var angularRadius: Double
    var ambient: Double
  }

  private struct Camera {
    var eye: Vec3
    var forward: Vec3
    var right: Vec3
    var camUp: Vec3
    var tanHalfFov: Double
  }

  // Hardness=1 -> crisp shadow edge (small angular radius).
  // Hardness=0 -> very diffuse shadow edge (large angular radius).
  // BASE_ANGULAR_RADIUS (0.09, the original script's fixed value at
  // intensity=1) sits roughly at hardness ~0.65, matching the old "default"
  // look while both ends of the new slider now reach further than the old
  // 0.2...3 intensity range ever could.
  //
  // hardnessMaxRadius was widened from 0.30 -> 0.55 after comparing against
  // the original Three.js reference tool (Sphere Light generator.html):
  // its MeshStandardMaterial terminator reads noticeably softer than a pure
  // Lambertian cutoff even at this raytracer's old Hardness=0 extreme. This
  // is a shared radius (also used for the cast-shadow penumbra), so a wider
  // max here also softens the ground shadow at low Hardness -- both were
  // judged to belong to the same "how soft is this light" control.
  private static let hardnessMinRadius = 0.02
  private static let hardnessMaxRadius = 0.55

  private static func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }

  private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = clamp01((x - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)
  }

  private static func computeLightDir(rotationDeg: Double, elevationDeg: Double) -> Vec3 {
    var elDeg = max(-89.5, min(89.5, elevationDeg))
    if abs(elDeg) < 0.5 { elDeg = elDeg >= 0 ? 0.5 : -0.5 }
    let az = rotationDeg * Double.pi / 180
    let el = elDeg * Double.pi / 180
    let r: Double = abs(elevationDeg) <= 12 ? 22 : 10
    let lightPos = Vec3(x: r * cos(el) * sin(az), y: r * sin(el), z: r * cos(el) * cos(az))
    let lightTarget = Vec3(x: 0, y: -1, z: 0)
    return (lightPos - lightTarget).normalized()
  }

  private static func ambient(forElevation elevationDeg: Double) -> Double {
    let t = (elevationDeg + 90) / 180
    return 0.06 + 0.16 * clamp01(t)
  }

  private static func orthonormalBasis(_ n: Vec3) -> (t: Vec3, b: Vec3) {
    let a: Vec3 = abs(n.x) > 0.9 ? Vec3(x: 0, y: 1, z: 0) : Vec3(x: 1, y: 0, z: 0)
    let t = a.cross(n).normalized()
    let b = n.cross(t)
    return (t, b)
  }

  private static func buildCamera() -> Camera {
    let eye = Vec3(x: 0, y: 6, z: 8)
    let target = Vec3(x: 0, y: -0.5, z: 0)
    let forward = (target - eye).normalized()
    let worldUp = Vec3(x: 0, y: 1, z: 0)
    let right = forward.cross(worldUp).normalized()
    let camUp = right.cross(forward)
    let tanHalfFov = tan((35 * Double.pi / 180) / 2)
    return Camera(eye: eye, forward: forward, right: right, camUp: camUp, tanHalfFov: tanHalfFov)
  }

  private static func intersectSphere(_ origin: Vec3, _ dir: Vec3) -> Double? {
    let b = origin.dot(dir)
    let c = origin.dot(origin) - 1
    let disc = b * b - c
    if disc < 0 { return nil }
    let sq = disc.squareRoot()
    let t1 = -b - sq
    let t2 = -b + sq
    let eps = 1e-4
    if t1 > eps { return t1 }
    if t2 > eps { return t2 }
    return nil
  }

  private static func intersectPlane(_ origin: Vec3, _ dir: Vec3, planeY: Double) -> Double? {
    if abs(dir.y) < 1e-9 { return nil }
    let t = (planeY - origin.y) / dir.y
    return t > 1e-4 ? t : nil
  }

  private static func diskSamples(_ n: Int) -> [(x: Double, y: Double)] {
    var pts: [(x: Double, y: Double)] = []
    pts.reserveCapacity(n)
    let golden = Double.pi * (3 - (5.0).squareRoot())
    for i in 0..<n {
      let rr = ((Double(i) + 0.5) / Double(n)).squareRoot()
      let theta = Double(i) * golden
      pts.append((x: rr * cos(theta), y: rr * sin(theta)))
    }
    return pts
  }

  private static func pixelRotation(_ px: Int, _ py: Int) -> Double {
    let h = sin(Double(px) * 12.9898 + Double(py) * 78.233) * 43758.5453
    return (h - h.rounded(.down)) * Double.pi * 2
  }

  private static func rgbComponents(of color: Color) -> (r: Double, g: Double, b: Double) {
    let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
    return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
  }

  private static func prepareLight(_ l: LightParams) -> PreparedLight {
    let dir = computeLightDir(rotationDeg: l.rotationDeg, elevationDeg: l.elevationDeg)
    let basis = orthonormalBasis(dir)
    let c = rgbComponents(of: l.color)
    let h = clamp01(l.hardness)
    let radius = hardnessMinRadius + (1 - h) * (hardnessMaxRadius - hardnessMinRadius)
    return PreparedLight(
      dir: dir, basisT: basis.t, basisB: basis.b,
      intensity: l.intensity, color: c,
      angularRadius: radius,
      ambient: ambient(forElevation: l.elevationDeg)
    )
  }

  /// Renders a tightly-packed RGB8 pixel buffer (no alpha), row-major, top-to-bottom.
  static func render(width: Int, height: Int, lights: [LightParams], shadowSampleCount: Int = 16)
    -> [UInt8]
  {
    let cam = buildCamera()
    let shadowSamples = diskSamples(shadowSampleCount)

    let BG = 0.541
    let SPHERE_ALBEDO = 0.8
    let PLANE_ALBEDO = 0.541

    let prepared = lights.map(prepareLight)
    guard !prepared.isEmpty else { return [UInt8](repeating: 0, count: width * height * 3) }
    let ambientAvg = prepared.reduce(0.0) { $0 + $1.ambient } / Double(prepared.count)

    var pixels = [UInt8](repeating: 0, count: width * height * 3)

    pixels.withUnsafeMutableBufferPointer { buf in
      for py in 0..<height {
        let v = (1 - 2 * (Double(py) + 0.5) / Double(height)) * cam.tanHalfFov
        for px in 0..<width {
          let u = (2 * (Double(px) + 0.5) / Double(width) - 1) * cam.tanHalfFov
          let dir = (cam.forward + cam.right * u + cam.camUp * v).normalized()
          let origin = cam.eye

          let tSphere = intersectSphere(origin, dir)
          let tPlane = intersectPlane(origin, dir, planeY: -1)

          var rC = 0.0
          var gC = 0.0
          var bC = 0.0

          if let ts = tSphere, (tPlane == nil || ts < tPlane!) {
            let hit = origin + dir * ts
            let n = hit.normalized()
            for l in prepared {
              // Soft terminator: same angularRadius that softens the cast
              // shadow on the plane also widens/narrows this band, so the
              // sphere's own day/night edge tracks the Hardness slider
              // instead of always being a hard Lambertian cutoff.
              let rawNdotL = n.dot(l.dir)
              let halfWidth = max(1e-4, l.angularRadius)
              let ndotl = smoothstep(-halfWidth, halfWidth, rawNdotL)
              rC += l.intensity * l.color.r * ndotl
              gC += l.intensity * l.color.g * ndotl
              bC += l.intensity * l.color.b * ndotl
            }
            rC = SPHERE_ALBEDO * (rC + ambientAvg)
            gC = SPHERE_ALBEDO * (gC + ambientAvg)
            bC = SPHERE_ALBEDO * (bC + ambientAvg)
          } else if let tp = tPlane {
            let hit = origin + dir * tp
            let rot = pixelRotation(px, py)
            let cosr = cos(rot)
            let sinr = sin(rot)
            for l in prepared {
              let ndotl = max(0, l.dir.y)  // plane normal = (0,1,0)
              var lit = 0.0
              for sp in shadowSamples {
                let rx = sp.x * cosr - sp.y * sinr
                let ry = sp.x * sinr + sp.y * cosr
                let jitter =
                  l.basisT * (rx * l.angularRadius) + l.basisB * (ry * l.angularRadius)
                let sampleDir = (l.dir + jitter).normalized()
                if intersectSphere(hit, sampleDir) == nil { lit += 1 }
              }
              let visibility = lit / Double(shadowSamples.count)
              rC += l.intensity * l.color.r * ndotl * visibility
              gC += l.intensity * l.color.g * ndotl * visibility
              bC += l.intensity * l.color.b * ndotl * visibility
            }
            rC = PLANE_ALBEDO * (rC + ambientAvg)
            gC = PLANE_ALBEDO * (gC + ambientAvg)
            bC = PLANE_ALBEDO * (bC + ambientAvg)
          } else {
            rC = BG
            gC = BG
            bC = BG
          }

          let R = UInt8(max(0, min(255, (255 * pow(clamp01(rC), 1 / 2.2)).rounded())))
          let G = UInt8(max(0, min(255, (255 * pow(clamp01(gC), 1 / 2.2)).rounded())))
          let B = UInt8(max(0, min(255, (255 * pow(clamp01(bC), 1 / 2.2)).rounded())))

          let idx = (py * width + px) * 3
          buf[idx] = R
          buf[idx + 1] = G
          buf[idx + 2] = B
        }
      }
    }

    return pixels
  }

  private static func makeBitmap(width: Int, height: Int) -> NSBitmapImageRep? {
    NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: width,
      pixelsHigh: height,
      bitsPerSample: 8,
      samplesPerPixel: 3,
      hasAlpha: false,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: width * 3,
      bitsPerPixel: 24
    )
  }

  static func nsImage(fromRGB8 pixels: [UInt8], width: Int, height: Int) -> NSImage? {
    guard let rep = makeBitmap(width: width, height: height), let dst = rep.bitmapData else {
      return nil
    }
    pixels.withUnsafeBufferPointer { src in
      dst.update(from: src.baseAddress!, count: pixels.count)
    }
    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(rep)
    return image
  }

  static func pngData(fromRGB8 pixels: [UInt8], width: Int, height: Int) -> Data? {
    guard let rep = makeBitmap(width: width, height: height), let dst = rep.bitmapData else {
      return nil
    }
    pixels.withUnsafeBufferPointer { src in
      dst.update(from: src.baseAddress!, count: pixels.count)
    }
    return rep.representation(using: .png, properties: [:])
  }
}
```

- [ ] **Step 3: Verificare**

Run: `cd "<repo>/Plugins/SphereLight" && swift test 2>&1 | grep -E "Test run|error:|issue"`
Expected: `Test run with 6 tests in 1 suite passed`.

- [ ] **Step 4: Commit**

```bash
cd "<repo>" && git add Plugins && git commit -m "feat: pacchetto del plug-in Sphere Light con il renderer della sfera

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: I messaggi e le stringhe

**Files:**
- Create: `Plugins/SphereLight/Sources/SphereLight/SLRMessages.swift`, `Plugins/SphereLight/Sources/SphereLight/Strings.swift`, `Plugins/SphereLight/Tests/SphereLightTests/SLRMessagesTests.swift`

**Interfaces:**
- Produces: `SLRMessages` — `acronym`, `overcastName` («SLR · Overcast»), `matchName` («SLR · Match the sun»), `lora`, `loraWeight`, `sphereName`, `fields(prompt:)`, `presets() -> [[String: Any]]` (per `registerPresets`), `moodboard(spherePath:)`, `pipeline(overcast:spherePath:) -> [String: Any]` (il valore della chiave `pipeline` di `contribute`). `L` — `Key` (CaseIterable), `systemIsItalian`, `text(_:italian:)`, `format(_:_:italian:)`, `isDefined(_:italian:)`.

- [ ] **Step 1: Scrivere i test e verificare che falliscano**

**`Plugins/SphereLight/Tests/SphereLightTests/SLRMessagesTests.swift`** (file nuovo o riscritto per intero):

```swift
import Testing

@testable import SphereLight

@Suite("SLRMessages")
struct SLRMessagesTests {
  private func steps(_ pipeline: [String: Any]) -> [[String: Any]] { pipeline["steps"] as? [[String: Any]] ?? [] }

  @Test func thePresetsCarryTheAcronymOfThePlugin() {
    let names = SLRMessages.presets().compactMap { $0["name"] as? String }
    #expect(names == ["SLR · Overcast", "SLR · Match the sun"])
  }

  @Test func bothPresetsHaveTheValuesOfTheScript() throws {
    for preset in SLRMessages.presets() {
      let fields = try #require(preset["fields"] as? [String: Any])
      #expect(fields["steps"] as? Int == 4)
      #expect(fields["guidanceScale"] as? Double == 1.0)
      #expect(fields["sampler"] as? Int == 16)
      #expect(fields["shift"] as? Int == 3)
      #expect(fields["cfgZeroStar"] as? Bool == false)
      // No size and no model: those are the user's.
      #expect(fields["width"] == nil && fields["height"] == nil && preset["model"] == nil)
    }
  }

  @Test func onlyTheMatchPresetHasTheLoraAtZeroPointSix() throws {
    let presets = SLRMessages.presets()
    #expect(presets[0]["loras"] == nil)
    let loras = try #require(presets[1]["loras"] as? [[String: Any]])
    #expect(loras.count == 1)
    #expect(loras[0]["file"] as? String == "flux_2_sun_direction_lora_v1_lora_f16.ckpt")
    #expect(loras[0]["weight"] as? Double == 0.6)
  }

  @Test func thePromptsAreTheOnesOfTheScript() throws {
    let prompts = SLRMessages.presets().map { ($0["fields"] as? [String: Any])?["prompt"] as? String }
    #expect(prompts[0] == "make it an overcast day, remove the shadows")
    #expect(prompts[1] == "match light direction, colors and intensity from the reference image 2")
  }

  @Test func withOvercastThereAreTwoPassesAndTheSecondStartsFromTheFirst() {
    let pipeline = SLRMessages.pipeline(overcast: true, spherePath: "/tmp/s.png")
    let list = steps(pipeline)
    #expect(list.count == 2)
    #expect(list[0]["preset"] as? String == "SLR · Overcast")
    #expect(list[0]["moodboard"] == nil && list[0]["useOutputAsStart"] == nil)
    #expect(list[1]["preset"] as? String == "SLR · Match the sun")
    #expect(list[1]["useOutputAsStart"] as? Bool == true)
  }

  @Test func withoutOvercastOnlyTheMatchPassRunsOnTheCanvas() {
    let list = steps(SLRMessages.pipeline(overcast: false, spherePath: "/tmp/s.png"))
    #expect(list.count == 1)
    #expect(list[0]["preset"] as? String == "SLR · Match the sun")
    #expect(list[0]["useOutputAsStart"] as? Bool == false)
  }

  @Test func theSphereIsInTheMoodboardOfTheMatchPassOnly() throws {
    for overcast in [true, false] {
      let list = steps(SLRMessages.pipeline(overcast: overcast, spherePath: "/tmp/s.png"))
      let moodboard = try #require(list.last?["moodboard"] as? [[String: Any]])
      #expect(moodboard.count == 1)
      #expect(moodboard[0]["path"] as? String == "/tmp/s.png")
      #expect(moodboard[0]["name"] as? String == "Sphere light")
    }
  }

  @Test func everyWordIsInItalianAndEnglish() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true), "\(key) has no Italian")
      #expect(L.isDefined(key, italian: false), "\(key) has no English")
    }
  }

  @Test func formattedWordsTakeTheirArguments() {
    #expect(L.format(.sentWithConflicts, 2, italian: false) == "Sent. 2 conflict(s) waiting in the app.")
    #expect(L.format(.savedDesktop, "Sphere Light 001.png", italian: true).contains("Sphere Light 001.png"))
  }
}
```

Run: `cd "<repo>/Plugins/SphereLight" && swift test 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'SLRMessages' in scope`.

- [ ] **Step 2: Implementare**

**`Plugins/SphereLight/Sources/SphereLight/SLRMessages.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation

/// The JSON the plug-in sends to DT Hub: its two presets and what "Send" contributes. Pure, so it can be tested.
enum SLRMessages {
  /// The prefix of the names of the plug-in's presets: the Preset menu shows nothing else about where one comes from.
  static let acronym = "SLR"
  static let overcastName = "\(acronym) · Overcast"
  static let matchName = "\(acronym) · Match the sun"
  static let overcastPrompt = "make it an overcast day, remove the shadows"
  static let matchPrompt = "match light direction, colors and intensity from the reference image 2"
  static let lora = "flux_2_sun_direction_lora_v1_lora_f16.ckpt"
  static let loraWeight = 0.6
  /// The name of the sphere in the Moodboard.
  static let sphereName = "Sphere light"
  static let pipelineName = "Sphere Light"

  /// The settings of the sun-direction passes of the Light Direction companion script.
  static func fields(prompt: String) -> [String: Any] {
    [
      "prompt": prompt, "steps": 4, "guidanceScale": 1.0, "shift": 3, "sampler": 16,
      "batchSize": 1, "batchCount": 1, "cfgZeroStar": false,
    ]
  }

  /// The two presets for the Preset menu (`presets` message). The app never overwrites a name it has.
  static func presets() -> [[String: Any]] {
    [
      ["name": overcastName, "fields": fields(prompt: overcastPrompt)],
      [
        "name": matchName, "fields": fields(prompt: matchPrompt),
        "loras": [["file": lora, "weight": loraWeight]],
      ],
    ]
  }

  static func moodboard(spherePath: String) -> [[String: Any]] {
    [["name": sphereName, "path": spherePath]]
  }

  /// The `pipeline` of a `contribute`: with `overcast` a first pass flattens the shadows of the canvas, then the
  /// sun is matched starting from that picture; without it only the second pass runs, on the canvas.
  static func pipeline(overcast: Bool, spherePath: String) -> [String: Any] {
    var steps: [[String: Any]] = []
    if overcast { steps.append(["title": "Overcast", "preset": overcastName]) }
    steps.append([
      "title": "Match the sun", "preset": matchName, "moodboard": moodboard(spherePath: spherePath),
      "useOutputAsStart": overcast,
    ])
    return ["name": pipelineName, "steps": steps]
  }
}
```

**`Plugins/SphereLight/Sources/SphereLight/Strings.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation

/// The words of the plug-in, in Italian and English. A plug-in bundle holds only its library, so there are no
/// `.strings` files: the table is here.
enum L {
  enum Key: CaseIterable {
    case lights, preview, light, rotation, elevation, intensity, hardness, color
    case addLight, removeLight
    case overcast, saveDesktop
    case sendPipeline, sendMoodboard
    case sent, sentWithConflicts, savedDesktop, saveFailed
    case noFolder, notAnswered, rendering, renderFailed, active, inactive
  }

  static var systemIsItalian: Bool {
    Locale.preferredLanguages.first?.hasPrefix("it") ?? false
  }

  static func text(_ key: Key, italian: Bool = systemIsItalian) -> String {
    (italian ? it : en)[key] ?? en[key] ?? "\(key)"
  }

  /// Whether the word is in the table of that language (the tests check both are complete).
  static func isDefined(_ key: Key, italian: Bool) -> Bool {
    (italian ? it : en)[key] != nil
  }

  static func format(_ key: Key, _ args: CVarArg..., italian: Bool = systemIsItalian) -> String {
    String(format: text(key, italian: italian), arguments: args)
  }

  private static let en: [Key: String] = [
    .lights: "Lights", .preview: "Preview", .light: "Light %d",
    .rotation: "Rotation (°)", .elevation: "Elevation (°)", .intensity: "Intensity",
    .hardness: "Shadow hardness", .color: "Color",
    .addLight: "Add light", .removeLight: "Remove light",
    .overcast: "Overcast (flatten the shadows first)", .saveDesktop: "Also save to Desktop",
    .sendPipeline: "Send to Generation", .sendMoodboard: "Sphere only, to the Moodboard",
    .sent: "Sent.", .sentWithConflicts: "Sent. %d conflict(s) waiting in the app.",
    .savedDesktop: "Saved to Desktop as %@.", .saveFailed: "Could not save to Desktop.",
    .noFolder: "No picture folder yet: switch the plug-in on first.",
    .notAnswered: "No answer from the app.", .rendering: "Rendering…", .renderFailed: "Rendering failed.",
    .active: "active", .inactive: "not active",
  ]

  private static let it: [Key: String] = [
    .lights: "Luci", .preview: "Anteprima", .light: "Luce %d",
    .rotation: "Rotazione (°)", .elevation: "Elevazione (°)", .intensity: "Intensità",
    .hardness: "Durezza dell'ombra", .color: "Colore",
    .addLight: "Aggiungi una luce", .removeLight: "Togli la luce",
    .overcast: "Overcast (prima appiattisci le ombre)", .saveDesktop: "Salva anche sulla Scrivania",
    .sendPipeline: "Invia a Generazione", .sendMoodboard: "Solo la sfera nel Moodboard",
    .sent: "Inviato.", .sentWithConflicts: "Inviato. %d conflitti in attesa nell'app.",
    .savedDesktop: "Salvata sulla Scrivania come %@.", .saveFailed: "Non si è potuto salvare sulla Scrivania.",
    .noFolder: "La cartella delle immagini non c'è ancora: prima accendi il plug-in.",
    .notAnswered: "Nessuna risposta dall'app.", .rendering: "Calcolo…", .renderFailed: "Calcolo non riuscito.",
    .active: "attivo", .inactive: "non attivo",
  ]
}
```

- [ ] **Step 3: Verificare che passino**

Run: `cd "<repo>/Plugins/SphereLight" && swift test 2>&1 | grep -E "Test run|error:|issue"`
Expected: `Test run with 15 tests in 2 suites passed`.

- [ ] **Step 4: Commit**

```bash
cd "<repo>" && git add Plugins && git commit -m "feat: messaggi, preset e stringhe del plug-in Sphere Light

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: La memoria e il salvataggio sulla Scrivania

**Files:**
- Create: `Plugins/SphereLight/Sources/SphereLight/DesktopSaver.swift`, `Plugins/SphereLight/Sources/SphereLight/SLRStore.swift`, `Plugins/SphereLight/Tests/SphereLightTests/SLRStoreTests.swift`

**Interfaces:**
- Produces: `SLRSession` (`lights`, `expanded`, `overcast`, `saveToDesktop`; `maxLights = 3`; `static initial()`: due luci predefinite aperte, caselle spente); `SLRStore(defaults:key:)` con `save(_:)` e `load() -> SLRSession?` (nil se manca, non si legge o non ha luci; al massimo tre luci); `DesktopSaver` — `desktopFolder`, `nextURL(in:)`, `save(_:in:) throws -> URL` (non sovrascrive mai).

- [ ] **Step 1: Scrivere i test e verificare che falliscano**

**`Plugins/SphereLight/Tests/SphereLightTests/SLRStoreTests.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation
import SwiftUI
import Testing

@testable import SphereLight

@Suite("SLRStore and DesktopSaver")
struct SLRStoreTests {
  /// A store on a throw-away suite: never the real preferences.
  private func makeStore() -> (SLRStore, () -> Void) {
    let name = "slr-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (SLRStore(defaults: defaults), { defaults.removePersistentDomain(forName: name) })
  }

  private func makeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("slr-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func nothingSavedMeansNoSession() {
    let (store, cleanup) = makeStore()
    defer { cleanup() }
    #expect(store.load() == nil)
  }

  @Test func threeLightsWithTheirColorsAndTheTwoBoxesComeBack() throws {
    let (store, cleanup) = makeStore()
    defer { cleanup() }
    var session = SLRSession.initial()
    session.lights.append(LightParams.makeDefault(index: 2))
    session.lights[1].color = Color(red: 1, green: 0.5, blue: 0.25)
    session.expanded[session.lights[1].id] = false
    session.overcast = true
    session.saveToDesktop = true
    store.save(session)
    let loaded = try #require(store.load())
    #expect(loaded.lights.count == 3)
    #expect(loaded.lights.map(\.id) == session.lights.map(\.id))
    #expect(loaded.lights[0].rotationDeg == -135 && loaded.lights[2].hardness == 0.3)
    #expect(loaded.expanded[session.lights[1].id] == false)
    #expect(loaded.overcast && loaded.saveToDesktop)
    let c = NSColor(loaded.lights[1].color).usingColorSpace(.deviceRGB)!
    #expect(abs(c.greenComponent - 0.5) < 0.01 && abs(c.blueComponent - 0.25) < 0.01)
  }

  @Test func theBoxesAreOffInAFirstRun() {
    let session = SLRSession.initial()
    #expect(session.lights.count == 2)
    #expect(!session.overcast && !session.saveToDesktop)
  }

  @Test func aSavedSessionWithoutLightsOrWithGarbageCountsAsNone() {
    let (store, cleanup) = makeStore()
    defer { cleanup() }
    store.defaults.set(Data("not json".utf8), forKey: store.key)
    #expect(store.load() == nil)
    store.save(SLRSession(lights: [], expanded: [:], overcast: true, saveToDesktop: true))
    #expect(store.load() == nil)
  }

  @Test func moreThanThreeSavedLightsAreCutToThree() throws {
    let (store, cleanup) = makeStore()
    defer { cleanup() }
    var session = SLRSession.initial()
    session.lights += [LightParams.makeDefault(index: 2), LightParams.makeDefault(index: 2)]
    store.save(session)
    #expect(try #require(store.load()).lights.count == 3)
  }

  @Test func theFirstSphereOfAFolderIsNumberOne() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(DesktopSaver.nextURL(in: folder).lastPathComponent == "Sphere Light 001.png")
  }

  @Test func theNextNumberIsOneMoreThanTheHighestAndOtherFilesAreIgnored() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    for name in ["Sphere Light 001.png", "Sphere Light 003.png", "Sphere Light copy.png", "photo.png"] {
      try Data().write(to: folder.appendingPathComponent(name))
    }
    #expect(DesktopSaver.nextURL(in: folder).lastPathComponent == "Sphere Light 004.png")
  }

  @Test func savingTwiceMakesTwoFilesAndNeverOverwrites() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = try DesktopSaver.save(Data("a".utf8), in: folder)
    let second = try DesktopSaver.save(Data("b".utf8), in: folder)
    #expect(first.lastPathComponent == "Sphere Light 001.png" && second.lastPathComponent == "Sphere Light 002.png")
    #expect(try Data(contentsOf: first) == Data("a".utf8))
  }

  @Test func aFolderThatIsNotThereIsAnError() {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("slr-missing-\(UUID().uuidString)")
    #expect(throws: (any Error).self) { try DesktopSaver.save(Data("a".utf8), in: missing) }
  }
}
```

Run: `cd "<repo>/Plugins/SphereLight" && swift test 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'SLRStore' in scope`.

- [ ] **Step 2: Implementare**

**`Plugins/SphereLight/Sources/SphereLight/DesktopSaver.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation

/// Saves a copy of the sphere as "Sphere Light NNN.png", with the first free number: an earlier one is never overwritten.
enum DesktopSaver {
  static let prefix = "Sphere Light "

  static var desktopFolder: URL {
    FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
  }

  /// "Sphere Light 004.png" when the folder has 001 and 003: one more than the highest number.
  static func nextURL(in folder: URL) -> URL {
    var highest = 0
    let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    for item in items {
      let name = item.deletingPathExtension().lastPathComponent
      guard name.hasPrefix(prefix), let number = Int(name.dropFirst(prefix.count)) else { continue }
      highest = max(highest, number)
    }
    return folder.appendingPathComponent(String(format: "%@%03d.png", prefix, highest + 1))
  }

  /// Writes `png` and returns where. Throws when the folder is not there or not writable.
  static func save(_ png: Data, in folder: URL = desktopFolder) throws -> URL {
    let url = nextURL(in: folder)
    try png.write(to: url, options: .withoutOverwriting)
    return url
  }
}
```

**`Plugins/SphereLight/Sources/SphereLight/SLRStore.swift`** (file nuovo o riscritto per intero):

```swift
import AppKit
import SwiftUI

/// What the plug-in remembers between runs: the lights (and whether each block is open) and the two boxes.
struct SLRSession: Equatable {
  static let maxLights = 3

  var lights: [LightParams]
  var expanded: [UUID: Bool]
  var overcast: Bool
  var saveToDesktop: Bool

  /// A first run: the two default lights, both open, both boxes off.
  static func initial() -> SLRSession {
    let lights = [LightParams.makeDefault(index: 0), LightParams.makeDefault(index: 1)]
    return SLRSession(
      lights: lights, expanded: Dictionary(uniqueKeysWithValues: lights.map { ($0.id, true) }),
      overcast: false, saveToDesktop: false)
  }
}

/// The session in `UserDefaults`. `Color` is not `Codable`, so it goes through plain RGB components.
struct SLRStore {
  static let key = "com.exiztenz.dthub.spherelight.state.v1"

  var defaults: UserDefaults = .standard
  var key: String = SLRStore.key

  private struct SavedLight: Codable {
    var id: UUID
    var rotationDeg: Double
    var elevationDeg: Double
    var intensity: Double
    var hardness: Double
    var colorR: Double
    var colorG: Double
    var colorB: Double
    var expanded: Bool
  }

  private struct Saved: Codable {
    var lights: [SavedLight]
    var overcast: Bool
    var saveToDesktop: Bool
  }

  func save(_ session: SLRSession) {
    let lights = session.lights.map { light -> SavedLight in
      let c = Self.components(of: light.color)
      return SavedLight(
        id: light.id, rotationDeg: light.rotationDeg, elevationDeg: light.elevationDeg,
        intensity: light.intensity, hardness: light.hardness, colorR: c.r, colorG: c.g, colorB: c.b,
        expanded: session.expanded[light.id, default: true])
    }
    let saved = Saved(lights: lights, overcast: session.overcast, saveToDesktop: session.saveToDesktop)
    guard let data = try? JSONEncoder().encode(saved) else { return }
    defaults.set(data, forKey: key)
  }

  /// The saved session; nil when there is none, it cannot be read or it has no lights.
  func load() -> SLRSession? {
    guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Saved.self, from: data),
      !saved.lights.isEmpty
    else { return nil }
    var lights: [LightParams] = []
    var expanded: [UUID: Bool] = [:]
    for item in saved.lights.prefix(SLRSession.maxLights) {
      lights.append(
        LightParams(
          id: item.id, rotationDeg: item.rotationDeg, elevationDeg: item.elevationDeg,
          intensity: item.intensity, hardness: item.hardness,
          color: Color(red: item.colorR, green: item.colorG, blue: item.colorB)))
      expanded[item.id] = item.expanded
    }
    return SLRSession(lights: lights, expanded: expanded, overcast: saved.overcast, saveToDesktop: saved.saveToDesktop)
  }

  private static func components(of color: Color) -> (r: Double, g: Double, b: Double) {
    let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
    return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
  }
}
```

- [ ] **Step 3: Verificare che passino**

Run: `cd "<repo>/Plugins/SphereLight" && swift test 2>&1 | grep -E "Test run|error:|issue"`
Expected: `Test run with 24 tests in 3 suites passed`.

- [ ] **Step 4: Commit**

```bash
cd "<repo>" && git add Plugins && git commit -m "feat: memoria delle luci e salvataggio sulla Scrivania del plug-in Sphere Light

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Il lavoro dei due pulsanti

**Files:**
- Modify/Create: `Plugins/SphereLight/Package.swift`, `Plugins/SphereLight/Sources/SphereLight/SphereSender.swift`, `Plugins/SphereLight/Tests/SphereLightTests/SphereSenderTests.swift`

**Interfaces:**
- Consumes: `SphereRenderer`, `LightParams` (Task 1); `SLRMessages`, `L` (Task 2); `DesktopSaver` (Task 3).
- Produces: `SphereSender` (`@MainActor struct`): `Kind` (`.pipeline`, `.moodboard`); `init(contribute:registerPresets:saveFolder:size:shadowSamples:italian:)` (le prime due sono chiusure `@MainActor` che il plug-in lega a `host.contribute` e `host.registerPresets`; il resto ha valori predefiniti: Scrivania vera, 1024, 16, lingua del sistema); `send(_:lights:overcast:saveToDesktop:tempFolder:) async -> String` (la riga di stato); `static fileName`; `static describe(_:italian:)`. Il pacchetto ora dipende da `PluginKit` (`../../PluginKit`) con `moduleAliases`.

- [ ] **Step 1: Scrivere i test e verificare che falliscano**

**`Plugins/SphereLight/Tests/SphereLightTests/SphereSenderTests.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation
import Testing

@testable import SphereLight

/// What the sender asked of the app.
@MainActor
final class Spy {
  var contributions: [[String: Any]] = []
  var presets: [[[String: Any]]] = []
  var answer: [String: Any]? = ["type": "ok", "conflicts": 0]
}

@MainActor
@Suite("SphereSender")
struct SphereSenderTests {
  private func makeSender(_ spy: Spy, saveFolder: URL) -> SphereSender {
    SphereSender(
      contribute: { spy.contributions.append($0); return spy.answer },
      registerPresets: { spy.presets.append($0); return ["type": "ok"] },
      saveFolder: saveFolder, size: 32, shadowSamples: 2, italian: false)
  }

  private func makeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("slr-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private let lights = [LightParams.makeDefault(index: 0)]

  @Test func withoutAPictureFolderNothingIsSent() async throws {
    let spy = Spy()
    let desk = try makeFolder()
    defer { try? FileManager.default.removeItem(at: desk) }
    let line = await makeSender(spy, saveFolder: desk).send(
      .pipeline, lights: lights, overcast: false, saveToDesktop: true, tempFolder: nil)
    #expect(line == "No picture folder yet: switch the plug-in on first.")
    #expect(spy.contributions.isEmpty && spy.presets.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: desk.path).isEmpty)
  }

  @Test func thePipelineGoesWithTheSphereAndThePresetsAreOfferedFirst() async throws {
    let spy = Spy()
    let desk = try makeFolder(), temp = try makeFolder()
    defer { for url in [desk, temp] { try? FileManager.default.removeItem(at: url) } }
    let line = await makeSender(spy, saveFolder: desk).send(
      .pipeline, lights: lights, overcast: true, saveToDesktop: false, tempFolder: temp.path)
    #expect(line == "Sent.")
    #expect(spy.presets.count == 1 && spy.presets[0].count == 2)
    let sphere = temp.appendingPathComponent(SphereSender.fileName).path
    #expect(FileManager.default.fileExists(atPath: sphere))
    let pipeline = try #require(spy.contributions.first?["pipeline"] as? [String: Any])
    let steps = try #require(pipeline["steps"] as? [[String: Any]])
    #expect(steps.count == 2)
    #expect((steps[1]["moodboard"] as? [[String: Any]])?.first?["path"] as? String == sphere)
    #expect(try FileManager.default.contentsOfDirectory(atPath: desk.path).isEmpty)
  }

  @Test func onlyTheMoodboardOffersNoPresetsAndSendsOnlyTheSphere() async throws {
    let spy = Spy()
    let desk = try makeFolder(), temp = try makeFolder()
    defer { for url in [desk, temp] { try? FileManager.default.removeItem(at: url) } }
    _ = await makeSender(spy, saveFolder: desk).send(
      .moodboard, lights: lights, overcast: true, saveToDesktop: false, tempFolder: temp.path)
    #expect(spy.presets.isEmpty)
    #expect(spy.contributions.count == 1 && Set(spy.contributions[0].keys) == ["moodboard"])
  }

  @Test func theBoxSavesACopyOnTheDesktopAndSaysSo() async throws {
    let spy = Spy()
    let desk = try makeFolder(), temp = try makeFolder()
    defer { for url in [desk, temp] { try? FileManager.default.removeItem(at: url) } }
    let sender = makeSender(spy, saveFolder: desk)
    let line = await sender.send(.moodboard, lights: lights, overcast: false, saveToDesktop: true, tempFolder: temp.path)
    #expect(line == "Sent. Saved to Desktop as Sphere Light 001.png.")
    _ = await sender.send(.moodboard, lights: lights, overcast: false, saveToDesktop: true, tempFolder: temp.path)
    #expect(Set(try FileManager.default.contentsOfDirectory(atPath: desk.path)) == ["Sphere Light 001.png", "Sphere Light 002.png"])
  }

  @Test func aFailedDesktopSaveIsReportedAndTheSendGoesOn() async throws {
    let spy = Spy()
    let temp = try makeFolder()
    defer { try? FileManager.default.removeItem(at: temp) }
    let missing = temp.appendingPathComponent("no-such-folder")
    let line = await makeSender(spy, saveFolder: missing).send(
      .moodboard, lights: lights, overcast: false, saveToDesktop: true, tempFolder: temp.path)
    #expect(line == "Sent. Could not save to Desktop.")
    #expect(spy.contributions.count == 1)
  }

  @Test func conflictsAnErrorAndNoAnswerAreSaid() async throws {
    let spy = Spy()
    let desk = try makeFolder(), temp = try makeFolder()
    defer { for url in [desk, temp] { try? FileManager.default.removeItem(at: url) } }
    let sender = makeSender(spy, saveFolder: desk)
    spy.answer = ["type": "ok", "conflicts": 2]
    #expect(await sender.send(.moodboard, lights: lights, overcast: false, saveToDesktop: false, tempFolder: temp.path)
      == "Sent. 2 conflict(s) waiting in the app.")
    spy.answer = ["type": "error", "text": "Plug-in is off"]
    #expect(await sender.send(.moodboard, lights: lights, overcast: false, saveToDesktop: false, tempFolder: temp.path)
      == "Plug-in is off")
    spy.answer = nil
    #expect(await sender.send(.moodboard, lights: lights, overcast: false, saveToDesktop: false, tempFolder: temp.path)
      == "No answer from the app.")
  }
}
```

Run: `cd "<repo>/Plugins/SphereLight" && swift test 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'SphereSender' in scope`.

- [ ] **Step 2: Implementare**

```diff
diff --git a/Plugins/SphereLight/Package.swift b/Plugins/SphereLight/Package.swift
index 4aca68f..594d442 100644
--- a/Plugins/SphereLight/Package.swift
+++ b/Plugins/SphereLight/Package.swift
@@ -6,8 +6,13 @@ let package = Package(
   name: "SphereLight",
   platforms: [.macOS(.v26)],
   products: [.library(name: "SphereLight", type: .dynamic, targets: ["SphereLight"])],
+  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
   targets: [
-    .target(name: "SphereLight"),
+    // Every plug-in carries its own copy of the kit; `moduleAliases` gives it a name of its own, so two plug-ins
+    // do not define the same Objective-C classes twice in one process.
+    .target(
+      name: "SphereLight",
+      dependencies: [.product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "SphereLightKit"])]),
     .testTarget(name: "SphereLightTests", dependencies: ["SphereLight"]),
   ]
 )
```

**`Plugins/SphereLight/Sources/SphereLight/SphereSender.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation

/// The two buttons of the tab, apart from the screen: render the sphere, write it where the app can read it, keep a
/// copy on the Desktop if asked, and contribute. It talks to the app through closures, so a test can stand in for it.
@MainActor
struct SphereSender {
  enum Kind { case pipeline, moodboard }

  /// `host.contribute` / `host.registerPresets`.
  var contribute: @MainActor ([String: Any]) async -> [String: Any]?
  var registerPresets: @MainActor ([[String: Any]]) async -> [String: Any]?
  var saveFolder: URL = DesktopSaver.desktopFolder
  var size = 1024
  var shadowSamples = 16
  var italian = L.systemIsItalian

  static let fileName = "com.exiztenz.dthub.spherelight-sphere.png"

  /// Does the whole job and returns the line to show under the buttons.
  func send(_ kind: Kind, lights: [LightParams], overcast: Bool, saveToDesktop: Bool, tempFolder: String?) async -> String {
    guard let tempFolder else { return L.text(.noFolder, italian: italian) }
    let (size, samples) = (size, shadowSamples)
    let pixels = await Task.detached(priority: .userInitiated) {
      SphereRenderer.render(width: size, height: size, lights: lights, shadowSampleCount: samples)
    }.value
    guard let png = SphereRenderer.pngData(fromRGB8: pixels, width: size, height: size) else {
      return L.text(.renderFailed, italian: italian)
    }
    let path = (tempFolder as NSString).appendingPathComponent(Self.fileName)
    do {
      try FileManager.default.createDirectory(atPath: tempFolder, withIntermediateDirectories: true)
      try png.write(to: URL(fileURLWithPath: path))
    } catch {
      return L.text(.renderFailed, italian: italian)
    }

    var lines: [String] = []
    if saveToDesktop {
      if let saved = try? DesktopSaver.save(png, in: saveFolder) {
        lines.append(L.format(.savedDesktop, saved.lastPathComponent, italian: italian))
      } else {
        lines.append(L.text(.saveFailed, italian: italian))
      }
    }

    let answer: [String: Any]?
    switch kind {
    case .pipeline:
      // The presets are offered again (a name the menu has is never touched), in case the user deleted one.
      _ = await registerPresets(SLRMessages.presets())
      answer = await contribute(["pipeline": SLRMessages.pipeline(overcast: overcast, spherePath: path)])
    case .moodboard:
      answer = await contribute(["moodboard": SLRMessages.moodboard(spherePath: path)])
    }
    lines.insert(Self.describe(answer, italian: italian), at: 0)
    return lines.joined(separator: " ")
  }

  static func describe(_ answer: [String: Any]?, italian: Bool) -> String {
    guard let answer else { return L.text(.notAnswered, italian: italian) }
    if answer["type"] as? String == "error" { return answer["text"] as? String ?? L.text(.notAnswered, italian: italian) }
    let conflicts = answer["conflicts"] as? Int ?? 0
    return conflicts > 0 ? L.format(.sentWithConflicts, conflicts, italian: italian) : L.text(.sent, italian: italian)
  }
}
```

- [ ] **Step 3: Verificare che passino**

Run: `cd "<repo>/Plugins/SphereLight" && swift test 2>&1 | grep -E "Test run|error:|issue"`
Expected: `Test run with 30 tests in 4 suites passed`.

- [ ] **Step 4: Commit**

```bash
cd "<repo>" && git add Plugins && git commit -m "feat: SphereSender, il lavoro dei due pulsanti del plug-in Sphere Light

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Il tab, il plug-in e il bundle

**Files:**
- Create: `Plugins/SphereLight/Scripts/build.sh`, `Plugins/SphereLight/Sources/SphereLight/LightControlView.swift`, `Plugins/SphereLight/Sources/SphereLight/SLRState.swift`, `Plugins/SphereLight/Sources/SphereLight/SphereLightPlugin.swift`, `Plugins/SphereLight/Sources/SphereLight/SphereLightView.swift`

**Interfaces:**
- Consumes: tutto quanto sopra e `DTHubPlugin`, `DTHubPluginEntry`, `DTHubManifest`, `DTHubContext`, `DTHubHost.contribute`/`registerPresets` del kit.
- Produces: `SLRState` (`@MainActor ObservableObject`: luci, aperture, caselle, anteprima, stato, `isSending`, `active`, `tempFolder`; `addLight`, `removeLight`, `lightChanged`); `LightControlView`; `SphereLightView(state:send:)`; `SphereLightPlugin` (`context` salva la `tempFolder`, `activate` accende i pulsanti e offre i preset, `deactivate` li spegne; ogni altro tipo risponde `unsupported`); `SphereLightEntry`; `Plugins/SphereLight/Scripts/build.sh OUT` che fa `OUT/SphereLight.dthubplugin`.

- [ ] **Step 1: Scrivere i file**

**`Plugins/SphereLight/Scripts/build.sh`** (file nuovo o riscritto per intero):

```bash
#!/bin/zsh
# build.sh OUT_FOLDER
# Builds the Sphere Light plug-in into OUT_FOLDER/SphereLight.dthubplugin (ad-hoc signed). Needs the Swift toolchain;
# run from anywhere.
set -e
HERE="${0:A:h}"
OUT="${1:?usage: build.sh OUT_FOLDER}"
VERSION="1.0"
mkdir -p "$OUT"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
swift build -c release --package-path "$HERE/.." --scratch-path "$SCRATCH" >/dev/null
"$HERE/../../../PluginKit/Scripts/make-bundle.sh" "$(find "$SCRATCH" -name libSphereLight.dylib | head -1)" \
  "$OUT/SphereLight.dthubplugin" com.exiztenz.dthub.spherelight SphereLight "$VERSION" SphereLightEntry
echo "$OUT/SphereLight.dthubplugin"
```

**`Plugins/SphereLight/Sources/SphereLight/LightControlView.swift`** (file nuovo o riscritto per intero):

```swift
import SwiftUI

/// One light: a block that opens and closes, with its five controls.
struct LightControlView: View {
  @Binding var light: LightParams
  let index: Int
  @Binding var isExpanded: Bool
  let canRemove: Bool
  let onRemove: () -> Void
  let onChange: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      if isExpanded {
        VStack(alignment: .leading, spacing: 10) {
          sliderRow(L.text(.rotation), value: $light.rotationDeg, range: -180...180, format: "%.0f°")
          sliderRow(L.text(.elevation), value: $light.elevationDeg, range: -90...90, format: "%.0f°")
          sliderRow(L.text(.intensity), value: $light.intensity, range: 0.2...3, format: "%.2f")
          sliderRow(L.text(.hardness), value: $light.hardness, range: 0...1, format: "%.2f")
          HStack {
            Text(L.text(.color)).font(.subheadline.weight(.semibold))
            Spacer()
            ColorPicker("", selection: $light.color, supportsOpacity: false)
              .labelsHidden()
              .onChange(of: light.color) { _, _ in onChange() }
          }
        }
      }
    }
  }

  private var header: some View {
    HStack {
      Button {
        withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
          Text(L.format(.light, index + 1)).font(.headline)
          Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if canRemove {
        Button(action: onRemove) { Image(systemName: "minus.circle.fill") }
          .buttonStyle(.plain)
          .foregroundStyle(.orange)
          .help(L.text(.removeLight))
      }
    }
  }

  private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(title).font(.subheadline.weight(.semibold))
        Spacer()
        Text(String(format: format, value.wrappedValue)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
      }
      Slider(value: value, in: range).controlSize(.small)
        .onChange(of: value.wrappedValue) { _, _ in onChange() }
    }
  }
}
```

**`Plugins/SphereLight/Sources/SphereLight/SLRState.swift`** (file nuovo o riscritto per intero):

```swift
import AppKit
import SwiftUI

/// What the tab shows and edits. The lights and the two boxes are remembered (`SLRStore`).
@MainActor
final class SLRState: ObservableObject {
  static let previewSize = 220

  private let store: SLRStore
  private var renderTask: Task<Void, Never>?

  @Published var lights: [LightParams] { didSet { persist() } }
  @Published var expanded: [UUID: Bool] { didSet { persist() } }
  @Published var overcast: Bool { didSet { persist() } }
  @Published var saveToDesktop: Bool { didSet { persist() } }
  @Published var previewImage: NSImage?
  @Published var status = ""
  @Published var isSending = false
  @Published var active = false
  /// The folder the app lends for exchanging pictures (from the `context` message).
  var tempFolder: String?

  init(store: SLRStore = SLRStore()) {
    self.store = store
    let session = store.load() ?? .initial()
    lights = session.lights
    expanded = session.expanded
    overcast = session.overcast
    saveToDesktop = session.saveToDesktop
    scheduleRender()
  }

  var canAddLight: Bool { lights.count < SLRSession.maxLights }

  func addLight() {
    guard canAddLight else { return }
    let light = LightParams.makeDefault(index: lights.count)
    lights.append(light)
    expanded[light.id] = true
    scheduleRender()
  }

  func removeLight(_ id: UUID) {
    guard lights.count > 1 else { return }
    lights.removeAll { $0.id == id }
    expanded.removeValue(forKey: id)
    scheduleRender()
  }

  func lightChanged() { scheduleRender() }

  /// The preview, ~60 ms after the last movement of a slider.
  private func scheduleRender() {
    renderTask?.cancel()
    let snapshot = lights
    renderTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 60_000_000)
      guard !Task.isCancelled else { return }
      let size = Self.previewSize
      let pixels = await Task.detached(priority: .userInitiated) {
        SphereRenderer.render(width: size, height: size, lights: snapshot, shadowSampleCount: 10)
      }.value
      guard !Task.isCancelled else { return }
      self?.previewImage = SphereRenderer.nsImage(fromRGB8: pixels, width: size, height: size)
    }
  }

  private func persist() {
    store.save(SLRSession(lights: lights, expanded: expanded, overcast: overcast, saveToDesktop: saveToDesktop))
  }
}
```

**`Plugins/SphereLight/Sources/SphereLight/SphereLightPlugin.swift`** (file nuovo o riscritto per intero):

```swift
import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class SphereLightPlugin: DTHubPlugin {
  /// Its tab is grey on the other families: the sun-direction LoRA is made for FLUX.2 Klein 9B.
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.spherelight", name: "Sphere Light", version: "1.0", symbol: "lightbulb.max",
    families: ["flux2_9b"])
  private let state = SLRState()
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: SphereLightView(state: state, send: { [weak self] kind in self?.send(kind) }))
  }

  func start(host: DTHubHost) {
    self.host = host
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      if let context = try? JSONDecoder().decode(DTHubContext.self, from: message) { state.tempFolder = context.tempFolder }
      return nil
    case "activate":
      state.active = true
      // The app only listens to a plug-in that is on: the presets are offered now. A name the menu has is never touched.
      _ = await host?.registerPresets(SLRMessages.presets())
      return nil
    case "deactivate":
      state.active = false
      return nil
    default:
      return DTHubMessage.bare("unsupported")
    }
  }

  private func send(_ kind: SphereSender.Kind) {
    guard !state.isSending, let host else { return }
    state.isSending = true
    state.status = L.text(.rendering)
    let sender = SphereSender(
      contribute: { await host.contribute($0) }, registerPresets: { await host.registerPresets($0) })
    let (lights, overcast, saveToDesktop, folder) = (state.lights, state.overcast, state.saveToDesktop, state.tempFolder)
    Task {
      state.status = await sender.send(kind, lights: lights, overcast: overcast, saveToDesktop: saveToDesktop, tempFolder: folder)
      state.isSending = false
    }
  }
}

@objc(SphereLightEntry)
public final class SphereLightEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { SphereLightPlugin() }
}
```

**`Plugins/SphereLight/Sources/SphereLight/SphereLightView.swift`** (file nuovo o riscritto per intero):

```swift
import SwiftUI

/// The tab: the lights on the left, the sphere and the two buttons on the right.
struct SphereLightView: View {
  @ObservedObject var state: SLRState
  let send: (SphereSender.Kind) -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      lights.frame(width: 290)
      preview.frame(maxWidth: .infinity)
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var lights: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(L.text(.lights)).font(.title3.weight(.semibold))
      ScrollView {
        VStack(spacing: 14) {
          ForEach($state.lights) { $light in
            let index = state.lights.firstIndex(where: { $0.id == light.id }) ?? 0
            LightControlView(
              light: $light, index: index,
              isExpanded: Binding(
                get: { state.expanded[light.id, default: true] }, set: { state.expanded[light.id] = $0 }),
              canRemove: state.lights.count > 1, onRemove: { state.removeLight(light.id) },
              onChange: { state.lightChanged() })
            if index < state.lights.count - 1 { Divider() }
          }
        }
      }
      if state.canAddLight {
        Button { state.addLight() } label: { Label(L.text(.addLight), systemImage: "plus") }
      }
    }
  }

  private var preview: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L.text(.preview)).font(.title3.weight(.semibold))
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06))
        if let image = state.previewImage {
          Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(6)
        } else {
          ProgressView()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .aspectRatio(1, contentMode: .fit)

      Toggle(L.text(.overcast), isOn: $state.overcast).toggleStyle(.checkbox)
      Toggle(L.text(.saveDesktop), isOn: $state.saveToDesktop).toggleStyle(.checkbox)
      HStack {
        Button { send(.pipeline) } label: {
          if state.isSending { ProgressView().controlSize(.small) } else { Text(L.text(.sendPipeline)) }
        }
        .buttonStyle(.borderedProminent)
        .disabled(state.isSending || !state.active)
        Button(L.text(.sendMoodboard)) { send(.moodboard) }
          .disabled(state.isSending || !state.active)
      }
      if !state.status.isEmpty {
        Text(state.status).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
  }
}
```

- [ ] **Step 2: Compilare, provare e fare il bundle**

Run: `cd "<repo>/Plugins/SphereLight" && chmod +x Scripts/build.sh && swift build 2>&1 | tail -2 && swift test 2>&1 | grep -E "Test run|error:|issue" && rm -rf /tmp/slr-bundles && Scripts/build.sh /tmp/slr-bundles | tail -1`
Expected: `Build complete!`, `Test run with 30 tests in 4 suites passed` (la colla non ha test nuovi) e `/tmp/slr-bundles/SphereLight.dthubplugin`.

Run: `plutil -p /tmp/slr-bundles/SphereLight.dthubplugin/Contents/Info.plist | grep -E "Identifier|PrincipalClass|Contract" && nm -gU /tmp/slr-bundles/SphereLight.dthubplugin/Contents/MacOS/SphereLight | grep -c "SphereLightKit"`
Expected: `com.exiztenz.dthub.spherelight`, `SphereLightEntry`, `DTHubContract => 1` e un numero maggiore di 0 (il kit ha il nome `SphereLightKit`).

- [ ] **Step 3: Commit**

```bash
cd "<repo>" && git add Plugins && git commit -m "feat: il tab, il plug-in e lo script per fare il bundle di Sphere Light

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Prova nell'app e documenti

**Files:**
- Create: `Plugins/SphereLight/README.md`
- Modify: `docs/superpowers/specs/2026-10-04-plugin-sphere-light-design.md`, `docs/superpowers/backlog.md`

- [ ] **Step 1: Provare il bundle in un'istanza isolata dell'app vera**

**Prima: l'app dell'utente deve essere chiusa** (`ps aux | grep "[D]T Hub"` vuoto), altrimenti gli strumenti per pilotare le finestre agirebbero sulla sua. Annotare `drawThings.selectedModel` e `workspace.selectedTab` e rimetterli alla fine. Servono: l'app costruita (`build/` di `main` va bene), il server gestito, FLUX.2 klein 9B, il LoRA `flux_2_sun_direction_lora_v1_lora_f16.ckpt` e un'immagine di partenza per il Run (il ritratto di test, 896×1152).

```bash
cd "<repo>"
defaults read com.exiztenz.DTHub drawThings.selectedModel; defaults read com.exiztenz.DTHub workspace.selectedTab   # annotare
Plugins/SphereLight/Scripts/build.sh /tmp/slr-bundles
H=/tmp/slrhome; rm -rf $H; AS="$H/Library/Application Support/DT Hub"; mkdir -p "$AS/Plug-ins"
cp -R /tmp/slr-bundles/SphereLight.dthubplugin "$AS/Plug-ins/com.exiztenz.dthub.spherelight.dthubplugin"
echo '{"enabled":["com.exiztenz.dthub.spherelight"]}' > "$AS/plugins.json"
defaults write com.exiztenz.DTHub drawThings.selectedModel flux_2_klein_9b_f16.ckpt
(CFFIXED_USER_HOME=$H nohup "build/Build/Products/Debug/DT Hub.app/Contents/MacOS/DT Hub" > /tmp/slr-app.log 2>&1 &)
```

Checklist:
1. Dopo l'avvio `$AS/Presets/` contiene `SLR · Match the sun.json` (passi 4, guidance 1, sampler 16, shift 3, il LoRA a 0,6, il prompt «match light direction…») e `SLR · Overcast.json` (senza LoRA); il menu **Preset** li elenca con il solo nome.
2. Il tab «Sphere Light» ha le luci a sinistra (due luci aperte) e la sfera a destra; muovere uno slider aggiorna la sfera; «+» aggiunge la terza luce, «−» ne toglie una; le caselle «Overcast» e «Salva anche sulla Scrivania» ci sono.
3. Con il plug-in acceso dal menu dell'header e Klein scelto: «Invia a Generazione» con Overcast **spento** dà «Run · 1 passaggi» (la dicitura dell'app non distingue il singolare), con Overcast **acceso** «Run · 2 passaggi»; la sfera è nel Moodboard del tab Control. Con un'immagine di partenza, Run: due immagini, la seconda parte dalla prima.
4. «Solo la sfera nel Moodboard» mette la sfera e non cambia prompt né parametri; con «Salva anche sulla Scrivania» accesa compare `Sphere Light 001.png` (poi 002…) sulla Scrivania e la riga di stato lo dice. **Cancellare poi quei file di prova.**
5. Modificare il peso del LoRA in `SLR · Match the sun` dal menu Preset (Salva con lo stesso nome) e rilanciare: vale il nuovo peso; cancellare un preset e premere «Invia a Generazione» lo ricrea.
6. Scegliere un modello di un'altra famiglia: il plug-in è grigio nel menu dell'header. Spento nell'header, i due pulsanti sono disattivati.
7. Chiudere e riaprire l'app: le luci, i colori e le due caselle tornano come erano.

- [ ] **Step 2: Scrivere il README e aggiornare spec e backlog**

```bash
cd "<repo>" && cat > Plugins/SphereLight/README.md <<'EOF'
# Sphere Light Reference (SLR)

Un plug-in di DT Hub: dispone fino a tre luci su una sfera, la calcola (ray tracing su CPU) e la manda a Draw Things per far
combaciare luce, colori e direzione del sole di un'immagine con quelli della sfera. Funziona con FLUX.2 Klein 9B e il LoRA
`flux_2_sun_direction_lora_v1_lora_f16.ckpt`.

- **Invia a Generazione:** la sfera va nel Moodboard e il pulsante Run diventa una pipeline di preset: `SLR · Match the sun`,
  preceduto da `SLR · Overcast` (appiattisce le ombre del canvas) se la casella «Overcast» è accesa.
- **Solo la sfera nel Moodboard:** manda solo l'immagine, per usare prompt e parametri tuoi.
- **I preset** si registrano da soli all'attivazione e stanno nel menu Preset: puoi cambiarli (il peso del LoRA, i passi…) e
  salvarli con lo stesso nome; il plug-in non li sovrascrive mai. Se ne cancelli uno, «Invia a Generazione» lo ricrea.
- **Salva anche sulla Scrivania:** una copia della sfera come `Sphere Light NNN.png`.

## Costruirlo

    Plugins/SphereLight/Scripts/build.sh OUT_FOLDER     # fa OUT_FOLDER/SphereLight.dthubplugin
    cd Plugins/SphereLight && swift test                # 30 test

Poi si aggiunge in DT Hub › Preferenze › Plug-in (si trascina il file) e si accende dal menu Plug-in dell'header.
Il codice del renderer viene dall'app `LightDirectionApp` (copia: l'app standalone non si sviluppa più).
EOF
python3 - <<'PY'
p = 'docs/superpowers/specs/2026-10-04-plugin-sphere-light-design.md'
s = open(p).read()
s = s.replace("Stato: bozza da approvare", "Stato: realizzata")
open(p, 'w').write(s)
p = 'docs/superpowers/backlog.md'
s = open(p).read().rstrip() + """

## Rimandi del plug-in Sphere Light

- **Non è firmato né notarizzato** e non c'è una pagina di download: la distribuzione ad altri è un lavoro a parte.
- **Il LoRA e Klein 9B devono essere installati:** il plug-in non li controlla (se mancano lo dice Draw Things).
- **La colla** (`SLRState`, le viste, `SphereLightPlugin`) non ha test automatici; la logica sta in `SphereSender`, `SLRMessages`, `SLRStore` e `DesktopSaver`.
- **«Run · 1 passaggi»** quando la pipeline ha un solo passaggio: la stringa `header.run.pipeline` dell'app non ha il singolare.
- **L'app standalone `LightDirectionApp`** resta com'è e non si sviluppa più: le correzioni al renderer vanno fatte nel plug-in.
"""
open(p, 'w').write(s + "\n")
PY
git diff --stat | tail -1
```

Expected: statistica su due file.

- [ ] **Step 3: Commit**

```bash
cd "<repo>" && git add Plugins docs && git commit -m "docs: README del plug-in Sphere Light; spec realizzata e rimandi nel backlog

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Fine

Esito atteso sul branch `sphere-light`:
- **30 test verdi** in `Plugins/SphereLight` (nessun test dell'app cambia: 649 + 5 Python); `Scripts/build.sh` fa `SphereLight.dthubplugin`;
- il plug-in si carica, registra i due preset e il tab manda la sfera e la pipeline.

Poi: revisione indipendente, correzioni, prova dell'utente (**lasciare l'app aperta**) e merge.
