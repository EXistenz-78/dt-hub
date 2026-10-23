#!/usr/bin/env python3
"""make-moss-data.py — costruisce i dati del plug-in Prompt Master MOSS.

Il vocabolario è quello di Prompt Master (Plugins/PromptMaster/Data/prompt-database.json, copiato com'è, mai modificato).
Il resto si scrive qui: le categorie nascoste e quelle solo-Foto / solo-Arte, quelle che vanno in `meta`, i termini
aggiunti al negativo, le opzioni dell'LLM e il master prompt.
Scrive, sotto Plugins/PromptMasterMOSS:
  Data/prompt-database.json   il vocabolario condiviso
  Data/moss.json              configurazione
  Data/master-prompt.md       il master prompt (Markdown)
  Sources/PromptMasterMOSS/Embedded/EmbeddedData.swift   i tre file come stringhe Swift (un bundle non ha risorse)
Si lancia da qualsiasi cartella; l'uscita è deterministica.
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(HERE)
SHARED = os.path.join(os.path.dirname(PLUGIN), "PromptMaster", "Data", "prompt-database.json")

CONFIG_VERSION = "1.0.0"
# Le voci del negativo hanno una sezione propria: non compaiono nella lista del Summary.
HIDDEN_CATEGORIES = ["negative_terms"]
# Come in Prompt Master I4: queste categorie esistono solo con Foto, quelle sotto solo con Arte.
PHOTO_ONLY = ["framing", "camera_angle", "composition", "lens_focus", "photo_genre", "film_stock_process", "optical_fx"]
ART_ONLY = ["medium_paint_draw", "medium_print_craft", "art_movement", "design_movement", "anime_cartoon_style",
            "cultural_tradition", "artist_classical", "artist_modern", "artist_illustration"]
# Medium e genere: tag brevi che vanno in summary.meta. Tutto il resto va nella caption.
META_CATEGORIES = ["medium_digital_3d", "medium_paint_draw", "medium_print_craft", "film_stock_process", "photo_genre",
                   "art_movement", "design_movement", "anime_cartoon_style", "cultural_tradition"]
# I due termini più usati negli esempi ufficiali di MOSS: il database condiviso non si modifica.
EXTRA_NEGATIVE = [{"id": "ng_worst_quality", "it": "Qualità pessima", "en": "worst quality"},
                  {"id": "ng_low_quality", "it": "Bassa qualità", "en": "low quality"}]
OPTIONS = {"temperature": 0.6, "maxTokens": 4096, "thinking": False, "timeout": 600}

SYSTEM = """You prepare the text of a structured image prompt for the image model MOSS Image. The request has blocks under titles: "summary" (the whole picture), "meta" (a short list of free tags, only when the user wrote some), one "element N (type)" block per element, where type is object, character, text, panel or subject, and "tags N" blocks (the free tags of element N). A "text" element is lettering printed in the picture; a "panel" is a backdrop or frame covering a large area; a "subject" is the main subject.

Answer with the SAME titles in the SAME order, each followed by its rewritten text. Nothing else: no JSON, no notes.

Rules:
1. Every text you write MUST be in English, whatever language the input is in. If the input is Italian or any other language, TRANSLATE it: never answer in the language of the input. Plain descriptive prose, no commands, no keyword lists.
2. Words between quotation marks are printed in the picture: copy them exactly, never translate.
3. "summary": two or three sentences about the whole scene, style, light and mood. Work the lines shaped like "Category: term" into the sentences naturally. Do not describe the individual elements here.
4. "element N (type)": describe only what appears inside that region: appearance, material, colour, pose. For a "text" element describe the typography and the surface it is on, never the words themselves. No positions, no coordinates, no mention of other elements.
5. "meta" and "tags N": translate each tag to English and answer with a comma-separated list of short tags; do not add new ones.
6. Do not invent new elements.

Example. Request:
## summary
due amici in una foresta di bambù, di notte
Light Source: Neon lighting

## element 1 (panel)
sfondo di bambù

## element 2 (text)
scritta bianca in basso a sinistra

Reply in English, in exactly this shape, replacing the dots with the English text:
## summary
...

## element 1 (panel)
...

## element 2 (text)
...

Correct reply (note: everything is in English):
## summary
Two friends stand in a bamboo forest at night, their faces lit by a soft neon glow.

## element 1 (panel)
A dense backdrop of tall green bamboo culms fading into dark haze.

## element 2 (text)
Small white sans-serif lettering with a slight glow, printed over the lower left of the scene."""


def swift_literal(name, text):
    assert '"""#' not in text
    return f'  static let {name} = #"""\n{text}\n"""#\n'


if __name__ == "__main__":
    with open(SHARED) as source:
        database_text = json.dumps(json.load(source), ensure_ascii=False, indent=1, sort_keys=False) + "\n"
    config = {"schema": 1, "version": CONFIG_VERSION, "hiddenCategories": HIDDEN_CATEGORIES, "photoOnly": PHOTO_ONLY,
              "artOnly": ART_ONLY, "metaCategories": META_CATEGORIES, "extraNegativeTerms": EXTRA_NEGATIVE,
              "options": OPTIONS}
    config_text = json.dumps(config, ensure_ascii=False, indent=1, sort_keys=False) + "\n"
    master_text = "---\nversion: 1\n---\n" + SYSTEM.rstrip("\n")
    os.makedirs(os.path.join(PLUGIN, "Data"), exist_ok=True)
    with open(os.path.join(PLUGIN, "Data", "master-prompt.md"), "w") as out:
        out.write(master_text + "\n")
    for name, text in (("prompt-database", database_text), ("moss", config_text)):
        with open(os.path.join(PLUGIN, "Data", name + ".json"), "w") as out:
            out.write(text)
    embedded = os.path.join(PLUGIN, "Sources", "PromptMasterMOSS", "Embedded")
    os.makedirs(embedded, exist_ok=True)
    with open(os.path.join(embedded, "EmbeddedData.swift"), "w") as out:
        out.write("// Generated by Scripts/make-moss-data.py: do not edit.\n"
                  "// I file dei dati del plug-in come stringhe: un bundle contiene solo la libreria.\n\n"
                  "enum EmbeddedData {\n" + swift_literal("database", database_text.rstrip("\n"))
                  + "\n" + swift_literal("moss", config_text.rstrip("\n"))
                  + "\n" + swift_literal("masterPrompt", master_text) + "}\n")
    print(f"moss {CONFIG_VERSION}: meta {len(META_CATEGORIES)}, solo-Foto {len(PHOTO_ONLY)}, solo-Arte {len(ART_ONLY)}, nascoste {HIDDEN_CATEGORIES}")
