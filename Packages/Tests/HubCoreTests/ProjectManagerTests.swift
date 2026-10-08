import Foundation
import Testing

@testable import HubCore

final class MemorySelection: ProjectSelectionStore, @unchecked Sendable {
  var name: String?
  var adopted = false
  func currentName() -> String? { name }
  func setCurrentName(_ name: String?) { self.name = name }
  func hasAdoptedLegacy() -> Bool { adopted }
  func markLegacyAdopted() { adopted = true }
}

/// What `onOpen` was called with, and what the manager said at that moment.
@MainActor
final class OpenLog {
  var calls: [(project: Project, reason: OpenReason, currentWhenCalled: String?)] = []
}

@MainActor
struct ProjectManagerTests {
  struct World {
    let root: URL
    var output: URL { root.appendingPathComponent("out") }
    let selection = MemorySelection()
    let log = OpenLog()
    var busy = false
  }

  private func legacy(_ root: URL, withState: Bool) throws -> LegacyState {
    let old = root.appendingPathComponent("old", isDirectory: true)
    try FileManager.default.createDirectory(at: old.appendingPathComponent("Control"), withIntermediateDirectories: true)
    if withState {
      try Data("{}".utf8).write(to: old.appendingPathComponent("control.json"))
      try Data("png".utf8).write(to: old.appendingPathComponent("Control/a.png"))
    }
    return LegacyState(controlFile: old.appendingPathComponent("control.json"), controlFolder: old.appendingPathComponent("Control"))
  }

