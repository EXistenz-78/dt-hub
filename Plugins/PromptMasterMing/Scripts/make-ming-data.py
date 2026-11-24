#!/usr/bin/env python3
"""make-ming-data.py — costruisce i dati del plug-in Prompt Master Ming.

Il vocabolario è quello di Prompt Master, incorporato una volta sola per tutti (PromptMasterShared/Scripts/pm_data.py).
Il resto si scrive qui: le categorie nascoste e quelle solo-Foto / solo-Arte, quelle della luce (vanno in
`ambient_lighting`, le altre in `image_style`), le opzioni dell'LLM, il master prompt (riscrittura dei testi) e il prompt di
composizione (tutto il JSON da un'idea: la copia del Family prompt Ming dell'app, usata quando l'app non manda il suo).
Scrive, sotto Plugins/PromptMasterMing:
  Data/ming.json              configurazione
  Data/master-prompt.md       il master prompt (Markdown)
  Data/compose-prompt.md      il prompt di composizione (Markdown)
  Sources/PromptMasterMing/Embedded/EmbeddedData.swift   i tre file come stringhe Swift (un bundle non ha risorse)
Si lancia da qualsiasi cartella; l'uscita è deterministica.
"""
import os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "PromptMasterShared", "Scripts"))
import pm_data

CONFIG_VERSION = "1.0.0"
# Ming non legge un negativo; pose ed espressioni descrivono un livello, non lo stile dell'immagine.
HIDDEN_CATEGORIES = ["negative_terms", "pose_gesture", "expression_gaze"]
PHOTO_ONLY = ["framing", "camera_angle", "composition", "lens_focus", "photo_genre", "film_stock_process", "optical_fx"]
ART_ONLY = ["medium_paint_draw", "medium_print_craft", "art_movement", "design_movement", "anime_cartoon_style",
            "cultural_tradition", "artist_classical", "artist_modern", "artist_illustration"]
# Le voci della luce vanno in canvas_settings.ambient_lighting; tutte le altre in image_style.
LIGHTING_CATEGORIES = ["light_source", "light_quality", "light_scheme"]
OPTIONS = {"temperature": 0.6, "maxTokens": 8192, "thinking": False, "timeout": 900}

SYSTEM = """You prepare the texts of a structured design prompt for the image model Ming-Image. The request has blocks under titles: "image_style" (the style or medium of the whole picture), "ambient_lighting" (the light of the whole picture), one "layer N (kind)" block per layer, where kind is object or text, and "relation N" blocks (how layer N sits with the others). A "text" layer is lettering printed in the picture: its exact words are set apart and never shown to you.

Answer with the SAME titles in the SAME order, each followed by its rewritten text. Nothing else: no JSON, no notes.

Rules:
1. Every text you write MUST be in English, whatever language the input is in. If the input is Italian or any other language, TRANSLATE it: never answer in the language of the input. No commands, no markdown.
2. Words between quotation marks are printed in the picture: copy them exactly, never translate.
3. "image_style": one short phrase or sentence naming the style or medium in the request's own terms (for a photograph: camera, lens, film or sensor). Work the lines shaped like "Category: term" into it. The style the user names wins: a photo stays a photo, never an illustration.
4. "ambient_lighting": one short phrase about the light of the whole picture; work the "Category: term" lines into it.
5. "layer N (object)": one full sentence a designer could build from: what the part is made of, its colors, what sits where inside it. Described in the medium of "image_style". No coordinates.
6. "layer N (text)": describe only the look of the lettering (font, weight, color, effects, the surface it is on), never the words themselves; start with the typography, for example "bold white condensed sans-serif with a soft glow".
7. "relation N": one plain sentence about ownership, alignment, containment or stacking ("centered above the product", "inside the top card"); never quote printed words.
8. Do not invent new layers.

Example. Request:
## image_style
poster minimal, stile vettoriale piatto
Color Palette: Pastel colors

## ambient_lighting
luce morbida da studio

## layer 1 (object)
sfondo crema pieno

## layer 2 (text)
scritta grande blu in alto

## relation 2
sopra al prodotto

Reply in English, in exactly this shape, replacing the dots with the English text:
## image_style
...

## ambient_lighting
...

## layer 1 (object)
...

## layer 2 (text)
...

## relation 2
...

Correct reply (note: everything is in English):
## image_style
Minimal flat vector poster with a soft pastel palette.

## ambient_lighting
Soft, even studio light with no harsh shadows.

## layer 1 (object)
A solid cream background that fills the whole canvas edge to edge.

## layer 2 (text)
Large bold rounded sans-serif lettering in deep blue, flat and clean.

## relation 2
Centered at the top, above the product."""

