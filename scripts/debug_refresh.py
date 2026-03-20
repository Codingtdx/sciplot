from __future__ import annotations

import os
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from make_plot import render_template
from scripts.smoke_check import (
    _write_curve_table,
    _write_dma_curve_table,
    _write_heatmap_table,
    _write_replicate_table,
    _write_stacked_curve_table,
    _write_tga_curve_table,
    _write_wide_nmr_bundle,
)

DEBUG_OUTPUT_DIR = ROOT / "figures" / "debug_outputs"
REVIEW_OUTPUT_DIR = ROOT / "figures" / "review_examples"
TRASH_PATHS = [ROOT / "figures" / ".DS_Store"]
REAL_DATA_JOB_SPECS = [
    ("box", "CODEGOD_DEBUG_REFRESH_TENSILE_RAW_DATA", {}),
    ("bar", "CODEGOD_DEBUG_REFRESH_TENSILE_RAW_DATA", {}),
    ("point_line", "CODEGOD_DEBUG_REFRESH_FREQ_SWEEP", {"xscale": "log", "yscale": "log"}),
    ("point_line", "CODEGOD_DEBUG_REFRESH_TEMP_SWEEP", {"yscale": "log"}),
    ("point_line", "CODEGOD_DEBUG_REFRESH_STRESS_RELAXATION", {"xscale": "log"}),
]


def _reset_directory(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def _remove_data_dir_plots(paths: list[Path]) -> None:
    seen: set[Path] = set()
    for input_path in paths:
        plots_dir = input_path.parent / "plots"
        if plots_dir in seen:
            continue
        seen.add(plots_dir)
        if plots_dir.exists():
            shutil.rmtree(plots_dir)


def _resolve_real_data_jobs() -> list[tuple[str, Path, dict[str, object]]]:
    jobs: list[tuple[str, Path, dict[str, object]]] = []
    for template, env_name, options in REAL_DATA_JOB_SPECS:
        raw_path = os.environ.get(env_name)
        if not raw_path:
            print(f"skip real-data job: {template} ({env_name} not set)")
            continue
        input_path = Path(raw_path).expanduser()
        if not input_path.exists():
            print(f"skip real-data job: {template} ({env_name} missing file: {input_path})")
            continue
        jobs.append((template, input_path, dict(options)))
    return jobs


def _render_review_examples(output_dir: Path) -> list[Path]:
    outputs: list[Path] = []
    with tempfile.TemporaryDirectory(prefix="plot_review_refresh_") as tmp:
        base = Path(tmp)
        review_jobs = [
            ("stacked_curve", "ftir", base / "ftir.csv"),
            ("stacked_curve", "nmr", base / "nmr.csv"),
            ("segmented_stacked_curve", "wide_nmr", base / "wide_nmr.csv"),
            ("stacked_curve", "xrd", base / "xrd.csv"),
            ("stacked_curve", "dsc", base / "dsc.csv"),
            ("curve", "tga", base / "tga.csv"),
            ("curve", "dma", base / "dma.csv"),
            ("scatter", "scatter", base / "scatter.csv"),
            ("violin", "violin", base / "violin.csv"),
            ("heatmap", "heatmap", base / "heatmap.csv"),
        ]
        for template, stem, input_path in review_jobs:
            if stem in {"ftir", "nmr", "xrd", "dsc"}:
                _write_stacked_curve_table(input_path, template=stem)
                outputs.extend(
                    render_template(
                        template,
                        input_path,
                        output_dir,
                        reverse_x=stem in {"ftir", "nmr"},
                        baseline="linear_endpoints" if stem in {"nmr", "dsc"} else "none",
                    )
                )
            elif stem == "wide_nmr":
                _write_wide_nmr_bundle(input_path)
                outputs.extend(
                    render_template(
                        template,
                        input_path,
                        output_dir,
                        reverse_x=True,
                        baseline="linear_endpoints",
                        use_sidecar=True,
                    )
                )
            elif stem == "tga":
                _write_tga_curve_table(input_path)
                outputs.extend(render_template(template, input_path, output_dir))
            elif stem == "dma":
                _write_dma_curve_table(input_path)
                outputs.extend(render_template(template, input_path, output_dir))
            elif stem == "scatter":
                _write_curve_table(input_path, "Time", "Stress", "s", "MPa")
                outputs.extend(render_template(template, input_path, output_dir))
            elif stem == "violin":
                _write_replicate_table(input_path)
                outputs.extend(render_template(template, input_path, output_dir))
            elif stem == "heatmap":
                _write_heatmap_table(input_path)
                outputs.extend(render_template(template, input_path, output_dir))
            else:
                raise ValueError(f"Unsupported review template: {stem}")
    return outputs


def _render_real_data(output_dir: Path, jobs: list[tuple[str, Path, dict[str, object]]]) -> list[Path]:
    outputs: list[Path] = []
    for template, input_path, options in jobs:
        print(f"run real-data job: {template} <- {input_path}")
        outputs.extend(render_template(template, input_path, output_dir, **options))
    return outputs


def main() -> int:
    real_data_jobs = _resolve_real_data_jobs()

    for path in TRASH_PATHS:
        path.unlink(missing_ok=True)
    _reset_directory(DEBUG_OUTPUT_DIR)
    _reset_directory(REVIEW_OUTPUT_DIR)
    _remove_data_dir_plots([path for _, path, _ in real_data_jobs])

    outputs = []
    outputs.extend(_render_review_examples(REVIEW_OUTPUT_DIR))
    outputs.extend(_render_real_data(DEBUG_OUTPUT_DIR, real_data_jobs))

    for output in outputs:
        print(output.resolve())
    print("Debug refresh completed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
