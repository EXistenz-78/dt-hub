# Generazione video: design

Data: 2026-10-29. Ramo: `feat/video`. Stato: bozza da rivedere.

## Obiettivo

Generare video dal server gRPC di Draw Things (porta 7859, collegato a DT+ cloud) dentro DT Hub, con
modelli e parametri equivalenti a quelli dell'app Draw Things. Il video esce come MP4 HEVC con audio e
compare nella stessa striscia Risultati delle immagini.

Decisioni di base:
- Approccio A: si estende il modello di risultato esistente, nessun tipo parallelo.
- T2V e I2V automatici: se la scheda Control ha un'immagine iniziale la richiesta e' I2V.
- Tutte le prove di generazione passano dal cloud DT+. Gli `internalError` casuali del server non indicano un difetto.

## Modelli della prima release

| Modello | File | Note |
|---|---|---|
| MiniMax H3 (fl2va, ref2va) | `minimax_h3_fl2va_i4x`, `minimax_h3_ref2va_i4x` (cloud); varianti q8p/q6p/i8x (locale) | famiglia `minimax_h3` |
| FastH3 Omni | `fasth3_omni_i4x` (cloud); `fasth3_omni_q8p`, `_i8x` (locale) | community: serve l'`override` con la specifica |
| LTX-2.3 22B | q8p (cloud) | famiglia `ltx2.3` |

Wan 2.2 5B e' fuori: nelle prove restituiva rumore e la causa non e' chiara.

### Modelli locali

Sono inclusi, come test di fattibilita' della prima release. Non sono stati provati in locale: sul cloud le
varianti diverse da i4x restituiscono 1 frame senza audio, e questo e' il motivo per cui prima erano escluse.
- Il filtro cloud di `CatalogBuilder.cloudCatalog` per le famiglie video accetta anche i file installati nel Mac,
  ricavati dall'elenco file del server. Nell'elenco i modelli locali hanno l'etichetta "locale".
- Il controllo "un solo frame" e' un errore solo per modelli cloud. In locale non scatta.
- Prima di chiudere il piano serve una prova manuale in locale con almeno un modello H3. Alcuni file sono molto grandi: il download resta a carico dell'utente.

## Specifiche dei modelli community

Per i modelli non ufficiali la richiesta deve contenere la specifica nell'`override`, altrimenti il server
restituisce rumore. La specifica viene da `kcjerrell/dt-models` (`community_models.json`).
- Un file JSON incluso nell'app contiene le voci dei soli modelli abilitati (H3 e FastH3, tutte le quantizzazioni). Nessun download a runtime.
- La specifica si registra con `registerRemoteSpec` prima di generare. H3 e LTX sono riconosciuti dalla libreria.
- La famiglia del modello e' impostata sempre, cosi' la libreria ricava fps (LTX 25, H3 24) e frequenza audio (LTX 48 kHz, H3 32 kHz).
- FastH3 (`modifier: ref2va`) secondo la nota del modello richiede un'immagine di riferimento, ma nelle prove funzionava senza. Il design non la impone e mostra un avviso soft se manca. Da riverificare nel piano.

## Sblocco nell'app

`ModelTree` (`ModelTree.swift:59-60`) oggi nasconde tutte le famiglie video tramite `VideoFamilies`. Il filtro
diventa una lista esplicita di famiglie abilitate: `minimax_h3` e `ltx2.3`.

## Interfaccia

Due card nel pannello parametri, sotto Campionamento e LoRA e prima del checkbox "Mostra impostazioni avanzate".
Compaiono solo con un modello video.

### Card "Video Settings"
- Numero di frame, con passo valido per famiglia. H3 e FastH3: 17k+5 (5, 22, 39, 56, 73, 90, 107, 124...). LTX-2.3: 8k+1 (25, 81, 121...). Per H3 vale il codice del server, non la tabella del client ufficiale.
- Accanto al numero di frame, solo la stima in secondi (esempio "5,2 s"), calcolata con gli fps del modello. Nessun campo per fps o durata.
- Audio Shift (`shiftForAudio`, predefinito 3, intervallo 0,1-12): solo H3 e FastH3.
- Strategic Stochastic Sampling (`stochasticSamplingGamma`, predefinito 0,3, intervallo 0-1): solo LTX-2.3 con sampler TCD Trailing.
- Compression Artifacts (`compressionArtifacts`: `disabled`, `h264`, `h265`, `jpeg`): tutti i modelli video.

### Card "Accelerator Settings" (solo H3 e FastH3)
- Sol Attention (`usesSolAttention`): checkbox, disattivato per default. Se attivo: Start Step (`solAttentionStart`, 2) e Tau (`solAttentionTau`, 0,50), campi numerici.
- TeaCache (`teaCache`): checkbox, disattivato per default. Se attivo: Start (5), End, Threshold (0,06), Max Skip Steps (3), campi numerici. Il valore predefinito di End e' 50 nell'app DT e -1 nel client ComfyUI: da fissare in fase di piano verificando il comportamento reale.
- Le descrizioni dell'app DT diventano il testo dei tooltip.

