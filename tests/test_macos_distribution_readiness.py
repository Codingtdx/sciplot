from __future__ import annotations

from pathlib import Path

from scripts import check_macos_distribution_readiness as readiness

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "app" / "macos" / "SciPlot.xcodeproj" / "project.pbxproj"
INFO_PLIST = ROOT / "app" / "macos" / "Info.plist"


def test_distribution_readiness_reports_local_dev_as_supported() -> None:
    report = readiness.build_readiness_report(project_path=PROJECT, info_plist_path=INFO_PLIST)

    local = next(item for item in report["modes"] if item["id"] == "local_unsigned")
    assert local["status"] == "passed"
    assert report["bundle_identifier"] == "io.github.codingtdx.sciplot.desktop"


def test_distribution_readiness_flags_signed_beta_blockers() -> None:
    report = readiness.build_readiness_report(project_path=PROJECT, info_plist_path=INFO_PLIST)

    signed = next(item for item in report["modes"] if item["id"] == "developer_signed_beta")
    assert signed["status"] == "blocked"
    assert "Code signing is disabled for the app target." in signed["blockers"]
    assert "Hardened runtime is disabled for the app target." in signed["blockers"]


def test_distribution_readiness_cli_returns_nonzero_when_required_mode_is_blocked(capsys) -> None:
    exit_code = readiness.main(
        [
            "--project",
            str(PROJECT),
            "--info-plist",
            str(INFO_PLIST),
            "--require-mode",
            "developer_signed_beta",
        ]
    )

    assert exit_code == 2
    assert "developer_signed_beta" in capsys.readouterr().out
