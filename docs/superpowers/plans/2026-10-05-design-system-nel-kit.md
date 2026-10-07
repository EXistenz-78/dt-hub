# Il design system nel kit dei plug-in — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Il design system dell'app (card, pulsanti a pillola, caselle teal, intestazioni, vetro) passa in un modulo del pacchetto `PluginKit` che l'app e i plug-in condividono; Sphere Light lo usa e il suo tab ha l'aspetto dell'app.

**Architecture:**
- Nuovo modulo `DTHubDesign` (prodotto di `PluginKit`, solo SwiftUI) con otto file spostati da `Packages/Sources/HubKit/DesignSystem/`; `HubKit` lo dichiara come dipendenza e lo **riesporta** (`@_exported import`), quindi `import HubKit` dà ancora `DS…` a tutta l'app e ai suoi moduli.
- `DSCollapsibleCard` ottiene un accessorio opzionale a destra del titolo.
- Un plug-in prende **due prodotti**, `DTHubPluginKit` e `DTHubDesign`, ognuno con il suo `moduleAliases` (il kit **non** riesporta il design system: con gli alias non si risolve, vedi il Ruling sotto).
- Sphere Light rifà `LightControlView` e `SphereLightView` con i componenti.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftPM (`moduleAliases`), Xcode 27, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-05-plugin-design-system-design.md`.

## Global Constraints

- **Repository:** radice `<repo>` (percorsi tra virgolette); branch `design-kit` da `main`.
- **Nessun cambio d'aspetto** dei componenti esistenti, salvo l'accessorio di `DSCollapsibleCard` (gli usi senza accessorio compilano e si vedono come prima). Nessun file di `App/` cambia.
- **Il contratto resta 1**; nel modulo `DTHubDesign` non ci sono classi Objective-C del kit né `DTHubPluginKit`. L'app non collega `DTHubPluginKit`.
- **Pacchetti:** `Packages/Package.swift` dipende da `.package(name: "PluginKit", path: "../PluginKit")` e `HubKit` dal prodotto `DTHubDesign`; `PluginKit/Package.swift` ha i prodotti `DTHubPluginKit` e `DTHubDesign` e due target di test.
- **Plug-in:** `moduleAliases` per il kit (`SphereLightKit`) e per il design (`SphereLightDesign`), ognuno sul suo prodotto; nel bundle nessun simbolo `DTHubDesign` né `DTHubPluginKit` senza alias.
- **Stringhe:** Sphere Light non usa `Bundle.module` né `String(localized:)`: restano nella tabella `L`.
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Blocchi `diff`:** modifiche ai file già esistenti, da salvare in un file e applicare dalla radice con `git apply --whitespace=nowarn <file>`; i blocchi dei file nuovi o riscritti si salvano così come sono.
- **L'app di prova** condivide le preferenze con quella dell'utente e i processi hanno lo stesso identificatore: **se l'app dell'utente è aperta non pilotare le finestre**; annotare e rimettere `workspace.selectedTab`; lo stato di Sphere Light (`com.exiztenz.dthub.spherelight.state.v1`) è nelle preferenze dell'utente: **non cancellarlo** e non salvare luci di prova.
- **Fuori:** cambiare l'aspetto dei componenti; ridisegnare altri tab; il kit che riesporta il design system.

## Review Focus

- **Chi usava `import HubKit` e `DS…` compila senza cambiare un file** (l'app, `HubCore`, i test): test `hubKitStillGivesTheWholeDesignSystem` (Task 1) e la build Xcode di Task 1 e 2.
- **Gli usi di `DSCollapsibleCard` senza accessorio** compilano com'erano (la build Xcode del Task 2 li compila tutti: Generazione, Control, Preferenze).
- **Il bundle di un plug-in non ha simboli senza alias** (Task 3: `nm`), così due plug-in e l'app non definiscono lo stesso tipo due volte.
- **L'esempio `Sample` si costruisce ancora** (Task 3: `build-sample.sh`).
- **Il tab con 1, 2 e 3 luci** (il pulsante «togli» sparisce con una sola luce; il pulsante «Aggiungi» sparisce a tre) e **con l'app che carica due plug-in insieme** senza avvisi di classi duplicate (Task 4, a mano).

## Ruling (preso scrivendo il piano)

Il kit **non** riesporta `DTHubDesign`: provato nel prototipo, `@_exported import DTHubDesign` dentro `DTHubPluginKit` con `moduleAliases` dà «unable to resolve module dependency: 'DTHubDesign'» (l'alias del secondo modulo non arriva al modulo del kit). Un plug-in prende quindi i due prodotti, ognuno con il suo alias; la spec e il README lo dicono (Task 4).

---

### Task 1: Il modulo `DTHubDesign` e i collegamenti

**Files:**
- `Packages/Package.swift`, `Packages/Sources/HubKit/DesignSystem/DS.swift`, `Packages/Sources/HubKit/DesignSystem/DSBackground.swift`, `Packages/Sources/HubKit/DesignSystem/DSButtons.swift`, `Packages/Sources/HubKit/DesignSystem/DSCardRow.swift`, `Packages/Sources/HubKit/DesignSystem/DSCollapsibleCard.swift`, `Packages/Sources/HubKit/DesignSystem/DSGlass.swift`, `Packages/Sources/HubKit/DesignSystem/DSPanel.swift`, `Packages/Sources/HubKit/DesignSystem/DSStatusDot.swift`, `Packages/Sources/HubKit/DesignSystem/DSTabFrame.swift`, `Packages/Sources/HubKit/DesignSystem/DesignReexport.swift`, `Packages/Tests/HubKitTests/DesignReexportTests.swift`, `PluginKit/Package.swift`, `PluginKit/Sources/DTHubDesign/DS.swift`, `PluginKit/Sources/DTHubDesign/DSBackground.swift`, `PluginKit/Sources/DTHubDesign/DSButtons.swift`, `PluginKit/Sources/DTHubDesign/DSCardRow.swift`, `PluginKit/Sources/DTHubDesign/DSCollapsibleCard.swift`, `PluginKit/Sources/DTHubDesign/DSGlass.swift`, `PluginKit/Sources/DTHubDesign/DSPanel.swift`, `PluginKit/Sources/DTHubDesign/DSTabFrame.swift`, `PluginKit/Tests/DTHubDesignTests/DTHubDesignTests.swift`, `PluginKit/Tests/DTHubPluginKitTests/DTHubPluginKitTests.swift` (gli otto file di `DesignSystem/` si **spostano** con `git mv`, non si riscrivono)

**Interfaces:**
- Produces: modulo e prodotto `DTHubDesign` in `PluginKit` (`public`: `DS`, `dsPanel`, `DSPanelHeader`, `DSGroupHeader`, `DSCollapsibleCard`, `DSCardRow`, `DSTabFrame`, `DSBackground`, `DSWindowConfigurator`, `dsGlass`, `DSPillButtonStyle`, `DSGlassCircleButtonStyle`, `DSTabButtonStyle`, `DSCheckboxToggleStyle`, `DSMenuLabel`, `dsMenuPill`); `HubKit` li riesporta; `DSStatusDot` resta in `HubKit`.

- [ ] **Step 1: Creare il branch e scrivere i test**

```bash
cd "<repo>" && git switch main && git switch -c design-kit && mkdir -p PluginKit/Tests/DTHubDesignTests PluginKit/Tests/DTHubPluginKitTests
```

**`Packages/Tests/HubKitTests/DesignReexportTests.swift`** (file nuovo o riscritto per intero):

```swift
import SwiftUI
import Testing

