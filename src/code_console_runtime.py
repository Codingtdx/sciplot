from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pandas as pd
from matplotlib.axes import Axes
from matplotlib.figure import Figure

from src import plot_style
from src.plot_contract import size_preset_contract
from src.rendering.cache import read_raw_table_cached
from src.rendering.dataset_models import (
    build_normalized_dataset,
    dataframe_sample_rows,
    normalized_dataset_payload,
)
from src.rendering.style_composer import DEFAULT_STYLE_COMPOSER

CONTEXT_JSON_ENV = "CODEGOD_CODE_CONSOLE_CONTEXT_JSON"
OUTPUT_DIR_ENV = "OUTPUT_DIR"


def _require_env_path(name: str) -> Path:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return Path(value).expanduser().resolve()


def _ensure_child_path(root: Path, relative_name: str) -> Path:
    candidate = (root / relative_name).resolve()
    if candidate != root and root not in candidate.parents:
        raise ValueError("Output paths must stay inside OUTPUT_DIR.")
    candidate.parent.mkdir(parents=True, exist_ok=True)
    return candidate


@dataclass(frozen=True)
class CodeConsoleRuntimeContext:
    input_path: Path
    sheet: str | int
    model: str
    template: str | None
    size: str
    width_mm: float
    height_mm: float
    style_preset: str
    palette_preset: str
    visual_theme_id: str | None
    prompt_text: str
    starter_code: str
    inspection: dict[str, Any]
    dataset: dict[str, Any] | None
    output_dir: Path

    @classmethod
    def from_environment(cls) -> CodeConsoleRuntimeContext:
        context_path = _require_env_path(CONTEXT_JSON_ENV)
        output_dir = _require_env_path(OUTPUT_DIR_ENV)
        payload = json.loads(context_path.read_text(encoding="utf-8"))
        return cls(
            input_path=Path(str(payload["input_path"])).expanduser().resolve(),
            sheet=payload["sheet"],
            model=str(payload["inspection"]["model"]),
            template=payload.get("template"),
            size=str(payload["options"]["size"]),
            width_mm=float(payload["options"]["width_mm"]),
            height_mm=float(payload["options"]["height_mm"]),
            style_preset=str(payload["options"]["style_preset"]),
            palette_preset=str(payload["options"]["palette_preset"]),
            visual_theme_id=payload["options"].get("visual_theme_id"),
            prompt_text=str(payload["prompt_text"]),
            starter_code=str(payload["starter_code"]),
            inspection=dict(payload["inspection"]),
            dataset=dict(payload["dataset"]) if payload.get("dataset") is not None else None,
            output_dir=output_dir,
        )

    def apply_style(
        self,
        *,
        style_preset: str | None = None,
        palette_preset: str | None = None,
        visual_theme_id: str | None = None,
    ) -> None:
        resolved_style = style_preset or self.style_preset
        resolved_theme = visual_theme_id if visual_theme_id is not None else self.visual_theme_id
        style_bundle = DEFAULT_STYLE_COMPOSER.compose(resolved_style, resolved_theme)
        plot_style.apply_style(
            style_bundle.publication_profile_id,
            palette_preset or self.palette_preset,
            soft_overrides=style_bundle.resolved_soft,
        )

    def new_figure(self, *, size: str | None = None) -> tuple[Figure, Axes]:
        self.apply_style()
        size_spec = size_preset_contract(size or self.size)
        return plot_style.create_panel_figure(
            width_mm=size_spec.width_mm,
            height_mm=size_spec.height_mm,
        )

    def output_path(self, relative_name: str) -> Path:
        if not relative_name.strip():
            raise ValueError("Output filename must not be empty.")
        return _ensure_child_path(self.output_dir, relative_name)

    def save_figure(
        self,
        figure: Figure,
        filename_stem: str,
        *,
        formats: tuple[str, ...] = ("pdf",),
        dpi: int = 220,
    ) -> list[Path]:
        cleaned_stem = filename_stem.strip().rstrip(".")
        if not cleaned_stem:
            raise ValueError("Figure filename stem must not be empty.")
        written: list[Path] = []
        for item in formats:
            normalized = item.lower().lstrip(".")
            if normalized == "pdf":
                output_path = self.output_path(f"{cleaned_stem}.pdf")
                plot_style.save_pdf(figure, output_path)
            elif normalized == "png":
                output_path = self.output_path(f"{cleaned_stem}.png")
                figure.savefig(output_path, format="png", dpi=dpi, facecolor="white", bbox_inches=None)
            else:
                raise ValueError(f"Unsupported figure format: {item}")
            written.append(output_path)
        return written

    def write_dataframe(self, frame: pd.DataFrame, relative_name: str, *, index: bool = False) -> Path:
        output_path = self.output_path(relative_name)
        if output_path.suffix.lower() in {".xlsx", ".xlsm"}:
            frame.to_excel(output_path, index=index)
        else:
            frame.to_csv(output_path, index=index)
        return output_path

    def write_text(self, text: str, relative_name: str) -> Path:
        output_path = self.output_path(relative_name)
        output_path.write_text(text, encoding="utf-8")
        return output_path

    def write_json(self, payload: dict[str, Any], relative_name: str) -> Path:
        output_path = self.output_path(relative_name)
        output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        return output_path

    def load_raw_dataframe(self) -> pd.DataFrame:
        return read_raw_table_cached(self.input_path, self.sheet).copy()

    def load_normalized_dataset_payload(self) -> dict[str, Any]:
        if self.model == "raw_table":
            if self.dataset is not None:
                return dict(self.dataset)
            raw = self.load_raw_dataframe().dropna(axis=1, how="all")
            return {
                "dataset_id": "raw_table",
                "source_path": str(self.input_path),
                "sheet": self.sheet,
                "model": "raw_table",
                "raw_rows": int(raw.shape[0]),
                "raw_cols": int(raw.shape[1]),
                "column_profiles": [],
                "candidate_roles": {},
                "data_shapes": ["table"],
                "semantic_signals": ["Raw table fallback context."],
                "quality_flags": ["code_console_raw_table_fallback"],
                "sample_rows": dataframe_sample_rows(raw),
            }
        normalized = build_normalized_dataset(self.input_path, self.sheet, model=self.model)
        raw = self.load_raw_dataframe().dropna(axis=1, how="all")
        return {
            **normalized_dataset_payload(normalized),
            "sample_rows": dataframe_sample_rows(raw),
        }


console = CodeConsoleRuntimeContext.from_environment()


__all__ = [
    "CONTEXT_JSON_ENV",
    "OUTPUT_DIR_ENV",
    "CodeConsoleRuntimeContext",
    "console",
]
