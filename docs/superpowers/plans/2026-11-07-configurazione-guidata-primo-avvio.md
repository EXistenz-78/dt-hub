# Configurazione guidata al primo avvio: piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Uno sheet di primo avvio che porta l'utente a un server Draw Things configurato, una cartella di output e (facoltativo) un modello linguistico.

**Architecture:** La logica pura (quando mostrare, ordine dei passi, regole del passo server) vive in HubCore ed è testata con Swift Testing. L'app ha `OnboardingState` (`@Observable`) che la usa, uno sheet contenitore e una vista snella per passo che richiamano la logica esistente (`DrawThingsConnection.apply`, `GenerationController.setOutputFolder`, `LanguageModelManager`, `LanguageModelDownloadController`).

**Tech Stack:** Swift 6.2, SwiftUI, Observation, Swift Testing, `App/Localizable.xcstrings`.

**Spec:** `docs/superpowers/specs/2026-11-07-configurazione-guidata-primo-avvio-design.md`

## Global Constraints

- Passi: Benvenuto, Server, Output, Modello linguistico, Fine. Aggiornamenti/privacy restano fuori.
- Chiave UserDefaults del completamento: `onboarding.completed`. Non si mostra se esistono `drawThings.connection` o `drawThings.managedServer` (chiavi di `ConnectionSettingsStore` / `ManagedServerSettingsStore`, non ridefinirle come stringhe).
- Server: Draw Things già attivo, ServerCLI o entrambi; Avanti bloccato finché almeno uno è configurato. Il CLI è configurato se `ManagedServerSettings.validationError() == nil`; Draw Things già attivo solo dopo **Connetti**. Con entrambi, selettore con default "Draw Things già attivo".
- Link di download e pulsante **Scegli…** del ServerCLI sempre visibili. Binario precompilato con `CLILocator.find()`.
- Connessione fallita non blocca Avanti. Nessun download del modello senza la conferma che nomina dimensione e destinazione.
- Stringhe in `App/Localizable.xcstrings`, chiavi `onboarding.*`, en e it (il target `CatalogTests` le verifica). Riusare le chiavi `prefs.*` dove il testo è identico.
- Voce di menu "Aiuto → Configurazione guidata".
- Commit solo quando l'utente lo chiede; i passi "Commit" sotto sono da eseguire solo se confermato.

## Review Focus

- Sheet di onboarding e `ProjectGateSheet` insieme al primo avvio: l'onboarding compare solo con `projects.didStart && projects.current != nil`, mai sopra il gate del progetto (Task 6).
- Aggiornamento da versione esistente con solo `drawThings.managedServer` salvato (nessuna `drawThings.connection`): non mostrare lo sheet (Task 1).
- Valore di `onboarding.completed` non Bool o chiavi con dati illeggibili: trattare come non completato ma senza crash (Task 1).
- Binario del CLI non eseguibile con cartella modelli valida: blocco non configurato, Avanti resta bloccato (Task 2).
- Chiusura con Esc a metà percorso: il flag viene impostato e ciò che è già applicato resta (Task 3).

## File Structure

- Create `Packages/Sources/HubCore/Onboarding/OnboardingGate.swift`: quando mostrare lo sheet.
- Create `Packages/Sources/HubCore/Onboarding/OnboardingFlow.swift`: passi e navigazione.
- Create `Packages/Sources/HubCore/Onboarding/OnboardingServerPlan.swift`: regole del passo server.
- Create `App/Onboarding/OnboardingState.swift`: stato osservabile e persistenza del flag.
- Create `App/Onboarding/OnboardingSheet.swift`: contenitore, indicatore, barra Indietro/Salta/Avanti.
- Create `App/Onboarding/OnboardingServerStep.swift`, `OnboardingOutputStep.swift`, `OnboardingLanguageStep.swift`, `OnboardingWelcomeAndDoneSteps.swift`.
- Modify `App/MainWindow/MainWindowView.swift` (sheet), `App/DTHubApp.swift` (stato, menu Aiuto), `App/Localizable.xcstrings`.
- Test: `Packages/Tests/HubCoreTests/OnboardingGateTests.swift`, `OnboardingFlowTests.swift`, `OnboardingServerPlanTests.swift`.

---

### Task 1: OnboardingGate

**Files:**
- Create: `Packages/Sources/HubCore/Onboarding/OnboardingGate.swift`
- Test: `Packages/Tests/HubCoreTests/OnboardingGateTests.swift`

