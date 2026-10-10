# Usi I2I e T2I degli LLM — Design

Data: 9 ottobre 2026. Stato: approvato in chat dall'utente; da implementare in una sessione locale con Xcode e Swift.
Base: `origin/main` con **«LLM per famiglia» (0.1.3–0.1.4) e «Migliora con immagini» già uniti** (`docs/superpowers/specs/2026-10-09-llm-per-famiglia-design.md`, `2026-10-09-migliora-con-immagini-design.md`). Chi implementa verifica i nomi reali introdotti da «Migliora con immagini» (`EnhanceImages`, `needsImages`, `Note.imagesNotSent`) prima di partire.

## 1. Obiettivo

Nelle Preferenze › LLM il menu **Uso** di ogni LLM ha oggi Migliora / Genera / Entrambi / Solo plug-in, legati in modo deterministico ai due tasti. Si aggiungono due usi che dipendono da **cosa c'è in Control**:

- **I2I** — l'LLM vale come «Entrambi», ma **solo quando Control ha immagini**.
- **T2I** — l'LLM vale come «Entrambi», ma **solo quando Control è vuoto**.

Esempio: per Qwen Image 2.1, PE T2I su «Qwen Image 2.1 · T2I» e PE I2I su «Qwen Image 2.1 · I2I»: Migliora Prompt sceglie da solo l'uno o l'altro secondo Control.

## 2. Decisioni (dell'utente e approvate in chat, 9 ottobre)

- **«Control ha immagini»** = c'è un'immagine di partenza, oppure almeno una Moodboard accesa per una famiglia che la legge (`FamilyTraits.usesMoodboard`). Maschera e disegno non contano. È esattamente «`EnhanceImages` non vuoto» di «Migliora con immagini».
- **Genera Prompt** parte sempre da un'immagine: per Genera vale sempre I2I, mai T2I.
- **Nessuna precedenza speciale tra usi:** più LLM sullo stesso posto → vince il primo per nome (come oggi), con l'avviso nelle Preferenze.
- **Visione e contesto sono due cose distinte:** «Control ha immagini» decide quali usi valgono; `needsImages` (di «Migliora con immagini») esige un LLM con visione. Nel ripiego «solo testo» (nessun LLM con visione) Control ha ancora immagini: un LLM su I2I senza visione resta scelto e riceve solo il testo, con la nota «Immagini non inviate».
- Prompt Master accetta anche `use == "t2i"` per il PE di Qwen Image 2.1 (scrive prompt senza immagini); `"i2i"` no. Character Sheet invariato.

## 3. Dati

```swift
// HubCore/Language/LanguageModelAssignment.swift
public enum LanguageModelUse: String, Codable, Sendable, CaseIterable {
  case enhance, describe, both, pluginsOnly, i2i, t2i
  public func covers(_ task: LanguageModelTask, controlHasImages: Bool) -> Bool
}
// HubCore/Language/LanguageModelNeeds.swift (nuovo)
public struct LanguageModelNeeds: Equatable, Sendable {
  public var controlHasImages: Bool   // quali usi valgono (I2I / T2I)
  public var needsImages: Bool        // serve un LLM con visione
  public init(controlHasImages: Bool = false, needsImages: Bool = false)
}
```

Tabella di `covers`:

| Uso | Migliora, Control vuoto | Migliora, Control con immagini | Genera |
|---|---|---|---|
| enhance | sì | sì | no |
| describe | no | no | sì |
| both | sì | sì | sì |
| pluginsOnly | no | no | no |
| i2i | no | sì | sì |
| t2i | sì | no | no |

`covers(_:)` senza contesto sparisce (ogni chiamante passa il contesto). Il valore grezzo (`"i2i"`, `"t2i"`) è anche quello salvato in `LanguageModelSettings` (codifica `rawValue`); impostazioni vecchie si leggono come prima.

## 4. Router e manager

