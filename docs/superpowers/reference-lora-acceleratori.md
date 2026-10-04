# Riferimento — Impostazioni di Draw Things con LoRA acceleratore e senza

Data: 4 ottobre 2026 · Fonte: la lista delle configurazioni ufficiali nella cache di Draw Things (`Caches/net/configs.json`, 57 voci). Solo per consultazione: DT Hub **non** usa queste voci (le scarta, vedi `specs/2026-10-04-recommended-settings-design.md` §2).

Ogni riga confronta la voce «con LoRA» con quella dello stesso modello senza LoRA; `a → **b**` vuol dire che il valore cambia.

| Con LoRA | Base | LoRA (peso) | Step | CFG | Sampler | Shift |
|---|---|---|---|---|---|---|
| Qwen Image 2512 with Lightning 4-Step v1.0 | Qwen Image 2512 | qwen_image_2512_lightning_4_step_v1.0_lora_f16 (1) | 30 → **4** | 4 → **1** | UniPC Trailing | 2 → **3** |
| Qwen Image Edit 2511 with Lightning 4-Step v1.0 | Qwen Image Edit 2511 | qwen_image_edit_2511_lightning_4_step_v1.0_lora_f16 (1) | 30 → **4** | 4 → **1** | UniPC Trailing | 2 → **3** |
| FLUX.2 [dev] with Turbo | FLUX.2 [dev] | flux_2_dev_turbo_lora_f16 (1) | 28 → **4** | 4.5 | DDIM Trailing | 1 → **3** |
| Wan v2.2 T2V 14B with Lightning v1.1 | Wan v2.2 T2V 14B | wan_v2.2_a14b_hne_t2v_lightning_v1.1_lora_f16 (1), wan_v2.2_a14b_lne_t2v_lightning_v1.1_lora_f16 (1) | 30 → **4** | 4 → **1** | UniPC Trailing | 8 → **5** |
| Wan v2.2 I2V 14B with Lightning v1.0 | Wan v2.2 I2V 14B | wan_v2.2_a14b_hne_i2v_lightning_v1.0_lora_f16 (1), wan_v2.2_a14b_lne_i2v_lightning_v1.0_lora_f16 (1) | 30 → **4** | 3.5 → **1** | UniPC Trailing | 5 |
| Qwen Image 1.0 with Lightning 4-Step v2.0 | Qwen Image 1.0 | qwen_image_1.0_lightning_4_step_v2.0_lora_f16 (1) | 30 → **4** | 4 → **1** | UniPC Trailing | 2 → **3** |
| Qwen Image 1.0 with Lightning 8-Step v2.0 | Qwen Image 1.0 | qwen_image_1.0_lightning_8_step_v2.0_lora_f16 (1) | 30 → **8** | 4 → **1** | UniPC Trailing | 2 → **3** |
| Qwen Image Edit 2509 with Lightning 4-Step v1.0 | Qwen Image Edit 2509 | qwen_image_edit_2509_lightning_4_step_v1.0_lora_f16 (1) | 30 → **4** | 4 → **1** | UniPC Trailing | 2 → **3** |
| Qwen Image Edit 2509 with Lightning 8-Step v1.0 | Qwen Image Edit 2509 | qwen_image_edit_2509_lightning_8_step_v1.0_lora_f16 (1) | 30 → **8** | 4 → **1** | UniPC Trailing | 2 → **3** |
| Qwen Image Edit 1.0 with Lightning 4-Step v1.0 | Qwen Image Edit 1.0 | qwen_image_edit_1.0_lightning_4_step_v1.0_lora_f16 (1) | 30 → **4** | 4 → **1** | UniPC Trailing | 2 → **3** |
| Qwen Image Edit 1.0 with Lightning 8-Step v1.0 | Qwen Image Edit 1.0 | qwen_image_edit_1.0_lightning_8_step_v1.0_lora_f16 (1) | 30 → **8** | 4 → **1** | UniPC Trailing | 2 → **3** |

## Cosa cambia, in sintesi

- **Step:** sempre molti di meno: 30 → 4 (Lightning 4-step, Turbo) o 30 → 8 (Lightning 8-step); FLUX.2 [dev] 28 → 4.
- **CFG:** scende a 1 su tutti i Qwen e i Wan con Lightning (4 → 1; Wan I2V 3,5 → 1). **Con FLUX.2 [dev] Turbo resta 4,5** (il modello usa la guidance incorporata).
- **Sampler:** non cambia mai nella lista (UniPC Trailing per Qwen e Wan, DDIM Trailing per FLUX.2).
- **Shift:** sale (2 → 3 sui Qwen, 1 → 3 su FLUX.2 [dev], 8 → 5 sul Wan T2V) o resta (Wan I2V 5). L'interruttore «Shift in base alla risoluzione» è **spento** nelle voci Qwen Lightning e FLUX.2 Turbo (nei modelli base è acceso o non indicato) e non è indicato nei Wan.
- **LoRA:** sempre il peso 1; i Wan 14B ne vogliono due (rumore alto e basso).
- Nessuna voce con LoRA per Klein, Z-Image, ERNIE, Krea, Ideogram, HiDream, FLUX.1 e SD/SDXL (i loro modelli «Turbo»/«fast» sono modelli a parte e hanno la loro voce senza LoRA).
