# Migliora Prompt con immagine di partenza e Moodboard — Piano di implementazione

> **Per chi esegue:** SOTTO-SKILL OBBLIGATORIA: `superpowers:subagent-driven-development` (consigliata) oppure `superpowers:executing-plans`. I passi usano la sintassi a caselle (`- [ ]`).

**Obiettivo:** «Migliora Prompt» manda all'LLM anche l'immagine di partenza e le Moodboard accese, numerate, chiedendo di conservare i riferimenti «image N».

**Architettura:** numerazione e testo in `PromptBrief` (puri); il router accetta `needsImages`; il profilo sceglie il system prompt i2i con immagini; `PromptAssistant.enhance` riceve le immagini e ripiega sul solo testo con una nota; il controller raccoglie le immagini.

**Tecnologie:** Swift 6.2, Swift Testing, SwiftUI.

**Spec:** `docs/superpowers/specs/2026-10-09-migliora-con-immagini-design.md` (testi esatti al §3).

## Vincoli globali

- Base: `origin/main` (0.1.4). Ramo nuovo (es. `migliora-con-immagini`). **Niente unione, push o release senza via libera esplicito.**
- File aggiunti **per nome**; mai `git add -A` né `git add docs`.
- Test: `cd Packages && swift test --filter <Suite> 2>&1 | grep -E "Test run with|error:"`; `PromptAssistant` è `@MainActor`.
- App: `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build`.
- I test esistenti di `PromptBriefTests`, `PromptAssistantTests`, `LanguageModelRouterTests`, `LanguageModelProfileTests` restano verdi; cambia solo la costruzione di `PromptAssistant` (firma di `Resolve`).
- Testi it/en (`Localizable.xcstrings`, `extractionState: manual`). Commenti in inglese.

## Review Focus

1. Nessuna immagine (né partenza né Moodboard accese): richiesta identica byte per byte a oggi (Task 1, Task 3).
2. Solo Moodboard, senza immagine di partenza: la prima Moodboard è «Image 1» (Task 1).
3. L'LLM per Migliora non legge immagini: si ottiene comunque il prompt migliorato, con la nota, senza errore (Task 3).
4. Moodboard con miniature spente: non vengono mandate e non contano nella numerazione (Task 4).
5. Famiglia che non legge la Moodboard: va solo l'immagine di partenza, numerata 1 (Task 4).

---

### Task 1: Numerazione e richiesta con immagini (`PromptBrief`)

**Files:**
- Modify: `Packages/Sources/HubCore/PromptAssist/PromptBrief.swift`
- Test: `Packages/Tests/HubCoreTests/PromptBriefTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct EnhanceImages: Equatable, Sendable {
    public var start: URL?; public var references: [URL]
    public init(start: URL? = nil, references: [URL] = [])
    public var isEmpty: Bool { get }
    public var all: [URL] { get }                        // start (se c'è) poi references
  }
  public static func imageLabels(hasStart: Bool, references: Int) -> [String]
  public static func enhance(_ current: PromptPair, family: String?, images: EnhanceImages) -> PromptRequest
  public static func enhance(_ current: PromptPair, ownSystem: String, generation: LanguageModelProfile.Generation?, images: EnhanceImages) -> PromptRequest
  ```
  Le funzioni di oggi senza `images` restano e equivalgono a `images: EnhanceImages()`.

- [ ] **Step 1: Test che falliscono**: `imageLabels(hasStart: true, references: 2) == ["Image 1: the start image (the picture being edited).", "Image 2: reference image 1.", "Image 3: reference image 2."]`; `imageLabels(hasStart: false, references: 2) == ["Image 1: reference image 1.", "Image 2: reference image 2."]` (**Review Focus 2**); `(true, 0)` → solo la riga della partenza; `(false, 0)` → `[]`. `enhance(current, family: "flux2", images: EnhanceImages(start: a, references: [b]))`: `images == [a, b]`, il testo inizia con `"Attached images:\n- Image 1: the start image (the picture being edited).\n- Image 2: reference image 1.\n\nThe prompt refers to these images. Look at them to make the description concrete and accurate, and keep every reference to an image (image 1, image 2…) exactly as written.\n\n"` e finisce con la richiesta di oggi (`PromptBrief.enhance(current, family: "flux2").prompt`); `options` uguali a oggi. Con `EnhanceImages()` la richiesta è **uguale** a `enhance(current, family:)` (**Review Focus 1**). Versione con `ownSystem`: testo = blocco + `"\n\n"` + `current.prompt`, `images` nell'ordine, opzioni come la versione con system proprio di oggi.
- [ ] **Step 2: Vedere il fallimento** — `swift test --filter PromptBriefTests`.
- [ ] **Step 3: Implementare** (un `private static func imagesBlock(_:) -> String?` condiviso; nil con `isEmpty`).
- [ ] **Step 4: Test verdi.**
- [ ] **Step 5: Commit** — `feat(prompt-assist): richiesta di Migliora con le immagini numerate`.

---

### Task 2: Router con `needsImages`, profilo con immagini

**Files:**
- Modify: `Packages/Sources/HubCore/Language/LanguageModelRouter.swift`, `LanguageModelManager.swift`, `LanguageModelProfile.swift`
- Test: `LanguageModelRouterTests.swift`, `LanguageModelProfileTests.swift`

