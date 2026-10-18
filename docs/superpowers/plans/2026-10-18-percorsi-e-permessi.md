# Percorsi predefiniti puliti e permessi — Piano di implementazione

> **Per chi esegue:** SOTTO-SKILL OBBLIGATORIA: `superpowers:executing-plans` oppure `superpowers:subagent-driven-development`. I passi usano la sintassi a caselle (`- [ ]`).

**Obiettivo:** nessun percorso dello sviluppatore come default; cartelle senza permesso riconosciute e spiegate; descrizioni d'uso per i permessi di macOS.

**Spec:** `docs/superpowers/specs/2026-10-18-percorsi-e-permessi-design.md`.

## Vincoli globali

- **Ramo e pubblicazione:**
  - base `origin/main` (0.3.0 o successiva), ramo nuovo (es. `percorsi-permessi`);
  - **niente unione, push o release senza via libera esplicito**;
  - file aggiunti **per nome**.
- **Lingua:** commenti in inglese; testi it/en in `App/Localizable.xcstrings` e `App/InfoPlist.xcstrings`.
- **Nessuna migrazione** delle impostazioni salvate.

## Review Focus

1. Il nuovo default non contiene `/Volumes` e non viene creato all'avvio (Task 1).
2. `denied` si distingue da `missing` e da «vuota» con un errore reale di macOS, non solo nei test (Task 2, prova a mano 4).
3. Il server «managed» si avvia ancora con una cartella che DT Hub non riesce a leggere (Task 3).
4. L'errore di scaricamento nomina la cartella dei modelli, non la cartella temporanea (Task 4).

---

### Task 1: Nuovo default LLM

**Files:** Modify `Packages/Sources/HubCore/Language/LanguageModelSettings.swift`, `Packages/Tests/HubCoreTests/LanguageModelTests.swift` (riga 63).

- [ ] **Step 1: Test** — sostituire l'attesa `"/Volumes/LLM-VLM/MLX"`:
  - `folder.hasSuffix("Application Support/DT Hub/LLM")`;
  - `!folder.contains("/Volumes")`.
- [ ] **Step 2: Implementare:**
  - `public static var defaultFolder: String` = `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DT Hub/LLM", isDirectory: true).path`;
  - commento di `folder`: «Where the models are (spec §9); by default a folder in DT Hub's Application Support, created when first needed»;
  - l'`init(from:)` usa già il default per un campo mancante: nessun altro cambiamento.
- [ ] **Step 3:** `cd Packages && swift test --filter LanguageModel` verde.
- [ ] **Step 4: Commit** — `fix(llm): cartella dei modelli predefinita nella Libreria dell'utente`.

### Task 2: `FolderAccess`

**Files:** Create `Packages/Sources/HubCore/Files/FolderAccess.swift`, `Packages/Tests/HubCoreTests/FolderAccessTests.swift`.

- [ ] **Step 1: Test** (cartelle temporanee):
  - cartella esistente → `.readable`;
  - percorso inesistente → `.missing`;
  - cartella con `chmod 000` → `.denied`, con `defer` che rimette `0o755`;
  - un file al posto della cartella → `.readable` (comportamento di oggi: lo decide chi chiama).
- [ ] **Step 2: Implementare** come la spec §4.2:
  - `enum FolderAccess { case readable, missing, denied }`;
  - `static func access(of:fileManager:)`;
  - `denied` se l'errore è `CocoaError(.fileReadNoPermission)`, oppure se `NSUnderlyingErrorKey` è un `POSIXError` `EACCES`/`EPERM`.
- [ ] **Step 3:** test verdi.
- [ ] **Step 4: Commit** — `feat(core): distinguere una cartella senza permesso da una vuota`.

### Task 3: Modelli di Draw Things («managed»)

**Files:** Modify `Packages/Sources/HubCore/Server/ManagedServerSettings.swift`, `App/Preferences/DrawThingsPreferencesView.swift`, `App/Localizable.xcstrings`; Test in `Packages/Tests/HubCoreTests/` (il file dei test di `ManagedServerSettings`).

- [ ] **Step 1: Test:**
  - sonda con `folderAccess` = `.denied` e `hasModelFiles` falso → `warning() == .modelsFolderDenied`;
  - `.readable` e nessun `.ckpt` → `.noModelFiles`, come oggi;
  - `validationError()` resta `nil` con `.denied` (**Review Focus 3**).
- [ ] **Step 2: Implementare:**
  - `FileSystemProbe.folderAccess: @Sendable (String) -> FolderAccess`, default `{ _ in .readable }` nell'`init` (i test di oggi non cambiano); `live` usa `FolderAccess.access(of:)`;
  - `Warning.modelsFolderDenied`, controllato prima di `hasModelFiles`.
- [ ] **Step 3: Vista:** con `.modelsFolderDenied`, il testo `prefs.folder.denied` in rosso + `PrivacySettingsLink()` (Task 5).
- [ ] **Step 4: Commit** — `fix(server): avviso per una cartella dei modelli senza permesso`.

### Task 4: Errore di scaricamento

**Files:** Modify `Packages/Sources/HubKit/Language/LanguageModel.swift` (`LanguageModelError`), `Packages/Sources/HubKit/Language/LanguageModelError+Plain.swift`, `Packages/Sources/LLMBridge/HubLanguageModelDownloader.swift`, `App/Preferences/LanguagePreferencesView.swift` (riga ~323), `App/Localizable.xcstrings`; Test nei test di LLMBridge.

