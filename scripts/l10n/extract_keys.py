#!/usr/bin/env python3
"""Appends strings that appeared in the code since the last run to scripts/l10n/keys.json.

Build first (scripts/build-dev.sh) so the compiler's .stringsdata files are fresh. Existing entries keep
their numbers, so the `N|translation` lines in <lang>.txt stay valid; new entries are printed so they can be
translated and appended to every language file.

    python3 scripts/l10n/extract_keys.py
"""
import glob
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
KEYS = ROOT / "scripts" / "l10n" / "keys.json"
STRINGSDATA = "build/Build/Intermediates.noindex/Wakeful.build/Debug/*/Objects-normal/arm64/*.stringsdata"


def main():
    keys = json.loads(KEYS.read_text(encoding="utf-8"))
    known = {(k["table"], k["key"]) for k in keys}
    added = []
    for path in sorted(glob.glob(str(ROOT / STRINGSDATA))):
        data = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
        for entry in data.get("tables", {}).get("Localizable", []):
            if ("Localizable", entry["key"]) not in known:
                known.add(("Localizable", entry["key"]))
                record = {"table": "Localizable", "key": entry["key"], "comment": entry.get("comment", "")}
                keys.append(record)
                added.append(record)
    KEYS.write_text(json.dumps(keys, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    if not added:
        print("No new strings.")
    for index, record in enumerate(keys, 1):
        if record in added:
            print(f"{index}|{record['key']}")


if __name__ == "__main__":
    main()
