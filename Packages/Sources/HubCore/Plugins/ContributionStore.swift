import Foundation
import HubKit
import Observation

/// A field a plug-in filled: teal while the field still holds the plug-in's value; once the user changes it
/// the teal goes and the plug-in's value stays for reference (plug-in design §7).
public struct FieldMark: Equatable, Sendable {
  public let pluginID: String
  /// What the plug-in sent, already limited as the card limits it.
  public let value: FieldValue
  public var isOverridden: Bool
}

/// The pipeline a plug-in proposed, shown on the Run button.
public struct PipelineContribution: Equatable, Sendable {
  /// Who the pipeline comes from: a plug-in, or the user's own (by the name of its file).
  public enum Source: Equatable, Sendable {
    case plugin(String)
    case user(String)
  }

  public let source: Source
  public let pipeline: PluginPipeline

  public init(pluginID: String, pipeline: PluginPipeline) {
    source = .plugin(pluginID)
    self.pipeline = pipeline
  }

  public init(userPipeline name: String, pipeline: PluginPipeline) {
    source = .user(name)
    self.pipeline = pipeline
  }

  /// Nil for a pipeline of the user.
  public var pluginID: String? {
    if case .plugin(let id) = source { id } else { nil }
  }

  /// Nil for a pipeline of a plug-in.
  public var userPipelineName: String? {
    if case .user(let name) = source { name } else { nil }
  }
}

/// Two plug-ins want the same thing: the user picks one in a pop-up (the only conflict there is).
public struct ContributionConflict: Identifiable, Equatable, Sendable {
  public enum Subject: Equatable, Sendable {
    case field(ContributionField)
    case startImage
    case pipeline
  }

  public enum Content: Equatable, Sendable {
    case value(FieldValue)
    /// The name of a picture.
    case image(String)
    /// The number of passes of a pipeline.
    case passes(Int)
  }

  public struct Side: Equatable, Sendable {
    public let pluginID: String
    public let content: Content
  }

  public let id = UUID()
  public let subject: Subject
  /// What the tab has now, from another plug-in.
  public let current: Side
  /// What the plug-in that is writing now wants.
  public let proposed: Side
  let payload: Payload

  enum Payload: Equatable, Sendable {
    case field(ContributionField, FieldValue)
    case startImage(PluginImageRef)
    case pipeline(PluginPipeline)
  }
}

/// What the store needs from the tab: the fields, the LoRA list, the Control tab's pictures.
@MainActor
public protocol ContributionTarget: AnyObject {
  var fields: GenerationFields { get set }
  var loraFiles: Set<String> { get }
  /// Adds the LoRA, or gives the one with the same file the new weight, mode and trigger.
  func addLoRA(_ lora: LoRASelection)
  var moodboardIDs: Set<UUID> { get }
  var startImageID: UUID? { get }
  func addMoodboardImage(_ image: PluginImageRef, from pluginID: String) throws -> UUID
  func removeMoodboardImage(_ id: UUID)
  func setStartImage(_ image: PluginImageRef, from pluginID: String) throws -> UUID
  /// The strength the start image is used with (0…1).
  func setStrength(_ value: Double)
  /// The drawing a plug-in made, as the Brush layer of the Control tab (it replaces the one there).
  func setPaint(_ image: PluginImageRef) throws
}

/// Remembers what each plug-in contributed, so the tab can show it (teal, the value in brackets) and so a
/// second plug-in writing the same field can be told apart (plug-in design §7). Plug-ins never block
/// anything: a field is always editable, and RUN sends what the fields hold.
@MainActor
@Observable
public final class ContributionStore {
  public private(set) var marks: [ContributionField: FieldMark] = [:]
  /// LoRA file → the plug-in that added it.
  public private(set) var loraPlugins: [String: String] = [:]
  /// Moodboard picture → the plug-in that added it.
  public private(set) var moodboardPlugins: [UUID: String] = [:]
  public private(set) var startImage: (pluginID: String, id: UUID, name: String)?
  public private(set) var pipeline: PipelineContribution?
  /// True while a pipeline runs: no pipeline can be sent to RUN then (a plug-in's is refused).
  @ObservationIgnored public var pipelineLocked = false
  /// Waiting for the user, in order; the pop-up lists them all.
  public private(set) var conflicts: [ContributionConflict] = []

