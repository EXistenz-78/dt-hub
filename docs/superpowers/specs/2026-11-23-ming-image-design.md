# Ming-Image 0.1 Design in DT Hub e nel server gRPC custom: piano di porting

Stato: **analisi, nessun codice scritto** (23 nov 2026). Modello: <https://huggingface.co/inclusionAI/Ming-Image-0.1-Design> (MIT),
file ComfyUI in <https://huggingface.co/Comfy-Org/Ming-Image>. Codice di riferimento: <https://github.com/inclusionAI/Ming-Image>.

## 1. Cos'è

Text-to-image (e, secondo i workflow Comfy-Org, anche edit con immagine: da verificare) da 6B, specializzato in grafica, poster,
UI, testo nell'immagine e **uscita RGBA** (sfondo trasparente). Tre blocchi:

| Blocco | Cos'è | File Comfy-Org (bf16) |
|---|---|---|
| DiT | S3-DiT stile Z-Image: dim 3840, 30 layer + 2 refiner di rumore + 2 di contesto, 30 teste MHA (head_dim 128), SwiGLU 10240, qk-norm, patch 2, 16 canali latenti, RoPE assi [32,48,48] theta 256 | `diffusion_models/ming_image_0.1_design_bf16.safetensors` (12,3 GB) |
| Encoder di testo | LLM MoE Ling (BailingMoeV2: 20 layer, hidden 2048, 256 esperti top-8 + 1 condiviso) + connector Qwen2 (28 layer, hidden 1536) + proiezioni + (per l'edit) vision tower Qwen2.5-ViT | `text_encoders/ming_image_0.1_ling_mini_2.0_bf16.safetensors` (36,7 GB: `thinker` 297, `connector` 337, `vision` 390 tensori, proiezioni, e il tokenizer come tensore `tokenizer_json`) |
| VAE | AutoencoderKLQwenImage a **4 canali** (RGBA), z 16, fattore 8, scaling 8.0064, shift 0 | `vae/ming_image_vae_bf16.safetensors` (0,25 GB) |

I file sono in **formato ComfyUI** (nomi dei tensori originali, metadato `image_model: ming_image`), **non** in formato Draw Things: vanno
convertiti tutti e tre. Le versioni int8 ConvRot e w4a8 non servono: l'encoder si converte da bf16 a **i8x** (8-bit S di Draw Things).

## 2. Pipeline di inferenza (dal codice ufficiale; i punti marcati ? non sono verificati)

1. **Testo → sequenza LLM.** `<role>SYSTEM</role>你是一个友好的AI助手。\n\ndetailed thinking off` + eos, `<role>HUMAN</role>` + prompt + eos,
   `<role>ASSISTANT</role>`. Il prompt e' testo grezzo (un file JSON e' tokenizzato com'e', non interpretato). Nessun troncamento (?).
2. **Query token.** Dopo il prefisso si aggiungono `[start 157158] + 256 × [patch 157157] + [end 157159]`; i 256 embedding sono
   sostituiti da `query_tokens_dict.16x16` (256×2048). I 256 token usano il **gate immagine** del MoE. Il rotary vede questi token come
   una griglia finta `[1, 2, 512]` (una striscia 1×256), non 16×16.
3. **LLM.** Solo testo, attenzione causale, hidden state di tutti i layer. Vision tower non eseguita nel t2i.
4. **Flusso A (query).** Ultimo hidden state (dopo la norm finale) sulle 256 posizioni → `proj_in` 2048→1536 → connector Qwen2 **non
   causale** → `proj_out` 1536→2560 (nessuna normalizzazione).
5. **Flusso B (directvlm).** Hidden state dei layer **5, 12, 20** sulle posizioni del prefisso, concatenati (6144) → RMSNorm → Linear
   6144→3840.
6. **Condizionamento DiT.** Caption = `[256 query → cap_embedder (RMSNorm 2560 + Linear 2560→3840)] + [L_text directvlm già a 3840]`,
   azzerata e mascherata fino a multiplo di 32 (niente token di padding appreso). Posizioni caption: t = 1..L, h = w = 0; immagine: t = L+1,
   h/w = indice di griglia. Sequenza unificata `[immagine, caption]`.
