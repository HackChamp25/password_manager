#!/bin/bash
# Run Flutter desktop (no Python). Usage: ./run.sh   or   ./run.sh macos
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/flutter"
TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  if [ "$(uname -s)" = "Darwin" ]; then
    TARGET="macos"
  else
    TARGET="linux"
  fi
fi
flutter run -d "$TARGET"
