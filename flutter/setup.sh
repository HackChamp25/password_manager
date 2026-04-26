#!/bin/bash
# Flutter Password Manager - Quick Setup Script

echo "🔐 Secure Password Manager - Flutter Setup"
echo "==========================================="
echo ""

# Check Flutter installation
echo "✓ Checking Flutter installation..."
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found. Please install Flutter first:"
    echo "   https://flutter.dev/docs/get-started/install"
    exit 1
fi

echo "✓ Flutter version:"
flutter --version
echo ""

# Check Dart installation
echo "✓ Checking Dart installation..."
if ! command -v dart &> /dev/null; then
    echo "❌ Dart not found. Install Flutter to get Dart."
    exit 1
fi

echo ""
echo "✓ Running flutter doctor..."
flutter doctor

echo ""
echo "✓ Getting dependencies..."
flutter pub get

echo ""
echo "✓ Running code analysis..."
flutter analyze

echo ""
echo "==========================================="
echo "✅ Setup complete!"
echo ""
echo "To run the app:"
echo ""
echo "  Desktop (Windows):"
echo "    flutter run -d windows"
echo ""
echo "  Desktop (macOS):"
echo "    flutter run -d macos"
echo ""
echo "  Desktop (Linux):"
echo "    flutter run -d linux"
echo ""
echo "  Android:"
echo "    flutter run -d android"
echo ""
echo "  iOS (macOS only):"
echo "    flutter run -d ios"
echo ""
echo "==========================================="
