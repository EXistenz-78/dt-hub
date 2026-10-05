#!/usr/bin/env python3
"""make-prompt-data.py [--source DIR] — builds the data of the Prompt Master plug-in from Prompt Master 2.0.

Reads DIR/prompt_database.json (the database of PM 2.0, never modified) and writes, under Plugins/PromptMaster:
  Data/prompt-database.json     the slim database: ids, Italian and English names (no booru/prose forms)
  Data/master-prompts.json      one master prompt per family of Draw Things (provisional: see the spec §9)
  Sources/PromptMaster/Embedded/EmbeddedData.swift   both files as Swift raw strings (a plug-in bundle has no resources)
Run from anywhere; the output is deterministic.
"""
import argparse, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(HERE)
DEFAULT_SOURCE = "/Users/existenz/Software developement/Prompt generator/Prompt Master 2.0"

DATABASE_VERSION = "2.1.0"
MASTER_VERSION = "1.0.0"

# The families of Draw Things (its `version`), in the order of the spec §3; `old` is the family of PM 2.0 whose
# category rules (only_for, blocked_for, blocked_categories) seed `hiddenCategories`.
FAMILIES = [
    # id,              label,                         old,           negative, words,      provisional
    ("flux1",          "FLUX.1",                      "flux1",       False, "60-150",  False),
    ("flux2",          "FLUX.2 [dev]",                "flux2_klein", False, "50-150",  True),
    ("flux2_9b",       "FLUX.2 [klein] 9B",           "flux2_klein", False, "50-150",  False),
    ("flux2_4b",       "FLUX.2 [klein] 4B",           "flux2_klein", False, "50-150",  False),
    ("krea_2",         "Krea 2",                      "krea2",       True,  "30-70",   False),
    ("qwen_image",     "Qwen Image",                  "qwen_image",  True,  "50-150",  False),
    ("qwen_image_2.1", "Qwen Image 2.1",              "qwen_image",  False, "50-150",  True),
    ("z_image",        "Z Image",                     "z_image",     False, "60-120",  False),
    ("sdxl_base_v0.9", "Stable Diffusion XL",         "sdxl",        True,  "30-70",   False),
    ("v1",             "Stable Diffusion 1.5",        "sd15",        True,  "15-40",   False),
    ("ernie_image",    "ERNIE-Image",                 "ernie_image", True,  "30-80",   False),
    ("hidream_i1",     "HiDream-I1",                  "flux1",       False, "50-150",  True),
    ("cosmos2.5_2b",   "Anima (Cosmos 2.5)",          "illustrious", True,  "20-60",   True),
]

COMMON = """You write prompts for the image model "{label}".

The user gives you a description of the image they want, in any language, and a list of terms in English taken from a vocabulary of photography, lighting, color, style and materials (some may be marked as things to avoid). Combine them into ONE final prompt that describes a single coherent image: keep every element of the description, use each term where it makes sense, and never contradict the description. Do not add subjects, text or a story the user did not ask for; you may add small connecting details that make the scene coherent.

The final prompt must be written exclusively in English, whatever the language of the description. {output}

Model notes:
{notes}"""

OUTPUT_TEXT = "Reply with the prompt only: no title, no quotation marks around it, no explanation, no markdown, no alternatives."
OUTPUT_JSON = (
    'Reply with a JSON object and nothing else, in this shape: {"prompt": "...", "negative": "..."}. '
    '"prompt" is the final prompt; "negative" lists only what to avoid (specific artifacts, unwanted objects, things the user marked as to avoid), '
    "kept short and targeted, never a generic list of quality words unless the notes below say so. Both values are in English."
)

