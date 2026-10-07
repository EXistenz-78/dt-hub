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
DEFAULT_SOURCE = os.environ.get("PM2_SOURCE")  # the folder of Prompt Master 2.0; or pass --source

DATABASE_VERSION = "2.1.0"
MASTER_VERSION = "1.3.0"

# The families of Draw Things (its `version`), in the order of the spec §3; `old` is the family of PM 2.0 whose
# category rules (only_for, blocked_for, blocked_categories) seed `hiddenCategories`.
FAMILIES = [
    # id, label, old, negative, usual length, ceiling, unit, why the ceiling, provisional
    ("flux1", "FLUX.1", "flux1", False, "80-250", 300, "words",
     "the text encoder (T5-XXL) reads 512 tokens, about 350 words, and drops the rest", False),
    ("flux2", "FLUX.2 [dev]", "flux2_klein", False, "60-250", 300, "words",
     "the text encoder reads 512 tokens, about 350 words, and drops the rest", True),
    ("flux2_9b", "FLUX.2 [klein] 9B", "flux2_klein", False, "60-250", 300, "words",
     "the text encoder reads 512 tokens, about 350 words, and drops the rest", False),
    ("flux2_4b", "FLUX.2 [klein] 4B", "flux2_klein", False, "60-250", 300, "words",
     "the text encoder reads 512 tokens, about 350 words, and drops the rest", False),
    ("krea_2", "Krea 2", "krea2", True, "40-150", 300, "words",
     "the conditioning is limited to 512 tokens, about 350 words, and a longer prompt can corrupt the picture", False),
    ("qwen_image", "Qwen Image", "qwen_image", True, "80-250", 450, "words",
     "the text encoder reads about 1024 tokens, roughly 500 words, and the prompt is cut after that", False),
    ("qwen_image_2.1", "Qwen Image 2.1", "qwen_image", False, "300-450", 500, "words",
     "the text encoder reads about 1024 tokens, roughly 500 words, and the prompt is cut after that", True),
    ("z_image", "Z Image", "z_image", False, "100-250", 300, "words",
     "the text encoder reads 512 tokens by default, about 350 words, and drops the rest", False),
    ("sdxl_base_v0.9", "Stable Diffusion XL", "sdxl", True, "30-55", 60, "words",
     "each CLIP text encoder reads 77 tokens, about 55 words, and ignores the rest; commas and tags cost tokens too", False),
    ("v1", "Stable Diffusion 1.5", "sd15", True, "20-35", 40, "tags",
     "CLIP reads 77 tokens and ignores the rest; every tag and every comma costs tokens", False),
    ("ernie_image", "ERNIE-Image", "ernie_image", True, "50-150", 300, "words",
     "the prompt is limited to about 2048 characters, roughly 330 words", False),
    ("hidream_i1", "HiDream-I1", "flux1", False, "40-90", 150, "words",
     "the reference pipeline reads 128 tokens, about 90 words, by default, and some tools raise it to 256 tokens, about 150 words", True),
    ("cosmos2.5_2b", "Anima (Cosmos 2.5)", "illustrious", True, "30-120", 300, "words",
     "the text conditioner works on 512 tokens, about 350 words", True),
]

COMMON = """You write prompts for the image model "{label}".

The user gives you a description of the image they want, in any language, and a list of terms in English taken from a vocabulary of photography, lighting, color, style and materials (some may be marked as things to avoid). Combine them into ONE final prompt that describes a single coherent image: keep every element of the description, use each term where it makes sense, and never contradict the description. {extras}

The final prompt must be written exclusively in English, whatever the language of the description. {output}

Model notes:
{notes}"""

# What a prompt may add to the description. The families that read natural language are asked to enrich the scene; the
# tag-based ones keep the strict rule (a tag the user did not ask for changes the picture).
EXTRAS_STRICT = (
    "Do not add subjects, text or a story the user did not ask for; you may add small connecting details that make the "
    "scene coherent."
)
EXTRAS_ENRICH = (
    "Enrich the description: add concrete, visual detail (the setting, materials and textures, how the light falls, the "
    "atmosphere) so the prompt is vivid and specific, as long as every addition is consistent with the scene and the "
    "terms given and never contradicts them. Do not change the main subject, do not add text to be rendered and do not "
    "invent a story."
)
ENRICHING = {
    "flux1", "flux2", "flux2_9b", "flux2_4b", "krea_2", "qwen_image", "qwen_image_2.1", "z_image", "ernie_image",
    "hidream_i1",
}

