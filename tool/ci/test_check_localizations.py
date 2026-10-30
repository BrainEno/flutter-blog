"""Contract tests for the tracked ARB catalogs (stdlib only)."""

import json
import plistlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ARB_DIR = ROOT / "lib" / "l10n"
PLACEHOLDER = re.compile(r"\{([A-Za-z][A-Za-z0-9_]*)\s*(?:,|\})")


def messages(catalog):
    return {key: value for key, value in catalog.items() if not key.startswith("@")}


class LocalizationCatalogTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.en = json.loads((ARB_DIR / "app_en.arb").read_text(encoding="utf-8"))
        cls.zh = json.loads((ARB_DIR / "app_zh.arb").read_text(encoding="utf-8"))

    def test_both_languages_have_the_same_nonempty_messages(self):
        en = messages(self.en)
        zh = messages(self.zh)
        self.assertEqual(set(en), set(zh))
        for locale, catalog in (("en", en), ("zh", zh)):
            for key, value in catalog.items():
                with self.subTest(locale=locale, key=key):
                    self.assertIsInstance(value, str)
                    self.assertTrue(value.strip())

    def test_placeholders_match_the_template_in_both_languages(self):
        for key, value in messages(self.en).items():
            declared = set(self.en.get("@" + key, {}).get("placeholders", {}))
            for locale, text in (("en", value), ("zh", self.zh[key])):
                with self.subTest(locale=locale, key=key):
                    self.assertEqual(set(PLACEHOLDER.findall(text)), declared)

    def test_ios_declares_both_locales_and_bundles_permission_text(self):
        with (ROOT / "ios" / "Runner" / "Info.plist").open("rb") as source:
            info = plistlib.load(source)
        self.assertEqual(set(info["CFBundleLocalizations"]), {"en", "zh-Hans"})
        project = (ROOT / "ios" / "Runner.xcodeproj" / "project.pbxproj").read_text()
        self.assertIn("InfoPlist.strings in Resources", project)
        for locale in ("en", "zh-Hans"):
            text = (ROOT / "ios" / "Runner" / (locale + ".lproj") /
                    "InfoPlist.strings").read_text(encoding="utf-8")
            with self.subTest(locale=locale):
                self.assertIn("NSCameraUsageDescription", text)
                self.assertIn("NSPhotoLibraryUsageDescription", text)

    def test_icu_plurals_cover_both_reading_time_and_retention(self):
        for key in ("readingTimeMinutes", "readingTimeHours", "purgeInDays", "followerStats"):
            for locale, catalog in (("en", self.en), ("zh", self.zh)):
                with self.subTest(locale=locale, key=key):
                    self.assertIn("plural", catalog[key])
                    self.assertIn("other{", catalog[key])


if __name__ == "__main__":
    unittest.main()
