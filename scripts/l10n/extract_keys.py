#!/usr/bin/env python3
"""Keeps scripts/l10n/keys.json in sync with the strings the code uses.

Build first (scripts/build-dev.sh) so the compiler's .stringsdata files are fresh.

    python3 scripts/l10n/extract_keys.py           # append new strings, print them for translation
    python3 scripts/l10n/extract_keys.py --prune   # also drop strings the code no longer uses and
                                                   # renumber every <lang>.txt to match

Without --prune, existing entries keep their numbers, so the `N|translation` lines stay valid.
"""
import glob
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = ROOT / "scripts" / "l10n"
KEYS = HERE / "keys.json"
STRINGSDATA = "build/Build/Intermediates.noindex/Wakeful.build/Debug/*/Objects-normal/arm64/*.stringsdata"
# Looked up at runtime by the screenshot renderer, so the compiler does not extract them.
RUNTIME_LOOKUPS = ROOT / "Wakeful" / "Debug" / "ScreenshotRenderer.swift"


def used_localizable_keys():
    used = []
    for path in sorted(glob.glob(str(ROOT / STRINGSDATA))):
        data = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
        if not pathlib.Path(data.get("source", "")).exists():
            continue  # stale output of a deleted source file
        for entry in data.get("tables", {}).get("Localizable", []):
            used.append((entry["key"], entry.get("comment", "")))
    source = RUNTIME_LOOKUPS.read_text(encoding="utf-8")
    for key in re.findall(r'L\.(?:text|string)\("((?:[^"\\]|\\.)*)"(?!, table: "Marketing")', source):
        used.append((key.replace('\\"', '"'), ""))
    return used


def prune(keys, used):
    keep = [k for k in keys if k["table"] != "Localizable" or k["key"] in used]
    old_numbers = {id(k): n for n, k in enumerate(keys, 1)}
    renumber = {old_numbers[id(k)]: n for n, k in enumerate(keep, 1)}
    for path in sorted(HERE.glob("*.txt")):
        lines = []
        for line in path.read_text(encoding="utf-8").splitlines():
            number, sep, text = line.partition("|")
            if sep and number.isdigit() and int(number) in renumber:
                lines.append(f"{renumber[int(number)]}|{text}")
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    removed = [k["key"] for k in keys if k not in keep]
    return keep, removed


def main():
    keys = json.loads(KEYS.read_text(encoding="utf-8"))
    used = used_localizable_keys()
    used_set = {key for key, _ in used}

    removed = []
    if "--prune" in sys.argv:
        keys, removed = prune(keys, used_set)

    known = {(k["table"], k["key"]) for k in keys}
    added = []
    for key, comment in used:
        if ("Localizable", key) not in known:
            known.add(("Localizable", key))
            record = {"table": "Localizable", "key": key, "comment": comment}
            keys.append(record)
            added.append(record)

    KEYS.write_text(json.dumps(keys, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    for key in removed:
        print(f"removed: {key}")
    if not added:
        print("No new strings.")
    for index, record in enumerate(keys, 1):
        if record in added:
            print(f"{index}|{record['key']}")


if __name__ == "__main__":
    main()
