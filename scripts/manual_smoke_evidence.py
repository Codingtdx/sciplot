from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Sequence

SCHEMA_VERSION = 1
REQUIRED_CHECK_IDS: tuple[str, ...] = (
    "plot_import_preview_export",
    "data_studio_import_open_plot",
    "overlay_drag_save_reopen",
)
VALID_STATUSES = {"passed", "blocked", "failed"}


def _timestamp() -> str:
    return datetime.now(UTC).isoformat()


def _json_dump(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2)


def _initial_payload() -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "generated_at": _timestamp(),
        "checks": [],
    }


def _load_payload(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _save_payload(path: Path, payload: dict[str, Any]) -> None:
    payload["generated_at"] = _timestamp()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(_json_dump(payload), encoding="utf-8")


def _check_map(payload: dict[str, Any]) -> dict[str, dict[str, Any]]:
    checks = payload.setdefault("checks", [])
    return {str(item.get("id")): item for item in checks if isinstance(item, dict)}


def validate_payload(
    payload: dict[str, Any],
    *,
    require_all: bool,
) -> list[str]:
    issues: list[str] = []
    if payload.get("schema_version") != SCHEMA_VERSION:
        issues.append(f"schema_version must be {SCHEMA_VERSION}.")
    if not isinstance(payload.get("generated_at"), str) or not payload["generated_at"]:
        issues.append("generated_at must be a non-empty string.")

    checks = payload.get("checks")
    if not isinstance(checks, list):
        issues.append("checks must be a list.")
        return issues

    seen_ids: set[str] = set()
    passed_ids: set[str] = set()
    for index, item in enumerate(checks):
        if not isinstance(item, dict):
            issues.append(f"checks[{index}] must be an object.")
            continue
        check_id = item.get("id")
        if not isinstance(check_id, str) or not check_id:
            issues.append(f"checks[{index}].id must be a non-empty string.")
            continue
        if check_id not in REQUIRED_CHECK_IDS:
            issues.append(f"checks[{index}].id {check_id!r} is not a supported manual smoke check.")
        if check_id in seen_ids:
            issues.append(f"checks[{index}].id {check_id!r} is duplicated.")
        seen_ids.add(check_id)

        status = item.get("status")
        if status not in VALID_STATUSES:
            issues.append(f"checks[{index}].status for {check_id!r} must be one of {sorted(VALID_STATUSES)}.")
            continue

        notes = item.get("notes")
        if not isinstance(notes, list) or any(not isinstance(note, str) for note in notes):
            issues.append(f"checks[{index}].notes for {check_id!r} must be a list of strings.")

        evidence_files = item.get("evidence_files")
        if not isinstance(evidence_files, list) or any(not isinstance(entry, str) for entry in evidence_files):
            issues.append(f"checks[{index}].evidence_files for {check_id!r} must be a list of strings.")
            evidence_files = []

        recorded_at = item.get("recorded_at")
        if not isinstance(recorded_at, str) or not recorded_at:
            issues.append(f"checks[{index}].recorded_at for {check_id!r} must be a non-empty string.")

        missing_files = [entry for entry in evidence_files if not Path(entry).exists()]
        if missing_files:
            issues.append(f"{check_id!r} references missing evidence files: {', '.join(missing_files)}.")

        if status == "passed":
            if not evidence_files:
                issues.append(f"{check_id!r} is passed but has no evidence_files.")
            elif not missing_files:
                passed_ids.add(check_id)

    if require_all:
        for check_id in REQUIRED_CHECK_IDS:
            if check_id not in passed_ids:
                issues.append(f"required manual smoke check {check_id!r} is not recorded as passed with evidence.")
    return issues


def completed_checks_from_evidence(path: Path) -> tuple[set[str], list[str]]:
    if not path.exists():
        return set(), [f"manual evidence file does not exist: {path}"]
    payload = _load_payload(path)
    issues = validate_payload(payload, require_all=False)
    completed: set[str] = set()
    for item in payload.get("checks", []):
        if not isinstance(item, dict):
            continue
        check_id = item.get("id")
        evidence_files = item.get("evidence_files", [])
        if (
            check_id in REQUIRED_CHECK_IDS
            and item.get("status") == "passed"
            and isinstance(evidence_files, list)
            and evidence_files
            and all(Path(entry).exists() for entry in evidence_files if isinstance(entry, str))
        ):
            completed.add(str(check_id))
    return completed, issues


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create and validate manual smoke evidence bundles.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    init_parser = subparsers.add_parser("init", help="Create an empty manual smoke evidence bundle.")
    init_parser.add_argument("--output", required=True, help="Path to the evidence JSON file to create.")

    record_parser = subparsers.add_parser("record", help="Record one manual smoke result into an evidence bundle.")
    record_parser.add_argument("--input", required=True, help="Existing evidence JSON path.")
    record_parser.add_argument("--check", required=True, choices=REQUIRED_CHECK_IDS, help="Manual smoke check id.")
    record_parser.add_argument("--status", required=True, choices=sorted(VALID_STATUSES), help="Manual smoke status.")
    record_parser.add_argument("--note", default="", help="Short note to append to this check entry.")
    record_parser.add_argument(
        "--evidence-file",
        action="append",
        default=[],
        help="Evidence file path. Repeat to attach multiple files.",
    )

    validate_parser = subparsers.add_parser("validate", help="Validate an evidence bundle.")
    validate_parser.add_argument("--input", required=True, help="Evidence JSON path.")
    validate_parser.add_argument(
        "--require-all",
        action="store_true",
        help="Require all supported manual smoke checks to be passed with existing evidence files.",
    )
    return parser.parse_args(argv)


def _run_init(output: Path) -> int:
    _save_payload(output, _initial_payload())
    print(f"[manual-smoke] initialized evidence bundle: {output}")
    return 0


def _run_record(
    input_path: Path,
    *,
    check_id: str,
    status: str,
    note: str,
    evidence_files: list[str],
) -> int:
    payload = _load_payload(input_path) if input_path.exists() else _initial_payload()
    check_map = _check_map(payload)
    entry = check_map.get(check_id)
    if entry is None:
        entry = {
            "id": check_id,
            "status": status,
            "notes": [],
            "evidence_files": [],
            "recorded_at": _timestamp(),
        }
        payload["checks"].append(entry)

    entry["status"] = status
    if note:
        notes = entry.setdefault("notes", [])
        if isinstance(notes, list):
            notes.append(note)
        else:
            entry["notes"] = [note]
    existing_files = [
        item for item in entry.get("evidence_files", []) if isinstance(item, str)
    ]
    for evidence_file in evidence_files:
        if evidence_file not in existing_files:
            existing_files.append(evidence_file)
    entry["evidence_files"] = existing_files
    entry["recorded_at"] = _timestamp()
    _save_payload(input_path, payload)
    print(f"[manual-smoke] recorded {check_id} as {status}: {input_path}")
    return 0


def _run_validate(input_path: Path, *, require_all: bool) -> int:
    if not input_path.exists():
        print(f"[manual-smoke] evidence file does not exist: {input_path}")
        return 2
    payload = _load_payload(input_path)
    issues = validate_payload(payload, require_all=require_all)
    if issues:
        print("[manual-smoke] validation failed:")
        for issue in issues:
            print(f"  - {issue}")
        return 2
    print(f"[manual-smoke] validation passed: {input_path}")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    if args.command == "init":
        return _run_init(Path(args.output))
    if args.command == "record":
        return _run_record(
            Path(args.input),
            check_id=args.check,
            status=args.status,
            note=args.note,
            evidence_files=list(args.evidence_file),
        )
    if args.command == "validate":
        return _run_validate(Path(args.input), require_all=args.require_all)
    raise AssertionError(f"Unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
