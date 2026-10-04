#!/usr/bin/env python3
"""Builds App/Resources/RecommendedSettings.json from the list of official configurations Draw Things keeps in its cache.

usage: make-recommended-settings.py [CONFIGS_JSON] [OUT_JSON]

CONFIGS_JSON defaults to the cache of the Draw Things app on this Mac
(~/Library/Containers/com.liuliu.draw-things/Data/Library/Caches/net/configs.json); OUT_JSON to
App/Resources/RecommendedSettings.json next to this script's repository.

For each model the file keeps the basic values Draw Things recommends: steps, guidanceScale, sampler (Draw Things'
number), shift and resolutionDependentShift (left out when the list does not say). Entries that use LoRAs (the
"with Lightning" variants) are not the model's base values and are left out. The key is the model's file name
without the quantization ("flux_2_klein_9b_f16.ckpt" and "flux_2_klein_9b_q6p.ckpt" are "flux_2_klein_9b"); an entry
that names its family (`version`) is also the fallback for that family.
"""
import json
import os
import re
import sys

DEFAULT_SOURCE = os.path.expanduser("~/Library/Containers/com.liuliu.draw-things/Data/Library/Caches/net/configs.json")
DEFAULT_OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Resources", "RecommendedSettings.json")
QUANTIZATION = re.compile(r"_(f16|f32|bf16|q\d+p|i8x|svd)$")


def model_key(file_name):
    """The model's file name without its quantization and extension."""
    name = re.sub(r"\.ckpt$", "", file_name)
    while True:
        shorter = QUANTIZATION.sub("", name)
        if shorter == name:
            return name
        name = shorter


def values(configuration):
    """The recommended values of a configuration, or None when it lacks the basic ones."""
    steps, guidance, sampler = configuration.get("steps"), configuration.get("guidanceScale"), configuration.get("sampler")
    if not isinstance(steps, int) or not isinstance(guidance, (int, float)) or not isinstance(sampler, int):
        return None
    result = {"steps": steps, "guidanceScale": guidance, "sampler": sampler}
    if isinstance(configuration.get("shift"), (int, float)):
        result["shift"] = configuration["shift"]
    if isinstance(configuration.get("resolutionDependentShift"), bool):
        result["resolutionDependentShift"] = configuration["resolutionDependentShift"]
    return result


def convert(entries):
    """{"models": {key: values}, "families": {version: values}} from the list of configurations."""
    models, families = {}, {}
    for entry in entries:
        configuration = entry.get("configuration") or {}
        model = configuration.get("model")
        if not isinstance(model, str) or configuration.get("loras"):
            continue
        found = values(configuration)
        if found is None:
            continue
        models.setdefault(model_key(model), found)
        family = entry.get("version")
        if isinstance(family, str) and family:
            families.setdefault(family, found)
    return {"models": dict(sorted(models.items())), "families": dict(sorted(families.items()))}


def main(argv):
    source = argv[1] if len(argv) > 1 else DEFAULT_SOURCE
    out = argv[2] if len(argv) > 2 else DEFAULT_OUT
    with open(source) as handle:
        table = convert(json.load(handle))
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w") as handle:
        json.dump(table, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print("wrote", os.path.abspath(out), len(table["models"]), "models,", len(table["families"]), "families")


if __name__ == "__main__":
    main(sys.argv)
