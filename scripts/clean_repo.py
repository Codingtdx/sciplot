from __future__ import annotations

import argparse
import os
import shutil
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ACTIVE_VENV_NAME = ".venv"
TOP_LEVEL_PATH_TARGETS: tuple[tuple[str, str], ...] = (
    (".mypy_cache", "mypy cache"),
    (".pytest_cache", "pytest cache"),
    (".ruff_cache", "ruff cache"),
    (".tmp", "temporary workspace"),
    ("app/desktop/dist", "desktop build output"),
    ("app/desktop/playwright-report", "desktop Playwright report"),
    ("app/desktop/test-results", "desktop test results"),
    ("app/desktop/src-tauri/target", "Tauri build output"),
)
TOP_LEVEL_GLOB_TARGETS: tuple[tuple[str, str], ...] = (
    (".venv-*", "backup virtualenv"),
    (".tmp_*", "temporary workspace"),
)
DEEP_PATH_TARGETS: tuple[tuple[str, str], ...] = (
    ("app/desktop/node_modules", "desktop dependencies"),
)
RECURSIVE_DIR_NAMES = frozenset({"__pycache__", ".cache", ".vite", ".turbo"})
RECURSIVE_FILE_NAMES = frozenset({".DS_Store"})
RECURSIVE_FILE_SUFFIXES = frozenset({".pyc", ".pyo", ".pyd"})
PROTECTED_TOP_LEVEL_DIRS = frozenset({".git", ACTIVE_VENV_NAME})


@dataclass(frozen=True)
class CleanupTarget:
    path: Path
    reason: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Remove generated caches and temporary files from this repo without touching source files."
        )
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be removed without deleting anything.",
    )
    parser.add_argument(
        "--include-node-modules",
        action="store_true",
        help="Also remove app/desktop/node_modules.",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=REPO_ROOT,
        help=argparse.SUPPRESS,
    )
    return parser.parse_args()


def format_bytes(size_bytes: int) -> str:
    units = ["B", "KB", "MB", "GB", "TB"]
    value = float(size_bytes)
    for unit in units:
        if value < 1024.0 or unit == units[-1]:
            if unit == "B":
                return f"{int(value)} {unit}"
            return f"{value:.1f} {unit}"
        value /= 1024.0
    return f"{size_bytes} B"


def safe_stat_size(path: Path) -> int:
    try:
        if path.is_symlink():
            return path.lstat().st_size
        if path.is_file():
            return path.stat().st_size
        if path.is_dir():
            total = 0
            for current_root, dirnames, filenames in os.walk(path, topdown=True, followlinks=False):
                dirnames[:] = [name for name in dirnames if not Path(current_root, name).is_symlink()]
                for filename in filenames:
                    candidate = Path(current_root, filename)
                    try:
                        total += candidate.lstat().st_size if candidate.is_symlink() else candidate.stat().st_size
                    except OSError:
                        continue
            return total
    except OSError:
        return 0
    return 0


def is_relative_to(path: Path, other: Path) -> bool:
    try:
        path.relative_to(other)
    except ValueError:
        return False
    return True


def collapse_targets(targets: list[CleanupTarget]) -> list[CleanupTarget]:
    deduped: dict[Path, CleanupTarget] = {}
    for target in targets:
        deduped[target.path] = target
    selected: list[CleanupTarget] = []
    for target in sorted(deduped.values(), key=lambda item: (len(item.path.parts), str(item.path))):
        if any(is_relative_to(target.path, chosen.path) for chosen in selected):
            continue
        selected.append(target)
    return selected


def should_skip_descent(
    root: Path,
    current_dir: Path,
    child_name: str,
    *,
    include_node_modules: bool,
) -> bool:
    if child_name in PROTECTED_TOP_LEVEL_DIRS:
        return True
    if child_name == "node_modules":
        return not include_node_modules or current_dir == root / "app" / "desktop"
    if current_dir == root and (child_name.startswith(".venv-") or child_name.startswith(".tmp_")):
        return True
    return False


def collect_top_level_targets(root: Path, *, include_node_modules: bool) -> list[CleanupTarget]:
    targets: list[CleanupTarget] = []
    for relative_path, reason in TOP_LEVEL_PATH_TARGETS:
        candidate = root / relative_path
        if candidate.exists():
            targets.append(CleanupTarget(candidate, reason))
    for pattern, reason in TOP_LEVEL_GLOB_TARGETS:
        for candidate in sorted(root.glob(pattern)):
            if candidate.name == ACTIVE_VENV_NAME or not candidate.exists():
                continue
            targets.append(CleanupTarget(candidate, reason))
    if include_node_modules:
        for relative_path, reason in DEEP_PATH_TARGETS:
            candidate = root / relative_path
            if candidate.exists():
                targets.append(CleanupTarget(candidate, reason))
    return targets


def collect_recursive_targets(root: Path, *, include_node_modules: bool) -> list[CleanupTarget]:
    targets: list[CleanupTarget] = []
    for current_root, dirnames, filenames in os.walk(root, topdown=True, followlinks=False):
        current_dir = Path(current_root)
        matched_dirnames = [name for name in dirnames if name in RECURSIVE_DIR_NAMES]
        for dirname in matched_dirnames:
            targets.append(CleanupTarget(current_dir / dirname, f"generated directory ({dirname})"))
        dirnames[:] = [
            name
            for name in dirnames
            if name not in RECURSIVE_DIR_NAMES
            and not should_skip_descent(root, current_dir, name, include_node_modules=include_node_modules)
        ]
        for filename in filenames:
            if filename in RECURSIVE_FILE_NAMES:
                targets.append(CleanupTarget(current_dir / filename, f"generated file ({filename})"))
                continue
            if Path(filename).suffix in RECURSIVE_FILE_SUFFIXES:
                targets.append(CleanupTarget(current_dir / filename, "compiled Python bytecode"))
    return targets


def discover_targets(root: Path, *, include_node_modules: bool) -> list[CleanupTarget]:
    targets = collect_top_level_targets(root, include_node_modules=include_node_modules)
    targets.extend(collect_recursive_targets(root, include_node_modules=include_node_modules))
    return collapse_targets(targets)


def remove_target(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink(missing_ok=True)
        return
    if path.is_dir():
        shutil.rmtree(path)


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    targets = discover_targets(root, include_node_modules=args.include_node_modules)
    if not targets:
        print("No generated files matched the cleanup rules.")
        return 0

    total_size = sum(safe_stat_size(target.path) for target in targets)
    action = "Would remove" if args.dry_run else "Removing"
    for target in sorted(targets, key=lambda item: str(item.path.relative_to(root))):
        relative_path = target.path.relative_to(root)
        print(f"{action}: {relative_path} ({target.reason})")
    print(f"Matched {len(targets)} paths, approx {format_bytes(total_size)}.")

    if args.dry_run:
        return 0

    errors: list[str] = []
    for target in sorted(targets, key=lambda item: (-len(item.path.parts), str(item.path))):
        try:
            remove_target(target.path)
        except OSError as error:
            relative_path = target.path.relative_to(root)
            errors.append(f"{relative_path}: {error}")
    if errors:
        print("Cleanup finished with errors:")
        for error in errors:
            print(f"  - {error}")
        return 1

    print(f"Cleanup finished. Reclaimed approx {format_bytes(total_size)}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
