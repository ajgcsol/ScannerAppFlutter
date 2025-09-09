#!/bin/sh

# ci_post_clone.sh
# Xcode Cloud script to set up Flutter environment
# Version: 2.0 - Optimized for Xcode Cloud

set -e

echo "🔥 Starting ci_post_clone.sh v2.0..."

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

# Install iOS dependencies with CDN fallback
echo "🍎 Installing iOS dependencies..."
cd ios

# First try with CDN, then fallback to git repo on failure
echo "🍎 Attempting pod install with CDN..."
if ! pod install --repo-update; then
    echo "⚠️  CDN failed, falling back to git repo..."
    pod repo remove trunk || true
    pod repo add trunk https://github.com/CocoaPods/Specs.git --shallow
    pod install --repo-update
fi

cd ..

echo "✅ ci_post_clone.sh completed successfully!"