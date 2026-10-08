import Foundation
import Observation

/// Where the name of the open project is remembered between launches, and whether the old state has been adopted.
public protocol ProjectSelectionStore: Sendable {
  func currentName() -> String?
  func setCurrentName(_ name: String?)
  /// The state DT Hub kept before projects (Control, the plug-ins' defaults) goes to the first project made, once.
  func hasAdoptedLegacy() -> Bool
  func markLegacyAdopted()
}

/// `UserDefaults`: `project.current` and `project.legacyAdopted`.
public struct DefaultsProjectSelection: ProjectSelectionStore, @unchecked Sendable {
  public static let currentKey = "project.current"
  public static let legacyKey = "project.legacyAdopted"
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func currentName() -> String? { defaults.string(forKey: Self.currentKey) }

  public func setCurrentName(_ name: String?) {
    if let name { defaults.set(name, forKey: Self.currentKey) } else { defaults.removeObject(forKey: Self.currentKey) }
  }

  public func hasAdoptedLegacy() -> Bool { defaults.bool(forKey: Self.legacyKey) }
  public func markLegacyAdopted() { defaults.set(true, forKey: Self.legacyKey) }
}

/// Why a project was opened: the callback brings the rest of the app along.
public enum OpenReason: Equatable, Sendable {
  /// A new project. `adoptsLegacy` is true for the first one ever: Control and the plug-ins take what they had before.
  case created(adoptsLegacy: Bool)
  case reopened
  case launch
}

public enum ProjectManagerError: Error, Equatable, Sendable {
  /// A RUN, its preparation or a pipeline is under way.
  case busy
  case catalog(ProjectCatalogError)
  case notFound
}

/// The open project and the list of projects (spec §5.1). It knows nothing of the app: what has to follow a change of
/// project (Control, the strip of results, the parameters, the plug-ins) is called back, in `onOpen`.
@MainActor
@Observable
public final class ProjectManager {
  public private(set) var current: Project?
  public private(set) var projects: [Project] = []
  public var lastError: ProjectManagerError?

  @ObservationIgnored private let outputFolder: @Sendable () -> URL
  @ObservationIgnored private let selection: any ProjectSelectionStore
  @ObservationIgnored private let legacy: LegacyState
  @ObservationIgnored private let canSwitch: @MainActor () -> Bool
  @ObservationIgnored private let onOpen: @MainActor (Project, OpenReason) async -> Void

  /// `outputFolder` is read at every use: the user can change it. `canSwitch` is false during a RUN.
  public init(
    outputFolder: @escaping @Sendable () -> URL, selection: any ProjectSelectionStore, legacy: LegacyState,
    canSwitch: @escaping @MainActor () -> Bool, onOpen: @escaping @MainActor (Project, OpenReason) async -> Void
  ) {
    self.outputFolder = outputFolder
    self.selection = selection
    self.legacy = legacy
    self.canSwitch = canSwitch
    self.onOpen = onOpen
  }

  private var catalog: ProjectCatalog { ProjectCatalog(outputFolder: outputFolder()) }

  /// At launch: opens the remembered project if it is still there, otherwise there is no current project.
  public func start() async {
    projects = catalog.projects()
    guard let name = selection.currentName(), let project = catalog.project(named: name) else {
      current = nil
      return
    }
    current = project
    await onOpen(project, .launch)
  }

  /// Reads the list again (the menu opens, the output folder changed). A current project that is gone leaves none, and
  /// is forgotten.
  public func refresh() {
    let catalog = catalog
    projects = catalog.projects()
    if let current, catalog.project(named: current.name) == nil {
      self.current = nil
      selection.setCurrentName(nil)
    }
  }

  public func open(_ project: Project) async {
    guard canSwitch() else {
      lastError = .busy
      return
    }
    guard project.name != current?.name else { return }
    lastError = nil
    current = project
    selection.setCurrentName(project.name)
    await onOpen(project, .reopened)
  }

  /// Makes a project and opens it. The first one ever adopts the state of before.
  @discardableResult
  public func create(named name: String) async -> Bool {
    guard canSwitch() else {
      lastError = .busy
      return false
    }
    let catalog = catalog
    let project: Project
    do {
      project = try catalog.create(named: name)
    } catch {
      lastError = .catalog(error)
      return false
    }
    lastError = nil
    let adoptsLegacy = !selection.hasAdoptedLegacy()
    if adoptsLegacy {
      if legacy.exists { _ = try? legacy.adopt(into: project) }
      selection.markLegacyAdopted()
    }
    projects = catalog.projects()
    current = project
    selection.setCurrentName(project.name)
    await onOpen(project, .created(adoptsLegacy: adoptsLegacy))
    return true
  }
}
