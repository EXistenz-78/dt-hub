# Il plug-in Prompt Master (tappa 2) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Il plug-in Prompt Master per le 13 famiglie di immagini di Draw Things: una card con i 875 termini (gruppi → categorie → termini con casella, Foto/Arte, Shuffle, ricerca, termini personali), una descrizione libera, l'elenco dei termini scelti e il pulsante «Scrivi prompt», che manda master prompt della famiglia, testo e termini all'LLM dell'app e mette il prompt inglese nella Generazione; per Qwen Image 2.1 usa i prompt enhancer ufficiali se ci sono.

**Architecture:**
- Un pacchetto `Plugins/PromptMaster/` come Sphere Light (libreria dinamica; kit e design system con `moduleAliases` `PromptMasterKit` e `PromptMasterDesign`; un solo `build.sh`).
- Dati: tre file JSON (database snellito, master prompt, termini personali) con una copia incorporata nel codice (un bundle non ha risorse); `Scripts/make-prompt-data.py` genera database, master prompt e copie incorporate da Prompt Master 2.0 senza modificarlo.
- Logica in tipi puri e testati (`PromptDatabase`/`DataSource`, `TermTree`, `CustomTermsStore`, `Shuffler`, `BriefBuilder`, `AnswerParser`, `PEPlanner`, `PMWriter`, `PMState`); le viste e `PromptMasterPlugin` sono la colla.
- Parla con l'app solo con il contratto 1 più le aggiunte della tappa 1 (`llm` con `system`/`model`/`options`; `context` con `startImage`, `moodboard`, `languageModels`).

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, SwiftPM (`moduleAliases`), Python 3 (lo script dei dati).

**Spec:** `docs/superpowers/specs/2026-10-05-plugin-prompt-master-design.md` (§3 dati, §4 interfaccia, §5 scrivere il prompt, §7 Qwen Image 2.1, §8 codice, §10 test).

## Global Constraints

- **Repository:** radice `/Users/existenz/Software developement/DT Hub` (percorsi tra virgolette); branch `prompt-master` da `main`. Si cambiano solo `Plugins/PromptMaster/` e `docs/`: né `App/` né `Packages/` né `PluginKit/`.
- **Il plug-in non ha risorse:** tutto è nel codice; le stringhe stanno nella tabella `L` (italiano e inglese, stesse chiavi e stessi segnaposto); i dati JSON sono incorporati in `EmbeddedData.swift` (generato, non si modifica a mano).
- **Chiavi del contratto usate:** `llm` con `system`, `model`, `options`; `context` con `startImage`, `moodboard`, `languageModels`; `contribute` con `fields` (`prompt`, `negativePrompt`). Il negativo si scrive solo per le famiglie con `negative: true`.
- **Famiglie** (le `version` di Draw Things): `flux1`, `flux2`, `flux2_9b`, `flux2_4b`, `krea_2`, `qwen_image`, `qwen_image_2.1`, `z_image`, `sdxl_base_v0.9`, `v1`, `ernie_image`, `hidream_i1`, `cosmos2.5_2b`. Provvisori: `flux2`, `qwen_image_2.1`, `hidream_i1`, `cosmos2.5_2b`. Ogni master prompt contiene «exclusively in English».
- **Identificatori:** plug-in `com.exiztenz.dthub.promptmaster`, classe `PromptMasterEntry`, versione 1.0; chiave di `UserDefaults` `com.exiztenz.dthub.promptmaster.state.v1`.
- **Nei test mai le cartelle vere:** né `~/Library/Application Support/DT Hub/Data`, né le preferenze dell'utente (ogni test usa una cartella temporanea e una `UserDefaults(suiteName:)` sua).
- **Moodboard e I2I:** l'I2I solo se c'è l'immagine di partenza; con il solo Moodboard è T2I e non si mandano immagini; con l'I2I vanno l'immagine di partenza e poi il Moodboard, al massimo 10.
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Blocchi di codice:** quelli dei file nuovi si salvano così come sono; quelli `diff` si applicano dalla radice con `git apply --whitespace=nowarn <file>`.
- **L'app di prova** condivide le preferenze con quella dell'utente: **se l'app dell'utente è aperta non pilotare le finestre**.
- **Fuori:** Ideogram 4; i master prompt rivisti con la ricerca (spec §9); i PE di Qwen provati dal vivo (tappa 3); l'annullamento della richiesta; applicare il formato suggerito dal PE.

## Review Focus

- **Quale copia dei dati vale:** file mancante, illeggibile, di un layout sconosciuto, più vecchio, uguale, più nuovo; il file illeggibile non si tocca (Task 1: `aNewerFileWinsAndAnEqualOneToo`, `anOlderFileLosesWithoutAWarning`, `aFileOfAnUnknownLayoutOrGarbageLosesWithAWarningAndIsLeftAlone`; Task 2: `anUnreadableFileIsNeverOverwritten`).
- **I termini personali sopravvivono** alla sostituzione del database e non si perdono con un file illeggibile (Task 2: `theTermsSurviveAReplacementOfTheDatabase`).
- **Cambiare famiglia** non butta via la selezione fatta in una categoria che la nuova famiglia nasconde, ma non la manda (Task 6: `theFamilyHidesCategoriesAndTheSelectionOfAHiddenOneIsNotSent`).
- **Il Moodboard da solo non fa I2I** e con l'I2I l'immagine di partenza viene prima e non si taglia mai (Task 4: `aMoodboardAloneDoesNotMakeItI2IAndSendsNoPictures`, `atMostTenPicturesGoAndTheStartImageIsNeverTheOneCut`).
- **Il negativo** si scrive solo dove la famiglia lo legge, anche se l'LLM lo manda lo stesso (Task 5: `theNegativePromptIsWrittenOnlyForAFamilyThatReadsOne`).
- **Un errore dell'LLM** (nessun modello, memoria, PE che fallisce) si mostra e non manda niente, e non ripiega in silenzio sul generico (Task 5: `whenTheLanguageModelFailsItsReasonIsShownAndNothingIsSent`, `aFailureOfTheEnhancerIsShownAndDoesNotFallBackInSilence`).
- **Risposte strane dell'LLM:** blocchi `<think>` aperti e mai chiusi, recinzioni, JSON rotto, solo virgolette (Task 4: i test di `AnswerParserTests`).
- **Doppio clic su «Scrivi prompt»** e testo vuoto: il pulsante non parte (Task 6: `theButtonNeedsTheTabOnATextOrATermAndAMasterPrompt`).

---

### Task 1: Il pacchetto, i modelli di dati, lo script dei dati e la regola di caricamento

**Files:**
- Create: `Plugins/PromptMaster/Package.swift`, `Plugins/PromptMaster/Scripts/make-prompt-data.py`, `Plugins/PromptMaster/Sources/PromptMaster/Models.swift`, `Plugins/PromptMaster/Sources/PromptMaster/DataSource.swift`, `Plugins/PromptMaster/Tests/PromptMasterTests/DataTests.swift`
- Generated by the script (committed): `Plugins/PromptMaster/Data/prompt-database.json`, `Plugins/PromptMaster/Data/master-prompts.json`, `Plugins/PromptMaster/Sources/PromptMaster/Embedded/EmbeddedData.swift`

**Interfaces:**
- Produces: `PMTerm`, `PMCategory` (con `negative`, `descIt`), `PMGroup` (con `restricted`), `PromptDatabase`, `FamilyPrompt`, `MasterPrompts`, `CustomTerm`, `PMFamilies.all` e `.withBooruSwitch`; `VersionedData`, `DataWarning` (`.unreadable(file:)`, `.unknownSchema(file:)`), `DataSource.load(_:fileURL:embedded:)`, `DataSource.isOlder(_:than:)`, `DataSource.defaultFolder`; `PMData.load(folder:)` (`database`, `masters`, `warnings`), `PMData.embeddedDatabase`, `PMData.embeddedMasters`, `PMData.pluginFolderName` (`"prompt-master"`), `EmbeddedData.database` e `.masterPrompts`.

- [ ] **Step 1: Creare il branch, il pacchetto e il test**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git switch main && git switch -c prompt-master && mkdir -p Plugins/PromptMaster/Sources/PromptMaster Plugins/PromptMaster/Tests/PromptMasterTests Plugins/PromptMaster/Scripts
```

**`Plugins/PromptMaster/Package.swift`** (file nuovo o riscritto per intero):

```swift
// swift-tools-version: 6.2
import PackageDescription

// The Prompt Master plug-in of DT Hub (docs/superpowers/specs/2026-10-05-plugin-prompt-master-design.md).
let package = Package(
  name: "PromptMaster",
  platforms: [.macOS(.v26)],
  products: [.library(name: "PromptMaster", type: .dynamic, targets: ["PromptMaster"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Like every plug-in it carries its own copy of the kit and of the design system, under names of its own.
    .target(
      name: "PromptMaster",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "PromptMasterKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "PromptMasterDesign"]),
      ]),
    .testTarget(name: "PromptMasterTests", dependencies: ["PromptMaster"]),
  ]
)
```

**`Plugins/PromptMaster/Tests/PromptMasterTests/DataTests.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation
import Testing

@testable import PromptMaster

@Suite("The data files")
struct DataTests {
  // MARK: The copies built into the plug-in

  @Test func theEmbeddedDatabaseIsTheSlimOneWithEveryTerm() {
    let database = PMData.embeddedDatabase
    #expect(database.schema == DataSource.supportedSchema)
    #expect(database.groups.count == 8 && database.categories.count == 40)
    let terms = database.categories.flatMap(\.terms)
    #expect(terms.count == 875)
    #expect(Set(terms.map(\.id)).count == 875)  // ids are unique: a selection is a set of ids
    #expect(terms.allSatisfy { !$0.it.isEmpty && !$0.en.isEmpty })
    #expect(database.categories.allSatisfy { category in database.groups.contains { $0.id == category.group } })
    #expect(database.groups.first { $0.id == "H" }?.restricted == true)
    #expect(database.categories.filter { $0.negative == true }.map(\.id) == ["negative_terms"])
    // Slim: no booru or prose forms.
    #expect(!EmbeddedData.database.contains("en_tag") && !EmbeddedData.database.contains("en_prose"))
  }

  @Test func theEmbeddedMasterPromptsCoverTheThirteenFamiliesAndAskForEnglish() {
    let masters = PMData.embeddedMasters
    #expect(Set(masters.families.keys) == Set(PMFamilies.all))
    #expect(PMFamilies.all.count == 13)
    for (family, prompt) in masters.families {
      #expect(prompt.system.contains("exclusively in English"), "\(family) must ask for English only")
      #expect(prompt.system.contains(prompt.label))
      // The JSON shape of the answer is the only place with braces: no placeholder was left unfilled.
      if !prompt.negative { #expect(!prompt.system.contains("{"), "\(family): an unfilled placeholder") }
      #expect(!prompt.system.contains("{label}") && !prompt.system.contains("{words}") && !prompt.system.contains("{notes}"))
    }
    // A family with a negative prompt asks for the JSON answer; one without does not.
    #expect(masters.families["sdxl_base_v0.9"]?.system.contains(#""negative""#) == true)
    #expect(masters.families["flux1"]?.system.contains(#""negative""#) == false)
    #expect(masters.families["flux1"]?.negative == false)
    #expect(masters.families["v1"]?.negative == true)
  }

  @Test func hiddenCategoriesAreRealOnesAndNegativeTermsAreHiddenWhereThereIsNoNegative() {
    let ids = Set(PMData.embeddedDatabase.categories.map(\.id))
    for (family, prompt) in PMData.embeddedMasters.families {
      #expect(Set(prompt.hiddenCategories).isSubset(of: ids), "\(family)")
      if !prompt.negative { #expect(prompt.hiddenCategories.contains("negative_terms"), "\(family)") }
    }
    #expect(PMData.embeddedMasters.families["z_image"]?.hiddenCategories.contains("typography_text") == true)
  }

  @Test func onlyTheTwoFamiliesWithTheBooruSwitchHaveItsText() {
    for (family, prompt) in PMData.embeddedMasters.families {
      #expect((prompt.booruSystem != nil) == PMFamilies.withBooruSwitch.contains(family), "\(family)")
    }
  }

  @Test func theFourFamiliesWithoutAReviewAreMarkedProvisional() {
    let provisional = PMData.embeddedMasters.families.filter { $0.value.provisional == true }.keys
    #expect(Set(provisional) == ["flux2", "qwen_image_2.1", "hidream_i1", "cosmos2.5_2b"])
  }

  // MARK: Which copy wins

  private func makeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pm-data-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url.appendingPathComponent("prompt-master"), withIntermediateDirectories: true)
    return url
  }

  private func databaseJSON(version: String, schema: Int = 1, marker: String = "X") -> Data {
    Data(
      """
      {"schema": \(schema), "version": "\(version)", "groups": [{"id": "A", "it": "\(marker)", "en": "\(marker)"}],
       "categories": []}
      """.utf8)
  }

  @Test func withoutAFileTheEmbeddedCopyIsUsedSilently() throws {
    let data = PMData.load(folder: try makeFolder())
    #expect(data.database == PMData.embeddedDatabase && data.masters == PMData.embeddedMasters && data.warnings.isEmpty)
  }

  @Test func aNewerFileWinsAndAnEqualOneToo() throws {
    let folder = try makeFolder()
    try databaseJSON(version: "99.0.0").write(to: folder.appendingPathComponent("prompt-database.json"))
    #expect(PMData.load(folder: folder).database.groups.first?.it == "X")
    try databaseJSON(version: PMData.embeddedDatabase.version).write(to: folder.appendingPathComponent("prompt-database.json"))
    #expect(PMData.load(folder: folder).database.groups.first?.it == "X")
  }

  @Test func anOlderFileLosesWithoutAWarning() throws {
    let folder = try makeFolder()
    try databaseJSON(version: "1.0.0").write(to: folder.appendingPathComponent("prompt-database.json"))
    let data = PMData.load(folder: folder)
    #expect(data.database == PMData.embeddedDatabase && data.warnings.isEmpty)
  }

  @Test func aFileOfAnUnknownLayoutOrGarbageLosesWithAWarningAndIsLeftAlone() throws {
    let folder = try makeFolder()
    let file = folder.appendingPathComponent("prompt-database.json")
    try databaseJSON(version: "99.0.0", schema: 2).write(to: file)
    #expect(PMData.load(folder: folder).warnings == [.unknownSchema(file: "prompt-database.json")])
    try Data("not json".utf8).write(to: file)
    let data = PMData.load(folder: folder)
    #expect(data.database == PMData.embeddedDatabase)
    #expect(data.warnings == [.unreadable(file: "prompt-database.json")])
    #expect(try Data(contentsOf: file) == Data("not json".utf8))  // never touched
  }

  @Test func theMasterPromptsFileLivesInThePluginsOwnFolder() throws {
    let folder = try makeFolder()
    var masters = PMData.embeddedMasters
    masters.version = "99.0.0"
    masters.families["flux1"]?.system = "CHANGED exclusively in English"
    try JSONEncoder().encode(masters).write(to: folder.appendingPathComponent("prompt-master/master-prompts.json"))
    #expect(PMData.load(folder: folder).masters.families["flux1"]?.system == "CHANGED exclusively in English")
  }

  @Test func versionsAreComparedNumberByNumber() {
    #expect(DataSource.isOlder("2.9.0", than: "2.10.0"))
    #expect(!DataSource.isOlder("2.10.0", than: "2.9.0"))
    #expect(!DataSource.isOlder("2.1", than: "2.1.0"))
    #expect(DataSource.isOlder("2.1", than: "2.1.1"))
    #expect(!DataSource.isOlder("abc", than: "0"))
  }
}
```

- [ ] **Step 2: Verificare che fallisca**

Run: `cd "/Users/existenz/Software developement/DT Hub/Plugins/PromptMaster" && swift test 2>&1 | grep -E "error" | head -2`
Expected: un errore (il target `PromptMaster` non ha sorgenti: `Source files for target PromptMaster should be located under 'Sources/PromptMaster'`).

- [ ] **Step 3: Scrivere i modelli, la regola di caricamento e lo script**

I modelli sono `Codable`; le chiavi dei JSON sono in camelCase (`descIt`, `hiddenCategories`, `booruSystem`). `DataSource.load` è l'unica regola su quale copia vale (spec §3): il file se esiste, si legge, ha `schema` 1 e `version` non più vecchia di quella incorporata; altrimenti l'incorporata, con un avviso solo se il file non si legge o ha un layout sconosciuto. Lo script legge Prompt Master 2.0 senza modificarlo.

**`Plugins/PromptMaster/Sources/PromptMaster/Models.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation

/// One term of the vocabulary: its id (stable, also the key of a selection), its Italian and English names. The
/// English name is what the language model gets; the Italian one is for the interface.
struct PMTerm: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var it: String
  var en: String
}

struct PMCategory: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var group: String
  var it: String
  var en: String
  /// A line about the category, in Italian only (a tooltip).
  var descIt: String?
  /// The terms of this category are things to avoid, not things to include.
  var negative: Bool?
  var terms: [PMTerm]
}

struct PMGroup: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var it: String
  var en: String
  /// The group of technical terms (quality, negative, text): the Shuffle leaves it alone.
  var restricted: Bool?
}

/// `prompt-database.json`: shared by the Prompt Master plug-ins (spec §3).
struct PromptDatabase: Codable, Equatable, Sendable, VersionedData {
  var schema: Int
  var version: String
  var groups: [PMGroup]
  var categories: [PMCategory]
}

/// The master prompt of one family and what goes with it.
struct FamilyPrompt: Codable, Equatable, Sendable {
  var label: String
  /// The family reads a negative prompt: the language model is asked for one too.
  var negative: Bool
  /// Categories that make no sense for the family; they do not appear in the list.
  var hiddenCategories: [String]
  var words: String
  /// The system prompt, in English, which asks for an English-only answer.
  var system: String
  /// What is added to `system` when the "booru tags" switch is on (only for the families that have it).
  var booruSystem: String?
  /// Written from the old notes only, waiting for the review of the spec §9.
  var provisional: Bool?
}

/// `master-prompts.json`, keyed by the `version` Draw Things gives the family.
struct MasterPrompts: Codable, Equatable, Sendable, VersionedData {
  var schema: Int
  var version: String
  var families: [String: FamilyPrompt]
}

/// A term the user added to a category (spec §4): one string, in any language.
struct CustomTerm: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var categoryID: String
  var text: String
}

enum PMFamilies {
  /// The families the plug-in works with (the tab is grey on the others), in the order of the spec §3.
  static let all = [
    "flux1", "flux2", "flux2_9b", "flux2_4b", "krea_2", "qwen_image", "qwen_image_2.1", "z_image",
    "sdxl_base_v0.9", "v1", "ernie_image", "hidream_i1", "cosmos2.5_2b",
  ]
  /// Families with the "booru tags" switch: Pony and Illustrious are SDXL and SD 1.5 for Draw Things.
  static let withBooruSwitch: Set<String> = ["sdxl_base_v0.9", "v1"]
}
```

**`Plugins/PromptMaster/Sources/PromptMaster/DataSource.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation

