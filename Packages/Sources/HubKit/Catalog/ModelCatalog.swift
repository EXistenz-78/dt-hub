/// A generative model installed on the Draw Things server.
public struct CatalogModel: Identifiable, Equatable, Sendable {
  public var id: String { file }
  public let file: String
  public let name: String
  /// Draw Things model version, e.g. "flux2_9b": the model family key of spec §5.
  public let family: String?

  public init(file: String, name: String, family: String?) {
    self.file = file
    self.name = name
    self.family = family
  }
}

/// A LoRA installed on the Draw Things server.
public struct CatalogLoRA: Identifiable, Equatable, Sendable {
  public var id: String { file }
  public let file: String
  public let name: String
  /// Model family the LoRA was made for; nil when the server does not say.
  public let family: String?
  /// The trigger word Draw Things keeps for it (its `prefix`); empty when there is none.
  public let trigger: String
  /// The weight suggested by its metadata, when there is one.
  public let defaultWeight: Double?

  public init(file: String, name: String, family: String?, trigger: String = "", defaultWeight: Double? = nil) {
    self.file = file
    self.name = name
    self.family = family
    self.trigger = trigger
    self.defaultWeight = defaultWeight
  }
}

/// Models of one family, for the grouped model menu.
public struct ModelFamilyGroup: Identifiable, Equatable, Sendable {
  public var id: String { family ?? "" }
  /// nil groups the models whose family is unknown.
  public let family: String?
  public let models: [CatalogModel]
}

/// What the Draw Things server has installed, as DT Hub needs it.
public struct ModelCatalog: Equatable, Sendable {
  public let models: [CatalogModel]
  public let loras: [CatalogLoRA]
  /// How many files the server listed. Zero when its "Model browsing" option is off (spec §10).
  public let fileCount: Int

  public init(models: [CatalogModel], loras: [CatalogLoRA], fileCount: Int) {
    self.models = models
    self.loras = loras
    self.fileCount = fileCount
  }

  public static let empty = ModelCatalog(models: [], loras: [], fileCount: 0)

  /// True when a reachable server lists no files at all: its model browsing is off.
  public var isModelBrowsingDisabled: Bool { fileCount == 0 }

  public func model(forFile file: String) -> CatalogModel? {
    models.first { $0.file == file }
  }

  /// Models grouped by family: families in alphabetical order, the unknown family last,
  /// models by name inside each group.
  public var modelsByFamily: [ModelFamilyGroup] {
    let grouped = Dictionary(grouping: models, by: \.family)
    let families = grouped.keys.sorted { lhs, rhs in
      switch (lhs, rhs) {
      case (nil, _): false
      case (_, nil): true
      case let (l?, r?): l.localizedStandardCompare(r) == .orderedAscending
      }
    }
    return families.map { family in
      ModelFamilyGroup(
        family: family,
        models: grouped[family, default: []].sorted {
          $0.name.localizedStandardCompare($1.name) == .orderedAscending
        })
    }
  }
}
