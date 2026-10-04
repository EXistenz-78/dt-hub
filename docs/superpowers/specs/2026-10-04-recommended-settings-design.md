# DT Hub — Design delle impostazioni consigliate per modello

Data: 4 ottobre 2026 · Stato: realizzata · Estende `2026-09-29-dt-hub-core-design.md` (§5 modelli, §6 parametri)

## 1. Scopo

Quando si sceglie un modello, la Generazione deve partire da una **base sensata per quel modello**: passi, CFG, sampler e shift. Oggi restano i valori del modello precedente (per esempio i 30 passi e il CFG 4 di un modello "base" su un modello "turbo" da 8 passi e CFG 1). Draw Things ha questi valori come «Recommended Settings»; DT Hub li ha in una tabella a parte, che non è nel menu Preset.

Decisioni dell'utente (4 ottobre 2026):
- un set minimo per modello: **N passi, CFG, sampler, shift**; l'utente poi cambia quello che vuole;
- separati dai preset, **non nel menu**, caricati quando si seleziona un modello;
- i valori vengono dalla **lista pubblica di Draw Things**, non scritti a mano.

Fuori: preset "di default" modificabili dall'utente per modello; un avviso o un annulla dopo l'applicazione; valori per le dimensioni, il Tiled Diffusion, le LoRA, le card Avanzate (non sono "base"); aggiornare la tabella da Internet a runtime.

## 2. La fonte dei valori

La lista delle 57 configurazioni ufficiali di Draw Things è **già sul Mac**, nella cache dell'app Draw Things (`~/Library/Containers/com.liuliu.draw-things/Data/Library/Caches/net/configs.json`, circa 58 KB): nessun download. Ogni voce ha il modello, i passi, il CFG, il sampler e lo shift (`version` su una o più voci di ogni famiglia: per FLUX.1 sta su [dev], non su [schnell]).

Uno script (`Scripts/make-recommended-settings.py`) la converte in **`App/Resources/RecommendedSettings.json`**, un file incluso nell'app, che DT Hub legge una volta: non legge mai la cache di Draw Things a runtime (non c'è sulle altre macchine). Si rigenera con lo script quando Draw Things aggiorna la lista.

Regole dello script:
- **Chiave: il nome del file del modello senza quantizzazione**: `flux_2_klein_9b_f16.ckpt` e `flux_2_klein_9b_q6p.ckpt` sono la stessa voce `flux_2_klein_9b` (si tolgono, dalla fine, `_f16`, `_f32`, `_bf16`, `_q<N>p`, `_i8x`, `_svd`, e `.ckpt`).
- Le voci **con LoRA** («with Lightning 4-Step», «with Turbo») sono **scartate**: non sono i valori di base del modello. Se due voci hanno la stessa chiave si tiene la prima.
- **Famiglie**: dove la lista dice `version` (`v1`, `sdxl_base_v0.9`, `flux1`, `flux2`, `flux2_9b`, `qwen_image`, `z_image`, …) la voce vale anche come ripiego per la famiglia, per i modelli che la lista non nomina (le versioni "fine-tuned" di SD 1.5 e SDXL). Attenzione: il ripiego prende i valori della voce con `version`, che in alcune famiglie è il modello distillato (Z-Image, ERNIE, Krea → 8 passi e CFG 1; FLUX.2 Klein → 4 passi e CFG 1): un modello della famiglia che la tabella non nomina (per esempio un fine-tune di un modello base) prende quei valori.
- I campi: `steps`, `guidanceScale`, `sampler` (il numero di Draw Things, lo stesso di `Sampler`), `shift` e `resolutionDependentShift`. Quando la lista non dà lo shift (modelli con "shift in base alla risoluzione") la voce ha `shift` nullo e l'interruttore acceso: lo shift del tab resta com'è, spento dall'interruttore.

Nel file dell'utente le 46 voci coprono i suoi modelli veri (Klein, Qwen, Z-Image, ERNIE, Krea, Ideogram, FLUX.1, …); restano senza voce solo i modelli che non generano immagini (encoder, upscaler, SeedVR…) e i fine-tuned, che hanno il ripiego di famiglia (SD 1.5, SDXL) se la famiglia c'è.

## 3. Quando si applica

- **Solo quando l'utente sceglie un modello dal menu dell'header** (`HeaderBar`) e il modello **cambia**: scegliere lo stesso modello non tocca niente.
- **Mai** all'avvio (si ripristina la sessione com'era), né quando un **preset** sceglie un modello (i valori del preset valgono), né in una **pipeline**, né con «Riprendi parametri», né dall'editor JSON, né da un plug-in (che non cambia mai il modello).
- Cerca la voce per nome del file, poi per famiglia del modello (la `version` del catalogo del server); se non c'è, **non cambia nulla**.
- Cambia **soltanto** passi, CFG, sampler, shift e l'interruttore dello shift. Dimensioni, seed, batch, LoRA, card Avanzate, prompt e negativo restano.
- Nessun avviso e nessun annulla (decisione di prodotto, rivedibile): i valori cambiano e basta; l'utente vede che sono quelli del modello perché li ha davanti.

## 4. Moduli toccati

| Modulo | Cambia |
|---|---|
| HubKit | `RecommendedSettings` (la tabella: voci per modello e per famiglia, ricerca per file e famiglia, lettura permissiva del JSON), `RecommendedValues` (i cinque campi) |
| HubKit | `GenerationParameters.applying(_:)` (passi, CFG, sampler, shift, interruttore, poi `clamped()`: riduce anche i passi iniziali di CFG-Zero* ai passi) |
| HubCore | `ModelSelection.choose(_:applyingTo:from:in:)` (seleziona e restituisce i parametri consigliati solo se il modello cambia e la tabella lo conosce per file, poi per famiglia del catalogo) |
| App | `RecommendedSettings.json` come risorsa; `GenerationController.chooseModel(_:in:)` per il menu dell'header (seleziona e applica); le altre vie di selezione non cambiano |
| Script | `Scripts/make-recommended-settings.py` |

## 5. Test e verifiche

**Unitari:** la ricerca (nome esatto, nome con un'altra quantizzazione, ripiego di famiglia, nessuna voce); l'applicazione (solo i cinque campi, valori limitati come le card, shift nullo lascia lo shift com'è); lettura permissiva del JSON (voci rovinate, campi mancanti); lo script (voci con LoRA scartate, quantizzazioni tolte, famiglie dalla `version`) provato su un piccolo file di esempio.
**App:** cambiare modello dal menu cambia i valori; scegliere lo stesso modello no; caricare un preset che nomina un altro modello lascia i valori del preset.
**Dal vivo:** Klein → Qwen Image 2.1 → ERNIE Turbo → Z-Image: i quattro valori seguono la lista di Draw Things.

## 6. Rischi aperti

- La lista di Draw Things cambia con le versioni dell'app: la tabella vecchia resta valida ma non nomina i modelli nuovi (si rigenera).
- Un utente che ha già regolato passi e CFG li perde cambiando modello: è il comportamento voluto, ma potrebbe sorprendere.
- I valori sono quelli della quantizzazione consigliata da Draw Things: per altre quantizzazioni dello stesso modello valgono comunque.
- I numeri sono fatti pubblici di Draw Things (passi, CFG, sampler, shift); la tabella non ne copia altro.

## 7. Tappa

Una tappa a sé, **dopo il merge dell'M8b** (già fatto). Branch dedicato, spec → piano → prototipo → prova su un `main` pulito → revisione → prova dell'utente → merge.
