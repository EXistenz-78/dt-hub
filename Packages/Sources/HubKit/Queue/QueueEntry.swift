import Foundation

/// Where an entry of the queue stands.
public enum QueueStatus: Codable, Equatable, Sendable {
  case pending
  /// Never kept on disk: an entry that was running when the app closed is read back as `pending`.
  case running
  case done
  /// The reason the entry could not be loaded or its RUN failed.
  case failed(String)
}

/// The pipeline on RUN when an entry was added. A guided pipeline (one a plug-in drives pass by pass) cannot be queued.
public enum QueuedPipeline: Codable, Equatable, Sendable {
  /// The user's own pipeline, by the name of its file: read again when the entry runs.
  case user(name: String)
  /// A plug-in's listed pipeline, as a copy of its steps (the pictures they name were copied into the entry's folder).
  case plugin(pluginID: String, name: String, steps: [PipelineStep])
}

/// One generation waiting in the queue: the Generation tab (the size included, unlike a preset on disk), Control and
/// the pipeline of RUN, as they were when the entry was added.
public struct QueueEntry: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var createdAt: Date
  public var status: QueueStatus
  /// Model, prompt, negative prompt and parameters; `name` stays empty.
  public var preset: Preset
  public var lockRatio: Bool
  /// The file names are relative to the entry's folder.
  public var control: ControlInputs
  public var pipeline: QueuedPipeline?

  public init(
    id: UUID = UUID(), createdAt: Date = Date(), status: QueueStatus = .pending, preset: Preset, lockRatio: Bool = false,
    control: ControlInputs = ControlInputs(), pipeline: QueuedPipeline? = nil
  ) {
    self.id = id
    self.createdAt = createdAt
    self.status = status
    self.preset = preset
    self.lockRatio = lockRatio
    self.control = control
    self.pipeline = pipeline
  }

  private enum CodingKeys: String, CodingKey { case id, createdAt, status, preset, lockRatio, control, pipeline }

  /// Lenient, like the other saved formats.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
    status = (try? container.decodeIfPresent(QueueStatus.self, forKey: .status)) ?? .pending
    preset = (try? container.decodeIfPresent(Preset.self, forKey: .preset)) ?? Preset(name: "")
    lockRatio = try container.decodeIfPresent(Bool.self, forKey: .lockRatio) ?? false
    control = (try? container.decodeIfPresent(ControlInputs.self, forKey: .control)) ?? ControlInputs()
    pipeline = try? container.decodeIfPresent(QueuedPipeline.self, forKey: .pipeline)
  }
}
