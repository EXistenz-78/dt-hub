#!/usr/bin/env python3
"""Writes dthub-release.json for a release: the version, the sha256 and the size of the app zip and of each
plug-in zip in a folder. Upload the result as an asset of the release (the app reads it to offer updates).

    python3 Scripts/make_release_manifest.py v1.0.0 <folder with the zips> [notice.json] > dthub-release.json

The optional notice.json ({"en": "...", "it": "..."}) is shown in the app's update dialog; the app picks the
user's language and falls back to "en".
"""
import glob
import hashlib
import json
import os
import plistlib
import sys
import zipfile


class ManifestError(Exception):
    pass


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_info(zip_path, bundle_extension):
    """The Info.plist of the bundle inside a zip (the __MACOSX folder is skipped)."""
    with zipfile.ZipFile(zip_path) as archive:
        for name in archive.namelist():
            parts = name.split("/")
            if (len(parts) == 3 and parts[0].endswith(bundle_extension) and parts[1] == "Contents"
                    and parts[2] == "Info.plist" and not name.startswith("__MACOSX")):
                return plistlib.loads(archive.read(name))
    raise ManifestError(f"{os.path.basename(zip_path)}: no {bundle_extension}/Contents/Info.plist")


def entry(path, info):
    return {"version": str(info.get("CFBundleShortVersionString", "0")), "asset": os.path.basename(path),
            "sha256": sha256_of(path), "size": os.path.getsize(path)}


def build(tag, folder, notice_path=None):
    apps = sorted(glob.glob(os.path.join(folder, "DT-Hub-*-macOS-arm64.zip")))
    if len(apps) != 1:
        raise ManifestError(f"expected one DT-Hub-*-macOS-arm64.zip in {folder}, found {len(apps)}")
    manifest = {"schema": 1, "tag": tag, "app": entry(apps[0], read_info(apps[0], ".app")), "plugins": []}
    for path in sorted(glob.glob(os.path.join(folder, "*.dthubplugin.zip"))):
        info = read_info(path, ".dthubplugin")
        item = entry(path, info)
        item.update({"id": info["CFBundleIdentifier"], "name": info["CFBundleName"],
                     "contract": int(info.get("DTHubContract", 1))})
        manifest["plugins"].append(item)
    if notice_path:
        with open(notice_path, encoding="utf-8") as handle:
            notice = json.load(handle)
        if not isinstance(notice, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in notice.items()):
            raise ManifestError("notice file must be a JSON object of language -> text")
        manifest["notice"] = notice
    return json.dumps(manifest, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        sys.exit("usage: make_release_manifest.py <tag> <folder with the zips> [notice.json]")
    try:
        print(build(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) == 4 else None))
    except (ManifestError, KeyError, OSError, ValueError) as error:
        sys.exit(f"error: {error}")
