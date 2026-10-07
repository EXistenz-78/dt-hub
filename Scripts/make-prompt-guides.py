#!/usr/bin/env python3
"""Extract the "Model notes" of every family from Prompt Master's master-prompts.json
and write them as PromptGuides.swift for the app's Enhance/Generate Prompt tools.

Used once; the generated file is edited by hand from then on.

    python3 Scripts/make-prompt-guides.py \
        --source Plugins/PromptMaster/Data/master-prompts.json \
        --out Packages/Sources/HubCore/PromptAssist/PromptGuides.swift
"""
import argparse
import json
import sys

HEADER = """// Generated once by Scripts/make-prompt-guides.py from Prompt Master's master-prompts.json; edit by hand from here on.
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
"""

FOOTER = """  ]

  public static func guide(for family: String?) -> PromptGuide? {
    family.flatMap { all[$0] }
  }
}
"""


def notes_of(key: str, system: str) -> str:
    marker = "Model notes:"
    index = system.find(marker)
    if index < 0:
        sys.exit(f"error: family {key} has no '{marker}'")
    lines = system[index + len(marker):].strip().split("\n")
    # Keep up to the last bullet line: drops trailing remarks such as "(Provisional master prompt…)".
    last = max((i for i, line in enumerate(lines) if line.startswith("- ")), default=-1)
    if last < 0:
        sys.exit(f"error: family {key} has no bullet notes")
    return "\n".join(lines[: last + 1]).strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    with open(args.source, encoding="utf-8") as handle:
        families = json.load(handle)["families"]
    out = [HEADER]
    for key, family in families.items():
        notes = notes_of(key, family["system"])
        if '"""#' in notes:
            sys.exit(f"error: family {key} notes contain the raw-string terminator")
        label = json.dumps(family["label"], ensure_ascii=False)
        negative = "true" if family["negative"] else "false"
        out.append(f'    {json.dumps(key)}: PromptGuide(\n')
        out.append(f"      label: {label}, usesNegative: {negative},\n")
        out.append(f'      notes: #"""\n{notes}\n"""#),\n')
    out.append(FOOTER)
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write("".join(out))


if __name__ == "__main__":
    main()
