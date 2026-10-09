# LLM assegnati alle famiglie dei modelli — Design

Data: 9 ottobre 2026. Stato: approvato in chat dall'utente; da implementare in una sessione locale con Xcode e Swift.
Base: `origin/main` a `50e8a0e` (release 0.1.3).

## 1. Obiettivo

Oggi «Migliora Prompt» e «Genera Prompt» usano sempre l'LLM scelto nelle Preferenze (`LanguageModelSettings.selectedModel`). Alcuni LLM sono fatti per una famiglia (PE T2I e PE I2I per Qwen Image 2.1), e i plug-in li riconoscono dal nome della cartella (`PEPlanner.marker = "qwen_image_2_1_pe_t2i"`, `CSBrief.isPEI2I`): fragile, perché altri utenti chiamano le cartelle in altro modo e usciranno LLM dedicati nuovi.

Si lega un LLM a una famiglia **per scelta dell'utente**, nelle Preferenze, senza dipendere dal nome della cartella.

Successo: con PE T2I assegnato a «Qwen Image 2.1 · Migliora» e Qwen3-VL a «Tutti gli altri · Entrambi», Migliora Prompt su Qwen Image 2.1 usa PE T2I con il suo system prompt; Genera Prompt su Qwen Image 2.1 e i due tasti su ogni altra famiglia usano Qwen3-VL. Con un solo LLM installato non si deve configurare nulla.

## 2. Decisioni (dell'utente, 9 ottobre)

- Preferenze › LLM: al posto del menu «Modello», l'**elenco degli LLM installati**; per ognuno un menu **Famiglia** (le famiglie dei modelli generativi più «Tutti gli altri») e un menu **Uso**.
- Uso: **Migliora prompt / Genera prompt / Entrambi / Solo plug-in**.
- Se nella cartella dell'LLM c'è un **system prompt suo**, lo si usa al posto delle regole dell'app.
- I plug-in ricevono famiglia e uso; **Prompt Master** li usa per il PE di Qwen Image 2.1, con il nome della cartella come ripiego. **Character Sheet resta com'è** (scelta manuale del modello: a volte l'LLM generico fa meglio).
- **Con un solo LLM installato** va automaticamente su «Tutti gli altri · Entrambi».
- Approvato in chat: due LLM sullo stesso posto → vince il primo per nome, con un avviso nelle Preferenze; chiave dell'assegnazione = nome relativo alla cartella dei modelli; impostazioni del modello da `generation_config.json` se c'è.

## 3. Dati

```swift
// HubCore/Language/LanguageModelAssignment.swift
public enum LanguageModelFamily: Hashable, Codable, Sendable {
  case none                  // non usato dai tasti (resta visibile ai plug-in)
  case allOthers             // «Tutti gli altri»
  case family(String)        // chiave `version` di Draw Things, es. "qwen_image_2.1"
}   // codifica come stringa: "" = none, "*" = allOthers, altrimenti la chiave
public enum LanguageModelUse: String, Codable, Sendable, CaseIterable { case enhance, describe, both, pluginsOnly }
public struct LanguageModelAssignment: Equatable, Codable, Sendable {
  public var family: LanguageModelFamily
  public var use: LanguageModelUse
}
// HubKit/Language/LanguageModel.swift
public enum LanguageModelTask: Equatable, Sendable { case enhance, describe }
```

`LanguageModelError` **non** cambia (è nel contratto dei plug-in, `LanguageModelContractTests`): «nessun LLM per questo» riusa `.noModelSelected`, con un testo nuovo (§9).

`LanguageModelSettings` guadagna `assignments: [String: LanguageModelAssignment]` (chiave = `LanguageModelDescriptor.name`), decodifica lenient (assente = vuoto). `selectedModel` resta solo per la migrazione.

Le assegnazioni di LLM che al momento non si trovano (disco esterno non montato) **non** si cancellano.

## 4. Riconciliazione (quando la lista degli LLM cambia)