NOTES = {
    "flux1": """- Write natural, flowing prose in full sentences (T5 encoder: long relational sentences are fine). Target length: {words} words.
- Order: subject and action first, then setting, then light and color, then camera and lens, then style or medium.
- Never use quality tags (masterpiece, 8k, best quality): they degrade the result. No numeric weights.
- There is no negative prompt: say in positive words what the image contains; turn "avoid" terms into a positive description.
- Text that must appear in the image goes in double quotes.""",
    "flux2_klein": """- Write natural prose. The text encoder reads the first elements most strongly, so put the most important element first. Target length: {words} words (under 20 is under-specified, over 300 drifts).
- Order: subject and action, setting, light and color, camera and lens, style or medium.
- No negative prompt and no numeric weights: turn "avoid" terms into positive description. Never use quality tags.
- Exact colors can be given as hex codes (#RRGGBB). Text in the image goes in double quotes, with font, color and position.""",
    "krea_2": """- Write natural prose, {words} words. The model has an aesthetic of its own (depth of field, color grading, rim light): start minimal, with a clear subject, one note of light and one atmosphere, and do not over-specify technical parameters.
- Keep the subject layer and the style layer in separate sentences.
- Numeric weights are read as literal text: never use them.
- A negative prompt is supported but must stay minimal and targeted, naming only specific artifacts or objects to avoid.""",
    "qwen_image": """- Write natural prose like for FLUX, {words} words. Excellent with text in the image (also Chinese and other scripts): put it in double quotes and state font, color and position.
- A negative prompt is supported: use it targeted by kind of defect, never as a generic list of low-quality words; if nothing specific has to be excluded, leave "negative" empty.
- You may end the prompt with the quality suffix "Ultra HD, 4k, cinematic composition".""",
    "qwen_image_2.1": """- Write natural prose, {words} words. The text encoder is a vision-language model: precise spatial and material descriptions work well. Text in the image goes in double quotes with font, color and position.
- If the user wants a transparent background, say explicitly: an RGBA image with an alpha channel and a transparent background.
- There is no negative prompt (guidance 1): turn "avoid" terms into positive description. Never use quality tags.
(Provisional master prompt: to be reviewed against the model's documentation.)""",
    "z_image": """- This is a distilled turbo model with no negative prompt and no numeric weights. Hard limit 800 characters; attention falls after about 75 tokens, so keep the essential content early. Target: {words} words.
- The very first sentence must be the style or medium (before the subject). Do not frame the image as "a photograph" or "a cinematic frame from a film": that framing overrides the style even in first position.
- Turn "avoid" terms into positive description.""",
    "sdxl": """- Start with one descriptive sentence, then a tail of comma-separated tags. Target: {words} words. Quality boosters (masterpiece, best quality) still work.
- Numeric weights like (term:1.2) are allowed, sparingly.
- A negative prompt is recommended: a short comma-separated list of what to avoid (for example blurry, low quality, deformed hands) plus the terms the user marked as to avoid.""",
    "sd15": """- Tags only: {words} comma-separated tags (CLIP, 77-token limit). Order is priority: the first tokens weigh the most, so start with the subject and the style.
- Weights like (term:1.2) are allowed, sparingly.
- A negative prompt is indispensable: a short comma-separated list (blurry, low quality, bad anatomy, extra limbs) plus the terms the user marked as to avoid.""",
    "ernie_image": """- Follow-the-letter model: write a complete prompt of {words} words; the model does not enhance short prompts. Weights like (term:1.3) are supported.
- Text in the image: double quotes, the font style stated next to the text, an explicit position, short segments (8-10 words each).
- A negative prompt is supported but must stay targeted by kind of defect (deformed hands, blurred text), never a generic list of low-quality words.""",
    "hidream": """- Write natural prose, {words} words, subject first, then setting, light, camera and style. No quality tags, no numeric weights.
- Turn "avoid" terms into positive description.
(Provisional master prompt: to be reviewed against the model's documentation.)""",
    "anima": """- Mix a short tag line with natural language: begin with quality and meta tags, then the subject tags (Danbooru style, underscores between words), then one or two sentences in plain English for the scene. Target: {words} words in total.
- A negative prompt is supported: a short comma-separated list of what to avoid.
(Provisional master prompt: to be reviewed against the model's documentation.)""",
}
NOTES_KEY = {"flux1": "flux1", "flux2": "flux2_klein", "flux2_9b": "flux2_klein", "flux2_4b": "flux2_klein",
             "krea_2": "krea_2", "qwen_image": "qwen_image", "qwen_image_2.1": "qwen_image_2.1", "z_image": "z_image",
             "sdxl_base_v0.9": "sdxl", "v1": "sd15", "ernie_image": "ernie_image", "hidream_i1": "hidream",
             "cosmos2.5_2b": "anima"}

