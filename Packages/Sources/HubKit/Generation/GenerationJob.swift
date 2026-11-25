import Foundation
import CoreGraphics

/// One RUN, as sent to the backend: everything is resolved (the seed included).
public struct GenerationJob: Equatable, Codable, Sendable {
  public let prompt: String
  /// Empty when the family does not use it (spec §6).
  public let negativePrompt: String
  public let model: String
  public let parameters: GenerationParameters
  /// The strength of the start image; nil when the RUN has no start image.
  public var imageStrength: Double?
  /// How many Moodboard pictures went with this RUN (0 without a Moodboard).
  public var moodboardCount: Int
  /// What Draw Things does with the mask; nil when the RUN has no mask.
  public var maskSettings: MaskSettings?
  /// The frame rate of the family when the RUN makes a video; nil for images.
  public var videoFPS: Double?
  /// The files of the job's LoRAs the user marked as edit LoRAs (category `edit`): the server must treat them as taking
  /// reference images even when their own specification says nothing. Nil when there are none.
  public var editLoRAFiles: [String]?
  /// The tiling of a pass of a plug-in's pipeline (a seamless pattern); nil for every other job. The key is left out of
  /// the saved job then.
  public var seamlessTile: SeamlessTile?

  public init(
    prompt: String, negativePrompt: String = "", model: String, parameters: GenerationParameters,
    imageStrength: Double? = nil, moodboardCount: Int = 0, maskSettings: MaskSettings? = nil,
    videoFPS: Double? = nil, editLoRAFiles: [String]? = nil, seamlessTile: SeamlessTile? = nil
  ) {
    self.prompt = prompt
    self.negativePrompt = negativePrompt
    self.model = model
    self.parameters = parameters
    self.imageStrength = imageStrength
    self.moodboardCount = moodboardCount
    self.maskSettings = maskSettings
    self.videoFPS = videoFPS
    self.editLoRAFiles = editLoRAFiles
    self.seamlessTile = seamlessTile
  }

  public var isVideo: Bool { videoFPS != nil }

  /// The clip length in seconds; nil for images.
  public var videoSeconds: Double? { videoFPS.map { Double(parameters.video.numFrames) / $0 } }

  /// What Draw Things receives: the trigger words of the job's LoRAs, in order, then the
  /// prompt, separated by spaces; edges trimmed where they join.
  public var promptWithTriggers: String {
    let triggers = parameters.loras.map { $0.trigger.trimmingCharacters(in: .whitespacesAndNewlines) }
    let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    return (triggers + [text]).filter { !$0.isEmpty }.joined(separator: " ")
  }

  /// Lenient, like `GenerationParameters`: jobs saved before the negative prompt existed load.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    prompt = try container.decode(String.self, forKey: .prompt)
    negativePrompt = (try? container.decodeIfPresent(String.self, forKey: .negativePrompt)) ?? ""
    model = try container.decode(String.self, forKey: .model)
    parameters = try container.decode(GenerationParameters.self, forKey: .parameters)
    imageStrength = try? container.decodeIfPresent(Double.self, forKey: .imageStrength)
    moodboardCount = (try? container.decodeIfPresent(Int.self, forKey: .moodboardCount)) ?? 0
    maskSettings = try? container.decodeIfPresent(MaskSettings.self, forKey: .maskSettings)
    videoFPS = try? container.decodeIfPresent(Double.self, forKey: .videoFPS)
    seamlessTile = try? container.decodeIfPresent(SeamlessTile.self, forKey: .seamlessTile)
  }
}

/// What a running generation reports, in order; `.finished` is always last.
public enum GenerationUpdate: Sendable {
  /// Sampling step `step` of `totalSteps`; nil step while encoding or decoding.
  case progress(step: Int?, totalSteps: Int)
  /// A preview of the image being sampled.
  case preview(CGImage)
  /// All the final images of the RUN.
  case finished([CGImage])
  /// The clip of a video RUN.
  case finishedVideo(GeneratedVideo)
}

extension GenerationJob {
  /// The key under which the layout of Draw Things keeps DT Hub's own job in a picture's "UserComment".
  public static let metadataKey = "dthub"
  /// The key of the seconds a picture took, next to the job.
  public static let elapsedKey = "elapsedSeconds"

  /// The job as a JSON object, with the seconds the picture took when they are known: what DT Hub keeps in a picture.
  public func metadataObject(elapsed: TimeInterval?) -> [String: Any] {
    guard let data = try? JSONEncoder().encode(self),
      var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    if let elapsed { object[Self.elapsedKey] = elapsed }
    return object
  }
}

