from __future__ import annotations

from scripts import benchmark_workbench_perf


def test_bench_operation_variants_report_cold_and_hot_metrics() -> None:
    calls: list[object] = []

    def clear_caches() -> None:
        calls.append("clear")

    def run_once(index: int) -> None:
        calls.append(index)

    measurements = benchmark_workbench_perf._bench_hot_and_cold(
        name="plot.preview",
        samples=2,
        warmup=1,
        run_once=run_once,
        clear_caches=clear_caches,
    )

    assert set(measurements) == {"plot.preview.cold", "plot.preview.hot"}
    assert measurements["plot.preview.cold"]["samples"] == 2
    assert measurements["plot.preview.hot"]["samples"] == 2
    assert calls.count("clear") == 3


def test_evaluate_budgets_reports_metric_regressions() -> None:
    measurements = {
        "plot.preview.cold": {"samples": 5, "p95": 0.82, "p50": 0.35},
        "plot.preview.hot": {"samples": 5, "p95": 0.002, "p50": 0.001},
    }
    budgets = {
        "plot.preview.cold": {"p95": 0.75},
        "plot.preview.hot": {"p95": 0.01},
    }

    results = benchmark_workbench_perf.evaluate_budgets(measurements, budgets)

    assert [item["status"] for item in results] == ["failed", "passed"]
    assert results[0]["operation"] == "plot.preview.cold"
    assert results[0]["metric"] == "p95"


def test_compare_measurements_flags_relative_regression() -> None:
    current = {"plot.export.hot": {"p50": 0.42}}
    baseline = {"plot.export.hot": {"p50": 0.30}}

    comparisons = benchmark_workbench_perf.compare_measurements(
        current,
        baseline,
        max_regression_fraction=0.20,
    )

    assert comparisons == [
        {
            "operation": "plot.export.hot",
            "metric": "p50",
            "baseline": 0.3,
            "current": 0.42,
            "delta": 0.12,
            "relative_delta": 0.4,
            "status": "regressed",
        }
    ]