BOORU = {
    "sdxl_base_v0.9": "Tag mode is ON: output only comma-separated booru tags (underscores between words), no sentences. Begin with quality tags such as masterpiece, best quality, absurdres (for Pony models score_9, score_8_up, score_7_up).",
    "v1": "Tag mode is ON: output only comma-separated booru tags (underscores between words), no sentences. Begin with quality tags such as masterpiece, best quality.",
}


def hidden_categories(db, old_families, old_id, negative):
    family = next(f for f in old_families if f["id"] == old_id)
    hidden = set(family.get("blocked_categories") or [])
    for cat in db["categories"]:
        if old_id in (cat.get("blocked_for") or []):
            hidden.add(cat["id"])
        only = cat.get("only_for")
        if only is not None and old_id not in only:
            hidden.add(cat["id"])
        if cat["slot"] == "negative" and not negative:
            hidden.add(cat["id"])
    return sorted(hidden)


def build(source):
    db = json.load(open(os.path.join(source, "prompt_database.json")))
    groups = []
    for g in db["groups"]:
        item = {"id": g["id"], "it": g["it"], "en": g["en"]}
        if g.get("restricted"):
            item["restricted"] = True
        groups.append(item)
    categories = []
    for c in db["categories"]:
        item = {"id": c["id"], "group": c["group"], "it": c["it"], "en": c["en"], "descIt": c["desc_it"]}
        if c["slot"] == "negative":
            item["negative"] = True
        item["terms"] = [{"id": t["id"], "it": t["it"], "en": t["en"]} for t in c["terms"]]
        categories.append(item)
    database = {"schema": 1, "version": DATABASE_VERSION, "groups": groups, "categories": categories}

    families = {}
    for fid, label, old, negative, words, provisional in FAMILIES:
        output = OUTPUT_JSON if negative else OUTPUT_TEXT
        notes = NOTES[NOTES_KEY[fid]].format(words=words)
        entry = {
            "label": label, "negative": negative, "hiddenCategories": hidden_categories(db, db["families"], old, negative),
            "words": words, "system": COMMON.format(label=label, output=output, notes=notes),
        }
        if fid in BOORU:
            entry["booruSystem"] = BOORU[fid]
        if provisional:
            entry["provisional"] = True
        families[fid] = entry
    return database, {"schema": 1, "version": MASTER_VERSION, "families": families}


def swift_literal(name, text):
    assert '"""#' not in text
    return f'  static let {name} = #"""\n{text}\n"""#\n'


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default=DEFAULT_SOURCE)
    args = parser.parse_args()
    database, masters = build(args.source)
    os.makedirs(os.path.join(PLUGIN, "Data"), exist_ok=True)
    texts = {}
    for name, obj in (("prompt-database", database), ("master-prompts", masters)):
        texts[name] = json.dumps(obj, ensure_ascii=False, indent=1, sort_keys=False) + "\n"
        with open(os.path.join(PLUGIN, "Data", name + ".json"), "w") as out:
            out.write(texts[name])
    embedded = os.path.join(PLUGIN, "Sources", "PromptMaster", "Embedded")
    os.makedirs(embedded, exist_ok=True)
    with open(os.path.join(embedded, "EmbeddedData.swift"), "w") as out:
        out.write("// Generated by Scripts/make-prompt-data.py: do not edit.\n"
                  "// The data files of the plug-in as strings: a plug-in bundle holds only its library.\n\n"
                  "enum EmbeddedData {\n" + swift_literal("database", texts["prompt-database"].rstrip("\n"))
                  + "\n" + swift_literal("masterPrompts", texts["master-prompts"].rstrip("\n")) + "}\n")
    n_terms = sum(len(c["terms"]) for c in database["categories"])
    print(f"database {database['version']}: {len(database['groups'])} groups, {len(database['categories'])} categories, {n_terms} terms")
    print(f"master prompts {masters['version']}: {len(masters['families'])} families")
