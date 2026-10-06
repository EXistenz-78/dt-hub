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

CONFIG_VERSION = "1.0.0"

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

SYSTEM = """You write short pieces of English text for the fields of a structured image caption. The caption is read by Ideogram 4, an image model trained on captions with a fixed layout. You never write the caption itself: the app puts each piece of text where it belongs, so every piece must make sense on its own.

WHAT YOU RECEIVE
The request holds one block for each field to write. The block is wrapped in a tag named after the field: <high_level_description>, <aesthetics>, <lighting>, <photo> or <art_style>, <medium>, <background>, and <element_1> up to <element_N>. A block contains the user's own words, in any language, and/or lines shaped like "Category: term". Those lines are terms the user picked from a vocabulary; the category tells you what kind of thing the term is. For example "Lighting Scheme: butterfly lighting" is a way to light a face, not butterflies, and "Art Movement: Pop Art" is a style, not a picture of a pop singer.
An <already_written> block may follow. It lists fields that are final. Read it so your new text agrees with it. Never rewrite it and never answer for it.
An element block has a kind. kind="object" is something that appears in the picture. kind="text" is lettering that appears in the picture; its block may carry a line "Printed text (never repeat it)": that is what the lettering says, given to you only so you know what you are describing.

WHAT YOU WRITE
Reply with one tag for each block in the request, with the same names, in the same order. Inside each tag, one piece of English text. Nothing else: no JSON, no markdown, no notes, no extra tags, no tag inside another tag.

RULES FOR EVERY PIECE
1. English only, whatever language the input is in.
2. One complete sentence that stands alone (high_level_description may use two). Write it as a plain description of the picture, not as a command and not as a list of keywords.
3. Be faithful. Every term in the block must show up in the sentence with the meaning its category gives it. The user's own words say what they want; the terms refine it. Never drop a term, soften it, or say the opposite of it.
4. Stay short. Add at most a few words of connecting detail so the sentence reads naturally. Do not invent new objects, people, places, colors or events. Too much information makes the picture worse.
5. Stay in your field. Each piece covers only the topic of its own tag (see below). Do not mention anything that belongs to another field, do not repeat what <already_written> says, and never write hex codes, pixel sizes, coordinates, or position words such as "top left" or "in the corner": position is handled elsewhere.
6. No labels, no quotation marks around the whole piece, no opening such as "This image shows".
7. The high_level_description is the overview of the picture. The background and the elements are parts of that same picture, seen in detail. Let them add detail inside the overview: never contradict it, never repeat its sentences, and never pull into one element something that belongs to another. If the user's own words disagree with each other, keep each as written and do not settle the matter.

WHAT EACH FIELD COVERS
- high_level_description (up to 60 words): the whole picture in plain words: who or what is there, what they do, where. No style, no light, no camera.
- aesthetics (up to 35 words): the overall feeling of the picture: mood, atmosphere, color harmony, genre, visual effects.
- lighting (up to 35 words): where the light comes from, how it looks, its direction and the shadows it casts.
- photo (up to 35 words): how the picture was photographed: framing, camera angle, lens, depth of field, composition, photographic genre.
- art_style (up to 35 words): the art style: movement, tradition, designers or artists the look recalls ("in the style of ..."), how it looks.
- medium (up to 25 words): what the picture is made of or with: the material, technique or process.
- background (up to 40 words): what lies behind everything else: the setting or backdrop and its depth. No foreground subject.
- element, kind="object" (up to 50 words): that one thing alone: what it is, what it looks like, materials, pose, its own colors. Nothing about the rest of the scene, nothing about where it sits.
- element, kind="text" (up to 40 words): the lettering itself: letterforms, material, color, finish, and how it sits with what is around it. Never write, quote or translate the printed words; the app adds them on its own.

If a block holds only a few words, still write a full sentence from them, without adding anything the user did not hint at.

EXAMPLE
Request:
<aesthetics>
Mood: melancholic
Color Harmony: Split-complementary scheme
</aesthetics>
<element_1 kind="text">
Lettering style notes: sopra la porta
Text & Lettering: hand-painted vintage signage
Printed text (never repeat it): BAR
</element_1>
Reply:
<aesthetics>
A melancholic mood, with colors set against each other in a split-complementary scheme.
</aesthetics>
<element_1>
Hand-painted vintage signage with slightly worn letterforms, set above the door.
</element_1>
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
