from __future__ import annotations

import pytest

from scripts import smoke_check


def test_help_exits_without_running_smoke(monkeypatch, capsys) -> None:
    def fail_smoke(_base):
        raise AssertionError("--help should not execute the smoke workspace")

    monkeypatch.setattr(smoke_check, "_run_smoke_workspace", fail_smoke)

    with pytest.raises(SystemExit) as exc_info:
        smoke_check.main(["--help"])

    assert exc_info.value.code == 0
    assert "smoke" in capsys.readouterr().out.lower()


def test_error_validation_fails_smoke_report_gate() -> None:
    reports = [
        {
            "id": "non_blank_pdf",
            "label": "Non-blank exported PDF",
            "severity": "error",
            "passed": False,
            "details": {"filename": "blank.pdf"},
        }
    ]

    with pytest.raises(AssertionError, match="non_blank_pdf"):
        smoke_check._assert_no_failed_error_validations(reports)


def test_warning_validation_does_not_fail_smoke_report_gate() -> None:
    reports = [
        {
            "id": "multi_output_bundle_notice",
            "label": "Multi-output notice",
            "severity": "warning",
            "passed": False,
            "details": {"template": "point_line"},
        }
    ]

    smoke_check._assert_no_failed_error_validations(reports)
