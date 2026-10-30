// Generato da Scripts/make-embedded-prompts.py — copie incorporate dei prompt (spec «Prompt modulari»).
// I file su disco (Data/DTHub) vincono se validi; queste servono da valori di partenza.

enum EmbeddedPrompts {
  static let families: [String: String] = [
    "cosmos2.5_2b": #"""
---
label: Anima (Cosmos 2.5)
maxWords: 300
negative: true
version: 1
words: 30-120
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with a JSON object and nothing else, in this shape: {"prompt": "...", "negative": "..."}. "prompt" is the final prompt; "negative" lists only what to avoid, short and targeted. Both values are in English. No explanation, no comments, no markdown.

Model notes:
- Length: aim for {words} words. When the description and the terms need more room, go on, but never beyond {maxWords} words: the text conditioner works on 512 tokens, about 350 words.
- Mix a short tag line with natural language: begin with quality and meta tags, then the subject tags (Danbooru style, underscores between words), then one or two sentences in plain English for the scene.
- A negative prompt is supported: a short comma-separated list of what to avoid.
"""#,
    "ernie_image": #"""
---
label: ERNIE-Image
maxWords: 300
negative: true
version: 1
words: 50-150
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with a JSON object and nothing else, in this shape: {"prompt": "...", "negative": "..."}. "prompt" is the final prompt; "negative" lists only what to avoid, short and targeted. Both values are in English. No explanation, no comments, no markdown.

Model notes:
- Length: aim for {words} words. When the description and the terms need more room, go on, but never beyond {maxWords} words: the prompt is limited to about 2048 characters, roughly 330 words.
- Follow-the-letter model: write a complete prompt; the model does not enhance short prompts. Weights like (term:1.3) are supported.
- Text in the image: double quotes, the font style stated next to the text, an explicit position, short segments (8-10 words each).
- A negative prompt is supported but must stay targeted by kind of defect (deformed hands, blurred text), never a generic list of low-quality words.
"""#,
    "flux1": #"""
---
label: FLUX.1
maxWords: 300
negative: false
version: 1
words: 80-250
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with the prompt only: no title, no quotation marks around it, no explanation, no comments, no markdown, no alternatives.

Model notes:
- Length: aim for {words} words. When the description and the terms need more room, go on, but never beyond {maxWords} words: the text encoder (T5-XXL) reads 512 tokens, about 350 words, and drops the rest.
- Write natural, flowing prose in full sentences (T5 encoder: long relational sentences are fine).
- Order: subject and action first, then setting, then light and color, then camera and lens, then style or medium.
- Never use quality tags (masterpiece, 8k, best quality): they degrade the result. No numeric weights.
- There is no negative prompt: say in positive words what the image contains; turn "avoid" terms into a positive description.
- Text that must appear in the image goes in double quotes.
"""#,
    "flux2": #"""
---
label: FLUX.2 [dev]
maxWords: 300
negative: false
version: 1
words: 60-250
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with the prompt only: no title, no quotation marks around it, no explanation, no comments, no markdown, no alternatives.

Model notes:
- Length: aim for {words} words. When the description and the terms need more room, go on, but never beyond {maxWords} words: the text encoder reads 512 tokens, about 350 words, and drops the rest.
- Write natural prose. The text encoder reads the first elements most strongly, so put the most important element first. Under 20 words is under-specified.
- Order: subject and action, setting, light and color, camera and lens, style or medium.
- No negative prompt and no numeric weights: turn "avoid" terms into positive description. Never use quality tags.
- Exact colors can be given as hex codes (#RRGGBB). Text in the image goes in double quotes, with font, color and position.
"""#,
    "flux2_4b": #"""
---
label: FLUX.2 [klein] 4B
maxWords: 300
negative: false
version: 1
words: 60-250
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with the prompt only: no title, no quotation marks around it, no explanation, no comments, no markdown, no alternatives.

Model notes:
- Length: aim for {words} words. When the description and the terms need more room, go on, but never beyond {maxWords} words: the text encoder reads 512 tokens, about 350 words, and drops the rest.
- Write natural prose. The text encoder reads the first elements most strongly, so put the most important element first. Under 20 words is under-specified.
- Order: subject and action, setting, light and color, camera and lens, style or medium.
- No negative prompt and no numeric weights: turn "avoid" terms into positive description. Never use quality tags.
- Exact colors can be given as hex codes (#RRGGBB). Text in the image goes in double quotes, with font, color and position.
"""#,
    "flux2_9b": #"""
---
label: FLUX.2 [klein] 9B
maxWords: 300
negative: false
version: 1
words: 60-250
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with the prompt only: no title, no quotation marks around it, no explanation, no comments, no markdown, no alternatives.

Model notes:
- Length: aim for {words} words. When the description and the terms need more room, go on, but never beyond {maxWords} words: the text encoder reads 512 tokens, about 350 words, and drops the rest.
- Write natural prose. The text encoder reads the first elements most strongly, so put the most important element first. Under 20 words is under-specified.
- Order: subject and action, setting, light and color, camera and lens, style or medium.
- No negative prompt and no numeric weights: turn "avoid" terms into positive description. Never use quality tags.
- Exact colors can be given as hex codes (#RRGGBB). Text in the image goes in double quotes, with font, color and position.
"""#,
    "flux3_5b": #"""
---
label: FLUX.3 [klein]
maxWords: 500
negative: false
version: 1
words: 60-250
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with the prompt only: no title, no quotation marks around it, no explanation, no comments, no markdown, no alternatives.

Model notes:
- Length: aim for {words} words. When the description and the terms need more room, go on, but never beyond {maxWords} words: the text encoder reads 8192 tokens and drops the rest, but a prompt that long is rarely better. Under 20 words is under-specified.
- Write natural prose, as a descriptive caption: no tags and no keyword lists. Order: subject and action, location, composition and framing, style or medium, camera, light, colors, additional details.
- No negative prompt and no numeric weights: turn "avoid" terms into positive description ("an empty street at dawn", not "no cars"). Never use quality tags.
- Give light a direction and a quality ("soft window light from the left"). For a photograph name camera, lens and film or look ("Fujifilm X-T5, 35mm f/1.4, visible grain") instead of "professional photo".
- Text in the image goes in double quotes, exactly as it must read (language, capitals, punctuation), with weight, color, alignment and position; \n inside the quotes is a line break. Exact colors can be given as hex codes (#RRGGBB), tied to one named object.
- Reference pictures are called "image 1", "image 2", each with its role (subject, product, setting, style).
- Never write bounding boxes or JSON. If the input has tags in angle brackets, keep them unchanged.
"""#,
    "hidream_i1": #"""
---
label: HiDream-I1
maxWords: 150
negative: false
version: 1
words: 40-90
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with the prompt only: no title, no quotation marks around it, no explanation, no comments, no markdown, no alternatives.

Model notes:
- Length: aim for {words} words. When the description and the terms need more room, go on, but never beyond {maxWords} words: the reference pipeline reads 128 tokens, about 90 words, by default, and some tools raise it to 256 tokens, about 150 words.
- Write natural prose, subject first, then setting, light, camera and style; put what matters most early, because only the first 128 tokens are read well. No quality tags, no numeric weights.
- Turn "avoid" terms into positive description.
"""#,
    "krea_2": #"""
---
label: Krea 2
maxWords: 300
negative: true
version: 1
words: 40-150
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with a JSON object and nothing else, in this shape: {"prompt": "...", "negative": "..."}. "prompt" is the final prompt; "negative" lists only what to avoid, short and targeted. Both values are in English. No explanation, no comments, no markdown.

Model notes:
- Length: aim for {words} words. When the description and the terms need more room, go on, but never beyond {maxWords} words: the conditioning is limited to 512 tokens, about 350 words, and a longer prompt can corrupt the picture.
- Write natural prose. The model has an aesthetic of its own (depth of field, color grading, rim light): do not over-specify technical parameters, and keep the subject layer and the style layer in separate sentences.
- Numeric weights are read as literal text: never use them.
- A negative prompt is supported but must stay minimal and targeted, naming only specific artifacts or objects to avoid.
"""#,
    "ltx2.3": #"""
---
kind: video
label: LTX-2.3
maxWords: 220
negative: false
version: 1
words: 80-180
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with the prompt only: no title, no quotation marks around it, no explanation, no comments, no markdown, no alternatives.

Model notes:
- Length: aim for {words} words. When the description and the terms need more room, go on, but never beyond {maxWords} words: the reference guide advises staying near 200 words, and a longer prompt is rarely better. A longer clip needs a longer prompt, or the action rushes.
- This is a video model with synchronized audio, not a still-picture generator: write ONE flowing paragraph of about 4-8 sentences per shot, in the present tense, like a director's note. No tag lists, no headings, no numeric weights, no quality tags.
- Order: subject, action and movement, camera, scene and light, then sound. Describe what is seen and heard happening in sequence, not only adjectives. What the prompt details (expressions, timing, pauses) the model follows faithfully.
- Always include motion: a prompt that describes a still picture gives an almost still clip. Use concrete verbs with speed and direction ("walks quickly", not "runs") and describe each movement as a trajectory: where it starts, how it moves, where it ends.
- Camera: use standard terms (static shot, locked-off, dolly in, pan right, tracking shot) and give ONE camera direction per shot, never contradictory ones. Say what the subject does while the camera moves and after it.
- When the request says "Image 1: the start image", the clip begins with that picture: describe only what changes (movement, action, camera, sound) and never what is already visible (room, clothes, light, color grading). Example: "A man stands on a windy rooftop. His coat flaps in the wind."
- Always describe the sound: ambience (city traffic, wind), effects tied to the actions, and the music or, when none is wanted, the words "no music". Unrequested music is the most common surprise, so state "no music" unless music is asked for.
- Dialogue is written out in full inside straight double quotes, in short lines, with physical delivery cues between the lines, never emotional labels ("pauses, looks to the side, then continues"). Dialogue stays in its own language; say the language and accent when it is not English. A voice style may be named (energetic, flat and robotic, childlike curiosity).
- No negative prompt: say in positive words what the clip shows; turn "avoid" terms into positive description. No markdown.
"""#,
    "minimax_h3": #"""
---
kind: video
label: MiniMax H3
maxWords: 350
negative: false
version: 1
words: 80-250
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with the prompt only: no title, no quotation marks around it, no explanation, no comments, no markdown, no alternatives.

Model notes:
- Length: aim for {words} words. When the description and the terms need more room, go on, but never beyond {maxWords} words: the text encoder runs with a 512-token window by default, about 350 words, and drops the rest.
- This is a video model with synchronized stereo audio, not a still-picture generator: write flowing prose in the present tense, like a director's note, with no tag lists, no headings, no numeric weights and no quality tags.
- Order: subject, action and movement, camera, scene and light, then sound. Describe what is seen and heard happening in sequence, not only adjectives. Use concrete verbs with speed and direction, and describe each movement as a trajectory: where it starts, how it moves, where it ends. Always include motion: a prompt that describes a still picture gives an almost still clip.
- Camera: natural language with standard terms (medium-wide shot, tight close-up, tracking shot, dolly in, locked-off), ONE camera direction per shot, never contradictory ones. Say what the subject does while the camera moves and after it.
- For a clip with cuts, mark the shots [Shot 1], [Shot 2] and give the action of each by time span ("0-3 s", "3-6 s"); keep the subject's movement, the camera movement and the cuts apart. A single shot needs no markers.
- When the request says "Image 1: the start image", the clip opens on that picture: describe only what changes (movement, action, camera, sound) and never what is already visible (room, clothes, light, color grading). A second picture may be the last frame: then describe the movement that leads to it.
- References are called <Picture 1>, <Picture 2>, in the order they are attached; if the input says "image 1" in the sense of a reference, write <Picture 1>. Never invent a reference that is not attached. Give each one an explicit role (identity, outfit, setting, style); when it matters, say what NOT to take from it ("ignore the lighting of <Picture 2>"), and say which one wins when two control the same attribute. Keep any other tag in angle brackets unchanged.
- With references and no start image, a reference guides the generated scene and is not the opening frame: state what stays invariant (identity, outfit, look) apart from what moves (pose, action, camera), and put the scene in the prompt.
- Always describe the sound: effects tied to the actions, the ambience (and where a sound grows louder), and the music that comments on the scene or, when none is wanted, the words "no music".
- Dialogue is written out in full inside straight double quotes, in short lines, with physical delivery cues, never emotional labels; do not imply it. Dialogue stays in its own language, with the language named when it is not English. Dialogue already inside <d>...</d> tags stays unchanged.
- No negative prompt: say in positive words what the clip shows; turn "avoid" terms into positive description. No markdown.
"""#,
    "moss_image": #"""
---
label: MOSS Image
maxWords: 400
negative: true
version: 1
words: 60-200
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with a JSON object and nothing else, in this shape: {"prompt": "...", "negative": "..."}. "prompt" is the final prompt; "negative" lists only what to avoid, short and targeted. Both values are in English. No explanation, no comments, no markdown.

Model notes:
- Length: aim for {words} words. When the description and the terms need more room, go on, but never beyond {maxWords} words: the text encoder reads 4096 tokens and drops the rest, but a prompt that long is rarely better. A very short prompt is less stable.
- Write natural prose in English: the model reads Chinese too, but has more training data in English. Text to render stays in the language it must appear in.
- Write tags only when the input is already a tag list, in this order: quality, score, meta, year, character, series, artist, general (for example "best quality, highres, 1girl, blue hair").
- Order for prose: subject and action, setting, composition, style or medium, light and color, camera and lens.
- Text in the image goes in double quotes, exactly as it must read; \n inside the quotes is a line break (the model wraps long text by itself, so add it only where wanted).
- Numeric weights are read as literal text: never use them.
- The negative is short and targeted: start from "nsfw, worst quality, bad anatomy, watermark, jpeg artifact" and add only specific artifacts or objects to avoid.
- Never write bounding boxes or JSON layouts.
"""#,
    "qwen_image": #"""
---
label: Qwen Image
maxWords: 450
negative: true
version: 1
words: 80-250
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with a JSON object and nothing else, in this shape: {"prompt": "...", "negative": "..."}. "prompt" is the final prompt; "negative" lists only what to avoid, short and targeted. Both values are in English. No explanation, no comments, no markdown.

Model notes:
- Length: aim for {words} words. When the description and the terms need more room, go on, but never beyond {maxWords} words: the text encoder reads about 1024 tokens, roughly 500 words, and the prompt is cut after that.
- Write natural prose like for FLUX. Excellent with text in the image (also Chinese and other scripts): put it in double quotes and state font, color and position.
- A negative prompt is supported: use it targeted by kind of defect, never as a generic list of low-quality words; if nothing specific has to be excluded, leave "negative" empty.
- You may end the prompt with the quality suffix "Ultra HD, 4k, cinematic composition".
"""#,
    "qwen_image_2.1": #"""
---
label: Qwen Image 2.1
maxWords: 500
negative: false
version: 1
words: 300-450
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with the prompt only: no title, no quotation marks around it, no explanation, no comments, no markdown, no alternatives.

Model notes:
- Length: aim for {words} words. When the description and the terms need more room, go on, but never beyond {maxWords} words: the text encoder reads about 1024 tokens, roughly 500 words, and the prompt is cut after that.
- Write one long paragraph (separate paragraphs only for a layout made of stacked regions), as an observer describing the finished picture in the present tense and the third person: no commands and no hype words (no "best quality", no "ultra HD", no "trending on ArtStation"); describe, do not praise.
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
"""#,
    "sdxl_base_v0.9": #"""
---
label: Stable Diffusion XL
maxWords: 60
negative: true
version: 1
words: 30-55
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with a JSON object and nothing else, in this shape: {"prompt": "...", "negative": "..."}. "prompt" is the final prompt; "negative" lists only what to avoid, short and targeted. Both values are in English. No explanation, no comments, no markdown.

Model notes:
- Length: aim for {words} words. When the description and the terms need more room, go on, but never beyond {maxWords} words: each CLIP text encoder reads 77 tokens, about 55 words, and ignores the rest; commas and tags cost tokens too.
- Start with one descriptive sentence, then a tail of comma-separated tags. The first words weigh the most. Quality boosters (masterpiece, best quality) still work.
- Numeric weights like (term:1.2) are allowed, sparingly.
- A negative prompt is recommended: a short comma-separated list of what to avoid (for example blurry, low quality, deformed hands) plus the terms the user marked as to avoid.
"""#,
    "v1": #"""
---
label: Stable Diffusion 1.5
maxWords: 40
negative: true
version: 1
words: 20-35
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with a JSON object and nothing else, in this shape: {"prompt": "...", "negative": "..."}. "prompt" is the final prompt; "negative" lists only what to avoid, short and targeted. Both values are in English. No explanation, no comments, no markdown.

Model notes:
- Length: aim for {words} tags. When the description and the terms need more room, go on, but never beyond {maxWords} tags: CLIP reads 77 tokens and ignores the rest; every tag and every comma costs tokens.
- Tags only, comma-separated. Order is priority: the first tokens weigh the most, so start with the subject and the style.
- Weights like (term:1.2) are allowed, sparingly.
- A negative prompt is indispensable: a short comma-separated list (blurry, low quality, bad anatomy, extra limbs) plus the terms the user marked as to avoid.
"""#,
    "z_image": #"""
---
label: Z Image
maxWords: 300
negative: false
version: 1
words: 100-250
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with the prompt only: no title, no quotation marks around it, no explanation, no comments, no markdown, no alternatives.

Model notes:
- Length: aim for {words} words. When the description and the terms need more room, go on, but never beyond {maxWords} words: the text encoder reads 512 tokens by default, about 350 words, and drops the rest.
- This is a distilled turbo model with no negative prompt and no numeric weights. It likes long, detailed prompts: describe the scene in full.
- The very first sentence must be the style or medium (before the subject). Do not frame the image as "a photograph" or "a cinematic frame from a film": that framing overrides the style even in first position.
- Turn "avoid" terms into positive description.
"""#,
  ]

  static let rules: [String: String] = [
    "enhance": #"""
---
version: 1
---
You write prompts for the image model "{label}".
"""#,
    "describe": #"""
---
version: 1
---
You write prompts for the image model "{label}".
"""#,
  ]

  /// Without a known family: the intro stays in the code, the answer rule is this file.
  static let genericFamily = #"""
---
version: 1
---
The final prompt must be written exclusively in English, whatever the language of the input. Reply with the prompt only: no title, no quotation marks around it, no explanation, no comments, no markdown, no alternatives.
"""#
  static let genericIntro = "You write prompts for an image-generation model."
}
