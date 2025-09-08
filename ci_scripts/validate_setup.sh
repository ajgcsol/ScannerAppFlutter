#!/bin/bash

# validate_setup.sh
# Script to validate Xcode Cloud setup for InSession Flutter app

echo "🔍 Validating Xcode Cloud Setup for InSession..."
echo "================================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2${NC}"
        return 0
    else
        echo -e "${RED}❌ $2${NC}"
        return 1
    fi
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "ℹ️  $1"
}

# Validation counters
CHECKS_PASSED=0
TOTAL_CHECKS=0

echo ""
echo "📁 File Structure Validation"
echo "----------------------------"

# Check if required files exist
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if [ -f ".xcode-cloud/workflows/InSession.yml" ]; then
    print_status 0 "Xcode Cloud workflow file exists"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    print_status 1 "Xcode Cloud workflow file missing"
fi

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if [ -f "ci_scripts/ci_post_clone.sh" ] && [ -x "ci_scripts/ci_post_clone.sh" ]; then
    print_status 0 "Post-clone script exists and is executable"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    print_status 1 "Post-clone script missing or not executable"
    print_info "Run: chmod +x ci_scripts/ci_post_clone.sh"
fi

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if [ -f "ci_scripts/ci_pre_xcodebuild.sh" ] && [ -x "ci_scripts/ci_pre_xcodebuild.sh" ]; then
    print_status 0 "Pre-xcodebuild script exists and is executable"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    print_status 1 "Pre-xcodebuild script missing or not executable"
    print_info "Run: chmod +x ci_scripts/ci_pre_xcodebuild.sh"
fi

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if [ -f "ios/ExportOptions.plist" ]; then
    print_status 0 "Export options plist exists"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    print_status 1 "Export options plist missing"
fi

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if [ -f "pubspec.yaml" ]; then
    print_status 0 "Flutter pubspec.yaml exists"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    print_status 1 "Flutter pubspec.yaml missing"
fi

echo ""
echo "⚙️  Configuration Validation"
echo "----------------------------"

# Check workflow configuration
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if grep -q "ios-ui-improvements" ".xcode-cloud/workflows/InSession.yml" 2>/dev/null; then
    print_status 0 "Workflow configured for ios-ui-improvements branch"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    print_status 1 "Workflow not configured for ios-ui-improvements branch"
fi

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if grep -q "main" ".xcode-cloud/workflows/InSession.yml" 2>/dev/null; then
    print_status 0 "Workflow configured for main branch"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    print_status 1 "Workflow not configured for main branch"
fi

# Check iOS project configuration
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if grep -q "4BVW4KZPSA" "ios/Runner.xcodeproj/project.pbxproj" 2>/dev/null; then
    print_status 0 "Development Team ID configured (4BVW4KZPSA)"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    print_status 1 "Development Team ID not found or incorrect"
fi

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if grep -q "com.charlestonlaw.insession" "ios/Runner.xcodeproj/project.pbxproj" 2>/dev/null; then
    print_status 0 "Bundle ID configured (com.charlestonlaw.insession)"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
elif grep -q "PRODUCT_BUNDLE_IDENTIFIER" "ios/Runner/Info.plist" 2>/dev/null; then
    print_status 0 "Bundle ID placeholder configured in Info.plist"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    print_status 1 "Bundle ID not found or incorrect"
fi

# Check export options
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if grep -q "app-store" "ios/ExportOptions.plist" 2>/dev/null; then
    print_status 0 "Export method set to app-store"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    print_status 1 "Export method not configured for app-store"
fi

echo ""
echo "📋 Environment Variables Checklist"
echo "----------------------------------"
print_warning "These must be configured in Xcode Cloud dashboard:"
echo "   • APP_STORE_CONNECT_USERNAME (your App Store Connect email)"
echo "   • APP_STORE_CONNECT_PASSWORD (app-specific password)"
echo "   • DEVELOPMENT_TEAM (4BVW4KZPSA)"
echo "   • FLUTTER_ROOT (/Users/local/flutter)"

echo ""
echo "🔐 Security Checklist"
echo "---------------------"
print_warning "Ensure you have:"
echo "   • Created app-specific password in Apple ID settings"
echo "   • App created in App Store Connect"
echo "   • GitHub repository connected to Xcode Cloud"
echo "   • Proper permissions for App Store Connect account"

echo ""
echo "📊 Validation Summary"
echo "====================/"
echo "Checks passed: $CHECKS_PASSED out of $TOTAL_CHECKS"

if [ $CHECKS_PASSED -eq $TOTAL_CHECKS ]; then
    echo -e "${GREEN}🎉 All validations passed! Setup looks good.${NC}"
    echo ""
    echo -e "${GREEN}Next steps:${NC}"
    echo "1. Configure environment variables in Xcode Cloud"
    echo "2. Push to main or ios-ui-improvements branch to trigger build"
    echo "3. Monitor build progress in App Store Connect > Xcode Cloud"
    exit 0
else
    FAILED_CHECKS=$((TOTAL_CHECKS - CHECKS_PASSED))
    echo -e "${RED}⚠️  $FAILED_CHECKS validation(s) failed. Please fix the issues above.${NC}"
    echo ""
    echo -e "${YELLOW}Common fixes:${NC}"
    echo "• Make scripts executable: chmod +x ci_scripts/*.sh"
    echo "• Ensure all required files are present"
    echo "• Check Xcode project settings for Team ID and Bundle ID"
    exit 1
fi