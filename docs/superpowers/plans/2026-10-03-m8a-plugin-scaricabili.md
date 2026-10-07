# M8a Plug-in scaricabili — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un plug-in è un bundle `.dthubplugin` scaricato a parte: si aggiunge dalle Preferenze (scelta del file o trascinamento, con conferma), si accende, si carica all'avvio successivo e mostra il proprio tab; il menu Plug-in dell'header lo attiva per il lavoro in corso. **Si installa e si accende un plug-in che mostra il proprio tab.**

**Architecture:**
- **HubKit** riceve i tipi del contratto (`PluginContract`, `PluginManifest`, `PluginVersion`, i messaggi `context` e `notice`).
- **HubCore** riceve la lettura e la validazione dei bundle (`PluginBundleReader`), la cartella dei plug-in con installazione e rimozione (`PluginFolder`), le impostazioni (`PluginSettingsStore`) e il registro (`PluginRegistry`, che dipende dai protocolli `PluginLoading`/`LoadedPlugin`/`PluginHosting`, quindi si prova con un caricatore finto).
- Un nuovo target **PluginHost** (AppKit, `Bundle`, selettori Objective-C) ha il caricatore vero, `BundlePluginLoader`.
- Un nuovo pacchetto **`PluginKit/`** (`DTHubPluginKit`) è ciò che usano gli autori: protocollo, classe base, tipi dei messaggi, un plug-in di esempio e lo script che fa il bundle.
- **L'app**: entitlement, Preferenze › Plug-in, menu Plug-in dell'header, tab del plug-in, avviso dei plug-in.

**Tech Stack:** Swift 6, SwiftUI/AppKit, macOS 26, Xcode 27, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-03-plugin-design.md` (§2–§6, §8–§9; i contributi e i conflitti di §7 sono M8b).

## Global Constraints

- **Repository e dipendenze:**
  - radice `<repo>` (percorsi tra virgolette);
  - branch `m8a-plugin` da `main`;
  - macOS 26, Swift 6, Xcode 27;
  - solo DTBridge importa DrawThings-Swift, solo LLMBridge importa MLX; **`PluginKit/` non dipende da nulla dell'app**.
- **Il bundle:** cartella `.dthubplugin` con `Contents/Info.plist` (`CFBundleIdentifier`, `CFBundleName`, `CFBundleShortVersionString`, `NSPrincipalClass`, `DTHubContract` intero) e `Contents/MacOS/<eseguibile>`. Contratto supportato: **solo la versione 1** (`PluginContract.supported`).
- **Il confine** è fatto di selettori e JSON, senza codice Swift condiviso: `dthubManifest() -> Data`, `dthubMakeViewController() -> NSViewController`, `dthubStart(_ host: NSObject)`, `dthubHandle(_ message: Data, reply:)`; l'host risponde a `dthubSend(_ message: Data, reply:)`. Messaggi `{"type": …}`; un tipo sconosciuto → `{"type":"unsupported"}`; una risposta che non arriva in **5 secondi** è `nil`.
- **Installazione:** il plug-in si copia in `~/Library/Application Support/DT Hub/Plug-ins/<identificatore>.dthubplugin` **solo dopo la conferma** (nome, versione, avviso "esegue codice sul tuo Mac con gli stessi permessi di DT Hub"); versione uguale o più bassa di quella installata = rifiutata, più alta = sostituisce; si toglie `com.apple.quarantine` dalla copia; un plug-in nuovo è **spento**; acceso/spento/rimosso ha effetto al **prossimo avvio** (il codice caricato non si scarica); ⌥ premuto all'avvio non carica nulla.
- **Stati** (`PluginEntry.State`): `off`, `loadsAtNextLaunch`, `skipped`, `loaded`, `failed(PluginError)`. Un bundle rotto o incompatibile è `failed` con il motivo e **non fa cadere l'app**.
- **Menu Plug-in dell'header:** elenca i plug-in **caricati**; l'interruttore li attiva o disattiva per il lavoro in corso (`setActive`); è grigio se la famiglia del modello scelto non è tra quelle del plug-in (famiglia sconosciuta = compatibile). Il tab di un plug-in esiste solo se è caricato, attivo e compatibile.
- **Messaggi di M8a:** app → plug-in `context` (modello, famiglia, parametri, cartella temporanea; mandato quando il plug-in è attivato e quando cambia il modello), `activate`, `deactivate`; plug-in → app `notice` (`text`, `isError`), mostrato per 8 secondi sopra la finestra. `contribute` e `llm` sono di M8b.
- **Firma:** entitlement `com.apple.security.cs.disable-library-validation` (file `DTHub.entitlements` nella radice, `CODE_SIGN_ENTITLEMENTS` in tutte e due le configurazioni). Le compilazioni con `CODE_SIGNING_ALLOWED=NO` non hanno hardened runtime e caricano i bundle comunque.
- **Il link alla pagina GitHub** dei plug-in è `PluginText.downloadPage`: `nil` finché la pagina non esiste (il link non compare).
- **Stringhe:** ogni testo visibile in `App/Localizable.xcstrings` (en + it), senza riformattare il catalogo; mai una stringa vuota come titolo (il test del catalogo la segnala).
- **La logica sta in HubKit/HubCore/PluginHost (testata); le viste si verificano con la compilazione e con la prova del Task 6.**
- **Blocchi `diff`:** sono le modifiche ai file che esistono già; si salvano in un file e si applicano dalla radice con `git apply --whitespace=nowarn <file>`. I blocchi di codice dei file nuovi si salvano così come sono (lo script `make-bundle.sh` va reso eseguibile: `chmod +x`).
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Se l'app dell'utente è aperta** non lanciare altre istanze con i suoi dati (stesso identificatore): compilare con `-derivedDataPath /tmp/m8a-dd` e provare con una cartella dati a parte (`CFFIXED_USER_HOME`, Task 6).
- **Fuori da M8a:** i messaggi `contribute` e `llm`, i campi in teal, i conflitti e la pipeline (M8b); un catalogo o l'installazione da indirizzo web; lo scaricamento a caldo del codice; i plug-in veri (Prompt Master, Sphere Light, Qwen).

## Review Focus

- **Un bundle sbagliato non fa cadere l'app né si carica:** contratto non supportato, chiave mancante, `Info.plist` illeggibile, identificatore del manifesto diverso da quello del bundle, classe principale mancante (test `eachRequiredKeyIsChecked`, `aContractThisAppDoesNotKnowIsRefused`, `aBundleWhoseCodeSaysAnotherIdentifierIsRefused`, `aBundleWithoutThePrincipalClassIsRefused`, `aPluginThatFailsToLoadIsReportedAndTheOthersLoad`, Task 2–4).
- **Installare non lascia mezzi guasti:** una copia fallita non toglie la versione vecchia, nessuna cartella di appoggio resta, la stessa versione o una più bassa è rifiutata (test `aHigherVersionReplacesAndTheSameOrALowerOneIsRefused`, Task 2).
- **La quarantena** del download si toglie dalla copia, bundle e file (test `theDownloadQuarantineMarkIsTakenOffTheCopy`, Task 2); non è provata su un file scaricato davvero.
- **Accendere/spegnere/rimuovere ha effetto al prossimo avvio** e nulla si carica prima; ⌥ non carica nulla (test `turningOneOnOrOffIsSavedAndTakesEffectAtTheNextLaunch`, `skippingLoadsNothing`, `removingForgetsThePluginAndItsSwitch`, Task 3).
- **Un plug-in che non risponde** non blocca l'app: la risposta scade a 5 secondi e vale `nil` (nessun test: `BundleLoadedPlugin.send` e `DTHubHost.send` — il revisore lo controlli a occhio).
- **Le viste dell'app** (Preferenze › Plug-in, menu dell'header, tab, avviso, lettura di ⌥ all'avvio, entitlement) non hanno test: il revisore le legga con attenzione.

---

### Task 1: I tipi del contratto (HubKit)

**Files:**
- Create: `Packages/Sources/HubKit/Plugin/PluginManifest.swift`, `Packages/Sources/HubKit/Plugin/PluginMessages.swift`
- Test: `Packages/Tests/HubKitTests/PluginContractTests.swift` (nuovo)

**Interfaces:**
- Produces (HubKit, `public`):
  - `enum PluginContract`: `supported: Set<Int>` ([1]), `current` (1), `infoKey` ("DTHubContract"), `bundleExtension` ("dthubplugin");
  - `struct PluginManifest: Codable, Equatable, Sendable` (`id`, `name`, `version` ("0"), `contract`, `symbol` ("puzzlepiece.extension"), `families: [String]?`; lettura permissiva: bastano `id`, `name`, `contract`; `supports(family:)`: nil/vuota = tutte, famiglia sconosciuta = vale);
  - `struct PluginVersion: Comparable, Equatable, Sendable` (`init(_ text: String)`, confronto numero per numero: "1.10" > "1.9", "1.0" == "1.0.0");
  - `enum PluginMessageType` (`context`, `activate`, `deactivate`, `notice`, `unsupported`, `ok`; `of(_ data: Data) -> String?`; `bare(_ type: String) -> Data`);
  - `struct PluginContext: Codable, Equatable, Sendable` (`type`, `model`, `family`, `parameters: GenerationParameters`, `tempFolder`) e `struct PluginNotice: Codable, Equatable, Sendable` (`type`, `text`, `isError` (false); lettura permissiva: serve `text`).
- Consumes: `GenerationParameters` (esistente).

- [ ] **Step 1: Creare il ramo e scrivere i test**

```bash
cd "<repo>" && git switch main && git switch -c m8a-plugin
```

```swift
import Foundation
import Testing

@testable import HubKit

