#!/usr/bin/env python3
"""Collects every translatable string into localization/messages.pot (gettext template).

Sources:
- tr("...") in scripts, and Text.message("...") / _notify(x, "...") message keys
- text and placeholder_text of nodes in .tscn scenes
- display_name / description / summary / rank_label fields of content (.tres, disciplines)

Translators copy the .pot to <language>.po; Godot loads .po files listed in
Project Settings > Localization > Translations. Run after adding UI text:
    python3 tools/extract_strings.py
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".git", ".godot", "node_modules", "backend", "tests", "tools"}
STRING = r'"((?:[^"\\]|\\.)*)"'
PATTERNS = {
    ".gd": [
        re.compile(r'\btr\(\s*' + STRING),
        re.compile(r'\bText\.message\(\s*' + STRING),
        re.compile(r'\b_notify\(\s*\w+\s*,\s*' + STRING),
        re.compile(r'"(?:name|summary)":\s*' + STRING),
        re.compile(r'const ASPECT_NAMES := \[(.*?)\]'),
    ],
    ".tscn": [re.compile(r'^(?:text|placeholder_text) = ' + STRING, re.M)],
    ".tres": [re.compile(r'^(?:display_name|description|rank_label|house_name) = ' + STRING, re.M)],
}


def main() -> None:
    found = {}  # msgid -> set of "file:line"
    for directory, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            ext = os.path.splitext(name)[1]
            if ext not in PATTERNS:
                continue
            path = os.path.join(directory, name)
            rel = os.path.relpath(path, ROOT)
            text = open(path, encoding="utf-8").read()
            for pattern in PATTERNS[ext]:
                for match in pattern.finditer(text):
                    line = text.count("\n", 0, match.start()) + 1
                    values = re.findall(STRING, match.group(1)) if "ASPECT_NAMES" in pattern.pattern else [match.group(1)]
                    for value in values:
                        if value.strip() and re.search(r"[A-Za-z]", value):
                            found.setdefault(value, set()).add(f"{rel}:{line}")
    out = ['msgid ""', 'msgstr ""', '"Content-Type: text/plain; charset=UTF-8\\n"', ""]
    for msgid in sorted(found):
        out.append("#: " + " ".join(sorted(found[msgid])))
        out.append(f'msgid "{msgid}"')
        out.append('msgstr ""')
        out.append("")
    os.makedirs(os.path.join(ROOT, "localization"), exist_ok=True)
    with open(os.path.join(ROOT, "localization", "messages.pot"), "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print(f"{len(found)} strings -> localization/messages.pot")


if __name__ == "__main__":
    main()
