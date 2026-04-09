from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from src.plot_contract import write_contract_markdown


def main() -> int:
    destination = write_contract_markdown()
    print(destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
