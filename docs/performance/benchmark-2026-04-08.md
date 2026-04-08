# 2026-04-08 First-Principles Optimization Benchmark

## Command

`.venv/bin/python scripts/benchmark_workbench_perf.py --samples 20 --warmup 3 --output docs/performance/benchmark-2026-04-08.json`

## Baseline (provided)

- `plot.preview p95≈0.27s`
- `plot.export p95≈0.34s`
- `data_studio.context p95≈0.41s`
- `data_studio.preview p95≈0.71s`
- `code_console.run p95≈0.93s`

## This Round (p95)

- `plot.preview p95=0.0008s`
- `plot.export p95=0.2776s`
- `data_studio.context p95=0.0013s`
- `data_studio.preview p95=0.2924s`
- `code_console.run p95=0.0031s`

## Notes

- Benchmark harness uses FastAPI `TestClient` in-process and is intended for same-harness trend comparison.
- Full raw output is stored in [`benchmark-2026-04-08.json`](./benchmark-2026-04-08.json).
