from __future__ import annotations

import os
import time
from pathlib import Path

import pandas as pd

from src.rendering import cache as rendering_cache


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
