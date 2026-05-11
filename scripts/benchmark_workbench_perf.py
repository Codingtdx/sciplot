from __future__ import annotations

import argparse
import json
import shutil
import sys
import tempfile
import time
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import pandas as pd
from fastapi.testclient import TestClient

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


def _curve_fixture(path: Path) -> None:
    pd.DataFrame(
        [
            ["Time", "Stress", "Time", "Stress"],
            ["s", "MPa", "s", "MPa"],
            ["Sample A", "Sample A", "Sample B", "Sample B"],
            [0, 1.0, 0, 2.0],
            [1, 1.2, 1, 2.3],
            [2, 1.5, 2, 2.7],
        ]
    ).to_csv(path, header=False, index=False)


def _percentile(values: list[float], q: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 0.0
    index = int(round((len(ordered) - 1) * q))
    return ordered[index]


def _stats(values: list[float]) -> dict[str, float | int]:
    if not values:
        return {"samples": 0, "p50": 0.0, "p95": 0.0, "min": 0.0, "max": 0.0, "mean": 0.0}
    return {
        "samples": len(values),
        "p50": round(_percentile(values, 0.50), 4),
        "p95": round(_percentile(values, 0.95), 4),
        "min": round(min(values), 4),
        "max": round(max(values), 4),
        "mean": round(sum(values) / len(values), 4),
    }


def _bench_operation(
    *,
    name: str,
    samples: int,
    warmup: int,
    run_once: Callable[[int], None],
    before_each: Callable[[], None] | None = None,
) -> dict[str, float | int]:
    timings: list[float] = []
    total = samples + warmup
    for index in range(total):
        if before_each is not None:
            before_each()
        started = time.perf_counter()
        run_once(index)
        elapsed = time.perf_counter() - started
        if index >= warmup:
            timings.append(elapsed)
    print(f"[bench] {name}: {json.dumps(_stats(timings), ensure_ascii=False)}", flush=True)
    return _stats(timings)


def _bench_hot_and_cold(
    *,
    name: str,
    samples: int,
    warmup: int,
    run_once: Callable[[int], None],
    clear_caches: Callable[[], None],
) -> dict[str, dict[str, float | int]]:
    cold_name = f"{name}.cold"
    hot_name = f"{name}.hot"
    return {
        cold_name: _bench_operation(
            name=cold_name,
            samples=samples,
            warmup=warmup,
            run_once=run_once,
            before_each=clear_caches,
        ),
        hot_name: _bench_operation(
            name=hot_name,
            samples=samples,
            warmup=warmup,
            run_once=run_once,
        ),
    }


def _numeric_metric(value: object) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value)


def evaluate_budgets(
    measurements: dict[str, dict[str, float | int]],
    budgets: dict[str, dict[str, float | int]],
) -> list[dict[str, object]]:
    results: list[dict[str, object]] = []
    for operation, operation_budgets in budgets.items():
        current_metrics = measurements.get(operation, {})
        for metric, limit_value in operation_budgets.items():
            current = _numeric_metric(current_metrics.get(metric))
            limit = _numeric_metric(limit_value)
            if current is None or limit is None:
                status = "missing"
            elif current <= limit:
                status = "passed"
            else:
                status = "failed"
            results.append(
                {
                    "operation": operation,
                    "metric": metric,
                    "current": current,
                    "budget": limit,
                    "status": status,
                }
            )
    return results


def compare_measurements(
    current: dict[str, dict[str, float | int]],
    baseline: dict[str, dict[str, float | int]],
    *,
    max_regression_fraction: float,
) -> list[dict[str, object]]:
    comparisons: list[dict[str, object]] = []
    for operation, current_metrics in current.items():
        baseline_metrics = baseline.get(operation, {})
        for metric, current_value in current_metrics.items():
            current_number = _numeric_metric(current_value)
            baseline_number = _numeric_metric(baseline_metrics.get(metric))
            if current_number is None or baseline_number is None or baseline_number <= 0:
                continue
            delta = round(current_number - baseline_number, 6)
            relative_delta = round(delta / baseline_number, 6)
            if relative_delta <= max_regression_fraction:
                continue
            comparisons.append(
                {
                    "operation": operation,
                    "metric": metric,
                    "baseline": round(baseline_number, 6),
                    "current": round(current_number, 6),
                    "delta": delta,
                    "relative_delta": relative_delta,
                    "status": "regressed",
                }
            )
    return comparisons


