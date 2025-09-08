#!/bin/sh

# ci_post_clone.sh
# Xcode Cloud script to set up Flutter environment

set -e

echo "🔥 Starting ci_post_clone.sh..."

# We're already in project root when script runs from ci_scripts/

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

# Install iOS dependencies
echo "🍎 Installing iOS dependencies..."
cd ios
pod install --clean-install
cd ..

echo "✅ ci_post_clone.sh completed successfully!"