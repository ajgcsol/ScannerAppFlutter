#!/bin/sh

# ci_post_clone.sh
# Xcode Cloud script to set up Flutter environment

set -e

echo "🔥 Starting ci_post_clone.sh..."

# Check if Flutter is already installed
if command -v flutter > /dev/null 2>&1; then
    echo "📱 Flutter already installed, skipping installation..."
    export PATH="$PATH:$HOME/flutter/bin"
else
    # Install Flutter
    echo "📱 Installing Flutter..."
    git clone https://github.com/flutter/flutter.git -b stable --depth 1 $HOME/flutter
    export PATH="$PATH:$HOME/flutter/bin"
fi

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