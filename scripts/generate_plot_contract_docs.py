from __future__ import annotations

from src.plot_contract import write_contract_markdown


def main() -> int:
    destination = write_contract_markdown()
    print(destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
