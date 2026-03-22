from __future__ import annotations

import hashlib
import shutil
from datetime import UTC, datetime
from pathlib import Path
from typing import Literal

from platformdirs import user_cache_path, user_data_path

from src.text_normalization import slugify_label

APP_NAME = "SciPlot God"
_APP_AUTHOR = False
_PLOT_EXPORT_RETENTION = 12
_CODE_CONSOLE_RUN_RETENTION = 8


def _data_root() -> Path:
    return user_data_path(APP_NAME, appauthor=_APP_AUTHOR, ensure_exists=True)


def _cache_root() -> Path:
    return user_cache_path(APP_NAME, appauthor=_APP_AUTHOR, ensure_exists=True)


def managed_templates_root() -> Path:
    path = _data_root() / "templates"
    path.mkdir(parents=True, exist_ok=True)
    return path


def managed_template_folder_path(variant: Literal["example", "blank"]) -> Path:
    path = managed_templates_root() / "folders" / variant
    path.mkdir(parents=True, exist_ok=True)
    return path


def managed_single_template_root(variant: Literal["example", "blank"]) -> Path:
    path = managed_templates_root() / "single" / variant
    path.mkdir(parents=True, exist_ok=True)
    return path


def managed_plot_exports_root() -> Path:
    path = _data_root() / "plot_exports"
    path.mkdir(parents=True, exist_ok=True)
    return path


def managed_code_console_runs_root() -> Path:
    path = _cache_root() / "code_console" / "runs"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _clear_directory(path: Path) -> tuple[int, int]:
    removed_files = 0
    removed_directories = 0
    if not path.exists():
        path.mkdir(parents=True, exist_ok=True)
        return removed_files, removed_directories
    for child in path.iterdir():
        files, directories = _remove_path(child)
        removed_files += files
        removed_directories += directories
    path.mkdir(parents=True, exist_ok=True)
    return removed_files, removed_directories


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


def _prune_directory_children(
    path: Path,
    *,
    keep: int,
    skip: set[Path] | None = None,
) -> tuple[int, int]:
    if not path.exists():
        return 0, 0
    skip_paths = {item.resolve() for item in (skip or set())}
    children = [
        child
        for child in path.iterdir()
        if child.resolve() not in skip_paths
    ]
    children.sort(key=lambda child: child.stat().st_mtime, reverse=True)
    removed_files = 0
    removed_directories = 0
    for child in children[keep:]:
        files, directories = _remove_path(child)
        removed_files += files
        removed_directories += directories
    return removed_files, removed_directories


def _hash_suffix(*parts: object, length: int = 10) -> str:
    digest = hashlib.sha256(
        "||".join(str(part) for part in parts).encode("utf-8")
    ).hexdigest()
    return digest[:length]


def _sheet_slug(sheet: str | int) -> str:
    slug = slugify_label(str(sheet))
    return slug or "sheet"


def prepare_managed_plot_export_dir(
    input_path: Path,
    *,
    sheet: str | int,
    template: str,
) -> Path:
    root = managed_plot_exports_root()
    stem = slugify_label(input_path.stem) or "plot"
    template_slug = slugify_label(template) or "template"
    directory = root / (
        f"{stem}_{_sheet_slug(sheet)}_{template_slug}_"
        f"{_hash_suffix(input_path.resolve(), sheet, template)}"
    )
    _clear_directory(directory)
    _prune_directory_children(root, keep=_PLOT_EXPORT_RETENTION, skip={directory})
    return directory


def create_managed_code_console_run_dir(session: dict[str, object]) -> Path:
    root = managed_code_console_runs_root()
    source = (
        session.get("input_filename")
        or session.get("project_id")
        or session.get("template")
        or "code_console"
    )
    slug = slugify_label(str(source)) or "code_console"
    session_id = str(session.get("session_id") or "session")
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S%f")
    run_dir = root / f"{stamp}_{slug}_{_hash_suffix(session_id, stamp, length=8)}"
    run_dir.mkdir(parents=True, exist_ok=False)
    _prune_directory_children(root, keep=_CODE_CONSOLE_RUN_RETENTION, skip={run_dir})
    return run_dir


def managed_storage_snapshot() -> dict[str, object]:
    example_templates_path = managed_template_folder_path("example")
    blank_templates_path = managed_template_folder_path("blank")
    single_example_path = managed_single_template_root("example")
    single_blank_path = managed_single_template_root("blank")
    plot_exports_path = managed_plot_exports_root()
    code_console_runs_path = managed_code_console_runs_root()
    return {
        "root_path": str(_data_root()),
        "data_root": str(_data_root()),
        "cache_root": str(_cache_root()),
        "example_templates_path": str(example_templates_path),
        "blank_templates_path": str(blank_templates_path),
        "single_example_templates_path": str(single_example_path),
        "single_blank_templates_path": str(single_blank_path),
        "plot_exports_path": str(plot_exports_path),
        "code_console_runs_path": str(code_console_runs_path),
        "example_template_file_count": sum(1 for path in example_templates_path.rglob("*") if path.is_file()),
        "blank_template_file_count": sum(1 for path in blank_templates_path.rglob("*") if path.is_file()),
        "single_template_file_count": sum(
            1
            for root in (single_example_path, single_blank_path)
            for path in root.rglob("*")
            if path.is_file()
        ),
        "plot_export_dir_count": sum(1 for path in plot_exports_path.iterdir() if path.is_dir()),
        "code_console_run_dir_count": sum(
            1 for path in code_console_runs_path.iterdir() if path.is_dir()
        ),
    }


def cleanup_managed_storage(
    *,
    strategy: Literal["all", "stale"] = "all",
) -> dict[str, object]:
    removed_files = 0
    removed_directories = 0
    if strategy == "all":
        for path in (
            managed_template_folder_path("example"),
            managed_template_folder_path("blank"),
            managed_single_template_root("example"),
            managed_single_template_root("blank"),
            managed_plot_exports_root(),
            managed_code_console_runs_root(),
        ):
            files, directories = _clear_directory(path)
            removed_files += files
            removed_directories += directories
    else:
        files, directories = _prune_directory_children(
            managed_plot_exports_root(),
            keep=_PLOT_EXPORT_RETENTION,
        )
        removed_files += files
        removed_directories += directories
        files, directories = _prune_directory_children(
            managed_code_console_runs_root(),
            keep=_CODE_CONSOLE_RUN_RETENTION,
        )
        removed_files += files
        removed_directories += directories

    snapshot = managed_storage_snapshot()
    snapshot.update(
        {
            "strategy": strategy,
            "removed_files": removed_files,
            "removed_directories": removed_directories,
        }
    )
    return snapshot


__all__ = [
    "cleanup_managed_storage",
    "create_managed_code_console_run_dir",
    "managed_plot_exports_root",
    "managed_single_template_root",
    "managed_storage_snapshot",
    "managed_template_folder_path",
    "prepare_managed_plot_export_dir",
]
