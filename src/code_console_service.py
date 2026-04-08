from __future__ import annotations

import json
import os
import subprocess
import sys
import textwrap
import time
from dataclasses import asdict, dataclass, is_dataclass
from pathlib import Path
from typing import Any

from src import plot_style
from src.infrastructure.persistence.code_console_runs import prepare_managed_code_console_run_dir
from src.plot_contract import template_contract
from src.rendering.cache import read_raw_table_cached
from src.rendering.dataset_models import (
    build_normalized_dataset,
    dataframe_sample_rows,
    normalized_dataset_payload,
)
from src.rendering.io import coerce_sheet, list_sheet_names
from src.rendering.options import resolve_render_options, validate_template_name
from src.rendering.recommendation import inspect_input_file
from src.text_normalization import slugify_label

REPO_ROOT = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class CodeConsoleResolvedContext:
    input_path: Path
    sheet: str | int
    sheet_names: tuple[str, ...]
    inspection: dict[str, Any]
    dataset: dict[str, Any] | None
    template: str
    options: dict[str, Any]
    prompt_text: str
    starter_code: str
    source_kind: str | None = None
    source_label: str | None = None


@dataclass(frozen=True)
class CodeConsoleGeneratedFile:
    path: Path
    name: str
    file_type: str
    size_bytes: int


@dataclass(frozen=True)
class CodeConsoleRunResult:
    status: str
    exit_code: int | None
    duration_seconds: float
    stdout: str
    stderr: str
    run_dir: Path
    output_dir: Path
    script_path: Path
    prompt_path: Path
    context_path: Path
    stdout_path: Path
    stderr_path: Path
    generated_files: tuple[CodeConsoleGeneratedFile, ...]


