// Generated once by Scripts/make-prompt-guides.py from Prompt Master's master-prompts.json; edit by hand from here on.
import Foundation

/// What the app tells the LLM about one image-model family (a simplified Prompt Master master prompt).
public struct PromptGuide: Equatable, Sendable {
  public let label: String
  /// The family reads a negative prompt, so the LLM is asked for one too.
  public let usesNegative: Bool
  /// The "Model notes" bullet list, in English, without its heading.
  public let notes: String
}

public enum PromptGuides {
  /// Key = Draw Things `version` (`CatalogModel.family`).
  public static let all: [String: PromptGuide] = [
    "flux1": PromptGuide(
      label: "FLUX.1", usesNegative: false,
      notes: #"""
- Length: aim for 80-250 words. When the description and the terms need more room, go on, but never beyond 300 words: the text encoder (T5-XXL) reads 512 tokens, about 350 words, and drops the rest.
- Write natural, flowing prose in full sentences (T5 encoder: long relational sentences are fine).
- Order: subject and action first, then setting, then light and color, then camera and lens, then style or medium.
- Never use quality tags (masterpiece, 8k, best quality): they degrade the result. No numeric weights.
- There is no negative prompt: say in positive words what the image contains; turn "avoid" terms into a positive description.
- Text that must appear in the image goes in double quotes.
"""#),
    "flux2": PromptGuide(
      label: "FLUX.2 [dev]", usesNegative: false,
      notes: #"""
- Length: aim for 60-250 words. When the description and the terms need more room, go on, but never beyond 300 words: the text encoder reads 512 tokens, about 350 words, and drops the rest.
- Write natural prose. The text encoder reads the first elements most strongly, so put the most important element first. Under 20 words is under-specified.
- Order: subject and action, setting, light and color, camera and lens, style or medium.
- No negative prompt and no numeric weights: turn "avoid" terms into positive description. Never use quality tags.
- Exact colors can be given as hex codes (#RRGGBB). Text in the image goes in double quotes, with font, color and position.
"""#),
    "flux2_9b": PromptGuide(
      label: "FLUX.2 [klein] 9B", usesNegative: false,
      notes: #"""
- Length: aim for 60-250 words. When the description and the terms need more room, go on, but never beyond 300 words: the text encoder reads 512 tokens, about 350 words, and drops the rest.
- Write natural prose. The text encoder reads the first elements most strongly, so put the most important element first. Under 20 words is under-specified.
- Order: subject and action, setting, light and color, camera and lens, style or medium.
- No negative prompt and no numeric weights: turn "avoid" terms into positive description. Never use quality tags.
- Exact colors can be given as hex codes (#RRGGBB). Text in the image goes in double quotes, with font, color and position.
"""#),
    "flux2_4b": PromptGuide(
      label: "FLUX.2 [klein] 4B", usesNegative: false,
      notes: #"""
- Length: aim for 60-250 words. When the description and the terms need more room, go on, but never beyond 300 words: the text encoder reads 512 tokens, about 350 words, and drops the rest.
- Write natural prose. The text encoder reads the first elements most strongly, so put the most important element first. Under 20 words is under-specified.
- Order: subject and action, setting, light and color, camera and lens, style or medium.
- No negative prompt and no numeric weights: turn "avoid" terms into positive description. Never use quality tags.
- Exact colors can be given as hex codes (#RRGGBB). Text in the image goes in double quotes, with font, color and position.
"""#),
    "krea_2": PromptGuide(
      label: "Krea 2", usesNegative: true,
      notes: #"""
- Length: aim for 40-150 words. When the description and the terms need more room, go on, but never beyond 300 words: the conditioning is limited to 512 tokens, about 350 words, and a longer prompt can corrupt the picture.
- Write natural prose. The model has an aesthetic of its own (depth of field, color grading, rim light): do not over-specify technical parameters, and keep the subject layer and the style layer in separate sentences.
- Numeric weights are read as literal text: never use them.
- A negative prompt is supported but must stay minimal and targeted, naming only specific artifacts or objects to avoid.
"""#),
    "qwen_image": PromptGuide(
      label: "Qwen Image", usesNegative: true,
      notes: #"""
- Length: aim for 80-250 words. When the description and the terms need more room, go on, but never beyond 450 words: the text encoder reads about 1024 tokens, roughly 500 words, and the prompt is cut after that.
- Write natural prose like for FLUX. Excellent with text in the image (also Chinese and other scripts): put it in double quotes and state font, color and position.
- A negative prompt is supported: use it targeted by kind of defect, never as a generic list of low-quality words; if nothing specific has to be excluded, leave "negative" empty.
- You may end the prompt with the quality suffix "Ultra HD, 4k, cinematic composition".
"""#),
    "qwen_image_2.1": PromptGuide(
      label: "Qwen Image 2.1", usesNegative: false,
      notes: #"""
- Length: aim for 300-450 words. When the description and the terms need more room, go on, but never beyond 500 words: the text encoder reads about 1024 tokens, roughly 500 words, and the prompt is cut after that.
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
"""#),
    "z_image": PromptGuide(
      label: "Z Image", usesNegative: false,
      notes: #"""
- Length: aim for 100-250 words. When the description and the terms need more room, go on, but never beyond 300 words: the text encoder reads 512 tokens by default, about 350 words, and drops the rest.
- This is a distilled turbo model with no negative prompt and no numeric weights. It likes long, detailed prompts: describe the scene in full.
- The very first sentence must be the style or medium (before the subject). Do not frame the image as "a photograph" or "a cinematic frame from a film": that framing overrides the style even in first position.
- Turn "avoid" terms into positive description.
"""#),
    "sdxl_base_v0.9": PromptGuide(
      label: "Stable Diffusion XL", usesNegative: true,
      notes: #"""
- Length: aim for 30-55 words. When the description and the terms need more room, go on, but never beyond 60 words: each CLIP text encoder reads 77 tokens, about 55 words, and ignores the rest; commas and tags cost tokens too.
- Start with one descriptive sentence, then a tail of comma-separated tags. The first words weigh the most. Quality boosters (masterpiece, best quality) still work.
- Numeric weights like (term:1.2) are allowed, sparingly.
- A negative prompt is recommended: a short comma-separated list of what to avoid (for example blurry, low quality, deformed hands) plus the terms the user marked as to avoid.
"""#),
    "v1": PromptGuide(
      label: "Stable Diffusion 1.5", usesNegative: true,
      notes: #"""
- Length: aim for 20-35 tags. When the description and the terms need more room, go on, but never beyond 40 tags: CLIP reads 77 tokens and ignores the rest; every tag and every comma costs tokens.
- Tags only, comma-separated. Order is priority: the first tokens weigh the most, so start with the subject and the style.
- Weights like (term:1.2) are allowed, sparingly.
- A negative prompt is indispensable: a short comma-separated list (blurry, low quality, bad anatomy, extra limbs) plus the terms the user marked as to avoid.
"""#),
    "ernie_image": PromptGuide(
      label: "ERNIE-Image", usesNegative: true,
      notes: #"""
- Length: aim for 50-150 words. When the description and the terms need more room, go on, but never beyond 300 words: the prompt is limited to about 2048 characters, roughly 330 words.
- Follow-the-letter model: write a complete prompt; the model does not enhance short prompts. Weights like (term:1.3) are supported.
- Text in the image: double quotes, the font style stated next to the text, an explicit position, short segments (8-10 words each).
- A negative prompt is supported but must stay targeted by kind of defect (deformed hands, blurred text), never a generic list of low-quality words.
"""#),
    "hidream_i1": PromptGuide(
      label: "HiDream-I1", usesNegative: false,
      notes: #"""
- Length: aim for 40-90 words. When the description and the terms need more room, go on, but never beyond 150 words: the reference pipeline reads 128 tokens, about 90 words, by default, and some tools raise it to 256 tokens, about 150 words.
- Write natural prose, subject first, then setting, light, camera and style; put what matters most early, because only the first 128 tokens are read well. No quality tags, no numeric weights.
- Turn "avoid" terms into positive description.
"""#),
    "cosmos2.5_2b": PromptGuide(
      label: "Anima (Cosmos 2.5)", usesNegative: true,
      notes: #"""
- Length: aim for 30-120 words. When the description and the terms need more room, go on, but never beyond 300 words: the text conditioner works on 512 tokens, about 350 words.
- Mix a short tag line with natural language: begin with quality and meta tags, then the subject tags (Danbooru style, underscores between words), then one or two sentences in plain English for the scene.
- A negative prompt is supported: a short comma-separated list of what to avoid.
"""#),
  ]

  public static func guide(for family: String?) -> PromptGuide? {
    family.flatMap { all[$0] }
  }
}
