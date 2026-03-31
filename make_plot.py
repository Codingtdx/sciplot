# ruff: noqa: F401, F403, I001

from src.entry.cli.make_plot import *  # noqa: F401,F403
from src.entry.cli.make_plot import main


if __name__ == "__main__":
    raise SystemExit(main())