def _json_ready(value: Any) -> Any:
    if is_dataclass(value) and not isinstance(value, type):
        return {key: _json_ready(item) for key, item in asdict(value).items()}
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, dict):
        return {key: _json_ready(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_ready(item) for item in value]
    return value


def _truncate_cell(value: object, *, max_chars: int = 48) -> object:
    text = str(value)
    if len(text) <= max_chars:
        return value
    return f"{text[: max_chars - 1]}…"


def _safe_sample_rows(
    dataset: dict[str, Any] | None,
    *,
    limit_rows: int = 6,
    limit_cols: int = 8,
) -> list[list[object]]:
    if not dataset:
        return []
    sample_rows = dataset.get("sample_rows", [])
    safe_rows: list[list[object]] = []
    for row in sample_rows[:limit_rows]:
        if not isinstance(row, list):
            continue
        safe_rows.append([_truncate_cell(item) for item in row[:limit_cols]])
    return safe_rows


def _series_hint(inspection: dict[str, Any]) -> str:
    recommendation = inspection.get("recommendation", {})
    template = recommendation.get("template")
    if template:
        return f"Preferred built-in template: `{template}`."
    return "No built-in template recommendation is available."


def _build_prompt(
    *,
    context: CodeConsoleResolvedContext,
) -> str:
    dataset = context.dataset or {}
    prompt_payload = {
        "input_path": str(context.input_path),
        "sheet": context.sheet,
        "sheet_names": list(context.sheet_names),
        "model": context.inspection.get("model"),
        "model_label": context.inspection.get("model_label"),
        "recommended_template": context.template,
        "style_preset": context.options["style_preset"],
        "palette_preset": context.options["palette_preset"],
        "size": context.options["size"],
        "visual_theme_id": context.options.get("visual_theme_id"),
        "semantic_signals": dataset.get("semantic_signals", []),
        "candidate_roles": dataset.get("candidate_roles", {}),
        "sample_rows": _safe_sample_rows(dataset),
    }
    source_line = (
        f"- Bound source: {context.source_label} ({context.source_kind}).\n"
        if context.source_label and context.source_kind
        else ""
    )
    return textwrap.dedent(
        f"""
        Write one Python script for the SciPlot God Code Console.

        Requirements:
        - Return Python code only. Do not wrap the answer in markdown fences.
        - The script will run with the repo root as the working directory.
        - Read the already selected dataset at `{context.input_path}` and sheet `{context.sheet}`.
        - Use repo-native helpers so the figure keeps SciPlot God styling.
        - External AI should handle fitting / derived analysis / custom overlays, not restyle the whole figure system.
        - Save every generated file inside `OUTPUT_DIR` only.
        - Print a short textual summary of what the script generated.

        Use this helper API:
        ```python
        from src.code_console_runtime import console

        df = console.load_raw_dataframe()
        normalized = console.load_normalized_dataset_payload()
        fig, ax = console.new_figure()
        console.save_figure(fig, "result_name")
        console.write_dataframe(df, "derived_table.csv", index=False)
        ```

        Styling target:
        - Style preset: `{context.options["style_preset"]}`
        - Palette preset: `{context.options["palette_preset"]}`
        - Size preset: `{context.options["size"]}`
        - Visual theme: `{context.options.get("visual_theme_id") or "none"}`
        - {_series_hint(context.inspection)}

        {source_line}Context snapshot:
        ```json
        {json.dumps(prompt_payload, ensure_ascii=False, indent=2)}
        ```
        """
    ).strip()


def _build_starter_code(*, context: CodeConsoleResolvedContext) -> str:
    output_stem = slugify_label(context.input_path.stem) or "code_console_output"
    return textwrap.dedent(
        f"""
        from src.code_console_runtime import console

        df = console.load_raw_dataframe()
        normalized = console.load_normalized_dataset_payload()

        fig, ax = console.new_figure()

        # Replace this placeholder plot with fitted data / derived overlays from the external AI.
        ax.plot([0, 1], [0, 1])
        ax.set_title("{context.inspection.get("model_label", "Code Console")}")

        console.save_figure(fig, "{output_stem}")
        console.write_json(normalized, "{output_stem}_normalized_dataset.json")

        print(f"Generated {{len(df)}} raw rows and saved outputs to {{console.output_dir}}")
        """
    ).strip()


def build_code_console_context(
    *,
    input_path: Path,
    sheet: str | int,
    template: str | None,
    size: str | None,
    style_preset: str | None,
    palette_preset: str | None,
    visual_theme_id: str | None,
    source_kind: str | None = None,
    source_label: str | None = None,
) -> CodeConsoleResolvedContext:
    resolved_sheet = coerce_sheet(str(sheet))
    inspection = inspect_input_file(input_path, resolved_sheet)
    normalized_dataset = build_normalized_dataset(input_path, resolved_sheet, model=inspection.model)
    raw = read_raw_table_cached(input_path, resolved_sheet).dropna(axis=1, how="all")
    dataset_payload = {
        **normalized_dataset_payload(normalized_dataset),
        "sample_rows": dataframe_sample_rows(raw),
    }
    top_recommendation = (
        inspection.recommendations[0]
        if inspection.recommendations
        else (inspection.primary_recommendation[0] if inspection.primary_recommendation else None)
    )
    if top_recommendation is None:
        raise ValueError("Inspection did not return any template recommendations.")
    recommended_size = top_recommendation.preview_config_summary.get("size")
    resolved_template = validate_template_name(template or top_recommendation.template_id)
    resolved_render_options = resolve_render_options(
        template=resolved_template,
        size=size or (str(recommended_size) if recommended_size is not None else None),
        style_preset=style_preset or plot_style.DEFAULT_STYLE_PRESET,
        palette_preset=palette_preset or plot_style.DEFAULT_PALETTE_PRESET,
        visual_theme_id=visual_theme_id,
    )
    context = CodeConsoleResolvedContext(
        input_path=input_path.resolve(),
        sheet=resolved_sheet,
        sheet_names=tuple(list_sheet_names(input_path)),
        inspection=_json_ready(inspection),
        dataset=_json_ready(dataset_payload),
        template=resolved_template,
        options={
            "size": size
            or (
                str(recommended_size)
                if recommended_size is not None
                else template_contract(resolved_template).default_size
            ),
            "width_mm": resolved_render_options.width_mm,
            "height_mm": resolved_render_options.height_mm,
            "style_preset": resolved_render_options.style_preset,
            "palette_preset": resolved_render_options.palette_preset,
            "visual_theme_id": resolved_render_options.visual_theme_id,
        },
        prompt_text="",
        starter_code="",
        source_kind=source_kind,
        source_label=source_label,
    )
    prompt_text = _build_prompt(context=context)
    starter_code = _build_starter_code(context=context)
    return CodeConsoleResolvedContext(
        input_path=context.input_path,
        sheet=context.sheet,
        sheet_names=context.sheet_names,
        inspection=context.inspection,
        dataset=context.dataset,
        template=context.template,
        options=context.options,
        prompt_text=prompt_text,
        starter_code=starter_code,
        source_kind=context.source_kind,
        source_label=context.source_label,
    )


def _serialize_context(context: CodeConsoleResolvedContext) -> dict[str, Any]:
    return {
        "input_path": str(context.input_path),
        "sheet": context.sheet,
        "sheet_names": list(context.sheet_names),
        "inspection": context.inspection,
        "dataset": context.dataset,
        "template": context.template,
        "options": context.options,
        "prompt_text": context.prompt_text,
        "starter_code": context.starter_code,
        "source_kind": context.source_kind,
        "source_label": context.source_label,
    }


def _generated_files(output_dir: Path) -> tuple[CodeConsoleGeneratedFile, ...]:
    if not output_dir.exists():
        return ()
    files = [path for path in output_dir.rglob("*") if path.is_file()]
    files.sort(key=lambda item: item.relative_to(output_dir).as_posix())
    return tuple(
        CodeConsoleGeneratedFile(
            path=path,
            name=path.relative_to(output_dir).as_posix(),
            file_type=(path.suffix.lower().lstrip(".") or "file"),
            size_bytes=path.stat().st_size,
        )
        for path in files
    )


def _coerce_subprocess_text(value: bytes | str | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def run_code_console_script(
    *,
    input_path: Path,
    sheet: str | int,
    template: str | None,
    size: str | None,
    style_preset: str | None,
    palette_preset: str | None,
    visual_theme_id: str | None,
    code: str,
    timeout_seconds: int,
    source_kind: str | None = None,
    source_label: str | None = None,
) -> CodeConsoleRunResult:
    context = build_code_console_context(
        input_path=input_path,
        sheet=sheet,
        template=template,
        size=size,
        style_preset=style_preset,
        palette_preset=palette_preset,
        visual_theme_id=visual_theme_id,
        source_kind=source_kind,
        source_label=source_label,
    )
    run_dir = prepare_managed_code_console_run_dir(input_path, sheet=context.sheet)
    output_dir = run_dir / "outputs"
    output_dir.mkdir(parents=True, exist_ok=True)
    prompt_path = run_dir / "external_ai_prompt.txt"
    context_path = run_dir / "context.json"
    script_path = run_dir / "user_code.py"
    stdout_path = run_dir / "stdout.txt"
    stderr_path = run_dir / "stderr.txt"

    prompt_path.write_text(context.prompt_text, encoding="utf-8")
    context_path.write_text(
        json.dumps(_serialize_context(context), ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    script_path.write_text(code, encoding="utf-8")

    environment = dict(os.environ)
    existing_pythonpath = environment.get("PYTHONPATH", "").strip()
    environment["PYTHONPATH"] = (
        f"{REPO_ROOT}{os.pathsep}{existing_pythonpath}" if existing_pythonpath else str(REPO_ROOT)
    )
    environment["PYTHONUNBUFFERED"] = "1"
    environment["OUTPUT_DIR"] = str(output_dir)
    environment["CODEGOD_CODE_CONSOLE_CONTEXT_JSON"] = str(context_path)

    started_at = time.perf_counter()
    try:
        completed = subprocess.run(
            [sys.executable, str(script_path)],
            cwd=str(REPO_ROOT),
            env=environment,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
        duration_seconds = time.perf_counter() - started_at
        status = "succeeded" if completed.returncode == 0 else "failed"
        stdout = completed.stdout
        stderr = completed.stderr
        exit_code = completed.returncode
    except subprocess.TimeoutExpired as exc:
        duration_seconds = time.perf_counter() - started_at
        status = "timed_out"
        stdout = _coerce_subprocess_text(exc.stdout)
        stderr = _coerce_subprocess_text(exc.stderr) + (
            f"\nCode Console timed out after {timeout_seconds} seconds."
            if timeout_seconds > 0
            else "\nCode Console timed out."
        )
        exit_code = None

    stdout_path.write_text(stdout, encoding="utf-8")
    stderr_path.write_text(stderr, encoding="utf-8")

    return CodeConsoleRunResult(
        status=status,
        exit_code=exit_code,
        duration_seconds=round(duration_seconds, 3),
        stdout=stdout,
        stderr=stderr,
        run_dir=run_dir,
        output_dir=output_dir,
        script_path=script_path,
        prompt_path=prompt_path,
        context_path=context_path,
        stdout_path=stdout_path,
        stderr_path=stderr_path,
        generated_files=_generated_files(output_dir),
    )


__all__ = [
    "CodeConsoleGeneratedFile",
    "CodeConsoleResolvedContext",
    "CodeConsoleRunResult",
    "build_code_console_context",
    "run_code_console_script",
]
