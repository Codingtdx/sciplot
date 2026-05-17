from __future__ import annotations

from typing import Any

SUPPORTED_COMMAND_KINDS = {"add", "copy_settings", "delete", "edit", "lock", "rename", "reorder", "visibility"}


def normalize_plot_edit_command(command: dict[str, Any], objects: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    kind = str(command.get("kind") or "").strip().replace("-", "_")
    if kind not in SUPPORTED_COMMAND_KINDS:
        raise ValueError(f"plot edit command kind must be one of {', '.join(sorted(SUPPORTED_COMMAND_KINDS))}.")
    target_object_id = str(command.get("target_object_id") or "").strip()
    if not target_object_id:
        raise ValueError("plot edit command target_object_id must not be empty.")
    known_ids = {str(item.get("id")) for item in objects or [] if item.get("id")}
    diagnostics: list[dict[str, Any]] = []
    if known_ids and target_object_id not in known_ids and kind not in {"add"}:
        diagnostics.append(
            {
                "status_code": "target_not_in_object_list",
                "message": f"`{target_object_id}` was not present in the provided object list.",
            }
        )
    normalized = dict(command)
    normalized["command_id"] = str(normalized.get("command_id") or f"cmd:{kind}:{target_object_id}")
    normalized["kind"] = kind
    normalized["target_object_id"] = target_object_id
    normalized["reversible"] = bool(normalized.get("reversible", True))
    normalized["help"] = normalized.get("help") or "Undoable typed plot edit command normalized by sidecar."
    graph_patch = dict(normalized.get("graph_patch") or {})
    graph_patch.setdefault("target_object_id", target_object_id)
    graph_patch.setdefault("kind", kind)
    normalized["graph_patch"] = graph_patch
    return {"command": normalized, "diagnostics": diagnostics}


__all__ = ["SUPPORTED_COMMAND_KINDS", "normalize_plot_edit_command"]