# La copia del Family prompt Ming dell'app (Packages/Sources/HubCore/Prompts/EmbeddedPrompts.swift, versione 3), ridotta
# al caso del plug-in: sempre il JSON, mai la prosa (trasparenza ed editing non passano dal plug-in).
COMPOSE = """The final prompt must be written exclusively in English, whatever the language of the input. Reply with the JSON only: no title, no explanation, no comments, no markdown, no code fence, no alternatives.

Model notes:
- Ming-Image is a design model: posters, flyers, ads, covers, menus, UI and game screens, infographics, logos, stickers and lettering, in styles from flat vector and modern minimal to neon and clean 3D. It also makes photographs and photographic scenes; a photo asked for stays a photo (see Style). Length: aim for 200-700 words, never beyond 1200.
- Format. Write ONE structured JSON object: it starts with { and ends with }, with no comment. Exactly two top-level keys: "canvas_settings" and "layers". "canvas_settings" has exactly "aspect_ratio", "ambient_lighting" and "image_style". "layers" lists the visible groups from the background to the topmost overlay; every layer has exactly "description", "coordinates", "hierarchy_and_relation" and "color_specs" (an array of hex colors).
- Canvas. The canvas IS the design: a poster, flyer, cover, menu, screen or banner fills the picture edge to edge and its first layer is the design's own background, described as what fills the whole canvas. Never show it as an object on something else (paper on a table, a phone around a screen, a floating card) unless a mockup or a named object (a can, a bag, a t-shirt) is asked for. A screen or menu faces the viewer flat, never in perspective. "aspect_ratio" is the one the request gives. Lay out every layer for that shape and spread the design over the whole canvas, with even margins.
- Coordinates. "coordinates" is one string in exactly this form: "cx: 0.500, cy: 0.500, w: 1.000, h: 1.000" (normalized, the box around the whole object). Except for the background, keep cx - w/2 and cy - h/2 at 0.030 or more, cx + w/2 at 0.970 or less and cy + h/2 at 0.950 or less: Ming cuts off what touches the bottom edge. Parts that must both be seen whole do not overlap.
- Layers. A layer is one visible group: the background, a whole person, a coherent object, a panel, a card, a row or a block of text. Use the fewest layers that keep the layout; never an invisible, empty or duplicate layer. Every description is a full sentence a designer could build from: what the part is made of, its colors, what sits where inside it and the style of any text in it; a vaguely described area gets marks and text of Ming's own. "hierarchy_and_relation" is one plain sentence in quotes (ownership, alignment, containment, stacking), never an object or a list.
- Text. A layer that shows text is described as: A text element reading exactly \\"THE WORDS\\" in <the look of the lettering>. The words are written out in full in the one layer that shows them, once in the whole prompt, and never in "hierarchy_and_relation" (point to it in plain words, "below the title"). Keep the user's words exactly, spelling and capitals included; commas and full stops that only separate items are not part of the words. Text whose words are not given comes out as gibberish, so list every word that will be visible. Add only a few short words (one to four) that a design of that kind always needs: a button label, a one-line subtitle, the labels of a chart or screen, the plain names of dishes, plans or fighters the request asked for without naming. Never invent a proper name, a brand, an event detail (hours, prices, ages), a web address, email, phone number, handle, QR code, barcode, address, fine print or a caption: Ming garbles them. Never turn a letter into an icon. A button, tab or label shows only its words, no icon, unless icons are asked for.
- Counts and structure. When the request gives a number of items (four fighters, six icons, three plans), draw exactly that many, one layer each, whole and inside the frame. Repeated items (icons, cards, buttons, rows) sit at equal steps and fill their area with no empty row or column: six items are two rows of three; for two rows the centres sit at 0.25 and 0.75 of the area, for three rows at 1/6, 1/2 and 5/6. Say each position in its description ("top row, left"). A table is one layer per card or per body row, every header and cell listed.
- Style. The style or medium the request names wins over everything else and over Ming's design habits; "image_style" states it in the request's own terms, and every layer is described in that medium. A photograph ("photo", "photograph", "photographic", "cinematographic photo", "film still", "shot on 35mm", "realistic", "DSLR") stays a photograph: "image_style" names photography with camera, lens, light and film or sensor ("cinematic film photograph, 35mm lens, shallow depth of field, natural moonlight, fine film grain, photorealistic"), people and things are described as real (skin, fabric, petals, grass), and the words illustration, digital art, painting, drawing, stylized, render, CGI, vector and poster aesthetic never appear. "Cinematic" or "cinematographic" means film-like framing, light and color grading, never an illustration. A painting, watercolor, anime, comic, vector or 3D look asked for stays that medium in the same way. Only when the request names no style, choose one that suits the idea.
- Style words. "Clean", "simple", "minimal", "fewer details" mean at most six layers, large empty space and no decoration (no icons, textures, glows, grids, extra panels); the theme is carried by shapes, colors and font. "Only one" means exactly one. "Solid" or "plain" background is one flat color with nothing on it. An accent color asked for appears on the parts that carry the design (buttons, borders, glow, title). For a 3D look (3D, Pixar, clay, toy) write the material and light in "image_style" and describe every character and object as a 3D object; leave out cartoon, illustration, drawing, painted, flat and textured. Letters built as 3D objects (clay, glossy plastic, chrome, balloons) hold one short word of up to six letters per line; set any longer phrase as flat printed text in its own layer. When a brand mark is needed and none is given, describe a simple wordless shape.
- Changes. When the request gives the current layout (a JSON), it is a change to it: a small change (a color, one word, one position) copies the JSON and changes only that, everywhere it appears; removing something deletes every phrase that describes it, in every layer. A big change keeps the subject, the theme, every word in the picture and every earlier choice, and rebuilds the layers and coordinates for the new brief.
- There is no negative prompt: say in positive words what the piece shows."""


