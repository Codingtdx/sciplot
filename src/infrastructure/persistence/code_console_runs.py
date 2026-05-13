from __future__ import annotations

import hashlib
import shutil
from datetime import UTC, datetime
from pathlib import Path

from platformdirs import user_data_path

from src.text_normalization import slugify_label

APP_NAME = "SciPlot"
_APP_AUTHOR = False
_CODE_CONSOLE_RUN_RETENTION = 20


def _data_root() -> Path:
    return user_data_path(APP_NAME, appauthor=_APP_AUTHOR, ensure_exists=True)


def managed_code_console_runs_root() -> Path:
    path = _data_root() / "code_console_runs"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _remove_path(path: Path) -> tuple[int, int]:
    if not path.exists():
        return 0, 0
    if path.is_dir():
        file_count = sum(1 for child in path.rglob("*") if child.is_file())
        dir_count = sum(1 for child in path.rglob("*") if child.is_dir()) + 1
        shutil.rmtree(path)
        return file_count, dir_count
    path.unlink(missing_ok=True)
    return 1, 0


def _prune_directory_children(path: Path, *, keep: int, skip: set[Path] | None = None) -> tuple[int, int]:
    if not path.exists():
        return 0, 0
    skip_paths = {item.resolve() for item in (skip or set())}
    children = [child for child in path.iterdir() if child.resolve() not in skip_paths]
    children.sort(key=lambda child: child.stat().st_mtime, reverse=True)
    removed_files = 0
    removed_directories = 0
    for child in children[keep:]:
        files, directories = _remove_path(child)
        removed_files += files
        removed_directories += directories
    return removed_files, removed_directories


def _hash_suffix(*parts: object, length: int = 10) -> str:
    digest = hashlib.sha256("||".join(str(part) for part in parts).encode("utf-8")).hexdigest()
    return digest[:length]


def prepare_managed_code_console_run_dir(input_path: Path, *, sheet: str | int) -> Path:
    root = managed_code_console_runs_root()
    stem = slugify_label(input_path.stem) or "code_console"
    sheet_slug = slugify_label(str(sheet)) or "sheet"
    timestamp = datetime.now(UTC).strftime("%Y%m%d_%H%M%S_%f")
    directory = root / (
        f"{stem}_{sheet_slug}_{timestamp}_{_hash_suffix(input_path.resolve(), sheet, timestamp)}"
    )
    directory.mkdir(parents=True, exist_ok=False)
    _prune_directory_children(root, keep=_CODE_CONSOLE_RUN_RETENTION, skip={directory})
    return directory


__all__ = [
    "managed_code_console_runs_root",
    "prepare_managed_code_console_run_dir",
]
