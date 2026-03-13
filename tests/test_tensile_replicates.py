from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from src.tensile_replicates import export_tensile_replicate_workbook, parse_tensile_csv

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "tests" / "fixtures" / "tensile_raw"


class TensileReplicateTests(unittest.TestCase):
    def test_export_tensile_replicate_workbook_skips_bad_fixture(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            output_path = Path(tmpdir) / "blendset.xlsx"
            workbook = export_tensile_replicate_workbook(
                [
                    FIXTURE_DIR / "BlendSet_A.csv",
                    FIXTURE_DIR / "BlendSet_B.csv",
                    FIXTURE_DIR / "BlendSet_bad.csv",
                ],
                output_path,
                group_name="BlendSet",
            )

            self.assertTrue(output_path.exists())
            self.assertEqual(workbook.sample_count, 2)
            self.assertEqual(workbook.group_name, "BlendSet")
            self.assertEqual(workbook.preferred_sheet, "Representative_Curve")
            self.assertEqual(len(workbook.warnings), 1)
            self.assertIn("BlendSet_bad.csv", workbook.warnings[0])

    def test_parse_tensile_csv_rejects_unknown_binary_payload(self) -> None:
        with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as handle:
            path = Path(handle.name)
            handle.write(b"\x81\x82\x83\x84not-a-tensile-export")

        self.addCleanup(path.unlink, missing_ok=True)

        with self.assertRaisesRegex(ValueError, "无法用常见编码读出拉伸导出表。"):
            parse_tensile_csv(path)


if __name__ == "__main__":
    unittest.main()
