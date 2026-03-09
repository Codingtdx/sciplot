from __future__ import annotations

import shutil
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from make_plot import render_template
from scripts.smoke_check import (
    _write_dma_curve_table,
    _write_heatmap_table,
    _write_stacked_curve_table,
    _write_tga_curve_table,
    _write_curve_table,
    _write_replicate_table,
    _write_wide_nmr_bundle,
)


DEBUG_OUTPUT_DIR = ROOT / "figures" / "debug_outputs"
REVIEW_OUTPUT_DIR = ROOT / "figures" / "review_examples"
TRASH_PATHS = [ROOT / "figures" / ".DS_Store"]

REAL_DATA_JOBS = [
    (
        "box",
        Path("/Users/dongxutian/Desktop/Polymer_Research/Tension/Tensile/PA-ADR-1/3 strength/箱线图/modulus/Raw_Data.xlsx"),
        {},
    ),
    (
        "bar",
        Path("/Users/dongxutian/Desktop/Polymer_Research/Tension/Tensile/PA-ADR-1/3 strength/箱线图/modulus/Raw_Data.xlsx"),
        {},
    ),
    (
        "point_line",
        Path("/Users/dongxutian/Library/CloudStorage/OneDrive-HKUST(Guangzhou)/1 Vitrimer/3 D PA/流变/freq/1/freq1.xlsx"),
        {"xscale": "log", "yscale": "log"},
    ),
    (
        "point_line",
        Path("/Users/dongxutian/Library/CloudStorage/OneDrive-HKUST(Guangzhou)/1 Vitrimer/3 D PA/流变/temp/1/temp1.xlsx"),
        {"yscale": "log"},
    ),
    (
        "point_line",
        Path("/Users/dongxutian/Library/CloudStorage/OneDrive-HKUST(Guangzhou)/1 Vitrimer/3 D PA/流变/stresss relaxation/1/stress relaxation.xlsx"),
        {"xscale": "log"},
    ),
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


def _render_real_data(output_dir: Path) -> list[Path]:
    outputs: list[Path] = []
    for template, input_path, options in REAL_DATA_JOBS:
        if not input_path.exists():
            raise FileNotFoundError(f"Missing expected real-data input: {input_path}")
        outputs.extend(render_template(template, input_path, output_dir, **options))
    return outputs


def main() -> int:
    for path in TRASH_PATHS:
        path.unlink(missing_ok=True)
    _reset_directory(DEBUG_OUTPUT_DIR)
    _reset_directory(REVIEW_OUTPUT_DIR)
    _remove_data_dir_plots([path for _, path, _ in REAL_DATA_JOBS])

    outputs = []
    outputs.extend(_render_review_examples(REVIEW_OUTPUT_DIR))
    outputs.extend(_render_real_data(DEBUG_OUTPUT_DIR))

    for output in outputs:
        print(output.resolve())
    print("Debug refresh completed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
