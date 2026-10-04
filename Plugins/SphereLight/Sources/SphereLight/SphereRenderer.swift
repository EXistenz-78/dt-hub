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