  /// A manager on a temporary folder; `busy` flips what `canSwitch` answers.
  private func make(
    legacyState: Bool = true, busy: Box = Box()
  ) throws -> (ProjectManager, World, Box, LegacyState) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pm-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let world = World(root: root)
    let state = try legacy(root, withState: legacyState)
    let output = world.output
    let log = world.log
    var holder: ProjectManager?
    let manager = ProjectManager(
      outputFolder: { output }, selection: world.selection, legacy: state, canSwitch: { !busy.value },
      onOpen: { project, reason in log.calls.append((project, reason, holder?.current?.name)) })
    holder = manager
    return (manager, world, busy, state)
  }

  final class Box: @unchecked Sendable { var value = false }

  @Test func theManagerSaysWhenStartIsDone() async throws {
    let (manager, _, _, _) = try make()
    #expect(!manager.didStart)
    await manager.start()
    #expect(manager.didStart)
  }

  @Test func startWithoutARememberedProjectHasNoCurrent() async throws {
    let (manager, world, _, _) = try make()
    await manager.start()
    #expect(manager.current == nil)
    #expect(world.log.calls.isEmpty)
  }

  @Test func startOpensTheRememberedProjectOnce() async throws {
    let (manager, world, _, _) = try make()
    _ = try ProjectCatalog(outputFolder: world.output).create(named: "A")
    world.selection.name = "A"
    await manager.start()
    #expect(manager.current?.name == "A")
    #expect(world.log.calls.count == 1)
    #expect(world.log.calls.first?.reason == .launch)
    #expect(manager.projects.map(\.name) == ["A"])
  }

  @Test func aRememberedFolderWithoutTheMarkerIsNoProject() async throws {
    let (manager, world, _, _) = try make()
    try FileManager.default.createDirectory(at: world.output.appendingPathComponent("A"), withIntermediateDirectories: true)
    world.selection.name = "A"
    await manager.start()
    #expect(manager.current == nil)
    #expect(world.log.calls.isEmpty)
  }

  @Test func theFirstProjectAdoptsTheOldStateAndTellsThePlugIns() async throws {
    let (manager, world, _, state) = try make()
    #expect(await manager.create(named: "A"))
    #expect(world.log.calls.count == 1)
    #expect(world.log.calls.first?.reason == .created(adoptsLegacy: true))
    #expect(FileManager.default.fileExists(atPath: world.output.appendingPathComponent("A/.dthub/control.json").path))
    #expect(!state.exists)
    #expect(manager.current?.name == "A")
  }

  @Test func theSecondProjectAdoptsNothing() async throws {
    let (manager, world, _, _) = try make()
    _ = await manager.create(named: "A")
    _ = await manager.create(named: "B")
    #expect(world.log.calls.map(\.reason) == [.created(adoptsLegacy: true), .created(adoptsLegacy: false)])
    #expect(!FileManager.default.fileExists(atPath: world.output.appendingPathComponent("B/.dthub/control.json").path))
  }

  @Test func theOldStateIsAdoptedOnlyOnceEvenIfEveryProjectGoesAway() async throws {
    let (manager, world, _, _) = try make(legacyState: false)
    _ = await manager.create(named: "A")
    try FileManager.default.removeItem(at: world.output.appendingPathComponent("A"))
    manager.refresh()
    _ = await manager.create(named: "B")
    #expect(world.log.calls.map(\.reason) == [.created(adoptsLegacy: true), .created(adoptsLegacy: false)])
  }

  @Test func aFirstProjectWithoutOldControlStateStillTellsThePlugIns() async throws {
    let (manager, world, _, _) = try make(legacyState: false)
    _ = await manager.create(named: "A")
    #expect(world.log.calls.first?.reason == .created(adoptsLegacy: true))
  }

  @Test func anInvalidNameIsReportedAndNothingOpens() async throws {
    let (manager, world, _, _) = try make()
    _ = await manager.create(named: "A")
    let ok = await manager.create(named: "a")
    #expect(!ok)
    #expect(manager.lastError == .catalog(.invalidName(.alreadyExists)))
    #expect(world.log.calls.count == 1)
    #expect(manager.current?.name == "A")
  }

  @Test func nothingChangesWhileARunIsGoingOn() async throws {
    let busy = Box()
    let (manager, world, _, _) = try make(busy: busy)
    _ = await manager.create(named: "A")
    let a = try #require(manager.current)
    _ = await manager.create(named: "B")
    busy.value = true
    await manager.open(a)
    #expect(manager.lastError == .busy)
    #expect(manager.current?.name == "B")
    #expect(world.log.calls.count == 2)
    #expect(world.selection.name == "B")
    let created = await manager.create(named: "C")
    #expect(!created)
    #expect(manager.lastError == .busy)
    #expect(ProjectCatalog(outputFolder: world.output).project(named: "C") == nil)
  }

  @Test func openingRemembersTheProjectAndClearsTheError() async throws {
    let (manager, world, _, _) = try make()
    _ = await manager.create(named: "A")
    let a = try #require(manager.current)
    _ = await manager.create(named: "B")
    manager.lastError = .notFound
    await manager.open(a)
    #expect(manager.current?.name == "A")
    #expect(world.selection.name == "A")
    #expect(manager.lastError == nil)
    #expect(world.log.calls.last?.reason == .reopened)
  }

  @Test func openingTheCurrentProjectDoesNothing() async throws {
    let (manager, world, _, _) = try make()
    _ = await manager.create(named: "A")
    let a = try #require(manager.current)
    await manager.open(a)
    #expect(world.log.calls.count == 1)
  }

  @Test func theManagerIsAlreadyOnTheProjectWhenTheCallbackRuns() async throws {
    let (manager, world, _, _) = try make()
    _ = await manager.create(named: "A")
    #expect(world.log.calls.first?.currentWhenCalled == "A")
    #expect(world.selection.name == "A")
  }

  @Test func aProjectDeletedFromTheFinderLeavesNoCurrent() async throws {
    let (manager, world, _, _) = try make()
    _ = await manager.create(named: "A")
    try FileManager.default.removeItem(at: world.output.appendingPathComponent("A"))
    manager.refresh()
    #expect(manager.current == nil)
    #expect(manager.projects.isEmpty)
    #expect(world.selection.name == nil)
  }

  @Test func refreshSeesProjectsMadeOutsideTheApp() async throws {
    let (manager, world, _, _) = try make()
    _ = try ProjectCatalog(outputFolder: world.output).create(named: "Fuori")
    manager.refresh()
    #expect(manager.projects.map(\.name) == ["Fuori"])
  }

  @Test func theListFollowsCreation() async throws {
    let (manager, _, _, _) = try make()
    _ = await manager.create(named: "B")
    _ = await manager.create(named: "a")
    #expect(manager.projects.map(\.name) == ["a", "B"])
  }

  final class FolderBox: @unchecked Sendable { var url: URL; init(_ url: URL) { self.url = url } }

  @Test func aChangedOutputFolderLeavesNoCurrentEvenIfTheNewOneHasThatName() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pm-\(UUID().uuidString)")
    let (first, second) = (root.appendingPathComponent("one"), root.appendingPathComponent("two"))
    _ = try ProjectCatalog(outputFolder: second).create(named: "A")
    let box = FolderBox(first)
    let selection = MemorySelection()
    let manager = ProjectManager(
      outputFolder: { box.url }, selection: selection,
      legacy: LegacyState(controlFile: root.appendingPathComponent("c.json"), controlFolder: root.appendingPathComponent("C")),
      canSwitch: { true }, onOpen: { _, _ in })
    #expect(await manager.create(named: "A"))
    box.url = second
    manager.refresh()
    #expect(manager.current == nil)
    #expect(manager.projects.map(\.name) == ["A"])
    #expect(selection.name == nil)
  }
}