/// Both data files say which layout they have and which edition.
protocol VersionedData {
  var schema: Int { get }
  var version: String { get }
}

/// Why a file in the data folder was not used.
enum DataWarning: Equatable, Sendable {
  case unreadable(file: String)
  case unknownSchema(file: String)
}

struct LoadedData<T> {
  var value: T
  var fromFile: Bool
  var warning: DataWarning?
}

/// Where the data files live and which copy wins (spec §3): the file in the folder, unless it is missing, unreadable,
/// of a layout this plug-in does not know, or older than the copy built into the plug-in.
enum DataSource {
  static let supportedSchema = 1

  static var defaultFolder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true).appendingPathComponent("Data", isDirectory: true)
  }

  /// `a` is an older edition than `b`: dotted numbers compared one by one (2.10.0 is newer than 2.9.0); a missing or
  /// unreadable part counts as 0.
  static func isOlder(_ a: String, than b: String) -> Bool {
    let left = a.split(separator: ".").map { Int($0) ?? 0 }
    let right = b.split(separator: ".").map { Int($0) ?? 0 }
    for index in 0..<max(left.count, right.count) {
      let (x, y) = (index < left.count ? left[index] : 0, index < right.count ? right[index] : 0)
      if x != y { return x < y }
    }
    return false
  }

  static func load<T: Decodable & VersionedData>(_ type: T.Type, fileURL: URL, embedded: T) -> LoadedData<T> {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return LoadedData(value: embedded, fromFile: false) }
    let name = fileURL.lastPathComponent
    guard let data = try? Data(contentsOf: fileURL), let file = try? JSONDecoder().decode(T.self, from: data) else {
      return LoadedData(value: embedded, fromFile: false, warning: .unreadable(file: name))
    }
    guard file.schema == supportedSchema else {
      return LoadedData(value: embedded, fromFile: false, warning: .unknownSchema(file: name))
    }
    if isOlder(file.version, than: embedded.version) { return LoadedData(value: embedded, fromFile: false) }
    return LoadedData(value: file, fromFile: true)
  }
}

/// The data the tab works with.
struct PMData {
  var database: PromptDatabase
  var masters: MasterPrompts
  var warnings: [DataWarning]

  static let databaseFileName = "prompt-database.json"
  static let mastersFileName = "master-prompts.json"
  static let pluginFolderName = "prompt-master"

  /// The copies built into the plug-in. A broken one is a bug of the build, caught by the tests.
  static let embeddedDatabase: PromptDatabase = decode(EmbeddedData.database)
  static let embeddedMasters: MasterPrompts = decode(EmbeddedData.masterPrompts)

  private static func decode<T: Decodable>(_ text: String) -> T {
    do { return try JSONDecoder().decode(T.self, from: Data(text.utf8)) } catch { fatalError("Embedded data: \(error)") }
  }

  static func load(folder: URL = DataSource.defaultFolder) -> PMData {
    let database = DataSource.load(
      PromptDatabase.self, fileURL: folder.appendingPathComponent(databaseFileName), embedded: embeddedDatabase)
    let masters = DataSource.load(
      MasterPrompts.self,
      fileURL: folder.appendingPathComponent(pluginFolderName).appendingPathComponent(mastersFileName),
      embedded: embeddedMasters)
    return PMData(
      database: database.value, masters: masters.value, warnings: [database.warning, masters.warning].compactMap { $0 })
  }
}
```

**`Plugins/PromptMaster/Scripts/make-prompt-data.py`** (file nuovo o riscritto per intero):

```python
#!/usr/bin/env python3
"""make-prompt-data.py [--source DIR] — builds the data of the Prompt Master plug-in from Prompt Master 2.0.

Reads DIR/prompt_database.json (the database of PM 2.0, never modified) and writes, under Plugins/PromptMaster:
  Data/prompt-database.json     the slim database: ids, Italian and English names (no booru/prose forms)
  Data/master-prompts.json      one master prompt per family of Draw Things (provisional: see the spec §9)
  Sources/PromptMaster/Embedded/EmbeddedData.swift   both files as Swift raw strings (a plug-in bundle has no resources)
Run from anywhere; the output is deterministic.
"""
import argparse, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(HERE)
DEFAULT_SOURCE = "/Users/existenz/Software developement/Prompt generator/Prompt Master 2.0"

DATABASE_VERSION = "2.1.0"
MASTER_VERSION = "1.0.0"

# The families of Draw Things (its `version`), in the order of the spec §3; `old` is the family of PM 2.0 whose
# category rules (only_for, blocked_for, blocked_categories) seed `hiddenCategories`.
FAMILIES = [
    # id,              label,                         old,           negative, words,      provisional
    ("flux1",          "FLUX.1",                      "flux1",       False, "60-150",  False),
    ("flux2",          "FLUX.2 [dev]",                "flux2_klein", False, "50-150",  True),
    ("flux2_9b",       "FLUX.2 [klein] 9B",           "flux2_klein", False, "50-150",  False),
    ("flux2_4b",       "FLUX.2 [klein] 4B",           "flux2_klein", False, "50-150",  False),
    ("krea_2",         "Krea 2",                      "krea2",       True,  "30-70",   False),
    ("qwen_image",     "Qwen Image",                  "qwen_image",  True,  "50-150",  False),
    ("qwen_image_2.1", "Qwen Image 2.1",              "qwen_image",  False, "50-150",  True),
    ("z_image",        "Z Image",                     "z_image",     False, "60-120",  False),
    ("sdxl_base_v0.9", "Stable Diffusion XL",         "sdxl",        True,  "30-70",   False),
    ("v1",             "Stable Diffusion 1.5",        "sd15",        True,  "15-40",   False),
    ("ernie_image",    "ERNIE-Image",                 "ernie_image", True,  "30-80",   False),
    ("hidream_i1",     "HiDream-I1",                  "flux1",       False, "50-150",  True),
    ("cosmos2.5_2b",   "Anima (Cosmos 2.5)",          "illustrious", True,  "20-60",   True),
]

COMMON = """You write prompts for the image model "{label}".

The user gives you a description of the image they want, in any language, and a list of terms in English taken from a vocabulary of photography, lighting, color, style and materials (some may be marked as things to avoid). Combine them into ONE final prompt that describes a single coherent image: keep every element of the description, use each term where it makes sense, and never contradict the description. Do not add subjects, text or a story the user did not ask for; you may add small connecting details that make the scene coherent.

The final prompt must be written exclusively in English, whatever the language of the description. {output}

Model notes:
{notes}"""

OUTPUT_TEXT = "Reply with the prompt only: no title, no quotation marks around it, no explanation, no markdown, no alternatives."
OUTPUT_JSON = (
    'Reply with a JSON object and nothing else, in this shape: {"prompt": "...", "negative": "..."}. '
    '"prompt" is the final prompt; "negative" lists only what to avoid (specific artifacts, unwanted objects, things the user marked as to avoid), '
    "kept short and targeted, never a generic list of quality words unless the notes below say so. Both values are in English."
)

NOTES = {
    "flux1": """- Write natural, flowing prose in full sentences (T5 encoder: long relational sentences are fine). Target length: {words} words.
- Order: subject and action first, then setting, then light and color, then camera and lens, then style or medium.
- Never use quality tags (masterpiece, 8k, best quality): they degrade the result. No numeric weights.
- There is no negative prompt: say in positive words what the image contains; turn "avoid" terms into a positive description.
- Text that must appear in the image goes in double quotes.""",
    "flux2_klein": """- Write natural prose. The text encoder reads the first elements most strongly, so put the most important element first. Target length: {words} words (under 20 is under-specified, over 300 drifts).
- Order: subject and action, setting, light and color, camera and lens, style or medium.
- No negative prompt and no numeric weights: turn "avoid" terms into positive description. Never use quality tags.
- Exact colors can be given as hex codes (#RRGGBB). Text in the image goes in double quotes, with font, color and position.""",
    "krea_2": """- Write natural prose, {words} words. The model has an aesthetic of its own (depth of field, color grading, rim light): start minimal, with a clear subject, one note of light and one atmosphere, and do not over-specify technical parameters.
- Keep the subject layer and the style layer in separate sentences.
- Numeric weights are read as literal text: never use them.
- A negative prompt is supported but must stay minimal and targeted, naming only specific artifacts or objects to avoid.""",
    "qwen_image": """- Write natural prose like for FLUX, {words} words. Excellent with text in the image (also Chinese and other scripts): put it in double quotes and state font, color and position.
- A negative prompt is supported: use it targeted by kind of defect, never as a generic list of low-quality words; if nothing specific has to be excluded, leave "negative" empty.
- You may end the prompt with the quality suffix "Ultra HD, 4k, cinematic composition".""",
    "qwen_image_2.1": """- Write natural prose, {words} words. The text encoder is a vision-language model: precise spatial and material descriptions work well. Text in the image goes in double quotes with font, color and position.
- If the user wants a transparent background, say explicitly: an RGBA image with an alpha channel and a transparent background.
- There is no negative prompt (guidance 1): turn "avoid" terms into positive description. Never use quality tags.
(Provisional master prompt: to be reviewed against the model's documentation.)""",
    "z_image": """- This is a distilled turbo model with no negative prompt and no numeric weights. Hard limit 800 characters; attention falls after about 75 tokens, so keep the essential content early. Target: {words} words.
- The very first sentence must be the style or medium (before the subject). Do not frame the image as "a photograph" or "a cinematic frame from a film": that framing overrides the style even in first position.
- Turn "avoid" terms into positive description.""",
    "sdxl": """- Start with one descriptive sentence, then a tail of comma-separated tags. Target: {words} words. Quality boosters (masterpiece, best quality) still work.
- Numeric weights like (term:1.2) are allowed, sparingly.
- A negative prompt is recommended: a short comma-separated list of what to avoid (for example blurry, low quality, deformed hands) plus the terms the user marked as to avoid.""",
    "sd15": """- Tags only: {words} comma-separated tags (CLIP, 77-token limit). Order is priority: the first tokens weigh the most, so start with the subject and the style.
- Weights like (term:1.2) are allowed, sparingly.
- A negative prompt is indispensable: a short comma-separated list (blurry, low quality, bad anatomy, extra limbs) plus the terms the user marked as to avoid.""",
    "ernie_image": """- Follow-the-letter model: write a complete prompt of {words} words; the model does not enhance short prompts. Weights like (term:1.3) are supported.
- Text in the image: double quotes, the font style stated next to the text, an explicit position, short segments (8-10 words each).
- A negative prompt is supported but must stay targeted by kind of defect (deformed hands, blurred text), never a generic list of low-quality words.""",
    "hidream": """- Write natural prose, {words} words, subject first, then setting, light, camera and style. No quality tags, no numeric weights.
- Turn "avoid" terms into positive description.
(Provisional master prompt: to be reviewed against the model's documentation.)""",
    "anima": """- Mix a short tag line with natural language: begin with quality and meta tags, then the subject tags (Danbooru style, underscores between words), then one or two sentences in plain English for the scene. Target: {words} words in total.
- A negative prompt is supported: a short comma-separated list of what to avoid.
(Provisional master prompt: to be reviewed against the model's documentation.)""",
}
NOTES_KEY = {"flux1": "flux1", "flux2": "flux2_klein", "flux2_9b": "flux2_klein", "flux2_4b": "flux2_klein",
             "krea_2": "krea_2", "qwen_image": "qwen_image", "qwen_image_2.1": "qwen_image_2.1", "z_image": "z_image",
             "sdxl_base_v0.9": "sdxl", "v1": "sd15", "ernie_image": "ernie_image", "hidream_i1": "hidream",
             "cosmos2.5_2b": "anima"}

BOORU = {
    "sdxl_base_v0.9": "Tag mode is ON: output only comma-separated booru tags (underscores between words), no sentences. Begin with quality tags such as masterpiece, best quality, absurdres (for Pony models score_9, score_8_up, score_7_up).",
    "v1": "Tag mode is ON: output only comma-separated booru tags (underscores between words), no sentences. Begin with quality tags such as masterpiece, best quality.",
}


def hidden_categories(db, old_families, old_id, negative):
    family = next(f for f in old_families if f["id"] == old_id)
    hidden = set(family.get("blocked_categories") or [])
    for cat in db["categories"]:
        if old_id in (cat.get("blocked_for") or []):
            hidden.add(cat["id"])
        only = cat.get("only_for")
        if only is not None and old_id not in only:
            hidden.add(cat["id"])
        if cat["slot"] == "negative" and not negative:
            hidden.add(cat["id"])
    return sorted(hidden)


def build(source):
    db = json.load(open(os.path.join(source, "prompt_database.json")))
    groups = []
    for g in db["groups"]:
        item = {"id": g["id"], "it": g["it"], "en": g["en"]}
        if g.get("restricted"):
            item["restricted"] = True
        groups.append(item)
    categories = []
    for c in db["categories"]:
        item = {"id": c["id"], "group": c["group"], "it": c["it"], "en": c["en"], "descIt": c["desc_it"]}
        if c["slot"] == "negative":
            item["negative"] = True
        item["terms"] = [{"id": t["id"], "it": t["it"], "en": t["en"]} for t in c["terms"]]
        categories.append(item)
    database = {"schema": 1, "version": DATABASE_VERSION, "groups": groups, "categories": categories}

    families = {}
    for fid, label, old, negative, words, provisional in FAMILIES:
        output = OUTPUT_JSON if negative else OUTPUT_TEXT
        notes = NOTES[NOTES_KEY[fid]].format(words=words)
        entry = {
            "label": label, "negative": negative, "hiddenCategories": hidden_categories(db, db["families"], old, negative),
            "words": words, "system": COMMON.format(label=label, output=output, notes=notes),
        }
        if fid in BOORU:
            entry["booruSystem"] = BOORU[fid]
        if provisional:
            entry["provisional"] = True
        families[fid] = entry
    return database, {"schema": 1, "version": MASTER_VERSION, "families": families}


def swift_literal(name, text):
    assert '"""#' not in text
    return f'  static let {name} = #"""\n{text}\n"""#\n'


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default=DEFAULT_SOURCE)
    args = parser.parse_args()
    database, masters = build(args.source)
    os.makedirs(os.path.join(PLUGIN, "Data"), exist_ok=True)
    texts = {}
    for name, obj in (("prompt-database", database), ("master-prompts", masters)):
        texts[name] = json.dumps(obj, ensure_ascii=False, indent=1, sort_keys=False) + "\n"
        with open(os.path.join(PLUGIN, "Data", name + ".json"), "w") as out:
            out.write(texts[name])
    embedded = os.path.join(PLUGIN, "Sources", "PromptMaster", "Embedded")
    os.makedirs(embedded, exist_ok=True)
    with open(os.path.join(embedded, "EmbeddedData.swift"), "w") as out:
        out.write("// Generated by Scripts/make-prompt-data.py: do not edit.\n"
                  "// The data files of the plug-in as strings: a plug-in bundle holds only its library.\n\n"
                  "enum EmbeddedData {\n" + swift_literal("database", texts["prompt-database"].rstrip("\n"))
                  + "\n" + swift_literal("masterPrompts", texts["master-prompts"].rstrip("\n")) + "}\n")
    n_terms = sum(len(c["terms"]) for c in database["categories"])
    print(f"database {database['version']}: {len(database['groups'])} groups, {len(database['categories'])} categories, {n_terms} terms")
    print(f"master prompts {masters['version']}: {len(masters['families'])} families")
