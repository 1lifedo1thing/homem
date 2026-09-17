#!/usr/bin/env python3
"""Check bundled translation coverage and format arguments before archiving."""
import collections
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
languages = ("zh-Hans", "es", "ja")
placeholder = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|g)")
count = 0
for name in ("Localizable", "InfoPlist"):
    catalog = json.loads((root / f"Homem/Resources/{name}.xcstrings").read_text())
    assert catalog["sourceLanguage"] == "en"
    for key, entry in catalog["strings"].items():
        if entry.get("shouldTranslate") is False:
            continue
        english = entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value", key)
        arguments = collections.Counter(placeholder.findall(english))
        for language in languages:
            unit = entry.get("localizations", {}).get(language, {}).get("stringUnit", {})
            assert unit.get("state") == "translated" and unit.get("value"), f"Missing {language}: {key}"
            assert collections.Counter(placeholder.findall(unit["value"])) == arguments, f"Format mismatch {language}: {key}"
        count += 1
print(f"Localization check passed: {count} strings in Chinese, Spanish and Japanese.")
