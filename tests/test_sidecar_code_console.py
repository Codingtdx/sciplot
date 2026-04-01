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
    assert payload["input_path"] == str(input_path)
    assert payload["template"] == "curve"
    assert payload["inspection"]["model"] == "curve_table"
    assert "src.code_console_runtime" in payload["prompt_text"]
    assert "console.save_figure" in payload["starter_code"]


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
