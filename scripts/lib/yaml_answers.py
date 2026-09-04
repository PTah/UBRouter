#!/usr/bin/env python3
"""Read/write UBrouter answers.yaml helpers. Requires PyYAML (python3-yaml)."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def _load(path: str):
    import yaml

    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise SystemExit(f"answers root must be mapping: {path}")
    return data


def _get(data, dotted: str):
    cur = data
    for part in dotted.split("."):
        if cur is None:
            return None
        if isinstance(cur, dict):
            cur = cur.get(part)
        else:
            return None
    return cur


def cmd_get(path: str, key: str) -> None:
    val = _get(_load(path), key)
    if val is None:
        print("")
        return
    if isinstance(val, bool):
        print("true" if val else "false")
    elif isinstance(val, (list, dict)):
        print(json.dumps(val, ensure_ascii=False))
    else:
        print(val)


def cmd_get_json(path: str, key: str) -> None:
    val = _get(_load(path), key)
    print(json.dumps(val, ensure_ascii=False))


def cmd_set_map(path: str, map_json: str) -> None:
    import yaml

    data = _load(path)
    data.setdefault("interfaces", {})
    data["interfaces"]["map"] = json.loads(map_json)
    with open(path, "w", encoding="utf-8") as f:
        yaml.safe_dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(
            "usage: yaml_answers.py get|get-json|set-map <answers.yaml> <key|map-json>"
        )
    cmd = sys.argv[1]
    path = sys.argv[2]
    if not Path(path).is_file():
        raise SystemExit(f"not found: {path}")
    if cmd == "get":
        cmd_get(path, sys.argv[3])
    elif cmd == "get-json":
        cmd_get_json(path, sys.argv[3])
    elif cmd == "set-map":
        cmd_set_map(path, sys.argv[3])
    else:
        raise SystemExit(f"unknown cmd: {cmd}")


if __name__ == "__main__":
    main()
