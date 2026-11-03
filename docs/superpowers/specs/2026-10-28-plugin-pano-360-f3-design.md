# Plug-in «Pano 360 F3» — spec

Data: 28 ottobre 2026. Stato: **design approvato dall'utente (28 ott); spec da rivedere**. Percorso: architetturale (nuovo plug-in) con una **dipendenza dall'app**: i passi guidati devono accettare `moodboard` e poter non avere `startImage` (§5, già scritto sul ramo `feat/guided-pass-moodboard`, non committato).
Fonti: la pagina Civitai «360 Degree [Flux]» (versione Flux 3 Klein, LoRA `360_f3`), la LoRA «360 Flux 2/3 Klein Seamfix» e il workflow ComfyUI `F3_Klein_360_VR.json` di denrakeiw (letto riga per riga); i due preset dell'utente `PANO F3.json` e `PANO F3 Seamfix.json`.

## 1. Scopo

Con **FLUX.3 [klein]** e la LoRA `360_f3` si genera un panorama 360° equirettangolare (2:1) a partire da una o più **immagini di riferimento**; una seconda LoRA, **Seamfix**, ripara la giunzione tra il bordo sinistro e destro. Il plug-in mette le due cose in una sola pipeline guidata: «Invia a generazione», RUN, e il panorama arriva ai Risultati già corretto.

**Successo:** l'utente trascina 1–N immagini nel Moodboard del plug-in, scrive (facoltativo) due righe sul luogo, sceglie la dimensione, preme «Invia a generazione» e RUN produce un panorama senza giunzione visibile; se non gli piace la giunzione, «Correggi giunzione» la ricrea con un altro seme.

### 1.1 Cosa è stato verificato a mano (28 ott, utente, DT Hub)
- La LoRA 360 funziona bene **solo** così: le immagini nel **Moodboard**, senza posizionarle né deformarle su un ERP; **canvas vuoto** 2:1; prompt = trigger `create a 360 hdr` seguito da ` starting from <image 1>` e, per più immagini, `, <image 2>`…
- Il solo trigger non basta. «using <image 1> and <image 2> as references» funziona con più immagini ma con **una sola tende a duplicarla**; «starting from» no.
- Il Seamfix funziona con il quadrato (§6) sia come **immagine di partenza** sia nel Moodboard, e **gira bene a 1024×1024** (metà della risoluzione del workflow ComfyUI).
- Il workflow ComfyUI usa il quadrato come immagine di riferimento (`ReferenceMultiLatent`, latent vuoto), il prompt `seamfix`, CFG 4, 30 passi, `er_sde`, 2048×2048 su un panorama 4096×2048; nei preset dell'utente: 16 passi, guidance 1, sampler 16, shift 16, HiRes acceso.
- La trigger word delle LoRA la aggiunge DT Hub a ogni job (`GenerationJob.promptWithTriggers`), anche a quelli dei passi guidati: il plug-in non la scrive mai.

### 1.2 Fuori dalla prima versione
Coda (`queue.capture`/`queue.prepare`), Cutout, canvas ERP e sticker posizionati, selettore Normale/Veloce, modelli diversi da FLUX.3 [klein] (il plug-in si spegne). La LoRA 360 su FLUX.3 non fa outpaint su verde: Panorama 360 resta per FLUX.2.