  @ObservationIgnored public weak var target: (any ContributionTarget)?

  public init() {}

  /// Takes a contribution. Fields, LoRAs and Moodboard pictures that do not clash go in at once; what clashes
  /// with another plug-in's becomes a conflict. Returns the reasons for what could not be used.
  @discardableResult
  public func receive(_ contribution: PluginContribution, from pluginID: String) -> [String] {
    guard let target else { return ["The app is not ready."] }
    var problems: [String] = []

    var accepted: [ContributionField: FieldValue] = [:]
    for field in contribution.fields.fields {
      guard let value = contribution.fields.values[field] else { continue }
      let limited = Self.limited(value, for: field, in: target.fields)
      if let mark = marks[field], mark.pluginID != pluginID, mark.value != limited {
        addConflict(
          subject: .field(field), current: .init(pluginID: mark.pluginID, content: .value(mark.value)),
          proposed: .init(pluginID: pluginID, content: .value(limited)), payload: .field(field, value))
      } else {
        accepted[field] = value
      }
    }
    if !accepted.isEmpty {
      let applied = FieldOverlay(accepted).applied(to: target.fields)
      target.fields = applied
      for field in accepted.keys {
        marks[field] = FieldMark(pluginID: pluginID, value: applied.value(of: field), isOverridden: false)
      }
    }

    for lora in contribution.loras {
      target.addLoRA(lora)
      loraPlugins[lora.file] = pluginID
    }

    if !contribution.moodboard.isEmpty {
      // A plug-in that sends its pictures again replaces the ones it sent before.
      for (id, owner) in moodboardPlugins where owner == pluginID {
        target.removeMoodboardImage(id)
        moodboardPlugins[id] = nil
      }
      for image in contribution.moodboard {
        do {
          moodboardPlugins[try target.addMoodboardImage(image, from: pluginID)] = pluginID
        } catch {
          problems.append("\(image.name): \(error)")
        }
      }
    }

    if let image = contribution.startImage {
      if let held = startImage, held.pluginID != pluginID, target.startImageID == held.id {
        addConflict(
          subject: .startImage, current: .init(pluginID: held.pluginID, content: .image(held.name)),
          proposed: .init(pluginID: pluginID, content: .image(image.name)), payload: .startImage(image))
      } else {
        do {
          startImage = (pluginID, try target.setStartImage(image, from: pluginID), image.name)
        } catch {
          problems.append("\(image.name): \(error)")
        }
      }
    }

    // The strength goes after the start image of the same message. It is not a field of the tab (no teal, no conflict):
    // the last one to write wins.
    if let strength = contribution.strength {
      if target.startImageID != nil {
        target.setStrength(strength)
      } else {
        problems.append("strength: there is no start image.")
      }
    }

    // The drawing goes after the start image of the same message, as the Brush layer; no teal, no conflict: the last one wins.
    if let image = contribution.paint {
      if target.startImageID != nil {
        do {
          try target.setPaint(image)
        } catch {
          problems.append("\(image.name): \(error)")
        }
      } else {
        problems.append("paint: there is no start image.")
      }
    }

    if let proposed = contribution.pipeline {
      if pipelineLocked {
        problems.append("pipeline: a pipeline is running.")
      } else if let held = pipeline, let owner = held.pluginID, owner != pluginID {
        // Only another plug-in's pipeline is a conflict: the user's own is replaced (the user pressed the plug-in's button).
        addConflict(
          subject: .pipeline, current: .init(pluginID: owner, content: .passes(held.pipeline.passCount)),
          proposed: .init(pluginID: pluginID, content: .passes(proposed.passCount)), payload: .pipeline(proposed))
      } else {
        pipeline = PipelineContribution(pluginID: pluginID, pipeline: proposed)
      }
    }
    return problems
  }

