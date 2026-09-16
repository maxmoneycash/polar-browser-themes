import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from polar_themes.theme import ASSETS, ThemeError, apply_theme, decode_theme, load_theme, validate_theme, config_dir


class Themes(unittest.TestCase):
    def test_every_bundled_theme_validates(self):
        index = json.loads((ASSETS / "themes/index.json").read_text())
        self.assertGreaterEqual(len(index), 3)
        self.assertEqual(len(index), len({item["id"] for item in index}))
        for item in index:
            with self.subTest(theme=item["id"]):
                self.assertEqual(load_theme(item["id"])["name"], item["name"])

    def test_rejects_unknown_fields_missing_sections_and_executable_content(self):
        original = load_theme("midnight")
        for edit in (lambda t: t.update(script="alert(1)"), lambda t: t.pop("palette"),
                     lambda t: t["palette"].update(color="url(https://example.com)"),
                     lambda t: t["frame"].update(radius=-1),
                     lambda t: t["palette"].update(width=20000),
                     lambda t: t.update(schemaVersion=True),
                     lambda t: t["frame"].update(inset=float("nan")),
                     lambda t: t["controls"].update(hidden="false"),
                     lambda t: t.update(id="../escape")):
            theme = copy.deepcopy(original)
            edit(theme)
            with self.assertRaises(ThemeError):
                validate_theme(theme)

    def test_rejects_invalid_and_oversize_documents(self):
        for data in (b"null", b"[]", b"{", b" " * 32769, b'{"id":"a","id":"b"}'):
            with self.assertRaises(ThemeError):
                decode_theme(data)

    def test_rejected_theme_cannot_replace_active_theme(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {"POLAR_THEMES_HOME": temp}):
            path = apply_theme(load_theme("aurora"))
            before = path.read_bytes()
            invalid = load_theme("ember")
            invalid["palette"]["fontSize"] = 10000
            with self.assertRaises(ThemeError):
                apply_theme(invalid)
            self.assertEqual(path.read_bytes(), before)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_previous_theme_can_be_restored(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {"POLAR_THEMES_HOME": temp}):
            apply_theme(load_theme("aurora"))
            apply_theme(load_theme("ember"))
            previous = load_theme(str(config_dir() / "previous.json"))
            self.assertEqual(previous["id"], "aurora")
            apply_theme(previous)
            self.assertEqual(load_theme(str(config_dir() / "current.json"))["id"], "aurora")


if __name__ == "__main__":
    unittest.main()