import HubKit  // only HubKit: the design system must still come with it

@Suite("Design system re-export")
struct DesignReexportTests {
  @Test func hubKitStillGivesTheWholeDesignSystem() {
    #expect(DS.panelRadius == 19)
    #expect(DS.pillHeight == 40)
    _ = DSPillButtonStyle(prominent: true)
    _ = DSCheckboxToggleStyle()
    _ = DSGlassCircleButtonStyle()
    _ = DSGroupHeader(title: "x")
    _ = DSStatusDot(status: .connected)  // the one component that stayed in HubKit
  }
}
```

**`PluginKit/Tests/DTHubPluginKitTests/DTHubPluginKitTests.swift`** (file nuovo o riscritto per intero):

```swift
import Testing

@testable import DTHubPluginKit

@Suite("DTHubPluginKit")
struct DTHubPluginKitTests {
  @Test func theContractVersionIsStillOne() {
    #expect(DTHubContract.current == 1)
  }

  @Test func aBareMessageIsAnObjectWithItsType() {
    #expect(DTHubMessage.type(of: DTHubMessage.bare("ok")) == "ok")
  }
}
```

**`PluginKit/Tests/DTHubDesignTests/DTHubDesignTests.swift`** (file nuovo o riscritto per intero):

```swift
import SwiftUI
import Testing

