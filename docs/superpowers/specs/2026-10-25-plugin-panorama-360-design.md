# Plug-in «Panorama 360» — spec

Data: 25 ottobre 2026. Stato: **bozza da far approvare**. Percorso: architetturale (nuovo plug-in + due aggiunte al contratto 1).
Mockup: `docs/superpowers/mockups/2026-10-25-panorama-360.html` (interattivo; il menu «stato simulato» in basso mostra errori e avvisi).
Prova della ERP: `docs/superpowers/bench/panorama-erp/` (`make_erp.py`, `make_landscape.py`).

## 1. Scopo

Dentro DT Hub si piazzano immagini di riferimento («sticker») su un canvas 360° (ERP, equirettangolare 2:1) e il LoRA **«360 ERP outpaint»** (nomadoor) di FLUX.2 [klein] **Base** completa il resto del panorama. Equivale ai nodi *Panorama Stickers* di `nomadoor/ComfyUI-Panorama-Stickers` (MIT; la matematica è riscritta in Swift, senza codice copiato).

**Successo:** l'utente trascina 1–N immagini sul canvas, le posiziona (yaw, pitch, FOV, rotazione, opacità, ordine), scrive una descrizione, preme «Invia a Generazione» e RUN produce un panorama 2048×1024 coerente con gli sticker.

### 1.1 Cosa è stato verificato a mano (25 ott, utente, Draw Things)
- Il LoRA funziona come **immagine di partenza** (ERP su verde `#00ff00`, forza 1.0). Come **Moodboard non funziona**.
- A 2048×1024 il risultato è buono. A 1024×512 il cielo regge ma l'acqua viene a strisce radiali: **2048×1024 è la sola dimensione** del plug-in.
- Il workflow di ComfyUI non usa maschera: il segnale è il verde e il prompt «Fill the green spaces…».
- Il preset dell'utente (`PAN · 360 ERP 9B`): modello `flux_2_klein_base_9b_i8x`, refiner `flux_2_klein_9b_kv_i8x` a 0,25, 16 passi, guidance 4, sampler 16, shift 3, shift dipendente dalla risoluzione acceso, LoRA `f2_360_erp_outpaint_lora_v1_lora_f16.ckpt` a 1 con la **frase d'innesco nel campo `trigger` del LoRA** e prompt vuoto. Il codice dell'app antepone i `trigger` dei LoRA al prompt all'invio (`GenerationJob.promptWithTriggers`): **il plug-in non scrive mai la frase nel prompt**.

### 1.2 Fuori dalla prima versione (ma il disegno li prevede)
Si arriva a questi dopo che la versione A funziona; non si fanno ora.
1. **Visore a sfera** (vista panorama puntabile) e **visore del risultato**.
2. **Cutout:** estrazione di viste prospettiche da un ERP.
3. **Correzione della giunzione** tra i due bordi verticali, basata sul metodo di Tiled Upscale per fondere i tile (§9).
Non si fa: copertura 180°, risoluzioni diverse da 2048×1024, colore di sfondo diverso dal verde, maschera, pittura, video/audio, zoom del canvas, FLUX.3 (il LoRA non esiste).

