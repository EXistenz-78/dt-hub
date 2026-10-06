#!/usr/bin/env python3
"""make-i4-data.py — builds the data of the Prompt Master I4 plug-in.

The vocabulary is the one of Prompt Master (Plugins/PromptMaster/Data/prompt-database.json, copied as it is, never
modified). The rest is written here: which categories feed each field of the Ideogram 4 caption, the settings of the
language model and the master prompt. Writes, under Plugins/PromptMasterI4:
  Data/prompt-database.json   the shared vocabulary
  Data/ideogram4.json         fields, language model options and master prompt
  Sources/PromptMasterI4/Embedded/EmbeddedData.swift   both files as Swift raw strings (a plug-in bundle has no resources)
Run from anywhere; the output is deterministic.
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(HERE)
SHARED = os.path.join(os.path.dirname(PLUGIN), "PromptMaster", "Data", "prompt-database.json")

CONFIG_VERSION = "1.1.0"

FIELDS = {
    "aesthetics": {"common": ["ij_mood_merged", "mood_aesthetic_register", "atmosphere", "color_harmony",
                              "genre_aesthetic", "atmospheric_fx"], "photoOnly": ["optical_fx"]},
    "lighting": {"common": ["light_source", "light_quality", "light_scheme"]},
    "style": {"photo": ["framing", "camera_angle", "composition", "lens_focus", "photo_genre"],
              "art": ["art_movement", "design_movement", "anime_cartoon_style", "cultural_tradition",
                      "artist_classical", "artist_modern", "artist_illustration"]},
    "medium": {"photo": ["medium_digital_3d", "film_stock_process"],
               "art": ["medium_digital_3d", "medium_paint_draw", "medium_print_craft"]},
    "background": {"common": ["background_setup"]},
    "lettering": {"common": ["typography_text"]},
}

MERGED_MOOD = {"id": "ij_mood_merged", "it": "Mood", "en": "Mood", "from": ["mood_emotional_tone", "mood"]}

OPTIONS = {"temperature": 0.6, "maxTokens": 4096, "thinking": False, "timeout": 600}

SYSTEM = """You write short English sentences for the fields of a structured image caption read by the image model Ideogram 4. The request has one block for each field to write, wrapped in a tag named after the field. A block holds the user's own words (any language) and/or lines shaped like "Category: term": terms the user picked from a vocabulary; the category says what kind of thing the term is. For example "Lighting Scheme: butterfly lighting" is a way to light a face, not butterflies, and "Art Movement: Pop Art" is a style, not a picture of a pop singer.

Answer with ONE tag for each block of the request, with the same name, in the same order, and ONE English sentence inside each tag. Write nothing else: no JSON, no markdown, no notes, no tags that are not in the request.

Rules for every sentence:
1. English only, whatever language the input is in. A complete sentence that stands alone, written as a plain description of the picture: no commands, no keyword lists, no labels, no quotation marks around it.
2. Use every term of the block with the meaning its category gives it; never drop, soften or contradict one. Add only a few connecting words: invent no new objects, people, places, colors or events. Too much information makes the picture worse.
3. Stay in the field of the tag. high_level_description (up to 60 words): the whole picture in plain words (who or what, doing what, where); no style, light or camera. aesthetics (35): mood, atmosphere, color harmony, genre, visual effects. lighting (35): source, quality, direction, shadows. photo (35): framing, angle, lens, depth of field, composition. art_style (35): movement, tradition, artists the look recalls. medium (25): material, technique, process. background (40): what lies behind everything else; no foreground subject. element, kind="object" (50): that one thing alone: what it is, looks like, its material, pose, own colors; nothing about the rest of the scene or about where it sits. element, kind="text" (40): the lettering itself: letterforms, material, color, finish; never invent the words it says.
4. Never write hex codes, sizes, coordinates or position words such as "top left".
5. high_level_description is the overview of the picture; background and elements are details inside it: add detail, never contradict it, never repeat its sentences, never put into one element what belongs to another. If the user's own words disagree, keep each as written.
6. <already_written> is context only: stay consistent with it, never answer for it.

Example. Request:
<aesthetics>
Mood: melancholic
Color Harmony: Split-complementary scheme
</aesthetics>
<element_1 kind="text">
Lettering style notes: sopra la porta
Text & Lettering: hand-painted vintage signage
</element_1>
Reply in exactly this shape, replacing the dots with the sentence:
<aesthetics>...</aesthetics>
<element_1>...</element_1>
Answer:
<aesthetics>A melancholic mood, with colors set against each other in a split-complementary scheme.</aesthetics>
<element_1>Hand-painted vintage signage with slightly worn letterforms, set above the door.</element_1>
"""


def swift_literal(name, text):
    assert '"""#' not in text
    return f'  static let {name} = #"""\n{text}\n"""#\n'


if __name__ == "__main__":
    with open(SHARED) as source:
        database_text = json.dumps(json.load(source), ensure_ascii=False, indent=1, sort_keys=False) + "\n"
    config = {"schema": 1, "version": CONFIG_VERSION, "fields": FIELDS, "mergedMood": MERGED_MOOD,
              "options": OPTIONS, "system": SYSTEM.rstrip("\n")}
    config_text = json.dumps(config, ensure_ascii=False, indent=1, sort_keys=False) + "\n"
    os.makedirs(os.path.join(PLUGIN, "Data"), exist_ok=True)
    for name, text in (("prompt-database", database_text), ("ideogram4", config_text)):
        with open(os.path.join(PLUGIN, "Data", name + ".json"), "w") as out:
            out.write(text)
    embedded = os.path.join(PLUGIN, "Sources", "PromptMasterI4", "Embedded")
    os.makedirs(embedded, exist_ok=True)
    with open(os.path.join(embedded, "EmbeddedData.swift"), "w") as out:
        out.write("// Generated by Scripts/make-i4-data.py: do not edit.\n"
                  "// The data files of the plug-in as strings: a plug-in bundle holds only its library.\n\n"
                  "enum EmbeddedData {\n" + swift_literal("database", database_text.rstrip("\n"))
                  + "\n" + swift_literal("ideogram4", config_text.rstrip("\n")) + "}\n")
    print(f"ideogram4 {CONFIG_VERSION}: {sum(len(v) for f in FIELDS.values() for v in f.values())} category slots")