@testable import DTHubDesign

@Suite("DTHubDesign")
struct DTHubDesignTests {
  @Test func theTokensAreTheOnesOfTheApp() {
    #expect(DS.panelRadius == 19)
    #expect(DS.pillHeight == 40)
    #expect(DS.groupGap == 18)
  }

  @Test func theComponentsCanBeMade() {
    _ = DSPillButtonStyle(prominent: true)
    _ = DSCheckboxToggleStyle()
    _ = DSGlassCircleButtonStyle()
    _ = DSGroupHeader(title: "x", prominent: true)
    _ = DSPanelHeader(icon: "lightbulb", title: "x")
  }
}
```

Run: `cd "<repo>/PluginKit" && swift test 2>&1 | grep -E "error:|no tests" | head -2`
Expected: un errore o nessun test: i target di test e il modulo `DTHubDesign` non esistono ancora (il test di `HubKit` invece passa già: è la guardia che continuerà a passare).

- [ ] **Step 2: Spostare i file e scrivere i collegamenti**

```bash
cd "<repo>" && mkdir -p PluginKit/Sources/DTHubDesign && for f in DS DSBackground DSButtons DSCardRow DSCollapsibleCard DSGlass DSPanel DSTabFrame; do git mv Packages/Sources/HubKit/DesignSystem/$f.swift PluginKit/Sources/DTHubDesign/$f.swift; done
```

**`Packages/Sources/HubKit/DesignSystem/DesignReexport.swift`** (file nuovo o riscritto per intero):

```swift
// The design system lives in `DTHubDesign` (the plug-in kit package), so that plug-ins share it with the app.
// HubKit re-exports it: `import HubKit` still gives every module and the app the `DS…` components.
@_exported import DTHubDesign
```

```diff
diff --git a/Packages/Sources/HubKit/DesignSystem/DSStatusDot.swift b/Packages/Sources/HubKit/DesignSystem/DSStatusDot.swift
index efd5901..5a378d4 100644
--- a/Packages/Sources/HubKit/DesignSystem/DSStatusDot.swift
+++ b/Packages/Sources/HubKit/DesignSystem/DSStatusDot.swift
@@ -1,3 +1,4 @@
+import DTHubDesign
 import SwiftUI
 
 /// Traffic-light dot for the Draw Things connection: green connected, yellow connecting,