- `LanguageModelRouter.model(for:family:models:assignments:needs: LanguageModelNeeds = .init())` sostituisce il parametro `needsImages:` introdotto da «Migliora con immagini». Usa `covers(task, controlHasImages: needs.controlHasImages)`; un LLM senza visione è scartato se `task == .describe || needs.needsImages` (esito `.imagesNotSupported` come oggi).
- `LanguageModelRouter.shadowed`: un LLM «vince» se vince almeno in una situazione che il suo uso copre, tra: Migliora con Control vuoto, Migliora con immagini (con `needsImages: true` solo se il modello legge immagini, altrimenti `false`), Genera (con `controlHasImages: true`). Altrimenti è in ombra.
- `LanguageModelManager.model(for:family:needs:)` lo passa avanti.

## 5. Assistente e controller

- `PromptAssistant.Resolve` = `@MainActor (LanguageModelTask, String?, LanguageModelNeeds) -> Result<Choice, LanguageModelError>`.
- `enhance(_:family:images:)`: `controlHasImages = !images.isEmpty`; prima `needs = (controlHasImages, needsImages: controlHasImages)`; se l'esito è `.imagesNotSupported`, di nuovo con `(controlHasImages, needsImages: false)`, richiesta senza immagini e `note = .imagesNotSent` (comportamento di «Migliora con immagini», ora con il contesto conservato).
- `describe`: `needs = (controlHasImages: true, needsImages: true)`.
- `GenerationController`: nessuna logica nuova; `EnhanceImages` già raccolto con la regola della Moodboard; la `resolve` passa `needs` al manager.

## 6. Plug-in

- `LanguageModelAssignment.pluginFields.use`: anche `"i2i"` e `"t2i"`. `PluginKit/README.md`: elenco dei valori aggiornato, con il significato («depends on whether the Control tab has images»).
- Prompt Master (`PEPlanner.plan`): l'assegnazione vale se `use` è in `["enhance", "both", "t2i"]`.

## 7. Preferenze

- Menu Uso: dopo «Entrambi», `I2I (immagini in Control)` / `I2I (images in Control)` e `T2I (Control vuoto)` / `T2I (empty Control)`, prima di «Solo plug-in».
- Nota `prefs.llm.assign.note` estesa: «I2I e T2I valgono come Entrambi solo con immagini in Control (immagine di partenza o Moodboard accesa) o solo con Control vuoto.» / «I2I and T2I act as Both only when the Control tab has images (start image or a Moodboard picture that is on), or only when it is empty.»

## 8. Test

HubCoreTests: `covers` per tutte le righe della tabella (§3); codifica/decodifica di `i2i`/`t2i`; router: PE T2I (`qwen·t2i`, testo) e PE I2I (`qwen·i2i`, visione) → Migliora con Control vuoto = PE T2I, con immagini = PE I2I, Genera = PE I2I; `t2i` mai per Genera; `i2i` senza visione con immagini e `needsImages: true` → `.imagesNotSupported`, con `needsImages: false` → scelto; `shadowed` con la coppia T2I/I2I → nessuno in ombra; due `i2i` sulla stessa famiglia → il secondo in ombra; `pluginFields` per i due nuovi usi. `PromptAssistantTests`: con immagini `needs == (true, true)`, ripiego `(true, false)`; senza immagini `(false, false)`; Genera `(true, true)`. Prompt Master: `PEPlannerTests` con `use "t2i"` scelto, `"i2i"` no.

## 9. Da verificare a mano

- PE T2I su «Qwen Image 2.1 · T2I», PE I2I su «Qwen Image 2.1 · I2I», Qwen3-VL su «Tutti gli altri · Entrambi»: Migliora con Control vuoto → PE T2I; con immagine di partenza → PE I2I; con sola Moodboard accesa → PE I2I; Genera → PE I2I; un'altra famiglia → Qwen3-VL.
- Nessun avviso di precedenza su PE T2I e PE I2I.
- Prompt Master su Qwen 2.1 con PE T2I su «T2I»: usa il PE.

## 10. Fuori ambito

Precedenza automatica degli usi specifici sui generici; contare maschera e disegno come immagini; I2I/T2I per i plug-in diversi da Prompt Master.
