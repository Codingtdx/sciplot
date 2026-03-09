#!/bin/zsh

set -euo pipefail

PROJECT_DIR="/Users/dongxutian/Documents/codegod"
VENV_ACTIVATE="$PROJECT_DIR/.venv/bin/activate"
SCRIPT_PATH="$PROJECT_DIR/interactive_plot.py"

cd "$PROJECT_DIR"

if [[ ! -f "$VENV_ACTIVATE" ]]; then
  echo "Error: virtual environment not found at $VENV_ACTIVATE"
  echo "Press Enter to close..."
  read
  exit 1
fi

if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "Error: interactive plot script not found at $SCRIPT_PATH"
  echo "Press Enter to close..."
  read
  exit 1
fi

source "$VENV_ACTIVATE"
python "$SCRIPT_PATH"

echo
echo "Press Enter to close..."
read