```

```diff
diff --git a/Packages/Package.swift b/Packages/Package.swift
index 38e5632..8870158 100644
--- a/Packages/Package.swift
+++ b/Packages/Package.swift
@@ -24,9 +24,11 @@ let package = Package(
     .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.32.3")),
     .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
     .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
+    // The design system (cards, buttons, colours) is shared with the plug-ins: it lives in the plug-in kit package.
+    .package(name: "PluginKit", path: "../PluginKit"),
   ],
   targets: [
-    .target(name: "HubKit"),
+    .target(name: "HubKit", dependencies: [.product(name: "DTHubDesign", package: "PluginKit")]),
     .target(name: "HubCore", dependencies: ["HubKit"]),
     // The only module that knows DrawThings-Swift and gRPC (spec §4).
     .target(
```

```diff
diff --git a/PluginKit/Package.swift b/PluginKit/Package.swift
index 4b67d85..2f2f866 100644
--- a/PluginKit/Package.swift
+++ b/PluginKit/Package.swift
@@ -3,9 +3,21 @@ import PackageDescription
 
 // The package a DT Hub plug-in is written with. It does not depend on DT Hub: the app and the plug-in
 // only talk through selectors and JSON messages (plug-in design §3).
+//
+// `DTHubDesign` is the look of the app (cards, buttons, colours: SwiftUI only, no Objective-C classes). The app's
+// HubKit uses it from here and a plug-in takes the same product next to the kit. A plug-in gives each module a name of
+// its own with `moduleAliases` (see Plugins/SphereLight/Package.swift).
 let package = Package(
   name: "DTHubPluginKit",
   platforms: [.macOS(.v26)],
-  products: [.library(name: "DTHubPluginKit", targets: ["DTHubPluginKit"])],
-  targets: [.target(name: "DTHubPluginKit")]
+  products: [
+    .library(name: "DTHubPluginKit", targets: ["DTHubPluginKit"]),
+    .library(name: "DTHubDesign", targets: ["DTHubDesign"]),
+  ],
+  targets: [
+    .target(name: "DTHubDesign"),
+    .target(name: "DTHubPluginKit"),
+    .testTarget(name: "DTHubPluginKitTests", dependencies: ["DTHubPluginKit"]),
+    .testTarget(name: "DTHubDesignTests", dependencies: ["DTHubDesign"]),
+  ]
 )
```

- [ ] **Step 3: Verificare**

Run: `cd "<repo>/PluginKit" && swift test 2>&1 | grep -E "Test run with|error:"`
Expected: due righe `Test run with 2 tests in 1 suite passed` (il kit e il design).

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubKit `102 tests … passed` (uno nuovo), gli altri invariati (HubCore 464, DTBridge 66, Catalog 6, LLMBridge 6, PluginHost 6).

Run: `cd "<repo>" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath /tmp/d-dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **` (Xcode risolve `PluginKit` tramite `Packages`).

- [ ] **Step 4: Commit**

```bash
cd "<repo>" && git add -A PluginKit Packages && git commit -m "feat: DTHubDesign, il design system nel pacchetto del kit dei plug-in; HubKit lo riesporta

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: L'accessorio di `DSCollapsibleCard`

**Files:**
- Modify: `PluginKit/Sources/DTHubDesign/DSCollapsibleCard.swift`, `PluginKit/Tests/DTHubDesignTests/DTHubDesignTests.swift`

**Interfaces:**
- Produces: `DSCollapsibleCard<Content: View, Trailing: View>`: `init(_:systemImage:tint:isExpanded:trailing:content:)` e, per `Trailing == EmptyView`, il vecchio `init(_:systemImage:tint:isExpanded:content:)`. L'accessorio sta fuori dal pulsante che apre e chiude la card.

- [ ] **Step 1: Scrivere il test e verificare che fallisca**

```diff
diff --git a/PluginKit/Tests/DTHubDesignTests/DTHubDesignTests.swift b/PluginKit/Tests/DTHubDesignTests/DTHubDesignTests.swift
index be2bd7c..8dd71f7 100644
--- a/PluginKit/Tests/DTHubDesignTests/DTHubDesignTests.swift
+++ b/PluginKit/Tests/DTHubDesignTests/DTHubDesignTests.swift
@@ -18,4 +18,10 @@ struct DTHubDesignTests {
     _ = DSGroupHeader(title: "x", prominent: true)
     _ = DSPanelHeader(icon: "lightbulb", title: "x")
   }
+
+  @Test func aCollapsibleCardCanCarryAnAccessoryNextToItsTitle() {
+    // With and without: the existing calls (no accessory) keep compiling.
+    _ = DSCollapsibleCard("x", isExpanded: .constant(true), trailing: { Image(systemName: "minus.circle") }) { Text("y") }
+    _ = DSCollapsibleCard("x", systemImage: "lightbulb", tint: DS.remove, isExpanded: .constant(false)) { Text("y") }
+  }
 }
```

Run: `cd "<repo>/PluginKit" && swift test 2>&1 | grep -E "error:" | head -2`
Expected: un errore di compilazione sulla card con `trailing:` (`extra argument 'trailing' in call`).

- [ ] **Step 2: Implementare**

```diff
diff --git a/PluginKit/Sources/DTHubDesign/DSCollapsibleCard.swift b/PluginKit/Sources/DTHubDesign/DSCollapsibleCard.swift
index 30517d7..8dfb96b 100644
--- a/PluginKit/Sources/DTHubDesign/DSCollapsibleCard.swift
+++ b/PluginKit/Sources/DTHubDesign/DSCollapsibleCard.swift
@@ -3,12 +3,14 @@ import SwiftUI
 /// A collapsible card of the Generation tab (spec §7). `tint` colours the card, e.g.
 /// `DS.remove` for the negative prompt. A custom disclosure rather than `DisclosureGroup`:
 /// the stock control keeps a system focus ring around its triangle. Pass a localized title
-/// (`String(localized:)`): the catalog test rejects literals here.
-public struct DSCollapsibleCard<Content: View>: View {
+/// (`String(localized:)`): the catalog test rejects literals here. `trailing` is an optional accessory at the
+/// right of the title (a "remove" button, say); it is not part of the button that opens and closes the card.
+public struct DSCollapsibleCard<Content: View, Trailing: View>: View {
   let title: String
   let systemImage: String?
   let tint: Color?
   @Binding var isExpanded: Bool
+  let trailing: Trailing
   let content: Content
 
   public init(
@@ -16,12 +18,14 @@ public struct DSCollapsibleCard<Content: View>: View {
     systemImage: String? = nil,
     tint: Color? = nil,
     isExpanded: Binding<Bool>,
+    @ViewBuilder trailing: () -> Trailing,
     @ViewBuilder content: () -> Content
   ) {
     self.title = title
     self.systemImage = systemImage
     self.tint = tint
     self._isExpanded = isExpanded
+    self.trailing = trailing()
     self.content = content()
   }
 
@@ -44,6 +48,15 @@ public struct DSCollapsibleCard<Content: View>: View {
   }
 
   private var header: some View {
+    HStack(spacing: DS.controlGap) {
+      toggleButton
+      trailing
+    }
+    .padding(.horizontal, DS.panelPadding)
+    .padding(.vertical, 12)
+  }
+
+  private var toggleButton: some View {
     Button {
       withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
     } label: {
@@ -60,8 +73,6 @@ public struct DSCollapsibleCard<Content: View>: View {
         DSGroupHeader(title: title, prominent: true)
         Spacer(minLength: 0)
       }
-      .padding(.horizontal, DS.panelPadding)
-      .padding(.vertical, 12)
       .contentShape(Rectangle())
     }
     .buttonStyle(.plain)
@@ -71,6 +82,21 @@ public struct DSCollapsibleCard<Content: View>: View {
   }
 }
 
+extension DSCollapsibleCard where Trailing == EmptyView {
+  /// A card without an accessory.
+  public init(
+    _ title: String,
+    systemImage: String? = nil,
+    tint: Color? = nil,
+    isExpanded: Binding<Bool>,
+    @ViewBuilder content: () -> Content
+  ) {
+    self.init(
+      title, systemImage: systemImage, tint: tint, isExpanded: isExpanded, trailing: { EmptyView() },
+      content: content)
+  }
+}
+
 #Preview("Cards") {
   @Previewable @State var promptOpen = true
   @Previewable @State var negativeOpen = true
```

- [ ] **Step 3: Verificare**

Run: `cd "<repo>/PluginKit" && swift test 2>&1 | grep -E "Test run with|error:"`
Expected: due righe passate (kit 2 test, design 3).

Run: `cd "<repo>" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath /tmp/d-dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **` (tutti gli usi esistenti della card compilano).

- [ ] **Step 4: Commit**

```bash
cd "<repo>" && git add -A PluginKit && git commit -m "feat: DSCollapsibleCard accetta un accessorio a destra del titolo

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Sphere Light con i componenti dell'app

**Files:**
- Modify/Create: `Plugins/SphereLight/Package.swift`, `Plugins/SphereLight/Sources/SphereLight/LightControlView.swift`, `Plugins/SphereLight/Sources/SphereLight/SphereLightView.swift`

**Interfaces:**
- Consumes: `DTHubDesign` (Task 1) e `DSCollapsibleCard` con accessorio (Task 2), come prodotto del pacchetto `PluginKit`, con `moduleAliases` `SphereLightDesign`.
- Produces: il tab di Sphere Light con le luci in `DSCollapsibleCard` («Luce N», icona `lightbulb`, «togli» in `DS.remove` come accessorio, slider con `tint(DS.accent)`), «Aggiungi una luce» e i due invii in `DSPillButtonStyle` (l'invio alla Generazione in evidenza), le due caselle in `DSCheckboxToggleStyle`, l'anteprima in un `dsPanel` con `DSPanelHeader`. Nessun cambio di logica (30 test invariati).

- [ ] **Step 1: Applicare le modifiche**

```diff
diff --git a/Plugins/SphereLight/Package.swift b/Plugins/SphereLight/Package.swift
index 594d442..f1b142f 100644
--- a/Plugins/SphereLight/Package.swift
+++ b/Plugins/SphereLight/Package.swift
@@ -8,11 +8,14 @@ let package = Package(
   products: [.library(name: "SphereLight", type: .dynamic, targets: ["SphereLight"])],
   dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
   targets: [
-    // Every plug-in carries its own copy of the kit; `moduleAliases` gives it a name of its own, so two plug-ins
-    // do not define the same Objective-C classes twice in one process.
+    // Every plug-in carries its own copy of the kit and of the design system; `moduleAliases` gives them
+    // names of their own, so two plug-ins (and the app) do not define the same classes twice in one process.
     .target(
       name: "SphereLight",
-      dependencies: [.product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "SphereLightKit"])]),
+      dependencies: [
+        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "SphereLightKit"]),
+        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "SphereLightDesign"]),
+      ]),
     .testTarget(name: "SphereLightTests", dependencies: ["SphereLight"]),
   ]
 )
