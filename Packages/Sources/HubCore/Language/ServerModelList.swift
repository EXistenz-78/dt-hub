import Foundation
import HubKit

/// The language models LM Studio's server offers. It asks LM Studio's own list first (`/api/v0/models`, which says
/// the type of each model and so tells language models from embedding models) and falls back to the OpenAI list
/// (`/v1/models`), dropping what looks like an embedding model.
public struct ServerModelList: Sendable {
  /// Reads one URL (replaced by a fake in tests).
  public var fetch: @Sendable (URL) async throws -> Data

  public init(fetch: @escaping @Sendable (URL) async throws -> Data) {
    self.fetch = fetch
  }

  /// The real one: 5 seconds of patience.
  public static let live = ServerModelList { url in
    var request = URLRequest(url: url)
    request.timeoutInterval = 5
    return try await URLSession.shared.data(for: request).0
  }

  /// A model of the server is told apart from a model of a folder by this start of its `path`.
  public static let idPrefix = "lmstudio://"

  public static func descriptor(id: String, vision: Bool) -> LanguageModelDescriptor {
    LanguageModelDescriptor(path: idPrefix + id, name: id, sizeBytes: 0, supportsImages: vision)
  }

  /// The language models of the server at `base`, by name. `visionModels` are those the user said read pictures.
  public func models(base: URL, visionModels: Set<String>) async throws(LanguageModelError) -> [LanguageModelDescriptor] {
    var found: [LanguageModelDescriptor]?
    if let data = try? await fetch(LMStudioAddress.nativeModelsURL(base)) {
      found = Self.native(data, visionModels: visionModels)
    }
    if found == nil {
      do {
        found = Self.openAI(try await fetch(LMStudioAddress.modelsURL(base)), visionModels: visionModels)
      } catch {
        found = nil
      }
    }
    guard let found else {
      let place = "\(base.host ?? "localhost"):\(base.port ?? 0)"
      throw .loadFailed("LM Studio does not answer on \(place). Is it running, with its server started?")
    }
    return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  private static func entries(_ data: Data) -> [[String: Any]]? {
    ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["data"] as? [[String: Any]]
  }

  static func native(_ data: Data, visionModels: Set<String>) -> [LanguageModelDescriptor]? {
    guard let entries = entries(data) else { return nil }
    return entries.compactMap { entry in
      guard let id = entry["id"] as? String, let type = entry["type"] as? String, type == "llm" || type == "vlm"
      else { return nil }
      return descriptor(id: id, vision: type == "vlm" || visionModels.contains(id))
    }
  }

  static func openAI(_ data: Data, visionModels: Set<String>) -> [LanguageModelDescriptor]? {
    guard let entries = entries(data) else { return nil }
    return entries.compactMap { entry in
      guard let id = entry["id"] as? String, !id.lowercased().contains("embed") else { return nil }
      return descriptor(id: id, vision: visionModels.contains(id))
    }
  }
}