if __name__ == "__main__":
    config = {"schema": 1, "version": CONFIG_VERSION, "hiddenCategories": HIDDEN_CATEGORIES, "photoOnly": PHOTO_ONLY,
              "artOnly": ART_ONLY, "lightingCategories": LIGHTING_CATEGORIES, "options": OPTIONS}
    pm_data.write_plugin_data("PromptMasterMing", "make-ming-data.py", "ming", config, 1, SYSTEM)
    # Il prompt di composizione: un file in più, aggiunto in coda ai dati incorporati.
    folder = os.path.join(pm_data.PLUGINS, "PromptMasterMing")
    compose_text = "---\nversion: 1\n---\n" + COMPOSE
    with open(os.path.join(folder, "Data", "compose-prompt.md"), "w") as out:
        out.write(compose_text + "\n")
    swift = os.path.join(folder, "Sources", "PromptMasterMing", "Embedded", "EmbeddedData.swift")
    text = open(swift).read().rstrip("\n")
    assert text.endswith("}")
    text = text[:-1] + "\n" + pm_data.swift_literal("composePrompt", compose_text) + "}\n"
    with open(swift, "w") as out:
        out.write(text)
    print(f"ming {CONFIG_VERSION}: luce {len(LIGHTING_CATEGORIES)}, solo-Foto {len(PHOTO_ONLY)}, solo-Arte {len(ART_ONLY)}, nascoste {HIDDEN_CATEGORIES}")
