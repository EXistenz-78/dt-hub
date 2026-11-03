import importlib.util
import json
import os
import plistlib
import tempfile
import unittest
import zipfile
import hashlib

spec = importlib.util.spec_from_file_location(
    "make_release_manifest", os.path.join(os.path.dirname(os.path.abspath(__file__)), "make_release_manifest.py"))
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


def write_zip(path, bundle_name, info):
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr(f"{bundle_name}/Contents/Info.plist", plistlib.dumps(info))
        # What `ditto -c -k` adds on a Mac: it must be ignored.
        archive.writestr("__MACOSX/._" + bundle_name, b"x")


class MakeReleaseManifestTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()

    def make(self, with_app=True, plugin_info=None):
        if with_app:
            write_zip(os.path.join(self.folder, "DT-Hub-1.0.0-macOS-arm64.zip"), "DT Hub.app",
                      {"CFBundleShortVersionString": "1.0.0"})
        write_zip(os.path.join(self.folder, "PromptMasterI4.dthubplugin.zip"), "PromptMasterI4.dthubplugin",
                  plugin_info or {"CFBundleIdentifier": "com.exiztenz.dthub.promptmasteri4",
                                  "CFBundleName": "Prompt Master I4", "CFBundleShortVersionString": "1.2",
                                  "DTHubContract": 1})

    def test_the_manifest_describes_the_app_and_the_plugins(self):
        self.make()
        manifest = json.loads(tool.build("v1.0.0", self.folder))
        self.assertEqual(manifest["schema"], 1)
        self.assertEqual(manifest["tag"], "v1.0.0")
        app = manifest["app"]
        zip_path = os.path.join(self.folder, "DT-Hub-1.0.0-macOS-arm64.zip")
        self.assertEqual(app["version"], "1.0.0")
        self.assertEqual(app["asset"], "DT-Hub-1.0.0-macOS-arm64.zip")
        self.assertEqual(app["sha256"], hashlib.sha256(open(zip_path, "rb").read()).hexdigest())
        self.assertEqual(app["size"], os.path.getsize(zip_path))
        plugin = manifest["plugins"][0]
        self.assertEqual(plugin["id"], "com.exiztenz.dthub.promptmasteri4")
        self.assertEqual(plugin["name"], "Prompt Master I4")
        self.assertEqual(plugin["version"], "1.2")
        self.assertEqual(plugin["contract"], 1)
        self.assertEqual(plugin["asset"], "PromptMasterI4.dthubplugin.zip")

    def test_without_the_app_zip_it_fails(self):
        self.make(with_app=False)
        with self.assertRaises(tool.ManifestError):
            tool.build("v1.0.0", self.folder)

    def test_a_plugin_without_an_info_plist_fails(self):
        self.make()
        with zipfile.ZipFile(os.path.join(self.folder, "Broken.dthubplugin.zip"), "w") as archive:
            archive.writestr("Broken.dthubplugin/readme.txt", b"x")
        with self.assertRaises(tool.ManifestError):
            tool.build("v1.0.0", self.folder)


if __name__ == "__main__":
    unittest.main()
