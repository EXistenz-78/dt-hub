# Plug-in «Batch plus» — Piano di implementazione

> **Per chi esegue:** SOTTO-SKILL OBBLIGATORIA: `superpowers:subagent-driven-development` (consigliata) oppure `superpowers:executing-plans`. I passi usano la sintassi a caselle (`- [ ]`).

**Obiettivo:** un plug-in che prepara una serie di RUN (parametri che crescono per incremento, oppure un elenco di prompt) e la manda all'app come pipeline.

**Architettura:** pacchetto `Plugins/BatchPlus` come gli altri (Sphere Light come modello: `Package.swift` con alias di modulo, `Scripts/build.sh`, tabella `L`, `DTHubDesign`); logica pura testata (calcolo, parser, costruzione dei passaggi, stato); vista SwiftUI sottile.

**Tecnologie:** Swift 6.2, Swift Testing, SwiftUI, DTHubPluginKit.

**Spec:** `docs/superpowers/specs/2026-10-09-plugin-batch-plus-design.md`.

## Vincoli globali

- **Prerequisito:** «Passaggi di pipeline con valori propri» unito in `main` (`PipelineStep.fields/loras`, `DTHubContext.parameters`).
- Ramo nuovo (es. `plugin-batch-plus`). **Niente unione, push o release senza via libera esplicito.** File aggiunti **per nome**.
- Test: `cd Plugins/BatchPlus && swift test 2>&1 | grep -E "Test run with|error:"`.
- Bundle: `Plugins/BatchPlus/Scripts/build.sh <cartella>` → `BatchPlus.dthubplugin`; installazione con `rm -rf` della vecchia copia prima di `cp -R` (briefing §3). Nella release: `BatchPlus.dthubplugin.zip`, riga in `Plugins/README.md`.
- Testi it/en nella tabella `L`; commenti in inglese; README del plug-in in inglese.

## Review Focus

1. Incremento con virgola («0,5») e con segno («-2»): letti correttamente (Task 1).
2. Elenco con righe che vanno a capo e punti vuoti: il numero di passaggi è quello dei punti veri (Task 2).
3. «Seed fisso» con un incremento sul seed: seed crescente e mai casuale (Task 3).
4. Nessun `preset`, `width`, `height` nei passaggi inviati (Task 3).
5. Contesto senza `parameters`: modalità Parametri disattivata con il messaggio, modalità Prompt funzionante (Task 5).

---

### Task 1: Scheletro del pacchetto e calcolo degli incrementi

**Files:** Create `Plugins/BatchPlus/{Package.swift, README.md, Scripts/build.sh}`, `Sources/BatchPlus/{BatchPlusPlugin.swift, Strings.swift, Increments.swift}`, `Tests/BatchPlusTests/IncrementsTests.swift` (copiare struttura e script da `Plugins/SphereLight`, cambiando nomi e id).

**Interfaces — Produces:**
```swift
enum BatchPlusKey: String, CaseIterable { case steps, guidanceScale, shift, cfgZeroInitSteps, seed }   // + LoRA per file a parte
enum IncrementParse { static func parse(_ text: String, integer: Bool) -> Result<Double?, IncrementError> }  // nil = vuoto o 0
enum BatchPlusMath { static func values(base: Double, increment: Double, count: Int) -> [Double] }          // count valori, il primo = base
```
- [ ] **Step 1: Test che falliscono**: `parse("0,5", integer: false) == .success(0.5)`; `parse("-2", integer: true) == .success(-2)`; `parse("1.5", integer: true)` → errore; `parse("")` e `parse("0")` → `.success(nil)`; `parse("abc")` → errore (**Review Focus 1**). `values(base: 10, increment: 10, count: 3) == [10, 20, 30]`; decremento `values(3, -0.5, 3) == [3, 2.5, 2]`.
- [ ] **Step 2–4:** vedere il fallimento, implementare, test verdi; `swift build` e `Scripts/build.sh` producono il bundle (plug-in con vista vuota).
- [ ] **Step 5: Commit** — `feat(batch-plus): pacchetto e calcolo degli incrementi`.

### Task 2: Parser dell'elenco di prompt

**Files:** Create `Sources/BatchPlus/PromptList.swift`, `Tests/BatchPlusTests/PromptListTests.swift`.

**Interfaces — Produces:** `enum PromptList { static func items(_ text: String) -> [String] }` (spec §5).
- [ ] **Step 1: Test che falliscono**: `"- a\n- b"` → `["a","b"]`; segni `•` e `*` e spazi iniziali; `"- a cat\n  on a roof\n- b"` → `["a cat on a roof","b"]`; `"- \n- b"` → `["b"]`; testo senza segni → `[]` (**Review Focus 2**).
- [ ] **Step 2–4, Step 5: Commit** — `feat(batch-plus): elenco dei prompt`.