**Interfaces:**
- Produces: `public enum OnboardingGate { public static let completedKey = "onboarding.completed"; public static func shouldShow(defaults: UserDefaults = .standard) -> Bool; public static func markCompleted(defaults: UserDefaults = .standard) }`

- [ ] **Step 1: Write the failing tests** in `OnboardingGateTests`, each with a private `UserDefaults(suiteName: UUID().uuidString)`:
  - `showsOnAFreshInstall`: nessuna chiave → `shouldShow == true`.
  - `hidesAfterCompletion`: dopo `markCompleted` → `false`.
  - `hidesWhenAConnectionWasSaved`: `ConnectionSettingsStore(defaults:).save(.default)` → `false`.
  - `hidesWhenOnlyTheManagedServerWasSaved`: `ManagedServerSettingsStore(defaults:).save(.default)` → `false` (Review Focus).
  - `anUnreadableCompletedValueCountsAsNotCompleted`: `defaults.set("x", forKey: OnboardingGate.completedKey)` → `true`, senza crash.
- [ ] **Step 2: Run** `swift test --package-path Packages --filter OnboardingGateTests`. Expected: FAIL (tipo non definito).
- [ ] **Step 3: Implement `OnboardingGate`** come da Interfaces; `shouldShow` è `false` se `defaults.bool(forKey:)` è vero o se `defaults.data(forKey:)` esiste per `ConnectionSettingsStore.key` o `ManagedServerSettingsStore.key`.
- [ ] **Step 4: Run** lo stesso comando. Expected: PASS.
- [ ] **Step 5: Commit** (se confermato): `git add Packages/Sources/HubCore/Onboarding Packages/Tests/HubCoreTests/OnboardingGateTests.swift && git commit -m "Primo avvio: regola per mostrare la configurazione guidata"`

### Task 2: OnboardingFlow e OnboardingServerPlan

**Files:**
- Create: `Packages/Sources/HubCore/Onboarding/OnboardingFlow.swift`, `OnboardingServerPlan.swift`
- Test: `Packages/Tests/HubCoreTests/OnboardingFlowTests.swift`, `OnboardingServerPlanTests.swift`

**Interfaces:**
- Produces:
  - `public enum OnboardingStep: Int, CaseIterable, Sendable { case welcome, server, output, language, done }`
  - `public struct OnboardingFlow: Sendable { public private(set) var step: OnboardingStep; public init(); public var isFirst: Bool; public var isLast: Bool; public mutating func next(); public mutating func back() }` (non esce dai limiti)
  - `public struct OnboardingServerPlan: Sendable { public init(attach: ConnectionSettings, attachConfirmed: Bool, managed: ManagedServerSettings, files: FileSystemProbe = .live, choice: ServerMode = .attach); public var attachConfigured: Bool; public var managedConfigured: Bool; public var canAdvance: Bool; public var needsChoice: Bool; public var resolvedMode: ServerMode? }`
- Regole di `OnboardingServerPlan`: `attachConfigured = attachConfirmed && attach.validationError == nil`; `managedConfigured = managed.validationError(files) == nil`; `canAdvance` se almeno uno; `needsChoice` se entrambi; `resolvedMode` = `choice` se entrambi, l'unico configurato altrimenti, `nil` se nessuno.

- [ ] **Step 1: Write the failing tests.** Flow: parte da `.welcome`; `back()` su `.welcome` resta lì; `next()` cinque volte finisce su `.done` e `isLast`. Plan (con `FileSystemProbe(isExecutableFile: { $0 == "/bin/cli" }, isDirectory: { $0 == "/models" })`): nessun blocco configurato → `canAdvance == false`, `resolvedMode == nil`; attach valido ma non confermato → `false` (default sempre valido); attach confermato → `true`, `resolvedMode == .attach`; solo CLI valido → `resolvedMode == .managed`, `needsChoice == false`; entrambi → `needsChoice`, `resolvedMode == choice` per `.attach` e `.managed`; CLI con binario `/nowhere` e cartella valida → non configurato (Review Focus).
- [ ] **Step 2: Run** `swift test --package-path Packages --filter "OnboardingFlowTests|OnboardingServerPlanTests"`. Expected: FAIL.
- [ ] **Step 3: Implement** i tipi come da Interfaces.
- [ ] **Step 4: Run** lo stesso comando. Expected: PASS.
- [ ] **Step 5: Commit** (se confermato): `git add Packages && git commit -m "Primo avvio: passi e regole del passo server"`

### Task 3: OnboardingState e stringhe base

**Files:**
- Create: `App/Onboarding/OnboardingState.swift`
- Modify: `App/Localizable.xcstrings`

