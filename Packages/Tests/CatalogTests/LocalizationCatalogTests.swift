import Foundation
import Testing

/// Every visible string of the app must exist in English and Italian (spec §12).
/// Xcode adds any new key it finds in the code to the catalog at build time,
/// untranslated: this test then fails until both languages are filled in.
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
}
