from __future__ import annotations

import time
from pathlib import Path

import pandas as pd

from src.code_console_runner import PersistentCodeConsoleRunner
from src.code_console_service import build_code_console_context, run_code_console_script


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


def test_code_console_context_id_is_stable_and_invalidates_on_mtime(tmp_path: Path) -> None:
    input_path = tmp_path / "curve.csv"
    _make_curve_csv(input_path)

    first = build_code_console_context(
        input_path=input_path,
        sheet=0,
        template="curve",
        size=None,
        style_preset=None,
        palette_preset=None,
        visual_theme_id=None,
    )
    second = build_code_console_context(
        input_path=input_path,
        sheet=0,
        template="curve",
        size=None,
        style_preset=None,
        palette_preset=None,
        visual_theme_id=None,
    )
    assert first.context_id == second.context_id

    time.sleep(0.01)
    input_path.write_text(input_path.read_text(encoding="utf-8") + "\n", encoding="utf-8")

    third = build_code_console_context(
        input_path=input_path,
        sheet=0,
        template="curve",
        size=None,
        style_preset=None,
        palette_preset=None,
        visual_theme_id=None,
    )
    assert third.context_id != first.context_id


def test_code_console_prompt_uses_ranked_recommendations(tmp_path: Path) -> None:
    input_path = tmp_path / "curve.csv"
    _make_curve_csv(input_path)

    context = build_code_console_context(
        input_path=input_path,
        sheet=0,
        template="curve",
        size=None,
        style_preset=None,
        palette_preset=None,
        visual_theme_id=None,
    )

    assert "Ranked template candidates:" in context.prompt_text
    assert "1. curve" in context.prompt_text
    assert "No built-in template recommendation is available." not in context.prompt_text


def test_code_console_run_falls_back_to_subprocess_when_runner_fails(
    tmp_path: Path,
    monkeypatch,
) -> None:
    input_path = tmp_path / "curve.csv"
    _make_curve_csv(input_path)
    context = build_code_console_context(
        input_path=input_path,
        sheet=0,
        template="curve",
        size=None,
        style_preset=None,
        palette_preset=None,
        visual_theme_id=None,
    )

    def fail_runner(*args, **kwargs):
        raise RuntimeError("forced-runner-failure")

    monkeypatch.setattr("src.code_console_service.DEFAULT_RUNNER_MANAGER.run", fail_runner)

    result = run_code_console_script(
        context_id=context.context_id,
        code='print("fallback_ok")',
        timeout_seconds=20,
    )
    assert result.status == "succeeded"
    assert result.exit_code == 0
    assert "fallback_ok" in result.stdout
    assert "fell back to subprocess" in result.stderr


def test_persistent_runner_recovers_after_timeout(tmp_path: Path) -> None:
    runner = PersistentCodeConsoleRunner()
    try:
        context_json = tmp_path / "context.json"
        context_json.write_text("{}", encoding="utf-8")
        output_dir = tmp_path / "outputs"
        output_dir.mkdir(parents=True, exist_ok=True)

        timeout_script = tmp_path / "timeout.py"
        timeout_script.write_text("import time\ntime.sleep(2)\n", encoding="utf-8")
        timeout_result = runner.run(
            script_path=timeout_script,
            repo_root=Path(__file__).resolve().parents[1],
            output_dir=output_dir,
            context_json_path=context_json,
            timeout_seconds=1,
        )
        assert timeout_result.status == "timed_out"

        success_script = tmp_path / "success.py"
        success_script.write_text('print("runner_recovered")\n', encoding="utf-8")
        success_result = runner.run(
            script_path=success_script,
            repo_root=Path(__file__).resolve().parents[1],
            output_dir=output_dir,
            context_json_path=context_json,
            timeout_seconds=10,
        )
        assert success_result.status == "succeeded"
        assert success_result.exit_code == 0
        assert "runner_recovered" in success_result.stdout
    finally:
        runner._restart_executor()  # noqa: SLF001