## 2. Scelte dell'utente (registro)
- Prima versione = canvas piatto (unwrap) con sticker; poi sfera, visore, Cutout, giunzione.
- Sticker da: drag & drop (Finder, browser, **galleria dei Risultati**) e tasto «+».
- Solo 360, 2048×1024.
- Nome visibile **«Panorama 360»**; icona SF Symbol `globe` (nessun plug-in gemello da cui ereditare l'icona).
- Rendering: **Metal** (stesso shader per editor, export e, poi, sfera).
- Preset: due, `PAN · 360 ERP` (Normale) e `PAN · 360 ERP Fast` (Veloce, con refiner), **entrambi con modelli 9B**; chi usa la 4B personalizza i preset. Niente distinzione 9B/4B nel plug-in, niente gestione delle quantizzazioni.
- «Migliora prompt» (LLM) c'è, con il testo, come negli altri plug-in; le altre azioni sono icone.
- Nessuna didascalia nell'interfaccia; ordine z con il trascinamento delle righe.
- Prompt e Invia in una sola card.

## 3. Architettura

Pacchetto `Plugins/Panorama360/` (id `com.exiztenz.dthub.panorama360`, nome «Panorama 360»), stessa struttura degli altri (`Package.swift`, `Sources`, `Tests`, `Scripts/build.sh`, `README.md`). Famiglie: `["flux2_9b","flux2_4b"]`. Nessuna dipendenza di codice da altri plug-in (copie dove serve).

| Unità | Compito | Dipende da |
|---|---|---|
| `PSModels` | `Sticker`, `PanoState`, JSON, `version`, migrazioni | — |
| `PSProjection` | matematica pura: ERP↔direzione, base dello sticker, proiezione sul piano tangente, hit-test, puntatore→yaw/pitch, asse orizzontale periodico con offset | — |
| `PSRenderer` | shader Metal compilato da stringa, texture degli sticker in cache, composizione premoltiplicata per ordine z, render su vista e offscreen 2048×1024 | `PSModels`, `PSProjection` |
| `PSCanvasView` | vista 2:1, guide, selezione, sposta/scala/ruota, tastiera, drop | `PSRenderer`, `PSProjection` |
| Schede | Canvas, Sticker (elenco + campi), Prompt (descrizione, Migliora, Annulla, switch, Invia, errori) | sopra |
| `PSStickerStore` | copia le immagini nella cartella del progetto, ricarica, elimina | `PSModels` |
| `PSSender` | rende l'ERP, scrive il PNG, compone il messaggio `contribute` | sopra |
| `PSPresets` | i due preset di fabbrica e i loro nomi | — |
| `PSPrompt` | master prompt, richiesta `llm`, Annulla | — |
| `Strings` | tabella `L` it/en | — |

**Isolamento:** `PSProjection` e `PSModels` non conoscono Metal né SwiftUI; il renderer riceve uno stato e una dimensione.

### 3.1 Dati (`PanoState`)
`version` (1), `stickers[]`, `selectedID`, `description` (testo libero), `mode` (`normal`|`fast`), `guides` (bool). Sticker: `id`, `name`, `file` (relativo alla cartella del progetto), `yaw`, `pitch`, `rot`, `hfov`, `opacity`, `visible`. L'**ordine nell'array è l'ordine z** (ultimo = sopra); il FOV verticale non si salva (deriva dalle proporzioni dell'immagine). Percorso: `<folder>/state.json` (messaggio `project`), scritto a ogni modifica. Immagini copiate in `<folder>/stickers/`. File illeggibile → stato vuoto e il vecchio resta come `state.json.bak`. Spazio previsto per un blocco `seam` futuro (opzionale).

### 3.2 Matematica (`PSProjection`)
Assi: +X destra, +Y su, +Z avanti. ERP: `lon = atan2(x,z)`, `lat = asin(y)`, `u = (lon/2π + 0,5)·W`, `v = (0,5 − lat/π)·H`. Sticker: forward `(sin y·cos p, sin p, cos y·cos p)`, right `(cos y, 0, −sin y)`, up `forward × right`, poi rotazione `rot` nel suo piano; piano tangente con `tanX = tan(hfov/2)`, `tanY = tanX·h/w`; per ogni direzione `d`: `dz = d·fwd`, scartato se `dz ≤ 1e-5`, `u_s = (d·right/dz)/tanX·0,5+0,5`, `v_s = 0,5 − (d·up/dz)/tanY·0,5`. Il bordo destro dell'ERP si ricongiunge al sinistro; yaw avvolto a ±180°; pitch limitato a ±89°; FOV tra 5° e 170°. Il calcolo accetta un offset orizzontale `uOffset` (zero ora): serve alla giunzione.

