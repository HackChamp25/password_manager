#!/bin/bash
# Linux/macOS launcher: FastAPI + Flutter
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="${SCRIPT_DIR}/backend"
cd "${SCRIPT_DIR}"
echo "Starting FastAPI backend..."
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000 &
BACKEND_PID=$!
echo "Backend PID $BACKEND_PID"
sleep 3
echo "Starting Flutter..."
cd flutter
PLATFORM=${1:-}
if [ -z "$PLATFORM" ]; then
  if [ "$(uname -s)" = "Darwin" ]; then
    PLATFORM="macos"
  else
    PLATFORM="linux"
  fi
fi
flutter run -d "$PLATFORM"
kill $BACKEND_PID 2>/dev/null || true
