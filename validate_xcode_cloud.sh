#!/bin/bash

# validate_xcode_cloud.sh
# Script to validate Xcode Cloud configuration for Flutter app

set -e

echo "🔍 Validating Xcode Cloud Configuration..."
echo "=========================================="

# Check if we're in a Flutter project
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ Error: pubspec.yaml not found. Are you in the Flutter project root?"
    exit 1
fi

echo "✅ Flutter project detected"

# Check for Xcode Cloud workflow
if [ ! -f ".xcode-cloud/workflows/InSession.yml" ]; then
    echo "❌ Error: Xcode Cloud workflow not found at .xcode-cloud/workflows/InSession.yml"
    exit 1
fi

echo "✅ Xcode Cloud workflow found"

# Check CI scripts
if [ ! -f "ci_scripts/ci_post_clone.sh" ]; then
    echo "❌ Error: ci_post_clone.sh not found"
    exit 1
fi

if [ ! -f "ci_scripts/ci_pre_xcodebuild.sh" ]; then
    echo "❌ Error: ci_pre_xcodebuild.sh not found"
    exit 1
fi

# Check if CI scripts are executable
if [ ! -x "ci_scripts/ci_post_clone.sh" ]; then
    echo "⚠️  Warning: ci_post_clone.sh is not executable. Run: chmod +x ci_scripts/ci_post_clone.sh"
else
    echo "✅ ci_post_clone.sh is executable"
fi

if [ ! -x "ci_scripts/ci_pre_xcodebuild.sh" ]; then
    echo "⚠️  Warning: ci_pre_xcodebuild.sh is not executable. Run: chmod +x ci_scripts/ci_pre_xcodebuild.sh"
else
    echo "✅ ci_pre_xcodebuild.sh is executable"
fi

# Check iOS configuration
if [ ! -f "ios/Runner.xcworkspace/contents.xcworkspacedata" ]; then
    echo "❌ Error: iOS workspace not found. Run 'pod install' in the ios/ directory"
    exit 1
fi

echo "✅ iOS workspace found"

# Check ExportOptions.plist
if [ ! -f "ios/ExportOptions.plist" ]; then
    echo "❌ Error: ExportOptions.plist not found"
    exit 1
fi

echo "✅ ExportOptions.plist found"

# Check current branch
CURRENT_BRANCH=$(git branch --show-current)
echo "📍 Current branch: $CURRENT_BRANCH"

# Check if current branch is configured for Xcode Cloud
if grep -q "$CURRENT_BRANCH" .xcode-cloud/workflows/InSession.yml; then
    echo "✅ Current branch is configured in Xcode Cloud workflow"
else
    echo "⚠️  Warning: Current branch '$CURRENT_BRANCH' is not configured in Xcode Cloud workflow"
    echo "    Configured branches:"
    grep -A 5 "include:" .xcode-cloud/workflows/InSession.yml | grep -E "^\s*-" | sed 's/^/    /'
fi

# Check bundle ID consistency
BUNDLE_ID=$(grep -A 1 "PRODUCT_BUNDLE_IDENTIFIER" ios/Runner.xcodeproj/project.pbxproj | grep "com\." | head -1 | sed 's/.*= \(.*\);.*/\1/')
echo "📱 Bundle ID: $BUNDLE_ID"

if [ "$BUNDLE_ID" = "com.charlestonlaw.insession" ]; then
    echo "✅ Bundle ID matches expected value"
else
    echo "⚠️  Warning: Bundle ID does not match expected 'com.charlestonlaw.insession'"
fi

echo ""
echo "🏁 Configuration validation complete!"
echo ""
echo "Next steps:"
echo "1. Ensure you have access to App Store Connect"
echo "2. Connect your GitHub repository to Xcode Cloud"
echo "3. Configure environment variables (APP_STORE_CONNECT_USERNAME, APP_STORE_CONNECT_PASSWORD)"
echo "4. Push to a configured branch to trigger a build"