`LanguageModelAssignments.reconciled(_ settings:, models:) -> [String: LanguageModelAssignment]`, funzione pura, applicata dal `LanguageModelManager` a ogni `respond` e a ogni rilettura della cartella (Preferenze, fine di un download), e salvata se cambia:

1. **Migrazione:** se `assignments` è vuoto e `selectedModel` indica un LLM presente, quello diventa `allOthers · both`.
2. **Un solo LLM:** se nella cartella c'è un solo LLM, senza voce o su `none`, e nessuno è su `allOthers`, diventa `allOthers · both`. Un'assegnazione a una famiglia non si tocca mai.
3. **Download:** il modello consigliato appena scaricato va su `allOthers · both` se nessuno è su `allOthers` (stessa regola del punto 2, estesa al modello scaricato).
4. Ogni LLM presente senza voce ottiene `none · both` (il menu Uso mostra «Entrambi» pronto per quando si sceglie la famiglia).

## 5. Scelta dell'LLM

`LanguageModelRouter.model(for task:, family:, models:, assignments:) -> Result<LanguageModelDescriptor, LanguageModelError>`, funzione pura:

1. Candidati con `family == .family(F)`, uso che copre il compito (`enhance` ← enhance/both; `describe` ← describe/both; `pluginsOnly` mai) e, per `describe`, `supportsImages`. Il primo per nome (`localizedStandardCompare`) vince.
2. Se nessuno: la stessa ricerca su `.allOthers`.
3. Se nessuno: `.failure(.noModelSelected)`; ma se per `describe` esistevano candidati (al punto 1 o 2) scartati solo perché non leggono immagini, `.failure(.imagesNotSupported)` (è quello che succede oggi chiedendo un'immagine all'LLM scelto senza visione).

`family == nil` (catalogo non caricato) salta il punto 1.

`LanguageModelRouter.shadowed(models:, assignments:) -> Set<String>`: i nomi degli LLM che non vincono mai su almeno un posto (famiglia + compito) dove sono assegnati; le Preferenze mostrano l'avviso sulla loro riga.

**Plug-in che chiedono senza nome di modello** (`llm` senza `model`): `LanguageModelManager.respond` usa `LanguageModelRouter` con `family: nil` e compito `describe` se ci sono immagini, altrimenti `enhance` (oggi usa `selectedModel`).

## 6. System prompt e impostazioni dell'LLM

`LanguageModelProfile.load(folder: URL, read: (URL) -> Data?) -> LanguageModelProfile`:

- `systemPrompt(for task:) -> String?`: per `enhance` il primo non vuoto tra `system_prompt_t2i.txt`, `system_prompt.txt`; per `describe` tra `system_prompt_i2i.txt`, `system_prompt.txt`. Testo con spazi ai bordi tolti.
- `generation`: da `generation_config.json`, se presente, `temperature`, `top_p`, `top_k` (tutti facoltativi).