  /// The user's pick in the pop-up: the plug-in that was writing (`proposed`) or the one already there.
  public func choose(_ conflictID: UUID, proposed: Bool) {
    guard let index = conflicts.firstIndex(where: { $0.id == conflictID }) else { return }
    let conflict = conflicts.remove(at: index)
    guard proposed, let target else { return }
    let owner = conflict.proposed.pluginID
    switch conflict.payload {
    case .field(let field, let value):
      let applied = FieldOverlay([field: value]).applied(to: target.fields)
      target.fields = applied
      marks[field] = FieldMark(pluginID: owner, value: applied.value(of: field), isOverridden: false)
    case .startImage(let image):
      if let id = try? target.setStartImage(image, from: owner) { startImage = (owner, id, image.name) }
    case .pipeline(let plan):
      pipeline = PipelineContribution(pluginID: owner, pipeline: plan)
    }
  }

  /// Esc: the fields stay as they are.
  public func dismissConflicts() { conflicts = [] }

  /// The tab's fields or pictures changed: a field that no longer holds the plug-in's value loses its teal,
  /// and a LoRA, Moodboard picture or start image that is gone is forgotten.
  public func reconcile() {
    guard let target else { return }
    let fields = target.fields
    for (field, mark) in marks {
      let overridden = fields.value(of: field) != mark.value
      if overridden != mark.isOverridden { marks[field]?.isOverridden = overridden }
    }
    let files = target.loraFiles
    if loraPlugins.keys.contains(where: { !files.contains($0) }) { loraPlugins = loraPlugins.filter { files.contains($0.key) } }
    let ids = target.moodboardIDs
    if moodboardPlugins.keys.contains(where: { !ids.contains($0) }) {
      moodboardPlugins = moodboardPlugins.filter { ids.contains($0.key) }
    }
    if let held = startImage, target.startImageID != held.id { startImage = nil }
  }

  /// The plug-in was turned off: its teal, its brackets and its pipeline go; the values stay as they are.
  public func forget(_ pluginID: String) {
    marks = marks.filter { $0.value.pluginID != pluginID }
    loraPlugins = loraPlugins.filter { $0.value != pluginID }
    moodboardPlugins = moodboardPlugins.filter { $0.value != pluginID }
    if startImage?.pluginID == pluginID { startImage = nil }
    if pipeline?.pluginID == pluginID { pipeline = nil }
    conflicts.removeAll { $0.current.pluginID == pluginID || $0.proposed.pluginID == pluginID }
  }

  /// The user chose one of their pipelines in the Preset menu: it becomes the pipeline of RUN, in place of anyone's,
  /// with no question (a pending one about pipelines goes). False while a pipeline runs: nothing changes then.
  @discardableResult
  public func setUserPipeline(_ pipeline: PluginPipeline, named name: String) -> Bool {
    guard !pipelineLocked else { return false }
    conflicts.removeAll { $0.subject == .pipeline }
    self.pipeline = PipelineContribution(userPipeline: name, pipeline: pipeline)
    return true
  }

  /// Realigns the user's pipeline on RUN with its file, after a pipeline or a preset was saved, renamed or deleted
  /// (`renamedTo` when the file of the pipeline itself was just renamed). A pipeline that cannot be read any more is
  /// taken away. A plug-in's pipeline is left alone.
  public func syncUserPipeline(with store: UserPipelineStore, renamedTo newName: String? = nil) {
    guard let current = pipeline?.userPipelineName else { return }
    let wanted = newName ?? current
    if let actual = store.existingName(for: wanted), let loaded = try? store.load(named: actual) {
      pipeline = PipelineContribution(userPipeline: actual, pipeline: loaded.pluginPipeline(named: actual))
    } else {
      pipeline = nil
    }
  }

  /// "Take away the pipeline" in the Run button's menu.
  public func removePipeline() { pipeline = nil }

  private func addConflict(
    subject: ContributionConflict.Subject, current: ContributionConflict.Side, proposed: ContributionConflict.Side,
    payload: ContributionConflict.Payload
  ) {
    // The same plug-in asking again for the same thing replaces its earlier question.
    conflicts.removeAll { $0.subject == subject && $0.proposed.pluginID == proposed.pluginID }
    conflicts.append(ContributionConflict(subject: subject, current: current, proposed: proposed, payload: payload))
  }

  private static func limited(_ value: FieldValue, for field: ContributionField, in fields: GenerationFields) -> FieldValue {
    FieldOverlay([field: value]).applied(to: fields).value(of: field)
  }
}
