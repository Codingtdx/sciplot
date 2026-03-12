from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import pandas as pd

from src.data_loader import load_curve_table


class DataLoaderTests(unittest.TestCase):
    def _write_csv(self, rows: list[list[object]]) -> Path:
        handle = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, newline="")
        path = Path(handle.name)
        handle.close()
        pd.DataFrame(rows).to_csv(path, header=False, index=False)
        self.addCleanup(path.unlink, missing_ok=True)
        return path

    def test_curve_table_rejects_missing_sample_header(self) -> None:
        path = self._write_csv(
            [
                ["Time", "Stress"],
                ["s", "MPa"],
                ["", ""],
                [0, 1.2],
            ]
        )

        with self.assertRaisesRegex(ValueError, "Curve table is missing a valid sample row."):
            load_curve_table(path)

    def test_curve_table_rejects_odd_columns(self) -> None:
        path = self._write_csv(
            [
                ["Time", "Stress", "Time"],
                ["s", "MPa", "s"],
                ["Sample A", "Sample A", "Sample B"],
                [0, 1.0, 0],
                [1, 1.4, 1],
            ]
        )

        with self.assertRaisesRegex(
            ValueError,
            "Curve table must contain an even number of columns arranged in X/Y pairs.",
        ):
            load_curve_table(path)

    def test_curve_table_rejects_non_numeric_data_region(self) -> None:
        path = self._write_csv(
            [
                ["Time", "Stress"],
                ["s", "MPa"],
                ["Sample A", "Sample A"],
                ["bad", "still bad"],
                ["nope", "broken"],
            ]
        )

        with self.assertRaisesRegex(
            ValueError,
            "Curve table columns 1 and 2 contain non-numeric values in the data region.",
        ):
            load_curve_table(path)


if __name__ == "__main__":
    unittest.main()