def _load_measurements_report(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if "measurements" in payload and isinstance(payload["measurements"], dict):
        return payload
    raise ValueError(f"Benchmark report is missing measurements: {path}")


def clear_sidecar_hot_path_caches() -> None:
    from app.sidecar import routes_render
    from src.data_studio import comparison, workbooks
    from src.rendering import cache as rendering_cache
    from src.rendering import dataset_models, recommendation

    rendering_cache.clear_input_cache()
    dataset_models.clear_normalized_dataset_cache()
    recommendation.clear_inspection_cache()
    routes_render._RENDER_PREVIEW_CACHE.clear()  # noqa: SLF001
    comparison._COMPARISON_PREVIEW_PDF_CACHE.clear()  # noqa: SLF001
    workbooks._import_workbook_cached.cache_clear()  # noqa: SLF001
    workbooks._load_workbook_specimen_bundle_cached.cache_clear()  # noqa: SLF001


def run_benchmark(*, samples: int, warmup: int) -> dict[str, object]:
    from app.sidecar.server import app

    fixture_dir = REPO_ROOT / "tests" / "fixtures" / "tensile_raw"
    with tempfile.TemporaryDirectory(prefix="codegod_bench_") as temp_dir:
        tmp_root = Path(temp_dir)
        curve_csv = tmp_root / "curve.csv"
        _curve_fixture(curve_csv)

        client = TestClient(app)

        left_workbook = tmp_root / "left.xlsx"
        right_workbook = tmp_root / "right.xlsx"
        for output, label in ((left_workbook, "Left"), (right_workbook, "Right")):
            response = client.post(
                "/data-studio/build-workbook",
                json={
                    "file_paths": [
                        str(fixture_dir / "BlendSet_A.csv"),
                        str(fixture_dir / "BlendSet_B.csv"),
                        str(fixture_dir / "BlendSet_bad.csv"),
                    ],
                    "output_path": str(output),
                    "template_id": "builtin/tensile",
                    "group_name": label,
                },
            )
            if response.status_code != 200:
                raise RuntimeError(f"Failed to build benchmark workbook {label}: {response.text}")

        code_context = client.post(
            "/code-console/context",
            json={
                "input_path": str(curve_csv),
                "sheet": 0,
                "template": "curve",
            },
        )
        if code_context.status_code != 200:
            raise RuntimeError(f"Failed to initialize code console context: {code_context.text}")
        context_id = code_context.json()["context_id"]

        def plot_preview(_index: int) -> None:
            response = client.post(
                "/render-preview",
                json={"input_path": str(curve_csv), "sheet": 0, "template": "curve"},
            )
            if response.status_code != 200:
                raise RuntimeError(response.text)

        def plot_export(index: int) -> None:
            output_dir = tmp_root / "plot_exports" / f"run_{index}"
            if output_dir.exists():
                shutil.rmtree(output_dir)
            response = client.post(
                "/export-render",
                json={
                    "input_path": str(curve_csv),
                    "sheet": 0,
                    "template": "curve",
                    "output_dir": str(output_dir),
                },
            )
            if response.status_code != 200:
                raise RuntimeError(response.text)

        def data_studio_context(_index: int) -> None:
            response = client.post(
                "/data-studio/comparison-context",
                json={"workbook_paths": [str(left_workbook), str(right_workbook)]},
            )
            if response.status_code != 200:
                raise RuntimeError(response.text)

        def data_studio_preview(_index: int) -> None:
            response = client.post(
                "/data-studio/comparison-preview",
                json={
                    "workbook_paths": [str(left_workbook), str(right_workbook)],
                    "recipe_id": "representative_curve",
                },
            )
            if response.status_code != 200:
                raise RuntimeError(response.text)

        def code_console_run(_index: int) -> None:
            response = client.post(
                "/code-console/run",
                json={
                    "context_id": context_id,
                    "code": 'print("bench_run")',
                    "timeout_seconds": 30,
                },
            )
            if response.status_code != 200:
                raise RuntimeError(response.text)

        measurements: dict[str, dict[str, float | int]] = {}
        measurements.update(
            _bench_hot_and_cold(
                name="plot.preview",
                samples=samples,
                warmup=warmup,
                run_once=plot_preview,
                clear_caches=clear_sidecar_hot_path_caches,
            )
        )
        measurements.update(
            _bench_hot_and_cold(
                name="plot.export",
                samples=samples,
                warmup=warmup,
                run_once=plot_export,
                clear_caches=clear_sidecar_hot_path_caches,
            )
        )
        measurements.update(
            _bench_hot_and_cold(
                name="data_studio.context",
                samples=samples,
                warmup=warmup,
                run_once=data_studio_context,
                clear_caches=clear_sidecar_hot_path_caches,
            )
        )
        measurements.update(
            _bench_hot_and_cold(
                name="data_studio.preview",
                samples=samples,
                warmup=warmup,
                run_once=data_studio_preview,
                clear_caches=clear_sidecar_hot_path_caches,
            )
        )
        measurements.update(
            _bench_hot_and_cold(
                name="code_console.run",
                samples=samples,
                warmup=warmup,
                run_once=code_console_run,
                clear_caches=clear_sidecar_hot_path_caches,
            )
        )

        return {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "samples": samples,
            "warmup": warmup,
            "fixtures": {
                "curve_csv": str(curve_csv),
                "workbooks": [str(left_workbook), str(right_workbook)],
            },
            "measurements": measurements,
        }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Benchmark sidecar hot paths for first-principles optimization.")
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--warmup", type=int, default=3)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(f"docs/performance/benchmark-{datetime.now(UTC).date().isoformat()}.json"),
    )
    parser.add_argument("--budget-file", type=Path, help="JSON file mapping operation metrics to budget ceilings.")
    parser.add_argument("--fail-on-budget", action="store_true", help="Exit non-zero when any budget is exceeded.")
    parser.add_argument("--compare-to", type=Path, help="Previous benchmark report to compare against.")
    parser.add_argument("--max-regression-fraction", type=float, default=0.25)
    parser.add_argument(
        "--fail-on-regression",
        action="store_true",
        help="Exit non-zero when comparison flags regressions.",
    )
    args = parser.parse_args(argv)

    report = run_benchmark(samples=args.samples, warmup=args.warmup)
    exit_code = 0
    if args.budget_file:
        budgets = json.loads(args.budget_file.read_text(encoding="utf-8"))
        budget_results = evaluate_budgets(report["measurements"], budgets)
        report["budget_results"] = budget_results
        failed_budgets = [item for item in budget_results if item["status"] in {"failed", "missing"}]
        if failed_budgets:
            print(f"[bench] budget issues: {json.dumps(failed_budgets, ensure_ascii=False)}", flush=True)
            if args.fail_on_budget:
                exit_code = 2
    if args.compare_to:
        baseline_report = _load_measurements_report(args.compare_to)
        comparison_results = compare_measurements(
            report["measurements"],
            baseline_report["measurements"],
            max_regression_fraction=args.max_regression_fraction,
        )
        report["comparison_results"] = comparison_results
        if comparison_results:
            print(f"[bench] regressions: {json.dumps(comparison_results, ensure_ascii=False)}", flush=True)
            if args.fail_on_regression:
                exit_code = 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[bench] report written: {args.output}", flush=True)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
