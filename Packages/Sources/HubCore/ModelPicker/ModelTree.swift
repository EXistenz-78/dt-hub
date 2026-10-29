import Foundation
import HubKit

/// A family inside one list: `flux1` of Community and `flux1` of Uncurated are two groups (spec §5).
public struct ModelTreeFamilyID: Hashable, Sendable {
  public var source: ModelSource
  public var family: String?

  public init(source: ModelSource, family: String?) {
    self.source = source
    self.family = family
  }
}

/// What the user has opened in the DT+ model picker. Only Official is open at first, no family is (spec §2); the state
/// lives as long as the app does.
public struct ModelTreeState: Equatable, Sendable {
  public var expandedSources: Set<ModelSource> = [.official]
  public var expandedFamilies: Set<ModelTreeFamilyID> = []

  public init() {}

  public mutating func toggle(_ source: ModelSource) {
    if !expandedSources.insert(source).inserted { expandedSources.remove(source) }
  }

  public mutating func toggle(_ family: ModelTreeFamilyID) {
    if !expandedFamilies.insert(family).inserted { expandedFamilies.remove(family) }
  }
}

public struct ModelTreeFamily: Identifiable, Equatable, Sendable {
  public let id: ModelTreeFamilyID
  public let count: Int
  public let isExpanded: Bool
  public let models: [CatalogModel]
  public var family: String? { id.family }
}

public struct ModelTreeSection: Identifiable, Equatable, Sendable {
  public var id: ModelSource { source }
  public let source: ModelSource
  /// All the models of the list, or the ones that match the search.
  public let count: Int
  public let isExpanded: Bool
  public let families: [ModelTreeFamily]
}

/// The tree of the DT+ model picker: list › family › models, with the search applied (spec §5).
public enum ModelTree {
  /// With no search (empty, or only spaces) the groups are open as `state` says. With a search only the models that
  /// match (name, file or family, ignoring case and accents) are kept, only the groups with results are shown, and
  /// every one of them is open: a result hidden in a closed group would not be found.
  public static func sections(for catalog: ModelCatalog, query: String, state: ModelTreeState) -> [ModelTreeSection] {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let searching = !text.isEmpty
    return catalog.modelsBySource.compactMap { group -> ModelTreeSection? in
      let families = group.families.compactMap { family -> ModelTreeFamily? in
        // Video families not enabled yet stay out (see `VideoFamilies`).
        guard !VideoFamilies.isHidden(family.family) else { return nil }
        let models = searching ? family.models.filter { matches($0, text) } : family.models
        guard !models.isEmpty else { return nil }
        let id = ModelTreeFamilyID(source: group.source, family: family.family)
        return ModelTreeFamily(
          id: id, count: models.count, isExpanded: searching || state.expandedFamilies.contains(id), models: models)
      }
      guard !families.isEmpty else { return nil }
      return ModelTreeSection(
        source: group.source, count: families.reduce(0) { $0 + $1.count },
        isExpanded: searching || state.expandedSources.contains(group.source), families: families)
    }
  }

  static func matches(_ model: CatalogModel, _ text: String) -> Bool {
    model.name.localizedStandardContains(text) || model.file.localizedStandardContains(text)
      || (model.family?.localizedStandardContains(text) ?? false)
  }
}
