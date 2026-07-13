#!/usr/bin/env python3
"""Fail when a local Markdown or embedded HTML link is missing or unsafe."""

from __future__ import annotations

import re
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
IGNORED_PARTS = {".git", ".build", ".swiftpm", "work"}
MARKDOWN_TARGET = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
HTML_TARGET = re.compile(r'''\b(?:href|src)=["']([^"']+)["']''', re.IGNORECASE)


def documents() -> list[Path]:
    return sorted(
        path
        for path in ROOT.rglob("*.md")
        if not IGNORED_PARTS.intersection(path.relative_to(ROOT).parts)
    )


def normalize(raw_target: str) -> str:
    target = raw_target.strip()
    if target.startswith("<") and ">" in target:
        return target[1 : target.index(">")]
    return target.split(maxsplit=1)[0]


def main() -> int:
    failures: list[str] = []
    markdown_files = documents()

    for document in markdown_files:
        text = document.read_text(encoding="utf-8")
        raw_targets = MARKDOWN_TARGET.findall(text) + HTML_TARGET.findall(text)
        for raw_target in raw_targets:
            target = normalize(raw_target)
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            if parsed.path.startswith("/"):
                failures.append(
                    f"{document.relative_to(ROOT)}: absolute local link {target}"
                )
                continue

            resolved = (document.parent / unquote(parsed.path)).resolve()
            try:
                resolved.relative_to(ROOT)
            except ValueError:
                failures.append(
                    f"{document.relative_to(ROOT)}: link escapes repository {target}"
                )
                continue
            if not resolved.exists():
                failures.append(
                    f"{document.relative_to(ROOT)}: missing target {target}"
                )

    if failures:
        print("\n".join(failures))
        return 1

    print(
        f"PASS checked Markdown and HTML links in {len(markdown_files)} Markdown file(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
