import Foundation

/// What the update check remembers between launches: whether it runs at launch, when it last ran (shown in the
/// preferences), and which versions the user put off.
public struct UpdateSettings {
  static let checkOnLaunchKey = "updates.checkOnLaunch"
  static let lastCheckKey = "updates.lastCheck"
  static let dismissedKey = "updates.dismissed"

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// Whether DT Hub checks at every launch (one small request; an offer found earlier is not remembered between launches, so
  /// a check that waited would hide it).
  public var checkOnLaunch: Bool {
    get { defaults.object(forKey: Self.checkOnLaunchKey) as? Bool ?? true }
    nonmutating set { defaults.set(newValue, forKey: Self.checkOnLaunchKey) }
  }

  public private(set) var lastCheck: Date? {
    get { defaults.object(forKey: Self.lastCheckKey) as? Date }
    nonmutating set { defaults.set(newValue, forKey: Self.lastCheckKey) }
  }

  /// Offer id (`app` for the app) → the version the user put off.
  public private(set) var dismissed: [String: String] {
    get { defaults.dictionary(forKey: Self.dismissedKey) as? [String: String] ?? [:] }
    nonmutating set { defaults.set(newValue, forKey: Self.dismissedKey) }
  }

  public mutating func markChecked(at date: Date) {
    lastCheck = date
  }

  public mutating func dismiss(_ offers: [UpdateOffer]) {
    var all = dismissed
    for offer in offers { all[offer.id] = offer.item.version }
    dismissed = all
  }
}
