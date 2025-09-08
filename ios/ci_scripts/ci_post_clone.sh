#!/bin/sh

# ci_post_clone.sh
# Xcode Cloud script to set up Flutter environment

set -e

echo "🔥 Starting ci_post_clone.sh..."

# Navigate to project root first (we're currently in ios/ci_scripts/)
echo "🔍 DEBUG: Navigating to project root..."
cd ../..
echo "🔍 DEBUG: Now in project root: $(pwd)"
ls -la

# Install Flutter (without sudo for Xcode Cloud) - optimized for speed
echo "📱 Installing Flutter..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1 ~/flutter
export PATH="$PATH:$HOME/flutter/bin"

# Quick Flutter setup - skip full doctor
echo "📱 Setting up Flutter..."
flutter --version
flutter precache --ios

# Install Dart dependencies
echo "📦 Installing Dart dependencies..."
flutter pub get || { echo "❌ flutter pub get failed"; exit 1; }

# Install iOS dependencies
echo "🍎 Installing iOS dependencies..."
cd ios
pod install --repo-update || { echo "❌ pod install failed"; exit 1; }
cd ..

echo "✅ ci_post_clone.sh completed successfully!"