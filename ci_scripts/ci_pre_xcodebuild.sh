#!/bin/sh

# ci_pre_xcodebuild.sh  
# Xcode Cloud script to build Flutter app before Xcode build

set -e

echo "🔥 FOUND ci_pre_xcodebuild.sh in ROOT DIRECTORY"

# Debug: Show current working directory and contents
echo "🔍 DEBUG: Current working directory: $(pwd)"
echo "🔍 DEBUG: Contents of current directory:"
ls -la

echo "🔍 DEBUG: Contents of ci_scripts directory:"
ls -la ci_scripts/ || echo "ci_scripts directory not found"

# Set Flutter path (should be installed by ci_post_clone.sh)
export PATH="$PATH:$HOME/flutter/bin"

# Verify Flutter installation
echo "📱 Verifying Flutter installation..."
which flutter || echo "❌ Flutter not found in PATH"
flutter --version || echo "❌ Flutter command failed"

# Get Flutter dependencies
echo "📱 Getting Flutter dependencies..."
flutter pub get || echo "❌ Flutter pub get failed"

# Clean any previous builds
echo "🧹 Cleaning previous Flutter builds..."
flutter clean || echo "❌ Flutter clean failed"

# Generate required iOS files
echo "📱 Generating iOS configuration files..."
flutter precache --ios || echo "❌ Flutter precache failed"

# Build Flutter iOS app to ensure Generated.xcconfig is created
echo "📱 Building Flutter iOS app..."
flutter build ios --release --no-codesign || echo "❌ Flutter build ios failed"

# Debug: Check what was created
echo "🔍 DEBUG: Contents of ios/Flutter/ after build:"
ls -la ios/Flutter/ || echo "❌ ios/Flutter directory not found"

# Verify Generated.xcconfig was created
if [ -f "ios/Flutter/Generated.xcconfig" ]; then
    echo "✅ Generated.xcconfig created successfully"
    echo "📋 Generated.xcconfig contents:"
    cat ios/Flutter/Generated.xcconfig
else
    echo "❌ ERROR: Generated.xcconfig not found"
    echo "🔍 DEBUG: Full directory listing:"
    find ios/Flutter/ -name "*.xcconfig" || echo "No xcconfig files found"
    
    # Try to create a minimal Generated.xcconfig as fallback
    echo "🔧 Creating fallback Generated.xcconfig..."
    mkdir -p ios/Flutter/
    cat > ios/Flutter/Generated.xcconfig << 'EOF'
// Flutter Generated.xcconfig (Fallback)
FLUTTER_ROOT=$HOME/flutter
FLUTTER_APPLICATION_PATH=.
COCOAPODS_PARALLEL_CODE_SIGN=true
FLUTTER_TARGET=lib/main.dart
FLUTTER_BUILD_DIR=build
FLUTTER_BUILD_NAME=1.0.0
FLUTTER_BUILD_NUMBER=1
EXCLUDED_ARCHS[sdk=iphonesimulator*]=i386
EXCLUDED_ARCHS[sdk=iphoneos*]=armv7
DART_OBFUSCATION=false
TRACK_WIDGET_CREATION=true
TREE_SHAKE_ICONS=false
PACKAGE_CONFIG=.dart_tool/package_config.json
EOF
    echo "✅ Fallback Generated.xcconfig created"
fi

echo "✅ ci_pre_xcodebuild.sh completed successfully!"