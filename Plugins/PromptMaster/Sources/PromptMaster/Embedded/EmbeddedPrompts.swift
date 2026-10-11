// Hand-maintained: the plug-in's own prompt files as strings (a plug-in bundle holds only its library). The files in
// Data/prompt-master/ win when valid and not older; `Rules` carry the task, the family's text comes from the app.

enum EmbeddedPrompts {
  static let families = #"""
{
 "schema": 1,
 "version": "1.0.0",
 "families": {
  "flux1": {
   "hiddenCategories": [
    "negative_terms",
    "render_quality"
   ]
  },
  "flux2": {
   "hiddenCategories": [
    "negative_terms",
    "render_quality"
   ],
   "provisional": true
  },
  "flux2_9b": {
   "hiddenCategories": [
    "negative_terms",
    "render_quality"
   ]
  },
  "flux2_4b": {
   "hiddenCategories": [
    "negative_terms",
    "render_quality"
   ]
  },
  "krea_2": {
   "hiddenCategories": [
    "negative_terms",
    "render_quality"
   ]
  },
  "qwen_image": {
   "hiddenCategories": [
    "render_quality"
   ]
  },
  "qwen_image_2.1": {
   "hiddenCategories": [
    "negative_terms",
    "render_quality"
   ],
   "provisional": true
  },
  "z_image": {
   "hiddenCategories": [
    "negative_terms",
    "render_quality",
    "typography_text"
   ]
  },
  "sdxl_base_v0.9": {
   "hiddenCategories": [
    "typography_text"
   ],
   "booruSystem": "Tag mode is ON: output only comma-separated booru tags (underscores between words), no sentences. Begin with quality tags such as masterpiece, best quality, absurdres (for Pony models score_9, score_8_up, score_7_up).",
   "tags": true
  },
  "v1": {
   "hiddenCategories": [
    "typography_text"
   ],
   "booruSystem": "Tag mode is ON: output only comma-separated booru tags (underscores between words), no sentences. Begin with quality tags such as masterpiece, best quality.",
   "tags": true
  },
  "ernie_image": {
   "hiddenCategories": [
    "negative_terms",
    "render_quality"
   ]
  },
  "hidream_i1": {
   "hiddenCategories": [
    "negative_terms",
    "render_quality"
   ],
   "provisional": true
  },
  "cosmos2.5_2b": {
   "hiddenCategories": [
    "artist_classical",
    "artist_modern",
    "typography_text"
   ],
   "provisional": true,
   "tags": true
  }
 }
}
"""#

  static let compose = #"""
---
version: 1
---
You write prompts for the image model "{label}".

The user gives you a description of the image they want, in any language, and a list of terms in English taken from a vocabulary of photography, lighting, color, style and materials (some may be marked as things to avoid). Combine them into ONE final prompt that describes a single coherent image: keep every element of the description, use each term where it makes sense, and never contradict the description. Enrich the description: add concrete, visual detail (the setting, materials and textures, how the light falls, the atmosphere) so the prompt is vivid and specific, as long as every addition is consistent with the scene and the terms given and never contradicts them. Do not change the main subject, do not add text to be rendered and do not invent a story.
"""#

  static let composeTags = #"""
---
version: 1
---
You write prompts for the image model "{label}".

The user gives you a description of the image they want, in any language, and a list of terms in English taken from a vocabulary of photography, lighting, color, style and materials (some may be marked as things to avoid). Combine them into ONE final prompt that describes a single coherent image: keep every element of the description, use each term where it makes sense, and never contradict the description. Do not add subjects, text or a story the user did not ask for; you may add small connecting details that make the scene coherent.
"""#
}