7. **Campionamento.** 12 step, **CFG 1.0 = un solo passaggio** (con CFG > 1 il ramo negativo e' a zero). Timestep in ingresso al DiT =
   `1 − sigma` (×1000 dentro), uscita del DiT con **segno invertito**, Euler a flow matching. Shift dinamico: `mu` = 1.35 per ≥ 4096 token
   (1024 px e 2048 px), 0.63 a 512 px; `sigma' = e^mu / (e^mu + (1/sigma − 1))`; `sigma_min = 0` (? ultimo step). Il config dice shift 6.0
   ma il codice lo sovrascrive.
8. **Dimensioni.** Bucket 1024 o 2048 (consigliato 2048), rapporti da una tabella fissa, lati multipli di 32; poi ridimensionamento.
9. **VAE.** `z / 8.0064` → decoder → 4 canali in [−1, 1]. RGBA: lo sfondo trasparente si ottiene **solo con una frase all'inizio del prompt**
   (es. «RGBA, 4-channel, transparent background», «isolated subject, alpha matte, no background»; elenco completo nel README ufficiale).
10. **Edit** (da verificare): i workflow Comfy-Org hanno «Image Edit». Richiede la vision tower e il VAE encoder a 4 canali; il codice t2i
    non li usa. Fuori dal primo traguardo.

## 3. Cosa c'e' già nell'engine e cosa manca

Engine: fork `ianiv/draw-things-community`, nostra base `f4d03b02` (`~/Developer-krea2/fork-f4d03b02`, ramo `krea2-edit-f4d03b02`).
Nessun commit upstream su Ming (verificato il 23 nov sul ramo `atelier-engine`; la ricerca di codice GitHub non ha dato risultati).

| Pezzo | Riuso | Lavoro |
|---|---|---|
| DiT | `Models/ZImage.swift` (1603 righe): stessa famiglia | verificare nomi/forme dei tensori; differenze: input `1−sigma`, segno, padding a zero, ordine/posizioni caption, due flussi di caption (2560 e 3840) |
| LLM Ling MoE | `SwiftLLM/Models/GLM5_3.swift`, `DeepSeek4*.swift`, `Inkling2Small.swift` (MoE con router) | **nuovo**: router sigmoid + bias, gruppi (n_group 8, topk_group 4), scala 2.5, esperto condiviso, gate separato per i token immagine, attenzione con qk-norm e rotary parziale 0.5 a 3 sezioni [8,12,12] (theta 600000), densa al layer 0 |
| Tokenizer | `Libraries/Tokenizer` | verificare che legga il `tokenizer.json` Ling (vocab 157184); token speciali |
| Connector | `Models/Qwen3.swift`/Qwen2 | Qwen2 28 layer non causale: piccolo |
| Proiezioni | — | `proj_in`, `proj_out`, `proj_directvlm.{0,1}`, `query_tokens` |
| VAE | `QwenImage2_1VAE.swift`, `AutoencoderCausal3D.swift` | VAE Qwen-Image **a 4 canali** in uscita (e in ingresso per l'edit); da confrontare col VAE a 3 canali esistente |
| Scheduler | RF Euler, `RFSigmaGridDiscretization.swift`; gli scheduler per richiesta sono già nel nostro fork | `mu` come sopra |
| Cablaggio famiglia | commit `70c23cb` «Add MiniMax H3 Image (engine wiring)»: **30 file, ~1000 righe** | stessa lista: `ModelVersion`, `ModelZoo`, `ModelImporter`, `Converter`, `TextEncoder`, `UNetFixedEncoder`, `UNetProtocol`, `FirstStage`, `LocalImageGenerator`, `ModelPreloader`, `ComputeUnits`, `TeaCache`, LoRA importer/exporter, trainer… |
| Quantizzazione | `Apps/ModelQuantizer/Quantizer.swift` (regole per famiglia; Z-Image: q6p, embedder e `-linear_final-` interi) | regola Ming; per l'encoder **i8x** (modello `qwen_3_vl_32b_50_i8x` come riferimento); decidere cosa resta fp16 (gate/router, query token, norm) |

**Memoria** (da stimare): DiT 6B ≈ 12 GB fp16 o ≈ 6–7 GB 8-bit; LLM ≈ 36 GB bf16 per la parte testo+vision, ma gli **esperti** sono la quasi
totalita'. Con i8x ≈ 18 GB (il file int8 ConvRot era 19,5 GB). Il testo non serve piu' dopo l'encoding: va scaricato prima del DiT (come per
H3 Image). Su un Mac con poca RAM il vincolo e' l'encoder.

## 4. Lato DT Hub (dopo che il server funziona)

- `Packages/Sources/DTBridge`: tratti di famiglia (`FamilyTraits`: CFG 1.0 e nessun prompt negativo; passi 12; scheduler/sampler consigliato;
  dimensioni 1024/2048 multipli di 32), `ComputeUnitsEstimator` (+ test di riferimento).
- `HubCore/Prompts/EmbeddedPrompts.swift`: **Family prompt** `ming_image` con `negative: false`. Contenuti: prompt in testo libero, descrizioni
  dettagliate; elenco delle frasi RGBA; regole sul testo nell'immagine. Test `theNegativePromptFollowsTheFamilyPrompts`.
- Opzione/preset «trasparente (RGBA)» che antepone la frase; salvataggio dei risultati con alpha (PNG) e anteprima su scacchiera.
- `PluginKit`/Prompt Master: `excludedFamilies` come per H3 Image/Fibo 2.
- README: sezione famiglia + «Written for DT Hub x.y.z»; briefing; Obsidian; claude-mem (regole di CLAUDE.md).

## 5. Convertitore (traguardo 1) e Model Converter

Obiettivo: da `diffusion_models/…design_bf16`, `vae/…bf16`, `text_encoders/…ling_mini_2.0_bf16` a:
`ming_image_0.1_design_f16.ckpt` (+ `_i8x`/q6p), `ming_image_vae_f16.ckpt`, `ming_image_ling_mini_2.0_i8x.ckpt` (nome da decidere) e la voce in
`custom.json` (`version: ming_image`, `default_scale` 32, `prefix`, `text_encoder`, `autoencoder`, `noise_discretization`/RF come H3).

1. Nel fork: `ModelVersion.mingImage` e `Converter.swift` con i flag `--ming-text-encoder` e `--ming-vae` (sul modello di
   `--fibo2-text-encoder` e `--h3-image-vae`); import del DiT in `ModelImporter` riusando la mappa Z-Image; regola in `Quantizer.swift`.
2. Verifica **per tensore**: forma e conteggio contro l'header safetensors (519 tensori DiT, 1037 encoder, 194 VAE), nessun tensore perso o
   inventato; confronto numerico delle uscite con la pipeline PyTorch di riferimento quando possibile (richiede una macchina con 80 GB: vedi §7).
3. In `Fibo Converter` (`/Users/existenz/Software developement/Fibo Converter`, app «Model Converter» 1.2): nuovo tab «Ming-Image»
   sul modello di `H3Conversion.swift` (`RequiredFile` con dimensioni esatte dei tre file Comfy-Org, passi convertitore → quantizzatore →
   `custom.json`), con licenza MIT mostrata. **Solo se Ming funziona in DT Hub** (richiesta dell'utente del 23 nov).

**Verificato il 23 nov sul file reale:** il DiT ha 519 tensori in 41 famiglie di nomi, e sono **gli stessi di Z-Image** (`all_x_embedder.2-1`,
`all_final_layer.2-1`, `cap_embedder.0/1`, `t_embedder.mlp.0/2`, `noise_refiner.N`, `context_refiner.N`, `layers.N` con `attention.to_q/k/v`,
`to_out.0`, `norm_q/k`, `feed_forward.w1/w2/w3`, `attention_norm1/2`, `ffn_norm1/2`, `adaLN_modulation`), senza `x_pad_token` e `cap_pad_token`
(`ModelImporter.swift` riga ~2220 li legge solo se presenti). Quindi **l'import del DiT è quasi gratis**: serve solo distinguere Ming da Z-Image
(`ModelImporter.swift` riga ~474 assegna `.zImage` ai file con quei nomi) con il metadato `image_model` o l'assenza dei pad token, e dare a Ming una
propria `ModelVersion` perché il forward differisce (§2). Il lavoro vero resta encoder, VAE a 4 canali e cablaggio.

## 6. Ordine di lavoro

1. **Convertitore e verifica dei tensori** (nessun rischio per il resto; si può provare con i file già scaricati).
2. Encoder: tokenizer + LLM MoE + connector + proiezioni, confrontato con la pipeline di riferimento su prompt corti (le 256 uscite).
3. DiT (da ZImage) con tutti i dettagli del §2; prima immagine a 1024.
4. VAE 4 canali e RGBA; scheduler `mu`.
5. Cablaggio della famiglia (lista del §3), patch in `Server/` (nuova versione di `krea2-edit.patch` o patch separata), test.
6. DT Hub: tratti, prompt, UI RGBA. Poi Model Converter. Poi, a parte, edit con immagine e Design-Layer.

## 6b. Riferimento numerico dell'encoder (fatto il 23 nov)

`Tools/ming-reference/ref_encoder.py` (locale, fuori da git): PyTorch float32 scritto dal codice ufficiale (non eseguito), legge l'encoder
bf16 Comfy un layer per volta (RAM bassa, ~40 s per prompt su CPU). Uscite salvate in `~/Developer-krea2/ming-ref/`
(`ref_apple.safetensors`, `ref_hello.safetensors`): token, posizioni 3D, `hidden_5/12/20`, `query_embeds` [256, 2560], `directvlm` [L, 3840],
instradamento del layer 1. Estratto anche `tokenizer.json` dal tensore `tokenizer_json` del file.

Verifiche: (1) `gate_up_proj` = `[gate; up]` e `down_proj` coincidono bit a bit con i pesi ufficiali separati (esperto 0, layer 1);
(2) modalità `chat` (domanda «What is the capital of France?» senza token immagine): primo token previsto con `lm_head` = **«Paris»**
(logit 19,66 contro 14,86 di «The»): attenzione, rotary 3D sul testo, routing a gruppi, esperti, esperto condiviso, layer 0 denso e norma sono giusti;
(3) nessun NaN. **Non verificato:** il percorso immagine (gate immagine sui 256 token, posizioni della striscia, query token) segue il codice ma
non ha un controllo indipendente.

Fatti da portare in Swift:
- eos = `<|role_end|>` (156895); nessun BOS; `<role>`/`</role>` sono token speciali (157151/157152); `<image>` 157158, `<imagePatch>` 157157,
  `</image>` 157159; testo = `<role>SYSTEM</role>你是一个友好的AI助手。\n\ndetailed thinking off` + eos + `<role>HUMAN</role>` + prompt + eos +
  `<role>ASSISTANT</role>`, poi `<image>` + 256 × `<imagePatch>` + `</image>`.
- `hidden_states[k]` = uscita di k layer (0 = embedding); l'ultimo (20) è **dopo** la norma finale. `directvlm` usa 5, 12, 20 sulle sole posizioni
  del prefisso (33 token nel prompt di prova), non su `<image>` né sui query token.
- Posizioni 3D: prefisso e `<image>` 0..n; i 256 token hanno t = h = n, w = n − 127 + k; `</image>` = n + 1 su tutti gli assi
  (w dei query token può essere negativa se n < 127). Sezioni rotary dopo `video_rope`: 24 dim alternate righe 1/2, 8 riga 0, 24 alternate, 8 riga 0
  (sulle 64 dim ruotate, `rotate_half`, theta 600000, resto della testa non ruotato).
- **Attivazioni enormi:** `hidden_5` arriva a ±14.800 (e `hidden_12` a ±14.900): i residui vanno tenuti in **FP32** (come fa `Qwen3.swift`), altrimenti
  la norma in FP16 va in overflow.
- `query_embeds`: media 0,56, deviazione 25,9, massimo 1.691; `directvlm`: deviazione ≈ 1.
- Connector: Qwen2, tutti i layer bidirezionali, posizioni 0..255, rotate_half su 128 dim, theta 1e6, norma finale `connector.norm`.

## 6c. Stato del porting nel fork (23 nov sera, ramo `ming-image` di `~/Developer-krea2/fork-f4d03b02`, non committato)

Fatto e verificato contro PyTorch:
- **DiT:** `ModelConverter` lo riconosce (`ming_image`, Z-Image senza pad token) e lo converte; `QuantI8x` lo porta a 8-bit (6,18 GB). Mai eseguito in generazione.
- **Encoder:** `MingText.swift` (grafo Ling per layer, routing a gruppi sull'host con `MoERouting` `preselected`, esperto condiviso, connector
  Qwen2, `proj_in/out`, directvlm). Convertitore `--ming-text-encoder` (f16, 34,6 GB, tokenizer a parte) e `QuantI8x --text-encoder` (i8x, 17,7 GB: embedding,
  query token, router e proiezioni restano f16, esperti 3D in i8x). Test `MingEncoderTest` layer per layer. f16: errore relativo 0,03% al layer 1,
  1,5% al layer 18, 5,6% dopo la norma finale, connector da solo 0,6%, `query_embeds` 6,3%, directvlm 0,55%. i8x: 17,6% sull'uscita finale e 17,1% sui
  `query_embeds` (un'esecuzione bf16, la precisione ufficiale, dista dall'fp32 il 14% e il 12%).
- **VAE:** `--ming-vae` con i grafi Wan esistenti a 4 canali (`MingVAEEncoder/Decoder`). Per profondità 1 il motore legge `conv_in`, `conv_out` e i due conv dei blocchi
  residui prendendo solo l'ultimo tap temporale (FirstStage.swift): lo stesso lettore serve nel runtime. Test `MingVAETest`: latenti vs PyTorch 0,27%; round trip
  su foto con alpha circolare: 33–35 dB sull'RGB opaco, 32,5 dB sull'alpha. I `time_conv` (8 tensori) non servono alle immagini.
- File prodotti in `~/Developer-krea2/ming-out/`: `ming_image_0.1_design_i8x.ckpt`, `ming_image_ling_mini_2.0_i8x.ckpt` (+ `_tokenizer.json`), `ming_image_vae_f16.ckpt`.
  Gli f16 intermedi sono stati cancellati.

**DiT (aggiornamento 23 nov, notte).** `MingImageFixed` in `ZImage.swift` (caption = query via `cap_embedder` + directvlm già a 3840, senza padding: equivale al padding
zero-mascherato se la posizione temporale dell'immagine usa la lunghezza arrotondata a 32, parametro `imageTimePosition` di `ZImageRotaryPositionEmbedding`).
Test `MingDiTTest` (un passo, 256 px, prompt «mela») contro `Tools/ming-reference/ref_dit.py`: `cap_embedder` 0,03%, caption raffinato 0,24%; con 4 layer 0,25%,
12 layer 0,29%, 21 layer 0,5%, 24 layer 0,8%, 27 layer 3,5%, 30 layer 19% (i8x) e 14% (f16 non quantizzato). Un passo in **bf16** del riferimento dista il 24% dall'fp32:
l'errore dei layer finali (attivazioni fino a ±10.800 e uscite FFN fino a 640.000) è rumore di precisione, non un errore di porting.
Trovato e corretto un difetto del quantizzatore: la conversione CPU `Tensor<Float16>(from: Tensor<BFloat16>)` restituisce zeri; `QuantI8x` ora passa da Float
(il DiT è scritto in bf16 dall'importer). **Su questo Mac il percorso bf16 del motore non compila** (`bfloat4` assente nel compilatore Metal) e il lettore non decodifica
i8x in bf16: il DiT quantizzato gira in f16 (`isBF16: false`, attenzione `.scale1`). Se l'immagine finale mostrerà artefatti, i fattori di scala per layer
(`activationQkScaling`, ecc.) vanno calcolati per Ming, come per gli altri modelli Z-Image.

Da fare: tokenizer nel server,
`TextEncoder.swift` (esecuzione per layer con routing sull'host), `FirstStage` con VAE a 4 canali per `.mingImage` (alpha come per `qwenImage2_1`), scheduler `mu`, `custom.json`,
poi DT Hub e Model Converter. Per `Package.swift` del fork: i target `MingEncoderTest` e `MingVAETest` sono locali.

## 7. Rischi e punti aperti

- **Verifica numerica**: la pipeline ufficiale chiede una GPU CUDA da 80 GB; su Mac non l'abbiamo provata. Senza riferimento si controlla
  solo la plausibilità visiva; valutare MPS/CPU per i soli passaggi piccoli (encoder sui 256 token) o un runner remoto.
- **Non letti nel codice ufficiale**: `tokenization_bailing.py`, `qwen2_5_vit.py`, diffusers `FlowMatchEulerDiscreteScheduler` (formula esatta di
  `mu` e dell'ultimo step), applicazione del rotary parziale nell'LLM, significato esatto di `attention_mask` float nel connector, nomi dei
  tensori dentro il file di encoder Comfy (`thinker.layers.*` ecc. vs ufficiale `model.model.*`).
- **Esperti MoE**: forma e layout dei pesi (256 esperti per layer) nel file Comfy; costo di memoria e velocità del routing su Metal.
- **RGBA**: il VAE a 4 canali impone di cambiare la pipeline di salvataggio/visualizzazione di DT Hub (alpha).
- **ConvRot**: nel binario del server c'è già una normalizzazione ConvRot (non usata dal nostro piano); non serve se si parte da bf16.
- **Licenze**: Ming e' MIT; il server custom resta GPL-3.0 (stesso trattamento degli altri patch).

## 6d. Edit con immagine di riferimento (24 novembre)

Funziona nel motore (fork, ramo `ming-image`, non ancora in commit) e nel CLI: `draw-things-cli generate … --image apple2.png --strength 1` con `modifier: kontext` nella specifica del modello e `clip_encoder: ming_image_ling_mini_2.0_vision_f16.ckpt`. Prova: «Change the apple to a blue apple, keep everything else the same» → mela blu, tavolo e luce identici (512 px, 12 passi, 3 s/passo in debug).

Percorso (letto dal codice ufficiale `pipeline.py`/`transformer.py`/`modeling_bailingmm2.py`):
- **Testo:** il turno HUMAN si apre con `<image>` + N × `<imagePatch>` + `</image>\n` (N = token del vision tower dopo il merge 2×2, immagine a ~451 584 px, multipli di 28); le N righe portano le feature della torre (Qwen2.5-ViT 32 layer, in FP32: in f16 va in NaN) dopo `linear_proj` e normalizzazione L2. Le 256 query restano in fondo. Posizioni rotary a blocchi (un blocco per immagine, uno per le query). Il DirectVLM vede l'intero prefisso (immagine inclusa), quindi la didascalia diventa 256 + prefisso.
- **DiT:** il riferimento è un latente pulito (VAE a 4 canali, scala 8,0064) della stessa griglia del target, portato come frame aggiuntivo dopo il rumore, stesso `x_embedder`, stessa modulazione del tempo, posizione temporale `cap_padded + 1 + frame`; si legge solo l'uscita dei token dell'immagine. Riferimento ritagliato al rapporto del target (come Krea 2).
- **Verifica numerica:** `MingDiTTest` con `MING_REFS=1` contro `ref_dit.py MING_REFS=1`: 4 layer, errore 0,25 % (uguale al caso senza riferimento).
- **Trappole:** `UNetProtocol` indicizza le condizioni dalla coda (`count - 131`, `count - 130`, `count - 129`): con i riferimenti in coda vanno spostati di `referenceImageCount` (compile, chiamata, `UNetExtractConditions`, costruzione del grafo).
- **DT Hub:** `ming_image` esce da `withoutMoodboard`; il Family prompt ha la nota sull'edit; test dei pacchetti ok (contatori delle famiglie 19→20).
- Da fare: più riferimenti (Moodboard) non provati; Design-Layer; alfa nel riferimento ignorata (solo RGB).

## 6e. Trasparenza (RGBA): causa trovata (24 novembre)

Non era il decoder né la pipeline: a **512 px** l'alfa resta opaco (min 191-244), a **1024 px** con «RGBA, 4-channel, transparent background. A red apple with a green leaf» esce un ritaglio pulito (alfa 0-255, 74 % dei pixel sotto 128; mela e foglia su sfondo trasparente). Il modello è addestrato su 1024/2048 (i bucket di `infer.py`). Il Family prompt `ming_image` lo dice. Il percorso di decodifica (`FirstStage`: alfa = (a+1)/2) era già giusto.

## 6f. Immagine nera sopra 1216 px: overflow FP16 (24 novembre)

**Sintomo:** in DT Hub, da 1280×1280 in su, l'anteprima resta nera e la generazione finisce senza immagini; fino a 1216 funziona.
**Causa:** overflow FP16 nel DiT (NaN dal primo passo; `LocalImageGenerator` scarta il risultato con `isNaN`). Dipende dalla lunghezza
totale della sequenza (token dell'immagine + testo), non solo dalla risoluzione: a 1280 un prompt corto passa, il JSON del Family prompt v2
(~740 token, ~1050 con modello di chat e 256 query) no. La voce di `custom.json` aveva `mmdit` senza scale delle attivazioni.
**Correzione:** in `custom.json` la voce Ming usa le stesse scale di Z-Image Base in ModelZoo (34 blocchi: i primi 2, i refiner, `qk` 1 e
`proj` 2, `ffn_proj_up` 1 e `ffn` 2; gli altri `qk` 32, `proj` 1, `ffn_proj_up` 32, `ffn` 1). Provata col server Release dell'app:
prompt lungo a 1280 ok, poster a 2048 ok. Aggiornati `/Volumes/LLM-VLM 1/Models/custom.json` (copia `custom.json.bak-ming-scaling`)
e la cartella di prova; `/Volumes/LLM-VLM/Models` non era montato. Chi converte Ming (Fibo Converter) deve scrivere queste scale.

## 6g. LoRA di Z-Image su Ming (24 novembre)

Il DiT di Ming è il grafo di Z-Image con gli stessi nomi dei pesi, quindi i LoRA di Z-Image si applicano così come sono. La regola
«un LoRA va solo con la sua famiglia» resta; si aggiunge una tabella di famiglie che girano i LoRA di un'altra famiglia.
- **Server (fork):** `LoRAZoo.versionForModel(_:runningWith:)` restituisce `.mingImage` per un LoRA `z_image` con un modello Ming;
  la usano tutti i filtri dei LoRA (`LocalImageGenerator`, `ImageConverter`, `ModelPreloader`, `ImageGeneratorUtils`). La parte del
  LoRA per il text encoder (Qwen3) non si usa: l'encoder di Ming non prende LoRA. Nemmeno il blocco fisso (`MingImageFixed`: refiner
  del contesto) prende LoRA. `LoRAZImage` ha `referenceCount` come `ZImage`, perché con il DiT i8x i LoRA girano a parte anche in edit.
- **DT Hub:** `HubKit/Catalog/LoRAFamilies.swift` (`ming_image` → `z_image`) usato da `ModelCatalog.loras(for:)` e `status(of:family:)`
  (scheda LoRA, invio con RUN, `EditModel`) e dall'agente MCP (`list_loras`/`set_model` vedono le famiglie su cui un LoRA gira).
  Per famiglia, non per file: un LoRA Z-Image aggiunto dopo vale subito anche per Ming. Test: `LoRAFamiliesTests`.
- **Prova:** «A lighthouse on a rocky cliff at dusk» a 1024, seed 11, con e senza «ZIT Darkness-Dream» (peso 1): stessa scena, stile
  del LoRA applicato. Edit con LoRA: vedi sotto.
