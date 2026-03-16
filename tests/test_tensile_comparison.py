from __future__ import annotations

from pathlib import Path

import fitz
import openpyxl
import pandas as pd
import pytest

from src.data_loader import load_curve_table, load_replicate_table
from src.rendering.tensile_compare import export_tensile_comparison_bundle, inspect_tensile_workbook
from src.tensile_replicates import export_tensile_replicate_workbook

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "tests" / "fixtures" / "tensile_raw"


def _make_workbook(path: Path, *, group_name: str = "BlendSet") -> Path:
    export_tensile_replicate_workbook(
        [
            FIXTURE_DIR / "BlendSet_A.csv",
            FIXTURE_DIR / "BlendSet_B.csv",
            FIXTURE_DIR / "BlendSet_bad.csv",
        ],
        path,
        group_name=group_name,
    )
    return path


def _pdf_size_mm(path: Path) -> tuple[float, float]:
    document = fitz.open(path)
    try:
        return (
            document[0].rect.width / 72.0 * 25.4,
            document[0].rect.height / 72.0 * 25.4,
        )
    finally:
        document.close()


def test_inspect_tensile_workbook_returns_summary(tmp_path: Path) -> None:
    workbook_path = _make_workbook(tmp_path / "solid.xlsx")

    summary = inspect_tensile_workbook(workbook_path)

    assert summary.workbook_path == workbook_path
    assert summary.label == "solid"
    assert summary.sample_count == 2
    assert summary.representative_filename in {"BlendSet_A.csv", "BlendSet_B.csv"}
    assert summary.sheet_names[0] == "Representative_Curve"
    assert [metric.label for metric in summary.metrics] == ["Strength", "Modulus", "Elongation"]


@pytest.mark.parametrize("group_count", [2, 3, 5])
def test_export_tensile_comparison_bundle_builds_workbook_and_outputs(
    tmp_path: Path,
    group_count: int,
) -> None:
    workbook_paths = []
    for index in range(group_count):
        workbook_paths.append(_make_workbook(tmp_path / f"group_{index + 1}.xlsx"))

    result = export_tensile_comparison_bundle(workbook_paths, tmp_path / "exports")

    assert result.bundle_dir.exists()
    assert result.comparison_workbook_path.exists()
    assert len(result.outputs) == 7
    assert all(path.exists() for path in result.outputs)

    with pd.ExcelFile(result.comparison_workbook_path) as workbook:
        assert workbook.sheet_names == [
            "Representative_Curve",
            "Strength_Replicates",
            "Modulus_Replicates",
            "Elongation_Replicates",
            "Summary",
        ]

    representative_series = load_curve_table(result.comparison_workbook_path, sheet_name="Representative_Curve")
    assert len(representative_series) == group_count

    strength_groups = load_replicate_table(result.comparison_workbook_path, sheet_name="Strength_Replicates")
    modulus_groups = load_replicate_table(result.comparison_workbook_path, sheet_name="Modulus_Replicates")
    elongation_groups = load_replicate_table(result.comparison_workbook_path, sheet_name="Elongation_Replicates")
    assert len(strength_groups) == group_count
    assert len(modulus_groups) == group_count
    assert len(elongation_groups) == group_count


def test_export_tensile_comparison_bundle_keeps_standard_plot_size(tmp_path: Path) -> None:
    workbook_paths = [_make_workbook(tmp_path / f"group_{index + 1}.xlsx") for index in range(5)]

    result = export_tensile_comparison_bundle(workbook_paths, tmp_path / "exports")

    for output_path in result.outputs:
        width_mm, height_mm = _pdf_size_mm(output_path)
        assert width_mm == pytest.approx(60.0, abs=0.2)
        assert height_mm == pytest.approx(55.0, abs=0.2)


def test_export_tensile_comparison_bundle_rejects_fewer_than_two_groups(tmp_path: Path) -> None:
    workbook_path = _make_workbook(tmp_path / "solid.xlsx")

    with pytest.raises(ValueError, match="至少需要 2 组"):
        export_tensile_comparison_bundle([workbook_path], tmp_path / "exports")


def test_export_tensile_comparison_bundle_rejects_missing_required_sheet(tmp_path: Path) -> None:
    workbook_path = _make_workbook(tmp_path / "solid.xlsx")
    workbook = openpyxl.load_workbook(workbook_path)
    workbook.remove(workbook["Strength_Replicates"])
    workbook.save(workbook_path)
    workbook.close()

    with pytest.raises(ValueError, match="缺少必需工作表"):
        export_tensile_comparison_bundle(
            [workbook_path, _make_workbook(tmp_path / "other.xlsx")],
            tmp_path / "exports",
        )


def test_export_tensile_comparison_bundle_rejects_empty_replicate_sheet(tmp_path: Path) -> None:
    workbook_path = _make_workbook(tmp_path / "solid.xlsx")
    with pd.ExcelWriter(workbook_path, mode="a", if_sheet_exists="replace") as writer:
        pd.DataFrame([["Strength"], ["Broken"], ["MPa"]]).to_excel(
            writer,
            sheet_name="Strength_Replicates",
            header=False,
            index=False,
        )

    with pytest.raises(ValueError, match="不是有效重复值表|没有有效重复值|没有可用的重复值数字"):
        export_tensile_comparison_bundle(
            [workbook_path, _make_workbook(tmp_path / "other.xlsx")],
            tmp_path / "exports",
        )


def test_export_tensile_comparison_bundle_rejects_inconsistent_metric_units(tmp_path: Path) -> None:
    left = _make_workbook(tmp_path / "solid.xlsx")
    right = _make_workbook(tmp_path / "other.xlsx")
    with pd.ExcelWriter(right, mode="a", if_sheet_exists="replace") as writer:
        pd.DataFrame(
            [
                ["Strength"],
                ["Other"],
                ["kPa"],
                [10.0],
                [12.0],
            ]
        ).to_excel(
            writer,
            sheet_name="Strength_Replicates",
            header=False,
            index=False,
        )

    with pytest.raises(ValueError, match="单位或标签不一致"):
        export_tensile_comparison_bundle([left, right], tmp_path / "exports")


def test_export_tensile_comparison_bundle_dedupes_duplicate_file_stems(tmp_path: Path) -> None:
    left_dir = tmp_path / "left"
    right_dir = tmp_path / "right"
    left_dir.mkdir()
    right_dir.mkdir()
    left = _make_workbook(left_dir / "solid.xlsx")
    right = _make_workbook(right_dir / "solid.xlsx")

    result = export_tensile_comparison_bundle([left, right], tmp_path / "exports")

    assert result.labels == ("solid", "solid (2)")
