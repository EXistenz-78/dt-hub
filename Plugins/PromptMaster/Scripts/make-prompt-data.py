#!/usr/bin/env python3
"""make-prompt-data.py [--source DIR] — builds the vocabulary of the Prompt Master plug-ins from Prompt Master 2.0.

With --source (or PM2_SOURCE) reads DIR/prompt_database.json (the database of PM 2.0, never modified) and writes
  Plugins/PromptMaster/Data/prompt-database.json   the slim database: ids, Italian and English names (no booru/prose forms)
Without it, that file is taken as it is. Either way it then writes
  Plugins/PromptMasterShared/Vocabulary/EmbeddedVocabulary.swift   the same file as a Swift raw string (a bundle has no resources)
which all four Prompt Master plug-ins compile (PromptMasterShared/Scripts/pm_data.py).
The family data (Data/families.json, Embedded/EmbeddedPrompts.swift) and the Rules are hand-maintained since 1.4: the
instructions of each family now live in the app (Family prompts). Run from anywhere; the output is deterministic.
"""
import argparse, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "PromptMasterShared", "Scripts"))
import pm_data

DEFAULT_SOURCE = os.environ.get("PM2_SOURCE")  # the folder of Prompt Master 2.0; or pass --source

DATABASE_VERSION = "2.1.0"


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
    return database


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default=DEFAULT_SOURCE)
    args = parser.parse_args()
    if args.source:
        with open(pm_data.VOCABULARY, "w") as out:
            out.write(pm_data.json_text(build(args.source)))
    with open(pm_data.VOCABULARY) as source:
        database = json.load(source)
    pm_data.write_vocabulary(pm_data.json_text(database))
    n_terms = sum(len(c["terms"]) for c in database["categories"])
    print(f"database {database['version']}: {len(database['groups'])} groups, {len(database['categories'])} categories, {n_terms} terms")