### 3.3 Rendering (Metal)
Un fragment shader per pixel: direzione, per ogni sticker visibile in ordine z, campionamento bilineare, composizione premoltiplicata sul verde `#00ff00`, opacità. Vista in tempo reale (a metà risoluzione mentre si trascina, piena al rilascio) e render offscreen 2048×1024 per l'invio. Il test confronta il risultato con un riferimento CPU nel solo target dei test. **Rischio e ripiego:** nessun plug-in usa ancora Metal; il Task 0 verifica che lo shader compilato da stringa si carichi nel dylib firmato. Se fallisce, ripiego su un renderer CPU multithread con la stessa interfaccia (`PSRenderer`), senza toccare il resto.

### 3.4 Interfaccia (mockup)
Canvas 2:1 con guide (orizzonte, meridiani ogni 90°, interruttore), tasti `+` e cestino «cancella tutti» (con conferma). Card Sticker: elenco (anteprima, nome, z, occhio) riordinabile con il trascinamento (rilascio = dopo quella riga), duplica ed elimina; campi yaw, pitch, rotazione, FOV orizzontale, FOV verticale (sola lettura), opacità; niente slider con passo. Card Prompt: descrizione, «Migliora prompt» (testo) e Annulla, riga d'errore o avviso, switch **Normale/Veloce**, «Invia a Generazione».
Interazioni: sposta (il puntatore→yaw/pitch con l'offset dal centro costante, attraversa la giunzione), scala dagli angoli (FOV moltiplicato per il rapporto di distanza), ruota dalla maniglia (Shift = 45°), Elimina, ⌘D, frecce 1° (Shift 5°). Più file in un drop: uno sticker per file, a cascata dal centro con 10° di yaw. I campi leggono lo stato, non la copia della scheda (regola dei campi di testo).

## 4. Invio, preset ed errori

**«Invia a Generazione»** (disattivato senza sticker visibili): rende l'ERP, scrive il PNG nella `tempFolder`, manda **un solo** `contribute`:
`preset` = `PAN · 360 ERP` (Normale) o `PAN · 360 ERP Fast` (Veloce); `startImage` = l'ERP; poi `fields`: `prompt` = la descrizione, `width` 2048, `height` 1024; `strength` 1.
Il resto (passi, guidance, sampler, shift, LoRA con trigger, modello, refiner) viene dal preset salvato: **il plug-in non scrive altri parametri e l'utente può personalizzare i due preset** (4B, quantizzazioni, refiner).

**Preset di fabbrica:** all'avvio il plug-in manda `presets` con i due preset (valori del preset dell'utente: 9B Base i8x; Fast con refiner `flux_2_klein_9b_kv_i8x` a 0,25). Il menu non tocca un nome già presente. Nomi in inglese fissi (convenzione dei plug-in); l'interfaccia dice «Normale/Veloce» (it) e «Normal/Fast» (en).

**Errori e avvisi:** i preset/LoRA/modelli mancanti li segnala l'app in `problems`; il plug-in li mostra nel riquadro. Dopo l'applicazione del preset, se il modello nel nuovo `context` non contiene «base» → avviso non bloccante. File non valido nel drop → `notice` «File non valido». Spiegazione per il LoRA mancante nel README (link di scaricamento, regola dei LoRA).

**«Migliora prompt»:** `llm` con il master prompt del plug-in (`Data/panorama-360/master-prompt.md`, più `custom/`), che riscrive **solo la descrizione**, in inglese, senza frasi d'innesco; Annulla ripristina l'ultima scrittura. La lingua si verifica nel codice come in F3 (solo italiano).

