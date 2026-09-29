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

  /// String literals the app localizes: the first string argument of the SwiftUI
  /// initializers that take a LocalizedStringKey, `String(localized:)`, and the
  /// `.help` / `.accessibilityLabel` / `.navigationTitle` modifiers.
  /// `Text(verbatim:)` and non-literal arguments are not localized, so not matched.
  static func localizedLiterals(in source: String) -> Set<String> {
    let pattern =
      #"(?:\b(?:Text|Label|Tab|Button|Toggle|Menu|Section|Picker|WindowGroup|ContentUnavailableView)\(\s*|String\(localized:\s*|\.(?:help|accessibilityLabel|navigationTitle)\(\s*)"((?:[^"\\]|\\.)*)""#
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
      """
    #expect(Self.localizedLiterals(in: source) == ["a.key", "b.key", "c.key"])
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
