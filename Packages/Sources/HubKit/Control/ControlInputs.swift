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

/// Everything the Control tab holds (spec §4). Saved as `control.json`.
public struct ControlInputs: Equatable, Codable, Sendable {
  public var image: ReferenceImage?
  public var framing: Framing
  /// nil = automatic: 100 % for the Edit models, 70 % for the others (at 100 % a normal image-
  /// to-image ignores the image). The user's choice, once made, wins.
  public var strength: Double?

  public init(image: ReferenceImage? = nil, framing: Framing = Framing(), strength: Double? = nil) {
    self.image = image
    self.framing = framing
    self.strength = strength
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
  }
}

/// What a RUN sends besides the job: the start image already framed to the canvas size. Not
/// `Codable`: images do not go into the PNG metadata.
public struct GenerationInputs: Sendable {
  public var image: CGImage?

  public init(image: CGImage? = nil) {
    self.image = image
  }

  public static let none = GenerationInputs()

  public var isEmpty: Bool { image == nil }
}