## 5. Aggiunte al contratto 1 (app e kit; facoltative, riusabili)
1. **`presets[]` accetta `model` e `advanced`** (per esempio `refinerModel`, `refinerStart`): il file del preset è scritto come lo scrive l'app. Un nome già nel menu non si tocca; valori non validi → `rejected`. Nessun altro cambio (il plug-in non sceglie mai il modello nella pipeline o in `contribute`).
2. **`contribute.preset: "nome"`:** applica il preset salvato come dal menu Preset. I campi diventano teal; `fields` e `startImage` dello stesso messaggio si applicano dopo. Preset assente → `problems`, niente effetto. Non vale mentre una pipeline è in esecuzione (come per le altre).
Da fare: `HubKit/Plugin/PluginContribution.swift` e `PluginPresets.swift` (campi nuovi), `PluginRegistry`, `ContributionStore`, `PresetStore` (scrittura con `advanced`/`model`), kit (helper di `DTHubHost`), `PluginKit/README.md` (con «serve DT Hub ≥ …»: numero deciso alla release), test. Stesso schema di `startImageWindow` e `contribute.result`.

## 6. Test
Elenco nel piano: `PSProjection` (round trip, centro sul pixel, avvolgimento, FOV verticale, hit-test z, offset del puntatore); renderer (Metal = CPU, stato vuoto = verde puro, opacità/z, sticker a cavallo della giunzione); `PSModels` (round trip, `.bak`); campi che leggono lo stato (regola); `PSSender` (messaggio, nomi dei preset, errori, avviso); `PSPrompt` con host finto; localizzazione it/en; render PNG dei tab; lato app: `contribute.preset` e `presets[]` con `model`/`advanced`.

## 7. Fasi (circa 10 task)
0. Prova di caricamento Metal nel dylib firmato (via libera/ripiego CPU).
1. Contratto (app+kit): le due aggiunte, test, README del kit.
2. `PSModels` e stato per progetto.
3. `PSProjection`.
4. Renderer, riferimento CPU, export PNG.
5. Vista del canvas e interazioni.
6. Card Sticker: drop (Finder, browser, galleria), copia nel progetto, riordino.
7. Card Prompt: master prompt, «Migliora prompt», Annulla.
8. Invio, preset di fabbrica, switch, errori.
9. Testi it/en, README, riga in `Plugins/README.md` (con i link ai LoRA su Hugging Face e la nota sulla licenza non commerciale della 9B), `build.sh`, elenco delle prove a mano.
Modo di esecuzione da scegliere con l'utente al piano.

## 8. Consegna
Ramo `feat/panorama-360` (spec, piano, mockup, banco della ERP); nessuna unione né push senza «unisci»/via libera. Le aggiunte al contratto richiedono una versione nuova dell'app (numero deciso alla release). A fine lavoro: nota Obsidian `DT Hub - Panorama 360`, briefing, screenshot per il README, zip `Panorama360.dthubplugin.zip` e riga nel README principale.

## 9. La correzione della giunzione (non ora, ma già nel disegno)
Si farà per ultima. Idea: il plug-in fa ruotare l'ERP generato di metà larghezza (così la giunzione sta al centro), maschera la fascia centrale e la rigenera in una **pipeline guidata** (`session.next`, `mask` 255 dove rigenera), fondendo con i lati come Tiled Upscale fonde i tile (`TUFade` per la dissolvenza, `TUTone` per la luminosità; si copiano nel plug-in). Preparato fin d'ora: asse orizzontale periodico con `uOffset` in `PSProjection` e nel renderer; `PanoState.version` e blocco `seam` opzionale; l'ERP generato sarà riprendibile dai Risultati o dall'immagine di partenza; nessuna scelta che impedisca di aggiungere `session.*` al plug-in.

## 10. Rischi aperti
- Metal nel dylib (ripiego CPU, §3.3).
- Se i risultati chiedono un LoRA a 0,9 o una guidance diversa, si cambia il preset, non il plug-in.
- Il refiner KV Fast non è stato provato con il LoRA 360: va provato a mano.
- Licenze: LoRA 9B con licenza FLUX non commerciale (v2.1), 4B Apache-2.0 nei metadati ma «segui la licenza del modello base»; nota nel README.
- Qualità sotto i 2048 px (strisce): per questo la dimensione è fissa.