struct PluginContractTests {
  @Test func theManifestNeedsOnlyTheIdTheNameAndTheContract() throws {
    let manifest = try JSONDecoder().decode(
      PluginManifest.self, from: Data(#"{"id":"com.x.p","name":"P","contract":1}"#.utf8))
    #expect(manifest == PluginManifest(id: "com.x.p", name: "P", version: "0", contract: 1))
    #expect(manifest.symbol == "puzzlepiece.extension" && manifest.families == nil)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(PluginManifest.self, from: Data(#"{"name":"P","contract":1}"#.utf8))
    }
  }

  @Test func aPluginWorksWithTheFamiliesItNamesAndWithAnUnknownOne() {
    var manifest = PluginManifest(id: "a", name: "A")
    #expect(manifest.supports(family: "flux2_9b") && manifest.supports(family: nil))
    manifest.families = ["qwen21"]
    #expect(manifest.supports(family: "qwen21"))
    #expect(!manifest.supports(family: "flux2_9b"))
    #expect(manifest.supports(family: nil), "an unknown family: everything applies")
    manifest.families = []
    #expect(manifest.supports(family: "flux2_9b"), "an empty list means all")
  }

  @Test func versionsAreComparedNumberByNumber() {
    #expect(PluginVersion("1.10") > PluginVersion("1.9"))
    #expect(PluginVersion("2") > PluginVersion("1.9.9"))
    #expect(PluginVersion("1.0") == PluginVersion("1.0.0"))
    #expect(!(PluginVersion("1.2") > PluginVersion("1.2")))
    #expect(PluginVersion("0") < PluginVersion("0.0.1"))
  }

  @Test func theMessageTypeIsReadFromTheJSON() {
    #expect(PluginMessageType.of(Data(#"{"type":"notice","text":"x"}"#.utf8)) == "notice")
    #expect(PluginMessageType.of(Data("nonsense".utf8)) == nil)
    #expect(PluginMessageType.of(PluginMessageType.bare("ok")) == "ok")
  }

  @Test func aNoticeAsksForTheTextOnly() throws {
    let notice = try JSONDecoder().decode(PluginNotice.self, from: Data(#"{"type":"notice","text":"Ready"}"#.utf8))
    #expect(notice.text == "Ready" && notice.isError == false)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(PluginNotice.self, from: Data(#"{"type":"notice"}"#.utf8))
    }
  }

  @Test func theContextCarriesTheModelTheParametersAndTheFolder() throws {
    let context = PluginContext(
      model: "m.ckpt", family: "flux2_9b", parameters: GenerationParameters(width: 512), tempFolder: "/tmp/x")
    let data = try JSONEncoder().encode(context)
    #expect(PluginMessageType.of(data) == PluginMessageType.context)
    let back = try JSONDecoder().decode(PluginContext.self, from: data)
    #expect(back == context)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter HubKitTests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'PluginManifest' in scope`.

- [ ] **Step 3: Implementare**

```swift
import Foundation

/// The plug-in contract between the app and a downloaded plug-in bundle (spec: plug-in design §3).
public enum PluginContract {
  /// The contract versions this app understands. A plug-in made for another one is refused.
  public static let supported: Set<Int> = [1]
  public static let current = 1
  /// The `Info.plist` key that holds the contract version a plug-in was made for.
  public static let infoKey = "DTHubContract"
  /// The folder extension of a plug-in bundle.
  public static let bundleExtension = "dthubplugin"
}

/// What a plug-in says about itself (the JSON its `dthubManifest` returns).
public struct PluginManifest: Codable, Equatable, Sendable {
  /// The bundle identifier.
  public var id: String
  public var name: String
  public var version: String
  public var contract: Int
  /// An SF Symbol name for the tab.
  public var symbol: String
  /// Model families it works with; nil or empty = all.
  public var families: [String]?

  public init(
    id: String, name: String, version: String = "0", contract: Int = PluginContract.current,
    symbol: String = "puzzlepiece.extension", families: [String]? = nil
  ) {
    self.id = id
    self.name = name
    self.version = version
    self.contract = contract
    self.symbol = symbol
    self.families = families
  }

  /// Lenient: only the identifier, the name and the contract version are needed.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    contract = try container.decode(Int.self, forKey: .contract)
    version = (try? container.decodeIfPresent(String.self, forKey: .version)) ?? "0"
    symbol = (try? container.decodeIfPresent(String.self, forKey: .symbol)) ?? "puzzlepiece.extension"
    families = try? container.decodeIfPresent([String].self, forKey: .families)
  }

  /// Whether it works with a model family (nil = unknown family: everything applies).
  public func supports(family: String?) -> Bool {
    guard let family, let families, !families.isEmpty else { return true }
    return families.contains(family)
  }
}

/// A dotted version ("1.2.10") compared number by number.
public struct PluginVersion: Comparable, Equatable, Sendable {
  public let parts: [Int]

  public init(_ text: String) {
    parts = text.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
  }

  public static func < (lhs: PluginVersion, rhs: PluginVersion) -> Bool {
    let count = max(lhs.parts.count, rhs.parts.count)
    for index in 0..<count {
      let a = index < lhs.parts.count ? lhs.parts[index] : 0
      let b = index < rhs.parts.count ? rhs.parts[index] : 0
      if a != b { return a < b }
    }
    return false
  }

  public static func == (lhs: PluginVersion, rhs: PluginVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}
```

```swift
import Foundation

/// Messages between the app and a plug-in are JSON objects with a `type`; an unknown type gets
/// `{"type":"unsupported"}` and is not an error.
public enum PluginMessageType {
  public static let context = "context"
  public static let activate = "activate"
  public static let deactivate = "deactivate"
  public static let notice = "notice"
  public static let unsupported = "unsupported"
  public static let ok = "ok"

  /// The `type` of a JSON message, if it is one.
  public static func of(_ data: Data) -> String? {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"] as? String
  }

  /// `{"type": type}` as data.
  public static func bare(_ type: String) -> Data {
    Data(#"{"type":"\#(type)"}"#.utf8)
  }
}

/// App → plug-in: where the app stands (sent when the plug-in is activated and when the model changes).
public struct PluginContext: Codable, Equatable, Sendable {
  public var type = PluginMessageType.context
  public var model: String?
  public var family: String?
  public var parameters: GenerationParameters
  /// A folder the plug-in can exchange image files through.
  public var tempFolder: String

  public init(model: String?, family: String?, parameters: GenerationParameters, tempFolder: String) {
    self.model = model
    self.family = family
    self.parameters = parameters
    self.tempFolder = tempFolder
  }
}

/// Plug-in → app: a line to show to the user.
public struct PluginNotice: Codable, Equatable, Sendable {
  public var type = PluginMessageType.notice
  public var text: String
  public var isError: Bool

  public init(text: String, isError: Bool = false) {
    self.text = text
    self.isError = isError
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    text = try container.decode(String.self, forKey: .text)
    isError = (try? container.decodeIfPresent(Bool.self, forKey: .isError)) ?? false
  }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubKit `82 tests … passed` (6 nuovi), HubCore 363, DTBridge 66, Catalog 6, LLMBridge 6 (totale **523**).

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: i tipi del contratto dei plug-in (manifesto, versioni, messaggi)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Leggere, trovare, installare e togliere i bundle (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Plugins/PluginError.swift`, `PluginBundleReader.swift`, `PluginFolder.swift`, `PluginSettings.swift`
- Test: `Packages/Tests/HubCoreTests/PluginFolderTests.swift` (nuovo)

**Interfaces:**
- Consumes: `PluginContract`, `PluginVersion` (Task 1).
- Produces (HubCore, `public`):
  - `enum PluginError: Error, Equatable, Sendable`: `unreadable`, `missingKey(String)`, `contractNotSupported(Int)`, `manifestMismatch(String)`, `noEntryPoint`, `loadFailed(String)`, `notNewer(installed: String)`, `cannotWrite(String)`;
  - `struct PluginBundleInfo: Equatable, Sendable` (`identifier`, `name`, `version`, `contract`, `principalClass`) e `PluginBundleReader.read(_ url: URL) throws(PluginError) -> PluginBundleInfo` (legge `Contents/Info.plist` senza caricare il codice; il contratto può essere un intero o un testo; contratto non supportato = errore);
  - `struct PluginSlot: Equatable, Sendable` (`url`, `info: PluginBundleInfo?`, `error: PluginError?`, `identifier`);
  - `struct PluginFolder: Sendable` (`root`, `defaultRoot`, `scan() -> [PluginSlot]` (un identificatore compare una volta: il secondo bundle uguale è `unreadable`), `installed(_:) -> PluginBundleInfo?`, `location(of:) -> URL`, `install(_ source: URL, info:) throws(PluginError)` (versione più alta sostituisce, uguale o più bassa `notNewer`; copia in una cartella di appoggio e poi sposta; toglie la quarantena), `remove(_:) throws(PluginError)`);
  - `struct PluginSettingsStore: Sendable` (`fileURL`, `defaultFileURL`, `enabled() -> Set<String>` (file mancante o illeggibile = vuoto), `save(_:)`).

- [ ] **Step 1: Scrivere i test che falliscono**

```swift
import Foundation
import HubKit
import Testing

@testable import HubCore

/// Fake `.dthubplugin` bundles on disk: an `Info.plist` and nothing else.
enum PluginFixture {
  static func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("PluginFolderTests-\(UUID())", isDirectory: true)
  }

  @discardableResult
  static func bundle(
    in folder: URL, id: String = "com.example.p", name: String = "P", version: String = "1.0", contract: Any? = 1,
    principal: String? = "PEntry", folderName: String? = nil
  ) throws -> URL {
    let url = folder.appendingPathComponent(folderName ?? "\(id).dthubplugin", isDirectory: true)
    try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    var plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleShortVersionString": version]
    if let principal { plist["NSPrincipalClass"] = principal }
    if let contract { plist[PluginContract.infoKey] = contract }
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      .write(to: url.appendingPathComponent("Contents/Info.plist"))
    return url
  }
}

struct PluginBundleReaderTests {
  @Test func aGoodBundleIsRead() throws {
    let url = try PluginFixture.bundle(in: PluginFixture.folder(), version: "2.1")
    let info = try PluginBundleReader.read(url)
    #expect(info == PluginBundleInfo(identifier: "com.example.p", name: "P", version: "2.1", contract: 1, principalClass: "PEntry"))
  }

  @Test func theContractMayBeATextInThePlist() throws {
    let url = try PluginFixture.bundle(in: PluginFixture.folder(), contract: "1")
    #expect(try PluginBundleReader.read(url).contract == 1)
  }

  @Test func aMissingPlistIsUnreadable() {
    #expect(throws: PluginError.unreadable) { try PluginBundleReader.read(PluginFixture.folder()) }
  }

  @Test func eachRequiredKeyIsChecked() throws {
    let folder = PluginFixture.folder()
    let noClass = try PluginFixture.bundle(in: folder, id: "a", principal: nil)
    #expect(throws: PluginError.missingKey("NSPrincipalClass")) { try PluginBundleReader.read(noClass) }
    let noContract = try PluginFixture.bundle(in: folder, id: "b", contract: nil)
    #expect(throws: PluginError.missingKey("DTHubContract")) { try PluginBundleReader.read(noContract) }
    let emptyName = try PluginFixture.bundle(in: folder, id: "c", name: "  ")
    #expect(throws: PluginError.missingKey("CFBundleName")) { try PluginBundleReader.read(emptyName) }
  }

  @Test func aContractThisAppDoesNotKnowIsRefused() throws {
    let url = try PluginFixture.bundle(in: PluginFixture.folder(), contract: 7)
    #expect(throws: PluginError.contractNotSupported(7)) { try PluginBundleReader.read(url) }
  }
}

struct PluginFolderTests {
  @Test func scanListsGoodAndBrokenBundlesAndIgnoresOtherFiles() throws {
    let root = PluginFixture.folder()
    try PluginFixture.bundle(in: root, id: "com.example.good")
    try PluginFixture.bundle(in: root, id: "com.example.old", contract: 9)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("junk.dthubplugin"), withIntermediateDirectories: true)
    try Data().write(to: root.appendingPathComponent("notes.txt"))
    let slots = PluginFolder(root: root).scan()
    #expect(slots.count == 3)
    #expect(slots.first { $0.identifier == "com.example.good" }?.info?.name == "P")
    #expect(slots.first { $0.identifier == "com.example.old" }?.error == .contractNotSupported(9))
    #expect(slots.first { $0.identifier == "junk" }?.error == .unreadable)
  }

  @Test func aMissingFolderHoldsNothing() {
    #expect(PluginFolder(root: PluginFixture.folder()).scan().isEmpty)
  }

  @Test func oneIdentifierAppearsOnce() throws {
    let root = PluginFixture.folder()
    try PluginFixture.bundle(in: root, id: "com.example.p", folderName: "a.dthubplugin")
    try PluginFixture.bundle(in: root, id: "com.example.p", folderName: "b.dthubplugin")
    let slots = PluginFolder(root: root).scan()
    #expect(slots.count == 2)
    #expect(slots.filter { $0.info != nil }.count == 1)
    #expect(slots.first { $0.url.lastPathComponent == "b.dthubplugin" }?.error == .unreadable)
  }

  @Test func installingCopiesTheBundleUnderItsIdentifier() throws {
    let source = try PluginFixture.bundle(in: PluginFixture.folder(), id: "com.example.p")
    let root = PluginFixture.folder()
    let folder = PluginFolder(root: root)
    try folder.install(source, info: PluginBundleReader.read(source))
    #expect(FileManager.default.fileExists(atPath: folder.location(of: "com.example.p").appendingPathComponent("Contents/Info.plist").path))
    #expect(folder.installed("com.example.p")?.version == "1.0")
    #expect(FileManager.default.fileExists(atPath: source.path), "the original is left where it was")
  }

  @Test func aHigherVersionReplacesAndTheSameOrALowerOneIsRefused() throws {
    let root = PluginFixture.folder()
    let folder = PluginFolder(root: root)
    let one = try PluginFixture.bundle(in: PluginFixture.folder(), version: "1.0")
    try folder.install(one, info: PluginBundleReader.read(one))
    let two = try PluginFixture.bundle(in: PluginFixture.folder(), version: "1.1")
    try folder.install(two, info: PluginBundleReader.read(two))
    #expect(folder.installed("com.example.p")?.version == "1.1")
    #expect(throws: PluginError.notNewer(installed: "1.1")) { try folder.install(two, info: PluginBundleReader.read(two)) }
    #expect(throws: PluginError.notNewer(installed: "1.1")) { try folder.install(one, info: PluginBundleReader.read(one)) }
    #expect(folder.installed("com.example.p")?.version == "1.1")
    #expect(folder.scan().count == 1, "no staging folder is left behind")
  }

  @Test func removingTakesTheFolderAway() throws {
    let root = PluginFixture.folder()
    let folder = PluginFolder(root: root)
    let source = try PluginFixture.bundle(in: PluginFixture.folder())
    try folder.install(source, info: PluginBundleReader.read(source))
    try folder.remove("com.example.p")
    #expect(folder.scan().isEmpty)
  }

  @Test func theDownloadQuarantineMarkIsTakenOffTheCopy() throws {
    let source = try PluginFixture.bundle(in: PluginFixture.folder())
    let plist = source.appendingPathComponent("Contents/Info.plist")
    let value = "0081;00000000;Safari;"
    #expect(setxattr(source.path, "com.apple.quarantine", value, value.utf8.count, 0, 0) == 0)
    #expect(setxattr(plist.path, "com.apple.quarantine", value, value.utf8.count, 0, 0) == 0)
    let folder = PluginFolder(root: PluginFixture.folder())
    try folder.install(source, info: PluginBundleReader.read(source))
    let copy = folder.location(of: "com.example.p")
    #expect(getxattr(copy.path, "com.apple.quarantine", nil, 0, 0, 0) < 0)
    #expect(getxattr(copy.appendingPathComponent("Contents/Info.plist").path, "com.apple.quarantine", nil, 0, 0, 0) < 0)
  }
}

struct PluginSettingsTests {
  @Test func nothingIsOnUntilTheUserTurnsItOn() {
    let file = PluginFixture.folder().appendingPathComponent("plugins.json")
    let store = PluginSettingsStore(fileURL: file)
    #expect(store.enabled().isEmpty)
    store.save(["b", "a"])
    #expect(PluginSettingsStore(fileURL: file).enabled() == ["a", "b"])
    try? Data("nonsense".utf8).write(to: file)
    #expect(store.enabled().isEmpty, "an unreadable file means nothing is on")
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter "PluginBundleReader|PluginFolder|PluginSettings" 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'PluginBundleReader' in scope`.

- [ ] **Step 3: Implementare**

```swift
import Foundation

/// Why a plug-in could not be read, installed or loaded. The app turns each case into a sentence.
public enum PluginError: Error, Equatable, Sendable {
  /// The folder is not a readable bundle (no `Contents/Info.plist`).
  case unreadable
  /// A required `Info.plist` key is missing or empty.
  case missingKey(String)
  /// Made for a contract version this app does not understand.
  case contractNotSupported(Int)
  /// The manifest the code returned does not match the bundle (its identifier).
  case manifestMismatch(String)
  /// The principal class is missing or is not the kind the app expects.
  case noEntryPoint
  /// The code could not be loaded.
  case loadFailed(String)
  /// An installed plug-in has the same version or a higher one.
  case notNewer(installed: String)
  /// A file operation failed.
  case cannotWrite(String)
}
```

```swift
import Foundation
import HubKit

/// What `Info.plist` of a plug-in bundle says.
public struct PluginBundleInfo: Equatable, Sendable {
  public let identifier: String
  public let name: String
  public let version: String
  public let contract: Int
  public let principalClass: String

  public init(identifier: String, name: String, version: String, contract: Int, principalClass: String) {
    self.identifier = identifier
    self.name = name
    self.version = version
    self.contract = contract
    self.principalClass = principalClass
  }
}

/// Reads and checks the `Info.plist` of a `.dthubplugin` bundle without loading its code.
public enum PluginBundleReader {
  public static func read(_ url: URL) throws(PluginError) -> PluginBundleInfo {
    let plist = url.appendingPathComponent("Contents/Info.plist")
    guard let data = try? Data(contentsOf: plist),
      let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
      let info = object as? [String: Any]
    else { throw .unreadable }
    func text(_ key: String) throws(PluginError) -> String {
      guard let value = info[key] as? String, !value.trimmingCharacters(in: .whitespaces).isEmpty
      else { throw .missingKey(key) }
      return value
    }
    let identifier = try text("CFBundleIdentifier")
    let name = try text("CFBundleName")
    let principal = try text("NSPrincipalClass")
    let version = (info["CFBundleShortVersionString"] as? String) ?? "0"
    guard let contract = (info[PluginContract.infoKey] as? Int) ?? (info[PluginContract.infoKey] as? String).flatMap(Int.init)
    else { throw .missingKey(PluginContract.infoKey) }
    guard PluginContract.supported.contains(contract) else { throw .contractNotSupported(contract) }
    return PluginBundleInfo(
      identifier: identifier, name: name, version: version, contract: contract, principalClass: principal)
  }
}
```

```swift
import Foundation
import HubKit

/// One `.dthubplugin` found in the folder: what it says, or why it cannot be used.
public struct PluginSlot: Equatable, Sendable {
  public let url: URL
  public let info: PluginBundleInfo?
  public let error: PluginError?

  public init(url: URL, info: PluginBundleInfo?, error: PluginError?) {
    self.url = url
    self.info = info
    self.error = error
  }

  /// The plug-in's identifier, or the folder's name when the bundle cannot be read.
  public var identifier: String { info?.identifier ?? url.deletingPathExtension().lastPathComponent }
}

/// The folder the plug-ins live in (`~/Library/Application Support/DT Hub/Plug-ins`): finds them,
/// copies a new one in, removes one.
public struct PluginFolder: Sendable {
  public let root: URL

  public init(root: URL) {
    self.root = root
  }

  public static var defaultRoot: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("Plug-ins", isDirectory: true)
  }

  /// Every `.dthubplugin` in the folder, read but not loaded; one identifier appears once (the
  /// first folder in name order wins, the others are reported as unreadable duplicates).
  public func scan() -> [PluginSlot] {
    let urls =
      (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    var seen: Set<String> = []
    var slots: [PluginSlot] = []
    for url in urls.filter({ $0.pathExtension == PluginContract.bundleExtension }).sorted(by: {
      $0.lastPathComponent < $1.lastPathComponent
    }) {
      do {
        let info = try PluginBundleReader.read(url)
        guard seen.insert(info.identifier).inserted else {
          slots.append(PluginSlot(url: url, info: nil, error: .unreadable))
          continue
        }
        slots.append(PluginSlot(url: url, info: info, error: nil))
      } catch {
        slots.append(PluginSlot(url: url, info: nil, error: error))
      }
    }
    return slots
  }

  /// The installed bundle with this identifier, if any.
  public func installed(_ identifier: String) -> PluginBundleInfo? {
    scan().compactMap(\.info).first { $0.identifier == identifier }
  }

  /// Where a plug-in with this identifier is kept.
  public func location(of identifier: String) -> URL {
    root.appendingPathComponent("\(identifier).\(PluginContract.bundleExtension)", isDirectory: true)
  }

  /// Copies the bundle in (replacing an older version of the same plug-in) and takes the download
  /// quarantine mark off the copy. The same or a lower version is refused.
  public func install(_ source: URL, info: PluginBundleInfo) throws(PluginError) {
    if let current = installed(info.identifier),
      !(PluginVersion(info.version) > PluginVersion(current.version))
    {
      throw .notNewer(installed: current.version)
    }
    let destination = location(of: info.identifier)
    let manager = FileManager.default
    do {
      try manager.createDirectory(at: root, withIntermediateDirectories: true)
      // Copy first, swap after: a failed copy leaves the old version in place.
      let staging = root.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
      try manager.copyItem(at: source, to: staging)
      Self.removeQuarantine(from: staging)
      if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
      try manager.moveItem(at: staging, to: destination)
    } catch {
      throw .cannotWrite(error.localizedDescription)
    }
  }

  /// Removes the plug-in's folder (a loaded plug-in goes away at the next launch).
  public func remove(_ identifier: String) throws(PluginError) {
    for slot in scan() where slot.identifier == identifier {
      do { try FileManager.default.removeItem(at: slot.url) } catch { throw .cannotWrite(error.localizedDescription) }
    }
  }

  /// Takes `com.apple.quarantine` off a bundle and everything in it.
  static func removeQuarantine(from url: URL) {
    removexattr(url.path, "com.apple.quarantine", XATTR_NOFOLLOW)
    let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
    while let item = enumerator?.nextObject() as? URL {
      removexattr(item.path, "com.apple.quarantine", XATTR_NOFOLLOW)
    }
  }
}
```

```swift
import Foundation

/// Which plug-ins the user turned on (`plugins.json`). A plug-in just installed is off.
public struct PluginSettingsStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public static var defaultFileURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true).appendingPathComponent("plugins.json")
  }

  private struct File: Codable {
    var enabled: [String]
  }

  /// A missing or unreadable file means nothing is on.
  public func enabled() -> Set<String> {
    guard let data = try? Data(contentsOf: fileURL), let file = try? JSONDecoder().decode(File.self, from: data)
    else { return [] }
    return Set(file.enabled)
  }

  public func save(_ identifiers: Set<String>) {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(File(enabled: identifiers.sorted())).write(to: fileURL, options: .atomic)
    } catch {
    }
  }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubCore `376 tests … passed` (13 nuovi); totale 82 + 376 + 66 + 6 + 6 = **536**.

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: lettura, scansione, installazione e rimozione dei bundle dei plug-in, impostazioni

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Il registro dei plug-in (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Plugins/PluginHosting.swift`, `PluginRegistry.swift`
- Test: `Packages/Tests/HubCoreTests/PluginRegistryTests.swift` (nuovo)

**Interfaces:**
- Consumes: Task 1 e 2; `WorkspaceTab` e `GenerationParameters` (esistenti).
- Produces (HubCore, `public`):
  - protocolli `@MainActor`: `LoadedPlugin` (`manifest`, `viewController: AnyObject`, `send(_ message: Data) async -> Data?`), `PluginHosting` (`receive(_ message: Data, from pluginID: String) -> Data`), `PluginLoading` (`load(_ bundle: URL, info:, host:) throws(PluginError) -> any LoadedPlugin`);
  - `struct PluginEntry: Identifiable, Equatable, Sendable` (`id`, `url`, `name`, `version`, `state: State` (`off`, `loadsAtNextLaunch`, `skipped`, `loaded`, `failed(PluginError)`), `isActive`, `manifest`), `struct PluginNoticeItem` (`pluginName`, `text`, `isError`), `struct PluginInstallOffer` (`source`, `info`, `replacing: String?`);
  - `@MainActor @Observable final class PluginRegistry: PluginHosting`: `init(folder:settings:loader:tempFolder:)`, `entries`, `latestNotice`, `family`, `model`, `start(skipping:)`, `offer(for:) throws(PluginError)`, `install(_:) throws(PluginError)`, `remove(_:) throws(PluginError)`, `setEnabled(_:_:)`, `isEnabled(_:)`, `setActive(_:_:)`, `isCompatible(_:)`, `activeTabs` (id `plugin.<identificatore>`), `viewController(forTab:)`, `updateContext(model:family:parameters:)`, `dismissNotice()`.
  - Comportamento: `start` carica solo i plug-in accesi (nessuno con `skipping`), manda `activate` a quelli caricati; `setActive` manda `activate` + `context` o `deactivate`; `updateContext` manda `context` ai plug-in caricati e attivi; un `notice` ricevuto diventa `latestNotice` con il nome del plug-in; un tipo sconosciuto riceve `unsupported`.

- [ ] **Step 1: Scrivere i test che falliscono**

```swift
import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
final class FakeLoadedPlugin: LoadedPlugin {
  let manifest: PluginManifest
  let viewController: AnyObject = NSObject()
  private(set) var sent: [Data] = []

  init(manifest: PluginManifest) { self.manifest = manifest }

  func send(_ message: Data) async -> Data? {
    sent.append(message)
    return PluginMessageType.bare(PluginMessageType.ok)
  }

  var sentTypes: [String] { sent.compactMap { PluginMessageType.of($0) } }
}

@MainActor
final class FakeLoader: PluginLoading {
  var failures: [String: PluginError] = [:]
  var families: [String: [String]] = [:]
  private(set) var loadedIDs: [String] = []
  private(set) var plugins: [String: FakeLoadedPlugin] = [:]
  private(set) var host: (any PluginHosting)?

  func load(_ bundle: URL, info: PluginBundleInfo, host: any PluginHosting) throws(PluginError) -> any LoadedPlugin {
    if let error = failures[info.identifier] { throw error }
    self.host = host
    loadedIDs.append(info.identifier)
    let plugin = FakeLoadedPlugin(
      manifest: PluginManifest(
        id: info.identifier, name: info.name, version: info.version, symbol: "star", families: families[info.identifier]))
    plugins[info.identifier] = plugin
    return plugin
  }
}

@MainActor
struct PluginRegistryTests {
  let root = PluginFixture.folder()
  var settingsFile: URL { root.deletingLastPathComponent().appendingPathComponent("settings-\(root.lastPathComponent).json") }

  func registry(loader: FakeLoader = FakeLoader(), enabled: Set<String> = []) -> PluginRegistry {
    let settings = PluginSettingsStore(fileURL: settingsFile)
    settings.save(enabled)
    return PluginRegistry(folder: PluginFolder(root: root), settings: settings, loader: loader, tempFolder: root)
  }

  func settle() async { try? await Task.sleep(for: .milliseconds(30)) }

  @Test func onlyThePluginsThatAreOnAreLoaded() throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    try PluginFixture.bundle(in: root, id: "b", name: "B")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["b"])
    registry.start()
    #expect(loader.loadedIDs == ["b"])
    #expect(registry.entries.map(\.state) == [.off, .loaded])
    #expect(registry.entries.map(\.isActive) == [false, true])
    #expect(registry.activeTabs.map(\.title) == ["B"])
  }

  @Test func aPluginThatFailsToLoadIsReportedAndTheOthersLoad() throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    try PluginFixture.bundle(in: root, id: "b", name: "B")
    try PluginFixture.bundle(in: root, id: "c", name: "C", contract: 9)
    let loader = FakeLoader()
    loader.failures["a"] = .noEntryPoint
    let registry = registry(loader: loader, enabled: ["a", "b"])
    registry.start()
    #expect(registry.entries.map(\.state) == [.failed(.noEntryPoint), .loaded, .failed(.contractNotSupported(9))])
    #expect(registry.activeTabs.map(\.title) == ["B"])
  }

  @Test func skippingLoadsNothing() throws {
    try PluginFixture.bundle(in: root, id: "a")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["a"])
    registry.start(skipping: true)
    #expect(loader.loadedIDs.isEmpty)
    #expect(registry.entries.map(\.state) == [.skipped])
    #expect(registry.activeTabs.isEmpty)
  }

  @Test func turningOneOnOrOffIsSavedAndTakesEffectAtTheNextLaunch() throws {
    try PluginFixture.bundle(in: root, id: "a")
    try PluginFixture.bundle(in: root, id: "b")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["b"])
    registry.start()
    registry.setEnabled("a", true)
    #expect(registry.entries.first { $0.id == "a" }?.state == .loadsAtNextLaunch)
    #expect(registry.isEnabled("a") && loader.loadedIDs == ["b"], "nothing loads before the next launch")
    registry.setEnabled("a", false)
    #expect(registry.entries.first { $0.id == "a" }?.state == .off)
    registry.setEnabled("b", false)
    #expect(registry.entries.first { $0.id == "b" }?.state == .loaded, "a loaded one stays until the next launch")
    #expect(PluginSettingsStore(fileURL: settingsFile).enabled().isEmpty)
    let again = PluginRegistry(
      folder: PluginFolder(root: root), settings: PluginSettingsStore(fileURL: settingsFile), loader: FakeLoader(),
      tempFolder: root)
    again.start()
    #expect(again.entries.allSatisfy { $0.state == .off })
  }

  @Test func theHeaderSwitchPutsALoadedPluginInOrOutOfTheWork() async throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["a"])
    registry.start()
    registry.updateContext(model: "m.ckpt", family: "flux2_9b", parameters: GenerationParameters(width: 512))
    await settle()
    let plugin = try #require(loader.plugins["a"])
    #expect(plugin.sentTypes.contains(PluginMessageType.activate) && plugin.sentTypes.contains(PluginMessageType.context))
    registry.setActive("a", false)
    #expect(registry.activeTabs.isEmpty)
    await settle()
    #expect(plugin.sentTypes.last == PluginMessageType.deactivate)
    registry.setActive("a", true)
    await settle()
    #expect(registry.activeTabs.map(\.id) == ["plugin.a"])
    #expect(Array(plugin.sentTypes.suffix(2)) == [PluginMessageType.activate, PluginMessageType.context])
  }

  @Test func aPluginForOtherFamiliesHasNoTabWhileAnotherModelIsChosen() throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    let loader = FakeLoader()
    loader.families["a"] = ["qwen21"]
    let registry = registry(loader: loader, enabled: ["a"])
    registry.start()
    registry.updateContext(model: "q.ckpt", family: "qwen21", parameters: GenerationParameters())
    #expect(registry.activeTabs.map(\.title) == ["A"])
    registry.updateContext(model: "f.ckpt", family: "flux2_9b", parameters: GenerationParameters())
    #expect(registry.activeTabs.isEmpty)
    #expect(registry.entries.first.map(registry.isCompatible) == false)
    registry.updateContext(model: nil, family: nil, parameters: GenerationParameters())
    #expect(registry.activeTabs.map(\.title) == ["A"], "an unknown family: everything applies")
  }

  @Test func theTabsViewControllerIsTheLoadedPluginsOne() throws {
    try PluginFixture.bundle(in: root, id: "a")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["a"])
    registry.start()
    #expect(registry.viewController(forTab: "plugin.a") === loader.plugins["a"]?.viewController)
    #expect(registry.viewController(forTab: "plugin.zzz") == nil && registry.viewController(forTab: "generation") == nil)
  }

  @Test func installingOffersWhatWouldHappenAndCopiesAfterTheUserConfirms() throws {
    let registry = registry()
    registry.start()
    let source = try PluginFixture.bundle(in: PluginFixture.folder(), id: "a", name: "A", version: "1.0")
    let offer = try registry.offer(for: source)
    #expect(offer.info.name == "A" && offer.replacing == nil)
    #expect(registry.entries.isEmpty, "nothing is copied before the user confirms")
    try registry.install(offer)
    #expect(registry.entries.map(\.state) == [.off] && registry.entries.map(\.name) == ["A"])
    let newer = try PluginFixture.bundle(in: PluginFixture.folder(), id: "a", name: "A", version: "1.1")
    #expect(try registry.offer(for: newer).replacing == "1.0")
    #expect(throws: PluginError.notNewer(installed: "1.0")) { try registry.offer(for: source) }
    #expect(throws: PluginError.unreadable) { try registry.offer(for: PluginFixture.folder()) }
  }

  @Test func removingForgetsThePluginAndItsSwitch() throws {
    try PluginFixture.bundle(in: root, id: "a")
    let registry = registry(enabled: ["a"])
    registry.start()
    try registry.remove("a")
    #expect(registry.entries.isEmpty)
    #expect(!registry.isEnabled("a"))
  }

  @Test func replacingALoadedPluginKeepsItLoadedUntilTheNextLaunch() throws {
    try PluginFixture.bundle(in: root, id: "a", version: "1.0")
    let registry = registry(enabled: ["a"])
    registry.start()
    let newer = try PluginFixture.bundle(in: PluginFixture.folder(), id: "a", version: "2.0")
    try registry.install(registry.offer(for: newer))
    #expect(registry.entries.map(\.state) == [.loaded])
    #expect(registry.entries.first?.isActive == true)
  }

  @Test func aNoticeFromAPluginIsShownWithItsName() throws {
    try PluginFixture.bundle(in: root, id: "a", name: "Alpha")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["a"])
    registry.start()
    let reply = try #require(loader.host).receive(Data(#"{"type":"notice","text":"Ready","isError":true}"#.utf8), from: "a")
    #expect(PluginMessageType.of(reply) == PluginMessageType.ok)
    #expect(registry.latestNotice?.pluginName == "Alpha" && registry.latestNotice?.text == "Ready")
    #expect(registry.latestNotice?.isError == true)
    registry.dismissNotice()
    #expect(registry.latestNotice == nil)
    let unknown = try #require(loader.host).receive(Data(#"{"type":"fly"}"#.utf8), from: "a")
    #expect(PluginMessageType.of(unknown) == PluginMessageType.unsupported)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter PluginRegistry 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find type 'LoadedPlugin' in scope`.

- [ ] **Step 3: Implementare**

```swift
import Foundation
import HubKit

/// A plug-in whose code is loaded (`PluginLoading` makes one).
@MainActor
public protocol LoadedPlugin: AnyObject {
  var manifest: PluginManifest { get }
  /// The plug-in's tab, an `NSViewController` made once at load (the app casts it).
  var viewController: AnyObject { get }
  /// App → plug-in. nil when the plug-in did not answer in time.
  func send(_ message: Data) async -> Data?
}

/// What a plug-in calls into: the app side of the message channel.
@MainActor
public protocol PluginHosting: AnyObject {
  /// Plug-in → app; the answer goes back to the plug-in.
  func receive(_ message: Data, from pluginID: String) -> Data
}

/// Loads the code of a plug-in bundle (the app's implementation uses `Bundle`; the tests a fake).
@MainActor
public protocol PluginLoading {
  func load(_ bundle: URL, info: PluginBundleInfo, host: any PluginHosting) throws(PluginError) -> any LoadedPlugin
}
```

```swift
import Foundation
import HubKit
import Observation

/// One line of the plug-in list.
public struct PluginEntry: Identifiable, Equatable, Sendable {
  public enum State: Equatable, Sendable {
    /// Installed, turned off.
    case off
    /// Turned on but not loaded yet: it loads at the next launch.
    case loadsAtNextLaunch
    /// Turned on, but plug-ins were skipped at this launch (⌥ held).
    case skipped
    case loaded
    case failed(PluginError)
  }

  public let id: String
  public let url: URL
  public let name: String
  public let version: String
  public var state: State
  /// Whether it counts for the work in hand (the header menu); only a loaded plug-in can be.
  public var isActive: Bool
  public var manifest: PluginManifest?
}

/// A line a plug-in asked the app to show.
public struct PluginNoticeItem: Identifiable, Equatable, Sendable {
  public let id = UUID()
  public let pluginName: String
  public let text: String
  public let isError: Bool
}

/// What the user is about to install.
public struct PluginInstallOffer: Equatable, Sendable {
  public let source: URL
  public let info: PluginBundleInfo
  /// The version that will be replaced, if the plug-in is installed already.
  public let replacing: String?
}

/// The plug-ins of the app: what is installed, turned on, loaded and active (plug-in design §4, §5).
@MainActor
@Observable
public final class PluginRegistry: PluginHosting {
  public private(set) var entries: [PluginEntry] = []
  public private(set) var latestNotice: PluginNoticeItem?
  public private(set) var family: String?
  public private(set) var model: String?

  @ObservationIgnored private let folder: PluginFolder
  @ObservationIgnored private let settings: PluginSettingsStore
  @ObservationIgnored private let loader: any PluginLoading
  @ObservationIgnored private let tempFolder: URL
  @ObservationIgnored private var loaded: [String: any LoadedPlugin] = [:]
  @ObservationIgnored private var skipPlugins = false

  public init(folder: PluginFolder, settings: PluginSettingsStore, loader: any PluginLoading, tempFolder: URL) {
    self.folder = folder
    self.settings = settings
    self.loader = loader
    self.tempFolder = tempFolder
  }

  /// Scans the folder and loads the plug-ins that are on (none when `skipping`, the ⌥ key at launch).
  public func start(skipping: Bool = false) {
    skipPlugins = skipping
    let enabled = settings.enabled()
    entries = folder.scan().map { slot in
      guard let info = slot.info else {
        return PluginEntry(
          id: slot.identifier, url: slot.url, name: slot.identifier, version: "", state: .failed(slot.error ?? .unreadable),
          isActive: false, manifest: nil)
      }
      var entry = PluginEntry(
        id: info.identifier, url: slot.url, name: info.name, version: info.version, state: .off, isActive: false,
        manifest: nil)
      guard enabled.contains(info.identifier) else { return entry }
      if skipping {
        entry.state = .skipped
        return entry
      }
      do {
        let plugin = try loader.load(slot.url, info: info, host: self)
        loaded[info.identifier] = plugin
        entry.state = .loaded
        entry.isActive = true
        entry.manifest = plugin.manifest
      } catch {
        entry.state = .failed((error as? PluginError) ?? .loadFailed(String(describing: error)))
      }
      return entry
    }
    for entry in entries where entry.isActive { send(PluginMessageType.bare(PluginMessageType.activate), to: entry.id) }
  }

  // MARK: Installing

  /// Reads the bundle the user chose and says what would happen; nothing is copied yet.
  public func offer(for source: URL) throws(PluginError) -> PluginInstallOffer {
    let info = try PluginBundleReader.read(source)
    let replacing = folder.installed(info.identifier)?.version
    if let replacing, !(PluginVersion(info.version) > PluginVersion(replacing)) {
      throw .notNewer(installed: replacing)
    }
    return PluginInstallOffer(source: source, info: info, replacing: replacing)
  }

  /// Copies the plug-in in (the user confirmed). A new plug-in is off; a replaced one keeps its switch
  /// and takes effect at the next launch.
  public func install(_ offer: PluginInstallOffer) throws(PluginError) {
    try folder.install(offer.source, info: offer.info)
    refreshEntries()
  }

  public func remove(_ identifier: String) throws(PluginError) {
    try folder.remove(identifier)
    var enabled = settings.enabled()
    enabled.remove(identifier)
    settings.save(enabled)
    refreshEntries()
  }

  /// Turns a plug-in on or off. The code loads at the next launch (and stays loaded until then).
  public func setEnabled(_ identifier: String, _ isOn: Bool) {
    var enabled = settings.enabled()
    if isOn { enabled.insert(identifier) } else { enabled.remove(identifier) }
    settings.save(enabled)
    guard let index = entries.firstIndex(where: { $0.id == identifier }) else { return }
    if isOn {
      if entries[index].state == .off { entries[index].state = skipPlugins ? .skipped : .loadsAtNextLaunch }
    } else if entries[index].state != .loaded {
      entries[index].state = .off
    }
  }

  /// Whether a plug-in is turned on in the settings.
  public func isEnabled(_ identifier: String) -> Bool { settings.enabled().contains(identifier) }

  /// Folder scan after an install or a removal, keeping what is loaded.
  private func refreshEntries() {
    let enabled = settings.enabled()
    let previous = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    entries = folder.scan().map { slot in
      guard let info = slot.info else {
        return PluginEntry(
          id: slot.identifier, url: slot.url, name: slot.identifier, version: "", state: .failed(slot.error ?? .unreadable),
          isActive: false, manifest: nil)
      }
      if let old = previous[info.identifier], old.state == .loaded {
        var kept = old
        kept.state = .loaded
        return kept
      }
      var entry = PluginEntry(
        id: info.identifier, url: slot.url, name: info.name, version: info.version, state: .off, isActive: false,
        manifest: nil)
      if enabled.contains(info.identifier) { entry.state = skipPlugins ? .skipped : .loadsAtNextLaunch }
      return entry
    }
  }

  // MARK: Active plug-ins and tabs

  /// Puts a loaded plug-in in or out of the work in hand (the header menu).
  public func setActive(_ identifier: String, _ isActive: Bool) {
    guard let index = entries.firstIndex(where: { $0.id == identifier }), entries[index].state == .loaded,
      entries[index].isActive != isActive
    else { return }
    entries[index].isActive = isActive
    send(PluginMessageType.bare(isActive ? PluginMessageType.activate : PluginMessageType.deactivate), to: identifier)
    if isActive { sendContext(to: identifier) }
  }

  /// A plug-in works with the chosen model's family (the header menu greys it out otherwise).
  public func isCompatible(_ entry: PluginEntry) -> Bool { entry.manifest?.supports(family: family) ?? false }

  /// The tabs of the plug-ins that are loaded, active and compatible with the model's family.
  public var activeTabs: [WorkspaceTab] {
    entries.compactMap { entry in
      guard entry.state == .loaded, entry.isActive, isCompatible(entry), let manifest = entry.manifest else { return nil }
      return WorkspaceTab(id: "plugin.\(entry.id)", title: manifest.name, systemImage: manifest.symbol)
    }
  }

  /// The view controller of a plug-in's tab (an `NSViewController`).
  public func viewController(forTab tabID: String) -> AnyObject? {
    guard tabID.hasPrefix("plugin.") else { return nil }
    return loaded[String(tabID.dropFirst("plugin.".count))]?.viewController
  }

  // MARK: Messages

  /// The model or its parameters changed: active plug-ins hear about it.
  public func updateContext(model: String?, family: String?, parameters: GenerationParameters) {
    self.model = model
    self.family = family
    latestParameters = parameters
    for entry in entries where entry.state == .loaded && entry.isActive { sendContext(to: entry.id) }
  }

  @ObservationIgnored private var latestParameters = GenerationParameters()

  private func sendContext(to identifier: String) {
    let context = PluginContext(
      model: model, family: family, parameters: latestParameters, tempFolder: tempFolder.path)
    guard let data = try? JSONEncoder().encode(context) else { return }
    send(data, to: identifier)
  }

  private func send(_ message: Data, to identifier: String) {
    guard let plugin = loaded[identifier] else { return }
    Task { _ = await plugin.send(message) }
  }

  public func dismissNotice() { latestNotice = nil }

  // MARK: PluginHosting

  public func receive(_ message: Data, from pluginID: String) -> Data {
    switch PluginMessageType.of(message) {
    case PluginMessageType.notice:
      if let notice = try? JSONDecoder().decode(PluginNotice.self, from: message) {
        let name = entries.first { $0.id == pluginID }?.name ?? pluginID
        latestNotice = PluginNoticeItem(pluginName: name, text: notice.text, isError: notice.isError)
      }
      return PluginMessageType.bare(PluginMessageType.ok)
    default:
      return PluginMessageType.bare(PluginMessageType.unsupported)
    }
  }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubCore `387 tests … passed` (11 nuovi); totale 82 + 387 + 66 + 6 + 6 = **547**.

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: il registro dei plug-in (stati, installazione con offerta, attivazione, tab, messaggi, avvisi)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: DTHubPluginKit, il plug-in di prova e il caricatore vero

**Files:**
- Create: `PluginKit/Package.swift`, `PluginKit/README.md`, `PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift`, `PluginKit/Examples/Sample/Package.swift`, `PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift`, `PluginKit/Scripts/make-bundle.sh`, `Packages/Sources/PluginHost/BundlePluginLoader.swift`
- Modify: `Packages/Package.swift`
- Test: `Packages/Tests/PluginHostTests/SampleBundle.swift`, `Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift` (nuovi)

**Interfaces:**
- Consumes: `PluginLoading`, `LoadedPlugin`, `PluginHosting`, `PluginRegistry`, `PluginFolder`, `PluginBundleReader` (Task 2–3).
- Produces:
  - **DTHubPluginKit** (pacchetto a parte, `PluginKit/`): `DTHubManifest`, `DTHubContract.current`, `DTHubMessage` (`type(of:)`, `bare(_:)`), `DTHubContext`, `@MainActor DTHubHost` (`send(_:) async -> Data?`, `notice(_:isError:)`), `@MainActor protocol DTHubPlugin` (`manifest`, `makeViewController()`, `start(host:)`, `handle(_:) async -> Data?`), `@MainActor open class DTHubPluginEntry: NSObject` (`makePlugin()` da sovrascrivere; i selettori `dthubManifest`, `dthubMakeViewController`, `dthubStart:`, `dthubHandle:reply:`);
  - **PluginHost** (HubCore, `public`): `@MainActor final class BundlePluginLoader: PluginLoading` (carica con `Bundle`; controlla la classe principale, i quattro selettori, il manifesto (identificatore uguale a quello del bundle, contratto supportato), la vista; consegna l'oggetto host; una risposta che non arriva in 5 secondi è `nil`);
  - `PluginKit/Scripts/make-bundle.sh DYLIB OUT IDENTIFIER NAME VERSION PRINCIPAL_CLASS [CONTRACT]`: fa il bundle e lo firma ad hoc;
  - il plug-in di esempio "Sample" (`SampleEntry`, identificatore `com.example.dthub.sample`, simbolo `star`): all'avvio manda un `notice` "Sample plug-in started"; mostra modello e stato.

- [ ] **Step 1: Scrivere i test che falliscono**

```swift
import Foundation

/// Builds the sample plug-in of the repository the way an author does (`swift build` of its package, then
/// `make-bundle.sh`), once per test run.
enum SampleBundle {
  /// The repository root: Packages/Tests/PluginHostTests/<this file>.
  static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  static let work = FileManager.default.temporaryDirectory
    .appendingPathComponent("PluginHostTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

  static let dylib: URL? = {
    let scratch = work.appendingPathComponent("build", isDirectory: true)
    guard run("/usr/bin/env", ["swift", "build", "--package-path", root.appendingPathComponent("PluginKit/Examples/Sample").path, "--scratch-path", scratch.path]) else { return nil }
    let enumerator = FileManager.default.enumerator(at: scratch, includingPropertiesForKeys: nil)
    while let url = enumerator?.nextObject() as? URL {
      if url.lastPathComponent == "libSamplePlugin.dylib" { return url }
    }
    return nil
  }()

  /// A bundle of the sample: its identifier, version, principal class and contract are the Info.plist's.
  static func make(
    id: String = "com.example.dthub.sample", version: String = "1.0", principal: String = "SampleEntry", contract: Int = 1
  ) -> URL? {
    guard let dylib else { return nil }
    let out = work.appendingPathComponent("\(UUID().uuidString)/Sample.dthubplugin", isDirectory: true)
    try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    let script = root.appendingPathComponent("PluginKit/Scripts/make-bundle.sh").path
    guard run(script, [dylib.path, out.path, id, "Sample", version, principal, String(contract)]) else { return nil }
    return out
  }

  private static func run(_ tool: String, _ arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
  }
}
```

```swift
import AppKit
import Foundation
import HubCore
import HubKit
import Testing

@testable import PluginHost

@MainActor
final class RecordingHost: PluginHosting {
  private(set) var received: [(message: Data, plugin: String)] = []

  func receive(_ message: Data, from pluginID: String) -> Data {
    received.append((message, pluginID))
    return PluginMessageType.bare(PluginMessageType.ok)
  }
}

/// Waits, polling, until `condition` holds (10 seconds at most): the plug-in speaks in its own time.
@MainActor
func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
  for _ in 0..<2000 {
    if condition() { return true }
    try? await Task.sleep(for: .milliseconds(5))
  }
  return condition()
}

/// These load a real bundle, built from the sample plug-in of the repository (a `swift build`, some seconds).
@MainActor
struct BundlePluginLoaderTests {
  func info(_ bundle: URL) throws -> PluginBundleInfo { try PluginBundleReader.read(bundle) }

  @Test func theSampleBundleLoadsAndAnswers() async throws {
    let bundle = try #require(SampleBundle.make(), "the sample plug-in could not be built")
    let host = RecordingHost()
    let plugin = try BundlePluginLoader().load(bundle, info: info(bundle), host: host)
    #expect(plugin.manifest.id == "com.example.dthub.sample" && plugin.manifest.name == "Sample")
    #expect(plugin.manifest.symbol == "star" && plugin.manifest.contract == 1)
    #expect(plugin.viewController is NSViewController)
    // The plug-in spoke to the app at start.
    #expect(await eventually { !host.received.isEmpty })
    let notice = try #require(host.received.first)
    #expect(notice.plugin == "com.example.dthub.sample")
    #expect(PluginMessageType.of(notice.message) == PluginMessageType.notice)
    #expect(String(decoding: notice.message, as: UTF8.self).contains("Sample plug-in started"))
    // The app speaks to the plug-in; an unknown type is "unsupported", a known one "ok".
    let context = try JSONEncoder().encode(
      PluginContext(model: "m.ckpt", family: "flux2_9b", parameters: GenerationParameters(), tempFolder: "/tmp"))
    let known = await plugin.send(context)
    #expect(known.flatMap(PluginMessageType.of) == PluginMessageType.ok)
    let unknown = await plugin.send(PluginMessageType.bare("fly"))
    #expect(unknown.flatMap(PluginMessageType.of) == PluginMessageType.unsupported)
  }

  @Test func aBundleWhoseCodeSaysAnotherIdentifierIsRefused() throws {
    let bundle = try #require(SampleBundle.make(id: "com.example.other"))
    #expect(throws: PluginError.manifestMismatch("com.example.dthub.sample")) {
      try BundlePluginLoader().load(bundle, info: info(bundle), host: RecordingHost())
    }
  }

  @Test func aBundleWithoutThePrincipalClassIsRefused() throws {
    let bundle = try #require(SampleBundle.make(principal: "NoSuchEntry"))
    #expect(throws: PluginError.noEntryPoint) {
      try BundlePluginLoader().load(bundle, info: info(bundle), host: RecordingHost())
    }
  }

  @Test func aBundleMadeForAnotherContractIsRefusedBeforeItsCodeLoads() throws {
    let bundle = try #require(SampleBundle.make(contract: 5))
    #expect(throws: PluginError.contractNotSupported(5)) { try info(bundle) }
  }

  @Test func theRegistryInstallsTurnsOnAndLoadsTheSampleAtTheNextLaunch() async throws {
    let source = try #require(SampleBundle.make())
    let root = SampleBundle.work.appendingPathComponent("registry-\(UUID().uuidString)", isDirectory: true)
    let settings = PluginSettingsStore(fileURL: root.appendingPathComponent("plugins.json"))
    func registry() -> PluginRegistry {
      PluginRegistry(
        folder: PluginFolder(root: root.appendingPathComponent("Plug-ins")), settings: settings,
        loader: BundlePluginLoader(), tempFolder: root)
    }
    let first = registry()
    first.start()
    try first.install(first.offer(for: source))
    first.setEnabled("com.example.dthub.sample", true)
    #expect(first.entries.map(\.state) == [.loadsAtNextLaunch])
    let second = registry()
    second.start()
    #expect(second.entries.map(\.state) == [.loaded])
    #expect(second.activeTabs.map(\.title) == ["Sample"])
    #expect(second.viewController(forTab: "plugin.com.example.dthub.sample") is NSViewController)
    #expect(await eventually { second.latestNotice != nil })
    #expect(second.latestNotice?.text == "Sample plug-in started")
    #expect(second.latestNotice?.pluginName == "Sample")
    let skipped = registry()
    skipped.start(skipping: true)
    #expect(skipped.entries.map(\.state) == [.skipped])
  }
}
```

I test costruiscono davvero il plug-in di esempio (`swift build` del suo pacchetto, qualche secondo, poi `make-bundle.sh`) e lo caricano.

- [ ] **Step 2: Aggiungere il target e verificare che falliscano**

```diff
diff --git a/Packages/Package.swift b/Packages/Package.swift
index 807da32..38e5632 100644
--- a/Packages/Package.swift
+++ b/Packages/Package.swift
@@ -12,6 +12,7 @@ let package = Package(
     .library(name: "HubCore", targets: ["HubCore"]),
     .library(name: "DTBridge", targets: ["DTBridge"]),
     .library(name: "LLMBridge", targets: ["LLMBridge"]),
+    .library(name: "PluginHost", targets: ["PluginHost"]),
   ],
   dependencies: [
     // Single maintainer, frequent releases: accept patch updates only (spec §5, §16).
@@ -43,12 +44,15 @@ let package = Package(
         .product(name: "HuggingFace", package: "swift-huggingface"),
         .product(name: "Tokenizers", package: "swift-transformers"),
       ]),
+    // Loads downloaded plug-in bundles (AppKit, Bundle, selectors); knows HubCore, never DT or MLX.
+    .target(name: "PluginHost", dependencies: ["HubKit", "HubCore"]),
     // Live tests: need a model on disk or the network, and the Metal library, so they run with
     // `xcodebuild test` (`swift test` skips them: spec §13, "LLMBridge: test a mano").
     .testTarget(name: "LLMBridgeTests", dependencies: ["LLMBridge", "HubKit"]),
     .testTarget(name: "HubKitTests", dependencies: ["HubKit"]),
     .testTarget(name: "HubCoreTests", dependencies: ["HubCore", "HubKit"]),
     .testTarget(name: "DTBridgeTests", dependencies: ["DTBridge", "HubKit", "HubCore"]),
+    .testTarget(name: "PluginHostTests", dependencies: ["PluginHost", "HubCore", "HubKit"]),
     // Checks App/Localizable.xcstrings: every string translated in en and it (spec §12).
     .testTarget(name: "CatalogTests"),
   ]
```

Run: `cd "<repo>/Packages" && swift test --filter PluginHostTests 2>&1 | grep -E "error:" | head -2`
Expected: `no such module 'PluginHost'` o `cannot find 'BundlePluginLoader' in scope`.

- [ ] **Step 3: Implementare**

```swift
// swift-tools-version: 6.2
import PackageDescription

// The package a DT Hub plug-in is written with. It does not depend on DT Hub: the app and the plug-in
// only talk through selectors and JSON messages (plug-in design §3).
let package = Package(
  name: "DTHubPluginKit",
  platforms: [.macOS(.v26)],
  products: [.library(name: "DTHubPluginKit", targets: ["DTHubPluginKit"])],
  targets: [.target(name: "DTHubPluginKit")]
)
```

```swift
import AppKit
import Foundation

/// What a plug-in says about itself (the JSON `dthubManifest` returns).
public struct DTHubManifest: Codable, Sendable {
  public var id: String
  public var name: String
  public var version: String
  /// The contract version this plug-in was made for.
  public var contract: Int
  /// An SF Symbol name for the tab.
  public var symbol: String
  /// Model families it works with; nil = all.
  public var families: [String]?

