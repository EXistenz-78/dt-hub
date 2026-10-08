#!/usr/bin/env python3
"""Extract the two prompt texts of a ComfyUI character-sheet workflow for the Character Sheet plug-in.

The workflow's texts are their author's, so they are not part of this repository: this script copies them from your
own copy of the workflow into the plug-in's data folder, where you can edit them freely.

    python3 Scripts/extract-from-workflow.py --source Character_Sheet_Production.json [--out FOLDER] [--force]

Writes `master-prompt.txt` (the system prompt of the "Prompt Template (Important)" node) and `static-prompt.txt`
(the other long text of the "Character Sheet Prompt Maker" sub-graph, with a {{name}} placeholder for the name).
"""
import argparse
import json
import os
import sys

SUBGRAPH = "Character Sheet Prompt Maker"
MASTER_TITLE = "Prompt Template (Important)"
NAME_PHRASE = 'Extract character name (or use "CHARACTER")'
NAME_PLACEHOLDER = 'Character name "{{name}}"'
DEFAULT_OUT = os.path.expanduser("~/Library/Application Support/DT Hub/Data/CharacterSheet")


def fail(message: str) -> None:
    sys.exit(f"error: {message}")


def long_texts(source: str) -> tuple[str, str]:
    try:
        with open(source, encoding="utf-8") as handle:
            workflow = json.load(handle)
    except (OSError, ValueError) as error:
        fail(f"cannot read {source}: {error}")
    subgraphs = (workflow.get("definitions") or {}).get("subgraphs") or []
    graph = next((g for g in subgraphs if g.get("name") == SUBGRAPH), None)
    if graph is None:
        fail(f'no sub-graph named "{SUBGRAPH}": is this the character sheet workflow?')
    texts = [n for n in graph.get("nodes", []) if n.get("type") == "PrimitiveStringMultiline"]
    master = next((n for n in texts if n.get("title") == MASTER_TITLE), None)
    other = next((n for n in texts if n is not master), None)
    if master is None:
        fail(f'no text node titled "{MASTER_TITLE}" in the sub-graph')
    if other is None:
        fail("no second text node (the static prompt) in the sub-graph")

    def text_of(node: dict) -> str:
        values = node.get("widgets_values") or []
        text = values[0].strip() if values and isinstance(values[0], str) else ""
        if not text:
            fail(f'the text node "{node.get("title") or node.get("id")}" is empty')
        return text

    master_text, static_text = text_of(master), text_of(other)
    if NAME_PHRASE not in static_text:
        fail(f"the static prompt does not contain {NAME_PHRASE!r}: the workflow changed, edit the script")
    return master_text, static_text.replace(NAME_PHRASE, NAME_PLACEHOLDER)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", required=True, help="the workflow .json")
    parser.add_argument("--out", default=DEFAULT_OUT, help="folder to write into (default: the plug-in's data folder)")
    parser.add_argument("--force", action="store_true", help="overwrite files that already exist")
    args = parser.parse_args()

    master, static = long_texts(args.source)
    targets = {"master-prompt.txt": master, "static-prompt.txt": static}
    if not args.force:
        existing = [name for name in targets if os.path.exists(os.path.join(args.out, name))]
        if existing:
            fail(f"{', '.join(existing)} already in {args.out}: pass --force to overwrite")
    os.makedirs(args.out, exist_ok=True)
    for name, text in targets.items():
        path = os.path.join(args.out, name)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text + "\n")
        print(f"{path}  ({len(text)} characters)")


if __name__ == "__main__":
    main()
