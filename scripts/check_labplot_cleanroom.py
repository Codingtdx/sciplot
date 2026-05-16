from __future__ import annotations

import argparse
from collections.abc import Iterable, Sequence
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

SOURCE_SUFFIXES = {
    ".c",
    ".cc",
    ".cpp",
    ".cxx",
    ".h",
    ".hh",
    ".hpp",
    ".m",
    ".mm",
    ".py",
    ".swift",
}

SKIPPED_PARTS = {
    ".git",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".venv",
    ".derivedData",
    "__pycache__",
    "docs",
    "figures",
    "tests",
}


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Guard SciPlot's Apache-2.0 clean-room LabPlot roadmap by rejecting copied LabPlot GPL source headers."
        )
    )
    parser.add_argument("--root", default=str(REPO_ROOT), help="Repository root to scan.")
    return parser.parse_args(argv)


def _is_skipped(path: Path, root: Path) -> bool:
    try:
        relative = path.relative_to(root)
    except ValueError:
        return True
    if relative.as_posix() == "scripts/check_labplot_cleanroom.py":
        return True
    return any(part in SKIPPED_PARTS for part in relative.parts)


def _source_files(root: Path) -> Iterable[Path]:
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if _is_skipped(path, root):
            continue
        if path.suffix.lower() in SOURCE_SUFFIXES:
            yield path


def _looks_like_labplot_gpl_source(text: str) -> bool:
    header = text[:5000]
    has_labplot_project_header = "Project" in header and "LabPlot" in header
    has_gpl_spdx = "SPDX-License-Identifier:" in header and "GPL-" in header
    return has_labplot_project_header and has_gpl_spdx


def scan(root: Path) -> list[Path]:
    findings: list[Path] = []
    for path in _source_files(root):
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if _looks_like_labplot_gpl_source(text):
            findings.append(path)
    return findings


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    root = Path(args.root).expanduser().resolve()
    findings = scan(root)
    if findings:
        print("[labplot-cleanroom] copied LabPlot GPL source header detected:")
        for path in findings:
            print(f"  - {path.relative_to(root)}: LabPlot GPL source header")
        return 2
    print("[labplot-cleanroom] no LabPlot GPL source headers found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