  public init(
    id: String, name: String, version: String = "1.0", contract: Int = DTHubContract.current,
    symbol: String = "puzzlepiece.extension", families: [String]? = nil
  ) {
    self.id = id
    self.name = name
    self.version = version
    self.contract = contract
    self.symbol = symbol
    self.families = families
  }
}

public enum DTHubContract {
  public static let current = 1
}

/// JSON messages are objects with a `type`.
public enum DTHubMessage {
  public static func type(of data: Data) -> String? {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"] as? String
  }

  public static func bare(_ type: String) -> Data { Data(#"{"type":"\#(type)"}"#.utf8) }
}

/// App → plug-in: where the app stands (message type `context`).
public struct DTHubContext: Decodable, Sendable {
  public var model: String?
  public var family: String?
  /// A folder to exchange image files through.
  public var tempFolder: String
}

/// The app side of the channel, given to the plug-in at start.
@MainActor
public final class DTHubHost {
  private let object: NSObject

  init(object: NSObject) { self.object = object }

  /// Sends a JSON message to the app and waits for its JSON answer.
  public func send(_ message: Data) async -> Data? {
    await withCheckedContinuation { continuation in
      let once = Once(continuation)
      let reply: @convention(block) (Data) -> Void = { once.finish($0) }
      _ = object.perform(NSSelectorFromString("dthubSend:reply:"), with: message, with: reply)
      Task {
        try? await Task.sleep(for: .seconds(5))
        once.finish(nil)
      }
    }
  }

  /// Asks the app to show a line to the user.
  public func notice(_ text: String, isError: Bool = false) {
    let body: [String: Any] = ["type": "notice", "text": text, "isError": isError]
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
    Task { _ = await send(data) }
  }
}

final class Once: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Data?, Never>?

  init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }

