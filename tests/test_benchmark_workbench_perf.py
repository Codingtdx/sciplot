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
