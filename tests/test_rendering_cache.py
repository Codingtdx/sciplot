from __future__ import annotations

import os
import time
from pathlib import Path

import pandas as pd

from src.rendering import cache as rendering_cache
from src.rendering import dataset_models
from src.rendering import recommendation as rendering_recommendation


def _write_curve_table(path: Path) -> Path:
    rows = [
        ["Time", "Stress", "Time", "Stress"],
        ["s", "MPa", "s", "MPa"],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
        [0, 1.0, 0, 2.0],
        [1, 1.3, 1, 2.4],
        [2, 1.5, 2, 2.8],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def test_read_raw_table_cache_hits_and_clones_results(tmp_path: Path, monkeypatch) -> None:
    path = tmp_path / "table.csv"
    path.write_text("placeholder\n", encoding="utf-8")
    calls: list[tuple[Path, str | int]] = []

    def fake_read_raw_table(input_path: Path, sheet_name: str | int = 0) -> pd.DataFrame:
        calls.append((input_path, sheet_name))
        return pd.DataFrame([[1, 2], [3, 4]])

    rendering_cache.clear_input_cache()
    monkeypatch.setattr(rendering_cache, "read_raw_table", fake_read_raw_table)

    first = rendering_cache.read_raw_table_cached(path, 0)
    second = rendering_cache.read_raw_table_cached(path, 0)

    assert len(calls) == 1
    assert first.equals(second)

    first.iloc[0, 0] = 999
    third = rendering_cache.read_raw_table_cached(path, 0)
    assert third.iloc[0, 0] == 1


def test_read_raw_table_cache_invalidates_on_mtime_change(tmp_path: Path, monkeypatch) -> None:
    path = tmp_path / "table.csv"
    path.write_text("placeholder\n", encoding="utf-8")
    calls: list[int] = []

    def fake_read_raw_table(input_path: Path, sheet_name: str | int = 0) -> pd.DataFrame:
        calls.append(1)
        return pd.DataFrame([[sheet_name]])

    rendering_cache.clear_input_cache()
    monkeypatch.setattr(rendering_cache, "read_raw_table", fake_read_raw_table)

    rendering_cache.read_raw_table_cached(path, 0)
    stat = path.stat()
    next_ns = max(time.time_ns(), stat.st_mtime_ns + 1_000_000)
    os.utime(path, ns=(next_ns, next_ns))
    rendering_cache.read_raw_table_cached(path, 0)

    assert len(calls) == 2


def test_read_raw_table_cache_isolates_sheet_keys(tmp_path: Path, monkeypatch) -> None:
    path = tmp_path / "table.csv"
    path.write_text("placeholder\n", encoding="utf-8")
    calls: list[str | int] = []

    def fake_read_raw_table(input_path: Path, sheet_name: str | int = 0) -> pd.DataFrame:
        calls.append(sheet_name)
        return pd.DataFrame([[sheet_name]])

    rendering_cache.clear_input_cache()
    monkeypatch.setattr(rendering_cache, "read_raw_table", fake_read_raw_table)

    rendering_cache.read_raw_table_cached(path, 0)
    rendering_cache.read_raw_table_cached(path, "Summary")
    rendering_cache.read_raw_table_cached(path, 0)

    assert calls == [0, "Summary"]


def test_normalized_dataset_cache_reuses_detection_for_unchanged_input(
    tmp_path: Path,
    monkeypatch,
) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")
    calls: list[tuple[Path, str | int]] = []
    original_detect_input_model = dataset_models.detect_input_model

    def tracking_detect_input_model(path: Path, sheet: str | int = 0) -> str:
        calls.append((path, sheet))
        return original_detect_input_model(path, sheet)

    dataset_models.clear_normalized_dataset_cache()
    monkeypatch.setattr(dataset_models, "detect_input_model", tracking_detect_input_model)

    dataset_models.build_normalized_dataset(input_path)
    dataset_models.build_normalized_dataset(input_path)

    assert calls == [(input_path, 0)]


def test_normalized_dataset_cache_invalidates_on_mtime_change(
    tmp_path: Path,
    monkeypatch,
) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")
    calls: list[tuple[Path, str | int]] = []
    original_detect_input_model = dataset_models.detect_input_model

    def tracking_detect_input_model(path: Path, sheet: str | int = 0) -> str:
        calls.append((path, sheet))
        return original_detect_input_model(path, sheet)

    dataset_models.clear_normalized_dataset_cache()
    monkeypatch.setattr(dataset_models, "detect_input_model", tracking_detect_input_model)

    dataset_models.build_normalized_dataset(input_path)
    stat = input_path.stat()
    next_ns = max(time.time_ns(), stat.st_mtime_ns + 1_000_000)
    os.utime(input_path, ns=(next_ns, next_ns))
    dataset_models.build_normalized_dataset(input_path)

    assert len(calls) == 2


def test_inspect_input_cache_reuses_recommender_for_unchanged_input(tmp_path: Path, monkeypatch) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")
    calls: list[int] = []
    original_recommend = rendering_recommendation.DEFAULT_RECOMMENDER.recommend

    def tracking_recommend(dataset, *, limit: int):
        calls.append(limit)
        return original_recommend(dataset, limit=limit)

    rendering_recommendation.clear_inspection_cache()
    monkeypatch.setattr(rendering_recommendation.DEFAULT_RECOMMENDER, "recommend", tracking_recommend)

    rendering_recommendation.inspect_input_file(input_path)
    rendering_recommendation.inspect_input_file(input_path)

    assert calls == [rendering_recommendation.INSPECTION_RECOMMENDATION_LIMIT]


def test_inspect_input_cache_invalidates_on_mtime_change(tmp_path: Path, monkeypatch) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")
    calls: list[int] = []
    original_recommend = rendering_recommendation.DEFAULT_RECOMMENDER.recommend

    def tracking_recommend(dataset, *, limit: int):
        calls.append(limit)
        return original_recommend(dataset, limit=limit)

    rendering_recommendation.clear_inspection_cache()
    monkeypatch.setattr(rendering_recommendation.DEFAULT_RECOMMENDER, "recommend", tracking_recommend)

    rendering_recommendation.inspect_input_file(input_path)
    stat = input_path.stat()
    next_ns = max(time.time_ns(), stat.st_mtime_ns + 1_000_000)
    os.utime(input_path, ns=(next_ns, next_ns))
    rendering_recommendation.inspect_input_file(input_path)

    assert len(calls) == 2
