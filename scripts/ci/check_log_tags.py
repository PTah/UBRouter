#!/usr/bin/env python3
"""Fail if log tags look mangled or still use [tag] form that confuses PowerShell/Markdown."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Forms produced by PowerShell -replace "[host]" (charclass) or console wrap misread
MANGLED = [
    re.compile(r'\b(info|warn)\s+"(ost|ardening|ulti-wan|ulti_wan)]'),
    re.compile(r'\b(info|warn)\s+"\[[^\]]*$'),  # broken open bracket at EOL
]

# Ban legacy [tag] after migration (except comments about the ban)
LEGACY = re.compile(r'\b(info|warn|die)\s+"\[[a-zA-Z]')


def main() -> int:
    errors: list[str] = []
    for p in (ROOT / "scripts").rglob("*.sh"):
        if "ci/" in str(p).replace("\\", "/"):
            continue
        text = p.read_text(encoding="utf-8")
        for i, line in enumerate(text.splitlines(), 1):
            code = line.split("#", 1)[0]
            for rx in MANGLED:
                if rx.search(code):
                    errors.append(f"{p.relative_to(ROOT)}:{i}: mangled tag: {line.strip()}")
            if LEGACY.search(code):
                errors.append(f"{p.relative_to(ROOT)}:{i}: use 'module:' not '[module]': {line.strip()}")
    ub = ROOT / "ubrouter"
    if ub.is_file():
        for i, line in enumerate(ub.read_text(encoding="utf-8").splitlines(), 1):
            if LEGACY.search(line):
                errors.append(f"ubrouter:{i}: use 'module:' not '[module]': {line.strip()}")
    if errors:
        print("ERROR: log tag check failed:", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        print(
            "\nCause: PowerShell/regex treat [host] as a character class; "
            "prefer info \"module: message\".",
            file=sys.stderr,
        )
        return 1
    print("OK: log tags")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
