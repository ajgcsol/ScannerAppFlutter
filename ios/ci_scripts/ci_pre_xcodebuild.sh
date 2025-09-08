#!/bin/sh

# ci_pre_xcodebuild.sh
# Xcode Cloud script to build Flutter app before Xcode build

set -e

echo "🔥 Starting ci_pre_xcodebuild.sh..."

# Debug: Show current working directory and contents
echo "🔍 DEBUG: Current working directory: $(pwd)"
echo "🔍 DEBUG: Contents of current directory:"
ls -la

# We're already in project root when script runs from ci_scripts/

echo "🔍 DEBUG: Confirmed we're in project root: $(pwd)"
echo "🔍 DEBUG: Contents of project root:"
ls -la

# Set Flutter path (should be installed by ci_post_clone.sh)
export PATH="$PATH:$HOME/flutter/bin"

# Verify Flutter installation
echo "📱 Verifying Flutter installation..."
which flutter || echo "❌ Flutter not found in PATH"
flutter --version || echo "❌ Flutter command failed"

# Get Flutter dependencies
echo "📱 Getting Flutter dependencies..."
flutter pub get

# Clean any previous builds
echo "🧹 Cleaning previous Flutter builds..."
flutter clean

# Generate required iOS files
echo "📱 Generating iOS configuration files..."
flutter precache --ios

# Build Flutter iOS app to ensure Generated.xcconfig is created
echo "📱 Building Flutter iOS app..."
flutter build ios --release --no-codesign

# Debug: Check what was created
echo "🔍 DEBUG: Contents of ios/Flutter/ after build:"
ls -la ios/Flutter/

# Verify Generated.xcconfig was created
if [ -f "ios/Flutter/Generated.xcconfig" ]; then
    echo "✅ Generated.xcconfig created successfully"
    echo "📋 Generated.xcconfig contents:"
    cat ios/Flutter/Generated.xcconfig
else
    echo "❌ ERROR: Generated.xcconfig not found"
    echo "🔍 DEBUG: Full directory listing:"
    find ios/Flutter/ -name "*.xcconfig" || echo "No xcconfig files found"
    exit 1
fi

echo "✅ ci_pre_xcodebuild.sh completed successfully!"