# Passaggi di pipeline con valori propri e contesto aggiornato — Design

Data: 9 ottobre 2026. Stato: approvato in chat dall'utente; da implementare in una sessione locale con Xcode e Swift.
Base: `origin/main` (0.1.4 o successiva). Serve al plug-in «Batch plus» (`2026-10-09-plugin-batch-plus-design.md`), ma è un'aggiunta generica al contratto 1.

## 1. Obiettivo

Oggi un passaggio di pipeline proposto da un plug-in (`PipelineStep`) può applicare solo un **preset per nome**. Per una serie che varia un valore servirebbero N preset salvati, che riportano al default tutto ciò che non indicano (avanzate ed «extra» compresi) e restano nel menu Preset.

Si aggiungono tre cose piccole e compatibili:

1. un passaggio può portare **i soli valori da cambiare** (`fields`, `loras`), applicati sopra i campi della scheda;
2. il contesto mandato ai plug-in porta i **parametri attuali** (oggi può portare una copia vecchia);
3. il kit (`DTHubContext`) espone i **parametri**.

Gli altri plug-in non cambiano comportamento (verificato: solo Sphere Light propone pipeline, e usa preset).

## 2. Passaggio con valori

`PipelineStep` (HubKit, `PluginContribution.swift`) guadagna:

```swift
public var fields: FieldOverlay        // le chiavi di `contribute.fields`; vuoto = nessuna modifica
public var loras: [LoRASelection]      // per file: aggiorna peso/modo/trigger di un LoRA della scheda, altrimenti lo aggiunge
```

JSON del passaggio: `{"title", "preset", "fields": {…}, "loras": [{"file","weight","mode","trigger"}], "moodboard", "startImage", "useOutputAsStart"}`. `fields` e `loras` facoltativi; letti con le stesse regole di `contribute` (valori fuori limite riportati nei limiti delle card, chiavi sconosciute ignorate).

Valori con cui gira un passaggio (`PipelinePresets.fields(for:over:presets:catalog:)`):

1. base = campi della scheda; se il passaggio ha un `preset`, il preset applicato sopra (come oggi);
2. poi `fields` applicati sopra (`FieldOverlay.applied(to:)`);
3. poi `loras`: un file già presente aggiorna peso (e modo/trigger se indicati); un file assente si aggiunge in coda;
4. **dimensioni**: restano quelle della base (come per i preset: un passaggio non cambia la dimensione). `width`/`height` in `fields` sono ignorati.

Le impostazioni avanzate e gli «extra» restano quelli della base: `FieldOverlay` non li tocca.

Un passaggio senza preset né `fields` né `loras` gira con la scheda com'è (come oggi).

## 3. Contesto aggiornato

`PluginRegistry` guadagna `@ObservationIgnored public var currentParameters: (@MainActor () -> GenerationParameters)?`. `sendContext` usa `currentParameters?() ?? latestParameters`. L'app lo collega a `generation.parameters`. Quando si apre la scheda di un plug-in (`refreshContext`) i parametri sono quindi quelli attuali; **nessun invio in più**.

## 4. Kit

`PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift`:

```swift
public struct DTHubLoRA: Decodable, Equatable, Sendable {
  public var file: String; public var weight: Double; public var mode: Int; public var trigger: String
}
public struct DTHubParameters: Decodable, Equatable, Sendable {
  public var width, height, steps, cfgZeroInitSteps, sampler, batchSize, batchCount: Int?
  public var guidanceScale, shift: Double?
  public var cfgZeroStar, resolutionDependentShift, randomSeed: Bool?
  public var seed: UInt32?
  public var loras: [DTHubLoRA]?
  public var advanced: [String: DTHubValue]?    // da mostrare, non da cambiare
  public var extra: [String: DTHubValue]?
}
public enum DTHubValue: Decodable, Equatable, Sendable { case bool(Bool), number(Double), string(String), other }
// DTHubContext: public var parameters: DTHubParameters?
```

Tutto facoltativo e decodificato con tolleranza: un campo mancante o di tipo diverso è `nil`, mai un errore che fa perdere il contesto. `README.md` del kit: chiavi di `parameters` nel contesto, `fields`/`loras` nei passaggi.

## 5. Test

HubKitTests: un passaggio JSON con `fields` e `loras` si legge; un passaggio vecchio (solo `preset`) si legge come prima; chiavi sconosciute ignorate. HubCoreTests (`PipelinePresets`): con `fields {steps: 20}` sopra una scheda con avanzate ed extra non di default → solo i passi cambiano, avanzate ed extra intatti; `width/height` in `fields` ignorati; preset + `fields` → `fields` vincono; `loras` aggiorna un peso esistente e aggiunge un file nuovo in coda; passaggio vuoto = scheda. `PluginRegistryTests`: `refreshContext` manda i parametri di `currentParameters`, non quelli dell'ultimo `updateContext`. Kit: `DTHubContext` con e senza `parameters`; valori di tipo sbagliato → `nil` senza perdere il resto.

## 6. Fuori ambito

Prompt nel contesto (variazione parziale del prompt); impostazioni avanzate modificabili da un passaggio; dimensioni per passaggio.
