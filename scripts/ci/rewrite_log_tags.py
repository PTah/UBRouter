#!/usr/bin/env python3
"""Rewrite info/warn \"[tag] msg\" -> \"tag: msg\" to avoid PowerShell/Markdown/regex eating [h...]."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

PAT = re.compile(r'(?P<fn>\b(?:info|warn|die))\s+\"\[(?P<tag>[^\]]+)\]\s*')
PAT_PRINT = re.compile(r'(print\([fF]?[\"\'])\[(?P<tag>[^\]]+)\]\s*')
PAT_ARROW = re.compile(r'(\"[\'\"]?--> )\[(?P<tag>[^\]]+)\]\s*')


def transform(text: str) -> str:
    text = PAT.sub(lambda m: f'{m.group("fn")} "{m.group("tag")}: ', text)
    text = PAT_PRINT.sub(lambda m: f'{m.group(1)}{m.group("tag")}: ', text)
    # print("--> tag: ...
    text = re.sub(
        r'(print\([fF]?["\'])--> \[([^\]]+)\]\s*',
        lambda m: f'{m.group(1)}--> {m.group(2)}: ',
        text,
    )
    return text


def main() -> None:
    changed: list[str] = []
    paths = list((ROOT / "scripts").rglob("*.sh"))
    # do not rewrite this package's own .py (docstrings contain examples)
    paths.append(ROOT / "ubrouter")
    for p in paths:
        if not p.is_file() or p.name.startswith("_"):
            continue
        raw = p.read_text(encoding="utf-8")
        new = transform(raw)
        if new != raw:
            p.write_text(new, encoding="utf-8", newline="\n")
            changed.append(str(p.relative_to(ROOT)))
    print(f"updated {len(changed)} files")
    for c in changed:
        print(c)


if __name__ == "__main__":
    main()