Oggi: la vista chiama `download.start(to: <cartella>/<RecommendedLanguageModel.folderName>)`; il downloader lavora nella cartella madre di quella destinazione; il testo grezzo di sistema arriva con `.downloadFailed(String)`.

- [ ] **Step 1: Test** — destinazione `X/models/<nome>` con `X` a `chmod 555` (e `defer` che rimette `0o755`):
  - il downloader lancia `LanguageModelError.folderNotWritable`;
  - l'errore arriva da `createDirectory`, prima di qualunque richiesta di rete.
- [ ] **Step 2: Implementare:**
  - `LanguageModelError.folderNotWritable(String)`, col percorso che non si è potuto scrivere;
  - nel `catch` del downloader: un errore di permesso (`CocoaError` `.fileWriteNoPermission` / `.fileReadNoPermission`, oppure POSIX `EACCES`/`EPERM`/`EROFS` diretto o in `NSUnderlyingErrorKey`) → `.folderNotWritable`; gli altri errori come oggi;
  - `LanguageModelError+Plain`: testo inglese della spec §4.6;
  - **tutti gli `switch` su `LanguageModelError`** segnalati dal compilatore vanno completati.
- [ ] **Step 3: App:** in `LanguagePreferencesView`, `.folderNotWritable` mostra `llm.download.noWritePermission` (it/en, spec §4.6) con `%@` = `manager.settings.folder`, cioè la cartella scelta dall'utente, non quella temporanea (**Review Focus 4**); sotto, `PrivacySettingsLink()`.
- [ ] **Step 4: Commit** — `fix(llm): errore chiaro quando la cartella dei modelli non è scrivibile`.

### Task 5: Preferenze › LLM e pulsanti

**Files:** Create `App/Preferences/PrivacySettingsLink.swift`. Modify `App/Preferences/LanguagePreferencesView.swift`, `App/Localizable.xcstrings`.

- [ ] **Step 1: `PrivacySettingsLink`:** pulsante «Apri Privacy e sicurezza» che apre l'indirizzo della spec §4.5; se `NSWorkspace.open` dà falso, apre quello di ripiego.
- [ ] **Step 2: «Mostra nel Finder»** accanto a «Scegli…»: `createDirectory(withIntermediateDirectories: true)` e `NSWorkspace.shared.open`, come `OutputPreferencesView` (righe 50–51).
- [ ] **Step 3: Messaggi** sotto il campo (spec §4.3), con `FolderAccess.access(of: manager.settings.folder)` calcolato in `refresh()`.
- [ ] **Step 4: Testi** (it/en):
  - `prefs.folder.denied`: «DT Hub non ha il permesso di leggere questa cartella.» / «DT Hub does not have permission to read this folder.»;
  - `prefs.privacy.open`: «Apri Privacy e sicurezza» / «Open Privacy & Security»;
  - `prefs.llm.folder.missing`: «La cartella non esiste: verrà creata al primo scaricamento.» / «The folder does not exist: it will be created at the first download.»;
  - pulsante «Mostra nel Finder»: riusare la chiave `prefs.output.reveal` di Uscita.
- [ ] **Step 5: Commit** — `feat(prefs): cartella LLM nel Finder e messaggio per i permessi`.

### Task 6: Descrizioni d'uso

**Files:** Modify `Config/Info.plist`. Create `App/InfoPlist.xcstrings` (il gruppo `App` è sincronizzato: Xcode lo prende da solo).

- [ ] **Step 1:** le 5 chiavi della spec §3 in `Info.plist`, col testo inglese della spec §4.7; commento in testa aggiornato.
- [ ] **Step 2:** `InfoPlist.xcstrings` con le stesse chiavi, it ed en.
- [ ] **Step 3: Controllo:** dopo `xcodebuild … build`, `plutil -p "build/Build/Products/Debug/DT Hub.app/Contents/Info.plist" | grep UsageDescription` mostra 5 righe, e `Contents/Resources/it.lproj/InfoPlist.strings` esiste.
- [ ] **Step 4: Commit** — `feat(app): descrizioni d'uso per dischi esterni, di rete e cartelle protette`.

### Task 7: Compilazione, prove, messaggio finale

- [ ] **Step 1:**
  - `cd Packages && swift test`;
  - `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build`.
- [ ] **Step 2: `grep -rn "LLM-VLM\|/Volumes/" App Packages/Sources`:** nessun risultato, tranne i commenti che parlano di dischi esterni in generale.
- [ ] **Step 3: Prove a mano** (spec §5, 1–6). Per ripartire da zero:
  - `tccutil reset All com.exiztenz.dthub`;
  - un utente macOS di prova per il primo avvio (oppure `defaults delete com.exiztenz.dthub` **solo** su un utente di prova).
- [ ] **Step 4: Messaggio finale** (briefing §6):
  - cosa provare;
  - **«Decisioni che ho preso»**, ognuna col suo costo: il modo di riconoscere `denied`, il nuovo caso `folderNotWritable` (Task 4), l'indirizzo di Privacy e sicurezza;
  - **«Rinviati»** (spec §6);
  - via libera prima di unire, push o release;
  - **note di rilascio:** «La cartella dei modelli LLM predefinita è ora in ~/Library/Application Support/DT Hub/LLM; chi aveva già una cartella la mantiene».
