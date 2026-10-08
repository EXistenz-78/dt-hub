import Foundation
import Testing

@testable import HubCore

struct ProjectNameTests {
  @Test func aGoodNameIsTrimmed() {
    #expect(ProjectName.validate("  Campagna  ", existing: []) == .success("Campagna"))
  }

  @Test func anEmptyNameIsRefused() {
    #expect(ProjectName.validate("", existing: []) == .failure(.empty))
    #expect(ProjectName.validate("   ", existing: []) == .failure(.empty))
  }

  @Test func slashAndColonAreRefused() {
    #expect(ProjectName.validate("a/b", existing: []) == .failure(.forbiddenCharacter))
    #expect(ProjectName.validate("a:b", existing: []) == .failure(.forbiddenCharacter))
  }

  @Test func aLeadingDotIsRefused() {
    #expect(ProjectName.validate(".nascosto", existing: []) == .failure(.leadingDot))
  }

  @Test func aNameOver120CharactersIsRefused() {
    #expect(ProjectName.validate(String(repeating: "a", count: 120), existing: []) == .success(String(repeating: "a", count: 120)))
    #expect(ProjectName.validate(String(repeating: "a", count: 121), existing: []) == .failure(.tooLong))
  }

  @Test func theShapeOfADateIsRefused() {
    #expect(ProjectName.validate("2026-10-07", existing: []) == .failure(.looksLikeADate))
    #expect(ProjectName.validate("2026-1-7", existing: []) == .success("2026-1-7"))
  }

  @Test func caseAndAccentsAreIgnoredForDuplicates() {
    #expect(ProjectName.validate("CITTA", existing: ["Città"]) == .failure(.alreadyExists))
    #expect(ProjectName.validate("città", existing: ["Città"]) == .failure(.alreadyExists))
    #expect(ProjectName.validate("Campagna", existing: ["Città"]) == .success("Campagna"))
  }

  @Test func aTrimmedNameIsComparedWithoutItsEdges() {
    #expect(ProjectName.validate("  Foto ", existing: ["Foto"]) == .failure(.alreadyExists))
  }
}

struct ProjectPathsTests {
  let project = Project(name: "Campagna", folder: URL(fileURLWithPath: "/tmp/o/Campagna"))

  @Test func theStateLivesInADotFolder() {
    #expect(project.stateFolder.path == "/tmp/o/Campagna/.dthub")
    #expect(project.markerFile.path == "/tmp/o/Campagna/.dthub/project.json")
    #expect(project.markerFile.lastPathComponent == "project.json")
  }

  @Test func controlAndResultsPaths() {
    #expect(project.controlFile.path == "/tmp/o/Campagna/.dthub/control.json")
    #expect(project.controlFolder.lastPathComponent == "Control")
    #expect(project.controlFolder.path == "/tmp/o/Campagna/.dthub/Control")
    #expect(project.resultsFile.lastPathComponent == "results.json")
  }

  @Test func eachPluginHasItsOwnFolder() {
    #expect(project.pluginFolder("com.x.y").path == "/tmp/o/Campagna/.dthub/plugins/com.x.y")
  }

  @Test func theIdIsTheName() {
    #expect(project.id == "Campagna")
  }
}
