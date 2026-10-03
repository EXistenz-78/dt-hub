# DT Hub — Design delle dimensioni fino a 8192 con il Tiled Diffusion

Data: 3 ottobre 2026 · Stato: realizzata (M7e) · Estende `2026-09-29-dt-hub-core-design.md` (card Dimensioni, Avanzate) e `2026-10-01-tab-control-design.md` (§5 "Adatta le dimensioni")

## 1. Scopo

Generare immagini fino a **8192×8192**. Draw Things lo permette solo con il **Tiled Diffusion** acceso; oggi DT Hub ferma tutto a 2048 (`GenerationParameters.sizeRange = 64…2048`).

Decisioni dell'utente (3 ottobre 2026):
- **il limite segue l'interruttore**: con il Tiled Diffusion acceso i campi delle dimensioni arrivano a 8192; spento, a 2048;
- spegnerlo con dimensioni sopra 2048 le riporta a 2048 **mantenendo il rapporto**, **senza avvisi**;
- il Tiled Diffusion e il Tiled Decoding esistono già nelle Avanzate e non cambiano.

Fuori: altri upscaler; la dimensione di lavoro di maschera e disegno (resta 1024); le dimensioni della correzione ad alta risoluzione (Hires fix, restano fino a 2048); un avviso o un blocco del Run per la memoria; la rimisura della fluidità del pennello a 8192 (da fare dopo, a mano).

## 2. Modello (HubKit)

In `GenerationParameters`:
- `static let sizeRange = 64...2048` resta il limite normale; `static let tiledSizeRange = 64...8192` è quello con il Tiled Diffusion;
- `var sizeLimit: Int`: `tiledSizeRange.upperBound` se `advanced.tiledDiffusion`, altrimenti `sizeRange.upperBound`;
- `static func snap(_ size: Double, limit: Int = sizeRange.upperBound) -> Int`: il multiplo di 64 più vicino, tra 64 e `limit`. Chi non passa il limite (Hires fix, `JobComposer`) resta a 2048;
- `apply(_ ratio:)`, `setWidth(_:keepingRatio:)`, `setHeight(_:keepingRatio:)` e `clamped()` usano `sizeLimit` del parametro stesso; `clamped()` limita ancora un lato alla volta;
- `mutating func fitSizeToLimit()`: se il lato lungo supera `sizeLimit`, porta tutte e due le dimensioni in scala perché il lato lungo valga il limite, con arrotondamento a 64 e minimo 64; altrimenti non fa nulla;
- `mutating func setTiledDiffusion(_ on: Bool)`: imposta l'interruttore e, spegnendo, chiama `fitSizeToLimit()`.

Sessione salvata, preset importati ("custom_configs.json"), "Riprendi parametri" e editor JSON passano già da `clamped()`: una sessione con 4096 e Tiled spento si legge a 2048 su quel lato, una con 4096 e Tiled acceso resta com'è.

## 3. Interfaccia (app)

- **Card Dimensioni**: i campi Larghezza e Altezza prendono l'intervallo `64…sizeLimit` e arrotondano con `snap(_, limit: sizeLimit)`. Il resto (preset dei rapporti, scambio, blocco del rapporto) non cambia: i preset tengono il lato lungo.
- **Avanzate → Tiled Diffusion**: l'interruttore scrive con `setTiledDiffusion`, così spegnerlo riporta le dimensioni dentro 2048. Con il blocco del rapporto attivo, il rapporto bloccato si aggiorna alle nuove dimensioni (come in "Adatta le dimensioni").
- **Tab Control, "Adatta le dimensioni"**: il limite è `parameters.sizeLimit` (8192 con il Tiled acceso), come previsto dalla spec del tab. La dimensione di lavoro di maschera e disegno resta 1024.
- Nessuna stringa nuova.

## 4. Draw Things

`JobMapper` manda già dimensioni e campi del Tiled: nessuna modifica. Verificato dal vivo il 3 ottobre 2026: SD 1.5 (Juggernaut Reborn), 3072×2048, 8 passi, Tiled Diffusion e Tiled Decoding accesi: il server accetta e restituisce un'immagine della dimensione chiesta.

## 5. Test e verifiche

**Unitari (HubKit):**
- `sizeLimit`: 2048 senza Tiled, 8192 con;
- `snap` con e senza limite (valori sopra, sotto, al limite);
- `setWidth`/`setHeight` con rapporto bloccato che non superano il limite; `apply(ratio)` sul lato lungo a 8192;
- `clamped()` con 4096 e Tiled spento → 2048 per lato; con Tiled acceso → invariato; sopra 8192 → 8192;
- `fitSizeToLimit()`: 4096×2048 → 2048×1024; 8192×4096 → 2048×1024; 6000×3000 (con arrotondamento a 64); già dentro il limite → invariato; lato lungo = altezza;
- `setTiledDiffusion(false)` riduce, `setTiledDiffusion(true)` non cambia le dimensioni;
- lettura di una sessione con dimensioni oltre 2048 e Tiled spento/acceso.

**HubCore:** "Adatta le dimensioni" (`FramingMath.adaptedSize`) con limite 8192 (già parametrico).

**Dal vivo con un server vero:** SD 1.5 (Juggernaut Reborn), 3072×2048, 8 passi, Tiled Diffusion e Tiled Decoding acceso: arriva un'immagine della dimensione chiesta.

## 6. Rischi aperti

- A 8192 la memoria e il tempo di Draw Things possono non bastare: DT Hub non lo sa e non lo avvisa (scelta dell'utente: nessun avviso). Un errore del server arriva come errore del Run.
- **Memoria dei risultati** (corretto dopo la revisione): un risultato salvato resta in memoria alla dimensione che serve allo schermo (lato lungo al massimo 2048, `GenerationSession.displayPixels`); il file ha l'originale. Un risultato che non si è potuto salvare resta intero. Senza questa riduzione, ogni immagine a 8192 pesava 256 MiB in memoria per tutta la sessione.
- **Immagini di partenza molto grandi**: Draw Things riceve l'immagine come tensore a 16 bit non compresso (8192² RGB = 384 MiB) più la maschera nello stesso messaggio; il tetto dei messaggi del client è 1 GiB (era 256 MiB, che fermava l'image-to-image e l'inpaint a circa 6600 pixel per lato). Il limite di ricezione del server non è verificato: una generazione da immagine di partenza a 8192² non è stata provata.
- Il pennello del tab Control a 8192 non è misurato.

## 7. Tappa

**M7e** — Dimensioni fino a 8192 con il Tiled Diffusion. Poi: M8 Plug-in, Galleria.
