#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h}"
MACOS_DIR="$PROJECT_DIR/app/macos"
PROJECT_FILE="$MACOS_DIR/SciPlot.xcodeproj"
SCHEME="SciPlotMac"
DERIVED_DATA="$MACOS_DIR/.derivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/SciPlot.app"
PYTHON_BIN="$PROJECT_DIR/.venv/bin/python"

cd "$PROJECT_DIR"

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "Error: repo virtual environment Python not found at $PYTHON_BIN"
  echo "The native macOS app expects the sidecar to launch from .venv/bin/python."
  echo "Press Enter to close..."
  read
  exit 1
fi

if [[ ! -d "$MACOS_DIR" || ! -d "$PROJECT_FILE" ]]; then
  echo "Error: native macOS project not found at $PROJECT_FILE"
  echo "Press Enter to close..."
  read
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild is unavailable."
  echo "Current developer directory: $(xcode-select -p 2>/dev/null || echo unavailable)"
  echo "Please install/select a full Xcode toolchain, then rerun Launch_SciPlot.command."
  echo "Press Enter to close..."
  read
  exit 1
fi

echo "Building native macOS frontend..."
if ! xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build; then
  echo
  echo "Native macOS build failed."
  echo "Please fix the Xcode/macOS toolchain or project configuration and rerun Launch_SciPlot.command."
  echo "Press Enter to close..."
  read
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: built app not found at $APP_PATH"
  echo "Press Enter to close..."
  read
  exit 1
fi

open "$APP_PATH"