**Interfaces:**
- Produces: `LanguageModelRouter.model(for:family:models:assignments:needsImages: Bool = false)`; `LanguageModelManager.model(for:family:needsImages: Bool = false)`; `LanguageModelProfile.systemPrompt(for: LanguageModelTask, withImages: Bool) -> String?` (con `systemPrompt(for:)` = `withImages: false`).

- [ ] **Step 1: Test che falliscono**: router — `txt: qwen_image_2.1·enhance` (testo), `vl: *·both` (visione): `.enhance` su `qwen_image_2.1` senza `needsImages` → `txt`, con `needsImages` → `vl`; solo `txt: *·both` con `needsImages` → `.failure(.imagesNotSupported)`; i casi di oggi invariati. Profilo — cartella con `system_prompt_t2i.txt` e `system_prompt_i2i.txt`: `systemPrompt(for: .enhance, withImages: true)` = i2i, `withImages: false` = t2i; con solo `system_prompt.txt` entrambi il generico; con solo t2i: `withImages: true` → nil.
- [ ] **Step 2: Vedere il fallimento.** **Step 3: Implementare** (nel router la condizione diventa `(task == .describe || needsImages) && !model.supportsImages`). **Step 4: Test verdi.**
- [ ] **Step 5: Commit** — `feat(llm): scelta e system prompt per Migliora con immagini`.

---

### Task 3: `PromptAssistant.enhance` con immagini e nota

**Files:**
- Modify: `Packages/Sources/HubCore/PromptAssist/PromptAssistant.swift`, `App/Generation/GenerationController.swift` (costruzione: `resolve` riceve `needsImages`)
- Test: `PromptAssistantTests.swift`

**Interfaces:**
- Consumes: Task 1–2.
- Produces: `Resolve = @MainActor (LanguageModelTask, String?, Bool) -> Result<Choice, LanguageModelError>`; `public enum Note: Equatable, Sendable { case imagesNotSent }`; `public private(set) var note: Note?`; `public func enhance(_ current: PromptPair, family: String?, images: EnhanceImages = EnhanceImages()) async -> PromptPair?`.

- [ ] **Step 1: Test che falliscono**: con immagini il `resolve` è chiamato con `needsImages == true` e `respond` riceve le immagini nell'ordine e il testo con il blocco; con un `resolve` che dà `.imagesNotSupported` per `true` e un modello per `false` → seconda chiamata con `false`, `respond` riceve `images == []` e la richiesta di oggi, `note == .imagesNotSent`, il risultato è scritto (**Review Focus 3**); `.noModelSelected` con `true` → `failure == .model(.noModelSelected)`, nessun ripiego; un'operazione successiva azzera `note`; senza immagini il `resolve` riceve `false` e la richiesta è quella di oggi; con system prompt proprio e immagini si usa `systemPrompt(for: .enhance, withImages: true)`.
- [ ] **Step 2: Vedere il fallimento.** **Step 3: Implementare**; aggiornare la costruzione dell'assistente nei test esistenti e in `GenerationController.init` (`resolve: { task, family, needsImages in languageModel.model(for: task, family: family, needsImages: needsImages).map { … } }`; `describe` passa `true`). **Step 4: Test verdi** (`swift test --filter Prompt`), poi `xcodebuild … build`.
- [ ] **Step 5: Commit** — `feat(prompt-assist): Migliora manda le immagini, con ripiego sul solo testo`.

---

### Task 4: Controller, card Prompt, testi, prove

**Files:**
- Modify: `App/Generation/GenerationController.swift`, `App/Generation/Cards/PromptCard.swift`, `App/Localizable.xcstrings`

- [ ] **Step 1: Controller** — in `enhancePrompt(in:)`: `let images = EnhanceImages(start: control.startImageURL, references: traits(in: connection).usesMoodboard ? control.moodboardURLs : [])` (`moodboardURLs` contiene già solo le accese, in ordine: **Review Focus 4, 5**) e `assistant.enhance(current, family: …, images: images)`.
- [ ] **Step 2: Card** — sotto il pulsante, dopo la riga d'errore, se `controller.assistant.note == .imagesNotSent`: `Text("prompt.assist.note.imagesNotSent").font(.caption).foregroundStyle(.secondary)`.
- [ ] **Step 3: Testi** (it / en): `prompt.assist.note.imagesNotSent` (spec §6); aggiornare `prompt.enhance.help` (spec §6).
- [ ] **Step 4: Compilare e suite** — `xcodebuild … build`; `cd Packages && swift test 2>&1 | grep -E "Test run with|error:"`.
- [ ] **Step 5: Prove a mano** (lista all'utente): spec §8 (la numerazione è già verificata).
- [ ] **Step 6: Commit** — `feat(app): Migliora Prompt usa immagine di partenza e Moodboard`.
- [ ] **Step 7: Messaggio finale** (briefing §6): cosa provare; «Decisioni che ho preso» (testo dei riferimenti; nota non rossa; con costi); «Rinviati» (spec §9); via libera prima di unire, push o release.

---

## Autorevisione

- **Copertura:** spec §3 → Task 1; §4–5 → Task 2–3; §6 → Task 3–4; §7 → Task 1–3; §8 → Task 4.
- **Tipi:** `EnhanceImages` (Task 1) usato nei Task 3–4; `needsImages` (Task 2) arriva da `Resolve` (Task 3); `Note` (Task 3) letto nel Task 4.
