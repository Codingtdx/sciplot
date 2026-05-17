from __future__ import annotations

from typing import Any

SUPPORTED_COMMAND_KINDS = {
    "add",
    "apply_template",
    "bind_source",
    "copy_settings",
    "create_output_ref",
    "delete",
    "edit",
    "import_container",
    "lock",
    "rename",
    "reorder",
    "visibility",
}
SUPPORTED_COMMAND_MODULES = {"code_console", "composer", "data_studio", "plot"}


def normalize_plot_edit_command(command: dict[str, Any], objects: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    kind = str(command.get("kind") or "").strip().replace("-", "_")
    if kind not in SUPPORTED_COMMAND_KINDS:
        raise ValueError(f"plot edit command kind must be one of {', '.join(sorted(SUPPORTED_COMMAND_KINDS))}.")
    module = str(command.get("module") or "plot").strip().replace("-", "_")
    if module not in SUPPORTED_COMMAND_MODULES:
        raise ValueError(f"command module must be one of {', '.join(sorted(SUPPORTED_COMMAND_MODULES))}.")
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
    normalized["module"] = module
    normalized["target_object_id"] = target_object_id
    normalized["reversible"] = bool(normalized.get("reversible", True))
    normalized["help"] = normalized.get("help") or "Undoable typed plot edit command normalized by sidecar."
    graph_patch = dict(normalized.get("graph_patch") or {})
    graph_patch.setdefault("target_object_id", target_object_id)
    graph_patch.setdefault("kind", kind)
    graph_patch.setdefault("module", module)
    graph_patch.setdefault("revision_delta", 1)
    normalized["graph_patch"] = graph_patch
    return {"command": normalized, "diagnostics": diagnostics}


def apply_command_preview(command: dict[str, Any], document_graph: dict[str, Any] | None = None) -> dict[str, Any]:
    normalized = normalize_plot_edit_command(command)["command"]
    graph = document_graph or {}
    current_revision = int(graph.get("revision") or 0)
    graph_revision = current_revision + int(normalized["graph_patch"].get("revision_delta") or 1)
    normalized["graph_revision"] = graph_revision
    return {
        "command": normalized,
        "graph_revision": graph_revision,
        "graph_patch": normalized["graph_patch"],
        "render_invalidation": {
            "reason": "command_applied",
            "target_object_id": normalized["target_object_id"],
            "module": normalized["module"],
        },
        "diagnostics": [],
    }


__all__ = ["SUPPORTED_COMMAND_KINDS", "apply_command_preview", "normalize_plot_edit_command"]