  func finish(_ data: Data?) {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume(returning: data)
  }
}

/// A DT Hub plug-in.
@MainActor
public protocol DTHubPlugin: AnyObject {
  var manifest: DTHubManifest { get }
  /// The tab of the plug-in (usually an `NSHostingController` with a SwiftUI view).
  func makeViewController() -> NSViewController
  /// Called once, after the manifest and the view are made.
  func start(host: DTHubHost)
  /// A message from the app; the answer is JSON (nil = `{"type":"ok"}`). An unknown type should
  /// get `nil` or `{"type":"unsupported"}`.
  func handle(_ message: Data) async -> Data?
}

/// The principal class of a plug-in bundle. Subclass it, give the subclass an Objective-C name
/// (`@objc(MyPluginEntry)`), put that name in `NSPrincipalClass`, and override `makePlugin()`.
@MainActor
open class DTHubPluginEntry: NSObject {
  private var plugin: (any DTHubPlugin)?

  public required override init() { super.init() }

  open func makePlugin() -> any DTHubPlugin { fatalError("override makePlugin()") }

  private func made() -> any DTHubPlugin {
    if let plugin { return plugin }
    let plugin = makePlugin()
    self.plugin = plugin
    return plugin
  }

  @objc public func dthubManifest() -> Data {
    (try? JSONEncoder().encode(made().manifest)) ?? Data()
  }

