# Passaggi di pipeline con valori propri e contesto aggiornato — Piano di implementazione

> **Per chi esegue:** SOTTO-SKILL OBBLIGATORIA: `superpowers:subagent-driven-development` (consigliata) oppure `superpowers:executing-plans`. I passi usano la sintassi a caselle (`- [ ]`).

**Obiettivo:** un passaggio di pipeline di un plug-in può cambiare solo alcuni valori (senza preset); i plug-in ricevono i parametri attuali e il kit li espone.

**Architettura:** `PipelineStep` (HubKit) con `fields`/`loras`; `PipelinePresets.fields` li applica sopra la base; `PluginRegistry.currentParameters` per il contesto; tipi decodificabili nel kit.

**Tecnologie:** Swift 6.2, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-09-pipeline-passaggi-con-valori-design.md`.

## Vincoli globali

- Ramo nuovo (es. `pipeline-valori`). **Niente unione, push o release senza via libera esplicito.** File aggiunti **per nome**.
- Test: `cd Packages && swift test --filter <Suite> 2>&1 | grep -E "Test run with|error:"`; kit: `cd PluginKit && swift test …` (se ha test; altrimenti i test del kit vanno nei test di un plug-in o in un target nuovo `DTHubPluginKitTests`).
- I test esistenti restano verdi (in particolare quelli delle pipeline e di Sphere Light).
- Commenti in inglese.

## Review Focus

1. Un passaggio solo-preset (Sphere Light) si comporta esattamente come prima (Task 1–2).
2. Avanzate ed «extra» della scheda sopravvivono a un passaggio con `fields` (Task 2).
3. Un `fields` con `width`/`height` non cambia la dimensione (Task 2).
4. Un `parameters` di tipo inatteso nel contesto non fa perdere il resto del contesto al plug-in (Task 4).
5. Aprire la scheda di un plug-in dopo aver cambiato solo i passi: il plug-in riceve il valore nuovo (Task 3).

---

### Task 1: `PipelineStep` con `fields` e `loras`

**Files:** Modify `Packages/Sources/HubKit/Plugin/PluginContribution.swift`. Test: `Packages/Tests/HubKitTests/` (file delle contribution esistente o nuovo `PipelineStepTests.swift`).

**Interfaces — Produces:** `PipelineStep.fields: FieldOverlay` (default vuoto), `PipelineStep.loras: [LoRASelection]` (default `[]`), `init(title:preset:fields:loras:moodboard:startImage:useOutputAsStart:)` con default per i nuovi parametri; lettura JSON in `PipelineStep(_:)` con `FieldOverlay(json:)` e `PluginContribution.loras(_:)` (già esistente per `contribute`).

- [ ] **Step 1: Test che falliscono**: un passaggio `{"title":"A","fields":{"steps":20,"guidanceScale":5.5},"loras":[{"file":"x.ckpt","weight":0.6}]}` → `fields.fields` contiene steps e guidanceScale, `loras == [LoRASelection(file:"x.ckpt", weight:0.6)]`; `{"title":"B","preset":"SLR · Overcast"}` → `fields.isEmpty`, `loras.isEmpty`, `preset` come oggi (**Review Focus 1**); chiavi sconosciute in `fields` ignorate; `steps` 9999 riportato nel limite della card.
- [ ] **Step 2–4:** vedere il fallimento, implementare, test verdi.
- [ ] **Step 5: Commit** — `feat(plugins): passaggi di pipeline con valori propri`.

### Task 2: `PipelinePresets.fields` applica `fields` e `loras`

**Files:** Modify `Packages/Sources/HubCore/Plugins/PipelinePresets.swift` (+ una funzione pura per i LoRA, es. `GenerationParameters.applyingStepLoRAs(_:)` in HubKit o privata qui). Test: `Packages/Tests/HubCoreTests/PipelinePresetsTests.swift` (o il file dei test di pipeline esistente).

**Interfaces — Produces:** `PipelinePresets.fields(for:over:presets:catalog:)` con l'ordine della spec §2.

- [ ] **Step 1: Test che falliscono**: scheda con `steps 8`, `advanced.clipSkip 2`, `extra["foo"] = .int(1)`, `width 832`; passaggio `fields {steps: 20, width: 1024}` → risultato `steps 20`, `clipSkip 2`, `extra["foo"] == .int(1)`, `width 832` (**Review Focus 2, 3**); preset + `fields {steps: 30}` → steps 30 e il resto dal preset; `loras [x.ckpt 0.6, y.ckpt 1.0]` su scheda con `x.ckpt 1.0` → `x.ckpt 0.6` nella stessa posizione e `y.ckpt` in coda; passaggio vuoto → scheda identica; passaggio solo-preset → stesso risultato di oggi (**Review Focus 1**).
- [ ] **Step 2–4:** vedere il fallimento, implementare, test verdi (`swift test --filter Pipeline`).
- [ ] **Step 5: Commit** — `feat(pipeline): valori del passaggio sopra la scheda`.

### Task 3: Contesto con i parametri attuali

**Files:** Modify `Packages/Sources/HubCore/Plugins/PluginRegistry.swift`, `App/DTHubApp.swift`. Test: `Packages/Tests/HubCoreTests/PluginRegistryTests.swift` (con `FakeLoadedPlugin`).

**Interfaces — Produces:** `PluginRegistry.currentParameters: (@MainActor () -> GenerationParameters)?`.

- [ ] **Step 1: Test che falliscono**: `updateContext(… parameters: steps 8)`, poi `currentParameters = { steps 20 }`, poi `refreshContext()` → il JSON ricevuto dal plug-in ha `parameters.steps == 20` (**Review Focus 5**); senza `currentParameters` vale l'ultimo `updateContext` (come oggi).
- [ ] **Step 2–4:** vedere il fallimento, implementare (`sendContext` usa `currentParameters?() ?? latestParameters`), test verdi. In `DTHubApp.init`: `plugins.currentParameters = { generation.parameters }`; `xcodebuild … build`.
- [ ] **Step 5: Commit** — `feat(plugins): il contesto porta i parametri attuali`.

### Task 4: `DTHubParameters` nel kit e README

**Files:** Modify `PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift`, `PluginKit/README.md`. Test: target di test del kit (creare `PluginKit/Tests/DTHubPluginKitTests` se non esiste, con `testTarget` nel `Package.swift` del kit).

**Interfaces — Produces:** `DTHubParameters`, `DTHubLoRA`, `DTHubValue`, `DTHubContext.parameters` (spec §4).

- [ ] **Step 1: Test che falliscono**: un `PluginContext` codificato dall'app (JSON di esempio copiato da un test di HubKit, con LoRA, avanzate ed extra) si decodifica in `DTHubContext` con `parameters.steps`, `loras[0].weight`, `advanced["clipSkip"] == .number(2)`; un contesto senza `parameters` → `nil`; `parameters` con `steps: "venti"` → `steps == nil` e il resto del contesto presente (**Review Focus 4**).
- [ ] **Step 2–4:** vedere il fallimento, implementare con `init(from:)` tollerante (`try?` per ogni chiave), test verdi. Ricompilare Sphere Light, Prompt Master, I4, Character Sheet (`swift build` in ciascuno) per verificare che nulla si rompa.
- [ ] **Step 5: README del kit** — sezione «Messages (contract 1)»: `context.parameters` (chiavi, `DTHubParameters`); passaggi della pipeline con `fields`/`loras` (spec §2, compresa la regola su dimensioni e avanzate).
- [ ] **Step 6: Suite** — `cd Packages && swift test`; `xcodebuild … build`. **Commit** — `feat(kit): parametri della scheda nel contesto`.
- [ ] **Step 7: Messaggio finale** (briefing §6) e via libera prima di unire. Questo lavoro va unito **prima** del plug-in Batch plus.
