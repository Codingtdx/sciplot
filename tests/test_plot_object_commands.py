from __future__ import annotations

from fastapi.testclient import TestClient

from app.sidecar.schemas import PlotEditCommandNormalizeResponse
from app.sidecar.server import app
from src.rendering.plot_object_commands import SUPPORTED_COMMAND_KINDS, normalize_plot_edit_command

client = TestClient(app)


def test_plot_object_command_registry_covers_undoable_edit_surface() -> None:
    assert SUPPORTED_COMMAND_KINDS == {"add", "edit", "delete", "reorder", "rename", "visibility", "lock"}


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
    assert command["graph_patch"] == {"target_object_id": "plot:series:1", "kind": "rename"}
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