```

**`Plugins/SphereLight/Sources/SphereLight/LightControlView.swift`** (file nuovo o riscritto per intero):

```swift
import DTHubDesign
import SwiftUI

/// One light: a card of the app's look that opens and closes, with its four sliders and its colour.
struct LightControlView: View {
  @Binding var light: LightParams
  let index: Int
  @Binding var isExpanded: Bool
  let canRemove: Bool
  let onRemove: () -> Void
  let onChange: () -> Void

  var body: some View {
    DSCollapsibleCard(
      L.format(.light, index + 1), systemImage: "lightbulb", isExpanded: $isExpanded,
      trailing: {
        if canRemove {
          Button(action: onRemove) { Image(systemName: "minus.circle.fill") }
            .buttonStyle(.plain)
            .foregroundStyle(DS.remove)
            .help(L.text(.removeLight))
        }
      }
    ) {
      VStack(alignment: .leading, spacing: DS.rowGap) {
        sliderRow(L.text(.rotation), value: $light.rotationDeg, range: -180...180, format: "%.0f°")
        sliderRow(L.text(.elevation), value: $light.elevationDeg, range: -90...90, format: "%.0f°")
        sliderRow(L.text(.intensity), value: $light.intensity, range: 0.2...3, format: "%.2f")
        sliderRow(L.text(.hardness), value: $light.hardness, range: 0...1, format: "%.2f")
        HStack {
          Text(L.text(.color)).font(.subheadline.weight(.semibold))
          Spacer()
          ColorPicker("", selection: $light.color, supportsOpacity: false)
            .labelsHidden()
            .onChange(of: light.color) { _, _ in onChange() }
        }
      }
    }
  }

