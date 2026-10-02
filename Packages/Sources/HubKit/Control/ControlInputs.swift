import CoreGraphics
import Foundation

/// An image the user gave to the Control tab, kept as a copy in the app's Control folder so the
/// original (or a Results image) can go away without breaking the input (tab Control spec §4).
public struct ReferenceImage: Identifiable, Equatable, Codable, Sendable {
  public enum Source: Equatable, Codable, Sendable {
    /// A file chosen or dropped from the Finder; the path is only for showing where it came from.
    case file(path: String)
    /// An image of the Results window.
    case result
    case pasteboard
    /// Given by a plug-in (from M8).
    case plugin(id: String)
  }

  public let id: UUID
  public let name: String
  public let pixelWidth: Int
  public let pixelHeight: Int
  public let source: Source
  /// The copy, in the Control folder.
  public let fileName: String

  public init(id: UUID, name: String, pixelWidth: Int, pixelHeight: Int, source: Source, fileName: String) {
    self.id = id
    self.name = name
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.source = source
    self.fileName = fileName
  }
}

/// How the start image sits in the canvas (spec §5). Only "fill" exists for now; "contain" comes
/// with the outpaint.
public struct Framing: Equatable, Codable, Sendable {
  public enum Mode: String, Codable, Sendable {
    case fill
  }

  public var mode: Mode
  /// Where the cut falls on the axis that is cropped: -1 shows the start (left or top) of the
  /// image, 0 is centered, 1 shows the end.
  public var offsetX: Double
  public var offsetY: Double

  public init(mode: Mode = .fill, offsetX: Double = 0, offsetY: Double = 0) {
    self.mode = mode
    self.offsetX = offsetX
    self.offsetY = offsetY
  }

  public func clamped() -> Framing {
    Framing(mode: mode, offsetX: min(1, max(-1, offsetX)), offsetY: min(1, max(-1, offsetY)))
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mode = (try? container.decodeIfPresent(Mode.self, forKey: .mode)) ?? .fill
    offsetX = (try? container.decodeIfPresent(Double.self, forKey: .offsetX)) ?? 0
    offsetY = (try? container.decodeIfPresent(Double.self, forKey: .offsetY)) ?? 0
  }
}

/// One image of the Moodboard (tab Control spec §3): its picture and the switch. Every picture
/// that is on counts the same: Draw Things gives the same weight to every picture above 0 on the
/// models that read the Moodboard (measured, 2 October 2026), so there are no shares yet (§4.1).
public struct MoodboardEntry: Identifiable, Equatable, Codable, Sendable {
  public var id: UUID { image.id }
  public var image: ReferenceImage
  public var isOn: Bool

  public init(image: ReferenceImage, isOn: Bool = true) {
    self.image = image
    self.isOn = isOn
  }
}

/// Decodes what it can: a damaged element becomes nil instead of failing the whole list.
struct Lossy<Value: Decodable>: Decodable {
  let value: Value?

  init(from decoder: any Decoder) throws {
    value = try? decoder.singleValueContainer().decode(Value.self)
  }
}

/// Everything the Control tab holds (spec §4). Saved as `control.json`.
public struct ControlInputs: Equatable, Codable, Sendable {
  public var image: ReferenceImage?
  /// The Moodboard, in the order of the thumbnails.
  public var moodboard: [MoodboardEntry]
  public var framing: Framing
  /// nil = automatic: 100 % for the Edit models, 70 % for the others (at 100 % a normal image-
  /// to-image ignores the image). The user's choice, once made, wins.
  public var strength: Double?

  public init(
    image: ReferenceImage? = nil, framing: Framing = Framing(), strength: Double? = nil,
    moodboard: [MoodboardEntry] = []
  ) {
    self.image = image
    self.framing = framing
    self.strength = strength
    self.moodboard = moodboard
  }

  /// The strength that is sent and shown, within 0…1.
  public func effectiveStrength(editModel: Bool) -> Double {
    min(1, max(0, strength ?? (editModel ? 1.0 : 0.7)))
  }

  /// Lenient, like the other saved files: a missing or unreadable field takes its default.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    image = try? container.decodeIfPresent(ReferenceImage.self, forKey: .image)
    framing = (try? container.decodeIfPresent(Framing.self, forKey: .framing)) ?? Framing()
    strength = try? container.decodeIfPresent(Double.self, forKey: .strength)
    moodboard = ((try? container.decodeIfPresent([Lossy<MoodboardEntry>].self, forKey: .moodboard)) ?? [])
      .compactMap(\.value)
  }
}

/// What a RUN sends besides the job: the start image already framed to the canvas size. Not
/// `Codable`: images do not go into the PNG metadata.
public struct GenerationInputs: Sendable {
  public var image: CGImage?
  /// The Moodboard's pictures that are on, in order.
  public var hints: [GenerationHint]

  public init(image: CGImage? = nil, hints: [GenerationHint] = []) {
    self.image = image
    self.hints = hints
  }

  public static let none = GenerationInputs()

  public var isEmpty: Bool { image == nil && hints.isEmpty }
}

/// One Moodboard picture of a RUN: encoded image data (PNG) and its weight (1: all count the same).
public struct GenerationHint: Sendable {
  public let imageData: Data
  public let weight: Double

  public init(imageData: Data, weight: Double = 1) {
    self.imageData = imageData
    self.weight = weight
  }
}