### Task 3: Costruzione dei passaggi

**Files:** Create `Sources/BatchPlus/BatchPlusBuilder.swift`, `Tests/BatchPlusTests/BatchPlusBuilderTests.swift`.

**Interfaces — Consumes:** Task 1–2; `DTHubParameters` (kit). **Produces:**
```swift
struct ParameterBatch { var increments: [BatchPlusKey: Double]; var loraIncrements: [String: Double]; var count: Int; var fixedSeed: Bool }
enum BatchPlusBuilder {
  static func pipeline(_ s: ParameterBatch, from p: DTHubParameters, italian: Bool) -> [String: Any]   // spec §6
  static func pipeline(prompts: [String], fixedSeed: Bool, seed: UInt32?, italian: Bool) -> [String: Any]
  static func preview(_ s: ParameterBatch, from p: DTHubParameters) -> [[String: Double]]            // per l'anteprima
}
```
- [ ] **Step 1: Test che falliscono**: passi 10 (+10) e guidance 3 (+2), count 3 → 3 passaggi con `fields` `{steps:10, guidanceScale:3}`, `{20,5}`, `{30,7}` e `title` «Passi 20 · Guidance 5» (it); `fixedSeed` con seed 1234 e senza incremento → ogni `fields` ha `seed:1234, randomSeed:false`; con incremento seed +1 → 1234, 1235, 1236, sempre `randomSeed:false` (**Review Focus 3**); LoRA `x.ckpt` peso 0,4 +0,2 → `loras [{file:"x.ckpt", weight:0.4}]`, poi 0.6, 0.8; nessun passaggio contiene le chiavi `preset`, `width`, `height` (**Review Focus 4**); `name` «Batch plus · Passi, Guidance»; modalità Prompt → `fields {prompt: …}` e `name` «Batch plus · Prompt».
- [ ] **Step 2–4, Step 5: Commit** — `feat(batch-plus): passaggi della serie`.

### Task 4: Stato per progetto

**Files:** Create `Sources/BatchPlus/{BatchPlusState.swift, BatchPlusStore.swift}`, `Tests/BatchPlusTests/BatchPlusStoreTests.swift` (modello: `SLRStore` con `folder` e `adoptLegacy`).

- [ ] **Step 1: Test che falliscono**: round trip di modalità, incrementi (come testo, per non perdere quello che l'utente ha scritto), numero di passaggi, seed fisso, testo dei prompt; file assente o rotto → stato iniziale (Parametri, 3 passaggi, seed fisso acceso, campi vuoti); due cartelle indipendenti.
- [ ] **Step 2–4, Step 5: Commit** — `feat(batch-plus): stato per progetto`.

### Task 5: Vista, messaggi, invio

**Files:** Create `Sources/BatchPlus/BatchPlusView.swift`; Modify `BatchPlusPlugin.swift` (`handle`: `context` → aggiorna `parameters` e modello; `project` → stato del progetto; `activate`/`deactivate`), `Strings.swift`, `README.md`.

- [ ] **Step 1: Vista** (spec §4–5): selettore Parametri/Prompt in cima; Parametri = righe in sola lettura con campo incremento dove previsto (bordo rosso se non valido), shift disattivato con «auto», LoRA uno per riga, «Avanzate» richiudibile, numero di passaggi (2–50, avviso ≥ 20), «Seed fisso», anteprima, pulsante; Prompt = editor, conteggio, anteprima, «Seed fisso», pulsante. Senza `parameters`: messaggio e modalità Parametri disattivata (**Review Focus 5**). Stile `DTHubDesign` come Sphere Light.
- [ ] **Step 2: Invio**: `host.contribute(BatchPlusBuilder.pipeline(…))`; riga di stato dalla risposta (`ok`, `conflicts`, `error`).
- [ ] **Step 3: Testi** it/en in `L` per ogni etichetta, messaggio e titolo dei passaggi.
- [ ] **Step 4: Build e suite** — `swift test`; `Scripts/build.sh "$TMPDIR/batch-plus"`; installare e provare a mano la spec §8 (lista all'utente, non pilotare l'interfaccia).
- [ ] **Step 5: README** del plug-in (inglese, «Works with: all families») e riga in `Plugins/README.md`. **Commit** — `feat(batch-plus): vista e invio della serie; README`.
- [ ] **Step 6: Messaggio finale** (briefing §6): cosa provare, «Decisioni che ho preso» (seed fisso anche per i prompt; shift disattivato con auto; limite 50), «Rinviati» (spec §9), via libera prima di unire, push o release.