**Interfaces:**
- Consumes: `OnboardingGate`, `OnboardingFlow`, `OnboardingStep`.
- Produces: `@MainActor @Observable final class OnboardingState { var flow: OnboardingFlow; var isPresented: Bool; init(defaults: UserDefaults = .standard); func presentIfFirstLaunch(); func reopen(); func finish() }`. `finish()` chiama `OnboardingGate.markCompleted`, mette `isPresented = false`. `reopen()` riparte da `.welcome` e imposta `isPresented = true` ignorando il flag. Anche la chiusura da Esc/Salta passa da `finish()`.

- [ ] **Step 1:** Implementare `OnboardingState` come da Interfaces; `presentIfFirstLaunch()` imposta `isPresented = OnboardingGate.shouldShow(defaults:)` solo se `flow` è ancora al primo passo.
- [ ] **Step 2:** Aggiungere in `Localizable.xcstrings` (en e it, `state: translated`, `extractionState: manual`, come le chiavi esistenti) le chiavi `onboarding.title`, `onboarding.back`, `onboarding.next`, `onboarding.skip`, `onboarding.finish`, `onboarding.step.welcome|server|output|language|done`, `onboarding.menu`.
- [ ] **Step 3: Run** `swift test --package-path Packages --filter CatalogTests`. Expected: PASS.
- [ ] **Step 4: Commit** (se confermato): `git add App && git commit -m "Primo avvio: stato dello sheet e stringhe base"`

### Task 4: Passo Server

**Files:**
- Create: `App/Onboarding/OnboardingServerStep.swift`
- Modify: `App/Localizable.xcstrings`

**Interfaces:**
- Consumes: `OnboardingServerPlan`, `DrawThingsConnection` (`apply`, `indicator`, `monitor.lastError`, `settings`, `managed`, `savedSecret()`), `CLILocator`.
- Produces: `struct OnboardingServerStep: View { init(connection: DrawThingsConnection, canAdvance: Binding<Bool>) }`; scrive `canAdvance` a ogni cambio di bozza o di `attachConfirmed`; applica la modalità risolta con `connection.apply(...)` alla pressione di Connetti e da `OnboardingSheet` all'uscita dal passo con Avanti (`func applyIfNeeded() async`, esposta tramite un piccolo oggetto `OnboardingServerDraft` `@Observable` posseduto da `OnboardingSheet`).

- [ ] **Step 1:** Costruire due `Section` sempre visibili. Blocco 1 (Draw Things già attivo): campi host/porta/TLS/segreto come `DrawThingsPreferencesView.attachSection`, messaggi di `validationError`, pulsante **Connetti** che imposta `attachConfirmed = true` e chiama `apply` con `managed.mode = .attach` (o la modalità risolta). Blocco 2 (ServerCLI): campo binario + **Scegli…**, cartella modelli + **Scegli…** + **Usa quella dell'app Draw Things** (`CLILocator.drawThingsAppModelsFolder()`), porta; `Link` ai download (`https://github.com/drawthingsai/draw-things-community/releases`) **sempre visibile**; binario iniziale da `CLILocator.find()`; avvisi `warning()` e `PrivacySettingsLink` come nelle Preferenze.
- [ ] **Step 2:** Se `plan.needsChoice`, `Picker` segmentato "Quale usare ora?" con default `.attach`. Mostrare lo stato di connessione (`DSStatusDot(status: connection.indicator)` + testo da `ConnectionStatusText.headline`).
- [ ] **Step 3:** Aggiungere le chiavi `onboarding.server.*` (en/it); riusare `prefs.dt.*` e `prefs.server.*` per etichette identiche. Run `swift test --package-path Packages --filter CatalogTests`. Expected: PASS.
- [ ] **Step 4: Build** `xcodebuild -project DTHub.xcodeproj -scheme DTHub -configuration Debug build` (verificare lo scheme con `xcodebuild -list -project DTHub.xcodeproj`). Expected: BUILD SUCCEEDED.
- [ ] **Step 5: Commit** (se confermato): `git add App && git commit -m "Primo avvio: passo server"`

### Task 5: Passi Output, Modello linguistico, Benvenuto e Fine

**Files:**
- Create: `App/Onboarding/OnboardingOutputStep.swift`, `OnboardingLanguageStep.swift`, `OnboardingWelcomeAndDoneSteps.swift`
- Modify: `App/Localizable.xcstrings`

