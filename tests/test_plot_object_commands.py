from __future__ import annotations

from fastapi.testclient import TestClient

from app.sidecar.schemas import PlotEditCommandNormalizeResponse
from app.sidecar.server import app
from src.rendering.plot_object_commands import (
    SUPPORTED_COMMAND_KINDS,
    apply_command_preview,
    normalize_plot_edit_command,
)

client = TestClient(app)


def test_plot_object_command_registry_covers_undoable_edit_surface() -> None:
    assert SUPPORTED_COMMAND_KINDS == {
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


def test_plot_object_command_normalizer_sets_graph_patch_and_reversibility() -> None:
    normalized = normalize_plot_edit_command(
        {
            "kind": "rename",
            "target_object_id": "plot:series:1",
            "before": {"label": "Raw"},
            "after": {"label": "Smoothed"},
        }
    )

    command = normalized["command"]
    assert command["command_id"] == "cmd:rename:plot:series:1"
    assert command["reversible"] is True
    assert command["graph_patch"] == {
        "target_object_id": "plot:series:1",
        "kind": "rename",
        "module": "plot",
        "revision_delta": 1,
    }
    assert normalized["diagnostics"] == []


def test_plot_object_command_endpoint_returns_typed_payload() -> None:
    response = client.post(
        "/plot-edit-command/normalize",
        json={
            "command": {
                "command_id": "cmd-lock-axis",
                "kind": "lock",
                "target_object_id": "plot:axis:left",
                "before": {"locked": False},
                "after": {"locked": True},
            }
        },
    )

    assert response.status_code == 200, response.text
    payload = PlotEditCommandNormalizeResponse.model_validate(response.json())
    assert payload.command.kind == "lock"
    assert payload.command.reversible is True
    assert payload.command.graph_patch["target_object_id"] == "plot:axis:left"


def test_plot_object_command_reports_unknown_targets_without_losing_command() -> None:
    normalized = normalize_plot_edit_command(
        {"kind": "visibility", "target_object_id": "plot:guide:missing"},
        objects=[{"id": "plot:guide:known"}],
    )

    assert normalized["command"]["target_object_id"] == "plot:guide:missing"
    assert normalized["diagnostics"][0]["status_code"] == "target_not_in_object_list"


def test_plot_object_command_accepts_copy_settings_alias() -> None:
    normalized = normalize_plot_edit_command(
        {
            "kind": "copy-settings",
            "target_object_id": "plot:series:target",
            "before": {"style": "raw"},
            "after": {"style": "source-series"},
        }
    )

    assert normalized["command"]["kind"] == "copy_settings"
    assert normalized["command"]["graph_patch"]["kind"] == "copy_settings"


def test_command_apply_preview_preserves_before_after_and_revision_metadata() -> None:
    payload = apply_command_preview(
        {
            "command_id": "cmd-visible",
            "kind": "visibility",
            "module": "plot",
            "target_object_id": "plot:guide:threshold",
            "before": {"visible": True},
            "after": {"visible": False},
        },
        {"schema_version": 2, "revision": 7},
    )

    assert payload["graph_revision"] == 8
    assert payload["command"]["graph_revision"] == 8
    assert payload["command"]["before"] == {"visible": True}
    assert payload["command"]["after"] == {"visible": False}
    assert payload["graph_patch"]["module"] == "plot"
    assert payload["render_invalidation"]["reason"] == "command_applied"
    assert payload["diagnostics"] == []


def test_command_apply_preview_ignores_stale_command_revision() -> None:
    payload = apply_command_preview(
        {
            "command_id": "cmd-stale",
            "kind": "rename",
            "module": "plot",
            "target_object_id": "plot:series:1",
            "before": {"label": "Old"},
            "after": {"label": "New"},
            "graph_revision": 3,
        },
        {"schema_version": 2, "revision": 5},
    )

    assert payload["graph_revision"] == 5
    assert payload["command"]["graph_revision"] == 5
    assert payload["graph_patch"] == {}
    assert payload["render_invalidation"]["reason"] == "stale_command_ignored"
    assert payload["diagnostics"][0]["status_code"] == "stale_command_revision"
