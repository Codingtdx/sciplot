from __future__ import annotations

import contextlib
import io
import os
import traceback
from concurrent.futures import ProcessPoolExecutor
from concurrent.futures import TimeoutError as FutureTimeoutError
from dataclasses import dataclass
from pathlib import Path
from threading import Lock
from typing import Any


@dataclass(frozen=True)
class RunnerExecutionResult:
    status: str
    exit_code: int | None
    stdout: str
    stderr: str


def _execute_code_in_worker(
    *,
    script_path: str,
    repo_root: str,
    output_dir: str,
    context_json_path: str,
) -> dict[str, Any]:
    os.chdir(repo_root)
    os.environ["OUTPUT_DIR"] = output_dir
    os.environ["CODEGOD_CODE_CONSOLE_CONTEXT_JSON"] = context_json_path
    os.environ["PYTHONUNBUFFERED"] = "1"

    stdout_buffer = io.StringIO()
    stderr_buffer = io.StringIO()
    status = "succeeded"
    exit_code: int | None = 0
    try:
        source = Path(script_path).read_text(encoding="utf-8")
        globals_dict: dict[str, Any] = {
            "__name__": "__main__",
            "__file__": script_path,
        }
        with contextlib.redirect_stdout(stdout_buffer), contextlib.redirect_stderr(stderr_buffer):
            exec(compile(source, script_path, "exec"), globals_dict, globals_dict)
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else 0
        exit_code = int(code)
        status = "succeeded" if exit_code == 0 else "failed"
    except Exception:
        status = "failed"
        exit_code = 1
        stderr_buffer.write(traceback.format_exc())
    return {
        "status": status,
        "exit_code": exit_code,
        "stdout": stdout_buffer.getvalue(),
        "stderr": stderr_buffer.getvalue(),
    }


class PersistentCodeConsoleRunner:
    """Single-process, reusable code runner with timeout-driven self-healing."""

    def __init__(self) -> None:
        self._lock = Lock()
        self._executor: ProcessPoolExecutor | None = None

    def _ensure_executor(self) -> ProcessPoolExecutor:
        with self._lock:
            if self._executor is None:
                self._executor = ProcessPoolExecutor(max_workers=1)
            return self._executor

    def _restart_executor(self) -> None:
        with self._lock:
            executor = self._executor
            self._executor = None
        if executor is not None:
            executor.shutdown(wait=False, cancel_futures=True)

    def run(
        self,
        *,
        script_path: Path,
        repo_root: Path,
        output_dir: Path,
        context_json_path: Path,
        timeout_seconds: int,
    ) -> RunnerExecutionResult:
        try:
            executor = self._ensure_executor()
            future = executor.submit(
                _execute_code_in_worker,
                script_path=str(script_path),
                repo_root=str(repo_root),
                output_dir=str(output_dir),
                context_json_path=str(context_json_path),
            )
            payload = future.result(timeout=timeout_seconds)
        except FutureTimeoutError:
            self._restart_executor()
            return RunnerExecutionResult(
                status="timed_out",
                exit_code=None,
                stdout="",
                stderr=(
                    f"Code Console timed out after {timeout_seconds} seconds in the persistent runner."
                ),
            )
        except Exception as exc:
            self._restart_executor()
            raise RuntimeError(f"Persistent Code Console runner failed: {exc}") from exc

        return RunnerExecutionResult(
            status=str(payload.get("status", "failed")),
            exit_code=payload.get("exit_code"),
            stdout=str(payload.get("stdout", "")),
            stderr=str(payload.get("stderr", "")),
        )


DEFAULT_RUNNER_MANAGER = PersistentCodeConsoleRunner()


__all__ = [
    "DEFAULT_RUNNER_MANAGER",
    "PersistentCodeConsoleRunner",
    "RunnerExecutionResult",
]