OUTPUT_TEXT = "Reply with the prompt only: no title, no quotation marks around it, no explanation, no markdown, no alternatives."
OUTPUT_JSON = (
    'Reply with a JSON object and nothing else, in this shape: {"prompt": "...", "negative": "..."}. '
    '"prompt" is the final prompt; "negative" lists only what to avoid (specific artifacts, unwanted objects, things the user marked as to avoid), '
    "kept short and targeted, never a generic list of quality words unless the notes below say so. Both values are in English."
)

# How good the evidence for each ceiling is, for whoever reviews the master prompts (kept in `lengthNote`, not sent to the model).
EVIDENCE = {
    "flux1": "Encoder limit (T5-XXL 512 tokens), well documented.",
    "flux2": "Reference code constant (MAX_LENGTH = 512).", "flux2_9b": "Reference code constant (MAX_LENGTH = 512).",
    "flux2_4b": "Reference code constant (MAX_LENGTH = 512).",
    "krea_2": "Reference implementation (max_length 512) and a bug report: beyond 512 tokens the output is corrupted.",
    "qwen_image": "diffusers default max_sequence_length 1024; the figure of about 500 words comes from the notebook.",
    "qwen_image_2.1": "Confirmed by the user at 450-500 words; Qwen's own prompt enhancer writes 400-500 words.",
    "z_image": "Model card: 512 tokens by default, 1024 on request; 'works best with long and detailed prompts'.",
    "sdxl_base_v0.9": "CLIP window of 77 tokens (notebook); how a runtime chunks longer prompts is not checked.",
    "v1": "CLIP window of 77 tokens (notebook); how a runtime chunks longer prompts is not checked.",
    "ernie_image": "The 2048 characters come from the notebook only; the official model card states no limit.",
    "hidream_i1": "Reference pipeline default (128 tokens, CLIP 77); no official statement on the model's real capacity. A cautious ceiling.",
    "cosmos2.5_2b": "Anima runtime default (max_sequence_length 512, accepts up to 4096).",
}

LENGTH = "- Length: aim for {words} {unit}. When the description and the terms need more room, go on, but never beyond {max} {unit}: {why}."

