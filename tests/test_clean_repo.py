import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "clean_repo.py"


def run_clean(tmp_path: Path, *args: str) -> subprocess.CompletedProcess[str]:
    command = [sys.executable, str(SCRIPT_PATH), "--root", str(tmp_path), *args]
    return subprocess.run(command, capture_output=True, text=True, check=False)


def test_clean_repo_dry_run_preserves_files(tmp_path: Path) -> None:
    (tmp_path / ".mypy_cache").mkdir()
    (tmp_path / ".venv-py314-backup-20260319").mkdir()
    (tmp_path / "src" / "__pycache__").mkdir(parents=True)
    (tmp_path / "src" / "__pycache__" / "module.pyc").write_bytes(b"x")

    result = run_clean(tmp_path, "--dry-run")

    assert result.returncode == 0
    assert (tmp_path / ".mypy_cache").exists()
    assert (tmp_path / ".venv-py314-backup-20260319").exists()
    assert (tmp_path / "src" / "__pycache__").exists()


def test_clean_repo_removes_safe_targets_but_keeps_active_venv(tmp_path: Path) -> None:
    (tmp_path / ".mypy_cache").mkdir()
    (tmp_path / ".venv").mkdir()
    (tmp_path / ".venv-py314-backup-20260319").mkdir()
    (tmp_path / ".tmp_clash_verge_autobuild").mkdir()
    (tmp_path / "src" / "__pycache__").mkdir(parents=True)
    (tmp_path / "src" / "__pycache__" / "module.pyc").write_bytes(b"x")
    (tmp_path / "src" / ".DS_Store").write_text("junk", encoding="utf-8")

    result = run_clean(tmp_path)

    assert result.returncode == 0
    assert not (tmp_path / ".mypy_cache").exists()
    assert not (tmp_path / ".venv-py314-backup-20260319").exists()
    assert not (tmp_path / ".tmp_clash_verge_autobuild").exists()
    assert not (tmp_path / "src" / "__pycache__").exists()
    assert not (tmp_path / "src" / ".DS_Store").exists()
    assert (tmp_path / ".venv").exists()


def test_clean_repo_keeps_unlisted_node_modules(tmp_path: Path) -> None:
    node_modules = tmp_path / "app" / "macos" / "node_modules"
    node_modules.mkdir(parents=True)
    (node_modules / "package.json").write_text("{}", encoding="utf-8")

    result = run_clean(tmp_path)
    assert result.returncode == 0
    assert node_modules.exists()
