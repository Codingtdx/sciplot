#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h}"
VENV_ACTIVATE="$PROJECT_DIR/.venv/bin/activate"
GUI_SCRIPT_PATH="$PROJECT_DIR/plot_wizard_gui.py"
FALLBACK_SCRIPT_PATH="$PROJECT_DIR/interactive_plot.py"

cd "$PROJECT_DIR"

if [[ ! -f "$VENV_ACTIVATE" ]]; then
  echo "Error: virtual environment not found at $VENV_ACTIVATE"
  echo "Press Enter to close..."
  read
  exit 1
fi

if [[ ! -f "$GUI_SCRIPT_PATH" ]]; then
  echo "Error: GUI plot script not found at $GUI_SCRIPT_PATH"
  echo "Press Enter to close..."
  read
  exit 1
fi

source "$VENV_ACTIVATE"

if ! python "$GUI_SCRIPT_PATH"; then
  echo
  echo "Legacy GUI launch failed. Falling back to terminal wizard..."
  if [[ -f "$FALLBACK_SCRIPT_PATH" ]]; then
    python "$FALLBACK_SCRIPT_PATH"
  else
    echo "Fallback script not found at $FALLBACK_SCRIPT_PATH"
    echo "Press Enter to close..."
    read
    exit 1
  fi
fi

echo
echo "Press Enter to close..."
read
