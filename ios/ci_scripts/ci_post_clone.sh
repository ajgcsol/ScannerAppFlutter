#!/bin/sh

# ci_post_clone.sh
# Xcode Cloud script to set up Flutter environment

set -e

echo "🔥 Starting ci_post_clone.sh..."

# Debug: Show current working directory and contents
echo "🔍 DEBUG: Current working directory: $(pwd)"
echo "🔍 DEBUG: Contents of current directory:"
ls -la

echo "🔍 DEBUG: Contents of ci_scripts directory:"
ls -la ci_scripts/ || echo "ci_scripts directory not found"

# Install Flutter (without sudo for Xcode Cloud)
echo "📱 Installing Flutter..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1 ~/flutter
export PATH="$PATH:$HOME/flutter/bin"

# Flutter setup
echo "📱 Setting up Flutter..."
flutter doctor -v
flutter precache --ios

# Install Dart dependencies
echo "📦 Installing Dart dependencies..."
flutter pub get

# Navigate to project root first (we're currently in ios/ci_scripts/)
echo "🔍 DEBUG: Navigating to project root..."
cd ../..
echo "🔍 DEBUG: Now in: $(pwd)"
ls -la

# Install iOS dependencies
echo "🍎 Installing iOS dependencies..."
cd ios
pod install --clean-install
cd ..

echo "✅ ci_post_clone.sh completed successfully!"