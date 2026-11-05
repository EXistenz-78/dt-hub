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

  /// The Draw Things app writes a model's entry in its custom.json only when the import is over, after the file is
  /// already in the models folder: a lookup in that window must not become a permanent "no description".
  @Test func aModelThatJustArrivedIsLookedUpAgainWhenTheAppWritesItsEntry() throws {
    let models = folder.appendingPathComponent("models", isDirectory: true)
    try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
    let ckpt = models.appendingPathComponent("kreamania.ckpt")
    try Data("x".utf8).write(to: ckpt)
    let mine = models.appendingPathComponent("custom.json")
    let app = try write("app.json", #"[{"file":"other.ckpt","name":"Other"}]"#)
    let source = source(app: app, folder: mine)
    #expect(CustomModelFiles.specs(for: ["kreamania.ckpt"], described: [], source: source).isEmpty)
    // The import ends: the app writes the entry.
    try Data(#"[{"file":"kreamania.ckpt","name":"Kreamania"}]"#.utf8).write(to: app)
    #expect(Set(CustomModelFiles.specs(for: ["kreamania.ckpt"], described: [], source: source).keys) == ["kreamania.ckpt"])
  }

  @Test func aSettledModelNobodyDescribesIsNotLookedUpAgain() throws {
    let models = folder.appendingPathComponent("models", isDirectory: true)
    try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
    let ckpt = models.appendingPathComponent("plain.ckpt")
    try Data("x".utf8).write(to: ckpt)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -86_400)], ofItemAtPath: ckpt.path)
    let app = try write("app.json", "[]")
    let source = source(app: app, folder: models.appendingPathComponent("custom.json"))
    #expect(CustomModelFiles.specs(for: ["plain.ckpt"], described: [], source: source).isEmpty)
    try Data(#"[{"file":"plain.ckpt","name":"Plain"}]"#.utf8).write(to: app)
    #expect(CustomModelFiles.specs(for: ["plain.ckpt"], described: [], source: source).isEmpty)
  }

  /// A cache written before the grace period may hold a "looked up, nothing" for a model that has an entry now.
  @Test func anOldCacheDoesNotKeepAModelFromBeingLookedUpAgain() throws {
    let app = try write("app.json", #"[{"file":"kreamania.ckpt","name":"Kreamania"}]"#)
    let source = source(app: app)
    try FileManager.default.createDirectory(at: folder0, withIntermediateDirectories: true)
    try Data(#"{"checked":["kreamania.ckpt"],"models":{}}"#.utf8).write(to: source.cacheFile)
    #expect(Set(CustomModelFiles.specs(for: ["kreamania.ckpt"], described: [], source: source).keys) == ["kreamania.ckpt"])
  }

  @Test func theModelsFoldersFileComesFirst() throws {
    let mine = try write("mine.json", #"[{"file":"kroma.ckpt","name":"mine"}]"#)
    let app = try write("app.json", #"[{"file":"kroma.ckpt","name":"app"}]"#)
    let found = CustomModelFiles.specs(for: ["kroma.ckpt"], described: [], source: source(app: app, folder: mine))
    let name = (try? JSONSerialization.jsonObject(with: try #require(found["kroma.ckpt"])) as? [String: Any])?["name"] as? String
    #expect(name == "mine")
  }
}
