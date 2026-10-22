#!/usr/bin/env python3
"""Builds fastlane `deliver` metadata for every App Store Connect locale from store/metadata/<lang>.txt.

Each source file has `key: value` header lines (name, subtitle, keywords, promo), a `---` line,
and then the full description. App Store limits are enforced before anything is written.

    python3 scripts/store/build_metadata.py            # all locales, fails on any problem
    python3 scripts/store/build_metadata.py --partial  # skip languages without a source file
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "store" / "metadata"
OUTPUT = ROOT / "fastlane" / "metadata"

SITE = "https://dionlima1.github.io/wakeful"
COPYRIGHT = "2026 Dion Lima"
SUPPORT_EMAIL = "YOUR-EMAIL@example.com"  # fill in before uploading

# App Store Connect locale -> source language file (same mapping as the screenshot renderer).
STORE_LOCALES = {
    "en-US": "en", "en-GB": "en", "en-AU": "en", "en-CA": "en",
    "ar-SA": "ar", "ca": "ca", "cs": "cs", "da": "da", "de-DE": "de", "el": "el",
    "es-ES": "es", "es-MX": "es", "fi": "fi", "fr-FR": "fr", "fr-CA": "fr", "he": "he",
    "hi": "hi", "hr": "hr", "hu": "hu", "id": "id", "it": "it", "ja": "ja", "ko": "ko",
    "ms": "ms", "nl-NL": "nl", "no": "nb", "pl": "pl", "pt-BR": "pt-BR", "pt-PT": "pt-PT",
    "ro": "ro", "ru": "ru", "sk": "sk", "sv": "sv", "th": "th", "tr": "tr", "uk": "uk",
    "vi": "vi", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant",
}
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promo": 170, "description": 4000}
REQUIRED = ["name", "subtitle", "keywords", "promo"]


def parse(path):
    header, _, body = path.read_text(encoding="utf-8").partition("\n---\n")
    fields = {}
    for line in header.splitlines():
        key, sep, value = line.partition(":")
        if sep:
            fields[key.strip()] = value.strip()
    fields["description"] = body.strip()
    return fields


def validate(lang, fields):
    problems = []
    for key in REQUIRED + ["description"]:
        if not fields.get(key):
            problems.append(f"{lang}: missing {key}")
    for key, limit in LIMITS.items():
        value = fields.get(key, "")
        if len(value) > limit:
            problems.append(f"{lang}: {key} is {len(value)} characters (limit {limit}): {value[:60]}…")
    keywords = fields.get("keywords", "")
    if ", " in keywords:
        problems.append(f"{lang}: keywords should not have spaces after commas")
    terms = [k.strip().lower() for k in keywords.split(",") if k.strip()]
    if len(terms) != len(set(terms)):
        problems.append(f"{lang}: duplicate keywords")
    return problems


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8")


def main():
    partial = "--partial" in sys.argv
    sources, problems = {}, []
    for lang in sorted(set(STORE_LOCALES.values())):
        path = SOURCE / f"{lang}.txt"
        if not path.exists():
            if not partial:
                problems.append(f"{lang}: missing {path.relative_to(ROOT)}")
            continue
        sources[lang] = parse(path)
        problems += validate(lang, sources[lang])
    if problems:
        print("\n".join(problems), file=sys.stderr)
        sys.exit(1)

    written = 0
    for locale, lang in STORE_LOCALES.items():
        if lang not in sources:
            continue
        fields = sources[lang]
        folder = OUTPUT / locale
        write(folder / "name.txt", fields["name"])
        write(folder / "subtitle.txt", fields["subtitle"])
        write(folder / "keywords.txt", fields["keywords"])
        write(folder / "promotional_text.txt", fields["promo"])
        write(folder / "description.txt", fields["description"])
        write(folder / "support_url.txt", f"{SITE}/")
        write(folder / "marketing_url.txt", f"{SITE}/")
        write(folder / "privacy_url.txt", f"{SITE}/privacy.html")
        written += 1

    write(OUTPUT / "copyright.txt", COPYRIGHT)
    write(OUTPUT / "primary_category.txt", "UTILITIES")
    write(OUTPUT / "secondary_category.txt", "PRODUCTIVITY")
    review = OUTPUT / "review_information"
    write(review / "first_name.txt", "Dion")
    write(review / "last_name.txt", "Lima")
    write(review / "email_address.txt", SUPPORT_EMAIL)
    if not (review / "phone_number.txt").exists():
        write(review / "phone_number.txt", "+55 00 00000-0000")
    write(review / "demo_required.txt", "false")
    write(review / "notes.txt", (ROOT / "store" / "review-notes.txt").read_text(encoding="utf-8"))

    print(f"fastlane/metadata: {written} locales from {len(sources)} languages")


if __name__ == "__main__":
    main()
