from __future__ import annotations

import argparse
import json
import shutil
import sys
import tempfile
import time
from collections.abc import Callable
from pathlib import Path

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
) -> dict[str, float | int]:
    timings: list[float] = []
    total = samples + warmup
    for index in range(total):
        started = time.perf_counter()
        run_once(index)
        elapsed = time.perf_counter() - started
        if index >= warmup:
            timings.append(elapsed)
    print(f"[bench] {name}: {json.dumps(_stats(timings), ensure_ascii=False)}", flush=True)
    return _stats(timings)


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

        measurements = {
            "plot.preview": _bench_operation(
                name="plot.preview",
                samples=samples,
                warmup=warmup,
                run_once=plot_preview,
            ),
            "plot.export": _bench_operation(
                name="plot.export",
                samples=samples,
                warmup=warmup,
                run_once=plot_export,
            ),
            "data_studio.context": _bench_operation(
                name="data_studio.context",
                samples=samples,
                warmup=warmup,
                run_once=data_studio_context,
            ),
            "data_studio.preview": _bench_operation(
                name="data_studio.preview",
                samples=samples,
                warmup=warmup,
                run_once=data_studio_preview,
            ),
            "code_console.run": _bench_operation(
                name="code_console.run",
                samples=samples,
                warmup=warmup,
                run_once=code_console_run,
            ),
        }

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


def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark sidecar hot paths for first-principles optimization.")
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--warmup", type=int, default=3)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("docs/performance/benchmark-2026-04-08.json"),
    )
    args = parser.parse_args()

    report = run_benchmark(samples=args.samples, warmup=args.warmup)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[bench] report written: {args.output}", flush=True)


if __name__ == "__main__":
    main()
