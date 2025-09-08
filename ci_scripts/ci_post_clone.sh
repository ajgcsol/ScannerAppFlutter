#!/bin/sh

# ci_post_clone.sh
# Xcode Cloud script to set up Flutter environment

set -e

echo "🔥 Starting ci_post_clone.sh..."

# Install Flutter
echo "📱 Installing Flutter..."
sudo git clone https://github.com/flutter/flutter.git -b stable --depth 1 /usr/local/flutter
sudo chown -R $(whoami) /usr/local/flutter
export PATH="$PATH:/usr/local/flutter/bin"

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