  private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(title).font(.subheadline.weight(.semibold))
        Spacer()
        Text(String(format: format, value.wrappedValue)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
      }
      Slider(value: value, in: range)
        .controlSize(.small)
        .tint(DS.accent)
        .onChange(of: value.wrappedValue) { _, _ in onChange() }
    }
  }
}
```

**`Plugins/SphereLight/Sources/SphereLight/SphereLightView.swift`** (file nuovo o riscritto per intero):

```swift
import DTHubDesign
import SwiftUI

/// The tab, in the look of the app: the lights as cards on the left, the sphere in a panel on the right.
struct SphereLightView: View {
  @ObservedObject var state: SLRState
  let send: (SphereSender.Kind) -> Void

  var body: some View {
    HStack(alignment: .top, spacing: DS.groupGap) {
      lights.frame(width: 300)
      preview.frame(maxWidth: .infinity)
    }
    .padding(DS.groupGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var lights: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      DSGroupHeader(title: L.text(.lights), prominent: true)
      ScrollView {
        VStack(spacing: DS.groupGap) {
          ForEach($state.lights) { $light in
            LightControlView(
              light: $light, index: state.lights.firstIndex(where: { $0.id == light.id }) ?? 0,
              isExpanded: Binding(
                get: { state.expanded[light.id, default: true] }, set: { state.expanded[light.id] = $0 }),
              canRemove: state.lights.count > 1, onRemove: { state.removeLight(light.id) },
              onChange: { state.lightChanged() })
          }
        }
        .padding(.bottom, DS.panelPadding)
      }
      .scrollIndicators(.hidden)
      if state.canAddLight {
        Button { state.addLight() } label: {
          HStack(spacing: DS.pillIconGap) {
            Image(systemName: "plus")
            Text(L.text(.addLight))
          }
        }
        .buttonStyle(DSPillButtonStyle())
      }
    }
  }