  @objc public func dthubMakeViewController() -> NSViewController {
    made().makeViewController()
  }

  @objc public func dthubStart(_ host: NSObject) {
    made().start(host: DTHubHost(object: host))
  }

  @objc public func dthubHandle(_ message: Data, reply: @escaping (Data) -> Void) {
    nonisolated(unsafe) let reply = reply
    let plugin = made()
    Task { @MainActor in
      reply(await plugin.handle(message) ?? DTHubMessage.bare("ok"))
    }
  }
}
```

```swift
// swift-tools-version: 6.2
import PackageDescription

// A complete plug-in to copy: a tab that shows the model the app tells it about, and a notice at start.
let package = Package(
  name: "SamplePlugin",
  platforms: [.macOS(.v26)],
  products: [.library(name: "SamplePlugin", type: .dynamic, targets: ["SamplePlugin"])],
  dependencies: [.package(name: "PluginKit", path: "../..")],
  targets: [.target(name: "SamplePlugin", dependencies: [.product(name: "DTHubPluginKit", package: "PluginKit")])]
)
```

```swift
import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class SampleState: ObservableObject {
  @Published var model = "—"
  @Published var active = false
}

@MainActor
final class SamplePlugin: DTHubPlugin {
  let manifest = DTHubManifest(id: "com.example.dthub.sample", name: "Sample", version: "1.0", symbol: "star")
  private let state = SampleState()

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: SampleView(state: state))
  }

  func start(host: DTHubHost) {
    host.notice("Sample plug-in started")
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      if let context = try? JSONDecoder().decode(DTHubContext.self, from: message) {
        state.model = context.model ?? "—"
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
}

struct SampleView: View {
  @ObservedObject var state: SampleState

  var body: some View {
    VStack(spacing: 8) {
      Text("Sample plug-in").font(.title2)
      Text("Model: \(state.model)")
      Text(state.active ? "active" : "not active").foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

@objc(SampleEntry)
public final class SampleEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { SamplePlugin() }
}
```

```
#!/bin/zsh
# make-bundle.sh DYLIB OUT.dthubplugin IDENTIFIER NAME VERSION PRINCIPAL_CLASS [CONTRACT]
# Wraps the dynamic library a plug-in package builds into a .dthubplugin bundle and signs it ad hoc.
set -e
DYLIB="$1"; OUT="$2"; ID="$3"; NAME="$4"; VERSION="$5"; CLASS="$6"; CONTRACT="${7:-1}"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"
cp "$DYLIB" "$OUT/Contents/MacOS/$NAME"
cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$ID</string>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundleExecutable</key><string>$NAME</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>NSPrincipalClass</key><string>$CLASS</string>
<key>DTHubContract</key><integer>$CONTRACT</integer>
</dict></plist>
PLIST
codesign -s - --force "$OUT" >/dev/null 2>&1
```

```
# DTHubPluginKit

The package a DT Hub plug-in is written with. It does not depend on DT Hub: the app and a plug-in only talk through
Objective-C selectors and JSON messages (see `docs/superpowers/specs/2026-10-03-plugin-design.md`).

## Writing a plug-in

1. A Swift package with a **dynamic** library product that depends on `DTHubPluginKit` (copy `Examples/Sample`).
2. A class conforming to `DTHubPlugin` (`manifest`, `makeViewController()`, `start(host:)`, `handle(_:)`).
3. A subclass of `DTHubPluginEntry` with an Objective-C name, overriding `makePlugin()`:

        @objc(MyPluginEntry)
        public final class MyPluginEntry: DTHubPluginEntry {
          public override func makePlugin() -> any DTHubPlugin { MyPlugin() }
        }

4. `swift build`, then wrap the library into a bundle:

        Scripts/make-bundle.sh .build/out/Products/Debug/libMyPlugin.dylib MyPlugin.dthubplugin com.you.myplugin MyPlugin 1.0 MyPluginEntry

   The arguments are the library, the bundle to make, the identifier (it must equal `manifest.id`), the name, the
   version, the principal class and, optionally, the contract version (default 1).

The bundle is added in DT Hub › Preferences › Plug-ins.

## Messages (contract 1)

JSON objects with a `type`. App → plug-in: `context` (model, family, parameters, a temporary folder), `activate`,
`deactivate`. Plug-in → app: `notice` (`text`, `isError`). An unknown type gets `{"type":"unsupported"}`.
```

```swift
import AppKit
import Foundation
import HubCore
import HubKit

/// Loads a `.dthubplugin` bundle into the app (plug-in design §3, §5): its code through `Bundle`, its
/// manifest, tab and messages through the selectors of the principal class.
@MainActor
public final class BundlePluginLoader: PluginLoading {
  public init() {}

  public func load(_ url: URL, info: PluginBundleInfo, host: any PluginHosting) throws(PluginError) -> any LoadedPlugin {
    guard let bundle = Bundle(url: url) else { throw .unreadable }
    do {
      try bundle.loadAndReturnError()
    } catch {
      throw .loadFailed(error.localizedDescription)
    }
    guard let entryClass = bundle.principalClass as? NSObject.Type else { throw .noEntryPoint }
    let entry = entryClass.init()
    let selectors = ["dthubManifest", "dthubMakeViewController", "dthubStart:", "dthubHandle:reply:"]
    guard selectors.allSatisfy({ entry.responds(to: NSSelectorFromString($0)) }) else { throw .noEntryPoint }

    guard let data = entry.perform(NSSelectorFromString("dthubManifest"))?.takeUnretainedValue() as? Data,
      let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data)
    else { throw .noEntryPoint }
    guard manifest.id == info.identifier else { throw .manifestMismatch(manifest.id) }
    guard PluginContract.supported.contains(manifest.contract) else { throw .contractNotSupported(manifest.contract) }
    guard
      let controller = entry.perform(NSSelectorFromString("dthubMakeViewController"))?.takeUnretainedValue()
        as? NSViewController
    else { throw .noEntryPoint }

    let hostObject = PluginHostObject(host: host, pluginID: manifest.id)
    _ = entry.perform(NSSelectorFromString("dthubStart:"), with: hostObject)
    return BundleLoadedPlugin(manifest: manifest, entry: entry, controller: controller, hostObject: hostObject)
  }
}

/// A loaded plug-in: the app talks to its principal class.
@MainActor
final class BundleLoadedPlugin: LoadedPlugin {
  let manifest: PluginManifest
  let viewController: AnyObject
  private let entry: NSObject
  private let hostObject: PluginHostObject

  init(manifest: PluginManifest, entry: NSObject, controller: NSViewController, hostObject: PluginHostObject) {
    self.manifest = manifest
    self.entry = entry
    self.viewController = controller
    self.hostObject = hostObject
  }

  /// An answer that did not come in 5 seconds is nil.
  func send(_ message: Data) async -> Data? {
    await withCheckedContinuation { continuation in
      let once = OnceReply(continuation)
      let reply: @convention(block) (Data) -> Void = { once.finish($0) }
      _ = entry.perform(NSSelectorFromString("dthubHandle:reply:"), with: message, with: reply)
      Task {
        try? await Task.sleep(for: .seconds(5))
        once.finish(nil)
      }
    }
  }
}

/// The object the plug-in calls into (`dthubSend:reply:`), possibly from any thread.
final class PluginHostObject: NSObject, @unchecked Sendable {
  private weak var host: (any PluginHosting)?
  private let pluginID: String

  @MainActor
  init(host: any PluginHosting, pluginID: String) {
    self.host = host
    self.pluginID = pluginID
  }

  @objc func dthubSend(_ message: Data, reply: @escaping (Data) -> Void) {
    nonisolated(unsafe) let reply = reply
    Task { @MainActor [weak self] in
      guard let self, let host = self.host else { return reply(PluginMessageType.bare(PluginMessageType.unsupported)) }
      reply(host.receive(message, from: self.pluginID))
    }
  }
}

/// Resumes a continuation once, whichever of the answer and the timeout comes first.
final class OnceReply: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Data?, Never>?

  init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }

  func finish(_ data: Data?) {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume(returning: data)
  }
}
```

```bash
cd "<repo>" && chmod +x PluginKit/Scripts/make-bundle.sh
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: PluginHost `5 tests … passed` (circa 10 secondi); HubKit 82, HubCore 387, DTBridge 66, Catalog 6, LLMBridge 6 (totale **552**).

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add Packages PluginKit && git commit -m "feat: DTHubPluginKit per gli autori, plug-in di esempio, script del bundle e caricatore vero (PluginHost)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: L'app — Preferenze, menu, tab, avviso, entitlement

