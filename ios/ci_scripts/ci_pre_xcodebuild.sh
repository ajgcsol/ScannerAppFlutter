#!/bin/sh

# ci_pre_xcodebuild.sh
# Xcode Cloud script to build Flutter app before Xcode build

set -e

echo "🔥 Starting ci_pre_xcodebuild.sh..."

# Navigate to project root (we're currently in ios/ directory)
cd ..

# Set Flutter path (should be installed by ci_post_clone.sh)
export PATH="$PATH:/usr/local/flutter/bin"

# Verify Flutter installation
echo "📱 Verifying Flutter installation..."
flutter doctor -v

# Get Flutter dependencies
echo "📱 Getting Flutter dependencies..."
flutter pub get

# Generate required iOS files
echo "📱 Generating iOS configuration files..."
flutter precache --ios

# Build Flutter iOS app to ensure Generated.xcconfig is created
echo "📱 Building Flutter iOS app..."
flutter build ios --release --no-codesign

# Verify Generated.xcconfig was created
if [ -f "ios/Flutter/Generated.xcconfig" ]; then
    echo "✅ Generated.xcconfig created successfully"
else
    echo "❌ ERROR: Generated.xcconfig not found"
    ls -la ios/Flutter/
    exit 1
fi

echo "✅ ci_pre_xcodebuild.sh completed successfully!"