  private var preview: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "circle.lefthalf.filled", title: L.text(.preview))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        ZStack {
          RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06))
          if let image = state.previewImage {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(6)
          } else {
            ProgressView()
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)

        Toggle(L.text(.overcast), isOn: $state.overcast).toggleStyle(DSCheckboxToggleStyle())
        Toggle(L.text(.saveDesktop), isOn: $state.saveToDesktop).toggleStyle(DSCheckboxToggleStyle())
        HStack(spacing: DS.controlGap) {
          Button { send(.pipeline) } label: {
            if state.isSending {
              ProgressView().controlSize(.small)
            } else {
              HStack(spacing: DS.pillIconGap) {
                Image(systemName: "sparkles")
                Text(L.text(.sendPipeline))
              }
            }
          }
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .disabled(state.isSending || !state.active)
          Button(L.text(.sendMoodboard)) { send(.moodboard) }
            .buttonStyle(DSPillButtonStyle())
            .disabled(state.isSending || !state.active)
        }
        if !state.status.isEmpty {
          Text(state.status).font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }
}
```

- [ ] **Step 2: Compilare, provare e fare il bundle**

Run: `cd "<repo>/Plugins/SphereLight" && swift build 2>&1 | grep -E "error|Build comp" && swift test 2>&1 | grep -E "Test run with|error:|issue" && rm -rf /tmp/slr-d && Scripts/build.sh /tmp/slr-d | tail -1`
Expected: `Build complete!`, `Test run with 30 tests in 4 suites passed` e `/tmp/slr-d/SphereLight.dthubplugin`.

Run: `B=/tmp/slr-d/SphereLight.dthubplugin/Contents/MacOS/SphereLight; echo "design con alias: $(nm -gU $B | grep -c SphereLightDesign) · design senza alias: $(nm -gU $B | grep -c DTHubDesign) · kit senza alias: $(nm -gU $B | grep -c 14DTHubPluginKit)"`
Expected: un numero maggiore di 0, poi `0`, poi `0`.

Run: `rm -rf /tmp/smp && "<repo>/PluginKit/Scripts/build-sample.sh" /tmp/smp | tail -1`
Expected: `/tmp/smp/Sample.dthubplugin` (l'esempio si costruisce ancora).

- [ ] **Step 3: Commit**

```bash
cd "<repo>" && git add -A Plugins && git commit -m "feat: Sphere Light con le card, i pulsanti e le caselle dell'app

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Documenti e prova nell'app

**Files:**
- Modify: `PluginKit/README.md`, `Plugins/SphereLight/README.md`, `docs/superpowers/specs/2026-10-05-plugin-design-system-design.md`, `docs/superpowers/backlog.md`

- [ ] **Step 1: Provare nell'app**

**Se l'app dell'utente è aperta, non pilotare le finestre.** Annotare `workspace.selectedTab`. **Non toccare** lo stato di Sphere Light nelle preferenze: la prova guarda e basta.

```bash
cd "<repo>"
defaults read com.exiztenz.DTHub workspace.selectedTab    # annotare
H=/tmp/dkhome; rm -rf $H; AS="$H/Library/Application Support/DT Hub"; mkdir -p "$AS/Plug-ins"
cp -R /tmp/slr-d/SphereLight.dthubplugin "$AS/Plug-ins/com.exiztenz.dthub.spherelight.dthubplugin"
cp -R /tmp/smp/Sample.dthubplugin "$AS/Plug-ins/com.example.dthub.sample.dthubplugin"
echo '{"enabled":["com.exiztenz.dthub.spherelight","com.example.dthub.sample"]}' > "$AS/plugins.json"
(CFFIXED_USER_HOME=$H nohup "/tmp/d-dd/Build/Products/Debug/DT Hub.app/Contents/MacOS/DT Hub" > /tmp/d-app.log 2>&1 &)
sleep 8; grep -ci "duplicate\|implemented in both" /tmp/d-app.log
```

