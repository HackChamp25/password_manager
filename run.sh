#!/bin/bash
# Linux/macOS launcher script for Password Manager (Backend + Frontend)
# Usage: chmod +x run.sh && ./run.sh

# Check if uvicorn is available
if ! command -v uvicorn &> /dev/null; then
    echo "Error: uvicorn not found. Please install with: pip install uvicorn[standard]"
    exit 1
fi

# Check if flutter is available
if ! command -v flutter &> /dev/null; then
    echo "Error: flutter not found. Please install from https://flutter.dev/docs/get-started/install"
    exit 1
fi

echo "Starting FastAPI backend..."
nohup uvicorn src.api.main:app --reload --host 127.0.0.1 --port 8000 > backend.log 2>&1 &
BACKEND_PID=$!
echo "Backend started with PID $BACKEND_PID"

sleep 3

echo "Starting Flutter frontend..."
cd flutter
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')
if [ "$PLATFORM" = "darwin" ]; then
    PLATFORM="macos"
fi
flutter run -d $PLATFORM

# When Flutter exits, kill backend
kill $BACKEND_PID