Con un system prompt proprio, `PromptBrief` costruisce la richiesta così:
- **Migliora:** `prompt` = il testo dell'utente così com'è (niente istruzioni dell'app); `options = LanguageModelOptions(system: <suo>, temperature/topP/topK: da generation, maxTokens: 16384, thinking: true)`.
- **Genera:** l'immagine e il testo `Describe this image as a prompt for an image-generation model.`, stesse opzioni.

Senza system prompt proprio: esattamente come oggi (regola generica + note della famiglia, `maxTokens 2048`, `thinking false`).

Il parser (`PromptBrief.parse`) toglie già `<think>…</think>`. Il negativo si aggiorna solo se la famiglia lo usa e la risposta lo contiene, come oggi.

## 7. Interfaccia — Preferenze › LLM

- Cartella dei modelli e download come oggi.
- Al posto del `Picker("prefs.llm.model")`: un elenco, una riga per LLM: nome, dimensione, icona `eye` se legge immagini; menu **Famiglia** (Nessuna, separatore, le famiglie, separatore, Tutti gli altri); menu **Uso** (disattivato con Nessuna).
- Famiglie nel menu: le 13 di `PromptGuides` con la loro `label`, più le famiglie del catalogo del server connesso non incluse (con la chiave come nome), in ordine di nome. Funzione pura `LanguageModelFamilyOptions.list(catalogFamilies:) -> [(key: String, label: String)]`.
- Riga con avviso (`exclamationmark.triangle`, testo «Un altro LLM ha la precedenza per questa famiglia e questo uso») se il nome è in `shadowed`.
- Nota sotto l'elenco: «Gli LLM su "Tutti gli altri" servono tutte le famiglie senza un LLM proprio. "Solo plug-in" li lascia ai plug-in.»

## 8. Plug-in

- `PluginLanguageModel` (HubKit) e `DTHubLanguageModel` (PluginKit) guadagnano `family: String?` (`"*"` = Tutti gli altri, la chiave della famiglia, assente = Nessuna) e `use: String?` (`"enhance"`, `"describe"`, `"both"`, `"plugins"`). Facoltativi: aggiunta compatibile al contratto 1. `PluginKit/README.md` lo documenta.
- **Prompt Master** (`PEPlanner.plan`): per `qwen_image_2.1` cerca prima un LLM con `family == "qwen_image_2.1"`, `use` in `enhance`/`both` **e** un system prompt nella cartella; se c'è, lo usa. Altrimenti il comportamento attuale (marcatore nel nome). Versione del plug-in alzata (minore).
- **Character Sheet:** nessuna modifica.

## 9. Errori

- `.noModelSelected`: nuovo testo di `llm.error.noModel`, «Nessun LLM assegnato per questa famiglia: sceglilo in Preferenze › LLM.» (it/en).
- `system_prompt*.txt` o `generation_config.json` illeggibili: ignorati (come se non ci fossero).
- I test esistenti di `LanguageModelManagerTests` (che scelgono il modello con `selectedModel`) devono restare verdi **senza modifiche**: sono la prova della migrazione (§4.1) e dell'errore `.imagesNotSupported`.

## 10. Test

HubCoreTests: codifica di `LanguageModelFamily` (`""`, `"*"`, chiave) e di `LanguageModelSettings` vecchie (senza `assignments`); `reconciled` (migrazione, un solo LLM, download, assegnazioni di LLM assenti conservate, nuovi su `none · both`); `LanguageModelRouter` (famiglia, ripiego su Tutti gli altri, visione per Genera con `.imagesNotSupported`, `pluginsOnly` escluso, `family nil`, doppioni → primo per nome, `shadowed`, `.noModelSelected`); `LanguageModelProfile` (t2i/i2i/generico, vuoti, `generation_config.json` parziale o rotto); `PromptBrief`/`PromptAssistant` con e senza system prompt proprio; `LanguageModelFamilyOptions.list`; `LanguageModelManager.respond` senza nome usa il router. Plug-in: `PEPlannerTests` con assegnazione, senza system prompt (ripiego), senza assegnazione (marcatore). L'app non ha test di UI: prove a mano (§12).

## 11. Fuori ambito (YAGNI)

System prompt o impostazioni modificabili a mano; più di una famiglia per LLM; Character Sheet; riconoscere i PE dal contenuto dei pesi; timeout configurabili.

## 12. Da verificare a mano (Mac, modelli veri)

- Sul disco: le cartelle di PE T2I e PE I2I hanno `generation_config.json`? Con quali valori? (Se manca, si usano le impostazioni dell'app.)
- Un solo LLM installato: nessuna configurazione, i tasti funzionano.
- PE T2I su «Qwen Image 2.1 · Migliora», Qwen3-VL su «Tutti gli altri · Entrambi»: Migliora su Qwen 2.1 usa PE T2I (pensa a lungo, risponde in inglese); Genera su Qwen 2.1 usa Qwen3-VL; un'altra famiglia usa Qwen3-VL.
- Due LLM sullo stesso posto: avviso sulla riga di chi perde.
- Prompt Master su Qwen 2.1 con PE T2I rinominato a piacere ma assegnato: usa il PE.
- Aggiornamento da 0.1.3 con un LLM scelto: diventa «Tutti gli altri · Entrambi».