Checklist:
1. `grep` dà `0`: due plug-in e l'app partono senza avvisi di classi duplicate.
2. Il tab Sphere Light ha le luci come card di vetro («LUCE 1», «LUCE 2» con l'icona della lampadina e il «−» arancione), la sfera in un pannello con l'intestazione «Anteprima», le caselle teal e i pulsanti a pillola con «Invia a Generazione» in evidenza; i tab Control e Generazione sono come prima.
3. Con una sola luce non c'è il «−»; con tre luci sparisce «Aggiungi una luce»; il «−» toglie la luce; aprire e chiudere una card funziona.
4. I due pulsanti di invio e le caselle funzionano come prima (è la stessa logica).
5. Rimettere `workspace.selectedTab`, chiudere l'istanza e `pkill -f gRPCServerCLI`.

- [ ] **Step 2: Aggiornare README, spec e backlog**

```bash
cd "<repo>" && python3 - <<'PY'
p = 'PluginKit/README.md'
s = open(p).read()
marker = "## Messages (contract 1)"
assert marker in s
s = s.replace(marker, """## The look of the app

`DTHubDesign` (a second product of this package, SwiftUI only) holds the components of the app: `DS` (colours, radii,
spacing), `dsPanel`, `DSPanelHeader`, `DSGroupHeader`, `DSCollapsibleCard` (with an optional `trailing` accessory),
`DSPillButtonStyle`, `DSGlassCircleButtonStyle`, `DSCheckboxToggleStyle`, `dsGlass`… A plug-in tab that uses them looks
like the rest of DT Hub. Take the product next to the kit and give **each** module an alias of its own (the kit does not
re-export the design system: with `moduleAliases` that does not resolve):

        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "MyPluginKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "MyPluginDesign"]),

and `import DTHubDesign` in the views (see `Plugins/SphereLight`).

""" + marker, 1)
open(p, 'w').write(s)

p = 'Plugins/SphereLight/README.md'
s = open(p).read()
assert "## Costruirlo" in s
s = s.replace("## Costruirlo", "Il tab usa i componenti dell'app (`DTHubDesign`, dal pacchetto `PluginKit`): card, pulsanti a pillola, caselle teal.\n\n## Costruirlo", 1)
open(p, 'w').write(s)

p = 'docs/superpowers/specs/2026-10-05-plugin-design-system-design.md'
s = open(p).read()
def rep(a, b):
    global s
    assert a in s, a
    s = s.replace(a, b, 1)
rep("Stato: bozza da approvare", "Stato: realizzata")
rep("| `DTHubPluginKit` (esistente) | contratto del plug-in; ora **riesporta** `DTHubDesign` (`@_exported import`): chi importa il kit ha anche il design system | i plug-in |",
    "| `DTHubPluginKit` (esistente) | contratto del plug-in, invariato; **non** riesporta il design system (vedi sotto) | i plug-in |")
rep("`DTHubPluginKit` dipende da `DTHubDesign`. L'app non collega",
    "`DTHubPluginKit` non dipende da `DTHubDesign`: un plug-in prende i due prodotti, ognuno con il suo alias. L'app non collega")
rep("- `@_exported import` di un modulo rinominato con `moduleAliases` nel kit è da provare nel prototipo; se non regge, il plug-in importa i due prodotti con i loro alias (e il README lo dice).",
    "- **Provato e non regge:** `@_exported import DTHubDesign` dentro il kit con `moduleAliases` dà «unable to resolve module dependency: 'DTHubDesign'». Un plug-in importa quindi i due prodotti con i loro alias (il README del kit lo dice).")
open(p, 'w').write(s)

p = 'docs/superpowers/backlog.md'
s = open(p).read().rstrip() + """

## Rimandi del design system nel kit

- **Il kit non riesporta il design system:** un plug-in prende due prodotti con due alias (vedi `PluginKit/README.md`). Se in futuro SwiftPM propaga l'alias, si può riesportare.
- **L'esempio `Sample` non usa il design system** (resta con i controlli standard).
- **`DSStatusDot` resta in `HubKit`** perché dipende da `ConnectionStatus`.
"""
open(p, 'w').write(s + "\n")
PY
git diff --stat | tail -1
```

Expected: statistica su quattro file.

- [ ] **Step 3: Commit**

```bash
cd "<repo>" && git add -A PluginKit Plugins docs && git commit -m "docs: il design system nel kit dei plug-in; README, spec realizzata e rimandi nel backlog

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Fine

Esito atteso sul branch `design-kit`:
- **650 test verdi** nell'app (HubKit 102), 5 nel kit (`DTHubPluginKit` 2 e `DTHubDesign` 3) e 30 in Sphere Light (più i 5 Python invariati); build Xcode pulita;
- `DTHubDesign` condiviso da app e plug-in; il tab di Sphere Light con l'aspetto dell'app.

Poi: revisione indipendente, correzioni, prova dell'utente (**lasciare l'app aperta**) e merge.