NOTES = {
    "flux1": """- Write natural, flowing prose in full sentences (T5 encoder: long relational sentences are fine).
- Order: subject and action first, then setting, then light and color, then camera and lens, then style or medium.
- Never use quality tags (masterpiece, 8k, best quality): they degrade the result. No numeric weights.
- There is no negative prompt: say in positive words what the image contains; turn "avoid" terms into a positive description.
- Text that must appear in the image goes in double quotes.""",
    "flux2_klein": """- Write natural prose. The text encoder reads the first elements most strongly, so put the most important element first. Under 20 words is under-specified.
- Order: subject and action, setting, light and color, camera and lens, style or medium.
- No negative prompt and no numeric weights: turn "avoid" terms into positive description. Never use quality tags.
- Exact colors can be given as hex codes (#RRGGBB). Text in the image goes in double quotes, with font, color and position.""",
    "krea_2": """- Write natural prose. The model has an aesthetic of its own (depth of field, color grading, rim light): do not over-specify technical parameters, and keep the subject layer and the style layer in separate sentences.
- Numeric weights are read as literal text: never use them.
- A negative prompt is supported but must stay minimal and targeted, naming only specific artifacts or objects to avoid.""",
    "qwen_image": """- Write natural prose like for FLUX. Excellent with text in the image (also Chinese and other scripts): put it in double quotes and state font, color and position.
- A negative prompt is supported: use it targeted by kind of defect, never as a generic list of low-quality words; if nothing specific has to be excluded, leave "negative" empty.
- You may end the prompt with the quality suffix "Ultra HD, 4k, cinematic composition".""",
    "qwen_image_2.1": """- Write one long paragraph (separate paragraphs only for a layout made of stacked regions), as an observer describing the finished picture in the present tense and the third person: no commands and no hype words (no "best quality", no "ultra HD", no "trending on ArtStation"); describe, do not praise.
- Begin with one sentence of roughly twenty words that names the kind of picture (photograph, poster, illustration, scene), its style, its subject and its backdrop with the palette.
- Then go through the frame in order, backdrop first. For a layout: the top area, then the middle from left to right, then the lower area. For a single subject: its pose and place in the frame, head and face, body and clothes, what it holds. Give every element a position in the frame (top left, bottom edge, to the right of the doorway, just behind the table) and use about ten such phrases, reaching the corners and the edges, not only the centre.
- Give the light a sentence of its own: where it comes from, how hard or soft it is, and what shadows and glints it makes.
- Describe colors with a qualifier (warm ochre, slate blue, dusty mauve) and say what things are made of and how they feel to the eye (oiled oak, hammered copper, rough plaster). Prefer a precise list to a collective word, and spell out small numbers.
- People: build, posture, gaze, expression, hair, each garment with its color and fabric; age loosely (a child, a young woman, an old man), never with a number of years.
- Any text that must appear goes in straight double quotes, in its own script, with weight, color and position; lettering that should not be legible is described as indistinct.
- Finish with a single sentence that sums up the picture as a whole (its balance, colors, style and atmosphere).
- Keep the scene physically plausible: shadows follow the light, reflections show what faces the surface.
- If the user wants a transparent background, say explicitly: an RGBA image with an alpha channel and a transparent background.
- There is no negative prompt (guidance 1): turn "avoid" terms into positive description.
(Provisional master prompt: its structure follows the model's own prompt enhancer, in our own words; to be reviewed against the model's documentation.)""",
    "z_image": """- This is a distilled turbo model with no negative prompt and no numeric weights. It likes long, detailed prompts: describe the scene in full.
- The very first sentence must be the style or medium (before the subject). Do not frame the image as "a photograph" or "a cinematic frame from a film": that framing overrides the style even in first position.
- Turn "avoid" terms into positive description.""",
    "sdxl": """- Start with one descriptive sentence, then a tail of comma-separated tags. The first words weigh the most. Quality boosters (masterpiece, best quality) still work.
- Numeric weights like (term:1.2) are allowed, sparingly.
- A negative prompt is recommended: a short comma-separated list of what to avoid (for example blurry, low quality, deformed hands) plus the terms the user marked as to avoid.""",
    "sd15": """- Tags only, comma-separated. Order is priority: the first tokens weigh the most, so start with the subject and the style.
- Weights like (term:1.2) are allowed, sparingly.
- A negative prompt is indispensable: a short comma-separated list (blurry, low quality, bad anatomy, extra limbs) plus the terms the user marked as to avoid.""",
    "ernie_image": """- Follow-the-letter model: write a complete prompt; the model does not enhance short prompts. Weights like (term:1.3) are supported.
- Text in the image: double quotes, the font style stated next to the text, an explicit position, short segments (8-10 words each).
- A negative prompt is supported but must stay targeted by kind of defect (deformed hands, blurred text), never a generic list of low-quality words.""",
    "hidream": """- Write natural prose, subject first, then setting, light, camera and style; put what matters most early, because only the first 128 tokens are read well. No quality tags, no numeric weights.
- Turn "avoid" terms into positive description.
(Provisional master prompt: to be reviewed against the model's documentation.)""",
    "anima": """- Mix a short tag line with natural language: begin with quality and meta tags, then the subject tags (Danbooru style, underscores between words), then one or two sentences in plain English for the scene.
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
    for fid, label, old, negative, words, ceiling, unit, why, provisional in FAMILIES:
        output = OUTPUT_JSON if negative else OUTPUT_TEXT
        length = LENGTH.format(words=words, unit=unit, max=ceiling, why=why)
        notes = length + "\n" + NOTES[NOTES_KEY[fid]]
        entry = {
            "label": label, "negative": negative, "hiddenCategories": hidden_categories(db, db["families"], old, negative),
            "words": words, "maxWords": ceiling, "lengthNote": why[0].upper() + why[1:] + ". " + EVIDENCE[fid],
            "system": COMMON.format(
                label=label, output=output, notes=notes, extras=EXTRAS_ENRICH if fid in ENRICHING else EXTRAS_STRICT),
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
    parser.add_argument("--source", default=DEFAULT_SOURCE, required=DEFAULT_SOURCE is None)
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
