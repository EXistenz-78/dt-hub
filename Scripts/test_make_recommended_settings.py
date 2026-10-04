import importlib.util
import os
import unittest

spec = importlib.util.spec_from_file_location(
    "make_recommended_settings", os.path.join(os.path.dirname(os.path.abspath(__file__)), "make-recommended-settings.py"))
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


def entry(model, name="x", version=None, **configuration):
    result = {"name": name, "configuration": {"model": model, **configuration}}
    if version:
        result["version"] = version
    return result


class MakeRecommendedSettingsTests(unittest.TestCase):
    def test_the_key_drops_the_quantization_and_the_extension(self):
        self.assertEqual(tool.model_key("flux_2_klein_9b_f16.ckpt"), "flux_2_klein_9b")
        self.assertEqual(tool.model_key("flux_2_klein_9b_q6p.ckpt"), "flux_2_klein_9b")
        self.assertEqual(tool.model_key("wan_v2.2_a14b_hne_t2v_q6p_svd.ckpt"), "wan_v2.2_a14b_hne_t2v")
        self.assertEqual(tool.model_key("qwen_image_2.1_q8p.ckpt"), "qwen_image_2.1")
        self.assertEqual(tool.model_key("z_image_turbo_1.0_f16.ckpt"), "z_image_turbo_1.0")

    def test_an_entry_gives_its_four_values_and_the_family_it_names(self):
        table = tool.convert([entry("a_q6p.ckpt", version="fam", steps=4, guidanceScale=1, sampler=16, shift=3, resolutionDependentShift=False)])
        expected = {"steps": 4, "guidanceScale": 1, "sampler": 16, "shift": 3, "resolutionDependentShift": False}
        self.assertEqual(table["models"], {"a": expected})
        self.assertEqual(table["families"], {"fam": expected})

    def test_entries_with_loras_are_left_out(self):
        table = tool.convert([
            entry("a_q6p.ckpt", steps=4, guidanceScale=1, sampler=17, shift=3, loras=[{"file": "x_lora_f16.ckpt"}]),
            entry("a_q6p.ckpt", steps=30, guidanceScale=4, sampler=17, shift=2, loras=[]),
        ])
        self.assertEqual(table["models"]["a"]["steps"], 30)

    def test_the_first_entry_of_a_key_wins_and_a_missing_shift_is_left_out(self):
        table = tool.convert([
            entry("a_q6p.ckpt", steps=30, guidanceScale=4, sampler=17, resolutionDependentShift=True),
            entry("a_f16.ckpt", steps=8, guidanceScale=1, sampler=10, shift=3),
        ])
        self.assertEqual(table["models"], {"a": {"steps": 30, "guidanceScale": 4, "sampler": 17, "resolutionDependentShift": True}})

    def test_entries_without_the_basic_values_or_a_model_are_left_out(self):
        table = tool.convert([entry("a.ckpt", steps=4), {"name": "no configuration"}, {"configuration": {"steps": 1}}, entry("b.ckpt", steps="x", guidanceScale=1, sampler=1)])
        self.assertEqual(table, {"models": {}, "families": {}})


if __name__ == "__main__":
    unittest.main()