```

```bash
cd "/Users/existenz/Software developement/DT Hub" && chmod +x Plugins/PromptMaster/Scripts/make-prompt-data.py
```

- [ ] **Step 4: Generare i dati**

Run: `cd "/Users/existenz/Software developement/DT Hub" && shasum -a 256 "/Users/existenz/Software developement/Prompt generator/Prompt Master 2.0/prompt_database.json" | cut -c1-16 && python3 Plugins/PromptMaster/Scripts/make-prompt-data.py && shasum -a 256 Plugins/PromptMaster/Data/*.json | cut -c1-16`
Expected: `20e597d2f327579e` (il database di Prompt Master 2.0, versione 2.0.0 del 2026-08-18), poi `database 2.1.0: 8 groups, 40 categories, 875 terms` e `master prompts 1.0.0: 13 families`, poi `79411168ae3b85fa` (master-prompts.json) e `f957ff368e0a57ef` (prompt-database.json).

- [ ] **Step 5: Verificare**

Run: `cd "/Users/existenz/Software developement/DT Hub/Plugins/PromptMaster" && swift test 2>&1 | grep -E "Test run with|error:|✘"`
Expected: `Test run with 11 tests in 1 suite passed`.

- [ ] **Step 6: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A Plugins/PromptMaster && git commit -m "feat(pm): pacchetto, modelli, dati generati e regola di caricamento

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: La lista dei termini (ricerca, conteggi) e i termini personali

**Files:**
- `Plugins/PromptMaster/Sources/PromptMaster/CustomTermsStore.swift`, `Plugins/PromptMaster/Sources/PromptMaster/TermTree.swift`, `Plugins/PromptMaster/Tests/PromptMasterTests/CustomTermsStoreTests.swift`, `Plugins/PromptMaster/Tests/PromptMasterTests/TermTreeTests.swift`

**Interfaces:**
- Consumes: `PromptDatabase`, `CustomTerm`, `PMData.embeddedDatabase` (Task 1).
- Produces: `TermNode`, `CategoryNode`, `GroupNode`, `SelectedTerm {id, title, categoryTitle, english, isNegative}`; `TermTree(database:custom:hidden:italian:)`, `filtered(by:database:italian:)`, `isFiltered`, `chosenCount(inCategory:selection:)`, `chosenCount(inGroup:selection:)`, `selectedTerms(_:)`, `pruned(_:)`; `CustomTermsStore(folder:)` con `load()`, `add(text:to:)`, `remove(id:)` e `Failure` (`.empty`, `.unreadableFile`, `.cannotWrite`).

- [ ] **Step 1: Scrivere i test**

**`Plugins/PromptMaster/Tests/PromptMasterTests/TermTreeTests.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation
import Testing

@testable import PromptMaster

@Suite("The list of terms")
struct TermTreeTests {
  private let database = PMData.embeddedDatabase

  private func tree(hidden: Set<String> = [], custom: [CustomTerm] = [], italian: Bool = true) -> TermTree {
    TermTree(database: database, custom: custom, hidden: hidden, italian: italian)
  }

  @Test func theWholeListHasThreeLevelsInTheOrderOfTheDatabase() {
    let tree = tree()
    #expect(tree.groups.map(\.id) == ["A", "B", "C", "D", "E", "F", "G", "H"])
    #expect(tree.groups[0].title == "Camera e ottica")
    #expect(tree.groups[0].categories.first?.id == "framing")
    #expect(tree.groups.flatMap(\.categories).flatMap(\.terms).count == 875)
  }

  @Test func theInterfaceLanguageChoosesTheNames() {
    #expect(tree(italian: false).groups[0].title == "Camera & Optics")
    let framing = tree(italian: false).groups[0].categories[0]
    #expect(framing.title == "Framing" && framing.terms[0].title == "Extreme close-up")
    #expect(framing.details == nil)  // the description is Italian only
    #expect(tree().groups[0].categories[0].details != nil)
    // The language model always gets the English name.
    #expect(tree().groups[0].categories[0].terms[0].english == "Extreme close-up")
  }

  @Test func hiddenCategoriesAreNotThereAndAnEmptyGroupGoesToo() {
    let allOfH = database.categories.filter { $0.group == "H" }.map(\.id)
    let tree = tree(hidden: Set(allOfH + ["framing"]))
    #expect(!tree.groups.contains { $0.id == "H" })
    #expect(!tree.groups[0].categories.contains { $0.id == "framing" })
  }

  @Test func customTermsJoinTheirCategoryAndAreEnglishAsWritten() {
    let custom = [CustomTerm(id: "custom-1", categoryID: "framing", text: "inquadratura dal basso a sinistra")]
    let framing = tree(custom: custom).groups[0].categories[0]
    #expect(framing.terms.last == TermNode(id: "custom-1", title: "inquadratura dal basso a sinistra", english: "inquadratura dal basso a sinistra", isCustom: true))
    // A custom term of a hidden or unknown category is not shown.
    let orphan = [CustomTerm(id: "custom-2", categoryID: "gone", text: "x")]
    #expect(tree(custom: orphan).groups.flatMap(\.categories).flatMap(\.terms).count == 875)
  }

  // MARK: Search

  private func found(_ query: String, italian: Bool = true) -> TermTree {
    tree(italian: italian).filtered(by: query, database: database, italian: italian)
  }

  @Test func aSearchIgnoresCaseAndAccentsAndMatchesBothLanguages() {
    let terms = found("PRIMISSIMO").groups.flatMap(\.categories).flatMap(\.terms).map(\.id)
    #expect(terms.contains("fr_extreme_closeup"))
    #expect(found("extreme close").groups.flatMap(\.categories).flatMap(\.terms).map(\.id).contains("fr_extreme_closeup"))
    #expect(found("intensita").isFiltered)  // "Intensità"-like words match without the accent
  }

  @Test func everyWordOfTheSearchMustMatch() {
    let both = found("primo piano").groups.flatMap(\.categories).flatMap(\.terms)
    #expect(both.contains { $0.id == "fr_closeup" })
    #expect(found("primo zzzz").groups.isEmpty)
  }

  @Test func aCategoryWhoseNameMatchesKeepsAllItsTerms() {
    let framing = found("inquadratura").groups.flatMap(\.categories).first { $0.id == "framing" }
    #expect(framing?.terms.count == database.categories.first { $0.id == "framing" }?.terms.count)
  }

  @Test func aSearchFindsCustomTermsAndAnEmptyOneIsTheWholeList() {
    let custom = [CustomTerm(id: "custom-1", categoryID: "framing", text: "Dal Basso")]
    let narrowed = tree(custom: custom).filtered(by: "basso", database: database, italian: true)
    #expect(narrowed.groups.flatMap(\.categories).flatMap(\.terms).contains { $0.id == "custom-1" })
    let whole = tree().filtered(by: "   ", database: database, italian: true)
    #expect(!whole.isFiltered && whole == tree())
  }

  // MARK: Counts and choices

  @Test func countsOfChosenTermsDoNotChangeWhileOneSearches() {
    let selection: Set<String> = ["fr_closeup", "fr_extreme_closeup", "lq_soft_diffused"]
    let narrowed = found("primo piano")
    #expect(narrowed.chosenCount(inCategory: "framing", selection: selection) == 2)
    #expect(narrowed.chosenCount(inGroup: "A", selection: selection) == 2)
    #expect(tree().chosenCount(inCategory: "nowhere", selection: selection) == 0)
  }

  @Test func theChosenTermsComeInTheOrderOfTheListAndUnknownIdsAreDropped() {
    let tree = tree()
    let ids = tree.selectedTerms(["fr_closeup", "gone", "fr_extreme_closeup"]).map(\.id)
    #expect(ids == ["fr_extreme_closeup", "fr_closeup"])
    #expect(tree.pruned(["fr_closeup", "gone"]) == ["fr_closeup"])
    #expect(tree.selectedTerms(["fr_closeup"])[0].categoryTitle == "Inquadratura")
  }

  @Test func termsOfTheNegativeCategoryAreMarkedToAvoid() {
    let negative = database.categories.first { $0.negative == true }!.terms[0].id
    #expect(tree().selectedTerms([negative])[0].isNegative)
    #expect(!tree().selectedTerms(["fr_closeup"])[0].isNegative)
  }
}
```

**`Plugins/PromptMaster/Tests/PromptMasterTests/CustomTermsStoreTests.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation
import Testing

@testable import PromptMaster

@Suite("The user's own terms")
struct CustomTermsStoreTests {
  private func makeStore() -> CustomTermsStore {
    CustomTermsStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("pm-custom-\(UUID().uuidString)"))
  }

  @Test func aTermIsAddedAndComesBackInANewStore() throws {
    let store = makeStore()
    #expect(store.load().isEmpty)
    let term = try store.add(text: "  luce da finestra  ", to: "light_source")
    #expect(term.text == "luce da finestra" && term.categoryID == "light_source" && term.id.hasPrefix("custom-"))
    #expect(CustomTermsStore(folder: store.folder).load() == [term])
  }

  @Test func theSameTextInTheSameCategoryIsNotAddedTwiceButInAnotherIs() throws {
    let store = makeStore()
    let first = try store.add(text: "Foggy", to: "time_weather")
    #expect(try store.add(text: "foggy", to: "time_weather") == first)
    let other = try store.add(text: "Foggy", to: "mood")
    #expect(other != first && store.load().count == 2)
  }

  @Test func anEmptyTextIsRefusedAndALongOneIsCut() throws {
    let store = makeStore()
    #expect(throws: CustomTermsStore.Failure.empty) { try store.add(text: "  \n ", to: "mood") }
    let long = try store.add(text: String(repeating: "a", count: 500), to: "mood")
    #expect(long.text.count == CustomTermsStore.maxLength)
  }

  @Test func aTermCanBeRemovedAndRemovingAnUnknownOneChangesNothing() throws {
    let store = makeStore()
    let one = try store.add(text: "one", to: "mood")
    let two = try store.add(text: "two", to: "mood")
    try store.remove(id: one.id)
    try store.remove(id: "custom-nothing")
    #expect(store.load() == [two])
  }

  @Test func anUnreadableFileIsNeverOverwritten() throws {
    let store = makeStore()
    try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
    let file = store.folder.appendingPathComponent("custom-terms.json")
    try Data("not json".utf8).write(to: file)
    #expect(store.load().isEmpty)
    #expect(throws: CustomTermsStore.Failure.unreadableFile) { try store.add(text: "x", to: "mood") }
    #expect(throws: CustomTermsStore.Failure.unreadableFile) { try store.remove(id: "custom-1") }
    #expect(try Data(contentsOf: file) == Data("not json".utf8))
  }

  @Test func aFileOfAnotherLayoutIsLeftAloneToo() throws {
    let store = makeStore()
    try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
    let file = store.folder.appendingPathComponent("custom-terms.json")
    try Data(#"{"schema": 2, "terms": []}"#.utf8).write(to: file)
    #expect(throws: CustomTermsStore.Failure.unreadableFile) { try store.add(text: "x", to: "mood") }
  }

  @Test func theTermsSurviveAReplacementOfTheDatabase() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pm-root-\(UUID().uuidString)")
    let store = CustomTermsStore(folder: root.appendingPathComponent("prompt-master"))
    let term = try store.add(text: "mine", to: "mood")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: root.appendingPathComponent("prompt-database.json"))  // the database file is replaced
    #expect(store.load() == [term])
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Plugins/PromptMaster" && swift test 2>&1 | grep -E "error:" | head -2`
Expected: errori di compilazione (`cannot find 'TermTree' in scope`, `cannot find 'CustomTermsStore' in scope`).

- [ ] **Step 3: Implementare**

`TermTree` costruisce i tre livelli per una famiglia (categorie nascoste escluse, gruppi vuoti esclusi), nella lingua dell'interfaccia; la ricerca ignora maiuscole e accenti, vuole tutte le parole, tiene tutto sotto un nome di gruppo o di categoria che corrisponde e cerca anche nei termini personali; i conteggi vengono dalla lista intera, non da quella filtrata. `CustomTermsStore` scrive in modo atomico e **non sovrascrive mai** un file che non si legge o ha un `schema` diverso.

**`Plugins/PromptMaster/Sources/PromptMaster/TermTree.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation

/// A term as the list shows it.
struct TermNode: Identifiable, Equatable {
  var id: String
  /// What the interface shows: the Italian or English name, or the text of a custom term.
  var title: String
  /// What the language model gets.
  var english: String
  var isCustom: Bool
}

struct CategoryNode: Identifiable, Equatable {
  var id: String
  var title: String
  var details: String?
  /// The terms are things to avoid.
  var isNegative: Bool
  var terms: [TermNode]
}

struct GroupNode: Identifiable, Equatable {
  var id: String
  var title: String
  var categories: [CategoryNode]
}

/// A term the user chose, with what the brief needs.
struct SelectedTerm: Identifiable, Equatable {
  var id: String
  var title: String
  var categoryTitle: String
  var english: String
  var isNegative: Bool
}

/// The list of the left card: groups → categories → terms, for one family (some categories are hidden), in one
/// language, with the user's own terms in their categories, and optionally narrowed by a search.
struct TermTree: Equatable {
  private(set) var groups: [GroupNode]
  /// The search narrowed the list: the groups and categories that are left are shown open.
  private(set) var isFiltered = false
  /// Every term id of each category, and every category id of each group, before any search: the counts of chosen
  /// terms do not change while one types.
  private var termIDsByCategory: [String: [String]]
  private var categoryIDsByGroup: [String: [String]]
  private var everyTerm: [String: SelectedTerm]
  private var order: [String]

  init(database: PromptDatabase, custom: [CustomTerm], hidden: Set<String>, italian: Bool) {
    var groups: [GroupNode] = []
    var termIDs: [String: [String]] = [:]
    var categoryIDs: [String: [String]] = [:]
    var every: [String: SelectedTerm] = [:]
    var order: [String] = []
    for group in database.groups {
      var categories: [CategoryNode] = []
      for category in database.categories where category.group == group.id && !hidden.contains(category.id) {
        let categoryTitle = italian ? category.it : category.en
        let isNegative = category.negative == true
        var terms = category.terms.map {
          TermNode(id: $0.id, title: italian ? $0.it : $0.en, english: $0.en, isCustom: false)
        }
        terms += custom.filter { $0.categoryID == category.id }.map {
          TermNode(id: $0.id, title: $0.text, english: $0.text, isCustom: true)
        }
        for term in terms {
          every[term.id] = SelectedTerm(
            id: term.id, title: term.title, categoryTitle: categoryTitle, english: term.english, isNegative: isNegative)
          order.append(term.id)
        }
        termIDs[category.id] = terms.map(\.id)
        categories.append(
          CategoryNode(
            id: category.id, title: categoryTitle, details: italian ? category.descIt : nil, isNegative: isNegative,
            terms: terms))
      }
      guard !categories.isEmpty else { continue }
      categoryIDs[group.id] = categories.map(\.id)
      groups.append(GroupNode(id: group.id, title: italian ? group.it : group.en, categories: categories))
    }
    (self.groups, termIDsByCategory, categoryIDsByGroup, everyTerm, self.order) = (groups, termIDs, categoryIDs, every, order)
  }

  // MARK: Search

  /// Lower case, without accents.
  static func fold(_ text: String) -> String { text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }

  /// The list narrowed by `query`: every word must be in the name (Italian or English, or a custom text). A group or
  /// category whose own name matches keeps everything below it. An empty query is the whole list.
  func filtered(by query: String, database: PromptDatabase, italian: Bool) -> TermTree {
    let words = Self.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    guard !words.isEmpty else { return self }
    func matches(_ texts: [String]) -> Bool {
      let haystack = Self.fold(texts.joined(separator: " "))
      return words.allSatisfy { haystack.contains($0) }
    }
    var copy = self
    copy.isFiltered = true
    copy.groups = groups.compactMap { group in
      let source = database.groups.first { $0.id == group.id }
      if matches([source?.it ?? "", source?.en ?? ""]) { return group }
      let categories = group.categories.compactMap { category -> CategoryNode? in
        let source = database.categories.first { $0.id == category.id }
        if matches([source?.it ?? "", source?.en ?? ""]) { return category }
        var narrowed = category
        let all = Dictionary(uniqueKeysWithValues: (source?.terms ?? []).map { ($0.id, $0) })
        narrowed.terms = category.terms.filter { term in
          guard let known = all[term.id] else { return matches([term.title]) }  // a custom term
          return matches([known.it, known.en])
        }
        return narrowed.terms.isEmpty ? nil : narrowed
      }
      guard !categories.isEmpty else { return nil }
      var narrowed = group
      narrowed.categories = categories
      return narrowed
    }
    return copy
  }

  // MARK: Counts and choices

  func chosenCount(inCategory id: String, selection: Set<String>) -> Int {
    (termIDsByCategory[id] ?? []).filter(selection.contains).count
  }

  func chosenCount(inGroup id: String, selection: Set<String>) -> Int {
    (categoryIDsByGroup[id] ?? []).reduce(0) { $0 + chosenCount(inCategory: $1, selection: selection) }
  }

  /// The chosen terms in the order of the list (groups, categories, terms); an id the list no longer has is dropped.
  func selectedTerms(_ selection: Set<String>) -> [SelectedTerm] {
    order.filter(selection.contains).compactMap { everyTerm[$0] }
  }

  /// The selection without the ids this list does not have (a term of a hidden category, of an older database).
  func pruned(_ selection: Set<String>) -> Set<String> { selection.filter { everyTerm[$0] != nil } }
}
```

**`Plugins/PromptMaster/Sources/PromptMaster/CustomTermsStore.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation

/// The user's own terms, in `custom-terms.json` of the plug-in's folder (spec §4). Apart from the database, so
/// replacing the database does not delete them.
struct CustomTermsStore {
  enum Failure: Error, Equatable {
    /// The text is empty.
    case empty
    /// The file exists and cannot be read: it is left alone rather than overwritten.
    case unreadableFile
    case cannotWrite
  }

  static let fileName = "custom-terms.json"
  static let maxLength = 200
  static let schema = 1

  var folder: URL = DataSource.defaultFolder.appendingPathComponent(PMData.pluginFolderName, isDirectory: true)

  private struct File: Codable {
    var schema: Int
    var terms: [CustomTerm]
  }

  private var fileURL: URL { folder.appendingPathComponent(Self.fileName) }

  /// The terms; none when the file is missing or unreadable.
  func load() -> [CustomTerm] { (try? read()) ?? [] }

  private func read() throws -> [CustomTerm] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    guard let data = try? Data(contentsOf: fileURL), let file = try? JSONDecoder().decode(File.self, from: data),
      file.schema == Self.schema
    else { throw Failure.unreadableFile }
    return file.terms
  }

  /// Adds a term to a category. The same text (ignoring case) in the same category is not added twice: the existing
  /// term comes back.
  @discardableResult
  func add(text: String, to categoryID: String) throws -> CustomTerm {
    let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxLength))
    guard !clean.isEmpty else { throw Failure.empty }
    var terms = try read()
    if let same = terms.first(where: { $0.categoryID == categoryID && $0.text.caseInsensitiveCompare(clean) == .orderedSame }) {
      return same
    }
    let term = CustomTerm(id: "custom-\(UUID().uuidString)", categoryID: categoryID, text: clean)
    terms.append(term)
    try write(terms)
    return term
  }

  func remove(id: String) throws {
    var terms = try read()
    terms.removeAll { $0.id == id }
    try write(terms)
  }

  private func write(_ terms: [CustomTerm]) throws {
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(File(schema: Self.schema, terms: terms)).write(to: fileURL, options: .atomic)
    } catch {
      throw Failure.cannotWrite
    }
  }
}
```

- [ ] **Step 4: Verificare**

Run: `cd "/Users/existenz/Software developement/DT Hub/Plugins/PromptMaster" && swift test 2>&1 | grep -E "Test run with|error:|✘"`
Expected: `Test run with 29 tests in 3 suites passed`.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A Plugins/PromptMaster && git commit -m "feat(pm): lista dei termini con ricerca e conteggi, termini personali

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Lo Shuffle

**Files:**
- `Plugins/PromptMaster/Sources/PromptMaster/Shuffler.swift`, `Plugins/PromptMaster/Tests/PromptMasterTests/ShufflerTests.swift`

**Interfaces:**
- Consumes: `PromptDatabase`, `PMGroup.restricted` (Task 1).
- Produces: `StyleMode` (`.photo`, `.art`); `Shuffler.pick(database:hidden:mode:using:)` → gli id dei termini scelti (uno per categoria che la famiglia non nasconde; le categorie del medium condividono un solo pescaggio; il gruppo tecnico mai).

- [ ] **Step 1: Scrivere il test**

**`Plugins/PromptMaster/Tests/PromptMasterTests/ShufflerTests.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation
import Testing

@testable import PromptMaster

/// A generator that gives the same numbers for the same seed (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
  var state: UInt64
  init(_ seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

@Suite("The Shuffle")
struct ShufflerTests {
  private let database = PMData.embeddedDatabase

  private func categoryOf(_ termID: String) -> String? {
    database.categories.first { $0.terms.contains { $0.id == termID } }?.id
  }

  private func shuffle(_ mode: StyleMode, hidden: Set<String> = [], seed: UInt64 = 1) -> [String] {
    var generator = SeededGenerator(seed)
    return Shuffler.pick(database: database, hidden: hidden, mode: mode, using: &generator)
  }

  @Test func itIsTheSameForTheSameSeedAndDifferentForAnother() {
    #expect(shuffle(.photo, seed: 7) == shuffle(.photo, seed: 7))
    #expect(shuffle(.photo, seed: 7) != shuffle(.photo, seed: 8))
  }

  @Test func everyPickIsARealTermAndNoCategoryGivesTwoExceptTheMedium() {
    for mode in [StyleMode.photo, .art] {
      let ids = shuffle(mode)
      let categories = ids.compactMap(categoryOf)
      #expect(categories.count == ids.count)  // all real
      let medium = Set(mode == .photo ? Shuffler.photoMedium : Shuffler.artMedium)
      let outsideMedium = categories.filter { !medium.contains($0) }
      #expect(Set(outsideMedium).count == outsideMedium.count)
      #expect(categories.filter(medium.contains).count == 1)  // the medium is one draw from the union
    }
  }

  @Test func photoPicksPhotographicCategoriesAndArtPicksArtisticOnes() {
    let photo = Set(shuffle(.photo).compactMap(categoryOf))
    let art = Set(shuffle(.art).compactMap(categoryOf))
    #expect(Set(Shuffler.photoOnly).isSubset(of: photo) && photo.isDisjoint(with: Shuffler.artOnly))
    #expect(Set(Shuffler.artOnly).isSubset(of: art) && art.isDisjoint(with: Shuffler.photoOnly))
    #expect(photo.isSuperset(of: ["light_source", "mood", "environment_built"]) && art.isSuperset(of: ["light_source", "mood"]))
  }

  @Test func theTechnicalGroupIsNeverShuffled() {
    let technical = Set(database.categories.filter { $0.group == "H" }.map(\.id))
    for seed in 1...20 as ClosedRange<UInt64> {
      #expect(Set(shuffle(.photo, seed: seed).compactMap(categoryOf)).isDisjoint(with: technical))
    }
  }

  @Test func hiddenCategoriesAreSkippedAndTheMediumDrawsOnlyFromWhatIsLeft() {
    let hidden: Set<String> = ["lens_focus", "framing", "medium_digital_3d", "film_stock_process"]
    for seed in 1...20 as ClosedRange<UInt64> {
      let categories = shuffle(.photo, hidden: hidden, seed: seed).compactMap(categoryOf)
      #expect(Set(categories).isDisjoint(with: hidden))
    }
    let everything = Set(database.categories.map(\.id))
    #expect(shuffle(.photo, hidden: everything).isEmpty)
  }

  @Test func theMediumPoolHasTheTermsOfAllItsCategories() {
    var seen = Set<String>()
    for seed in 1...400 as ClosedRange<UInt64> {
      seen.formUnion(shuffle(.art, seed: seed).compactMap(categoryOf).filter(Shuffler.artMedium.contains))
    }
    #expect(seen == Set(Shuffler.artMedium))
  }
}
```

- [ ] **Step 2: Verificare che fallisca**

Run: `cd "/Users/existenz/Software developement/DT Hub/Plugins/PromptMaster" && swift test 2>&1 | grep -E "error:" | head -2`
Expected: un errore di compilazione (`cannot find 'Shuffler' in scope`).

- [ ] **Step 3: Implementare**

Le liste di categorie sono quelle del vecchio Prompt Master (comuni, solo foto, solo arte, medium); non pesca i termini personali.

**`Plugins/PromptMaster/Sources/PromptMaster/Shuffler.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation

/// What the Shuffle picks from: the photographic or the artistic side of the vocabulary.
enum StyleMode: String, Codable, Sendable { case photo, art }

/// The Shuffle button of the list (as in Prompt Master 2.0): a new random selection, one term for each category the
/// family keeps, except that the categories of the medium share one draw. The group of technical terms (quality,
/// negative, text) is never shuffled. The user's own terms are not picked.
enum Shuffler {
  /// Categories picked in both modes.
  static let common = [
    "mood_aesthetic_register", "atmosphere", "color_harmony", "genre_aesthetic", "atmospheric_fx",
    "mood", "mood_emotional_tone",
    "light_source", "light_quality", "light_scheme",
    "background_setup",
    "color_palette", "pose_gesture", "expression_gaze", "environment_natural", "environment_built", "time_weather",
    "material_natural", "material_manmade", "surface_finish",
  ]
  static let photoOnly = ["optical_fx", "framing", "camera_angle", "composition", "lens_focus", "photo_genre"]
  static let artOnly = [
    "art_movement", "design_movement", "anime_cartoon_style", "cultural_tradition",
    "artist_classical", "artist_modern", "artist_illustration",
  ]
  static let photoMedium = ["medium_digital_3d", "film_stock_process"]
  static let artMedium = ["medium_digital_3d", "medium_paint_draw", "medium_print_craft"]

  static func pick(
    database: PromptDatabase, hidden: Set<String>, mode: StyleMode, using generator: inout some RandomNumberGenerator
  ) -> [String] {
    let restricted = Set(database.groups.filter { $0.restricted == true }.map(\.id))
    let categories = Dictionary(uniqueKeysWithValues: database.categories.map { ($0.id, $0) })
    func eligible(_ id: String) -> PMCategory? {
      guard let category = categories[id], !category.terms.isEmpty, !hidden.contains(id),
        !restricted.contains(category.group)
      else { return nil }
      return category
    }
    var picked: [String] = []
    for id in common + (mode == .photo ? photoOnly : artOnly) {
      if let category = eligible(id), let term = category.terms.randomElement(using: &generator) { picked.append(term.id) }
    }
    let pool = (mode == .photo ? photoMedium : artMedium).compactMap(eligible).flatMap(\.terms)
    if let term = pool.randomElement(using: &generator) { picked.append(term.id) }
    return picked
  }
}
```

- [ ] **Step 4: Verificare**

Run: `cd "/Users/existenz/Software developement/DT Hub/Plugins/PromptMaster" && swift test 2>&1 | grep -E "Test run with|error:|✘"`
Expected: `Test run with 35 tests in 4 suites passed`.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A Plugins/PromptMaster && git commit -m "feat(pm): Shuffle

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: La richiesta all'LLM, la lettura della risposta e la scelta dei prompt enhancer di Qwen

**Files:**
- `Plugins/PromptMaster/Sources/PromptMaster/AnswerParser.swift`, `Plugins/PromptMaster/Sources/PromptMaster/BriefBuilder.swift`, `Plugins/PromptMaster/Sources/PromptMaster/PEPlanner.swift`, `Plugins/PromptMaster/Tests/PromptMasterTests/AnswerParserTests.swift`, `Plugins/PromptMaster/Tests/PromptMasterTests/BriefTests.swift`, `Plugins/PromptMaster/Tests/PromptMasterTests/PEPlannerTests.swift`

**Interfaces:**
- Consumes: `MasterPrompts`, `FamilyPrompt`, `SelectedTerm` (Task 1, 2); `DTHubLanguageModel`, `DTHubLLMOptions` (il kit, tappa 1).
- Produces: `Brief {system, prompt}`, `BriefBuilder.request(description:terms:)` e `.make(family:masters:description:terms:booru:)`; `ParsedAnswer {prompt, negative, ratio}`, `AnswerParser.parse(_:)`; `PEKind` (`.t2i`, `.i2i`), `PEFallback` (`.modelMissing(PEKind)`, `.systemPromptMissing(model:)`), `Enhancer {kind, model, system, images, options}`, `PEPlan` (`.generic(reason:)`, `.enhancer(_)`), `PEPlanner.plan(family:startImage:moodboard:languageModels:folderSize:readFile:)`, `PEPlanner.folderSize(_:)`.

- [ ] **Step 1: Scrivere i test**

**`Plugins/PromptMaster/Tests/PromptMasterTests/BriefTests.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation
import Testing

@testable import PromptMaster

@Suite("The brief for the language model")
struct BriefTests {
  private let masters = PMData.embeddedMasters
  private func term(_ id: String, _ english: String, avoid: Bool = false) -> SelectedTerm {
    SelectedTerm(id: id, title: english, categoryTitle: "C", english: english, isNegative: avoid)
  }

  @Test func theRequestHasTheDescriptionAsWrittenAndTheTermsInEnglish() {
    let text = BriefBuilder.request(
      description: "  Un vecchio pescatore al molo, all'alba  ",
      terms: [term("a", "Extreme close-up"), term("b", "Soft diffused light"), term("c", "Blurry", avoid: true)])
    #expect(
      text == """
        Description (any language):
        Un vecchio pescatore al molo, all'alba

        Terms to include:
        - Extreme close-up
        - Soft diffused light

        Terms to avoid:
        - Blurry
        """)
  }

  @Test func withoutADescriptionTheModelIsToldToUseTheTermsAlone() {
    let text = BriefBuilder.request(description: " \n ", terms: [term("a", "Fog")])
    #expect(text.contains("(none: build the image from the terms alone)") && text.contains("- Fog"))
    #expect(!text.contains("Terms to avoid"))
  }

  @Test func withoutTermsThereIsNoTermsSection() {
    let text = BriefBuilder.request(description: "a cat", terms: [])
    #expect(text == "Description (any language):\na cat")
  }

  @Test func theSystemPromptIsTheFamilysAndAsksForEnglish() throws {
    let brief = try #require(
      BriefBuilder.make(family: "flux2_9b", masters: masters, description: "ciao", terms: [], booru: false))
    #expect(brief.system == masters.families["flux2_9b"]?.system)
    #expect(brief.system.contains("exclusively in English"))
  }

  @Test func theBooruRuleIsAddedOnlyWhenOnAndOnlyWhereThereIsOne() throws {
    let on = try #require(BriefBuilder.make(family: "v1", masters: masters, description: "x", terms: [], booru: true))
    #expect(on.system.hasSuffix(masters.families["v1"]!.booruSystem!))
    let off = try #require(BriefBuilder.make(family: "v1", masters: masters, description: "x", terms: [], booru: false))
    #expect(off.system == masters.families["v1"]?.system)
    let flux = try #require(BriefBuilder.make(family: "flux1", masters: masters, description: "x", terms: [], booru: true))
    #expect(flux.system == masters.families["flux1"]?.system)  // no switch on this family
  }

  @Test func aFamilyWithoutAMasterPromptHasNoBrief() {
    #expect(BriefBuilder.make(family: "ideogram_4", masters: masters, description: "x", terms: [], booru: false) == nil)
  }
}
```

**`Plugins/PromptMaster/Tests/PromptMasterTests/AnswerParserTests.swift`** (file nuovo o riscritto per intero):

````swift
import Foundation
import Testing

@testable import PromptMaster

@Suite("Reading the answer")
struct AnswerParserTests {
  @Test func plainTextIsThePrompt() {
    #expect(AnswerParser.parse("  A quiet harbour at dawn.\n")?.prompt == "A quiet harbour at dawn.")
    #expect(AnswerParser.parse("A quiet harbour at dawn.")?.negative == nil)
  }

  @Test func aJSONAnswerGivesThePromptAndTheNegative() {
    let answer = AnswerParser.parse(#"{"prompt": "a cat on a sofa", "negative": "blurry, extra legs"}"#)
    #expect(answer == ParsedAnswer(prompt: "a cat on a sofa", negative: "blurry, extra legs", ratio: nil))
  }

  @Test func theEnhancersKeysAreReadToo() {
    let answer = AnswerParser.parse(#"{"rewritten_prompt": "a long prompt", "wh_ratio": "3:2"}"#)
    #expect(answer == ParsedAnswer(prompt: "a long prompt", negative: nil, ratio: "3:2"))
    #expect(AnswerParser.parse(#"{"positive_prompt": "edit it", "ratio_follow": 1}"#)?.prompt == "edit it")
  }

  @Test func thinkingBlocksAndFencesAreRemoved() {
    #expect(AnswerParser.parse("<think>hmm, a cat?</think>\nA cat.")?.prompt == "A cat.")
    #expect(AnswerParser.parse("<think>one</think> x <think>two</think>\nA cat.")?.prompt == "A cat.")
    #expect(AnswerParser.parse("```json\n{\"prompt\": \"a cat\", \"negative\": \"dog\"}\n```")?.negative == "dog")
    #expect(AnswerParser.parse("```\nA cat.\n```")?.prompt == "A cat.")
  }

  @Test func aThinkingBlockThatNeverClosesLeavesWhatCameBefore() {
    #expect(AnswerParser.parse("A cat.<think>and then it went on")?.prompt == "A cat.")
    #expect(AnswerParser.parse("<think>only thoughts") == nil)
  }

  @Test func textAroundTheJSONIsIgnored() {
    #expect(AnswerParser.parse("Here you go: {\"prompt\": \"a cat\"} Enjoy!")?.prompt == "a cat")
  }

  @Test func aMalformedJSONOrOneWithoutAPromptIsTakenAsText() {
    let broken = #"{"prompt": "a cat", "negative":"#
    #expect(AnswerParser.parse(broken)?.prompt == broken)
    let other = #"{"title": "a cat"}"#
    #expect(AnswerParser.parse(other)?.prompt == other)
  }

  @Test func oneWrappingPairOfQuotesGoes() {
    #expect(AnswerParser.parse("\"A cat.\"")?.prompt == "A cat.")
    #expect(AnswerParser.parse("“A cat.”")?.prompt == "A cat.")
    #expect(AnswerParser.parse("\"A cat\" and \"a dog\"")?.prompt == "\"A cat\" and \"a dog\"")  // quotes inside stay
  }

  @Test func nothingLeftIsNil() {
    #expect(AnswerParser.parse("") == nil)
    #expect(AnswerParser.parse("  \n ") == nil)
    #expect(AnswerParser.parse(#"{"prompt": "  "}"#)?.prompt == #"{"prompt": "  "}"#)
  }
}
````

**`Plugins/PromptMaster/Tests/PromptMasterTests/PEPlannerTests.swift`** (file nuovo o riscritto per intero):

```swift
import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMaster

@Suite("Choosing the prompt enhancer")
struct PEPlannerTests {
  /// The kit has no public initializer for the models of the context: they are read from JSON, as the app sends them.
  private func model(_ name: String, vision: Bool = true) -> DTHubLanguageModel {
    let json = #"{"name": "\#(name)", "path": "/models/\#(name)", "supportsImages": \#(vision)}"#
    return try! JSONDecoder().decode(DTHubLanguageModel.self, from: Data(json.utf8))
  }

  private let t2i = "mlx/Qwen-Image-2.1-PE-T2I-MLX-4bit"
  private let i2i = "mlx/Qwen-Image-2.1-PE-I2I-MLX-4bit"

  /// Every enhancer folder has its system prompt file, unless the test says otherwise.
  private func plan(
    family: String? = "qwen_image_2.1", start: String? = nil, moodboard: [String] = [],
    models: [DTHubLanguageModel], sizes: [String: Int64] = [:], files: [String: String]? = nil
  ) -> PEPlan {
    let defaults = ["system_prompt.txt": "T2I SYSTEM", "system_prompt_edit.txt": "EDIT SYSTEM"]
    return PEPlanner.plan(
      family: family, startImage: start, moodboard: moodboard, languageModels: models,
      folderSize: { sizes[$0] ?? 0 },
      readFile: { url in (files ?? defaults)[url.lastPathComponent] })
  }

  private func enhancer(_ plan: PEPlan) -> Enhancer? {
    if case .enhancer(let value) = plan { return value }
    return nil
  }

  @Test func otherFamiliesNeverUseAnEnhancerAndSayNothingAboutIt() {
    #expect(plan(family: "flux2_9b", models: [model(t2i)]) == .generic(reason: nil))
    #expect(plan(family: nil, models: [model(t2i)]) == .generic(reason: nil))
  }

  @Test func withoutAStartImageItIsT2IWithQwensSettings() throws {
    let chosen = try #require(enhancer(plan(models: [model(t2i), model(i2i)])))
    #expect(chosen.kind == .t2i && chosen.model == t2i && chosen.system == "T2I SYSTEM" && chosen.images.isEmpty)
    #expect(chosen.options.temperature == 1 && chosen.options.topK == 20 && chosen.options.presencePenalty == 1.5)
    #expect(chosen.options.maxTokens == 16256 && chosen.options.thinking == true)
  }

  @Test func aMoodboardAloneDoesNotMakeItI2IAndSendsNoPictures() throws {
    let chosen = try #require(enhancer(plan(moodboard: ["/m1.png", "/m2.png"], models: [model(t2i), model(i2i)])))
    #expect(chosen.kind == .t2i && chosen.images.isEmpty)
  }

  @Test func aStartImageMakesItI2IWithTheStartImageFirstThenTheMoodboard() throws {
    let chosen = try #require(enhancer(plan(start: "/s.png", moodboard: ["/m1.png", "/m2.png"], models: [model(t2i), model(i2i)])))
    #expect(chosen.kind == .i2i && chosen.model == i2i && chosen.system == "EDIT SYSTEM")
    #expect(chosen.images == ["/s.png", "/m1.png", "/m2.png"])
    #expect(chosen.options.presencePenalty == 0 && chosen.options.maxTokens == 24000)
  }

  @Test func atMostTenPicturesGoAndTheStartImageIsNeverTheOneCut() throws {
    let moodboard = (1...12).map { "/m\($0).png" }
    let chosen = try #require(enhancer(plan(start: "/s.png", moodboard: moodboard, models: [model(i2i)])))
    #expect(chosen.images.count == 10 && chosen.images.first == "/s.png" && chosen.images.last == "/m9.png")
  }

  @Test func namesWithDashesDotsOrUnderscoresAndAnySuffixAreRecognised() {
    for name in ["qwen3.5_9b_qwen_image_2.1_pe_t2i", "Qwen-Image-2.1-PE-T2I-MLX-4bit", "x/Qwen-Image-2_1-PE-T2I-8bit"] {
      #expect(enhancer(plan(models: [model(name)])) != nil, "\(name)")
    }
    #expect(enhancer(plan(models: [model("Qwen-Image-2.1-PE-I2I-MLX-4bit")])) == nil)  // I2I is not T2I
  }

  @Test func ofTwoFoldersTheBiggestWins() throws {
    let small = model("a/Qwen-Image-2.1-PE-T2I-MLX-4bit"), big = model("a/Qwen-Image-2.1-PE-T2I-MLX-8bit")
    let sizes = [small.path: Int64(5_000), big.path: Int64(9_000)]
    #expect(try #require(enhancer(plan(models: [small, big], sizes: sizes))).model == big.name)
    #expect(try #require(enhancer(plan(models: [big, small], sizes: sizes))).model == big.name)
  }

  @Test func theI2IEnhancerMustReadImages() {
    #expect(plan(start: "/s.png", models: [model(i2i, vision: false)]) == .generic(reason: .modelMissing(.i2i)))
  }

  @Test func withoutTheModelTheGenericOneIsUsedAndTheReasonSaysWhich() {
    #expect(plan(models: []) == .generic(reason: .modelMissing(.t2i)))
    #expect(plan(start: "/s.png", models: [model(t2i)]) == .generic(reason: .modelMissing(.i2i)))
  }

  @Test func withoutTheSystemPromptFileTheGenericOneIsUsedAndTheReasonNamesTheModel() {
    #expect(plan(models: [model(t2i)], files: [:]) == .generic(reason: .systemPromptMissing(model: t2i)))
    #expect(plan(models: [model(t2i)], files: ["system_prompt.txt": "  \n "]) == .generic(reason: .systemPromptMissing(model: t2i)))
  }

  @Test func theOtherSystemPromptFileNamesAreAccepted() throws {
    let t2iFile = try #require(enhancer(plan(models: [model(t2i)], files: ["system_prompt_t2i.txt": "T"])))
    #expect(t2iFile.system == "T")
    let edit = try #require(enhancer(plan(start: "/s.png", models: [model(i2i)], files: ["system_prompt_i2i.txt": "E"])))
    #expect(edit.system == "E")
  }

  @Test func theFolderSizeAddsTheFilesOfTheFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pm-size-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(count: 100).write(to: folder.appendingPathComponent("a.safetensors"))
    try Data(count: 50).write(to: folder.appendingPathComponent("config.json"))
    #expect(PEPlanner.folderSize(folder.path) == 150)
    #expect(PEPlanner.folderSize("/nowhere/\(UUID().uuidString)") == 0)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Plugins/PromptMaster" && swift test 2>&1 | grep -E "error:" | head -2`
Expected: errori di compilazione (`cannot find 'BriefBuilder' in scope`, `cannot find 'AnswerParser'`, `cannot find 'PEPlanner'`).

- [ ] **Step 3: Implementare**

`BriefBuilder.request` è il testo che va all'LLM (descrizione, termini da includere, termini da evitare, questi in inglese); lo stesso per il modello generico e per un PE. `AnswerParser.parse` toglie i blocchi `<think>` (anche quello mai chiuso) e le recinzioni, legge un JSON (`prompt`, `rewritten_prompt` o `positive_prompt`; `negative`; `wh_ratio`) e altrimenti prende il testo intero, senza una coppia di virgolette attorno. `PEPlanner` è una funzione pura: solo per `qwen_image_2.1`, I2I solo se c'è l'immagine di partenza, nomi delle cartelle riconosciuti con `-` e `.` letti come `_`, la cartella più grande vince, il system prompt si cerca nella cartella del modello; manca una delle due cose e il motivo viaggia con `.generic`. Le impostazioni sono quelle di Qwen.

**`Plugins/PromptMaster/Sources/PromptMaster/BriefBuilder.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation

/// What is sent to the language model: the system prompt and the request.
struct Brief: Equatable {
  var system: String
  var prompt: String
}

enum BriefBuilder {
  /// The request: the description as the user wrote it (any language), then the terms in English, those to include
  /// and those to avoid. The same text goes to the generic model and to a prompt enhancer.
  static func request(description: String, terms: [SelectedTerm]) -> String {
    let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
    var lines = ["Description (any language):", text.isEmpty ? "(none: build the image from the terms alone)" : text]
    let include = terms.filter { !$0.isNegative }
    let avoid = terms.filter(\.isNegative)
    if !include.isEmpty {
      lines += ["", "Terms to include:"] + include.map { "- \($0.english)" }
    }
    if !avoid.isEmpty {
      lines += ["", "Terms to avoid:"] + avoid.map { "- \($0.english)" }
    }
    return lines.joined(separator: "\n")
  }

  /// The brief for a family's master prompt; nil for a family without one. `booru` adds the tag rule, for the two
  /// families that have the switch.
  static func make(
    family: String, masters: MasterPrompts, description: String, terms: [SelectedTerm], booru: Bool
  ) -> Brief? {
    guard let master = masters.families[family] else { return nil }
    var system = master.system
    if booru, let extra = master.booruSystem { system += "\n\n" + extra }
    return Brief(system: system, prompt: request(description: description, terms: terms))
  }
}
```

**`Plugins/PromptMaster/Sources/PromptMaster/AnswerParser.swift`** (file nuovo o riscritto per intero):

````swift
import Foundation

/// What the language model answered, cleaned up.
struct ParsedAnswer: Equatable {
  var prompt: String
  var negative: String?
  /// The aspect ratio a prompt enhancer suggests ("3:2").
  var ratio: String?
}

enum AnswerParser {
  /// The prompt (and the negative prompt, and the ratio) in an answer. Reasoning blocks (`<think>…</think>`) and code
  /// fences go; a JSON object gives its `prompt` (or `rewritten_prompt`, or `positive_prompt`) and `negative`; anything
  /// else, a malformed JSON included, is taken as the prompt itself. Nil when nothing is left.
  static func parse(_ raw: String) -> ParsedAnswer? {
    var text = withoutThinking(raw)
    text = withoutFences(text).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
      let object = (try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8))) as? [String: Any],
      let prompt = ["prompt", "rewritten_prompt", "positive_prompt"].lazy.compactMap({ clean(object[$0]) }).first
    {
      return ParsedAnswer(
        prompt: prompt, negative: ["negative", "negative_prompt"].lazy.compactMap { clean(object[$0]) }.first,
        ratio: clean(object["wh_ratio"]))
    }
    return ParsedAnswer(prompt: unquoted(text))
  }

  private static func clean(_ value: Any?) -> String? {
    guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
    return text
  }

  /// Everything up to the last `</think>`; a `<think>` that never closes takes the rest of the text with it.
  private static func withoutThinking(_ text: String) -> String {
    var result = text
    if let close = result.range(of: "</think>", options: .backwards) { result = String(result[close.upperBound...]) }
    if let open = result.range(of: "<think>") { result = String(result[..<open.lowerBound]) }
    return result
  }

  /// The inside of a fenced block (```json … ```), when the text is one.
  private static func withoutFences(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```"), let firstBreak = trimmed.firstIndex(of: "\n") else { return text }
    var inside = String(trimmed[trimmed.index(after: firstBreak)...])
    if let close = inside.range(of: "```", options: .backwards) { inside = String(inside[..<close.lowerBound]) }
    return inside
  }

  /// A prompt wrapped in one pair of quotation marks loses them.
  private static func unquoted(_ text: String) -> String {
    for (open, close) in [("\"", "\""), ("“", "”")] where text.count > 1 && text.hasPrefix(open) && text.hasSuffix(close) {
      let inside = String(text.dropFirst().dropLast())
      if !inside.contains(open) { return inside.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    return text
  }
}
````

**`Plugins/PromptMaster/Sources/PromptMaster/PEPlanner.swift`** (file nuovo o riscritto per intero):

```swift
import DTHubPluginKit
import Foundation

/// Why a family that has prompt enhancers still goes to the generic model.
enum PEFallback: Equatable {
  case modelMissing(PEKind)
  case systemPromptMissing(model: String)
}

enum PEKind: Equatable { case t2i, i2i }

/// A call to a Qwen prompt enhancer.
struct Enhancer: Equatable {
  var kind: PEKind
  /// The name of the model in the app's models folder.
  var model: String
  /// The enhancer's own system prompt, read from its folder.
  var system: String
  /// The pictures it reads: the start image, then the Moodboard (I2I only).
  var images: [String]
  var options: DTHubLLMOptions
}

enum PEPlan: Equatable {
  /// The generic language model with the family's master prompt; `reason` says why a prompt enhancer was not used.
  case generic(reason: PEFallback?)
  case enhancer(Enhancer)
}

/// Qwen Image 2.1 has two prompt enhancers of its own (spec §7); this decides whether and which to use. A pure function
/// of what the app said and what is in the folders, so the rule can be tested and changed in one place.
enum PEPlanner {
  static let family = "qwen_image_2.1"
  static let maxImages = 10
  static let t2iMarker = "qwen_image_2_1_pe_t2i"
  static let i2iMarker = "qwen_image_2_1_pe_i2i"
  static let systemFileNames: [PEKind: [String]] = [
    .t2i: ["system_prompt_t2i.txt", "system_prompt.txt"],
    .i2i: ["system_prompt_edit.txt", "system_prompt_i2i.txt", "system_prompt.txt"],
  ]

  /// Qwen's recommended settings (the enhancer thinks first, so it may take minutes).
  static func options(for kind: PEKind) -> DTHubLLMOptions {
    switch kind {
    case .t2i:
      return DTHubLLMOptions(
        temperature: 1.0, topP: 0.95, topK: 20, presencePenalty: 1.5, maxTokens: 16256, thinking: true, timeout: 900)
    case .i2i:
      return DTHubLLMOptions(
        temperature: 1.0, topP: 0.95, topK: 20, presencePenalty: 0, maxTokens: 24000, thinking: true, timeout: 1200)
    }
  }

  /// `-` and `.` read as `_`, in lower case: `Qwen-Image-2.1-PE-T2I-MLX-4bit` and `qwen3.5_9b_qwen_image_2.1_pe_t2i` both match.
  static func normalized(_ name: String) -> String {
    name.lowercased().map { $0 == "-" || $0 == "." ? "_" : $0 }.reduce(into: "") { $0.append($1) }
  }

  /// - The I2I enhancer is chosen when there is a start image; the Moodboard alone does not make it I2I.
  /// - Of several folders that match, the biggest wins (the most precise: 8 bit over 4 bit).
  static func plan(
    family: String?, startImage: String?, moodboard: [String], languageModels: [DTHubLanguageModel],
    folderSize: (String) -> Int64, readFile: (URL) -> String?
  ) -> PEPlan {
    guard family == Self.family else { return .generic(reason: nil) }
    let kind: PEKind = startImage == nil ? .t2i : .i2i
    let marker = kind == .t2i ? t2iMarker : i2iMarker
    let candidates = languageModels.filter {
      normalized($0.name).contains(marker) && (kind == .t2i || $0.supportsImages)
    }
    guard let model = candidates.max(by: { folderSize($0.path) < folderSize($1.path) }) else {
      return .generic(reason: .modelMissing(kind))
    }
    let folder = URL(fileURLWithPath: model.path, isDirectory: true)
    let system = (systemFileNames[kind] ?? [])
      .compactMap { readFile(folder.appendingPathComponent($0)) }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
    guard let system else { return .generic(reason: .systemPromptMissing(model: model.name)) }
    let images = kind == .i2i ? Array(([startImage].compactMap { $0 } + moodboard).prefix(maxImages)) : []
    return .enhancer(Enhancer(kind: kind, model: model.name, system: system, images: images, options: options(for: kind)))
  }

  /// The size of the files in a folder, for choosing between two enhancers.
  static func folderSize(_ path: String) -> Int64 {
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.fileSizeKey])) ?? []
    return urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
  }
}
```

- [ ] **Step 4: Verificare**

Run: `cd "/Users/existenz/Software developement/DT Hub/Plugins/PromptMaster" && swift test 2>&1 | grep -E "Test run with|error:|✘"`
Expected: `Test run with 62 tests in 7 suites passed`.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A Plugins/PromptMaster && git commit -m "feat(pm): richiesta all'LLM, lettura della risposta, scelta dei PE di Qwen

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Scrivere il prompt e lo shuffle della scena, con le stringhe

**Files:**
- `Plugins/PromptMaster/Sources/PromptMaster/PMWriter.swift`, `Plugins/PromptMaster/Sources/PromptMaster/Strings.swift`, `Plugins/PromptMaster/Tests/PromptMasterTests/PMWriterTests.swift`

**Interfaces:**
- Consumes: `BriefBuilder`, `AnswerParser`, `PEPlanner`, `PEPlan` (Task 4); `DTHubLLMAnswer`, `DTHubLLMOptions` (il kit).
- Produces: `L` (`Key`, `text(_:italian:)`, `format(_:_:italian:)`, `isDefined(_:italian:)`, `systemIsItalian`); `PMWriter` (`@MainActor`, con le closure `ask` e `contribute` e `folderSize`/`readFile`), `PMWriter.Request`, `PMWriter.Outcome {status, ratio, sent}`, `write(_:)`, `scene()` → `Result<String, SceneFailure>`, `PMWriter.genericOptions`, `PMWriter.sceneSystem`.

- [ ] **Step 1: Scrivere il test**

**`Plugins/PromptMaster/Tests/PromptMasterTests/PMWriterTests.swift`** (file nuovo o riscritto per intero):

```swift
import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMaster

/// What the writer asked of the app.
@MainActor
final class Recorder {
  struct Ask { var prompt: String; var images: [String]; var system: String?; var model: String?; var options: DTHubLLMOptions }
  var asks: [Ask] = []
  var contributions: [[String: Any]] = []
  var answer: DTHubLLMAnswer = .text("A quiet harbour at dawn.")
  var accepted: [String: Any]? = ["type": "ok", "conflicts": 0]
}

@MainActor
@Suite("Writing the prompt")
struct PMWriterTests {
  private let masters = PMData.embeddedMasters

  private func writer(_ recorder: Recorder, files: [String: String] = [:], sizes: [String: Int64] = [:]) -> PMWriter {
    PMWriter(
      ask: { prompt, images, system, model, options in
        recorder.asks.append(.init(prompt: prompt, images: images, system: system, model: model, options: options))
        return recorder.answer
      },
      contribute: { recorder.contributions.append($0); return recorder.accepted },
      italian: false, folderSize: { sizes[$0] ?? 0 }, readFile: { files[$0.lastPathComponent] })
  }

  private func request(
    _ family: String = "flux2_9b", description: String = "un porto all'alba", terms: [SelectedTerm] = [],
    booru: Bool = false, start: String? = nil, moodboard: [String] = [], models: [DTHubLanguageModel] = []
  ) -> PMWriter.Request {
    PMWriter.Request(
      family: family, masters: masters, description: description, terms: terms, booru: booru, startImage: start,
      moodboard: moodboard, languageModels: models)
  }

  private func term(_ english: String, avoid: Bool = false) -> SelectedTerm {
    SelectedTerm(id: english, title: english, categoryTitle: "C", english: english, isNegative: avoid)
  }

  private func model(_ name: String) -> DTHubLanguageModel {
    try! JSONDecoder().decode(
      DTHubLanguageModel.self, from: Data(#"{"name": "\#(name)", "path": "/models/\#(name)", "supportsImages": true}"#.utf8))
  }

  private func fields(_ recorder: Recorder) -> [String: Any]? { recorder.contributions.last?["fields"] as? [String: Any] }

  @Test func theFamilysMasterPromptIsTheSystemAndTheRequestHasDescriptionAndTerms() async {
    let recorder = Recorder()
    let outcome = await writer(recorder).write(request(terms: [term("Fog")]))
    let ask = recorder.asks[0]
    #expect(ask.system == masters.families["flux2_9b"]?.system)
    #expect(ask.prompt.contains("un porto all'alba") && ask.prompt.contains("- Fog"))
    #expect(ask.model == nil && ask.images.isEmpty && ask.options == PMWriter.genericOptions)
    #expect(fields(recorder)?["prompt"] as? String == "A quiet harbour at dawn.")
    #expect(outcome.status == "Prompt sent to Generation." && outcome.sent)
  }

  @Test func theNegativePromptIsWrittenOnlyForAFamilyThatReadsOne() async {
    let recorder = Recorder()
    recorder.answer = .text(#"{"prompt": "a cat", "negative": "blurry"}"#)
    _ = await writer(recorder).write(request("sdxl_base_v0.9"))
    #expect(fields(recorder)?["prompt"] as? String == "a cat" && fields(recorder)?["negativePrompt"] as? String == "blurry")
    let flux = Recorder()
    flux.answer = .text(#"{"prompt": "a cat", "negative": "blurry"}"#)
    _ = await writer(flux).write(request("flux1"))
    #expect(fields(flux)?["prompt"] as? String == "a cat" && fields(flux)?["negativePrompt"] == nil)
  }

  @Test func theBooruSwitchReachesTheSystemPrompt() async {
    let recorder = Recorder()
    _ = await writer(recorder).write(request("v1", booru: true))
    #expect(recorder.asks[0].system?.hasSuffix(masters.families["v1"]!.booruSystem!) == true)
  }

  @Test func aFamilyWithoutAMasterPromptSendsNothing() async {
    let recorder = Recorder()
    let outcome = await writer(recorder).write(request("ideogram_4"))
    #expect(outcome.status == "This model has no master prompt." && !outcome.sent)
    #expect(recorder.asks.isEmpty && recorder.contributions.isEmpty)
  }

  @Test func whenTheLanguageModelFailsItsReasonIsShownAndNothingIsSent() async {
    let recorder = Recorder()
    recorder.answer = .failure("No language model is chosen.")
    let outcome = await writer(recorder).write(request())
    #expect(outcome.status == "No language model is chosen." && !outcome.sent)
    #expect(recorder.contributions.isEmpty)
  }

  @Test func anAnswerWithoutAPromptIsReportedAndNothingIsSent() async {
    let recorder = Recorder()
    recorder.answer = .text("<think>only thoughts")
    let outcome = await writer(recorder).write(request())
    #expect(outcome.status == "The language model's answer had no prompt in it." && recorder.contributions.isEmpty)
  }

  @Test func whatTheAppSaysAboutTheContributionIsShown() async {
    let recorder = Recorder()
    recorder.accepted = ["type": "ok", "conflicts": 2]
    #expect(await writer(recorder).write(request()).status == "Prompt sent. 2 conflict(s) waiting in the app.")
    recorder.accepted = ["type": "error", "text": "The plug-in is not active."]
    let refused = await writer(recorder).write(request())
    #expect(refused.status == "The plug-in is not active." && !refused.sent)
    recorder.accepted = nil
    #expect(await writer(recorder).write(request()).status == "No answer from the app.")
  }

  // MARK: Qwen Image 2.1

  private let t2i = "mlx/Qwen-Image-2.1-PE-T2I-MLX-4bit"
  private let i2i = "mlx/Qwen-Image-2.1-PE-I2I-MLX-4bit"
  private let files = ["system_prompt.txt": "T2I SYSTEM", "system_prompt_edit.txt": "EDIT SYSTEM"]

  @Test func theEnhancerGetsItsOwnSystemPromptTheRequestAndQwensSettings() async {
    let recorder = Recorder()
    recorder.answer = .text(#"<think>hm</think>{"rewritten_prompt": "a long rich prompt", "wh_ratio": "3:2"}"#)
    let outcome = await writer(recorder, files: files).write(
      request("qwen_image_2.1", terms: [term("Fog")], models: [model(t2i), model(i2i)]))
    let ask = recorder.asks[0]
    #expect(ask.model == t2i && ask.system == "T2I SYSTEM" && ask.images.isEmpty)
    #expect(ask.options.thinking == true && ask.options.maxTokens == 16256 && ask.options.timeout == 900)
    #expect(ask.prompt.contains("- Fog"))
    #expect(fields(recorder)?["prompt"] as? String == "a long rich prompt")
    #expect(fields(recorder)?["negativePrompt"] == nil)
    #expect(outcome.ratio == "3:2" && outcome.status == "Prompt sent to Generation. Suggested format: 3:2")
  }

  @Test func withAStartImageTheI2IEnhancerGetsThePicturesAndAMoodboardAloneDoesNot() async {
    let recorder = Recorder()
    _ = await writer(recorder, files: files).write(
      request("qwen_image_2.1", start: "/s.png", moodboard: ["/m.png"], models: [model(t2i), model(i2i)]))
    #expect(recorder.asks[0].model == i2i && recorder.asks[0].images == ["/s.png", "/m.png"] && recorder.asks[0].system == "EDIT SYSTEM")
    let again = Recorder()
    _ = await writer(again, files: files).write(request("qwen_image_2.1", moodboard: ["/m.png"], models: [model(t2i), model(i2i)]))
    #expect(again.asks[0].model == t2i && again.asks[0].images.isEmpty)
  }

  @Test func withoutTheEnhancerTheGenericModelIsUsedAndTheLineSaysSoAndThatTheMasterPromptIsProvisional() async {
    let recorder = Recorder()
    let outcome = await writer(recorder).write(request("qwen_image_2.1"))
    #expect(recorder.asks[0].model == nil && recorder.asks[0].system == masters.families["qwen_image_2.1"]?.system)
    #expect(outcome.status.contains("Prompt enhancer (T2I) not found") && outcome.status.contains("provisional"))
    let noSystem = Recorder()
    let second = await writer(noSystem, files: [:]).write(request("qwen_image_2.1", models: [model(t2i)]))
    #expect(second.status.contains("has no system_prompt.txt") && noSystem.asks[0].model == nil)
  }

  @Test func aFailureOfTheEnhancerIsShownAndDoesNotFallBackInSilence() async {
    let recorder = Recorder()
    recorder.answer = .failure("The language model needs about 6 GB and only 2 GB is free.")
    let outcome = await writer(recorder, files: files).write(request("qwen_image_2.1", models: [model(t2i)]))
    #expect(outcome.status.contains("only 2 GB is free") && !outcome.sent && recorder.asks.count == 1)
  }

  // MARK: The scene

  @Test func theSceneComesBackAsTextInTheInterfaceLanguage() async throws {
    let recorder = Recorder()
    recorder.answer = .text("A fisherman mends a net. A foggy pier at dawn.")
    #expect(try await writer(recorder).scene().get() == "A fisherman mends a net. A foggy pier at dawn.")
    #expect(recorder.asks[0].prompt.contains("English") && recorder.asks[0].system == PMWriter.sceneSystem)
    #expect(recorder.contributions.isEmpty)  // the scene goes in the description, not to Generation
  }

  @Test func aFailedSceneSaysWhy() async {
    let recorder = Recorder()
    recorder.answer = .failure("No language model is chosen.")
    #expect(await writer(recorder).scene() == .failure(.init(text: "No scene: No language model is chosen.")))
  }

  @Test func bothLanguagesHaveEveryWord() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true) && L.isDefined(key, italian: false), "\(key)")
    }
    // The placeholders match in the two languages.
    for key in L.Key.allCases {
      let count = { (text: String) in text.components(separatedBy: "%").count }
      #expect(count(L.text(key, italian: true)) == count(L.text(key, italian: false)), "\(key)")
    }
  }
}
```

- [ ] **Step 2: Verificare che fallisca**

Run: `cd "/Users/existenz/Software developement/DT Hub/Plugins/PromptMaster" && swift test 2>&1 | grep -E "error:" | head -2`
Expected: errori di compilazione (`cannot find 'PMWriter' in scope`, `cannot find 'L' in scope`).

- [ ] **Step 3: Implementare**

`PMWriter.write` sceglie con `PEPlanner`, manda una sola domanda (al PE con il suo system prompt, le immagini e le opzioni di Qwen; altrimenti al modello scelto con il master prompt della famiglia e `maxTokens: 2048`), legge la risposta e fa un solo `contribute` con `fields` (il negativo solo se la famiglia lo legge); un errore dell'LLM o una risposta senza prompt non manda niente e non ripiega di nascosto. La riga di stato dice cosa è successo e, se serve, che si è usato il modello generico o che il master prompt è provvisorio. Lo shuffle della scena è una domanda a parte, nella lingua dell'interfaccia, e non contribuisce.

**`Plugins/PromptMaster/Sources/PromptMaster/Strings.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation

/// The words of the plug-in, in Italian and English. A plug-in bundle holds only its library, so there are no
/// `.strings` files: the table is here (the tests check both languages are complete).
enum L {
  enum Key: CaseIterable {
    // The list
    case terms, search, photo, art, shuffle, noMatches, addTerm, addTermPlaceholder, removeTerm, customTerm
    // The description
    case description, descriptionPlaceholder, sceneShuffle, sceneWriting
    // The chosen terms and the button
    case chosen, clearAll, removeChosen, noneChosen, writePrompt, writing, booru
    // What happened
    case sent, sentWithConflicts, notAnswered, noMasterPrompt, emptyAnswer, llmFailed, sceneFailed
    case enhancerModelMissingT2I, enhancerModelMissingI2I, enhancerSystemMissing, ratio, provisional
    case unreadableFile, unknownSchema, customNotSaved
  }

  static var systemIsItalian: Bool {
    Locale.preferredLanguages.first?.hasPrefix("it") ?? false
  }

  static func text(_ key: Key, italian: Bool = systemIsItalian) -> String {
    (italian ? it : en)[key] ?? en[key] ?? "\(key)"
  }

  static func isDefined(_ key: Key, italian: Bool) -> Bool { (italian ? it : en)[key] != nil }

  static func format(_ key: Key, _ args: CVarArg..., italian: Bool = systemIsItalian) -> String {
    String(format: text(key, italian: italian), arguments: args)
  }

  private static let en: [Key: String] = [
    .terms: "Terms", .search: "Search", .photo: "Photo", .art: "Art", .shuffle: "Shuffle",
    .noMatches: "No term matches.", .addTerm: "Add a term", .addTermPlaceholder: "Your term",
    .removeTerm: "Remove this term", .customTerm: "Your own term",
    .description: "Description", .descriptionPlaceholder: "Subject, scene and action, in any language",
    .sceneShuffle: "Shuffle scene", .sceneWriting: "Thinking of a scene…",
    .chosen: "Chosen terms", .clearAll: "Clear the list", .removeChosen: "Remove", .noneChosen: "No term chosen yet.",
    .writePrompt: "Write prompt", .writing: "Writing…", .booru: "Booru tags",
    .sent: "Prompt sent to Generation.", .sentWithConflicts: "Prompt sent. %d conflict(s) waiting in the app.",
    .notAnswered: "No answer from the app.", .noMasterPrompt: "This model has no master prompt.",
    .emptyAnswer: "The language model's answer had no prompt in it.", .llmFailed: "%@",
    .sceneFailed: "No scene: %@",
    .enhancerModelMissingT2I: "Prompt enhancer (T2I) not found in the models folder: using the language model you chose.",
    .enhancerModelMissingI2I: "Prompt enhancer (I2I) not found in the models folder: using the language model you chose.",
    .enhancerSystemMissing: "The enhancer %@ has no system_prompt.txt in its folder: using the language model you chose.",
    .ratio: "Suggested format: %@", .provisional: "This family's master prompt is provisional.",
    .unreadableFile: "%@ cannot be read: using the copy built into the plug-in.",
    .unknownSchema: "%@ has a layout this plug-in does not know: using the copy built into the plug-in.",
    .customNotSaved: "Could not save your term.",
  ]

  private static let it: [Key: String] = [
    .terms: "Termini", .search: "Cerca", .photo: "Foto", .art: "Arte", .shuffle: "Shuffle",
    .noMatches: "Nessun termine corrisponde.", .addTerm: "Aggiungi un termine", .addTermPlaceholder: "Il tuo termine",
    .removeTerm: "Togli questo termine", .customTerm: "Un tuo termine",
    .description: "Descrizione", .descriptionPlaceholder: "Soggetto, scena e azione, in qualsiasi lingua",
    .sceneShuffle: "Shuffle scena", .sceneWriting: "Penso a una scena…",
    .chosen: "Termini scelti", .clearAll: "Svuota l'elenco", .removeChosen: "Togli", .noneChosen: "Nessun termine scelto.",
    .writePrompt: "Scrivi prompt", .writing: "Sto scrivendo…", .booru: "Tag booru",
    .sent: "Prompt inviato alla Generazione.", .sentWithConflicts: "Prompt inviato. %d conflitti in attesa nell'app.",
    .notAnswered: "Nessuna risposta dall'app.", .noMasterPrompt: "Questo modello non ha un master prompt.",
    .emptyAnswer: "La risposta del modello linguistico non conteneva un prompt.", .llmFailed: "%@",
    .sceneFailed: "Nessuna scena: %@",
    .enhancerModelMissingT2I: "Il prompt enhancer (T2I) non è nella cartella dei modelli: uso il modello linguistico scelto.",
    .enhancerModelMissingI2I: "Il prompt enhancer (I2I) non è nella cartella dei modelli: uso il modello linguistico scelto.",
    .enhancerSystemMissing: "Nella cartella di %@ manca system_prompt.txt: uso il modello linguistico scelto.",
    .ratio: "Formato consigliato: %@", .provisional: "Il master prompt di questa famiglia è provvisorio.",
    .unreadableFile: "%@ non si legge: uso la copia incorporata nel plug-in.",
    .unknownSchema: "%@ ha un formato che questo plug-in non conosce: uso la copia incorporata.",
    .customNotSaved: "Non si è potuto salvare il tuo termine.",
  ]
}
```

**`Plugins/PromptMaster/Sources/PromptMaster/PMWriter.swift`** (file nuovo o riscritto per intero):

```swift
import DTHubPluginKit
import Foundation

/// The "Write prompt" button and the scene Shuffle, apart from the screen: choose the language model, build the request,
/// read the answer and contribute it to the Generation tab. It talks to the app through closures, so a test can stand in
/// for it.
@MainActor
struct PMWriter {
  /// `host.askLanguageModelAnswer(_:images:system:model:options:)`.
  var ask: @MainActor (_ prompt: String, _ images: [String], _ system: String?, _ model: String?, _ options: DTHubLLMOptions) async -> DTHubLLMAnswer
  /// `host.contribute`.
  var contribute: @MainActor ([String: Any]) async -> [String: Any]?
  var italian = L.systemIsItalian
  var folderSize: (String) -> Int64 = PEPlanner.folderSize
  var readFile: (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) }

  /// What the tab knows when the button is pressed.
  struct Request {
    var family: String
    var masters: MasterPrompts
    var description: String
    var terms: [SelectedTerm]
    var booru: Bool
    var startImage: String?
    var moodboard: [String]
    var languageModels: [DTHubLanguageModel]
  }

  struct Outcome: Equatable {
    /// The lines to show under the button.
    var status: String
    /// The format a prompt enhancer suggested, when it did.
    var ratio: String?
    var sent: Bool
  }

  /// The generic model has to say a prompt, maybe with its negative: room for that.
  static let genericOptions = DTHubLLMOptions(maxTokens: 2048)

  func write(_ request: Request) async -> Outcome {
    let master = request.masters.families[request.family]
    let plan = PEPlanner.plan(
      family: request.family, startImage: request.startImage, moodboard: request.moodboard,
      languageModels: request.languageModels, folderSize: folderSize, readFile: readFile)
    var notes: [String] = []
    let answer: DTHubLLMAnswer
    switch plan {
    case .enhancer(let enhancer):
      answer = await ask(
        BriefBuilder.request(description: request.description, terms: request.terms), enhancer.images, enhancer.system,
        enhancer.model, enhancer.options)
    case .generic(let reason):
      guard let brief = BriefBuilder.make(
        family: request.family, masters: request.masters, description: request.description, terms: request.terms,
        booru: request.booru)
      else { return Outcome(status: L.text(.noMasterPrompt, italian: italian), ratio: nil, sent: false) }
      switch reason {
      case .modelMissing(let kind)?:
        notes.append(L.text(kind == .t2i ? .enhancerModelMissingT2I : .enhancerModelMissingI2I, italian: italian))
      case .systemPromptMissing(let model)?:
        notes.append(L.format(.enhancerSystemMissing, model, italian: italian))
      case nil:
        break
      }
      answer = await ask(brief.prompt, [], brief.system, nil, Self.genericOptions)
    }

    let text: String
    switch answer {
    case .failure(let reason):
      return Outcome(status: ([L.format(.llmFailed, reason, italian: italian)] + notes).joined(separator: " "), ratio: nil, sent: false)
    case .text(let value):
      text = value
    }
    guard let parsed = AnswerParser.parse(text) else {
      return Outcome(status: ([L.text(.emptyAnswer, italian: italian)] + notes).joined(separator: " "), ratio: nil, sent: false)
    }
    // The negative prompt is written only where the family reads one.
    var fields: [String: Any] = ["prompt": parsed.prompt]
    if master?.negative == true, let negative = parsed.negative { fields["negativePrompt"] = negative }
    let result = await contribute(["fields": fields])
    var lines = [Self.describe(result, italian: italian)] + notes
    if let ratio = parsed.ratio { lines.append(L.format(.ratio, ratio, italian: italian)) }
    if master?.provisional == true, case .generic = plan { lines.append(L.text(.provisional, italian: italian)) }
    return Outcome(status: lines.joined(separator: " "), ratio: parsed.ratio, sent: Self.wasAccepted(result))
  }

  static func wasAccepted(_ answer: [String: Any]?) -> Bool {
    guard let answer else { return false }
    return answer["type"] as? String != "error"
  }

  static func describe(_ answer: [String: Any]?, italian: Bool) -> String {
    guard let answer else { return L.text(.notAnswered, italian: italian) }
    if answer["type"] as? String == "error" { return answer["text"] as? String ?? L.text(.notAnswered, italian: italian) }
    let conflicts = answer["conflicts"] as? Int ?? 0
    return conflicts > 0 ? L.format(.sentWithConflicts, conflicts, italian: italian) : L.text(.sent, italian: italian)
  }

  // MARK: The scene Shuffle

  static let sceneSystem = """
    You invent ideas for images. Reply with exactly two short sentences: the first names a subject and what it is doing, \
    the second describes the setting. Be concrete and visual; no title, no quotation marks, no lists.
    """

  func scene() async -> Result<String, SceneFailure> {
    let language = italian ? "Italian" : "English"
    let answer = await ask(
      "Invent a subject with an action, and a setting, for an image. Write the two sentences in \(language).", [],
      Self.sceneSystem, nil, DTHubLLMOptions(temperature: 1.0, maxTokens: 300))
    switch answer {
    case .failure(let reason):
      return .failure(SceneFailure(text: L.format(.sceneFailed, reason, italian: italian)))
    case .text(let value):
      guard let scene = AnswerParser.parse(value)?.prompt else {
        return .failure(SceneFailure(text: L.format(.sceneFailed, L.text(.emptyAnswer, italian: italian), italian: italian)))
      }
      return .success(scene)
    }
  }

  struct SceneFailure: Error, Equatable { var text: String }
}
```

- [ ] **Step 4: Verificare**

Run: `cd "/Users/existenz/Software developement/DT Hub/Plugins/PromptMaster" && swift test 2>&1 | grep -E "Test run with|error:|✘"`
Expected: `Test run with 76 tests in 8 suites passed`.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A Plugins/PromptMaster && git commit -m "feat(pm): scrittura del prompt e shuffle della scena, con le stringhe

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Lo stato del tab e la memoria

**Files:**
- `Plugins/PromptMaster/Sources/PromptMaster/PMState.swift`, `Plugins/PromptMaster/Sources/PromptMaster/PMStore.swift`, `Plugins/PromptMaster/Tests/PromptMasterTests/PMStateTests.swift`

**Interfaces:**
- Consumes: `PMData`, `TermTree`, `CustomTermsStore`, `Shuffler`, `StyleMode` (Task 1–3); `PMWriter.Request` e `L` (Task 5).
- Produces: `PMSession` e `PMStore` (`UserDefaults`, chiave `com.exiztenz.dthub.promptmaster.state.v1`); `PMState` (`@MainActor`, `ObservableObject`): `description`, `selection`, `mode`, `booru`, `openGroups`, `openCategories`, `query`, `visibleTree`, `customTerms`, `status`, `isWriting`, `isMakingScene`, `active`, `addingIn`, `newTermText`; `update(family:startImage:moodboard:languageModels:)`, `master`, `hasBooruSwitch`, `selectedTerms`, `chosenCount(inGroup:)`/`(inCategory:)`, `isOpen(group:)`/`(category:)`, `toggleOpen(group:)`/`(category:)`, `setChosen(_:_:)`, `clearAll()`, `shuffle()`, `addCustomTerm()`, `removeCustomTerm(_:)`, `canWrite`, `writeRequest`.

- [ ] **Step 1: Scrivere il test**

**`Plugins/PromptMaster/Tests/PromptMasterTests/PMStateTests.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation
import Testing

@testable import PromptMaster

@MainActor
@Suite("The state of the tab")
struct PMStateTests {
  private func defaults() -> UserDefaults { UserDefaults(suiteName: "pm-state-\(UUID().uuidString)")! }
  private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("pm-state-\(UUID().uuidString)") }

  private func state(
    defaults: UserDefaults? = nil, custom: URL? = nil, shuffled: [String] = ["fr_closeup", "lq_soft_diffused"]
  ) -> PMState {
    let state = PMState(
      store: PMStore(defaults: defaults ?? self.defaults()), customStore: CustomTermsStore(folder: custom ?? folder()),
      italian: true, shuffler: { _, _, _ in shuffled })
    state.update(family: "flux2_9b", startImage: nil, moodboard: [], languageModels: [])
    state.active = true
    return state
  }

  @Test func choosingATermAddsItToTheListOfChosenTermsInTheOrderOfTheList() {
    let state = state()
    state.setChosen("fr_closeup", true)
    state.setChosen("fr_extreme_closeup", true)
    #expect(state.selectedTerms.map(\.id) == ["fr_extreme_closeup", "fr_closeup"])
    #expect(state.chosenCount(inCategory: "framing") == 2 && state.chosenCount(inGroup: "A") == 2)
    state.setChosen("fr_closeup", false)
    #expect(state.selectedTerms.map(\.id) == ["fr_extreme_closeup"])
  }

  @Test func clearingTheListEmptiesTheSelection() {
    let state = state()
    state.setChosen("fr_closeup", true)
    state.clearAll()
    #expect(state.selection.isEmpty && state.selectedTerms.isEmpty)
  }

  @Test func theShuffleReplacesTheSelectionWithWhatTheShufflerPicksForTheFamilyAndMode() {
    var seen: (Set<String>, StyleMode)?
    let state = PMState(
      store: PMStore(defaults: defaults()), customStore: CustomTermsStore(folder: folder()), italian: true,
      shuffler: { _, hidden, mode in seen = (hidden, mode); return ["lq_soft_diffused"] })
    state.update(family: "z_image", startImage: nil, moodboard: [], languageModels: [])
    state.setChosen("fr_closeup", true)
    state.mode = .art
    state.shuffle()
    #expect(state.selection == ["lq_soft_diffused"])
    #expect(seen?.1 == .art && seen?.0.contains("typography_text") == true)  // z_image hides it
  }

  @Test func theFamilyHidesCategoriesAndTheSelectionOfAHiddenOneIsNotSent() {
    let state = state()
    #expect(state.visibleTree.groups.flatMap(\.categories).contains { $0.id == "typography_text" })
    let typography = PMData.embeddedDatabase.categories.first { $0.id == "typography_text" }!.terms[0].id
    state.setChosen(typography, true)
    #expect(state.selectedTerms.map(\.id) == [typography])
    state.update(family: "z_image", startImage: nil, moodboard: [], languageModels: [])
    #expect(!state.visibleTree.groups.flatMap(\.categories).contains { $0.id == "typography_text" })
    #expect(state.selectedTerms.isEmpty && state.selection == [typography])  // kept for when the family changes back
  }

  @Test func theSearchNarrowsTheListAndOpensIt() {
    let state = state()
    #expect(!state.isOpen(group: "A"))
    state.query = "primissimo"
    #expect(state.visibleTree.isFiltered && state.isOpen(group: "A") && state.isOpen(category: "framing"))
    #expect(state.visibleTree.groups.flatMap(\.categories).flatMap(\.terms).contains { $0.id == "fr_extreme_closeup" })
    state.query = ""
    #expect(!state.isOpen(group: "A"))
  }

  @Test func groupsAndCategoriesOpenAndClose() {
    let state = state()
    state.toggleOpen(group: "A")
    state.toggleOpen(category: "framing")
    #expect(state.isOpen(group: "A") && state.isOpen(category: "framing"))
    state.toggleOpen(group: "A")
    #expect(!state.isOpen(group: "A"))
  }

  // MARK: Custom terms

  @Test func aTermTheUserTypesJoinsItsCategoryAndIsChosen() {
    let state = state()
    state.addingIn = "framing"
    state.newTermText = " dal basso a sinistra "
    state.addCustomTerm()
    let term = state.customTerms[0]
    #expect(term.text == "dal basso a sinistra" && state.selection.contains(term.id) && state.addingIn == nil)
    #expect(state.visibleTree.groups[0].categories[0].terms.last?.id == term.id)
    #expect(state.isOpen(category: "framing"))
    state.removeCustomTerm(term.id)
    #expect(state.customTerms.isEmpty && !state.selection.contains(term.id))
  }

  @Test func anEmptyNewTermJustClosesTheField() {
    let state = state()
    state.addingIn = "framing"
    state.newTermText = "   "
    state.addCustomTerm()
    #expect(state.customTerms.isEmpty && state.addingIn == nil && state.status.isEmpty)
  }

  @Test func ifTheFileCannotBeWrittenTheStatusSaysSo() throws {
    let custom = folder()
    try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: custom.appendingPathComponent("custom-terms.json"))
    let state = state(custom: custom)
    state.addingIn = "framing"
    state.newTermText = "x"
    state.addCustomTerm()
    #expect(state.status == "Non si è potuto salvare il tuo termine." && state.customTerms.isEmpty)
  }

  // MARK: The button

  @Test func theButtonNeedsTheTabOnATextOrATermAndAMasterPrompt() {
    let state = state()
    #expect(!state.canWrite)  // nothing yet
    state.description = "  \n "
    #expect(!state.canWrite)
    state.description = "un porto"
    #expect(state.canWrite)
    state.description = ""
    state.setChosen("fr_closeup", true)
    #expect(state.canWrite)
    state.active = false
    #expect(!state.canWrite)
    state.active = true
    state.isWriting = true
    #expect(!state.canWrite)
    state.isWriting = false
    state.update(family: "ideogram_4", startImage: nil, moodboard: [], languageModels: [])
    #expect(!state.canWrite && state.writeRequest?.family == "ideogram_4")
  }

  @Test func theRequestCarriesWhatTheTabKnowsAndTheBooruSwitchOnlyWhereItExists() throws {
    let state = state()
    state.description = "ciao"
    state.booru = true
    state.update(family: "v1", startImage: "/s.png", moodboard: ["/m.png"], languageModels: [])
    var request = try #require(state.writeRequest)
    #expect(request.booru && request.startImage == "/s.png" && request.moodboard == ["/m.png"] && request.description == "ciao")
    state.update(family: "flux1", startImage: nil, moodboard: [], languageModels: [])
    request = try #require(state.writeRequest)
    #expect(!request.booru)
  }

  // MARK: Memory

  @Test func theSessionComesBackInANewState() {
    let shared = defaults()
    let custom = folder()
    let first = state(defaults: shared, custom: custom)
    first.description = "un porto all'alba"
    first.setChosen("fr_closeup", true)
    first.mode = .art
    first.booru = true
    first.toggleOpen(group: "B")
    first.toggleOpen(category: "light_source")
    let second = state(defaults: shared, custom: custom)
    #expect(second.description == "un porto all'alba" && second.selection == ["fr_closeup"])
    #expect(second.mode == .art && second.booru && second.openGroups == ["B"] && second.openCategories == ["light_source"])
    #expect(second.query.isEmpty)
  }

  @Test func aSessionThatCannotBeReadStartsEmpty() {
    let shared = defaults()
    shared.set(Data("garbage".utf8), forKey: PMStore.key)
    #expect(state(defaults: shared).selection.isEmpty)
  }

  @Test func aFileThatCouldNotBeReadAtStartIsMentionedInTheStatus() throws {
    let root = folder()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: root.appendingPathComponent("prompt-database.json"))
    let data = PMData.load(folder: root)
    let state = PMState(
      data: data, store: PMStore(defaults: defaults()), customStore: CustomTermsStore(folder: folder()), italian: false)
    #expect(state.status == "prompt-database.json cannot be read: using the copy built into the plug-in.")
  }
}
```

- [ ] **Step 2: Verificare che fallisca**

Run: `cd "/Users/existenz/Software developement/DT Hub/Plugins/PromptMaster" && swift test 2>&1 | grep -E "error:" | head -2`
Expected: errori di compilazione (`cannot find 'PMState' in scope`, `cannot find 'PMStore' in scope`).

- [ ] **Step 3: Implementare**

Lo stato carica i dati una sola volta all'avvio; la famiglia (dal `context`) decide categorie nascoste e master prompt, ma una selezione fatta in una categoria nascosta resta (non si manda); lo Shuffle sostituisce tutta la selezione; un termine personale aggiunto si sceglie da solo; il pulsante vale solo con il plug-in acceso, qualcosa da cui scrivere, un master prompt e senza una scrittura in corso; lo Shuffle è iniettabile per i test.

**`Plugins/PromptMaster/Sources/PromptMaster/PMStore.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation

/// What the tab remembers between runs: the text, the chosen terms, the Shuffle mode, the booru switch and which
/// groups and categories are open. The search is not kept.
struct PMSession: Codable, Equatable {
  var description = ""
  var selection: [String] = []
  var mode: StyleMode = .photo
  var booru = false
  var openGroups: [String] = []
  var openCategories: [String] = []
}

/// The session in `UserDefaults`, under a key of its own.
struct PMStore {
  static let key = "com.exiztenz.dthub.promptmaster.state.v1"

  var defaults: UserDefaults = .standard
  var key: String = PMStore.key

  func save(_ session: PMSession) {
    guard let data = try? JSONEncoder().encode(session) else { return }
    defaults.set(data, forKey: key)
  }

  /// The saved session; a first run, or one that cannot be read, starts empty.
  func load() -> PMSession {
    guard let data = defaults.data(forKey: key), let session = try? JSONDecoder().decode(PMSession.self, from: data) else {
      return PMSession()
    }
    return session
  }
}
```

**`Plugins/PromptMaster/Sources/PromptMaster/PMState.swift`** (file nuovo o riscritto per intero):

```swift
import DTHubPluginKit
import Foundation
import SwiftUI

/// What the tab shows and edits.
@MainActor
final class PMState: ObservableObject {
  let data: PMData
  private let store: PMStore
  private let customStore: CustomTermsStore
  private let shuffler: (PromptDatabase, Set<String>, StyleMode) -> [String]
  let italian: Bool

  @Published var description: String { didSet { persist() } }
  @Published var selection: Set<String> { didSet { persist() } }
  @Published var mode: StyleMode { didSet { persist() } }
  @Published var booru: Bool { didSet { persist() } }
  @Published var openGroups: Set<String> { didSet { persist() } }
  @Published var openCategories: Set<String> { didSet { persist() } }
  @Published var query = "" { didSet { rebuildVisible() } }
  @Published private(set) var customTerms: [CustomTerm]
  @Published private(set) var visibleTree: TermTree
  @Published var status = ""
  @Published var isWriting = false
  @Published var isMakingScene = false
  @Published var active = false
  /// The category where the user is typing a new term, and what they typed.
  @Published var addingIn: String?
  @Published var newTermText = ""

  private(set) var family: String?
  private(set) var startImage: String?
  private(set) var moodboard: [String] = []
  private(set) var languageModels: [DTHubLanguageModel] = []
  private var fullTree: TermTree

  init(
    data: PMData = PMData.load(), store: PMStore = PMStore(), customStore: CustomTermsStore = CustomTermsStore(),
    italian: Bool = L.systemIsItalian,
    shuffler: @escaping (PromptDatabase, Set<String>, StyleMode) -> [String] = { database, hidden, mode in
      var generator = SystemRandomNumberGenerator()
      return Shuffler.pick(database: database, hidden: hidden, mode: mode, using: &generator)
    }
  ) {
    self.data = data
    self.store = store
    self.customStore = customStore
    self.italian = italian
    self.shuffler = shuffler
    let session = store.load()
    description = session.description
    selection = Set(session.selection)
    mode = session.mode
    booru = session.booru
    openGroups = Set(session.openGroups)
    openCategories = Set(session.openCategories)
    let custom = customStore.load()
    customTerms = custom
    let tree = TermTree(database: data.database, custom: custom, hidden: [], italian: italian)
    fullTree = tree
    visibleTree = tree
    status = data.warnings.map { Self.text(for: $0, italian: italian) }.joined(separator: " ")
    rebuild()
  }

  private static func text(for warning: DataWarning, italian: Bool) -> String {
    switch warning {
    case .unreadable(let file): return L.format(.unreadableFile, file, italian: italian)
    case .unknownSchema(let file): return L.format(.unknownSchema, file, italian: italian)
    }
  }

  // MARK: What the app says

  /// The `context` message: the family decides which categories are hidden and which master prompt is used.
  func update(family: String?, startImage: String?, moodboard: [String], languageModels: [DTHubLanguageModel]) {
    let changed = family != self.family
    self.family = family
    self.startImage = startImage
    self.moodboard = moodboard
    self.languageModels = languageModels
    if changed { rebuild() }
  }

  var master: FamilyPrompt? { family.flatMap { data.masters.families[$0] } }
  var hasBooruSwitch: Bool { family.map(PMFamilies.withBooruSwitch.contains) ?? false }
  var hiddenCategories: Set<String> { Set(master?.hiddenCategories ?? []) }

  // MARK: The list

  private func rebuild() {
    fullTree = TermTree(database: data.database, custom: customTerms, hidden: hiddenCategories, italian: italian)
    rebuildVisible()
  }

  private func rebuildVisible() {
    visibleTree = fullTree.filtered(by: query, database: data.database, italian: italian)
  }

  var selectedTerms: [SelectedTerm] { fullTree.selectedTerms(selection) }

  func chosenCount(inGroup id: String) -> Int { fullTree.chosenCount(inGroup: id, selection: selection) }
  func chosenCount(inCategory id: String) -> Int { fullTree.chosenCount(inCategory: id, selection: selection) }

  func isOpen(group id: String) -> Bool { visibleTree.isFiltered || openGroups.contains(id) }
  func isOpen(category id: String) -> Bool { visibleTree.isFiltered || openCategories.contains(id) }

  func toggleOpen(group id: String) { if !openGroups.insert(id).inserted { openGroups.remove(id) } }
  func toggleOpen(category id: String) { if !openCategories.insert(id).inserted { openCategories.remove(id) } }

  func setChosen(_ id: String, _ chosen: Bool) {
    if chosen { selection.insert(id) } else { selection.remove(id) }
  }

  func clearAll() { selection = [] }

  /// A new random selection (it replaces the old one), from the categories the family keeps.
  func shuffle() { selection = Set(shuffler(data.database, hiddenCategories, mode)) }

  // MARK: The user's own terms

  /// Adds the term the user typed to `categoryID` and chooses it.
  func addCustomTerm() {
    guard let category = addingIn else { return }
    do {
      let term = try customStore.add(text: newTermText, to: category)
      customTerms = customStore.load()
      rebuild()
      selection.insert(term.id)
      openCategories.insert(category)
      addingIn = nil
      newTermText = ""
    } catch CustomTermsStore.Failure.empty {
      addingIn = nil
      newTermText = ""
    } catch {
      status = L.text(.customNotSaved, italian: italian)
    }
  }

  func removeCustomTerm(_ id: String) {
    do {
      try customStore.remove(id: id)
      customTerms = customStore.load()
      selection.remove(id)
      rebuild()
    } catch {
      status = L.text(.customNotSaved, italian: italian)
    }
  }

  // MARK: The button

  /// There is something to write from, a master prompt to write with, and the plug-in is on and not busy.
  var canWrite: Bool {
    active && !isWriting && master != nil
      && (!description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedTerms.isEmpty)
  }

  var writeRequest: PMWriter.Request? {
    guard let family else { return nil }
    return PMWriter.Request(
      family: family, masters: data.masters, description: description, terms: selectedTerms,
      booru: booru && hasBooruSwitch, startImage: startImage, moodboard: moodboard, languageModels: languageModels)
  }

  private func persist() {
    store.save(
      PMSession(
        description: description, selection: selection.sorted(), mode: mode, booru: booru,
        openGroups: openGroups.sorted(), openCategories: openCategories.sorted()))
  }
}
```

- [ ] **Step 4: Verificare**

Run: `cd "/Users/existenz/Software developement/DT Hub/Plugins/PromptMaster" && swift test 2>&1 | grep -E "Test run with|error:|✘"`
Expected: `Test run with 90 tests in 9 suites passed`.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A Plugins/PromptMaster && git commit -m "feat(pm): stato del tab e memoria

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Il tab, il plug-in, il bundle e i documenti

**Files:**
- `Plugins/PromptMaster/README.md`, `Plugins/PromptMaster/Scripts/build.sh`, `Plugins/PromptMaster/Sources/PromptMaster/PromptMasterPlugin.swift`, `Plugins/PromptMaster/Sources/PromptMaster/PromptMasterView.swift`, `Plugins/PromptMaster/Sources/PromptMaster/TermListView.swift`, `docs/superpowers/backlog.md`

**Interfaces:**
- Consumes: `PMState`, `PMWriter`, `L`, `PMFamilies` (Task 1–6); `DTHubPlugin`, `DTHubPluginEntry`, `DTHubHost.askLanguageModelAnswer`/`contribute`, `DTHubContext` (il kit); i componenti di `DTHubDesign` (`DSPanelHeader`, `dsPanel`, `DSPillButtonStyle`, `DSCheckboxToggleStyle`, `DSGroupHeader`, `DS.remove`, `DS.accent`).
- Produces: `TermListView` (la card di sinistra), `PromptMasterView` (le due colonne), `PromptMasterPlugin` (manifest con le 13 famiglie, simbolo `wand.and.stars`) e `PromptMasterEntry` (`@objc(PromptMasterEntry)`); `Scripts/build.sh OUT` → `OUT/PromptMaster.dthubplugin` firmato ad-hoc.

- [ ] **Step 1: Scrivere le viste, il plug-in e lo script del bundle**

La card di sinistra ha tre livelli (gruppi, categorie, termini con casella) con il numero dei termini scelti, Foto/Arte, Shuffle, ricerca e «Aggiungi un termine» in fondo a ogni categoria; a destra la descrizione con «Shuffle scena» e i termini scelti con la X arancione (`DS.remove`) che svuota l'elenco, l'interruttore «Tag booru» (solo `v1` e `sdxl_base_v0.9`), la riga di stato e «Scrivi prompt». Gli stati sono quelli di `PMState`; le viste non hanno logica. `PromptMasterPlugin` passa il `context` allo stato, accende e spegne con `activate`/`deactivate` e fa le due domande all'LLM con `PMWriter`.

**`Plugins/PromptMaster/Sources/PromptMaster/TermListView.swift`** (file nuovo o riscritto per intero):

```swift
import DTHubDesign
import SwiftUI

/// The left card: groups → categories → terms with a check box, the Photo/Art switch, the Shuffle and the search.
struct TermListView: View {
  @ObservedObject var state: PMState

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "list.bullet.indent", title: L.text(.terms, italian: state.italian))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        controls
        searchField
        if state.visibleTree.groups.isEmpty {
          Text(L.text(.noMatches, italian: state.italian)).font(.callout).foregroundStyle(.secondary).padding(.top, 6)
        }
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(state.visibleTree.groups) { group in GroupSection(state: state, group: group) }
          }
          .padding(.bottom, DS.panelPadding)
        }
        .scrollIndicators(.hidden)
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }

  private var controls: some View {
    HStack(spacing: DS.controlGap) {
      HStack(spacing: 4) {
        modeButton(.photo, L.text(.photo, italian: state.italian), "camera")
        modeButton(.art, L.text(.art, italian: state.italian), "paintpalette")
      }
      Spacer(minLength: 0)
      Button { state.shuffle() } label: {
        HStack(spacing: DS.pillIconGap) {
          Image(systemName: "dice")
          Text(L.text(.shuffle, italian: state.italian))
        }
      }
      .buttonStyle(DSPillButtonStyle())
    }
  }

  private func modeButton(_ mode: StyleMode, _ title: String, _ icon: String) -> some View {
    Button { state.mode = mode } label: {
      HStack(spacing: DS.pillIconGap) {
        Image(systemName: icon)
        Text(title)
      }
    }
    .buttonStyle(DSPillButtonStyle(prominent: state.mode == mode))
  }

  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
      TextField(L.text(.search, italian: state.italian), text: $state.query).textFieldStyle(.plain)
      if !state.query.isEmpty {
        Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
          .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 10).padding(.vertical, 7)
    .background(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
  }
}

/// A row that opens and closes: a chevron, a title and how many terms of it are chosen.
private struct DisclosureRow: View {
  let title: String
  let chosen: Int
  let isOpen: Bool
  let isGroup: Bool
  let help: String?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
          .rotationEffect(.degrees(isOpen ? 90 : 0))
        if isGroup {
          DSGroupHeader(title: title, prominent: true)
        } else {
          Text(title).font(.subheadline.weight(.semibold))
        }
        Spacer(minLength: 0)
        if chosen > 0 {
          Text("\(chosen)").font(.caption.weight(.semibold)).monospacedDigit()
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(Capsule().fill(DS.accent.opacity(0.25)))
        }
      }
      .padding(.vertical, isGroup ? 7 : 4)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help ?? "")
  }
}

private struct GroupSection: View {
  @ObservedObject var state: PMState
  let group: GroupNode

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DisclosureRow(
        title: group.title, chosen: state.chosenCount(inGroup: group.id), isOpen: state.isOpen(group: group.id),
        isGroup: true, help: nil
      ) { state.toggleOpen(group: group.id) }
      if state.isOpen(group: group.id) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(group.categories) { category in CategorySection(state: state, category: category) }
        }
        .padding(.leading, 14)
      }
    }
  }
}

private struct CategorySection: View {
  @ObservedObject var state: PMState
  let category: CategoryNode

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DisclosureRow(
        title: category.title, chosen: state.chosenCount(inCategory: category.id),
        isOpen: state.isOpen(category: category.id), isGroup: false, help: category.details
      ) { state.toggleOpen(category: category.id) }
      if state.isOpen(category: category.id) {
        VStack(alignment: .leading, spacing: 5) {
          ForEach(category.terms) { term in TermRow(state: state, term: term) }
          if !state.visibleTree.isFiltered { addTerm }
        }
        .padding(.leading, 18).padding(.top, 2).padding(.bottom, 8)
      }
    }
  }

  @ViewBuilder private var addTerm: some View {
    if state.addingIn == category.id {
      HStack(spacing: 6) {
        TextField(L.text(.addTermPlaceholder, italian: state.italian), text: $state.newTermText)
          .textFieldStyle(.roundedBorder).onSubmit { state.addCustomTerm() }
        Button { state.addCustomTerm() } label: { Image(systemName: "checkmark.circle.fill") }
          .buttonStyle(.plain).foregroundStyle(DS.accent)
      }
    } else {
      Button {
        state.newTermText = ""
        state.addingIn = category.id
      } label: {
        HStack(spacing: 5) {
          Image(systemName: "plus")
          Text(L.text(.addTerm, italian: state.italian))
        }
        .font(.caption).foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
  }
}

private struct TermRow: View {
  @ObservedObject var state: PMState
  let term: TermNode

  var body: some View {
    HStack(spacing: 6) {
      Toggle(isOn: Binding(get: { state.selection.contains(term.id) }, set: { state.setChosen(term.id, $0) })) {
        Text(term.title).font(.callout).fixedSize(horizontal: false, vertical: true)
      }
      .toggleStyle(DSCheckboxToggleStyle())
      if term.isCustom {
        Image(systemName: "person.fill").font(.caption2).foregroundStyle(.secondary)
          .help(L.text(.customTerm, italian: state.italian))
        Spacer(minLength: 0)
        Button { state.removeCustomTerm(term.id) } label: { Image(systemName: "minus.circle.fill") }
          .buttonStyle(.plain).foregroundStyle(DS.remove).help(L.text(.removeTerm, italian: state.italian))
      }
    }
  }
}
```

**`Plugins/PromptMaster/Sources/PromptMaster/PromptMasterView.swift`** (file nuovo o riscritto per intero):

```swift
import DTHubDesign
import SwiftUI

/// The tab, in the look of the app: the list of terms on the left; on the right the description and the chosen terms
/// with the button that writes the prompt.
struct PromptMasterView: View {
  @ObservedObject var state: PMState
  let write: () -> Void
  let makeScene: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: DS.groupGap) {
      TermListView(state: state).frame(minWidth: 340, maxWidth: .infinity)
      VStack(spacing: DS.groupGap) {
        descriptionCard
        chosenCard
      }
      .frame(minWidth: 340, maxWidth: .infinity)
    }
    .padding(DS.groupGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var descriptionCard: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "text.alignleft", title: L.text(.description, italian: state.italian))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        ZStack(alignment: .topLeading) {
          TextEditor(text: $state.description)
            .font(.body).scrollContentBackground(.hidden).padding(6)
          if state.description.isEmpty {
            Text(L.text(.descriptionPlaceholder, italian: state.italian)).foregroundStyle(.tertiary)
              .padding(.horizontal, 11).padding(.vertical, 14).allowsHitTesting(false)
          }
        }
        .frame(minHeight: 110, maxHeight: 190)
        .background(RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
        HStack {
          Spacer()
          Button(action: makeScene) {
            if state.isMakingScene {
              HStack(spacing: DS.pillIconGap) {
                ProgressView().controlSize(.small)
                Text(L.text(.sceneWriting, italian: state.italian))
              }
            } else {
              HStack(spacing: DS.pillIconGap) {
                Image(systemName: "dice")
                Text(L.text(.sceneShuffle, italian: state.italian))
              }
            }
          }
          .buttonStyle(DSPillButtonStyle())
          .disabled(state.isMakingScene || state.isWriting || !state.active)
        }
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }

  private var chosenCard: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "checklist", title: L.text(.chosen, italian: state.italian))
        .overlay(alignment: .trailing) {
          Button { state.clearAll() } label: {
            Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(DS.remove)
          }
          .buttonStyle(.plain).padding(.trailing, DS.panelPadding)
          .help(L.text(.clearAll, italian: state.italian))
          .disabled(state.selection.isEmpty)
        }
      VStack(alignment: .leading, spacing: DS.rowGap) {
        if state.selectedTerms.isEmpty {
          Text(L.text(.noneChosen, italian: state.italian)).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(state.selectedTerms) { term in
              HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                  Text(term.title).font(.callout).foregroundStyle(term.isNegative ? DS.remove : Color.primary)
                  Text(term.categoryTitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { state.setChosen(term.id, false) } label: { Image(systemName: "xmark").font(.caption) }
                  .buttonStyle(.plain).foregroundStyle(.secondary).help(L.text(.removeChosen, italian: state.italian))
              }
            }
          }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
        if state.hasBooruSwitch {
          Toggle(L.text(.booru, italian: state.italian), isOn: $state.booru).toggleStyle(DSCheckboxToggleStyle())
        }
        if !state.status.isEmpty {
          Text(state.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        Button(action: write) {
          if state.isWriting {
            HStack(spacing: DS.pillIconGap) {
              ProgressView().controlSize(.small)
              Text(L.text(.writing, italian: state.italian))
            }
          } else {
            HStack(spacing: DS.pillIconGap) {
              Image(systemName: "sparkles")
              Text(L.text(.writePrompt, italian: state.italian))
            }
          }
        }
        .buttonStyle(DSPillButtonStyle(prominent: true))
        .disabled(!state.canWrite)
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
    .frame(maxHeight: .infinity)
  }
}
```

**`Plugins/PromptMaster/Sources/PromptMaster/PromptMasterPlugin.swift`** (file nuovo o riscritto per intero):

```swift
import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class PromptMasterPlugin: DTHubPlugin {
  /// Its tab is grey on the other families: those are the ones Prompt Master has a master prompt for.
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.promptmaster", name: "Prompt Master", version: "1.0", symbol: "wand.and.stars",
    families: PMFamilies.all)
  private let state = PMState()
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(
      rootView: PromptMasterView(
        state: state, write: { [weak self] in self?.write() }, makeScene: { [weak self] in self?.makeScene() }))
  }

  func start(host: DTHubHost) {
    self.host = host
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      if let context = try? JSONDecoder().decode(DTHubContext.self, from: message) {
        state.update(
          family: context.family, startImage: context.startImage, moodboard: context.moodboard ?? [],
          languageModels: context.languageModels ?? [])
      }
      return nil
    case "activate":
      state.active = true
      return nil
    case "deactivate":
      state.active = false
      return nil
    default:
      return DTHubMessage.bare("unsupported")
    }
  }

  private func makeWriter(_ host: DTHubHost) -> PMWriter {
    PMWriter(
      ask: { prompt, images, system, model, options in
        await host.askLanguageModelAnswer(prompt, images: images, system: system, model: model, options: options)
      },
      contribute: { await host.contribute($0) }, italian: state.italian)
  }

  private func write() {
    guard state.canWrite, let host, let request = state.writeRequest else { return }
    state.isWriting = true
    state.status = ""
    let writer = makeWriter(host)
    Task {
      state.status = await writer.write(request).status
      state.isWriting = false
    }
  }

  private func makeScene() {
    guard !state.isMakingScene, !state.isWriting, let host else { return }
    state.isMakingScene = true
    let writer = makeWriter(host)
    Task {
      switch await writer.scene() {
      case .success(let scene):
        state.description = scene
        state.status = ""
      case .failure(let failure):
        state.status = failure.text
      }
      state.isMakingScene = false
    }
  }
}

@objc(PromptMasterEntry)
public final class PromptMasterEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { PromptMasterPlugin() }
}
```

**`Plugins/PromptMaster/Scripts/build.sh`** (file nuovo o riscritto per intero):

```bash
#!/bin/zsh
# build.sh OUT_FOLDER
# Builds the Prompt Master plug-in into OUT_FOLDER/PromptMaster.dthubplugin (ad-hoc signed). Needs the Swift toolchain;
# run from anywhere.
set -e
HERE="${0:A:h}"
OUT="${1:?usage: build.sh OUT_FOLDER}"
VERSION="1.0"
mkdir -p "$OUT"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
swift build -c release --package-path "$HERE/.." --scratch-path "$SCRATCH" >/dev/null
"$HERE/../../../PluginKit/Scripts/make-bundle.sh" "$(find "$SCRATCH" -name libPromptMaster.dylib | head -1)" \
  "$OUT/PromptMaster.dthubplugin" com.exiztenz.dthub.promptmaster PromptMaster "$VERSION" PromptMasterEntry
echo "$OUT/PromptMaster.dthubplugin"
```

```bash
cd "/Users/existenz/Software developement/DT Hub" && chmod +x Plugins/PromptMaster/Scripts/build.sh
```

- [ ] **Step 2: Compilare, provare e fare il bundle**

Run: `cd "/Users/existenz/Software developement/DT Hub/Plugins/PromptMaster" && swift build 2>&1 | grep -E "error|Build comp" && swift test 2>&1 | grep -E "Test run with|error:|✘" && rm -rf /tmp/pm-out && Scripts/build.sh /tmp/pm-out | tail -1`
Expected: `Build complete!`, `Test run with 90 tests in 9 suites passed` e `/tmp/pm-out/PromptMaster.dthubplugin`.

Run: `B=/tmp/pm-out/PromptMaster.dthubplugin/Contents/MacOS/PromptMaster; echo "design con alias: $(nm -gU $B | grep -c PromptMasterDesign) · design senza alias: $(nm -gU $B | grep -c DTHubDesign) · kit senza alias: $(nm -gU $B | grep -c 14DTHubPluginKit) · kit con alias: $(nm -gU $B | grep -c PromptMasterKit)"`
Expected: un numero maggiore di 0, poi `0`, poi `0`, poi un numero maggiore di 0.

- [ ] **Step 3: Caricarlo con il caricatore vero dell'app**

Un test **temporaneo** (non si committa) carica il bundle con `BundlePluginLoader`, come fa l'app.

```bash
cd "/Users/existenz/Software developement/DT Hub/Packages" && cat > Tests/PluginHostTests/ZZPromptMasterLoadTests.swift <<'EOF'
import AppKit
import Foundation
import HubCore
import HubKit
import Testing

@testable import PluginHost

@MainActor
struct ZZPromptMasterLoadTests {
  @Test func theBuiltBundleLoadsInTheRealLoader() async throws {
    let bundle = URL(fileURLWithPath: "/tmp/pm-out/PromptMaster.dthubplugin")
    let info = try PluginBundleReader.read(bundle)
    let host = RecordingHost()
    let plugin = try BundlePluginLoader().load(bundle, info: info, host: host)
    #expect(plugin.manifest.id == "com.exiztenz.dthub.promptmaster" && plugin.manifest.name == "Prompt Master")
    #expect(plugin.manifest.families?.count == 13 && plugin.manifest.families?.contains("qwen_image_2.1") == true)
    #expect(plugin.manifest.supports(family: "flux2_9b") && !plugin.manifest.supports(family: "ideogram_4"))
    #expect(plugin.viewController is NSViewController)
    let context = try JSONEncoder().encode(
      PluginContext(
        model: "m.ckpt", family: "flux2_9b", parameters: GenerationParameters(), tempFolder: "/tmp",
        startImage: "/tmp/s.png", moodboard: ["/tmp/m.png"],
        languageModels: [PluginLanguageModel(name: "a/b", path: "/m/a/b", supportsImages: true)]))
    #expect(await plugin.send(context).flatMap(PluginMessageType.of) == PluginMessageType.ok)
    #expect(await plugin.send(PluginMessageType.bare("activate")).flatMap(PluginMessageType.of) == PluginMessageType.ok)
    #expect(await plugin.send(PluginMessageType.bare("fly")).flatMap(PluginMessageType.of) == PluginMessageType.unsupported)
  }
}
EOF
swift test --filter ZZPromptMasterLoadTests 2>&1 | grep -E "Test run with|error:|✘"; rm Tests/PluginHostTests/ZZPromptMasterLoadTests.swift; git -C .. status --short
```
Expected: `Test run with 1 test in 1 suite passed`, e `git status` non mostra il file temporaneo.

- [ ] **Step 4: Il README e il backlog**

**`Plugins/PromptMaster/README.md`** (file nuovo o riscritto per intero):

```markdown
# Prompt Master

Un plug-in di DT Hub: un elenco di termini (8 gruppi → 40 categorie → 875 termini di fotografia, luce, colore, stile e
materia) che si scelgono con una casella, più una descrizione libera in qualsiasi lingua. «Scrivi prompt» manda tutto
all'LLM locale dell'app, con il master prompt della famiglia del modello scelto, e il prompt inglese che ne esce finisce
nel campo Prompt della Generazione (e nel negativo, per le famiglie che lo leggono).

- **Foto / Arte** guidano solo lo Shuffle (quali categorie pesca); **Shuffle** sostituisce la selezione con un termine a caso
  per categoria; **Shuffle scena** chiede all'LLM un soggetto e un'ambientazione e li scrive nella descrizione.
- **Termini personali:** «Aggiungi un termine» in fondo a ogni categoria (una stringa, in qualsiasi lingua).
- **Qwen Image 2.1:** se nella cartella dei modelli ci sono i due prompt enhancer ufficiali (`…PE-T2I…` e `…PE-I2I…`, con il loro
  `system_prompt.txt` accanto ai pesi) il plug-in usa quelli al posto dell'LLM generico: l'I2I se c'è un'immagine di partenza
  (il Moodboard non decide, ma con l'I2I le sue immagini vanno al modello). Altrimenti usa l'LLM scelto.
- Funziona con 13 famiglie (`PMFamilies.all`); sulle altre il tab è grigio.

## I dati

Tre file JSON, ognuno con una copia incorporata nel plug-in (un bundle contiene solo la libreria):

| File | Dove | Chi lo scrive |
|---|---|---|
| `prompt-database.json` | `~/Library/Application Support/DT Hub/Data/` (condiviso con altri plug-in) | tu, per aggiornarlo |
| `master-prompts.json` | `…/Data/prompt-master/` | tu (la revisione dei master prompt arriva così) |
| `custom-terms.json` | `…/Data/prompt-master/` | il plug-in |

Vale il file se esiste, si legge, ha `schema` 1 e una `version` non più vecchia di quella incorporata; altrimenti vale la
copia incorporata (e se il file non si legge o ha un layout sconosciuto la riga di stato lo dice). Il plug-in non scrive mai i
primi due. Le copie incorporate e i file di `Data/` si rigenerano con `Scripts/make-prompt-data.py` da Prompt Master 2.0
(che non viene modificato).

## Costruirlo

    Plugins/PromptMaster/Scripts/build.sh OUT_FOLDER     # fa OUT_FOLDER/PromptMaster.dthubplugin
    cd Plugins/PromptMaster && swift test                # 90 test

Poi si aggiunge in DT Hub › Preferenze › Plug-in e si accende dal menu Plug-in dell'header. Richiede il contratto `llm`
con `system`, `model` e `options` e il `context` con `startImage`, `moodboard` e `languageModels` (tappa 1).
```

```diff
diff --git a/docs/superpowers/backlog.md b/docs/superpowers/backlog.md
index 2161266..12f91e3 100644
--- a/docs/superpowers/backlog.md
+++ b/docs/superpowers/backlog.md
@@ -183,3 +183,15 @@ I test di sessione dell'M3 (`GenerationSessionTests`) sono stati resi determinis
 - **Due domande insieme a modelli diversi** (due plug-in, o un doppio clic) non si vedono tra loro: possono caricare due modelli insieme. Esisteva già con lo stesso modello; il caricamento per nome lo rende un po' più probabile.
 - **Un plug-in futuro che contribuisce un Moodboard a ogni contesto** ne rimanderebbe uno nuovo a ogni invio (le immagini cambiano id, il contesto si rimanda): nessun plug-in lo fa oggi.
 - **`startImage` è il file salvato**, senza ritaglio né disegno del Brush: se il PE deve vedere l'immagine incorniciata è una scelta di prodotto.
+
+## Rimandi del plug-in Prompt Master (tappa 2)
+
+- **I master prompt sono provvisori:** quelli di `flux2`, `qwen_image_2.1`, `hidream_i1` e `cosmos2.5_2b` sono scritti senza ricerca, gli altri nove partono dalle note del vecchio PM tradotte; la revisione con le fonti online (spec §9) arriva come nuovo `master-prompts.json`.
+- **Lo Shuffle non pesca i termini personali** e sostituisce tutta la selezione, personali compresi.
+- **I termini a evitare** (categoria «negative_terms») vanno all'LLM in un elenco a parte; nelle famiglie senza negativo l'LLM li trasforma in descrizione positiva. Non c'è un campo negativo scritto a mano.
+- **Il pulsante «Scrivi prompt» non si può annullare** (il contratto non lo prevede); il PE con il thinking può metterci minuti.
+- **Il formato suggerito dal PE** (`wh_ratio`) si mostra e non si applica.
+- **Il kit non ha un `init` pubblico per `DTHubLanguageModel`:** i test lo costruiscono da JSON.
+- **La colla** (`PromptMasterPlugin`, le viste) non ha test automatici; la logica sta in `PMWriter`, `PMState`, `PEPlanner`, `TermTree` e gli altri tipi puri. Il tab è stato visto in un PNG disegnato fuori dall'app, non dal vivo nella finestra.
+- **Provato dal vivo solo con il modello generico locale** (Qwen3-VL-2B): i PE di Qwen (tappa 3) e un modello più grande per i master prompt non ancora.
+
```

- [ ] **Step 5: Provare il tab a mano (con l'app dell'utente chiusa)**

Mettere `/tmp/pm-out/PromptMaster.dthubplugin` in `~/Library/Application Support/DT Hub/Plug-ins/` (o trascinarlo in Preferenze › Plug-in) e accenderlo dal menu Plug-in; scegliere un modello FLUX.2 Klein: il tab «Prompt Master» ha a sinistra i gruppi (chiusi), a destra la descrizione e i termini scelti. Scegliere alcuni termini, scrivere una descrizione in italiano e premere «Scrivi prompt» con un modello linguistico scelto nelle impostazioni: il Prompt della Generazione si riempie con un prompt **in inglese**. Con Pony/SDXL il campo negativo si riempie anche; sul modello Ideogram 4 il tab è grigio.
Expected: i comportamenti descritti (da provare dall'utente).

- [ ] **Step 6: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A Plugins/PromptMaster docs && git commit -m "feat(pm): tab, plug-in, build.sh e README; rimandi nel backlog

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
