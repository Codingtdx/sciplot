from __future__ import annotations

from pathlib import Path

import pandas as pd
from fastapi.testclient import TestClient

from app.sidecar.server import app

client = TestClient(app)


def _make_curve_csv(path: Path) -> None:
    pd.DataFrame(
        [
            ["Time", "Stress", "Time", "Stress"],
            ["s", "MPa", "s", "MPa"],
            ["Sample A", "Sample A", "Sample B", "Sample B"],
            [0, 1.0, 0, 2.0],
            [1, 1.2, 1, 2.3],
            [2, 1.5, 2, 2.7],
        ]
    ).to_csv(path, header=False, index=False)


def _make_raw_notes_csv(path: Path) -> None:
    pd.DataFrame(
        [
            ["sample", "stage", "operator", "comment"],
            ["A", "prep", "DX", "cooled before mixing"],
            ["A", "mix", "DX", "viscous during loading"],
            ["A", "cast", "DX", "smooth surface"],
            ["B", "prep", "LT", "slight haze"],
            ["B", "mix", "LT", "longer settling time"],
            ["B", "cast", "LT", "edge bubble"],
            ["C", "prep", "MK", "stored overnight"],
            ["C", "mix", "MK", "fast gel"],
            ["C", "cast", "MK", "trimmed edge"],
            ["D", "prep", "DX", "fresh batch"],
            ["D", "mix", "DX", "uniform"],
            ["D", "cast", "DX", "kept for reference"],
            ["E", "prep", "LT", "control note"],
        ]
    ).to_csv(path, header=False, index=False)


def test_code_console_context_returns_prompt_and_starter_code(tmp_path: Path) -> None:
    input_path = tmp_path / "curve.csv"
    _make_curve_csv(input_path)

    response = client.post(
        "/code-console/context",
        json={
            "input_path": str(input_path),
            "sheet": 0,
            "template": "curve",
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["context_id"].startswith("ctx_")
    assert payload["input_path"] == str(input_path)
    assert payload["template"] == "curve"
    assert payload["inspection"]["model"] == "curve_table"
    assert "src.code_console_runtime" in payload["prompt_text"]
    assert "console.save_figure" in payload["starter_code"]
    assert "Replace this placeholder plot" not in payload["starter_code"]
    assert "data_profile" in payload["starter_code"]


def test_code_console_context_falls_back_to_raw_table_for_unrecognized_inputs(tmp_path: Path) -> None:
    input_path = tmp_path / "notes.csv"
    _make_raw_notes_csv(input_path)

    response = client.post(
        "/code-console/context",
        json={
            "input_path": str(input_path),
            "sheet": 0,
        },
    )

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["inspection"]["model"] == "raw_table"
    assert payload["template"] == "table_figure"
    assert payload["dataset"]["raw_rows"] == 14
    assert payload["dataset"]["raw_cols"] == 4
    assert "Raw table fallback" in payload["prompt_text"]
    assert "console.load_raw_dataframe()" in payload["starter_code"]


def test_code_console_run_uses_raw_table_context_payload(tmp_path: Path) -> None:
    input_path = tmp_path / "notes.csv"
    _make_raw_notes_csv(input_path)
    context_response = client.post(
        "/code-console/context",
        json={
            "input_path": str(input_path),
            "sheet": 0,
        },
    )
    assert context_response.status_code == 200, context_response.text
    context_id = context_response.json()["context_id"]

    run_response = client.post(
        "/code-console/run",
        json={
            "context_id": context_id,
            "code": """
from src.code_console_runtime import console

payload = console.load_normalized_dataset_payload()
df = console.load_raw_dataframe()
print(f"model={payload['model']} rows={len(df)}")
""",
            "timeout_seconds": 20,
        },
    )

    assert run_response.status_code == 200, run_response.text
    payload = run_response.json()
    assert payload["status"] == "succeeded"
    assert "model=raw_table rows=14" in payload["stdout"]


def test_code_console_run_executes_repo_native_python_and_collects_outputs(tmp_path: Path) -> None:
    input_path = tmp_path / "curve.csv"
    _make_curve_csv(input_path)

    response = client.post(
        "/code-console/run",
        json={
            "context": {
                "input_path": str(input_path),
                "sheet": 0,
                "template": "curve",
            },
            "code": """
from src.code_console_runtime import console

df = console.load_raw_dataframe()
fig, ax = console.new_figure()
ax.plot([0, 1, 2], [1, 1.5, 2.0])
ax.set_xlabel("Time (s)")
ax.set_ylabel("Stress (MPa)")
console.save_figure(fig, "console_plot")
console.write_dataframe(df, "raw_snapshot.csv", index=False)
print(f"rows={len(df)}")
""",
            "timeout_seconds": 30,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "succeeded"
    assert payload["exit_code"] == 0
    assert "rows=" in payload["stdout"]
    assert Path(payload["output_dir"]).exists()
    generated_names = {item["name"] for item in payload["generated_files"]}
    assert "console_plot.pdf" in generated_names
    assert "raw_snapshot.csv" in generated_names
    notebook_outputs = {item["label"]: item for item in payload["notebook_outputs"]}
    assert notebook_outputs["console_plot.pdf"]["kind"] == "figure"
    assert notebook_outputs["raw_snapshot.csv"]["kind"] == "table"
    notebook_artifacts = {item["label"]: item for item in payload["notebook_artifacts"]}
    assert notebook_artifacts["console_plot.pdf"]["kind"] == "figure"
    assert notebook_artifacts["console_plot.pdf"]["source_module"] == "code_console"
    assert notebook_artifacts["console_plot.pdf"]["source_graph_node_id"].startswith("code_console:notebook_output:")
    assert notebook_artifacts["raw_snapshot.csv"]["kind"] == "table"
    assert (
        notebook_artifacts["raw_snapshot.csv"]["data_container_id"]
        == notebook_outputs["raw_snapshot.csv"]["container_ids"][0]
    )
    assert notebook_artifacts["stdout.log"]["kind"] == "log"
    assert payload["data_containers"][0]["kind"] == "notebook_output"
    assert payload["data_containers"][0]["label"] == "raw_snapshot.csv"


def test_code_console_run_prefers_context_id_fast_path(tmp_path: Path, monkeypatch) -> None:
    input_path = tmp_path / "curve.csv"
    _make_curve_csv(input_path)

    context_response = client.post(
        "/code-console/context",
        json={
            "input_path": str(input_path),
            "sheet": 0,
            "template": "curve",
        },
    )
    assert context_response.status_code == 200, context_response.text
    context_id = context_response.json()["context_id"]

    def fail_build(*args, **kwargs):
        raise AssertionError("context_id run path should not rebuild context")

    monkeypatch.setattr("src.code_console_service.build_code_console_context", fail_build)

    run_response = client.post(
        "/code-console/run",
        json={
            "context_id": context_id,
            "code": """
from src.code_console_runtime import console
df = console.load_raw_dataframe()
print(f"fast_path_rows={len(df)}")
""",
            "timeout_seconds": 20,
        },
    )

    assert run_response.status_code == 200, run_response.text
    payload = run_response.json()
    assert payload["status"] == "succeeded"
    assert payload["exit_code"] == 0
    assert "fast_path_rows=" in payload["stdout"]
