import Foundation
import Testing

@testable import HubCore

struct ProjectCatalogTests {
  private func makeOutput() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func aMissingOutputFolderHasNoProjects() {
    let catalog = ProjectCatalog(
      outputFolder: FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)"))
    #expect(catalog.projects().isEmpty)
  }

  @Test func projectsAreListedByNameWithoutCase() throws {
    let output = try makeOutput()
    defer { try? FileManager.default.removeItem(at: output) }
    let catalog = ProjectCatalog(outputFolder: output)
    _ = try catalog.create(named: "B")
    _ = try catalog.create(named: "a")
    #expect(catalog.projects().map(\.name) == ["a", "B"])
    #expect(catalog.projects().first?.folder.path == output.appendingPathComponent("a").path)
  }

  @Test func dateFoldersAndFoldersWithoutAMarkerAreNotProjects() throws {
    let output = try makeOutput()
    defer { try? FileManager.default.removeItem(at: output) }
    for name in ["2026-10-07", "Foto"] {
      try FileManager.default.createDirectory(at: output.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    let catalog = ProjectCatalog(outputFolder: output)
    _ = try catalog.create(named: "Vero")
    #expect(catalog.projects().map(\.name) == ["Vero"])
    #expect(catalog.project(named: "Foto") == nil)
    #expect(catalog.project(named: "Vero")?.name == "Vero")
  }

  @Test func theSameNameTwiceIsRefused() throws {
    let output = try makeOutput()
    defer { try? FileManager.default.removeItem(at: output) }
    let catalog = ProjectCatalog(outputFolder: output)
    _ = try catalog.create(named: "a")
    #expect(throws: ProjectCatalogError.invalidName(.alreadyExists)) { try catalog.create(named: "a") }
    #expect(throws: ProjectCatalogError.invalidName(.alreadyExists)) { try catalog.create(named: "A") }
  }

  @Test func anInvalidNameIsRefusedBeforeAnythingIsWritten() throws {
    let output = try makeOutput()
    defer { try? FileManager.default.removeItem(at: output) }
    let catalog = ProjectCatalog(outputFolder: output)
    #expect(throws: ProjectCatalogError.invalidName(.forbiddenCharacter)) { try catalog.create(named: "x/y") }
    #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
  }

  @Test func theMarkerHasTheSchemaAndADate() throws {
    let output = try makeOutput()
    defer { try? FileManager.default.removeItem(at: output) }
    let project = try ProjectCatalog(outputFolder: output).create(named: "Campagna")
    let data = try Data(contentsOf: project.markerFile)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["schema"] as? Int == 1)
    let created = try #require(object["created"] as? String)
    #expect(ISO8601DateFormatter().date(from: created) != nil)
    var isFolder: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: project.controlFolder.path, isDirectory: &isFolder) && isFolder.boolValue)
  }

  @Test func existingFoldersCountAsUsedNames() throws {
    let output = try makeOutput()
    defer { try? FileManager.default.removeItem(at: output) }
    try FileManager.default.createDirectory(at: output.appendingPathComponent("2026-10-07"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output.appendingPathComponent("Foto"), withIntermediateDirectories: true)
    let catalog = ProjectCatalog(outputFolder: output)
    #expect(throws: ProjectCatalogError.invalidName(.looksLikeADate)) { try catalog.create(named: "2026-10-07") }
    #expect(throws: ProjectCatalogError.invalidName(.alreadyExists)) { try catalog.create(named: "Foto") }
    #expect(throws: ProjectCatalogError.invalidName(.alreadyExists)) { try catalog.create(named: "foto") }
  }

  @Test func aProjectCanBeCreatedInAMissingOutputFolder() throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("new-\(UUID().uuidString)/out")
    defer { try? FileManager.default.removeItem(at: output.deletingLastPathComponent()) }
    let project = try ProjectCatalog(outputFolder: output).create(named: "A")
    #expect(FileManager.default.fileExists(atPath: project.markerFile.path))
  }

  @Test func aFolderThatCannotBeWrittenIsAnErrorWithTheReason() throws {
    let output = try makeOutput()
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: output.path)
      try? FileManager.default.removeItem(at: output)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: output.path)
    do {
      _ = try ProjectCatalog(outputFolder: output).create(named: "A")
      Issue.record("expected cannotWrite")
    } catch {
      guard case .cannotWrite(let reason) = error else {
        Issue.record("expected cannotWrite, got \(error)")
        return
      }
      #expect(!reason.isEmpty)
    }
  }
}
