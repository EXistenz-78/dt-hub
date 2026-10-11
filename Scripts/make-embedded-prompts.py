#!/usr/bin/env python3
"""Genera Packages/Sources/HubCore/Prompts/EmbeddedPrompts.swift (Rules e Family prompt incorporati, in MD).

Una tantum: parte da PromptGuides.swift (note di famiglia) e dal master-prompts.json di Prompt Master (words/maxWords).
Fallisce se, risolti i segnaposto, il testo di una famiglia non coincide con quello di PromptGuides.
Uso: python3 Scripts/make-embedded-prompts.py
"""
import json, re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
guides_src = (root / "Packages/Sources/HubCore/PromptAssist/PromptGuides.swift").read_text()
brief_src = (root / "Packages/Sources/HubCore/PromptAssist/PromptBrief.swift").read_text()
pm = (root / "Plugins/PromptMaster/Sources/PromptMaster/Embedded/EmbeddedData.swift").read_text()
i = pm.index('static let masterPrompts = #"""')
j = pm.index('"""#', i)
masters = json.loads(pm[i + len('static let masterPrompts = #"""'):j])["families"]

prose = re.search(r'proseRule =\s*\n?\s*"((?:[^"\\]|\\.)*)"', brief_src).group(1)
jsonr = re.search(r'jsonRule =\s*\n?\s*"((?:[^"\\]|\\.)*)"', brief_src).group(1)
unescape = lambda s: s.replace('\\"', '"')
prose, jsonr = unescape(prose), unescape(jsonr)

guides = {}
for m in re.finditer(r'^    "([^"]+)": PromptGuide\(\s*\n\s*label: "([^"]+)", usesNegative: (true|false),\s*\n\s*notes: #"""\n(.*?)\n"""#\)', guides_src, re.M | re.S):
    guides[m.group(1)] = dict(label=m.group(2), negative=m.group(3), notes=m.group(4))
if len(guides) != 13:
    sys.exit(f"attese 13 famiglie, trovate {len(guides)}")

out = ['// Generato da Scripts/make-embedded-prompts.py — copie incorporate dei prompt (spec «Prompt modulari»).',
       '// I file su disco (Data/DTHub) vincono se validi; queste servono da valori di partenza.', '',
       'enum EmbeddedPrompts {', '  static let families: [String: String] = [']
for key in sorted(guides):
    g = guides[key]
    words, maxw = masters[key]["words"], str(masters[key]["maxWords"])
    notes = g["notes"]
    new, n1 = re.subn(r'aim for ' + re.escape(words) + r' (words|tags)', r'aim for {words} \1', notes, count=1)
    new, n2 = re.subn(r'never beyond ' + re.escape(maxw) + r' (words|tags)', r'never beyond {maxWords} \1', new, count=1)
    if n1 != 1 or n2 != 1:
        sys.exit(f"{key}: frasi di lunghezza non trovate (words={words}, maxWords={maxw}, n={n1},{n2})")
    if new.replace('{words}', words).replace('{maxWords}', maxw) != notes:
        sys.exit(f"{key}: il testo risolto non coincide")
    rule = jsonr if g["negative"] == "true" else prose
    body = f"{rule}\n\nModel notes:\n{new}"
    text = (f"---\nlabel: {g['label']}\nmaxWords: {maxw}\nnegative: {g['negative']}\nversion: 1\nwords: {words}\n---\n{body}")
    out.append(f'    "{key}": #"""\n{text}\n"""#,')
out.append('  ]\n')
rules = "---\nversion: 1\n---\nYou write prompts for the image model \"{label}\"."
out.append('  static let rules: [String: String] = [')
for name in ("enhance", "describe"):
    out.append(f'    "{name}": #"""\n{rules}\n"""#,')
out.append('  ]\n')
out.append('  /// Without a known family: the intro stays in the code, the answer rule is this file.')
out.append(f'  static let genericFamily = #"""\n---\nversion: 1\n---\n{prose}\n"""#')
out.append('  static let genericIntro = "You write prompts for an image-generation model."')
out.append('}')
(root / "Packages/Sources/HubCore/Prompts/EmbeddedPrompts.swift").write_text("\n".join(out) + "\n")
print("ok", len(guides))
