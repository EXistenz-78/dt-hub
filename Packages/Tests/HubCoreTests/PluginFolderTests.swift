import Foundation
import HubKit
import Testing

@testable import HubCore

/// Fake `.dthubplugin` bundles on disk: an `Info.plist` and nothing else.
enum PluginFixture {
  static func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("PluginFolderTests-\(UUID())", isDirectory: true)
  }

  @discardableResult
  static func bundle(
    in folder: URL, id: String = "com.example.p", name: String = "P", version: String = "1.0", contract: Any? = 1,
    principal: String? = "PEntry", folderName: String? = nil
  ) throws -> URL {
    let url = folder.appendingPathComponent(folderName ?? "\(id).dthubplugin", isDirectory: true)
    try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    var plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleShortVersionString": version]
    if let principal { plist["NSPrincipalClass"] = principal }
    if let contract { plist[PluginContract.infoKey] = contract }
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      .write(to: url.appendingPathComponent("Contents/Info.plist"))
    return url
  }
}

struct PluginBundleReaderTests {
  @Test func aGoodBundleIsRead() throws {
    let url = try PluginFixture.bundle(in: PluginFixture.folder(), version: "2.1")
    let info = try PluginBundleReader.read(url)
    #expect(info == PluginBundleInfo(identifier: "com.example.p", name: "P", version: "2.1", contract: 1, principalClass: "PEntry"))
  }

  @Test func theContractMayBeATextInThePlist() throws {
    let url = try PluginFixture.bundle(in: PluginFixture.folder(), contract: "1")
    #expect(try PluginBundleReader.read(url).contract == 1)
  }

  @Test func aMissingPlistIsUnreadable() {
    #expect(throws: PluginError.unreadable) { try PluginBundleReader.read(PluginFixture.folder()) }
  }

  @Test func eachRequiredKeyIsChecked() throws {
    let folder = PluginFixture.folder()
    let noClass = try PluginFixture.bundle(in: folder, id: "a", principal: nil)
    #expect(throws: PluginError.missingKey("NSPrincipalClass")) { try PluginBundleReader.read(noClass) }
    let noContract = try PluginFixture.bundle(in: folder, id: "b", contract: nil)
    #expect(throws: PluginError.missingKey("DTHubContract")) { try PluginBundleReader.read(noContract) }
    let emptyName = try PluginFixture.bundle(in: folder, id: "c", name: "  ")
    #expect(throws: PluginError.missingKey("CFBundleName")) { try PluginBundleReader.read(emptyName) }
  }

  @Test func anIdentifierThatIsNotAPlainNameIsRefused() throws {
    let folder = PluginFixture.folder()
    for bad in ["../../X", "a/b", ".hidden", "with space", "tab\t"] {
      let url = try PluginFixture.bundle(in: folder, id: bad, folderName: "bundle-\(UUID()).dthubplugin")
      #expect(throws: PluginError.invalidIdentifier(bad)) { try PluginBundleReader.read(url) }
    }
    let good = try PluginFixture.bundle(in: folder, id: "com.example.My-Plug_in2", folderName: "good.dthubplugin")
    #expect(try PluginBundleReader.read(good).identifier == "com.example.My-Plug_in2")
  }

  @Test func aContractThisAppDoesNotKnowIsRefused() throws {
    let url = try PluginFixture.bundle(in: PluginFixture.folder(), contract: 7)
    #expect(throws: PluginError.contractNotSupported(7)) { try PluginBundleReader.read(url) }
  }
}

