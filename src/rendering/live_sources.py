from __future__ import annotations

from pathlib import Path
from typing import Any

from src.rendering.data_containers import source_table_data_containers
from src.rendering.source_table_preview import source_table_preview

SUPPORTED_LIVE_SOURCE_KINDS = {"file_tail", "folder_watch", "periodic_csv"}


def _diagnostic(status_code: str, message: str, **extra: Any) -> dict[str, Any]:
    return {"status_code": status_code, "message": message, **extra}


def _resolve_live_source_path(kind: str, input_path: str | Path) -> tuple[Path | None, dict[str, Any] | None]:
    path = Path(input_path).expanduser()
    if kind == "folder_watch":
        if not path.exists() or not path.is_dir():
            return None, _diagnostic(
                "folder_not_found",
                "Folder watch live source requires an existing directory.",
                input_path=str(path),
            )
        candidates = sorted(path.glob("*.csv"), key=lambda item: item.stat().st_mtime_ns, reverse=True)
        if not candidates:
            return None, _diagnostic(
                "folder_watch_empty",
                "Folder watch did not find a CSV file to refresh.",
                input_path=str(path),
            )
        return candidates[0], None
    if not path.exists() or not path.is_file():
        return None, _diagnostic(
            "source_not_found",
            "Live source update requires an existing local file.",
            input_path=str(path),
        )
    return path, None


def update_live_source(
    *,
    live_source: dict[str, Any],
    input_path: str | Path,
    sheet: str | int = 0,
    options: dict[str, Any] | None = None,
) -> dict[str, Any]:
    source = dict(live_source)
    kind = str(source.get("kind") or "")
    if kind not in SUPPORTED_LIVE_SOURCE_KINDS:
        diagnostic = _diagnostic(
            "live_source_disabled",
            "This live source kind is disabled until sandbox, dependency, and fixture policy exists.",
            kind=kind,
        )
        source["status"] = "disabled"
        source["last_update_diagnostic"] = diagnostic
        return {
            "live_source": source,
            "input_path": str(input_path),
            "sheet": sheet,
            "data_revision": 0,
            "data_containers": [],
            "diagnostics": [diagnostic],
            "render_invalidation": {"reason": "live_source_disabled"},
            "help": source.get("help") or diagnostic["message"],
        }

    if source.get("status") != "enabled":
        diagnostic = _diagnostic("live_source_paused", "Live source is disabled or paused.")
        source["last_update_diagnostic"] = diagnostic
        return {
            "live_source": source,
            "input_path": str(input_path),
            "sheet": sheet,
            "data_revision": 0,
            "data_containers": [],
            "diagnostics": [diagnostic],
            "render_invalidation": {"reason": "live_source_paused"},
            "help": source.get("help") or diagnostic["message"],
        }

    resolved_path, error = _resolve_live_source_path(kind, input_path)
    if resolved_path is None:
        source["last_update_diagnostic"] = error or {}
        return {
            "live_source": source,
            "input_path": str(input_path),
            "sheet": sheet,
            "data_revision": 0,
            "data_containers": [],
            "diagnostics": [error or _diagnostic("source_not_found", "Live source could not be resolved.")],
            "render_invalidation": {"reason": "live_source_error"},
            "help": source.get("help") or "Resolve the live source path and refresh again.",
        }

    sample_window = max(1, int(source.get("sample_window") or 1000))
    preview = source_table_preview(
        resolved_path,
        sheet=sheet,
        offset=0,
        limit=min(sample_window, 10_000),
        encoding=(options or {}).get("encoding"),
        delimiter=(options or {}).get("delimiter"),
    )
    containers = source_table_data_containers(preview)
    data_revision = max(1, int(resolved_path.stat().st_mtime_ns))
    diagnostic = _diagnostic(
        "live_source_updated",
        "Live source refreshed from the current local file snapshot.",
        input_path=str(resolved_path),
        data_revision=data_revision,
    )
    source["last_update_diagnostic"] = diagnostic
    return {
        "live_source": source,
        "input_path": str(resolved_path),
        "sheet": sheet,
        "data_revision": data_revision,
        "data_containers": containers,
        "diagnostics": [diagnostic],
        "render_invalidation": {"reason": "live_source_updated", "data_revision": data_revision},
        "help": source.get("help") or "Live source refreshed.",
    }


__all__ = ["SUPPORTED_LIVE_SOURCE_KINDS", "update_live_source"]
