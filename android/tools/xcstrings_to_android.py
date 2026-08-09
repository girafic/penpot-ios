#!/usr/bin/env python3
"""Convert the iOS String Catalog (Sources/Localizable.xcstrings) into Android
string resources (android/app/src/main/res/values*/strings.xml).

The English key text is the source of truth (Xcode-style: the key *is* the
English copy unless an explicit "en" localization overrides it).

Rules:
  * Resource names are derived deterministically from the English key
    (lowercase snake_case; "%@" becomes "s", "%lld" becomes "d"; name
    collisions get a numeric suffix in alphabetical key order).
  * Format specifiers: %@ -> %s, %lld -> %d. Strings with more than one
    specifier use positional forms (%1$s, %2$d, …) — argument order is the
    order of appearance in the English key, which is what iOS assumes too.
  * Keys with a "variations.plural" localization become <plurals>.
  * pt-BR maps to values-pt-rBR.

Run from the repo root:
  python3 android/tools/xcstrings_to_android.py
"""

import json
import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CATALOG = os.path.join(REPO_ROOT, "Sources", "Localizable.xcstrings")
RES_DIR = os.path.join(REPO_ROOT, "android", "app", "src", "main", "res")

LOCALES = {          # xcstrings locale -> res values suffix ("" = default/English)
    "en": "",
    "de": "-de",
    "es": "-es",
    "fr": "-fr",
    "pt-BR": "-pt-rBR",
    "ru": "-ru",
}

SPEC_RE = re.compile(r"%(\d+\$)?(?:@|lld)")


def resource_name(key: str) -> str:
    text = key.replace("%@", " s ").replace("%lld", " d ")
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "_", text).strip("_")
    text = re.sub(r"_+", "_", text)
    if not text:
        import hashlib
        text = "str_" + hashlib.sha1(key.encode()).hexdigest()[:8]
    if text[0].isdigit():
        text = "n_" + text
    return text[:60].rstrip("_")


def convert_format(value: str) -> str:
    """%@/%lld -> %s/%d, positional when the string has 2+ specifiers."""
    specs = SPEC_RE.findall(value)
    positional = len(SPEC_RE.findall(value)) > 1
    index = [0]

    def repl(match: re.Match) -> str:
        index[0] += 1
        explicit = match.group(1)  # e.g. "1$"
        java_type = "s" if match.group(0).endswith("@") else "d"
        if explicit:
            return f"%{explicit}{java_type}"
        if positional:
            return f"%{index[0]}${java_type}"
        return f"%{java_type}"

    return SPEC_RE.sub(repl, value)


def escape_android(value: str) -> str:
    value = value.replace("\\", "\\\\")
    value = value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    value = value.replace("'", "\\'").replace('"', '\\"')
    value = value.replace("\n", "\\n")
    # A leading/trailing "%" without specifier would break formatted=true, but the
    # catalog has none; literal % in a formatted string must become %%.
    return value


def localized_value(entry: dict, locale: str, key: str):
    """Returns (plain_value, plural_dict) for a locale; plural_dict maps category->value."""
    loc = (entry.get("localizations") or {}).get(locale)
    if loc is None:
        return (key if locale == "en" else None), None
    if "stringUnit" in loc:
        return loc["stringUnit"]["value"], None
    if "variations" in loc and "plural" in loc["variations"]:
        plural = {}
        for category, unit in loc["variations"]["plural"].items():
            plural[category] = unit["stringUnit"]["value"]
        return None, plural
    return (key if locale == "en" else None), None


def main() -> int:
    with open(CATALOG, encoding="utf-8") as fh:
        catalog = json.load(fh)
    strings = catalog["strings"]

    # Deterministic names: assign in alphabetical key order, suffix collisions.
    names: dict[str, str] = {}
    used: dict[str, int] = {}
    plural_names: dict[str, str] = {}
    plural_used: dict[str, int] = {}
    for key in sorted(strings.keys()):
        entry = strings[key]
        is_plural = any(
            "variations" in loc for loc in (entry.get("localizations") or {}).values()
        )
        base = resource_name(key)
        pool, target = (plural_used, plural_names) if is_plural else (used, names)
        count = pool.get(base, 0)
        pool[base] = count + 1
        target[key] = base if count == 0 else f"{base}_{count + 1}"

    for locale, suffix in LOCALES.items():
        lines = [
            '<?xml version="1.0" encoding="utf-8"?>',
            "<!-- GENERATED from Sources/Localizable.xcstrings by android/tools/xcstrings_to_android.py.",
            "     Do not edit by hand — edit the String Catalog and re-run the script. -->",
            "<resources>",
        ]
        if locale == "en":
            lines.append('    <string name="app_name" translatable="false">Penpot</string>')

        for key in sorted(strings.keys()):
            entry = strings[key]
            value, plural = localized_value(entry, locale, key)
            if plural is not None:
                lines.append(f'    <plurals name="{plural_names[key]}">')
                for category in ("zero", "one", "two", "few", "many", "other"):
                    if category in plural:
                        item = escape_android(convert_format(plural[category]))
                        lines.append(f'        <item quantity="{category}">{item}</item>')
                lines.append("    </plurals>")
            elif key in plural_names:
                # Plural in English but this locale carries a plain string (or nothing):
                # skip — Android falls back to the default locale's <plurals>.
                continue
            elif value is not None:
                lines.append(
                    f'    <string name="{names[key]}">{escape_android(convert_format(value))}</string>'
                )
        lines.append("</resources>")

        out_dir = os.path.join(RES_DIR, f"values{suffix}")
        os.makedirs(out_dir, exist_ok=True)
        out_path = os.path.join(out_dir, "strings.xml")
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
        print(f"wrote {out_path}")

    # Reference map for developers: English key -> resource name.
    map_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "string-keys.md")
    with open(map_path, "w", encoding="utf-8") as fh:
        fh.write("# Generated string resource names\n\n")
        fh.write("English key (from `Sources/Localizable.xcstrings`) → Android resource name.\n\n")
        fh.write("| resource | English key |\n|---|---|\n")
        for key in sorted(strings.keys()):
            name = plural_names.get(key) or names[key]
            kind = "plurals " if key in plural_names else ""
            printable = key.replace("|", "\\|").replace("\n", " ")
            fh.write(f"| {kind}`{name}` | {printable} |\n")
    print(f"wrote {map_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