**Files:**
- Create: `App/Plugins/PluginText.swift`, `App/Plugins/PluginTabView.swift`, `App/Plugins/PluginNoticeBanner.swift`, `App/Plugins/PluginsPreferencesView.swift`, `DTHub.entitlements`
- Modify: `App/DTHubApp.swift`, `App/MainWindow/HeaderBar.swift`, `App/MainWindow/MainWindowView.swift`, `App/Preferences/PreferencesView.swift`, `DTHub.xcodeproj/project.pbxproj`, `App/Localizable.xcstrings`

**Interfaces:**
- Consumes: `PluginRegistry`, `PluginEntry`, `PluginInstallOffer`, `PluginError` (Task 2–3), `BundlePluginLoader` (Task 4), `WorkspaceState.setPluginTabs` (esistente).
- Produces: all'avvio l'app crea il registro (cartella `PluginFolder.defaultRoot`, impostazioni `plugins.json`, `BundlePluginLoader`, cartella temporanea `DTHub-plugins`) e lo avvia con `skipping: NSEvent.modifierFlags.contains(.option)`; Preferenze › **Plug-in** (elenco con stato e interruttore, "Aggiungi…", trascinamento, conferma con avviso, "Rimuovi", errori); header › menu **Plug-in** (plug-in caricati con interruttore, grigi se incompatibili, "Gestisci i plug-in…"); i tab dei plug-in attivi nella barra; il tab mostra la vista del plug-in; l'avviso dei plug-in sopra la finestra per 8 secondi; il registro riceve modello e famiglia quando cambiano; entitlement `disable-library-validation`.

