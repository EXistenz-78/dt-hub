import Foundation
import Testing

@testable import DTBridge

struct CustomModelFilesTests {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("custom-models-\(UUID().uuidString)", isDirectory: true)

  func write(_ name: String, _ json: String) throws -> URL {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent(name)
    try Data(json.utf8).write(to: url)
    return url
  }

  @Test func eachModelIsKeptByItsFileName() throws {
    let url = try write("a.json", #"[{"file":"kroma.ckpt","name":"Kroma","version":"krea_2"},{"name":"no file"},{"file":""}]"#)
    let specs = CustomModelFiles.specs(in: [url])
    #expect(Array(specs.keys) == ["kroma.ckpt"])
    let json = try #require(specs["kroma.ckpt"].flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    #expect(json["version"] as? String == "krea_2" && json["name"] as? String == "Kroma")
  }

  @Test func theFirstFileWinsAndAMissingOrBrokenOneIsSkipped() throws {
    let first = try write("first.json", #"[{"file":"m.ckpt","name":"first"}]"#)
    let second = try write("second.json", #"[{"file":"m.ckpt","name":"second"},{"file":"n.ckpt","name":"n"}]"#)
    let broken = try write("broken.json", "not json")
    let missing = folder.appendingPathComponent("missing.json")
    let specs = CustomModelFiles.specs(in: [missing, broken, first, second])
    #expect(Set(specs.keys) == ["m.ckpt", "n.ckpt"])
    let name = (try? JSONSerialization.jsonObject(with: try #require(specs["m.ckpt"])) as? [String: Any])?["name"] as? String
    #expect(name == "first")
  }

  func source(app: URL, folder: URL? = nil) -> CustomModelSource {
    CustomModelSource(folderFile: folder, appFile: app, cacheFile: folder0.appendingPathComponent("cache.json"))
  }
  var folder0: URL { folder.appendingPathComponent("support", isDirectory: true) }

  @Test func theAppsFileIsReadOnlyForAFileNothingDescribesAndWhatItSaidIsKept() throws {
    let app = try write("app.json", #"[{"file":"kroma.ckpt","name":"Kroma"},{"file":"other.ckpt","name":"Other"}]"#)
    let source = source(app: app)
    let first = CustomModelFiles.specs(for: ["kroma.ckpt", "lora.ckpt"], described: [], source: source)
    #expect(Set(first.keys) == ["kroma.ckpt"])
    // The app's file is gone (or macOS says no): the cache answers, and nothing is looked up again.
    try FileManager.default.removeItem(at: app)
    let second = CustomModelFiles.specs(for: ["kroma.ckpt", "lora.ckpt"], described: [], source: source)
    #expect(Set(second.keys) == ["kroma.ckpt"])
  }

  @Test func nothingIsReadWhenEverythingIsDescribed() throws {
    let app = try write("app.json", #"[{"file":"kroma.ckpt"}]"#)
    let source = source(app: app)
    #expect(CustomModelFiles.specs(for: ["kroma.ckpt"], described: ["kroma.ckpt"], source: source).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: source.cacheFile.path))
  }

  @Test func anUnreadableAppFileMarksNothingAsLookedUp() throws {
    let missing = folder.appendingPathComponent("missing.json")
    let source = source(app: missing)
    #expect(CustomModelFiles.specs(for: ["kroma.ckpt"], described: [], source: source).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: source.cacheFile.path))
    // Allowed later: the file is read then.
    _ = try write("missing.json", #"[{"file":"kroma.ckpt","name":"Kroma"}]"#)
    #expect(Set(CustomModelFiles.specs(for: ["kroma.ckpt"], described: [], source: source).keys) == ["kroma.ckpt"])
  }

  @Test func theModelsFoldersFileComesFirst() throws {
    let mine = try write("mine.json", #"[{"file":"kroma.ckpt","name":"mine"}]"#)
    let app = try write("app.json", #"[{"file":"kroma.ckpt","name":"app"}]"#)
    let found = CustomModelFiles.specs(for: ["kroma.ckpt"], described: [], source: source(app: app, folder: mine))
    let name = (try? JSONSerialization.jsonObject(with: try #require(found["kroma.ckpt"])) as? [String: Any])?["name"] as? String
    #expect(name == "mine")
  }
}
