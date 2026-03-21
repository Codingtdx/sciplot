#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h}"
VENV_ACTIVATE="$PROJECT_DIR/.venv/bin/activate"
DESKTOP_DIR="$PROJECT_DIR/app/desktop"

cd "$PROJECT_DIR"

if [[ ! -f "$VENV_ACTIVATE" ]]; then
  echo "Error: virtual environment not found at $VENV_ACTIVATE"
  echo "Press Enter to close..."
  read
  exit 1
fi

if [[ ! -d "$DESKTOP_DIR" ]]; then
  echo "Error: desktop app directory not found at $DESKTOP_DIR"
  echo "Press Enter to close..."
  read
  exit 1
fi

source "$VENV_ACTIVATE"
if [[ ! -d "$DESKTOP_DIR/node_modules" ]]; then
  echo "Installing desktop app dependencies..."
  if [[ -f "$DESKTOP_DIR/package-lock.json" ]]; then
    (cd "$DESKTOP_DIR" && npm ci)
  else
    (cd "$DESKTOP_DIR" && npm install)
  fi
fi

if (cd "$DESKTOP_DIR" && npm run tauri dev); then
  exit 0
fi

echo
echo "Desktop Tauri launch failed."
echo "This repository no longer ships the legacy PySide / terminal launcher."
echo "Please fix the Tauri runtime or desktop dependencies and rerun Launch_Plotter.command."
echo "Press Enter to close..."
read
exit 1
