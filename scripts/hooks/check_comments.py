"""Enforces header-only comment policy for Java, Scala, Python, SQL."""

import pathlib
import re
import sys

ALLOWED_TOP = {
    ".py": lambda s: s.startswith('"""') or s.startswith("'''") or s.startswith("#"),
    ".java": lambda s: s.startswith("//"),
    ".scala": lambda s: s.startswith("//"),
    ".sql": lambda s: s.startswith("--"),
}

SKIP_DIRS = {".git", ".venv", "target", ".mypy_cache", "__pycache__", "node_modules"}


def check_file(path: pathlib.Path) -> list[str]:
    errors: list[str] = []
    text = path.read_text(encoding="utf-8", errors="ignore")
    lines = text.splitlines()
    if not lines:
        return errors
    ended_top = False
    for idx, line in enumerate(lines, start=1):
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith(("#!", "@")):
            continue
        is_comment = stripped.startswith(
            ("//", "#", "--", "/*", "*", "*/", '"""', "'''")
        )
        if not ended_top and is_comment:
            continue
        if not ended_top and stripped:
            ended_top = True
        if (
            ended_top
            and is_comment
            and "noqa" not in stripped
            and "type: ignore" not in stripped
            and "spotless:" not in stripped
        ):
            if re.match(r"^\s*(//|#|--|/\*|\*).+", line):
                errors.append(
                    f"{path}:{idx}: inline comments not allowed: {line.strip()}"
                )
    return errors


def main() -> int:
    root = pathlib.Path(".")
    patterns = ["**/*.py", "**/*.java", "**/*.scala", "**/*.sql"]
    errors: list[str] = []
    for pat in patterns:
        for p in root.glob(pat):
            if any(d in p.parts for d in SKIP_DIRS):
                continue
            if p.name == "check_comments.py":
                continue
            errors.extend(check_file(p))
    if errors:
        for e in errors:
            print(e)
        return 1
    print("check_comments: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
