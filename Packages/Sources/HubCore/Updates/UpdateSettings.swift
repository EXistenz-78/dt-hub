import Foundation

/// What the update check remembers between launches: whether it runs at launch, when it last ran, and which versions
/// the user put off.
public struct UpdateSettings {
  static let checkOnLaunchKey = "updates.checkOnLaunch"
  static let lastCheckKey = "updates.lastCheck"
  static let dismissedKey = "updates.dismissed"
  /// The launch check waits at least this long after the last one.
  static let interval: TimeInterval = 12 * 3600

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

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

  /// Whether the check at launch should run now.
  public func isDue(now: Date) -> Bool {
    guard checkOnLaunch else { return false }
    guard let last = lastCheck else { return true }
    return now.timeIntervalSince(last) >= Self.interval
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
