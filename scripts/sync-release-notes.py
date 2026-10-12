#!/usr/bin/env python3
"""Синхронизация releases/ с CHANGELOG.md.

Раскладывает секции CHANGELOG по файлам releases/<version>.md (без «v»).
Секции без номера версии («Следующий релиз», «До v0.1.9» и т.п.) и файл
EXAMPLE.md не трогаются. Запускать перед пушем релизных изменений.

Использование:
    python3 scripts/sync-release-notes.py
"""

import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main() -> None:
    changelog_path = os.path.join(ROOT, "CHANGELOG.md")
    releases_dir = os.path.join(ROOT, "releases")
    changelog = open(changelog_path, encoding="utf-8").read()
    os.makedirs(releases_dir, exist_ok=True)

    written, skipped = [], []
    for section in re.split(r"^## ", changelog, flags=re.M)[1:]:
        title_line, _, body = section.partition("\n")
        match = re.match(r"^v(\d+\.\d+\.\d+)\b", title_line.strip())
        if not match:
            skipped.append(title_line.strip() or "(без заголовка)")
            continue
        version = match.group(1)
        date = ""
        date_match = re.search(r"—\s*(\d{4}-\d{2}-\d{2})", title_line)
        if date_match:
            date = date_match.group(1)
        header = f"# Trace v{version}" + (f" — {date}" if date else "") + "\n\n"
        with open(os.path.join(releases_dir, f"{version}.md"), "w", encoding="utf-8") as handle:
            handle.write(header + body.strip() + "\n")
        written.append(version)

    print(f"releases/: обновлено {len(written)} файл(ов): {', '.join(written) or '—'}")
    if skipped:
        print(f"пропущены секции без версии: {', '.join(skipped)}")


if __name__ == "__main__":
    main()
