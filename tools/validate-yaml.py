#!/usr/bin/env python3
"""Parse every YAML file below a directory without constructing custom tags."""

from __future__ import annotations

import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("PyYAML is required: python -m pip install pyyaml", file=sys.stderr)
    raise SystemExit(2)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate-yaml.py <directory>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1]).resolve()
    if not root.is_dir():
        print(f"YAML root is not a directory: {root}", file=sys.stderr)
        return 2

    files = sorted(
        path
        for path in root.rglob("*")
        if path.is_file() and path.suffix.lower() in {".yml", ".yaml"}
    )
    failures: list[str] = []
    for path in files:
        try:
            with path.open("r", encoding="utf-8-sig") as stream:
                tuple(yaml.compose_all(stream, Loader=yaml.SafeLoader))
        except (OSError, UnicodeError, yaml.YAMLError) as error:
            relative = path.relative_to(root)
            failures.append(f"{relative}: {error}")

    if failures:
        print(f"YAML validation failed ({len(failures)} file(s)):")
        for failure in failures:
            print(f" - {failure}")
        return 1

    print(f"YAML syntax passed ({len(files)} files).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