## 2. Scelte dell'utente (registro)
- Plug-in **separato** da «Panorama 360» (precedente: un plug-in per famiglia, come PromptMaster/F3/I4/MOSS).
- Schede: **Moodboard** (al posto di Sticker, senza yaw/pitch/FOV/rotazione/opacità: solo aggiungere, riordinare, eliminare), **Prompt** alla sua destra (senza Normale/Veloce), **Visore** sotto (solo visore sferico del risultato, **chiuso di default**, si apre quando c'è un panorama o a mano, accetta trascinamenti da galleria e Finder).
- «Invia a generazione» avvia **una pipeline guidata** con due passi (panorama, Seamfix).
- **«Correggi giunzione»** resta, per rifare la giunzione quando il primo risultato non convince.
- **Il quadrato del Seamfix ha il lato uguale all'altezza del panorama** (1024² a 2048×1024), mai una risoluzione fissa.
- **Nel passo 2 il Moodboard è vuoto**: c'è solo il quadrato con la fascia bianca.
- **Selettore delle dimensioni**, sempre 2:1: parte da 2048×1024; «^» aggiunge 128 in larghezza e 64 in altezza, «v» toglie le stesse quantità.
- Separatore tra l'elenco delle immagini e la descrizione: **«. »**.
- Preset: i due dell'utente (`PANO F3`, `PANO F3 Seamfix`), HiRes acceso in entrambi.

## 3. Architettura

Pacchetto `Plugins/Panorama360F3/` (id `com.exiztenz.dthub.panorama360f3`, nome «Pano 360 F3», icona SF Symbol `globe`, famiglie `["flux3_5b"]`), stessa struttura degli altri (`Package.swift`, `Sources`, `Tests`, `Scripts/build.sh`, `README.md`). **Nessuna dipendenza di codice** da Panorama 360 né da altri plug-in: dove serve si **copiano** i file (prefisso `PF`, dove `PF` sta per «Pano F3»); un pacchetto condiviso si valuta solo se i due plug-in evolvono insieme.

| Unità | Compito | Dipende da |
|---|---|---|
| `PFModels` | `PanoState` (immagini, descrizione, dimensione, visore), JSON, `version` | — |
| `PFImageStore` | copia le immagini nella cartella del progetto (lato lungo 2048), ricarica, elimina | `PFModels` |
| `PFSizes` | passi `^`/`v` del selettore, limiti, controlli dell'altezza (multipli di 64) | — |
| `PFPrompt` | composizione del prompt (§4); «Migliora prompt» (LLM) | — |
| `PFSeam` | **funzioni pure sulle immagini**: quadrato con fascia bianca, rimontaggio, correzione colore Reinhard, feather | — |
| `PFSession` | risposte a `session.next` per i due passi, `session.end`, invio del risultato | `PFSeam`, `PFPrompt`, `PFPresets` |
| `PFPresets` | i due preset di fabbrica e i loro nomi | — |
| Schede | Moodboard, Prompt, Visore (comprimibile) | sopra |
| Visore (copiato) | `PSSphere`, `PSSphereView`, `PSMetalRenderer`, `PSProjection`, `PSMetalProbe`, `PSDrop`, `PSImages` di Panorama 360, solo la sorgente «Risultato» | — |
| `Strings` | tabella it/en | — |

**Isolamento:** `PFSeam`, `PFSizes` e `PFPrompt` non conoscono SwiftUI né Metal né il protocollo del plug-in; ricevono valori e restituiscono valori, e si provano da soli.

### 3.1 Dati (`PanoState`)
`version` (1), `images[]` (`id`, `name`, `file` relativo alla cartella del progetto, `visible`), `description`, `width`/`height` (2:1, default 2048×1024), `viewerOpen`. **L'ordine nell'array è l'ordine `<image N>`**; solo le immagini con `visible == true` vanno al Moodboard della generazione e sono numerate, in ordine, da 1. Percorso: `<folder>/state.json` (messaggio `project`), scritto a ogni modifica; immagini copiate in `<folder>/images/`.

### 3.2 Interfaccia
- **Moodboard**: elenco (anteprima, nome, occhio, elimina), riordino con trascinamento, `+`, drop da Finder, browser e striscia dei Risultati. Il badge di ogni riga è il numero `<image N>`.
- **Prompt**: descrizione, «Migliora prompt» (manda le immagini visibili all'LLM, ridotte, e riscrive solo la descrizione in inglese) e Annulla, **selettore delle dimensioni** («W × H» con `^` e `v`), riga d'errore o avviso, «Invia a generazione».
- **Visore**: sfera del solo risultato, con «Correggi giunzione» nell'intestazione; chiuso all'inizio, **si apre da solo** quando arriva un nuovo panorama; un'immagine trascinata sopra diventa il «risultato» mostrato (come in Panorama 360) e «Correggi giunzione» lavora su quella.
- «Invia a generazione» è **disattivato senza immagini visibili** (senza `starting from` la LoRA non funziona).

## 4. Prompt, dimensioni e preset

**Prompt del passo 1** (senza il trigger, che aggiunge DT Hub): `starting from <image 1>` per un'immagine; `starting from <image 1>, <image 2>, <image 3>` per più; se la descrizione non è vuota si aggiunge il separatore `". "` (punto e spazio) e la descrizione. Esempio con due immagini e la descrizione «foggy cemetery at night»: `starting from <image 1>, <image 2>. foggy cemetery at night`; DT Hub lo manda a Draw Things come `create a 360 hdr starting from <image 1>, <image 2>. foggy cemetery at night`. **Passo 2: prompt sempre vuoto** (DT Hub aggiunge `seamfix`).

**Dimensioni:** `PFSizes` produce solo coppie (W, H) con W = 2H e H multiplo di 64. Da 2048×1024, `^` → 2176×1088, 2304×1152…; `v` → 1920×960, 1792×896…. Intervallo proposto **1024×512 … 8192×4096** (HiRes arriva a 8192 per lato); ai due estremi il pulsante si disattiva. Se il modello accetta meno, l'app rifiuta e il plug-in mostra il suo messaggio.

**Preset di fabbrica** (valori dei file dell'utente; l'app non tocca un nome già presente): `PANO F3` e `PANO F3 Seamfix`, modello `flux_3_klein_q8p.ckpt`, 16 passi, guidance 1, sampler 16, shift 16 (non dipendente dalla risoluzione), `highRes` **acceso**; LoRA `f3_360_lora_f16.ckpt` (trigger `create a 360 hdr`) e `f3_seamfix_lora_f16.ckpt` (trigger `seamfix`), peso 1. Il modello di un passo guidato è quello dell'intestazione (il preset non lo cambia): se differisce, avviso come in Panorama 360.

**Campi di ogni passo:** oltre al preset, il plug-in manda `loras` esplicite (file, peso, trigger, come fa Tiled Upscale), `highRes: true` e `randomSeed: true` (i preset hanno il seme fisso: senza il seme casuale «Correggi giunzione» rifarebbe sempre lo stesso risultato).

## 5. Pipeline guidata

«Invia a generazione» manda un `contribute` con `pipeline: {name, guided: true, passes: 2, estimate}`; l'`estimate` è il passo 1 (preset `PANO F3`, dimensione scelta). Poi l'app chiede i passi con `session.next`:

| Passo | `preset` | `startImage` | `moodboard` | `size` | `fields.prompt` |
|---|---|---|---|---|---|
| 1 Panorama | `PANO F3` | **nessuna** (canvas vuoto) | le immagini visibili, in ordine | W×H scelti | `starting from <image 1>, …` (+ descrizione) |
| 2 Seamfix | `PANO F3 Seamfix` | il quadrato con la fascia bianca (`strength` 1) | **nessuno** | H×H | vuoto |

Il quadrato si costruisce dal PNG del passo 1 (`previous`, §6). A `session.end` con `finished` il plug-in rimonta il risultato (§6) e lo manda come `result` ai Risultati. Con `failed` o `stopped` **dopo il passo 1** manda il panorama grezzo come `result` (descrizione «senza correzione della giunzione»), così il lavoro non va perso.

**Correggi giunzione:** pipeline guidata a **un passo** (il passo 2) sull'immagine mostrata nel Visore. Il plug-in ne tiene una copia propria e costruisce il quadrato da quella (al primo passo non c'è `previous`). Il pulsante è disattivato, con la ragione nel tooltip, se non c'è un risultato, se non è 2:1, se H non è multiplo di 64 o se H > 4096.

### 5.1 Dipendenza dall'app (fatta, sul ramo `feat/guided-pass-moodboard`)
Un passo guidato accetta `moodboard` (`[{"path","name"}]`) e può non avere `startImage` (canvas vuoto di `size`); una `mask` richiede ancora `startImage`. Un'immagine illeggibile del Moodboard è scartata (come in `pipeline`). Documentato in `PluginKit/README.md` per **DT Hub 0.7.0 (numero provvisorio)**; il manifest del plug-in richiede quella versione.

## 6. Il quadrato Seamfix e il rimontaggio (`PFSeam`)

Panorama W×H, W = 2H, `q = W/4 = H/2`. **Quadrato** H×H: a sinistra l'estremo **destro** del panorama (`x ∈ [W−q, W)`), a destra l'estremo **sinistro** (`x ∈ [0, q)`): la giunzione cade al centro. **Fascia bianca** (`#ffffff`) larga `W/8 = H/4` e alta H, centrata (`x ∈ [q − W/16, q + W/16)`).

**Rimontaggio:** (1) correzione colore **Reinhard** (spazio lαβ, media e deviazione per canale) del risultato verso il quadrato **senza fascia**; (2) la metà sinistra del risultato torna all'estremo destro, la destra all'estremo sinistro del panorama originale, ciascuna con un **feather di `q/16` px** sul bordo interno; il resto del panorama resta pixel per pixel com'era.

Il risultato del Seamfix ha la dimensione H×H; se la ricevuta è diversa, si scala (Lanczos) a H×H prima del rimontaggio. Con H = 1024: quadrato 1024², fascia 256, metà 512, feather 32.

## 7. Test

Unitari, nel pacchetto: `PFSizes` (passi, estremi, 2:1, multipli di 64); `PFPrompt` (1, 2, N immagini; immagini nascoste; descrizione vuota/presente; separatore «. »); `PFSeam` (posizioni del quadrato e della fascia, una giunzione sintetica con un gradino che sparisce dopo il rimontaggio, il resto del panorama invariato, Reinhard su immagini note, dimensioni 1024/1088/2048); `PFSession` (risposte dei due passi: nessuna `startImage` e `moodboard` nel primo, `startImage` e Moodboard vuoto nel secondo, `loras`/`highRes`/`randomSeed`; `session.end` con `finished`/`failed`/`stopped`; Correggi giunzione a un passo); `PFImageStore` e `PanoState` (JSON, ordine, migrazione). Le schede e il Visore si provano come in Panorama 360. **La prova reale con Draw Things la fa l'utente.**

## 8. Fasi (circa 8 task)
1. Pacchetto, manifest, `PanoState`, `PFImageStore`, scheda Moodboard.
2. `PFSizes` e `PFPrompt`.
3. `PFSeam` (funzioni pure, con i test).
4. `PFPresets` e registrazione al primo avvio.
5. `PFSession`: pipeline a due passi, `session.end`, risultato.
6. Scheda Prompt (selettore, Migliora prompt, errori).
7. Scheda Visore (copiata) e «Correggi giunzione».
8. README, `Scripts/build.sh`, bundle, prova con l'app 0.7.0.

## 9. Consegna
Plug-in 1.0 nel repository, `Plugins/README.md` aggiornato, `README.md` del plug-in con link alle LoRA (360_f3 e Seamfix, FLUX Kommunity License) e i due preset. Rilascio con l'app 0.7.0.

## 10. Rischi aperti
- **DT Hub 0.7.0** (numero provvisorio): senza l'estensione dei passi guidati il plug-in non funziona; la modifica è sul ramo `feat/guided-pass-moodboard`, non ancora committata né rilasciata.
- **Modello:** la LoRA è addestrata sul modello Base, il preset usa `flux_3_klein_q8p`; non è stato verificato che la differenza non conti. Il plug-in mostra un avviso se il modello non è quello atteso.
- **Canvas vuoto + Moodboard in un passo guidato** non è ancora stato provato con Draw Things dall'app; le prove a mano dell'utente sono in DT Hub con un RUN normale.
- **Dimensioni grandi** (oltre 4096×2048): il passo 1 pesa molto e l'app può rifiutare; il Seamfix è stato visto solo a 1024²–2048².
- **Immagini nascoste e numerazione:** `<image N>` conta solo le immagini visibili; un cambio di visibilità tra «Invia» e RUN non è coperto (come in ogni plug-in).
- **Seme casuale** in entrambi i passi (`randomSeed: true`): un panorama non si ripete identico a ogni RUN. Se dopo le prove serve poterlo fissare, si aggiunge un'opzione; non è nella prima versione.
