from __future__ import annotations

import argparse
import json
import plistlib
import re
from collections.abc import Sequence
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROJECT = ROOT / "app" / "macos" / "SciPlot.xcodeproj" / "project.pbxproj"
DEFAULT_INFO_PLIST = ROOT / "app" / "macos" / "Info.plist"
DEFAULT_EXPORT_OPTIONS = ROOT / "app" / "macos" / "ExportOptions.plist"
APP_BUNDLE_ID = "io.github.codingtdx.sciplot.desktop"


def _parse_build_settings(settings_text: str) -> dict[str, str]:
    settings: dict[str, str] = {}
    for line in settings_text.splitlines():
        match = re.match(r"\s*([A-Z0-9_]+)\s*=\s*(.+?);$", line)
        if not match:
            continue
        key, value = match.groups()
        settings[key] = value.strip().strip('"')
    return settings


def _app_build_configurations(project_path: Path) -> list[dict[str, str]]:
    text = project_path.read_text(encoding="utf-8")
    configurations: list[dict[str, str]] = []
    pattern = re.compile(
        r"/\*\s*(Debug|Release)\s*\*/\s*=\s*\{\s*"
        r"isa\s*=\s*XCBuildConfiguration;\s*"
        r"buildSettings\s*=\s*\{(?P<settings>.*?)\};\s*"
        r"name\s*=\s*(Debug|Release);\s*\};",
        re.DOTALL,
    )
    for match in pattern.finditer(text):
        settings = _parse_build_settings(match.group("settings"))
        if settings.get("PRODUCT_BUNDLE_IDENTIFIER") == APP_BUNDLE_ID:
            settings["CONFIGURATION"] = match.group(1)
            configurations.append(settings)
    return configurations


def _all_configs_equal(configs: list[dict[str, str]], key: str, expected: str) -> bool:
    return bool(configs) and all(config.get(key) == expected for config in configs)


def _any_config_has(configs: list[dict[str, str]], key: str) -> bool:
    return any(bool(config.get(key)) for config in configs)


def _mode(status: str, *, mode_id: str, label: str, blockers: list[str], notes: list[str]) -> dict[str, object]:
    return {
        "id": mode_id,
        "label": label,
        "status": status,
        "blockers": blockers,
        "notes": notes,
    }


def build_readiness_report(
    *,
    project_path: Path = DEFAULT_PROJECT,
    info_plist_path: Path = DEFAULT_INFO_PLIST,
    export_options_path: Path = DEFAULT_EXPORT_OPTIONS,
) -> dict[str, Any]:
    configurations = _app_build_configurations(project_path)
    info = plistlib.loads(info_plist_path.read_bytes())
    bundle_identifier = next(
        (
            config.get("PRODUCT_BUNDLE_IDENTIFIER")
            for config in configurations
            if config.get("PRODUCT_BUNDLE_IDENTIFIER")
        ),
        str(info.get("CFBundleIdentifier", "")),
    )
    checks = {
        "app_configurations": [config.get("CONFIGURATION") for config in configurations],
        "code_signing_allowed": _all_configs_equal(configurations, "CODE_SIGNING_ALLOWED", "YES"),
        "hardened_runtime": _all_configs_equal(configurations, "ENABLE_HARDENED_RUNTIME", "YES"),
        "development_team_present": _any_config_has(configurations, "DEVELOPMENT_TEAM"),
        "entitlements_present": _any_config_has(configurations, "CODE_SIGN_ENTITLEMENTS"),
        "export_options_present": export_options_path.exists(),
    }

    local_blockers = [] if configurations else ["App target build settings were not found."]
    signed_blockers: list[str] = []
    if not checks["code_signing_allowed"]:
        signed_blockers.append("Code signing is disabled for the app target.")
    if not checks["hardened_runtime"]:
        signed_blockers.append("Hardened runtime is disabled for the app target.")
    if not checks["development_team_present"]:
        signed_blockers.append("No DEVELOPMENT_TEAM is configured for the app target.")

    notarized_blockers = list(signed_blockers)
    if not checks["export_options_present"]:
        notarized_blockers.append("No ExportOptions.plist was found for archive export.")

    return {
        "project_path": str(project_path),
        "info_plist_path": str(info_plist_path),
        "bundle_identifier": bundle_identifier,
        "checks": checks,
        "modes": [
            _mode(
                "blocked" if local_blockers else "passed",
                mode_id="local_unsigned",
                label="Local unsigned debug app",
                blockers=local_blockers,
                notes=["Supported for developer-machine smoke runs only."],
            ),
            _mode(
                "blocked" if signed_blockers else "passed",
                mode_id="developer_signed_beta",
                label="Developer-signed beta app",
                blockers=signed_blockers,
                notes=["Required before sharing the app outside the local checkout."],
            ),
            _mode(
                "blocked" if notarized_blockers else "passed",
                mode_id="notarized_beta",
                label="Notarized beta distribution",
                blockers=notarized_blockers,
                notes=["Requires a signed archive, export options, and notarytool validation."],
            ),
        ],
    }


def _parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check macOS beta distribution readiness.")
    parser.add_argument("--project", type=Path, default=DEFAULT_PROJECT)
    parser.add_argument("--info-plist", type=Path, default=DEFAULT_INFO_PLIST)
    parser.add_argument("--export-options", type=Path, default=DEFAULT_EXPORT_OPTIONS)
    parser.add_argument(
        "--require-mode",
        choices=("local_unsigned", "developer_signed_beta", "notarized_beta"),
        help="Return non-zero when this distribution mode is blocked.",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv)
    report = build_readiness_report(
        project_path=args.project,
        info_plist_path=args.info_plist,
        export_options_path=args.export_options,
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if args.require_mode:
        mode = next(item for item in report["modes"] if item["id"] == args.require_mode)
        if mode["status"] != "passed":
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