### Valori predefiniti
Nessun menu preset. Alla selezione di un modello video si applicano i suoi valori predefiniti, con lo stesso
meccanismo dei modelli immagine (da individuare nel codice in fase di piano).
- FastH3: 8 step, DDIM Trailing (sampler 16), guidance 1, shift 12, audio shift 3, 768 di lato corto.
- H3: shift 12, 50 step (valori delle prove funzionanti).
- LTX-2.3: 8 step, TCD Trailing (sampler 19), shift 5, guidance 1, 121 frame, correzione ad alta risoluzione 640x384 -> 1280x768, strength 0,7, fissa.
- Gli fps non sono un campo: li fornisce la famiglia e servono solo all'export.

### Stima CU
Nessuna stima in prima release. I consumi si misurano e si regolano sul campo.

### Immagine iniziale
Con un'immagine nella scheda Control la richiesta e' I2V. La scheda mostra un'etichetta "Immagine -> video".

### Avanzamento
Con la correzione ad alta risoluzione il totale e' steps x (1 + strength), come nel client ufficiale.

## Risultati, riproduzione, export

### Cosa si salva
A fine generazione l'app codifica subito un MP4 HEVC (AVAssetWriter) e lo scrive nell'`ImageStore` insieme a
un fotogramma di copertina (il primo). I frame grezzi non si tengono: 124 frame a 832x512 sono oltre 200 MB in RAM.
- Audio: float32 planare stereo (intestazione 68 byte, eventuale compressione fpzip) scritto come traccia AAC alla frequenza della famiglia. Se il modello non produce audio, l'MP4 e' senza traccia.
- Il modello di risultato riceve campi opzionali: percorso del video, durata, fps, numero di frame, presenza di audio. Per le immagini non cambia nulla.

### Pipeline
- `GenerationUpdate.finished` porta oggi `[CGImage]`. Si aggiunge un esito video con frame, audio e fps.
- `JobMapper.finalImages` taglia le immagini a `batchSize`: per i video non deve farlo. Il batch e' sempre 1.

### Striscia Risultati
Il video e' una miniatura normale (la copertina) con un piccolo badge (play + durata). Doppio clic: visualizzatore con AVPlayer,
ripetizione automatica, barra di avanzamento, audio. Trascinamento ed export danno il file MP4.

### Anteprima durante la generazione
Le anteprime H3 hanno 24 canali e possono non decodificarsi. In quel caso resta la barra di avanzamento, senza errore.

## Errori e ritentativi

- `INTERNAL` o `UNAVAILABLE` prima di ricevere immagini: un solo ritentativo dopo 0,5 s, silenzioso.
- Errore dopo l'arrivo di frame: si codifica quanto ricevuto, il risultato e' marcato parziale e l'utente viene avvisato.
- Un solo frame da un modello video cloud: errore "modello non disponibile sul cloud", non un video di un frame.
- Annullamento con `stream.cancel()`. Se erano gia' arrivati frame non si salva nulla.

## Fuori dalla prima release

Wan, video-to-video, estensione clip, audio-to-video, upscale video, fps modificabile, ProRes, stima CU senza misure.
Le LoRA turbo di H3 (3 e 4 step) sono una possibile aggiunta successiva.

## Test

- Unit test: tabella dei frame validi, calcolo della durata, codifica MP4 con audio (frame sintetici), logica di ritentativo, caso "un solo frame", filtro catalogo cloud/locale.
- Prove manuali: generazione cloud per H3 (fl2va e ref2va), FastH3 e LTX-2.3; prova locale con almeno un modello H3.

## Appendice: risultati delle prove (gRPC, DT+ cloud)

- H3 i4x (fl2va e ref2va): video valido a 56 e 124 frame con 8 o 50 step. H3 q8p sul cloud: 1 frame, nessun audio.
- FastH3 Omni i4x: funziona solo con la specifica nell'`override`. Senza, 1 frame di rumore. Configurazione riuscita: 832x512, 124 frame, 8 step, sampler 16, shift 12, audio shift 3.
- LTX-2.3 22B q8p: video valido.
- Frame validi decodificati: H3 17k+5, LTX 8k+1.
- Frequenze: audio predefinito 24 kHz, LTX-2.3 48 kHz, H3 32 kHz; fps LTX 25, H3 24.

## Punti aperti per il piano

- Valore predefinito di End per TeaCache (50 nell'app DT, -1 nel client ComfyUI).
- Come si applicano i valori predefiniti per modello nel codice esistente.
- Se un'immagine di riferimento e' davvero obbligatoria per FastH3.
- Come il server elenca i file locali (verificare che l'elenco distingua cloud e locale).
- Aggiornare DrawThings-Swift da 2.2.0 a 2.3.0 (cataloghi DT+ aggiornati).
