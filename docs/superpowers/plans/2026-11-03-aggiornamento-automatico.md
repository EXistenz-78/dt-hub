# Aggiornamento automatico Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** All'avvio DT Hub controlla il release più recente di `EXistenz-78/dt-hub` tramite un manifest e, solo dopo la conferma dell'utente, scarica e installa la nuova app e i soli plug-in installati che sono più nuovi.

**Architecture:** Un nuovo gruppo `HubCore/Updates/` con tipi piccoli e a iniezione (manifest, piano, controllo, installazione, sostituzione dell'app, controller a stati); nessuna dipendenza nuova. L'app aggiunge solo viste (banner, foglio dei dettagli, scheda Preferenze) e il collegamento in `DTHubApp`. I plug-in passano dal flusso esistente `PluginRegistry.offer(for:)` / `install(_:)`.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, `URLSession`, CryptoKit, `/usr/bin/ditto`, `/usr/bin/codesign`, Python 3 (script del manifest).

**Spec:** `docs/superpowers/specs/2026-11-03-aggiornamento-automatico-design.md`

## Global Constraints

- Manifest: asset `dthub-release.json` di ogni release, letto da `https://github.com/EXistenz-78/dt-hub/releases/latest/download/dthub-release.json` (nessuna API di `api.github.com`); file scaricati da `https://github.com/EXistenz-78/dt-hub/releases/download/<tag>/<asset>`. `schema` deve valere `1`.
- Una sola richiesta per controllo, timeout 15 s. Il controllo all'avvio parte al massimo ogni **12 ore** (`updates.lastCheck`) e solo se `updates.checkOnLaunch` è acceso (acceso all'inizio); spento = nessuna richiesta di rete.
- Si propongono solo: l'app (se la versione è più alta) e i plug-in **già installati** con versione più alta e `contract` in `PluginContract.supported`. Mai un ritorno indietro.
- Si scarica e si installa **solo dopo** la conferma nel foglio dei dettagli; il foglio dice cosa, da dove (`github.com/EXistenz-78/dt-hub`) e quanto (per voce e totale).
- Il sha256 del manifest si verifica a blocchi di 4 MiB prima di scompattare; se non coincide non si installa nulla.
- App: `codesign --verify --deep --strict` riuscito, `CFBundleIdentifier` uguale, versione più alta, quarantena tolta; scambio con rollback; il vecchio `.app` va nel Cestino; cartella non scrivibile → `~/Downloads` + Finder. Riavvio con un `sh` staccato.
- Offline, HTTP ≠ 200, manifest illeggibile: nessun avviso all'avvio; solo «Controlla ora» mostra l'errore.
- «Più tardi» salva, per id (`app` per l'app), la versione rifiutata in `updates.dismissed`; torna solo una versione più alta.
- Nessuna dipendenza nuova. `PluginRegistry`, `ServerVersion`, `PluginKit` e i plug-in non si toccano (tranne `PluginFolder.removeQuarantine`, reso visibile al modulo).
- Testi in `App/Localizable.xcstrings`, inglese e italiano, chiavi `updates.*`. Documenti e messaggi di commit in italiano.
- Nei test una chiamata di rete reale da `swift test` va in timeout dentro la sandbox: i test normali iniettano `fetch`/`download`/`unzip`; le prove di rete vanno fuori sandbox.
- Comandi: test `cd Packages && swift test --filter <Nome> 2>&1 | grep -E "Test run with|✘|error:"`; build app `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"`.
- Ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; `git add` solo sui file toccati.

## Review Focus

1. **Nome di asset ostile nel manifest** (`../x`, `a/b`, vuoto). Il manifest si scarta. Test nella Task 1.
2. **Aggiornamento a una versione uguale o più bassa** (manifest vecchio o app più nuova di GitHub). Nessuna offerta. Test nella Task 3.
3. **Sha256 sbagliato o zip con due bundle / bundle di un'altra identità.** Nulla si installa, la voce fallisce, le altre proseguono. Test nella Task 5.
4. **Lo scambio dell'app fallisce a metà.** Il vecchio `.app` torna al suo posto. Test nella Task 6.
5. **Due controlli insieme, o un controllo mentre si installa.** Il secondo non parte e non cambia l'elenco mostrato. Test nella Task 7.

---

### Task 1: Il manifest

**Files:**
- Create: `Packages/Sources/HubCore/Updates/ReleaseManifest.swift`
- Test: `Packages/Tests/HubCoreTests/ReleaseManifestTests.swift`

**Interfaces:**
- Produces:
  - `public struct ReleaseItem: Equatable, Sendable { public let id: String; public let name: String; public let version: String; public let asset: String; public let sha256: String; public let size: Int64; public let contract: Int?; public init(...) }` (l'app ha `id == "app"`, `name == "DT Hub"`, `contract == nil`).
  - `public struct ReleaseManifest: Equatable, Sendable { public let tag: String; public let app: ReleaseItem; public let plugins: [ReleaseItem]; public static let supportedSchema = 1; public static func parse(_ data: Data) -> ReleaseManifest?; public func downloadURL(for item: ReleaseItem, base: URL) -> URL }`.
  - `public enum UpdateEndpoint { public static let releasesBase: URL` (`https://github.com/EXistenz-78/dt-hub/releases`)`; public static func manifestURL(base: URL) -> URL` (`<base>/latest/download/dthub-release.json`)`; public static var base: URL` (legge `UserDefaults` `debug.updateBaseURL`, altrimenti `releasesBase`) `}`.

- [ ] **Step 1: Scrivere i test (devono fallire)** in `ReleaseManifestTests.swift`:
  - `aValidManifestIsRead`: JSON del §1 della spec con un plug-in → `tag == "v1.0.0"`, `app.version == "1.0.0"`, `plugins[0].id`, `size == 608492`, `contract == 1`.
  - `aHigherSchemaIsRefused`: `"schema": 2` → `parse` è nil.
  - `hostileAssetNamesAreRefused`: asset `"../x.zip"`, `"a/b.zip"`, `""` (in `app` e in un plug-in) → nil per ciascuno.
  - `badChecksumsAreRefused`: sha256 di 63 caratteri o con una `g` → nil.
  - `missingFieldsAreRefused`: senza `tag`, senza `app`, versione vuota → nil.
  - `downloadURLsFollowTheTag`: con base `https://github.com/EXistenz-78/dt-hub/releases`, `downloadURL(for: app)` = `…/releases/download/v1.0.0/DT-Hub-1.0.0-macOS-arm64.zip`; `manifestURL(base:)` = `…/releases/latest/download/dthub-release.json`.

- [ ] **Step 2: Eseguire e vedere fallire** — `cd Packages && swift test --filter ReleaseManifestTests 2>&1 | grep -E "Test run with|✘|error:"` → errore di compilazione (tipi mancanti).

- [ ] **Step 3: Implementare** `ReleaseItem`, `ReleaseManifest.parse` (decodifica `Decodable` privata, poi validazione: schema, `tag`/`version`/`id`/`name` non vuoti, asset senza `/`, `\\`, `..` e non vuoto, sha256 = 64 cifre esadecimali, `size >= 0`) e `UpdateEndpoint`.

- [ ] **Step 4: Eseguire** lo stesso comando → tutti passano.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers Packages/Sources/HubCore/Updates/ReleaseManifest.swift Packages/Tests/HubCoreTests/ReleaseManifestTests.swift
git commit -m "Aggiornamenti: manifest del release e suo controllo" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Lo script che genera il manifest

**Files:**
- Create: `Scripts/make_release_manifest.py`, `Scripts/test_make_release_manifest.py` (come `make-recommended-settings.py` e il suo test)

**Interfaces:**
- Produces: `python3 Scripts/make_release_manifest.py <tag> <cartella-degli-zip> > dthub-release.json`. Esce con codice ≠ 0 e un messaggio se manca lo zip dell'app (`DT-Hub-*-macOS-arm64.zip`) o se un `.dthubplugin.zip` non ha `Contents/Info.plist`.

- [ ] **Step 1: Scrivere il test** (`unittest`, cartella temporanea con due zip finti: un `.app` con `Contents/Info.plist` `CFBundleShortVersionString` 1.0.0 e un `.dthubplugin` con `CFBundleIdentifier`, `CFBundleName`, versione 1.2, `DTHubContract` 1): il JSON ha `schema == 1`, `tag`, `app.version`, `app.sha256` = sha256 vero dello zip, `size` = dimensione vera, un plug-in con `id`, `name`, `version`, `contract`, `asset`; senza lo zip dell'app lo script esce con errore.

- [ ] **Step 2: Eseguire e vedere fallire** — `python3 -I -m unittest Scripts/test_make_release_manifest.py 2>&1 | tail -3` (dalla radice del repo; adattare al modo in cui gira `test_make_recommended_settings.py`).

- [ ] **Step 3: Implementare** con soli `zipfile`, `plistlib`, `hashlib`, `json`, `sys`, `pathlib`. Ordine dei plug-in: per nome di file.

- [ ] **Step 4: Eseguire** → il test passa. Poi, a mano: lo script sul vero release 0.9.0 scaricato in una cartella temporanea (`gh release download v0.9.0 --repo EXistenz-78/dt-hub -D "$TMPDIR/rel"`), e il risultato passa `ReleaseManifest.parse` (si controlla nella Task 9).

- [ ] **Step 5: Commit**

```bash
git add Scripts/make_release_manifest.py Scripts/test_make_release_manifest.py
git commit -m "Aggiornamenti: script che genera dthub-release.json" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Impostazioni e piano delle offerte

**Files:**
- Create: `Packages/Sources/HubCore/Updates/UpdateSettings.swift`, `Packages/Sources/HubCore/Updates/UpdatePlan.swift`
- Test: `Packages/Tests/HubCoreTests/UpdatePlanTests.swift`, `Packages/Tests/HubCoreTests/UpdateSettingsTests.swift`

**Interfaces:**
- Consumes: `ReleaseManifest`, `ReleaseItem` (Task 1); `PluginVersion` (HubKit).
- Produces:
  - `public struct UpdateOffer: Identifiable, Equatable, Sendable { public var id: String { item.id }; public let item: ReleaseItem; public let installed: String; public var isApp: Bool { item.id == "app" } }`.
  - `public enum UpdatePlan { public static func make(manifest: ReleaseManifest, appVersion: String, installedPlugins: [String: String], supportedContracts: Set<Int>) -> [UpdateOffer]` (app per prima, poi i plug-in in ordine di nome)`; public static func visible(_ offers: [UpdateOffer], dismissed: [String: String]) -> [UpdateOffer] }`.
  - `public struct UpdateSettings { public init(defaults: UserDefaults = .standard); public var checkOnLaunch: Bool` (predefinito `true`, chiave `updates.checkOnLaunch`)`; public var lastCheck: Date?` (`updates.lastCheck`)`; public var dismissed: [String: String]` (`updates.dismissed`)`; public func isDue(now: Date) -> Bool; public mutating func markChecked(at: Date); public mutating func dismiss(_ offers: [UpdateOffer]) }`.

- [ ] **Step 1: Scrivere i test (devono fallire).** `UpdatePlanTests`:
  - `anAppNewerThanTheRunningOneIsOffered` / `…SameOrOlderIsNot` (1.0.0 contro 0.9.0, 1.0.0, 1.1.0).
  - `versionsAreComparedByNumber`: plug-in 1.10 contro 1.9 → offerto.
  - `onlyInstalledPluginsAreOffered`: un plug-in del manifest non presente in `installedPlugins` non compare.
  - `aPluginOfAnUnsupportedContractWaits`: `contract: 2` con `supportedContracts: [1]` → non compare.
  - `visibleHidesWhatWasPutOffAtTheSameVersion`: `dismissed["app"] == "1.0.0"` nasconde l'app 1.0.0; con `"0.9.5"` la mostra; con `"1.1.0"` (rifiuto di una più alta) la nasconde.
  - `UpdateSettingsTests` (con `UserDefaults(suiteName:)` temporaneo): `isDue` vale `true` senza `lastCheck`; `false` a 11 h 59 min; `true` a 12 h; `false` sempre con `checkOnLaunch = false`; `dismiss` salva id → versione e un nuovo `UpdateSettings` sullo stesso suite lo rilegge.

- [ ] **Step 2: Eseguire e vedere fallire** — `swift test --filter "UpdatePlanTests|UpdateSettingsTests"`.

- [ ] **Step 3: Implementare** i due file (nessuna logica oltre ai confronti con `PluginVersion`).

- [ ] **Step 4: Eseguire** lo stesso comando → passano.

- [ ] **Step 5: Commit**

```bash
git add Packages/Sources/HubCore/Updates/UpdateSettings.swift Packages/Sources/HubCore/Updates/UpdatePlan.swift Packages/Tests/HubCoreTests/UpdatePlanTests.swift Packages/Tests/HubCoreTests/UpdateSettingsTests.swift
git commit -m "Aggiornamenti: piano delle offerte e impostazioni" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Il controllo

**Files:**
- Create: `Packages/Sources/HubCore/Updates/UpdateChecker.swift`
- Test: `Packages/Tests/HubCoreTests/UpdateCheckerTests.swift`

**Interfaces:**
- Consumes: `ReleaseManifest.parse`, `UpdateEndpoint` (Task 1).
- Produces:
  - `public enum UpdateFetch: Equatable, Sendable { case ok(Data), missing, failed }` (`missing` = HTTP 404).
  - `public enum UpdateCheckResult: Equatable, Sendable { case manifest(ReleaseManifest), noInformation, unreachable }`.
  - `public struct UpdateChecker: Sendable { public var fetch: @Sendable (URL) async -> UpdateFetch; public init(fetch:); public func check(base: URL = UpdateEndpoint.base) async -> UpdateCheckResult; public static let live: UpdateChecker }`. `check` chiama `fetch` una volta sola con `UpdateEndpoint.manifestURL(base:)`.

- [ ] **Step 1: Scrivere i test (devono fallire):** `okWithAValidManifestGivesIt`; `okWithGarbageIsNoInformation`; `missingIsNoInformation` (404: release senza manifest); `failedIsUnreachable`; `itAsksOnceAndForTheManifestURL` (un contatore e l'URL ricevuto = `manifestURL(base:)`).

- [ ] **Step 2: Eseguire e vedere fallire** — `swift test --filter UpdateCheckerTests`.

- [ ] **Step 3: Implementare** `UpdateChecker`; `live` usa `URLSession.shared.data(for:)` con `URLRequest(url:, timeoutInterval: 15)`, intestazione `Accept: application/json`, 200 → `.ok`, 404 → `.missing`, altro o errore → `.failed` (stesso stile di `GitHubReleases.fetch`).

- [ ] **Step 4: Eseguire** → passano.

- [ ] **Step 5: Commit**

```bash
git add Packages/Sources/HubCore/Updates/UpdateChecker.swift Packages/Tests/HubCoreTests/UpdateCheckerTests.swift
git commit -m "Aggiornamenti: il controllo con una sola richiesta" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Scaricare, verificare, scompattare

**Files:**
- Create: `Packages/Sources/HubCore/Updates/UpdateError.swift`, `Packages/Sources/HubCore/Updates/UpdateInstaller.swift`
- Test: `Packages/Tests/HubCoreTests/UpdateInstallerTests.swift`

**Interfaces:**
- Consumes: `ReleaseItem`, `ReleaseManifest`, `UpdateEndpoint` (Task 1); `ServerVersionChecker.sha256(ofFileAt:)`; `PluginBundleReader.read`.
- Produces:
  - `public enum UpdateError: Error, Equatable, Sendable { case download(String), checksum, unzip(String), noBundle, identityMismatch, signature, notNewer, cannotWrite(String), plugin(PluginError) }`.
  - `public struct UpdateInstaller: Sendable { public var download: @Sendable (URL, URL, @Sendable (Double) -> Void) async throws -> Void` (da URL a file di destinazione, con progresso 0…1)`; public var unzip: @Sendable (URL, URL) async throws -> Void` (zip, cartella vuota)`; public var sha256: @Sendable (URL) async -> String?; public init(...); public static let live: UpdateInstaller`.
  - `public func fetchBundle(_ item: ReleaseItem, manifest: ReleaseManifest, base: URL, work: URL, progress: @escaping @Sendable (Double) -> Void) async throws(UpdateError) -> URL` — crea `work/<item.id>/`, scarica lo zip, verifica il sha256, scompatta, trova **esattamente un** bundle (`.app` per `app`, `.dthubplugin` per un plug-in) e lo ritorna; per un plug-in verifica anche `PluginBundleReader.read(bundle)`: identificatore e versione uguali a `item.id` e `item.version`.

- [ ] **Step 1: Scrivere i test (devono fallire)** con `download` che scrive un file, `unzip` che crea cartelle finte (un `X.dthubplugin/Contents/Info.plist` vero, scritto con `PropertyListSerialization`), `sha256` finto, in una cartella temporanea:
  - `aGoodPluginComesBackAsItsBundle`.
  - `aWrongChecksumThrowsAndLeavesNoUnzippedFiles`: `.checksum`, e la cartella `work/<id>/` non contiene bundle.
  - `twoBundlesInOneZipFail` e `noBundleFails` (`.noBundle`).
  - `aBundleWithAnotherIdentifierOrVersionFails` (`.identityMismatch`).
  - `theAppBundleIsAnAppFolder`: per `app` si accetta un `.app` e non un `.dthubplugin`.
  - `aFailingDownloadIsReported` (`.download`).

- [ ] **Step 2: Eseguire e vedere fallire** — `swift test --filter UpdateInstallerTests`.

- [ ] **Step 3: Implementare.** `live.download`: `URLSession.shared.download(from:)` (delegate o `bytes` per il progresso), sposta il file in destinazione; `live.unzip`: `Process` su `/usr/bin/ditto` con `-x -k <zip> <cartella>`, errore se lo stato ≠ 0; `live.sha256`: `ServerVersionChecker.sha256(ofFileAt:)` fuori dal thread principale.

- [ ] **Step 4: Eseguire** → passano.

- [ ] **Step 5: Commit**

```bash
git add Packages/Sources/HubCore/Updates/UpdateError.swift Packages/Sources/HubCore/Updates/UpdateInstaller.swift Packages/Tests/HubCoreTests/UpdateInstallerTests.swift
git commit -m "Aggiornamenti: download, sha256 e scompattazione di una voce" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Sostituire l'app e riavviare

**Files:**
- Create: `Packages/Sources/HubCore/Updates/AppReplacer.swift`
- Modify: `Packages/Sources/HubCore/Plugins/PluginFolder.swift` (`removeQuarantine` da `static func` a `public static func`)
- Test: `Packages/Tests/HubCoreTests/AppReplacerTests.swift`

**Interfaces:**
- Consumes: `UpdateError` (Task 5); `PluginFolder.removeQuarantine(from:)`.
- Produces:
  - `public enum AppReplaceOutcome: Equatable, Sendable { case replaced, revealed(URL) }`.
  - `public struct AppReplacer: Sendable { public var verifySignature: @Sendable (URL) async -> Bool; public var move: @Sendable (URL, URL) throws -> Void; public var trash: @Sendable (URL) -> Void; public init(...); public static let live: AppReplacer`.
  - `public func replace(running: URL, runningIdentifier: String, runningVersion: String, with new: URL, work: URL, downloads: URL) async throws(UpdateError) -> AppReplaceOutcome`.
  - `public static func relaunchArguments(appAt: URL, pid: Int32) -> [String]` → `["-c", "while kill -0 <pid> 2>/dev/null; do sleep 0.2; done; open \"<percorso>\""]` (da passare a `/bin/sh`); `public static func relaunchAndQuit()` lo lancia con `Process` staccato e poi `NSApplication.shared.terminate(nil)` (non testata: solo la costruzione degli argomenti).

- [ ] **Step 1: Scrivere i test (devono fallire)** con finti `.app` (cartella con `Contents/Info.plist`: `CFBundleIdentifier`, `CFBundleShortVersionString`) in una cartella temporanea:
  - `aNewerAppTakesThePlaceOfTheOldOne`: `.replaced`; il `.app` in `running` ha la versione nuova; il vecchio è passato da `trash`.
  - `aFailureWhilePlacingTheNewAppPutsTheOldBack`: `move` che fallisce alla seconda chiamata → errore `.cannotWrite`, e `running` ha ancora la versione vecchia (**Review Focus 4**).
  - `anotherIdentifierIsRefused` (`.identityMismatch`), `anOlderOrSameVersionIsRefused` (`.notNewer`), `aBrokenSignatureIsRefused` (`.signature`, nulla si sposta).
  - `anUnwritableFolderRevealsInDownloads`: la cartella che contiene `running` non scrivibile (permessi 0o555 sulla cartella temporanea) → `.revealed(url)` con `url` dentro `downloads`.
  - `relaunchArgumentsWaitForTheProcessThenOpen`: la stringa contiene `kill -0 123` e `open "/Applications/DT Hub.app"`.

- [ ] **Step 2: Eseguire e vedere fallire** — `swift test --filter AppReplacerTests`.

- [ ] **Step 3: Implementare** `replace`: controlli (id, versione con `PluginVersion`, firma) → `removeQuarantine` sul nuovo → se `FileManager.isWritableFile(atPath:)` sulla cartella del `.app` in esecuzione è falso (o il percorso inizia con `/Volumes/`, o contiene `/AppTranslocation/`), sposta il nuovo in `downloads` e ritorna `.revealed` → altrimenti `move(running, work/aside.app)`, `move(new, running)`; se la seconda fallisce, `move(aside, running)` e rilancia; a riuscita `trash(aside)`. `live.verifySignature`: `/usr/bin/codesign --verify --deep --strict <app>` con stato 0; `live.move`: `FileManager.moveItem`; `live.trash`: `trashItem` (se fallisce, `removeItem`).

- [ ] **Step 4: Eseguire** → passano.

- [ ] **Step 5: Commit**

```bash
git add Packages/Sources/HubCore/Updates/AppReplacer.swift Packages/Sources/HubCore/Plugins/PluginFolder.swift Packages/Tests/HubCoreTests/AppReplacerTests.swift
git commit -m "Aggiornamenti: sostituzione dell'app con rollback e riavvio" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Il controller a stati

**Files:**
- Create: `Packages/Sources/HubCore/Updates/UpdateController.swift`
- Test: `Packages/Tests/HubCoreTests/UpdateControllerTests.swift`

**Interfaces:**
- Consumes: tutto delle Task 1-6.
- Produces: `@MainActor @Observable public final class UpdateController` con
  - `public enum State: Equatable { case idle, checking, installing(String, Double), finished }` e `public private(set) var state: State`;
  - `public private(set) var offers: [UpdateOffer]` (tutte), `public var visibleOffers: [UpdateOffer]` (dopo `UpdatePlan.visible`), `public private(set) var tag: String?`;
  - `public private(set) var message: UpdateMessage?` con `public enum UpdateMessage: Equatable { case upToDate, unreachable, noInformation, results([UpdateResult]) }` e `public struct UpdateResult: Equatable { public let id: String; public let name: String; public let error: UpdateError? }`;
  - `public private(set) var needsRelaunch: Bool` (l'app è stata sostituita), `public private(set) var revealedApp: URL?`;
  - `public init(checker: UpdateChecker, installer: UpdateInstaller, replacer: AppReplacer, settings: UpdateSettings, appVersion: String, appURL: URL, appIdentifier: String, installedPlugins: @escaping @MainActor () -> [String: String], installPlugin: @escaping @MainActor (URL) throws(PluginError) -> Void, now: @escaping @Sendable () -> Date = Date.init, workFolder: URL, downloads: URL, base: URL = UpdateEndpoint.base)`;
  - `public func checkOnLaunch() async` (rispetta `isDue` e l'interruttore; fallimenti in silenzio), `public func checkNow() async` (forza e imposta `message`), `public func install(_ selected: Set<String>) async` (ordine: plug-in, poi app), `public func putOff()` (chiama `dismiss(visibleOffers)`), `public var checkOnLaunchEnabled: Bool { get set }`, `public var lastCheck: Date?`.

- [ ] **Step 1: Scrivere i test (devono fallire)** con tutto iniettato:
  - `launchCheckSkipsTheNetworkWhenOffOrNotDue` (contatore di `fetch` a 0).
  - `launchCheckFailsInSilence`: `unreachable` → `message == nil`, `lastCheck` non cambia; `checkNow()` invece dà `message == .unreachable`.
  - `aNewerReleaseProducesOffersAndRemembersTheCheck`.
  - `putOffHidesThemUntilAHigherVersion`.
  - `twoChecksAtOnceMakeOneRequest`: due `checkNow()` concorrenti → un solo `fetch` (**Review Focus 5**); un `checkNow()` durante `installing` non cambia `offers`.
  - `installingDoesPluginsThenTheApp`: l'ordine delle chiamate registrato; `installPlugin` riceve il bundle; alla fine `needsRelaunch == true` e `message == .results(...)` senza errori.
  - `oneFailingItemDoesNotStopTheOthers`: sha256 sbagliato su un plug-in → quel `UpdateResult` ha `error == .checksum`, gli altri sono riusciti.
  - `onlyTheSelectedItemsAreInstalled`.
  - `aRevealedAppIsReportedNotRelaunched`: `.revealed(url)` → `revealedApp == url`, `needsRelaunch == false`.

- [ ] **Step 2: Eseguire e vedere fallire** — `swift test --filter UpdateControllerTests`.

- [ ] **Step 3: Implementare.** Un solo `Task` di controllo alla volta (un flag `isBusy`; chi arriva mentre è occupato ritorna subito). Le offerte non cambiano mentre `state == .installing`. La cartella `workFolder` si svuota a fine installazione. `installedPlugins` si ricalcola a ogni controllo.

- [ ] **Step 4: Eseguire** → passano. Poi l'intera suite del pacchetto: `swift test 2>&1 | grep -E "Test run with|✘|error:"`.

- [ ] **Step 5: Commit**

```bash
git add Packages/Sources/HubCore/Updates/UpdateController.swift Packages/Tests/HubCoreTests/UpdateControllerTests.swift
git commit -m "Aggiornamenti: il controller che guida controllo e installazione" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Interfaccia e collegamento nell'app

**Files:**
- Create: `App/Updates/UpdateBanner.swift`, `App/Updates/UpdateDetailsSheet.swift`, `App/Updates/UpdatesPreferencesView.swift`
- Modify: `App/DTHubApp.swift` (costruzione, `.task`, passaggio alle viste), `App/Preferences/PreferencesView.swift` (scheda), `App/MainWindow/MainWindowView.swift` (banner dopo `ManagedServerBanner`), `App/Localizable.xcstrings`

**Interfaces:**
- Consumes: `UpdateController` (Task 7); `plugins.entries` (`id`, `version`) per `installedPlugins`; `plugins.offer(for:)` e `plugins.install(_:)` per `installPlugin`.
- Produces: `UpdateBanner(controller:)`, `UpdateDetailsSheet(controller:)`, `UpdatesPreferencesView(controller:)`; `PreferencesView` e `MainWindowView` ricevono `updates: UpdateController`.

- [ ] **Step 1: Stringhe** in `Localizable.xcstrings`, chiavi `updates.*`, inglese e italiano: `updates.banner` («Disponibile DT Hub %@ e %lld plug-in» e le varianti solo app / solo plug-in), `updates.details`, `updates.later`, `updates.install` («Scarica e installa»), `updates.source` («da github.com/EXistenz-78/dt-hub»), `updates.total`, `updates.releaseNotes`, `updates.relaunchNow`, `updates.relaunchLater`, `updates.revealed`, `updates.checkNow`, `updates.checkOnLaunch`, `updates.lastCheck`, `updates.currentVersion`, `updates.upToDate`, `updates.unreachable`, `updates.noInformation`, `updates.item.installed`, `updates.item.failed.*` (checksum, firma, identità, scrittura), `prefs.tab.updates`.

- [ ] **Step 2: Costruire `UpdateController` in `DTHubApp.init`** con `.live` per checker, installer e replacer, `UpdateSettings()`, `appVersion` da `Bundle.main` (`CFBundleShortVersionString`), `appURL = Bundle.main.bundleURL`, `appIdentifier = Bundle.main.bundleIdentifier`, `installedPlugins = { Dictionary(uniqueKeysWithValues: plugins.entries.filter { !$0.id.hasPrefix("broken:") }.map { ($0.id, $0.version) }) }`, `installPlugin = { try plugins.install(try plugins.offer(for: $0)) }`, `workFolder` in `temporaryDirectory/DTHub-update`, `downloads` = cartella Download dell'utente. Aggiungere `.task { await updates.checkOnLaunch() }` accanto al `.task` di LM Studio.

- [ ] **Step 3: Viste.** Banner (compare quando `visibleOffers` non è vuoto e lo stato è `idle`; **Dettagli…** apre il foglio, **Più tardi** chiama `putOff()`); foglio (elenco con casella per voce, «1.1 → 1.2», dimensione, totale, origine, link alle note `https://github.com/EXistenz-78/dt-hub/releases/tag/<tag>`, avanzamento mentre installa, esito per voce, poi **Riavvia ora** / **Più tardi** o, per `revealedApp`, un pulsante «Mostra in Finder»); scheda Preferenze (versione in uso, ultimo controllo, interruttore, **Controlla ora**, messaggio, stessa lista con **Dettagli…**). Seguire lo stile di `ManagedServerBanner` e di `PluginsPreferencesView` (componenti `DS`).

- [ ] **Step 4: Build** — comando di build dei vincoli globali → `BUILD SUCCEEDED`, nessun `error:`.

- [ ] **Step 5: Provare l'interfaccia a mano** con la base locale di prova (Task 9, passi 1-2) e `defaults write com.exiztenz.DTHub debug.updateBaseURL http://localhost:8765/releases`: il banner compare, il foglio mostra voci, dimensioni e totale; lo stato senza offerte mostra «Aggiornato».

- [ ] **Step 6: Commit**

```bash
git add App/Updates App/DTHubApp.swift App/Preferences/PreferencesView.swift App/MainWindow/MainWindowView.swift App/Localizable.xcstrings
git commit -m "Aggiornamenti: banner, foglio dei dettagli e scheda Preferenze" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Prova con un release di prova, README, verifica finale

**Files:**
- Modify: `README.md`, `Plugins/README.md`

- [ ] **Step 1: Preparare il release di prova (fuori sandbox, senza toccare il repository pubblico).** In una cartella temporanea: lo zip della 0.9.0 reale (`gh release download v0.9.0 --repo EXistenz-78/dt-hub -D "$TMPDIR/rel"`), uno zip dell'app con `CFBundleShortVersionString` alzato a `1.0.0-prova` (la copia del `.app` 0.9.0 con `Info.plist` modificato e ri-firmata ad-hoc con `codesign --force --deep -s -`), un plug-in con versione alzata (stessa procedura). Generare `dthub-release.json` con `Scripts/make_release_manifest.py v1.0.0-prova`. Disporre i file come `releases/latest/download/dthub-release.json` e `releases/download/v1.0.0-prova/<asset>` e servirli con `python3 -m http.server 8765`.

- [ ] **Step 2: Provare il flusso.** Con `defaults write com.exiztenz.DTHub debug.updateBaseURL http://localhost:8765/releases`, avviare una build 0.9.0 dell'app **copiata in una cartella scrivibile di prova** (non quella installata): il banner compare; con «Scarica e installa» il plug-in si aggiorna, il `.app` si scambia, «Riavvia ora» riapre la versione nuova. Provare anche: sha256 manomesso nel manifest (nulla si installa), server spento (nessun avviso all'avvio, errore con «Controlla ora»), cartella non scrivibile (Finder). Se `http://localhost` è bloccato da App Transport Security, aggiungere `NSAllowsLocalNetworking` come già fa la sorgente LM Studio e annotarlo nel piano. Poi `defaults delete com.exiztenz.DTHub debug.updateBaseURL`.

- [ ] **Step 3: README.** In `README.md` una sezione «Aggiornamenti» (cosa controlla, da dove, cosa manda — niente —, che chiede conferma, l'interruttore, `debug.updateBaseURL` non va documentato) e aggiornare il punto di installazione e la frase sulla rete; in `Plugins/README.md` una riga: i plug-in installati si aggiornano dal banner; e in «Release» come pubblicare il manifest (`python3 Scripts/make_release_manifest.py <tag> <cartella>` e caricarlo come asset `dthub-release.json`).

- [ ] **Step 4: Verifica finale.** `cd Packages && swift test 2>&1 | grep -E "Test run with|✘|error:"` → tutti passano; la build dell'app riesce; `git status` pulito dei soli file attesi.

- [ ] **Step 5: Commit**

```bash
git add README.md Plugins/README.md
git commit -m "Aggiornamenti: README e prova con un release di prova" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
