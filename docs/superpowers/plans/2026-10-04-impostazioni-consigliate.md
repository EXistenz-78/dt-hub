# Impostazioni consigliate per modello — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Quando l'utente sceglie un modello dal menu dell'header, la Generazione prende i valori consigliati da Draw Things per quel modello: **passi, CFG, sampler, shift** (e l'interruttore «Shift in base alla risoluzione» dove la lista lo dice). I valori stanno in una tabella inclusa nell'app, ricavata dalla lista ufficiale di Draw Things, fuori dal menu Preset. Un modello che la tabella non conosce lascia i valori com'erano.

**Architecture:**
- **Script** `Scripts/make-recommended-settings.py`: converte la lista di Draw Things (la cache dell'app Draw Things sul Mac) in `App/Resources/RecommendedSettings.json`.
- **HubKit**: `RecommendedValues`, `RecommendedSettings` (lettura permissiva del JSON, ricerca per file senza quantizzazione e poi per famiglia) e `GenerationParameters.applying(_:)`.
- **HubCore**: `ModelSelection.choose(_:applyingTo:from:in:)` (seleziona, e se il modello cambia e la tabella lo conosce restituisce i parametri con i valori consigliati).
- **L'app**: `GenerationController.chooseModel` e il menu dell'header lo usano; nessun'altra via di selezione cambia.

**Tech Stack:** Python 3 (script), Swift 6, SwiftUI, macOS 26, Xcode 27, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-04-recommended-settings-design.md`.

## Global Constraints

- **Repository e dipendenze:** radice `/Users/existenz/Software developement/DT Hub` (percorsi tra virgolette); branch `recommended-settings` da `main`; macOS 26, Swift 6, Xcode 27; solo DTBridge importa DrawThings-Swift, solo LLMBridge importa MLX.
- **Solo quattro valori (più l'interruttore):** `steps`, `guidanceScale`, `sampler`, `shift` e `resolutionDependentShift`. Non si toccano dimensioni, seed, batch, LoRA, card Avanzate, prompt, negativo.
- **Quando:** solo la scelta di un modello **diverso** dal menu dell'header. Mai all'avvio, né con un preset che nomina un modello, né in una pipeline, né con «Riprendi parametri», né dall'editor JSON, né da un plug-in. Scegliere lo stesso modello non tocca niente. Un modello senza voce (né per file né per famiglia) lascia i valori. Nessun avviso e nessun annulla.
- **La tabella:** chiave = nome del file senza quantizzazione e senza estensione (si tolgono dalla fine `_f16`, `_f32`, `_bf16`, `_q<N>p`, `_i8x`, `_svd`); ricerca per file, poi per famiglia (la `version` del catalogo del server). Le voci con LoRA della lista di Draw Things si scartano. `shift` o `resolutionDependentShift` che la lista non dà si lasciano fuori: la voce senza `shift` lascia lo shift del tab. Il campionatore è il numero di Draw Things (lo stesso di `Sampler`); un numero sconosciuto scarta la voce. I valori applicati passano da `clamped()`.
- **Nessun download e nessuna lettura della cache di Draw Things a runtime:** lo script la legge sul Mac dello sviluppatore, l'app legge solo `RecommendedSettings.json` incluso.
- **Commit:** indentazione a 2 spazi (Swift) e 4 (Python); ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Blocchi `diff`:** modifiche ai file già esistenti, da salvare in un file e applicare dalla radice con `git apply --whitespace=nowarn <file>`; i blocchi dei file nuovi si salvano così come sono.
- **L'app di prova** condivide le preferenze con quella dell'utente (i file no) e i processi hanno lo stesso identificatore: **se l'app dell'utente è aperta non pilotare le finestre** (agirebbero sulla sua); il Task 5 lo dice.
- **Fuori:** le voci con LoRA; un avviso o un annulla; valori per altro che i cinque campi; aggiornare la tabella da Internet; preset di default modificabili dall'utente.

## Review Focus

- **Un file della tabella rovinato o vecchio non fa danni:** JSON non valido, voce senza `steps`, campionatore sconosciuto, famiglia assente (test `damagedEntriesAreLeftOutAndTheRestIsKept`, Task 2).
- **Non si sovrascrivono i valori scelti da un preset:** un preset che nomina un modello lo seleziona con `select`, non con `choose` (test `selectingWithoutChoosingKeepsTheValues`, Task 3; **che le altre vie di selezione non passino da `chooseModel` non ha test automatici**: il revisore lo verifichi cercando ogni uso di `selection.select(` in `App/`).
- **Lo stesso modello due volte** non cambia niente (test `choosingTheSameModelAgainChangesNothing`).
- **La famiglia di un modello sconosciuto alla tabella** viene dal catalogo del server (`CatalogModel.family`); un catalogo non ancora caricato dà famiglia nil e nessun ripiego.
- **L'app non ha test del menu dell'header:** la prova dal vivo (Task 5) cambia modello davvero.

---

### Task 1: Lo script e la tabella

**Files:**
- Create: `App/Resources/RecommendedSettings.json`, `Scripts/make-recommended-settings.py`, `Scripts/test_make_recommended_settings.py`

**Interfaces:**
- Produces: `Scripts/make-recommended-settings.py [CONFIGS_JSON] [OUT_JSON]` (funzioni `model_key(file)`, `values(configuration)`, `convert(entries)`); `App/Resources/RecommendedSettings.json`: `{"models": {chiave: {steps, guidanceScale, sampler, shift?, resolutionDependentShift?}}, "families": {versione: {…}}}` (46 modelli e 18 famiglie dalla lista di Draw Things del 4 ottobre 2026).

- [ ] **Step 1: Creare il branch e scrivere il test**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git switch main && git switch -c recommended-settings
```

**`Scripts/test_make_recommended_settings.py`** (file nuovo o riscritto per intero):

```python
import importlib.util
import os
import unittest

spec = importlib.util.spec_from_file_location(
    "make_recommended_settings", os.path.join(os.path.dirname(os.path.abspath(__file__)), "make-recommended-settings.py"))
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


def entry(model, name="x", version=None, **configuration):
    result = {"name": name, "configuration": {"model": model, **configuration}}
    if version:
        result["version"] = version
    return result


class MakeRecommendedSettingsTests(unittest.TestCase):
    def test_the_key_drops_the_quantization_and_the_extension(self):
        self.assertEqual(tool.model_key("flux_2_klein_9b_f16.ckpt"), "flux_2_klein_9b")
        self.assertEqual(tool.model_key("flux_2_klein_9b_q6p.ckpt"), "flux_2_klein_9b")
        self.assertEqual(tool.model_key("wan_v2.2_a14b_hne_t2v_q6p_svd.ckpt"), "wan_v2.2_a14b_hne_t2v")
        self.assertEqual(tool.model_key("qwen_image_2.1_q8p.ckpt"), "qwen_image_2.1")
        self.assertEqual(tool.model_key("z_image_turbo_1.0_f16.ckpt"), "z_image_turbo_1.0")

    def test_an_entry_gives_its_four_values_and_the_family_it_names(self):
        table = tool.convert([entry("a_q6p.ckpt", version="fam", steps=4, guidanceScale=1, sampler=16, shift=3, resolutionDependentShift=False)])
        expected = {"steps": 4, "guidanceScale": 1, "sampler": 16, "shift": 3, "resolutionDependentShift": False}
        self.assertEqual(table["models"], {"a": expected})
        self.assertEqual(table["families"], {"fam": expected})

    def test_entries_with_loras_are_left_out(self):
        table = tool.convert([
            entry("a_q6p.ckpt", steps=4, guidanceScale=1, sampler=17, shift=3, loras=[{"file": "x_lora_f16.ckpt"}]),
            entry("a_q6p.ckpt", steps=30, guidanceScale=4, sampler=17, shift=2, loras=[]),
        ])
        self.assertEqual(table["models"]["a"]["steps"], 30)

    def test_the_first_entry_of_a_key_wins_and_a_missing_shift_is_left_out(self):
        table = tool.convert([
            entry("a_q6p.ckpt", steps=30, guidanceScale=4, sampler=17, resolutionDependentShift=True),
            entry("a_f16.ckpt", steps=8, guidanceScale=1, sampler=10, shift=3),
        ])
        self.assertEqual(table["models"], {"a": {"steps": 30, "guidanceScale": 4, "sampler": 17, "resolutionDependentShift": True}})

    def test_entries_without_the_basic_values_or_a_model_are_left_out(self):
        table = tool.convert([entry("a.ckpt", steps=4), {"name": "no configuration"}, {"configuration": {"steps": 1}}, entry("b.ckpt", steps="x", guidanceScale=1, sampler=1)])
        self.assertEqual(table, {"models": {}, "families": {}})


if __name__ == "__main__":
    unittest.main()
```

Run: `cd "/Users/existenz/Software developement/DT Hub" && python3 -m unittest Scripts/test_make_recommended_settings.py 2>&1 | tail -3`
Expected: un errore perché `Scripts/make-recommended-settings.py` non esiste (`FileNotFoundError`).

- [ ] **Step 2: Implementare lo script e salvare la tabella**

**`App/Resources/RecommendedSettings.json`** (file nuovo o riscritto per intero):

```json
{
  "families": {
    "cosmos2.5_2b": {
      "guidanceScale": 4,
      "resolutionDependentShift": true,
      "sampler": 16,
      "steps": 30
    },
    "ernie_image": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 17,
      "shift": 4,
      "steps": 8
    },
    "flux1": {
      "guidanceScale": 4.5,
      "resolutionDependentShift": true,
      "sampler": 10,
      "shift": 1,
      "steps": 28
    },
    "flux2": {
      "guidanceScale": 4.5,
      "resolutionDependentShift": true,
      "sampler": 16,
      "shift": 1,
      "steps": 28
    },
    "flux2_4b": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 16,
      "shift": 3,
      "steps": 4
    },
    "flux2_9b": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 16,
      "shift": 3,
      "steps": 4
    },
    "hidream_i1": {
      "guidanceScale": 5,
      "resolutionDependentShift": false,
      "sampler": 10,
      "shift": 3,
      "steps": 40
    },
    "hunyuan_video": {
      "guidanceScale": 6,
      "resolutionDependentShift": false,
      "sampler": 16,
      "shift": 7,
      "steps": 30
    },
    "ideogram_4": {
      "guidanceScale": 7,
      "resolutionDependentShift": false,
      "sampler": 10,
      "shift": 1,
      "steps": 48
    },
    "krea_2": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 10,
      "shift": 3,
      "steps": 8
    },
    "ltx2": {
      "guidanceScale": 5,
      "sampler": 17,
      "shift": 5,
      "steps": 30
    },
    "minimax_h3": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 16,
      "shift": 12,
      "steps": 50
    },
    "qwen_image": {
      "guidanceScale": 4,
      "sampler": 17,
      "shift": 2,
      "steps": 30
    },
    "qwen_image_2.1": {
      "guidanceScale": 1,
      "resolutionDependentShift": true,
      "sampler": 16,
      "shift": 1,
      "steps": 40
    },
    "sdxl_base_v0.9": {
      "guidanceScale": 5,
      "resolutionDependentShift": false,
      "sampler": 12,
      "shift": 1,
      "steps": 16
    },
    "v1": {
      "guidanceScale": 5,
      "resolutionDependentShift": false,
      "sampler": 12,
      "shift": 1,
      "steps": 16
    },
    "wan_v2.1_14b": {
      "guidanceScale": 5,
      "sampler": 10,
      "shift": 5,
      "steps": 30
    },
    "z_image": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 17,
      "shift": 3,
      "steps": 8
    }
  },
  "models": {
    "anima_aesthetic_1.1": {
      "guidanceScale": 4,
      "resolutionDependentShift": true,
      "sampler": 16,
      "steps": 30
    },
    "anima_base_1.0": {
      "guidanceScale": 4,
      "resolutionDependentShift": true,
      "sampler": 16,
      "steps": 30
    },
    "ernie_image": {
      "guidanceScale": 4,
      "resolutionDependentShift": true,
      "sampler": 17,
      "steps": 30
    },
    "ernie_image_turbo": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 17,
      "shift": 4,
      "steps": 8
    },
    "flux_1_dev": {
      "guidanceScale": 4.5,
      "resolutionDependentShift": true,
      "sampler": 10,
      "shift": 1,
      "steps": 28
    },
    "flux_1_fill_dev": {
      "guidanceScale": 50,
      "resolutionDependentShift": true,
      "sampler": 10,
      "shift": 1,
      "steps": 28
    },
    "flux_1_schnell": {
      "guidanceScale": 4.5,
      "resolutionDependentShift": false,
      "sampler": 10,
      "shift": 1,
      "steps": 4
    },
    "flux_2_dev": {
      "guidanceScale": 4.5,
      "resolutionDependentShift": true,
      "sampler": 16,
      "shift": 1,
      "steps": 28
    },
    "flux_2_klein_4b": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 16,
      "shift": 3,
      "steps": 4
    },
    "flux_2_klein_9b": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 16,
      "shift": 3,
      "steps": 4
    },
    "flux_2_klein_9b_kv": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 16,
      "shift": 3,
      "steps": 4
    },
    "flux_2_klein_base_4b": {
      "guidanceScale": 4,
      "resolutionDependentShift": true,
      "sampler": 16,
      "steps": 30
    },
    "flux_2_klein_base_9b": {
      "guidanceScale": 4,
      "resolutionDependentShift": true,
      "sampler": 16,
      "steps": 30
    },
    "hidream_i1_dev": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 10,
      "shift": 6,
      "steps": 28
    },
    "hidream_i1_fast": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 10,
      "shift": 3,
      "steps": 16
    },
    "hidream_i1_full": {
      "guidanceScale": 5,
      "resolutionDependentShift": false,
      "sampler": 10,
      "shift": 3,
      "steps": 40
    },
    "hunyuan_video_t2v_720p": {
      "guidanceScale": 6,
      "resolutionDependentShift": false,
      "sampler": 16,
      "shift": 7,
      "steps": 30
    },
    "ideogram_4": {
      "guidanceScale": 7,
      "resolutionDependentShift": false,
      "sampler": 10,
      "shift": 1,
      "steps": 48
    },
    "ideogram_4_fast": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 10,
      "shift": 1,
      "steps": 20
    },
    "ideogram_4_instant": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 10,
      "shift": 1,
      "steps": 8
    },
    "krea_2_raw": {
      "guidanceScale": 3.5,
      "resolutionDependentShift": true,
      "sampler": 10,
      "steps": 52
    },
    "krea_2_turbo": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 10,
      "shift": 3,
      "steps": 8
    },
    "ltx_2.3_22b_dev": {
      "guidanceScale": 5,
      "sampler": 17,
      "shift": 5,
      "steps": 30
    },
    "ltx_2.3_22b_distilled": {
      "guidanceScale": 1,
      "sampler": 19,
      "shift": 5,
      "steps": 8
    },
    "ltx_2_19b_dev": {
      "guidanceScale": 5,
      "sampler": 17,
      "shift": 5,
      "steps": 30
    },
    "ltx_2_19b_distilled": {
      "guidanceScale": 1,
      "sampler": 19,
      "shift": 5,
      "steps": 8
    },
    "minimax_h3_fl2va": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 16,
      "shift": 12,
      "steps": 50
    },
    "minimax_h3_ref2va": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 16,
      "shift": 12,
      "steps": 50
    },
    "qwen_image_1.0": {
      "guidanceScale": 4,
      "sampler": 17,
      "shift": 2,
      "steps": 30
    },
    "qwen_image_2.1": {
      "guidanceScale": 1,
      "resolutionDependentShift": true,
      "sampler": 16,
      "shift": 1,
      "steps": 40
    },
    "qwen_image_2512": {
      "guidanceScale": 4,
      "sampler": 17,
      "shift": 2,
      "steps": 30
    },
    "qwen_image_edit_1.0": {
      "guidanceScale": 4,
      "sampler": 17,
      "shift": 2,
      "steps": 30
    },
    "qwen_image_edit_2509": {
      "guidanceScale": 4,
      "sampler": 17,
      "shift": 2,
      "steps": 30
    },
    "qwen_image_edit_2511": {
      "guidanceScale": 4,
      "sampler": 17,
      "shift": 2,
      "steps": 30
    },
    "sd_v1.5": {
      "guidanceScale": 5,
      "resolutionDependentShift": false,
      "sampler": 12,
      "shift": 1,
      "steps": 16
    },
    "sd_xl_base_1.0": {
      "guidanceScale": 5,
      "resolutionDependentShift": false,
      "sampler": 12,
      "shift": 1,
      "steps": 16
    },
    "skyreels_v1_hunyuan_i2v": {
      "guidanceScale": 6,
      "resolutionDependentShift": false,
      "sampler": 16,
      "shift": 7,
      "steps": 30
    },
    "skyreels_v1_hunyuan_t2v": {
      "guidanceScale": 6,
      "resolutionDependentShift": false,
      "sampler": 16,
      "shift": 7,
      "steps": 30
    },
    "wan_v2.1_1.3b_480p": {
      "guidanceScale": 5,
      "sampler": 10,
      "shift": 5,
      "steps": 30
    },
    "wan_v2.1_14b_720p": {
      "guidanceScale": 5,
      "sampler": 10,
      "shift": 5,
      "steps": 30
    },
    "wan_v2.1_14b_i2v_480p": {
      "guidanceScale": 5,
      "sampler": 10,
      "shift": 3,
      "steps": 30
    },
    "wan_v2.1_14b_i2v_720p": {
      "guidanceScale": 5,
      "sampler": 10,
      "shift": 5,
      "steps": 30
    },
    "wan_v2.2_a14b_hne_i2v": {
      "guidanceScale": 3.5,
      "sampler": 17,
      "shift": 5,
      "steps": 30
    },
    "wan_v2.2_a14b_hne_t2v": {
      "guidanceScale": 4,
      "sampler": 17,
      "shift": 8,
      "steps": 30
    },
    "z_image_1.0": {
      "guidanceScale": 4,
      "resolutionDependentShift": true,
      "sampler": 17,
      "steps": 30
    },
    "z_image_turbo_1.0": {
      "guidanceScale": 1,
      "resolutionDependentShift": false,
      "sampler": 17,
      "shift": 3,
      "steps": 8
    }
  }
}
```

**`Scripts/make-recommended-settings.py`** (file nuovo o riscritto per intero):

```python
#!/usr/bin/env python3
"""Builds App/Resources/RecommendedSettings.json from the list of official configurations Draw Things keeps in its cache.

usage: make-recommended-settings.py [CONFIGS_JSON] [OUT_JSON]

CONFIGS_JSON defaults to the cache of the Draw Things app on this Mac
(~/Library/Containers/com.liuliu.draw-things/Data/Library/Caches/net/configs.json); OUT_JSON to
App/Resources/RecommendedSettings.json next to this script's repository.

For each model the file keeps the basic values Draw Things recommends: steps, guidanceScale, sampler (Draw Things'
number), shift and resolutionDependentShift (left out when the list does not say). Entries that use LoRAs (the
"with Lightning" variants) are not the model's base values and are left out. The key is the model's file name
without the quantization ("flux_2_klein_9b_f16.ckpt" and "flux_2_klein_9b_q6p.ckpt" are "flux_2_klein_9b"); an entry
that names its family (`version`) is also the fallback for that family.
"""
import json
import os
import re
import sys

DEFAULT_SOURCE = os.path.expanduser("~/Library/Containers/com.liuliu.draw-things/Data/Library/Caches/net/configs.json")
DEFAULT_OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Resources", "RecommendedSettings.json")
QUANTIZATION = re.compile(r"_(f16|f32|bf16|q\d+p|i8x|svd)$")


def model_key(file_name):
    """The model's file name without its quantization and extension."""
    name = re.sub(r"\.ckpt$", "", file_name)
    while True:
        shorter = QUANTIZATION.sub("", name)
        if shorter == name:
            return name
        name = shorter


def values(configuration):
    """The recommended values of a configuration, or None when it lacks the basic ones."""
    steps, guidance, sampler = configuration.get("steps"), configuration.get("guidanceScale"), configuration.get("sampler")
    if not isinstance(steps, int) or not isinstance(guidance, (int, float)) or not isinstance(sampler, int):
        return None
    result = {"steps": steps, "guidanceScale": guidance, "sampler": sampler}
    if isinstance(configuration.get("shift"), (int, float)):
        result["shift"] = configuration["shift"]
    if isinstance(configuration.get("resolutionDependentShift"), bool):
        result["resolutionDependentShift"] = configuration["resolutionDependentShift"]
    return result


def convert(entries):
    """{"models": {key: values}, "families": {version: values}} from the list of configurations."""
    models, families = {}, {}
    for entry in entries:
        configuration = entry.get("configuration") or {}
        model = configuration.get("model")
        if not isinstance(model, str) or configuration.get("loras"):
            continue
        found = values(configuration)
        if found is None:
            continue
        models.setdefault(model_key(model), found)
        family = entry.get("version")
        if isinstance(family, str) and family:
            families.setdefault(family, found)
    return {"models": dict(sorted(models.items())), "families": dict(sorted(families.items()))}


def main(argv):
    source = argv[1] if len(argv) > 1 else DEFAULT_SOURCE
    out = argv[2] if len(argv) > 2 else DEFAULT_OUT
    with open(source) as handle:
        table = convert(json.load(handle))
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w") as handle:
        json.dump(table, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print("wrote", os.path.abspath(out), len(table["models"]), "models,", len(table["families"]), "families")


if __name__ == "__main__":
    main(sys.argv)
```

(La tabella qui sopra è l'esito dello script sulla lista di Draw Things del 4 ottobre 2026. Rigenerarla con `python3 Scripts/make-recommended-settings.py` darebbe lo stesso file se la lista non è cambiata; il piano usa il file così com'è, per non dipendere dalla cache.)

- [ ] **Step 3: Verificare**

Run: `cd "/Users/existenz/Software developement/DT Hub" && python3 -m unittest Scripts/test_make_recommended_settings.py 2>&1 | tail -3 && python3 -c "import json; d=json.load(open('App/Resources/RecommendedSettings.json')); print(len(d['models']), len(d['families']))"`
Expected: `OK` dei 5 test e `46 18`.

- [ ] **Step 4: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Scripts App/Resources && git commit -m "feat: la tabella delle impostazioni consigliate per modello e lo script che la fa

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: La tabella in HubKit

**Files:**
- Create: `Packages/Sources/HubKit/Generation/RecommendedSettings.swift`, `Packages/Tests/HubKitTests/RecommendedSettingsTests.swift`

**Interfaces:**
- Produces (HubKit, `public`):
  - `struct RecommendedValues: Equatable, Sendable` (`steps`, `guidanceScale`, `sampler: Sampler`, `shift: Double?`, `resolutionDependentShift: Bool?`);
  - `struct RecommendedSettings: Equatable, Sendable` (`init(models:families:)`, `init(data: Data)` permissivo: voce rovinata, senza passi/CFG o con un campionatore sconosciuto è lasciata fuori, dati che non sono una tabella danno `.empty`; `static key(forFile:)`; `values(forFile:family:)`: per file, poi per famiglia, altrimenti nil; `static empty`);
  - `GenerationParameters.applying(_ values: RecommendedValues) -> GenerationParameters`: cambia solo passi, CFG, sampler, shift (se c'è) e l'interruttore (se c'è), poi `clamped()`.

- [ ] **Step 1: Scrivere i test e verificare che falliscano**

**`Packages/Tests/HubKitTests/RecommendedSettingsTests.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation
import Testing

@testable import HubKit

struct RecommendedSettingsTests {
  let table = RecommendedSettings(
    data: Data(
      """
      {"models":{
        "flux_2_klein_9b":{"steps":4,"guidanceScale":1,"sampler":16,"shift":3,"resolutionDependentShift":false},
        "qwen_image_2512":{"steps":30,"guidanceScale":4,"sampler":17,"shift":2},
        "z_image_1.0":{"steps":30,"guidanceScale":4,"sampler":17,"resolutionDependentShift":true},
        "bad_steps":{"steps":"x","guidanceScale":1,"sampler":1},
        "bad_sampler":{"steps":4,"guidanceScale":1,"sampler":999},
        "no_guidance":{"steps":4,"sampler":1}},
       "families":{"v1":{"steps":16,"guidanceScale":5,"sampler":12,"shift":1,"resolutionDependentShift":false}}}
      """.utf8))

  @Test func theKeyDropsTheQuantizationAndTheExtension() {
    #expect(RecommendedSettings.key(forFile: "flux_2_klein_9b_f16.ckpt") == "flux_2_klein_9b")
    #expect(RecommendedSettings.key(forFile: "flux_2_klein_9b_q6p.ckpt") == "flux_2_klein_9b")
    #expect(RecommendedSettings.key(forFile: "wan_v2.2_a14b_hne_t2v_q6p_svd.ckpt") == "wan_v2.2_a14b_hne_t2v")
    #expect(RecommendedSettings.key(forFile: "juggernaut_reborn_q6p_q8p.ckpt") == "juggernaut_reborn")
    #expect(RecommendedSettings.key(forFile: "plain") == "plain")
  }

  @Test func aModelIsFoundByItsFileWhateverItsQuantization() {
    #expect(table.values(forFile: "flux_2_klein_9b_f16.ckpt", family: nil)?.steps == 4)
    #expect(table.values(forFile: "flux_2_klein_9b_i8x.ckpt", family: "other")?.sampler == .ddimTrailing)
  }

  @Test func aModelNotInTheTableFallsBackOnItsFamilyAndOtherwiseHasNothing() {
    #expect(table.values(forFile: "juggernaut_reborn_q6p_q8p.ckpt", family: "v1")?.steps == 16)
    #expect(table.values(forFile: "juggernaut_reborn_q6p_q8p.ckpt", family: "unknown") == nil)
    #expect(table.values(forFile: "juggernaut_reborn_q6p_q8p.ckpt", family: nil) == nil)
  }

  @Test func damagedEntriesAreLeftOutAndTheRestIsKept() {
    #expect(table.values(forFile: "bad_steps.ckpt", family: nil) == nil)
    #expect(table.values(forFile: "bad_sampler.ckpt", family: nil) == nil)
    #expect(table.values(forFile: "no_guidance.ckpt", family: nil) == nil)
    #expect(table.values(forFile: "qwen_image_2512_q8p.ckpt", family: nil)?.shift == 2)
    #expect(RecommendedSettings(data: Data("garbage".utf8)) == .empty)
    #expect(RecommendedSettings(data: Data("[1]".utf8)) == .empty)
  }

  @Test func applyingChangesOnlyStepsGuidanceSamplerAndShift() {
    var tab = GenerationParameters(width: 768, height: 1280, steps: 30, guidanceScale: 4, seed: 7, randomSeed: false, batchCount: 3)
    tab.loras = [LoRASelection(file: "x.ckpt")]
    tab.advanced.hiresFix = true
    tab.shift = 9
    let values = table.values(forFile: "flux_2_klein_9b_f16.ckpt", family: nil)!
    let result = tab.applying(values)
    #expect(result.steps == 4 && result.guidanceScale == 1 && result.sampler == .ddimTrailing)
    #expect(result.shift == 3 && result.resolutionDependentShift == false)
    var expected = tab
    expected.steps = 4
    expected.guidanceScale = 1
    expected.sampler = .ddimTrailing
    expected.shift = 3
    expected.resolutionDependentShift = false
    #expect(result == expected)
  }

  @Test func aListWithoutAShiftLeavesTheShiftAndTurnsTheSwitchOn() {
    var tab = GenerationParameters()
    tab.shift = 9
    tab.resolutionDependentShift = false
    let result = tab.applying(table.values(forFile: "z_image_1.0_q8p.ckpt", family: nil)!)
    #expect(result.shift == 9 && result.resolutionDependentShift)
    // A list that gives a shift but not the switch leaves the switch.
    var on = GenerationParameters()
    on.resolutionDependentShift = true
    let other = on.applying(table.values(forFile: "qwen_image_2512_q8p.ckpt", family: nil)!)
    #expect(other.shift == 2 && other.resolutionDependentShift)
  }

  @Test func appliedValuesAreLimitedLikeTheCardsLimitThem() {
    let wild = RecommendedValues(steps: 9999, guidanceScale: -3, sampler: .uniPC, shift: 99)
    let result = GenerationParameters().applying(wild)
    #expect(result.steps == GenerationParameters.stepsRange.upperBound)
    #expect(result.guidanceScale == 0 && result.shift == GenerationParameters.shiftRange.upperBound)
  }

  /// The file the app ships (made by the script from Draw Things' list): readable, with the models the app is
  /// used with and the families it falls back on.
  @Test func theShippedTableIsReadableAndKnowsTheCommonModels() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("App/Resources/RecommendedSettings.json"))
    let shipped = RecommendedSettings(data: data)
    #expect(shipped.values(forFile: "flux_2_klein_9b_f16.ckpt", family: nil)?.steps == 4)
    #expect(shipped.values(forFile: "z_image_turbo_1.0_f16.ckpt", family: nil)?.steps == 8)
    #expect(shipped.values(forFile: "qwen_image_2.1_q8p.ckpt", family: nil)?.steps == 40)
    #expect(shipped.values(forFile: "juggernaut_reborn_q6p_q8p.ckpt", family: "v1")?.guidanceScale == 5)
    #expect(shipped.values(forFile: "some_sdxl_finetune.ckpt", family: "sdxl_base_v0.9") != nil)
  }
}
```

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter RecommendedSettingsTests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'RecommendedSettings' in scope`.

- [ ] **Step 2: Implementare**

**`Packages/Sources/HubKit/Generation/RecommendedSettings.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation

/// The basic values Draw Things recommends for a model: steps, guidance, sampler and shift
/// (`2026-10-04-recommended-settings-design.md`).
public struct RecommendedValues: Equatable, Sendable {
  public var steps: Int
  public var guidanceScale: Double
  public var sampler: Sampler
  /// nil when the list gives none: the model computes it from the resolution, and the tab's shift stays as it is.
  public var shift: Double?
  /// nil when the list does not say.
  public var resolutionDependentShift: Bool?

  public init(
    steps: Int, guidanceScale: Double, sampler: Sampler, shift: Double? = nil, resolutionDependentShift: Bool? = nil
  ) {
    self.steps = steps
    self.guidanceScale = guidanceScale
    self.sampler = sampler
    self.shift = shift
    self.resolutionDependentShift = resolutionDependentShift
  }
}

/// The table of recommended values, by model and by family. It is a file in the app (`RecommendedSettings.json`,
/// made by `Scripts/make-recommended-settings.py` from Draw Things' own list); it is not in the Preset menu.
public struct RecommendedSettings: Equatable, Sendable {
  private var models: [String: RecommendedValues]
  private var families: [String: RecommendedValues]

  public init(models: [String: RecommendedValues] = [:], families: [String: RecommendedValues] = [:]) {
    self.models = models
    self.families = families
  }

  public static let empty = RecommendedSettings()

  /// Reads the file's JSON, leniently: an entry that is damaged, lacks a basic value or names a sampler
  /// Draw Things DT Hub does not know is left out; data that is not a table gives an empty one.
  public init(data: Data) {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      self.init()
      return
    }
    func read(_ section: Any?) -> [String: RecommendedValues] {
      var result: [String: RecommendedValues] = [:]
      for (key, raw) in (section as? [String: Any]) ?? [:] {
        guard let entry = raw as? [String: Any], let steps = entry["steps"] as? Int,
          let guidance = (entry["guidanceScale"] as? NSNumber)?.doubleValue, let samplerNumber = entry["sampler"] as? Int,
          let sampler = Sampler(rawValue: samplerNumber)
        else { continue }
        result[key] = RecommendedValues(
          steps: steps, guidanceScale: guidance, sampler: sampler, shift: (entry["shift"] as? NSNumber)?.doubleValue,
          resolutionDependentShift: entry["resolutionDependentShift"] as? Bool)
      }
      return result
    }
    self.init(models: read(root["models"]), families: read(root["families"]))
  }

  /// The model's file name without its quantization and extension: `flux_2_klein_9b_f16.ckpt` and
  /// `flux_2_klein_9b_q6p.ckpt` are both `flux_2_klein_9b`.
  public static func key(forFile file: String) -> String {
    var name = file
    if name.hasSuffix(".ckpt") { name.removeLast(5) }
    while let range = name.range(of: #"_(f16|f32|bf16|q\d+p|i8x|svd)$"#, options: .regularExpression) {
      name.removeSubrange(range)
    }
    return name
  }

  /// By the model's file, then by its family; nil when the table has neither.
  public func values(forFile file: String, family: String?) -> RecommendedValues? {
    models[Self.key(forFile: file)] ?? family.flatMap { families[$0] }
  }
}

extension GenerationParameters {
  /// The parameters with the recommended steps, guidance, sampler and shift (and the shift switch when the
  /// table says it), limited as the cards limit them. Nothing else changes: not the size, seed, batch, LoRAs,
  /// Advanced cards. A model whose list gives no shift leaves the shift as it is.
  public func applying(_ values: RecommendedValues) -> GenerationParameters {
    var copy = self
    copy.steps = values.steps
    copy.guidanceScale = values.guidanceScale
    copy.sampler = values.sampler
    if let shift = values.shift { copy.shift = shift }
    if let switchOn = values.resolutionDependentShift { copy.resolutionDependentShift = switchOn }
    return copy.clamped()
  }
}
```

- [ ] **Step 3: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubKit `101 tests … passed` (8 nuovi, tra cui la lettura della tabella vera di `App/Resources`); gli altri invariati.

- [ ] **Step 4: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: RecommendedSettings — la tabella dei valori consigliati e la sua applicazione ai parametri

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: La scelta del modello (HubCore)

**Files:**
- Modify/Create: `Packages/Sources/HubCore/Selection/ModelSelection.swift`, `Packages/Tests/HubCoreTests/ModelChoiceTests.swift`

**Interfaces:**
- Consumes: `RecommendedSettings`, `GenerationParameters.applying` (Task 2); `ModelCatalog.model(forFile:)`, `CatalogModel.family` (esistenti).
- Produces: `ModelSelection.choose(_ file: String, applyingTo parameters: GenerationParameters, from table: RecommendedSettings, in catalog: ModelCatalog) -> GenerationParameters?`: seleziona il file; restituisce i parametri con i valori consigliati solo se il modello è **un altro** e la tabella lo conosce (per file, poi per la famiglia che il catalogo gli dà); altrimenti nil. `select(_:)` non cambia.

- [ ] **Step 1: Scrivere i test e verificare che falliscano**

**`Packages/Tests/HubCoreTests/ModelChoiceTests.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct ModelChoiceTests {
  let table = RecommendedSettings(
    models: [
      "flux_2_klein_9b": RecommendedValues(steps: 4, guidanceScale: 1, sampler: .ddimTrailing, shift: 3, resolutionDependentShift: false),
      "qwen_image_2.1": RecommendedValues(steps: 40, guidanceScale: 1, sampler: .ddimTrailing, shift: 1, resolutionDependentShift: true),
    ],
    families: ["v1": RecommendedValues(steps: 16, guidanceScale: 5, sampler: .dpmpp2mAYS, shift: 1, resolutionDependentShift: false)])

  func catalog() -> ModelCatalog {
    func model(_ file: String, _ family: String) -> CatalogModel {
      CatalogModel(file: file, name: file, family: family, capabilities: .unknown)
    }
    return ModelCatalog(
      models: [model("flux_2_klein_9b_f16.ckpt", "flux2_9b"), model("qwen_image_2.1_q8p.ckpt", "qwen_image_2.1"),
        model("juggernaut_reborn_q6p_q8p.ckpt", "v1"), model("mystery.ckpt", "mystery")],
      loras: [], fileCount: 4)
  }

  func selection() -> ModelSelection {
    ModelSelection(defaults: UserDefaults(suiteName: "ModelChoiceTests-\(UUID())")!)
  }

  @Test func choosingAnotherModelSelectsItAndReturnsTheRecommendedValues() throws {
    let selection = selection()
    var tab = GenerationParameters(width: 768, height: 1280, steps: 30, guidanceScale: 4)
    tab.loras = [LoRASelection(file: "x.ckpt")]
    let result = try #require(selection.choose("flux_2_klein_9b_f16.ckpt", applyingTo: tab, from: table, in: catalog()))
    #expect(selection.selectedFile == "flux_2_klein_9b_f16.ckpt")
    #expect(result.steps == 4 && result.sampler == .ddimTrailing && result.width == 768 && result.loras.count == 1)
  }

  @Test func choosingTheSameModelAgainChangesNothing() {
    let selection = selection()
    selection.select("flux_2_klein_9b_f16.ckpt")
    #expect(selection.choose("flux_2_klein_9b_f16.ckpt", applyingTo: GenerationParameters(steps: 30), from: table, in: catalog()) == nil)
  }

  @Test func aModelTheTableDoesNotKnowIsSelectedAndLeavesTheValues() {
    let selection = selection()
    #expect(selection.choose("mystery.ckpt", applyingTo: GenerationParameters(steps: 30), from: table, in: catalog()) == nil)
    #expect(selection.selectedFile == "mystery.ckpt")
  }

  @Test func aModelFallsBackOnItsFamilyAndSwitchingBackAppliesTheOthersAgain() throws {
    let selection = selection()
    let fine = try #require(selection.choose("juggernaut_reborn_q6p_q8p.ckpt", applyingTo: GenerationParameters(), from: table, in: catalog()))
    #expect(fine.steps == 16 && fine.guidanceScale == 5)
    let qwen = try #require(selection.choose("qwen_image_2.1_q8p.ckpt", applyingTo: fine, from: table, in: catalog()))
    #expect(qwen.steps == 40 && qwen.resolutionDependentShift)
    let klein = try #require(selection.choose("flux_2_klein_9b_f16.ckpt", applyingTo: qwen, from: table, in: catalog()))
    #expect(klein.steps == 4 && !klein.resolutionDependentShift)
  }

  @Test func selectingWithoutChoosingKeepsTheValues() {
    // What a preset, the JSON editor and "resume parameters" do: `select` alone.
    let selection = selection()
    selection.select("qwen_image_2.1_q8p.ckpt")
    #expect(selection.selectedFile == "qwen_image_2.1_q8p.ckpt")
  }
}
```

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter ModelChoiceTests 2>&1 | grep -E "error:" | head -2`
Expected: `value of type 'ModelSelection' has no member 'choose'`.

- [ ] **Step 2: Implementare**

```diff
diff --git a/Packages/Sources/HubCore/Selection/ModelSelection.swift b/Packages/Sources/HubCore/Selection/ModelSelection.swift
index edf4cf6..fd2c5b9 100644
--- a/Packages/Sources/HubCore/Selection/ModelSelection.swift
+++ b/Packages/Sources/HubCore/Selection/ModelSelection.swift
@@ -23,6 +23,22 @@ public final class ModelSelection {
     defaults.set(selectedFile, forKey: Self.key)
   }
 
+  /// The user chose this model in the header: selects it, and, if it is another model than the one selected and
+  /// the table knows it (by its file, then by its family), returns `parameters` with the recommended steps,
+  /// guidance, sampler and shift. Nil when nothing about the parameters should change. Only the header's menu
+  /// goes through here: a preset, the JSON editor, "resume parameters" and the restored session choose models
+  /// with `select`, and keep their own values.
+  public func choose(
+    _ file: String, applyingTo parameters: GenerationParameters, from table: RecommendedSettings, in catalog: ModelCatalog
+  ) -> GenerationParameters? {
+    let previous = selectedFile
+    select(file)
+    guard file != previous, let values = table.values(forFile: file, family: catalog.model(forFile: file)?.family) else {
+      return nil
+    }
+    return parameters.applying(values)
+  }
+
   /// An empty name means no model, as it does for RUN (`RunAvailability`).
   private static func normalized(_ file: String?) -> String? {
     guard let file, !file.isEmpty else { return nil }
```

- [ ] **Step 3: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubCore `464 tests … passed` (5 nuovi).

- [ ] **Step 4: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: scegliere un modello dall'header applica i valori consigliati se il modello cambia

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: L'app

**Files:**
- Modify: `App/Generation/GenerationController.swift`, `App/MainWindow/HeaderBar.swift`

**Interfaces:**
- Consumes: `ModelSelection.choose` (Task 3), `RecommendedSettings(data:)` (Task 2), la risorsa `RecommendedSettings.json` (Task 1; l'app la include da sé: la cartella `App/` è sincronizzata con il progetto).
- Produces: `GenerationController.recommended` (letta dalla risorsa dell'app, `.empty` se manca) e `chooseModel(_:in:)`; il menu dei modelli dell'header chiama `generation.chooseModel`. Le altre vie (`load` di un preset, `applyJSON`, `resume`) restano su `selection.select`.

- [ ] **Step 1: Applicare le modifiche**

```diff
diff --git a/App/Generation/GenerationController.swift b/App/Generation/GenerationController.swift
index ffbcf06..e3a3e68 100644
--- a/App/Generation/GenerationController.swift
+++ b/App/Generation/GenerationController.swift
@@ -83,6 +83,24 @@ final class GenerationController {
     pendingSave = nil
   }
 
+  /// The recommended values per model, from the file the app ships (`RecommendedSettings.json`).
+  @ObservationIgnored let recommended: RecommendedSettings = {
+    guard let url = Bundle.main.url(forResource: "RecommendedSettings", withExtension: "json"),
+      let data = try? Data(contentsOf: url)
+    else { return .empty }
+    return RecommendedSettings(data: data)
+  }()
+
+  /// The model chosen in the header: selected, and the tab takes its recommended steps, guidance, sampler and
+  /// shift when the model changes (a model the table does not know leaves the values as they are).
+  func chooseModel(_ file: String, in connection: DrawThingsConnection) {
+    if let values = connection.selection.choose(
+      file, applyingTo: parameters, from: recommended, in: connection.monitor.catalog)
+    {
+      parameters = values
+    }
+  }
+
   /// The saved presets (spec §6).
   let presets = PresetStore(folder: PresetStore.defaultFolder)
   /// Reads and writes the Draw Things configuration JSON (spec §6, level 3).
```

```diff
diff --git a/App/MainWindow/HeaderBar.swift b/App/MainWindow/HeaderBar.swift
index bea688c..4d4a421 100644
--- a/App/MainWindow/HeaderBar.swift
+++ b/App/MainWindow/HeaderBar.swift
@@ -84,7 +84,7 @@ struct HeaderBar: View {
             Toggle(
               isOn: Binding(
                 get: { selection.selectedFile == model.file },
-                set: { _ in selection.select(model.file) })
+                set: { _ in generation.chooseModel(model.file, in: connection) })
             ) {
               Text(verbatim: model.name)
             }
```

- [ ] **Step 2: Compilare e provare**

Run: `cd "/Users/existenz/Software developement/DT Hub" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath /tmp/r-dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" && ls "/tmp/r-dd/Build/Products/Debug/DT Hub.app/Contents/Resources/RecommendedSettings.json"`
Expected: `** BUILD SUCCEEDED **` e il percorso della risorsa dentro l'app.

Run: `cd "/Users/existenz/Software developement/DT Hub" && grep -rn "selection.select(" App`
Expected: nessun uso nel menu dei modelli dell'header (solo `GenerationController` con `load`, `applyJSON` e `resume`).

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: gli stessi conteggi del Task 3 (totale **649**).

- [ ] **Step 3: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A App && git commit -m "feat: il menu dei modelli dell'header applica le impostazioni consigliate

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Prova nell'app e documenti

**Files:**
- Modify: `docs/superpowers/specs/2026-10-04-recommended-settings-design.md`, `docs/superpowers/backlog.md`

- [ ] **Step 1: Provare nell'app**

**Se l'app dell'utente è aperta, non pilotare le finestre** (stesso identificatore): chiedere all'utente di provarla lui, o aspettare che la chiuda. Il menu dei modelli è un menu a tendina: gli strumenti per pilotare le finestre in background non lo aprono, quindi la prova è dell'utente o richiede il controllo dello schermo.

```bash
cd "/Users/existenz/Software developement/DT Hub"
xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
open "build/Build/Products/Debug/DT Hub.app"
```

Checklist (connesso al server, con questi modelli installati):
1. **FLUX.2 klein 9B** dal menu dell'header: Step **4**, CFG **1**, Sampler **DDIM Trailing**, Shift **3**, «Shift in base alla risoluzione» spento.
2. **Qwen Image 2.1**: Step **40**, CFG **1**, DDIM Trailing, interruttore «in base alla risoluzione» **acceso**.
3. **ERNIE Image Turbo**: Step **8**, CFG **1**, UniPC Trailing, Shift **4**. **Z-Image Turbo**: Step **8**, CFG **1**, UniPC Trailing, Shift **3**. **Z-Image** (base): Step **30**, CFG **4**.
4. Cambiare Step a mano e scegliere **lo stesso modello** dal menu: il valore a mano resta.
5. Scegliere un altro modello dopo aver cambiato larghezza, altezza, seed, batch e aggiunto un LoRA: restano tutti.
6. Caricare un preset che nomina un modello diverso: valgono i valori del preset, non i consigliati.
7. Riavviare l'app: i valori sono quelli di prima, non vengono riapplicati.
8. Un modello fuori dalla tabella (per esempio un fine-tuned senza famiglia nota): i valori restano; uno di famiglia SD 1.5 o SDXL prende quelli della famiglia (16 passi, CFG 5).

- [ ] **Step 2: Aggiornare spec e backlog**

```bash
cd "/Users/existenz/Software developement/DT Hub" && python3 - <<'PY'
p = 'docs/superpowers/specs/2026-10-04-recommended-settings-design.md'
s = open(p).read()
s = s.replace("Stato: da approvare", "Stato: realizzata")
open(p, 'w').write(s)
p = 'docs/superpowers/backlog.md'
s = open(p).read().rstrip() + """

## Rimandi delle impostazioni consigliate

- **Le voci con LoRA acceleratore** (Lightning, Turbo) non sono nella tabella: la scelta resta all'utente (`docs/superpowers/reference-lora-acceleratori.md` mostra cosa cambierebbero).
- **La tabella si rigenera a mano** con `python3 Scripts/make-recommended-settings.py` quando Draw Things aggiorna la lista; i modelli nuovi hanno il valore consigliato solo dopo la rigenerazione.
- **Nessun avviso né annulla** quando cambiare modello cambia i valori.
- **Il menu dei modelli non ha test automatici**; la logica sta in `ModelSelection.choose`.
"""
open(p, 'w').write(s + "\n")
PY
git diff --stat docs | tail -1
```

Expected: statistica su due file.

- [ ] **Step 3: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add docs && git commit -m "docs: impostazioni consigliate realizzate; rimandi nel backlog

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Fine

Esito atteso sul branch `recommended-settings`:
- **649 test verdi** (più i 5 dello script Python), build Xcode pulita;
- scegliere un modello dal menu dell'header porta Step, CFG, Sampler e Shift a quelli consigliati da Draw Things per quel modello (o per la sua famiglia); tutto il resto resta com'era.

Poi: revisione indipendente, correzioni, prova dell'utente (**lasciare l'app aperta**) e merge.
