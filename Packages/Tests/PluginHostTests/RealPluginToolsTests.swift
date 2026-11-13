import AppKit
import CoreGraphics
import Foundation
import HubCore
import HubKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import PluginHost

/// Loads a REAL built plug-in bundle and calls its tools through the real message channel. Skipped unless the environment names
/// a bundle: `DTHUB_TU_BUNDLE=/path/TiledUpscale.dthubplugin swift test --filter RealPluginToolsTests` (the bundle comes from
/// `Plugins/TiledUpscale/Scripts/build.sh`).
@MainActor
struct RealPluginToolsTests {
  nonisolated static let bundlePath = ProcessInfo.processInfo.environment["DTHUB_TU_BUNDLE"]

  func call(_ plugin: any LoadedPlugin, _ tool: String, _ arguments: [String: Any] = [:]) async throws -> [String: Any] {
    let body = try JSONSerialization.data(withJSONObject: ["type": "tool.call", "tool": tool, "arguments": arguments])
    let answer = try #require(await plugin.send(body))
    return try #require(try JSONSerialization.jsonObject(with: answer) as? [String: Any])
  }

  @Test(.enabled(if: RealPluginToolsTests.bundlePath != nil))
  func theRealTiledUpscaleBundleAnswersItsTools() async throws {
    let bundle = URL(fileURLWithPath: try #require(Self.bundlePath))
    let host = RecordingHost()
    let plugin = try BundlePluginLoader().load(bundle, info: try PluginBundleReader.read(bundle), host: host)
    #expect(plugin.manifest.id == "com.exiztenz.dthub.tiledupscale")
    let tools = try #require(plugin.manifest.tools)
    #expect(tools.map(\.name) == ["get_status", "get_options", "prepare_upscale", "upscale"])
    #expect(tools.map(\.level.rawValue) == ["read", "read", "edit", "generate"])
    #expect(tools.last?.parameters.first { $0.name == "image" }?.format == "image")
    #expect(tools.allSatisfy { $0.families == ["flux2_9b", "flux3_5b", "qwen_image_2.1"] })

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tu-real-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let context = try JSONSerialization.data(withJSONObject: [
      "type": "context", "model": "flux.ckpt", "family": "flux2_9b", "tempFolder": folder.path,
    ])
    _ = await plugin.send(context)
    _ = await plugin.send(PluginMessageType.bare("activate"))

    let options = try await call(plugin, "get_options")
    #expect(options["type"] as? String == "tool.result" && options["isError"] == nil)
    #expect((options["text"] as? String)?.contains("TUP · FLUX.2 klein 9B") == true)

    // A picture of 1000×1000 → 1984×1984 at 2×: the plug-in prepares and asks the app to run.
    let space = CGColorSpaceCreateDeviceRGB()
    let context2 = try #require(
      CGContext(data: nil, width: 1000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context2.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
    context2.fill(CGRect(x: 0, y: 0, width: 1000, height: 1000))
    let png = folder.appendingPathComponent("p.png")
    let destination = try #require(CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context2.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))

    let ran = try await call(plugin, "upscale", ["image": png.path, "factor": 2])
    #expect(ran["isError"] == nil && ran["startsRun"] as? Bool == true, Comment(rawValue: "\(ran)"))
    let sent = host.received.compactMap { PluginContribution(message: $0.message)?.pipeline }
    let pipeline = try #require(sent.last)
    #expect(pipeline.guided != nil && pipeline.passCount > 1)
    let refused = try await call(plugin, "prepare_upscale", ["factor": 3])
    #expect(refused["isError"] as? Bool == true)
  }

  nonisolated static let batchPlusBundlePath = ProcessInfo.processInfo.environment["DTHUB_BP_BUNDLE"]

  /// `DTHUB_BP_BUNDLE=/path/BatchPlus.dthubplugin swift test --filter RealPluginToolsTests` (from `Plugins/BatchPlus/Scripts/build.sh`).
  @Test(.enabled(if: RealPluginToolsTests.batchPlusBundlePath != nil))
  func theRealBatchPlusBundleAnswersItsTools() async throws {
    let bundle = URL(fileURLWithPath: try #require(Self.batchPlusBundlePath))
    let host = RecordingHost()
    let plugin = try BundlePluginLoader().load(bundle, info: try PluginBundleReader.read(bundle), host: host)
    #expect(plugin.manifest.id == "com.exiztenz.dthub.batchplus")
    let tools = try #require(plugin.manifest.tools)
    #expect(tools.map(\.name) == ["get_status", "set_batch", "start_batch"])
    #expect(tools.map(\.level.rawValue) == ["read", "edit", "generate"])
    #expect(tools.allSatisfy { $0.families == nil })

    let context = try JSONSerialization.data(withJSONObject: [
      "type": "context", "model": "m.ckpt", "tempFolder": NSTemporaryDirectory(),
      "parameters": ["width": 832, "height": 1216, "steps": 8, "guidanceScale": 1.5, "seed": 99, "shift": 3],
    ])
    _ = await plugin.send(context)
    _ = await plugin.send(PluginMessageType.bare("activate"))

    let status = try await call(plugin, "get_status")
    #expect(status["type"] as? String == "tool.result" && status["isError"] == nil)
    let set = try await call(plugin, "set_batch", ["passes": 3, "steps_increment": 4])
    #expect(set["isError"] == nil && set["startsRun"] == nil, Comment(rawValue: "\(set)"))
    let ran = try await call(plugin, "start_batch")
    #expect(ran["isError"] == nil && ran["startsRun"] as? Bool == true, Comment(rawValue: "\(ran)"))
    let sent = host.received.compactMap { PluginContribution(message: $0.message)?.pipeline }
    #expect(try #require(sent.last).passCount == 3)
    let refused = try await call(plugin, "set_batch", ["passes": 99])
    #expect(refused["isError"] as? Bool == true)
  }

  nonisolated static let characterSheetBundlePath = ProcessInfo.processInfo.environment["DTHUB_CS_BUNDLE"]

  /// `DTHUB_CS_BUNDLE=/path/CharacterSheet.dthubplugin swift test --filter RealPluginToolsTests` (from `Plugins/CharacterSheet/Scripts/build.sh`).
  @Test(.enabled(if: RealPluginToolsTests.characterSheetBundlePath != nil))
  func theRealCharacterSheetBundleAnswersItsTools() async throws {
    let bundle = URL(fileURLWithPath: try #require(Self.characterSheetBundlePath))
    let host = RecordingHost()
    let plugin = try BundlePluginLoader().load(bundle, info: try PluginBundleReader.read(bundle), host: host)
    #expect(plugin.manifest.id == "com.exiztenz.dthub.charactersheet")
    let tools = try #require(plugin.manifest.tools)
    #expect(tools.map(\.name) == ["get_status", "prepare_sheet"])
    #expect(tools.map(\.level.rawValue) == ["read", "edit"])
    #expect(tools.last?.parameters.first { $0.name == "image" }?.format == "image")
    #expect(plugin.manifest.families == ["qwen_image_2.1"])

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cs-real-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let context = try JSONSerialization.data(withJSONObject: [
      "type": "context", "model": "qwen.ckpt", "family": "qwen_image_2.1", "tempFolder": folder.path,
    ])
    _ = await plugin.send(context)
    _ = await plugin.send(PluginMessageType.bare("activate"))

    let status = try await call(plugin, "get_status")
    #expect(status["type"] as? String == "tool.result" && status["isError"] == nil, Comment(rawValue: "\(status)"))
    // Not a real preparation: the plug-in keeps its choices in the user's own data folder, which a test must not change.
    let refused = try await call(plugin, "prepare_sheet", ["kind": "bogus"])
    #expect(refused["isError"] as? Bool == true)
  }
}