**Interfaces:**
- Consumes: `GenerationController.outputFolder`/`setOutputFolder(_:)`, `ProjectManager.refresh()`, `LanguageModelManager` (`settings.backend`, `settings.folder`, `settings.serverURL`, `refreshServerModels()`, `availableModels()`, `serverError`), `LanguageModelDownloadController` (`start(repository:to:)`, `progress`, `cancel()`, `failure`), `RecommendedLanguageModel`.
- Produces: `OnboardingOutputStep(controller:projects:)`, `OnboardingLanguageStep(manager:download:)`, `OnboardingWelcomeStep()`, `OnboardingDoneStep(summary:)`.

- [ ] **Step 1: Output.** Cartella corrente, **Scegli…** (`NSOpenPanel` con `canCreateDirectories`, poi `controller.setOutputFolder(url)` e `projects.refresh()`), **Mostra nel Finder**. Come `OutputPreferencesView`.
- [ ] **Step 2: Modello linguistico.** `Picker` segmentato LM Studio / Cartella MLX (`manager.settings.backend`). LM Studio: indirizzo, **Prova**, elenco dei modelli (nessuna scelta di famiglia/uso). Cartella: campo + **Scegli…**, e **Scarica il modello consigliato** dietro `confirmationDialog` che riusa `prefs.llm.download.confirm.*` con dimensione (`RecommendedLanguageModel.approximateBytes`) e cartella; avanzamento e **Annulla**; errori come in `LanguagePreferencesView.downloadRow`.
- [ ] **Step 3: Benvenuto e Fine.** Benvenuto: una riga su cosa serve. Fine: riepilogo (server: modalità e stato; output: cartella; modello: scelto o saltato) e pulsante **Inizia** che chiama `OnboardingState.finish()`.
- [ ] **Step 4:** Chiavi `onboarding.output.*`, `onboarding.language.*`, `onboarding.welcome.*`, `onboarding.done.*` (en/it). Run `swift test --package-path Packages --filter CatalogTests`. Expected: PASS.
- [ ] **Step 5: Build** come nel Task 4. Expected: BUILD SUCCEEDED.
- [ ] **Step 6: Commit** (se confermato): `git add App && git commit -m "Primo avvio: passi output, modello linguistico, benvenuto e fine"`

### Task 6: Sheet contenitore, cablaggio e menu

**Files:**
- Create: `App/Onboarding/OnboardingSheet.swift`
- Modify: `App/MainWindow/MainWindowView.swift`, `App/DTHubApp.swift`

**Interfaces:**
- Consumes: tutto quanto sopra.
- Produces: `OnboardingSheet(state:connection:generation:languageModel:download:projects:)`; `MainWindowView` riceve `onboarding: OnboardingState`.

- [ ] **Step 1: `OnboardingSheet`.** Titolo, indicatore dei passi (`OnboardingStep.allCases`), vista del passo corrente, barra **Indietro / Salta / Avanti**. Avanti disabilitato nel passo server finché `canAdvance` è falso; su Avanti dal passo server applica la bozza (`applyIfNeeded`). **Salta** e la chiusura con Esc chiamano `state.finish()` (`.interactiveDismissDisabled(false)` con `onDismiss`).
- [ ] **Step 2: `MainWindowView`.** Aggiungere `.sheet(isPresented:)` su `onboarding.isPresented`, ma con binding che è vero solo se `projects.didStart && projects.current != nil` (Review Focus); chiamare `onboarding.presentIfFirstLaunch()` in un `.task` dopo `projects.start()`.
- [ ] **Step 3: `DTHubApp`.** Creare `@State private var onboarding = OnboardingState()`, passarlo a `MainWindowView`, e aggiungere `CommandGroup(replacing: .help) { Button(String(localized: "onboarding.menu")) { onboarding.reopen() } }`.
- [ ] **Step 4: Build** `xcodebuild -project DTHub.xcodeproj -scheme DTHub -configuration Debug build`. Expected: BUILD SUCCEEDED. Run `swift test --package-path Packages`. Expected: tutti PASS.
- [ ] **Step 5: Verifica manuale.** `defaults delete com.exiztenz.DTHub` e avvio. Controllare: (a) lo sheet compare dopo che il progetto è aperto; (b) solo Draw Things: Avanti si abilita dopo Connetti; (c) solo CLI senza binario: link e Scegli… visibili, Avanti bloccato; (d) entrambi: selettore con default Draw Things; (e) Esc a metà chiude e non riappare al riavvio; (f) con `drawThings.connection` già salvata non compare; (g) Aiuto → Configurazione guidata la riapre.
- [ ] **Step 6: Commit** (se confermato): `git add App && git commit -m "Primo avvio: sheet di configurazione guidata e voce di menu Aiuto"`