- [ ] **Step 1: Stringhe**

@@KEYS@@

Salvare lo script come `/tmp/m8a_keys.py` e lanciarlo dalla radice: `cd "<repo>" && python3 /tmp/m8a_keys.py`. Controllare con `git diff --stat App/Localizable.xcstrings` (solo righe aggiunte).

- [ ] **Step 2: Le viste nuove e l'entitlement**

```swift
import Foundation
import HubCore

/// The sentences for what the plug-in list shows.
enum PluginText {
  /// The page where plug-ins can be downloaded, once it exists (nil: the link is not shown).
  static let downloadPage: URL? = nil

  static func error(_ error: PluginError) -> String {
    switch error {
    case .unreadable: String(localized: "plugin.error.unreadable")
    case .missingKey(let key): String(format: String(localized: "plugin.error.missingKey"), key)
    case .contractNotSupported(let version): String(format: String(localized: "plugin.error.contract"), version)
    case .manifestMismatch(let found): String(format: String(localized: "plugin.error.mismatch"), found)
    case .noEntryPoint: String(localized: "plugin.error.entry")
    case .loadFailed(let reason): String(format: String(localized: "plugin.error.load"), reason)
    case .notNewer(let installed): String(format: String(localized: "plugin.error.notNewer"), installed)
    case .cannotWrite(let reason): String(format: String(localized: "plugin.error.write"), reason)
    }
  }

  static func state(_ state: PluginEntry.State) -> String {
    switch state {
    case .off: String(localized: "plugin.state.off")
    case .loadsAtNextLaunch: String(localized: "plugin.state.next")
    case .skipped: String(localized: "plugin.state.skipped")
    case .loaded: String(localized: "plugin.state.loaded")
    case .failed(let reason): error(reason)
    }
  }
}
```

```swift
import AppKit
import SwiftUI

/// A plug-in's tab: the view controller its code made.
struct PluginTabView: NSViewControllerRepresentable {
  let controller: NSViewController

  func makeNSViewController(context: Context) -> NSViewController { controller }

  func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}
```

```swift
import HubCore
import HubKit
import SwiftUI

/// A line a plug-in asked to show, floating over the window for a few seconds.
struct PluginNoticeBanner: View {
  let plugins: PluginRegistry

  var body: some View {
    Group {
      if let notice = plugins.latestNotice {
        HStack(spacing: DS.controlGap) {
          Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "puzzlepiece.extension")
            .foregroundStyle(notice.isError ? DS.remove : DS.accent)
          Text(verbatim: "\(notice.pluginName): \(notice.text)").lineLimit(2)
          Button {
            plugins.dismissNotice()
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 6, y: 2)
        .padding(.bottom, 16)
        .transition(.opacity)
        .task(id: notice.id) {
          try? await Task.sleep(for: .seconds(8))
          if plugins.latestNotice?.id == notice.id { plugins.dismissNotice() }
        }
      }
    }
    .animation(.default, value: plugins.latestNotice?.id)
  }
}
```

```swift
import AppKit
import HubCore
import HubKit
import SwiftUI
import UniformTypeIdentifiers

/// Preferences › Plug-ins: what is installed, the switches, add (a file chosen or dropped) and remove.
struct PluginsPreferencesView: View {
  let plugins: PluginRegistry
  @State private var offer: PluginInstallOffer?
  @State private var problem: String?
  @State private var isTargeted = false

  var body: some View {
    Form {
      Section {
        if plugins.entries.isEmpty {
          Text("prefs.plugins.empty").foregroundStyle(.secondary)
        }
        ForEach(plugins.entries) { entry in
          row(entry)
        }
      } footer: {
        VStack(alignment: .leading, spacing: 4) {
          if let problem { Text(verbatim: problem).foregroundStyle(DS.remove) }
          Text("prefs.plugins.note").foregroundStyle(.secondary)
          if let page = PluginText.downloadPage {
            Link("prefs.plugins.download", destination: page)
          }
        }
      }
      Section {
        HStack(spacing: DS.controlGap) {
          Spacer(minLength: 0)
          Button("prefs.plugins.add") { choose() }
            .buttonStyle(DSPillButtonStyle(prominent: true))
        }
      }
    }
    .formStyle(.grouped)
    .overlay(RoundedRectangle(cornerRadius: DS.boxRadius).strokeBorder(DS.accent, lineWidth: isTargeted ? 2 : 0).padding(4))
    .dropDestination(for: URL.self) { urls, _ in
      guard let url = urls.first(where: { $0.pathExtension == "dthubplugin" }) else { return false }
      propose(url)
      return true
    } isTargeted: { isTargeted = $0 }
    .confirmationDialog(
      offer.map { String(format: String(localized: "prefs.plugins.confirm.title"), $0.info.name) } ?? "",
      isPresented: Binding(get: { offer != nil }, set: { if !$0 { offer = nil } }), presenting: offer
    ) { offer in
      Button("prefs.plugins.confirm.add") { install(offer) }
      Button("prefs.plugins.confirm.cancel", role: .cancel) {}
    } message: { offer in
      Text(
        String(format: String(localized: "prefs.plugins.confirm.message"), offer.info.version)
          + (offer.replacing.map { "\n" + String(format: String(localized: "prefs.plugins.confirm.replacing"), $0) } ?? ""))
    }
  }

  private func row(_ entry: PluginEntry) -> some View {
    HStack(spacing: DS.controlGap) {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: "\(entry.name) \(entry.version)")
        Text(verbatim: PluginText.state(entry.state)).font(.caption)
          .foregroundStyle({ if case .failed = entry.state { DS.remove } else { Color.secondary } }())
      }
      Spacer(minLength: 0)
      if case .failed = entry.state {
      } else {
        Toggle(isOn: Binding(get: { plugins.isEnabled(entry.id) }, set: { plugins.setEnabled(entry.id, $0) })) {
          Text(verbatim: entry.name)
        }
        .labelsHidden()
        .toggleStyle(.switch)
      }
      Button("prefs.plugins.remove", role: .destructive) { remove(entry) }
        .buttonStyle(DSPillButtonStyle())
    }
  }

  private func choose() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true  // a .dthubplugin is a folder
    panel.allowsMultipleSelection = false
    panel.message = String(localized: "prefs.plugins.choose")
    if panel.runModal() == .OK, let url = panel.url { propose(url) }
  }

  private func propose(_ url: URL) {
    problem = nil
    do {
      offer = try plugins.offer(for: url)
    } catch {
      problem = PluginText.error(error)
    }
  }

  private func install(_ offer: PluginInstallOffer) {
    do {
      try plugins.install(offer)
      problem = nil
    } catch {
      problem = PluginText.error(error)
    }
  }

  private func remove(_ entry: PluginEntry) {
    do {
      try plugins.remove(entry.id)
      problem = nil
    } catch {
      problem = PluginText.error(error)
    }
  }
}
```

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- Plug-ins are bundles signed by others (or only ad hoc): the hardened runtime must let the app load them. -->
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 3: Collegare l'app**

```diff
diff --git a/App/DTHubApp.swift b/App/DTHubApp.swift
index e6932f0..ccc8fc9 100644
--- a/App/DTHubApp.swift
+++ b/App/DTHubApp.swift
@@ -2,6 +2,7 @@ import AppKit
 import HubCore
 import HubKit
 import LLMBridge
+import PluginHost
 import SwiftUI
 
 @main
@@ -19,6 +20,7 @@ struct DTHubApp: App {
   @State private var languageModel: LanguageModelManager
   @State private var generation: GenerationController
   @State private var download: LanguageModelDownloadController
+  @State private var plugins: PluginRegistry
 
   init() {
     let connection = DrawThingsConnection()
@@ -35,6 +37,13 @@ struct DTHubApp: App {
     _languageModel = State(initialValue: languageModel)
     _generation = State(initialValue: generation)
     _download = State(initialValue: LanguageModelDownloadController(downloader: HubLanguageModelDownloader()))
+    // Plug-ins load now; holding ⌥ at launch loads none (plug-in design §5).
+    let plugins = PluginRegistry(
+      folder: PluginFolder(root: PluginFolder.defaultRoot),
+      settings: PluginSettingsStore(fileURL: PluginSettingsStore.defaultFileURL), loader: BundlePluginLoader(),
+      tempFolder: FileManager.default.temporaryDirectory.appendingPathComponent("DTHub-plugins", isDirectory: true))
+    plugins.start(skipping: NSEvent.modifierFlags.contains(.option))
+    _plugins = State(initialValue: plugins)
     // A download cut short by quitting leaves a hidden folder with part of a model: remove it.
     let leftovers = URL(fileURLWithPath: languageModel.settings.folder, isDirectory: true)
       .appendingPathComponent(RecommendedLanguageModel.folderName, isDirectory: true).deletingLastPathComponent()
@@ -43,7 +52,7 @@ struct DTHubApp: App {
 
   var body: some Scene {
     WindowGroup(String(localized: "app.title")) {
-      MainWindowView(workspace: workspace, connection: connection, generation: generation)
+      MainWindowView(workspace: workspace, connection: connection, generation: generation, plugins: plugins)
         .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
           generation.saveSessionNow()
         }
@@ -62,7 +71,8 @@ struct DTHubApp: App {
 
     Settings {
       PreferencesView(
-        connection: connection, generation: generation, languageModel: languageModel, download: download)
+        connection: connection, generation: generation, languageModel: languageModel, download: download,
+        plugins: plugins)
     }
   }
 }
```

