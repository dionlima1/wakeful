#!/usr/bin/env python3
"""Builds the app's String Catalogs from scripts/l10n/keys.json and one <lang>.txt per language.

Each <lang>.txt has one `N|translation` line per entry in keys.json (1-based). The script refuses to
write anything if a translation is missing, duplicated, or changes the format specifiers.

    python3 scripts/l10n/build_catalogs.py
"""
import collections
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = ROOT / "scripts" / "l10n"
LANGUAGES = [
    "ar", "ca", "cs", "da", "de", "el", "es", "fi", "fr", "he", "hi", "hr", "hu", "id", "it", "ja", "ko",
    "ms", "nb", "nl", "pl", "pt-BR", "pt-PT", "ro", "ru", "sk", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant",
]
OUTPUTS = {
    "Localizable": ROOT / "Shared" / "Localizable.xcstrings",
    "Marketing": ROOT / "Wakeful" / "Resources" / "Marketing.xcstrings",
    "AppShortcuts": ROOT / "Wakeful" / "AppShortcuts.xcstrings",
    "InfoPlist": ROOT / "Wakeful" / "InfoPlist.xcstrings",
}
SPECIFIER = re.compile(r"%(?:\d+\$)?(@|lld|d|%)")


def source_text(entry):
    return entry["comment"] if entry["table"] == "InfoPlist" else entry["key"]


def specifiers(text):
    return collections.Counter(SPECIFIER.findall(text))


def load_language(lang, keys):
    path = HERE / f"{lang}.txt"
    if not path.exists():
        return None, [f"{lang}: missing {path.name}"]
    values, errors = {}, []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        index, sep, text = line.partition("|")
        if not sep or not index.strip().isdigit():
            errors.append(f"{lang}:{number}: expected 'N|text'")
            continue
        index = int(index)
        if index in values:
            errors.append(f"{lang}:{number}: entry {index} appears twice")
        values[index] = text.strip()

    for index, entry in enumerate(keys, 1):
        text = values.get(index)
        source = source_text(entry)
        if not text:
            errors.append(f"{lang}: entry {index} missing ({source!r})")
            continue
        if specifiers(text) != specifiers(source):
            errors.append(f"{lang}: entry {index} format specifiers differ: {source!r} -> {text!r}")
        if "${applicationName}" in source and "${applicationName}" not in text:
            errors.append(f"{lang}: entry {index} must keep ${{applicationName}}")
    extra = set(values) - set(range(1, len(keys) + 1))
    if extra:
        errors.append(f"{lang}: unknown entries {sorted(extra)}")
    return values, errors


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def main():
    keys = json.loads((HERE / "keys.json").read_text(encoding="utf-8"))
    translations, errors = {}, []
    for lang in LANGUAGES:
        values, lang_errors = load_language(lang, keys)
        errors += lang_errors
        if values:
            translations[lang] = values
    if errors:
        print("\n".join(errors), file=sys.stderr)
        print(f"\n{len(errors)} problem(s); nothing written.", file=sys.stderr)
        sys.exit(1)

    catalogs = {table: {} for table in OUTPUTS}
    for index, entry in enumerate(keys, 1):
        localizations = {lang: unit(translations[lang][index]) for lang in LANGUAGES}
        if entry["table"] == "InfoPlist":
            localizations["en"] = unit(entry["comment"])
            for plist_key in ("NSLocationUsageDescription", "NSLocationWhenInUseUsageDescription"):
                catalogs["InfoPlist"][plist_key] = {"extractionState": "manual", "localizations": localizations}
            continue
        record = {"localizations": dict(sorted(localizations.items()))}
        if entry["table"] in ("Marketing", "AppShortcuts"):
            record["extractionState"] = "manual"
        catalogs[entry["table"]][entry["key"]] = record

    for table, path in OUTPUTS.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        catalog = {"sourceLanguage": "en", "strings": dict(sorted(catalogs[table].items())), "version": "1.0"}
        path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"{path.relative_to(ROOT)}: {len(catalogs[table])} strings × {len(LANGUAGES) + 1} languages")


if __name__ == "__main__":
    main()
