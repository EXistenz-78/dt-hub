import Foundation
import Testing

/// Every visible string of the app must exist in English and Italian (spec §12).
/// Two checks: every catalog entry is translated in both languages, and every localized
/// literal in the app's sources is a catalog key. The second check is needed because
/// command-line builds (`xcodebuild`) do not add new keys to the catalog: without it, a
/// new `Text("…")` would pass here and show its raw key in the app.
struct LocalizationCatalogTests {
  static let catalogURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // CatalogTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // Packages
    .deletingLastPathComponent()  // repository root
    .appendingPathComponent("App/Localizable.xcstrings")

  struct Catalog: Decodable {
    let sourceLanguage: String
    let strings: [String: Entry]
  }

  struct Entry: Decodable {
    let localizations: [String: Localization]?
  }

  struct Localization: Decodable {
    let stringUnit: StringUnit?
  }

  struct StringUnit: Decodable {
    let state: String
    let value: String
  }

  static func loadCatalog() throws -> Catalog {
    try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))
  }

  static let appURL = catalogURL.deletingLastPathComponent()

  static func appSwiftFiles() throws -> [URL] {
    let enumerator = FileManager.default.enumerator(at: appURL, includingPropertiesForKeys: nil)
    return (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
  }

  /// String literals given as the title of a design-system component (`DSCollapsibleCard`,
  /// `DSMenuLabel`, `DSGroupHeader`, `DSPanelHeader`), in source order.
  static func designSystemLiteralTitles(in source: String) -> [String] {
    let pattern =
      #"\bDS(?:CollapsibleCard|MenuLabel)\(\s*"((?:[^"\\]|\\.)*)"|\bDS(?:GroupHeader|PanelHeader)\([^)]*?\btitle:\s*"((?:[^"\\]|\\.)*)""#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(source.startIndex..., in: source)
    return regex.matches(in: source, range: range).compactMap { match in
      [1, 2].lazy.compactMap { Range(match.range(at: $0), in: source) }.first.map { String(source[$0]) }
    }
  }

  /// String literals the app localizes: the first string argument of the SwiftUI
  /// initializers that take a LocalizedStringKey, `String(localized:)`, and the modifiers
  /// that show text (`.help`, `.accessibilityLabel/Hint/Value`, `.navigationTitle/Subtitle`,
  /// `.alert`, `.confirmationDialog`).
  /// `Text(verbatim:)` and non-literal arguments are not localized, so not matched.
  static func localizedLiterals(in source: String) -> Set<String> {
    let pattern =
      #"(?:\b(?:Text|TextField|SecureField|Label|Tab|Button|Toggle|Menu|Section|Picker|Stepper|ProgressView|Link|LabeledContent|GroupBox|DisclosureGroup|WindowGroup|ContentUnavailableView|LocalizedStringKey|LocalizedStringResource)\(\s*|String\(localized:\s*|\.(?:help|accessibilityLabel|accessibilityHint|accessibilityValue|navigationTitle|navigationSubtitle|alert|confirmationDialog)\(\s*)"((?:[^"\\]|\\.)*)""#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(source.startIndex..., in: source)
    return Set(
      regex.matches(in: source, range: range).compactMap { match in
        Range(match.range(at: 1), in: source).map { String(source[$0]) }
      })
  }

  @Test func sourceLanguageIsEnglishAndCatalogIsNotEmpty() throws {
    let catalog = try Self.loadCatalog()
    #expect(catalog.sourceLanguage == "en")
    #expect(!catalog.strings.isEmpty)
  }

  @Test(arguments: ["en", "it"])
  func everyKeyIsTranslated(language: String) throws {
    let catalog = try Self.loadCatalog()
    let missing = catalog.strings.compactMap { key, entry -> String? in
      guard let unit = entry.localizations?[language]?.stringUnit,
        unit.state == "translated", !unit.value.isEmpty
      else { return key }
      return nil
    }
    #expect(missing.isEmpty, "Missing \(language) translations: \(missing.sorted())")
  }

  @Test func findsLocalizedLiteralsInSource() {
    let source = """
      Text("a.key")
      Label("b.key", systemImage: "cube")
      Image(systemName: "chevron.down")
      Text(verbatim: "raw")
      Text(tab.title)
      .help(String(localized: "c.key"))
      TextField("d.key", text: $host)
      SecureField("e.key", text: $secret)
      Stepper("f.key", value: $steps)
      ProgressView("g.key")
      LabeledContent("h.key", value: size)
      .alert("i.key", isPresented: $shown) { }
      .accessibilityHint("j.key")
      Text(LocalizedStringKey("k.key"))
      """
    #expect(
      Self.localizedLiterals(in: source)
        == ["a.key", "b.key", "c.key", "d.key", "e.key", "f.key", "g.key", "h.key", "i.key", "j.key", "k.key"])
  }

  @Test func findsDesignSystemTitlesGivenAsStringLiterals() {
    let source = """
      DSCollapsibleCard("Prompt", isExpanded: $open) { }
      DSMenuLabel(String(localized: "header.plugins"), systemImage: "cube")
      DSGroupHeader(title: "Light")
      DSPanelHeader(icon: "sun.max", title: String(localized: "panel.light"))
      """
    #expect(Self.designSystemLiteralTitles(in: source) == ["Prompt", "Light"])
  }

  /// Design-system components take a plain `String` title, which SwiftUI never localizes:
  /// a literal there would ship untranslated (spec §12). Callers pass `String(localized:)`.
  @Test func appNeverPassesStringLiteralsToDesignSystemTitles() throws {
    var offenders: [String] = []
    for file in try Self.appSwiftFiles() {
      let source = try String(contentsOf: file, encoding: .utf8)
      offenders += Self.designSystemLiteralTitles(in: source).map { "\(file.lastPathComponent): \($0)" }
    }
    #expect(offenders.isEmpty, "Pass String(localized:) instead: \(offenders.sorted())")
  }

  @Test func everyLocalizedLiteralOfTheAppIsInTheCatalog() throws {
    let keys = Set(try Self.loadCatalog().strings.keys)
    var missing: [String] = []
    for file in try Self.appSwiftFiles() {
      let used = Self.localizedLiterals(in: try String(contentsOf: file, encoding: .utf8))
      missing += used.subtracting(keys).map { "\(file.lastPathComponent): \($0)" }
    }
    #expect(missing.isEmpty, "Not in the catalog: \(missing.sorted())")
  }
}