struct PluginFolderTests {
  @Test func scanListsGoodAndBrokenBundlesAndIgnoresOtherFiles() throws {
    let root = PluginFixture.folder()
    try PluginFixture.bundle(in: root, id: "com.example.good")
    try PluginFixture.bundle(in: root, id: "com.example.old", contract: 9)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("junk.dthubplugin"), withIntermediateDirectories: true)
    try Data().write(to: root.appendingPathComponent("notes.txt"))
    let slots = PluginFolder(root: root).scan()
    #expect(slots.count == 3)
    #expect(slots.first { $0.identifier == "com.example.good" }?.info?.name == "P")
    #expect(slots.first { $0.identifier == "com.example.old" }?.error == .contractNotSupported(9))
    #expect(slots.first { $0.identifier == "junk" }?.error == .unreadable)
  }

  @Test func aMissingFolderHoldsNothing() {
    #expect(PluginFolder(root: PluginFixture.folder()).scan().isEmpty)
  }

  @Test func oneIdentifierAppearsOnce() throws {
    let root = PluginFixture.folder()
    try PluginFixture.bundle(in: root, id: "com.example.p", folderName: "a.dthubplugin")
    try PluginFixture.bundle(in: root, id: "com.example.p", folderName: "b.dthubplugin")
    let slots = PluginFolder(root: root).scan()
    #expect(slots.count == 2)
    #expect(slots.filter { $0.info != nil }.count == 1)
    #expect(slots.first { $0.url.lastPathComponent == "b.dthubplugin" }?.error == .unreadable)
  }

  @Test func installingCopiesTheBundleUnderItsIdentifier() throws {
    let source = try PluginFixture.bundle(in: PluginFixture.folder(), id: "com.example.p")
    let root = PluginFixture.folder()
    let folder = PluginFolder(root: root)
    try folder.install(source, info: PluginBundleReader.read(source))
    #expect(FileManager.default.fileExists(atPath: folder.location(of: "com.example.p").appendingPathComponent("Contents/Info.plist").path))
    #expect(folder.installed("com.example.p")?.version == "1.0")
    #expect(FileManager.default.fileExists(atPath: source.path), "the original is left where it was")
  }

  @Test func aHigherVersionReplacesAndTheSameOrALowerOneIsRefused() throws {
    let root = PluginFixture.folder()
    let folder = PluginFolder(root: root)
    let one = try PluginFixture.bundle(in: PluginFixture.folder(), version: "1.0")
    try folder.install(one, info: PluginBundleReader.read(one))
    let two = try PluginFixture.bundle(in: PluginFixture.folder(), version: "1.1")
    try folder.install(two, info: PluginBundleReader.read(two))
    #expect(folder.installed("com.example.p")?.version == "1.1")
    #expect(throws: PluginError.notNewer(installed: "1.1")) { try folder.install(two, info: PluginBundleReader.read(two)) }
    #expect(throws: PluginError.notNewer(installed: "1.1")) { try folder.install(one, info: PluginBundleReader.read(one)) }
    #expect(folder.installed("com.example.p")?.version == "1.1")
    #expect(folder.scan().count == 1, "no staging folder is left behind")
  }

  @Test func aFailedInstallLeavesNoStagingAndKeepsTheOldVersion() throws {
    let root = PluginFixture.folder()
    let folder = PluginFolder(root: root)
    let one = try PluginFixture.bundle(in: PluginFixture.folder(), version: "1.0")
    try folder.install(one, info: PluginBundleReader.read(one))
    // A newer bundle with a file nobody can read: the copy fails halfway.
    let two = try PluginFixture.bundle(in: PluginFixture.folder(), version: "1.1")
    let locked = two.appendingPathComponent("Contents/Resources/locked.bin")
    try FileManager.default.createDirectory(at: locked.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: locked)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
    #expect(throws: PluginError.self) { try folder.install(two, info: PluginBundleReader.read(two)) }
    let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
    #expect(names == ["com.example.p.dthubplugin"], "nothing else is left, hidden folders included")
    #expect(folder.installed("com.example.p")?.version == "1.0")
  }

  @Test func anUpdateReplacesTheBundleEvenWhenItSitsUnderAnotherFolderName() throws {
    let root = PluginFixture.folder()
    try PluginFixture.bundle(in: root, id: "com.example.p", version: "1.0", folderName: "Sample.dthubplugin")
    let folder = PluginFolder(root: root)
    let newer = try PluginFixture.bundle(in: PluginFixture.folder(), version: "1.1")
    try folder.install(newer, info: PluginBundleReader.read(newer))
    let slots = folder.scan()
    #expect(slots.count == 1 && slots.first?.info?.version == "1.1")
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Sample.dthubplugin").path))
  }

  @Test func removingTakesTheFolderAway() throws {
    let root = PluginFixture.folder()
    let folder = PluginFolder(root: root)
    let source = try PluginFixture.bundle(in: PluginFixture.folder())
    try folder.install(source, info: PluginBundleReader.read(source))
    try folder.remove("com.example.p")
    #expect(folder.scan().isEmpty)
  }

  @Test func theDownloadQuarantineMarkIsTakenOffTheCopy() throws {
    let source = try PluginFixture.bundle(in: PluginFixture.folder())
    let plist = source.appendingPathComponent("Contents/Info.plist")
    let value = "0081;00000000;Safari;"
    #expect(setxattr(source.path, "com.apple.quarantine", value, value.utf8.count, 0, 0) == 0)
    #expect(setxattr(plist.path, "com.apple.quarantine", value, value.utf8.count, 0, 0) == 0)
    let folder = PluginFolder(root: PluginFixture.folder())
    try folder.install(source, info: PluginBundleReader.read(source))
    let copy = folder.location(of: "com.example.p")
    #expect(getxattr(copy.path, "com.apple.quarantine", nil, 0, 0, 0) < 0)
    #expect(getxattr(copy.appendingPathComponent("Contents/Info.plist").path, "com.apple.quarantine", nil, 0, 0, 0) < 0)
  }
}

struct PluginSettingsTests {
  @Test func nothingIsOnUntilTheUserTurnsItOn() {
    let file = PluginFixture.folder().appendingPathComponent("plugins.json")
    let store = PluginSettingsStore(fileURL: file)
    #expect(store.enabled().isEmpty)
    store.save(["b", "a"])
    #expect(PluginSettingsStore(fileURL: file).enabled() == ["a", "b"])
    try? Data("nonsense".utf8).write(to: file)
    #expect(store.enabled().isEmpty, "an unreadable file means nothing is on")
  }
}