```diff
diff --git a/App/MainWindow/HeaderBar.swift b/App/MainWindow/HeaderBar.swift
index 3b8a55e..d94e8a4 100644
--- a/App/MainWindow/HeaderBar.swift
+++ b/App/MainWindow/HeaderBar.swift
@@ -6,7 +6,9 @@ import SwiftUI
 struct HeaderBar: View {
   let connection: DrawThingsConnection
   let generation: GenerationController
+  let plugins: PluginRegistry
   @Environment(\.openWindow) private var openWindow
+  @Environment(\.openSettings) private var openSettings
 
   private var monitor: ConnectionMonitor { connection.monitor }
   private var selection: ModelSelection { connection.selection }
@@ -38,7 +40,20 @@ struct HeaderBar: View {
 
   private var pluginsMenu: some View {
     Menu {
-      Text("header.plugins.none")
+      let loaded = plugins.entries.filter { $0.state == .loaded }
+      if loaded.isEmpty {
+        Text("header.plugins.none")
+      }
+      ForEach(loaded) { entry in
+        Toggle(
+          entry.name,
+          isOn: Binding(get: { entry.isActive }, set: { plugins.setActive(entry.id, $0) })
+        )
+        .disabled(!plugins.isCompatible(entry))
+        .help(plugins.isCompatible(entry) ? "" : String(localized: "header.plugins.incompatible"))
+      }
+      Divider()
+      Button("header.plugins.manage") { openSettings() }
     } label: {
       DSMenuLabel(String(localized: "header.plugins"), systemImage: "puzzlepiece.extension")
     }
```

```diff
diff --git a/App/MainWindow/MainWindowView.swift b/App/MainWindow/MainWindowView.swift
index 1a3a5da..c6e299a 100644
--- a/App/MainWindow/MainWindowView.swift
+++ b/App/MainWindow/MainWindowView.swift
@@ -1,3 +1,4 @@
+import AppKit
 import HubCore
 import HubKit
 import SwiftUI
@@ -7,10 +8,17 @@ struct MainWindowView: View {
   let workspace: WorkspaceState
   let connection: DrawThingsConnection
   let generation: GenerationController
+  let plugins: PluginRegistry
+
+  /// What the plug-ins are told about: the model and its family.
+  private var contextKey: [String?] {
+    let model = connection.selection.selectedModel(in: connection.monitor.catalog)
+    return [model?.file, model?.family]
+  }
 
   var body: some View {
     VStack(spacing: DS.panelPadding) {
-      HeaderBar(connection: connection, generation: generation)
+      HeaderBar(connection: connection, generation: generation, plugins: plugins)
       ManagedServerBanner(connection: connection)
       DSTabFrame {
         WorkspaceTabBar(workspace: workspace)
@@ -23,6 +31,12 @@ struct MainWindowView: View {
     .background(DSBackground())
     .background(DSWindowConfigurator())
     .tint(DS.accent)
+    .overlay(alignment: .bottom) { PluginNoticeBanner(plugins: plugins) }
+    .task(id: contextKey) {
+      plugins.updateContext(model: contextKey[0], family: contextKey[1], parameters: generation.parameters)
+      workspace.setPluginTabs(plugins.activeTabs)
+    }
+    .onChange(of: plugins.activeTabs) { workspace.setPluginTabs(plugins.activeTabs) }
   }
 
   @ViewBuilder private var tabContent: some View {
@@ -30,8 +44,9 @@ struct MainWindowView: View {
       ControlTabView(generation: generation, connection: connection)
     } else if workspace.selectedTabID == WorkspaceTab.generationID {
       GenerationTabView(controller: generation, connection: connection)
+    } else if let controller = plugins.viewController(forTab: workspace.selectedTabID) as? NSViewController {
+      PluginTabView(controller: controller)
     } else {
-      // Plug-in tabs arrive with the plug-in contract (M7).
       EmptyView()
     }
   }
```

```diff
diff --git a/App/Preferences/PreferencesView.swift b/App/Preferences/PreferencesView.swift
index e91b6dc..dc56b31 100644
--- a/App/Preferences/PreferencesView.swift
+++ b/App/Preferences/PreferencesView.swift
@@ -7,6 +7,7 @@ struct PreferencesView: View {
   let generation: GenerationController
   let languageModel: LanguageModelManager
   let download: LanguageModelDownloadController
+  let plugins: PluginRegistry
 
   var body: some View {
     TabView {
@@ -19,6 +20,9 @@ struct PreferencesView: View {
       Tab("prefs.tab.output", systemImage: "folder") {
         OutputPreferencesView(controller: generation)
       }
+      Tab("prefs.tab.plugins", systemImage: "puzzlepiece.extension") {
+        PluginsPreferencesView(plugins: plugins)
+      }
     }
     .frame(width: 560, height: 420)
   }
```

```diff
diff --git a/DTHub.xcodeproj/project.pbxproj b/DTHub.xcodeproj/project.pbxproj
index a3494e6..22e1b63 100644
--- a/DTHub.xcodeproj/project.pbxproj
+++ b/DTHub.xcodeproj/project.pbxproj
@@ -11,6 +11,7 @@
 		9DE148152A7E358B4403C627 /* HubCore in Frameworks */ = {isa = PBXBuildFile; productRef = 032BDA881CF996C0D4322A03 /* HubCore */; };
 		D7B41D6E5C2A4F0B9E3A1C01 /* DTBridge in Frameworks */ = {isa = PBXBuildFile; productRef = D7B41D6E5C2A4F0B9E3A1C02 /* DTBridge */; };
 		E8C52E7F6D3B5A1CAF4B2D11 /* LLMBridge in Frameworks */ = {isa = PBXBuildFile; productRef = E8C52E7F6D3B5A1CAF4B2D12 /* LLMBridge */; };
+		F9D63F808E4C6B2DB05C3E21 /* PluginHost in Frameworks */ = {isa = PBXBuildFile; productRef = F9D63F808E4C6B2DB05C3E22 /* PluginHost */; };
 /* End PBXBuildFile section */
 
 /* Begin PBXFileReference section */
@@ -35,6 +36,7 @@
 				9DE148152A7E358B4403C627 /* HubCore in Frameworks */,
 				D7B41D6E5C2A4F0B9E3A1C01 /* DTBridge in Frameworks */,
 				E8C52E7F6D3B5A1CAF4B2D11 /* LLMBridge in Frameworks */,
+				F9D63F808E4C6B2DB05C3E21 /* PluginHost in Frameworks */,
 			);
 			runOnlyForDeploymentPostprocessing = 0;
 		};
@@ -90,6 +92,7 @@
 				032BDA881CF996C0D4322A03 /* HubCore */,
 				D7B41D6E5C2A4F0B9E3A1C02 /* DTBridge */,
 				E8C52E7F6D3B5A1CAF4B2D12 /* LLMBridge */,
+				F9D63F808E4C6B2DB05C3E22 /* PluginHost */,
 			);
 			productName = DTHub;
 			productReference = 26BE388AD6E6D7E846B549DF /* DTHub.app */;
@@ -158,6 +161,7 @@
 			isa = XCBuildConfiguration;
 			buildSettings = {
 				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
+				CODE_SIGN_ENTITLEMENTS = DTHub.entitlements;
 				CODE_SIGN_STYLE = Automatic;
 				COMBINE_HIDPI_IMAGES = YES;
 				CURRENT_PROJECT_VERSION = 1;
@@ -305,6 +309,7 @@
 			isa = XCBuildConfiguration;
 			buildSettings = {
 				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
+				CODE_SIGN_ENTITLEMENTS = DTHub.entitlements;
 				CODE_SIGN_STYLE = Automatic;
 				COMBINE_HIDPI_IMAGES = YES;
 				CURRENT_PROJECT_VERSION = 1;
@@ -376,6 +381,10 @@
 			isa = XCSwiftPackageProductDependency;
 			productName = LLMBridge;
 		};
+		F9D63F808E4C6B2DB05C3E22 /* PluginHost */ = {
+			isa = XCSwiftPackageProductDependency;
+			productName = PluginHost;
+		};
 /* End XCSwiftPackageProductDependency section */
 	};
 	rootObject = F6F3A79C40E00FEAA5ED17E9 /* Project object */;
```

- [ ] **Step 4: Compilare e provare**

Run: `cd "<repo>" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath /tmp/m8a-dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; cd Packages && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|Missing|Not in" | grep -v "started\|reportsFailures"`
Expected: `** BUILD SUCCEEDED **`; test HubKit 82, HubCore 387, PluginHost 5, DTBridge 66, Catalog 6, LLMBridge 6 = **552** passati (il test del catalogo controlla le nuove chiavi e che nessun titolo sia una stringa vuota).

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add App DTHub.entitlements DTHub.xcodeproj && git commit -m "feat: Preferenze › Plug-in, menu Plug-in dell'header, tab e avvisi dei plug-in, entitlement

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Prova nell'app e documenti

**Files:**
- Modify: `docs/superpowers/specs/2026-10-03-plugin-design.md`

- [ ] **Step 1: Provare il plug-in di esempio nell'app vera, in una cartella dati a parte**

Non si toccano i dati dell'utente: l'app parte con `CFFIXED_USER_HOME` (cartella Application Support e preferenze a parte) e il plug-in di esempio già installato e acceso.

```bash
cd "<repo>" && (cd PluginKit/Examples/Sample && swift build 2>&1 | tail -1)
H=/tmp/m8ahome; rm -rf $H; AS="$H/Library/Application Support/DT Hub"; mkdir -p "$AS/Plug-ins"
PluginKit/Scripts/make-bundle.sh PluginKit/Examples/Sample/.build/out/Products/Debug/libSamplePlugin.dylib "$AS/Plug-ins/com.example.dthub.sample.dthubplugin" com.example.dthub.sample Sample 1.0 SampleEntry
echo '{"enabled":["com.example.dthub.sample"]}' > "$AS/plugins.json"
(CFFIXED_USER_HOME=$H nohup "/tmp/m8a-dd/Build/Products/Debug/DT Hub.app/Contents/MacOS/DT Hub" > /tmp/m8a-app.log 2>&1 &)
```

Se l'app dell'utente è aperta, gli strumenti per pilotare le finestre vedono la sua e non quella di prova: la finestra della prova si trova con `CGWindowListCopyWindowInfo` sul `pid` del processo (`pgrep -f m8a-dd`) e si cattura con `screencapture -x -l <numero> /tmp/m8a.png`.

Checklist:
1. La barra dei tab ha **Control, Generazione, Sample** (stella); il tab Sample mostra "Sample plug-in", "Model: …" e "active".
2. Il menu **Plug-in** dell'header elenca "Sample" con un segno; spegnerlo toglie il tab, riaccenderlo lo rimette.
3. Poco dopo l'avvio compare l'avviso "Sample: Sample plug-in started" per circa 8 secondi.
4. Preferenze › **Plug-in**: "Sample 1.0 — Acceso — caricato"; "Aggiungi…" con un secondo bundle (per esempio lo stesso rifatto con versione 1.1) mostra la conferma con l'avviso e, dopo "Aggiungi", la riga resta "caricato" (la nuova versione vale dal prossimo avvio); lo stesso bundle una seconda volta dà "È già installata la versione …".
5. Spegnere l'interruttore: lo stato diventa "caricato" finché non si riavvia; dopo il riavvio è "Spento" e il tab non c'è.
6. Riavviando **con ⌥ premuto** non si carica nulla (stato "non caricato in questo avvio").
7. Un bundle con contratto 5 (`make-bundle.sh … 5`) trascinato sulle Preferenze dà "Fatto per il contratto 5…" e non si copia.

Alla fine: chiudere l'app di prova (`pkill -f m8a-dd`), togliere `/tmp/m8ahome`.

- [ ] **Step 2: Aggiornare la spec**

```bash
cd "<repo>" && python3 - <<'PY'
p = 'docs/superpowers/specs/2026-10-03-plugin-design.md'
s = open(p).read()
s = s.replace("Stato: bozza da approvare", "Stato: M8a realizzata, M8b da fare")
open(p, 'w').write(s)
PY
git diff --stat docs
```

Expected: una riga di statistica sulla sola spec dei plug-in (1 riga cambiata).

- [ ] **Step 3: Commit**

```bash
cd "<repo>" && git add docs && git commit -m "docs: spec dei plug-in — M8a realizzata

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Fine della M8a

Esito atteso sul branch `m8a-plugin`:
- **552 test verdi** (5 nuovi di PluginHost caricano un bundle vero, costruito dal plug-in di esempio);
- build Xcode pulita, con l'entitlement;
- un plug-in `.dthubplugin` si aggiunge dalle Preferenze (con conferma), si accende, si carica al prossimo avvio e mostra il proprio tab; il menu Plug-in dell'header lo attiva per il lavoro in corso; ⌥ all'avvio non carica nulla; un bundle sbagliato è elencato con il motivo e non fa cadere nulla.

Poi: revisione indipendente, correzioni, prove dell'utente (**lasciare l'app aperta**), merge. Dopo M8a: M8b (contributi, campi in teal, conflitti, pipeline), poi i plug-in veri.

