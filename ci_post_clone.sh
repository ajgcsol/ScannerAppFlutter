#!/bin/sh

echo "🔥 FOUND ci_post_clone.sh in ROOT DIRECTORY"
echo "Current directory: $(pwd)"
echo "Repository contents:"
ls -la

echo "Looking for ci_scripts directory:"
ls -la ci_scripts/ || echo "ci_scripts directory not found"

echo "Checking if we can find Flutter..."
which flutter || echo "Flutter not in PATH"

# Try to install Flutter without sudo
echo "Installing Flutter to home directory..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1 ~/flutter || echo "Flutter clone failed"
export PATH="$PATH:$HOME/flutter/bin"

echo "Setting up Flutter..."
flutter doctor -v || echo "Flutter doctor failed"
flutter pub get || echo "Flutter pub get failed"

echo "Installing iOS pods..."
cd ios && pod install && cd .. || echo "Pod install failed"

echo "✅ ci_post_clone.sh completed"