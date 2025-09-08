# Xcode Cloud Setup for InSession - Complete Step-by-Step Guide

This document provides detailed, step-by-step instructions for setting up Xcode Cloud CI/CD for the InSession Flutter iOS app with proper environment variables configuration.

## Prerequisites Checklist

- [ ] **Apple Developer Account**: Active Apple Developer Program membership ($99/year)
- [ ] **App Store Connect Access**: Admin or App Manager role access
- [ ] **GitHub Repository**: Project hosted on GitHub with proper access permissions
- [ ] **Development Team ID**: `4BVW4KZPSA` (already configured in project)
- [ ] **Bundle ID**: `com.charlestonlaw.insession` (already configured)

## Part 1: App Store Connect Setup

### Step 1: Create App Store Connect App

1. Sign in to [App Store Connect](https://appstoreconnect.apple.com)
2. Click **"My Apps"** in the top navigation
3. Click the **"+"** button and select **"New App"**
4. Fill in the app details:
   - **Platform**: iOS
   - **Name**: InSession
   - **Primary Language**: English (U.S.)
   - **Bundle ID**: Select `com.charlestonlaw.insession`
   - **SKU**: `insession-ios-app` (or your preferred unique identifier)
5. Click **"Create"**

### Step 2: Configure App Information

1. In your newly created app, go to **"App Information"**
2. Set **Category**: Business (or appropriate category)
3. Set **Content Rights**: Does Not Use Third-Party Content
4. Save changes

### Step 3: Create App-Specific Password

1. Go to [Apple ID Account Settings](https://appleid.apple.com/account/manage)
2. Sign in with your Apple ID
3. Go to **"Security"** section
4. Under **"App-Specific Passwords"**, click **"Generate Password..."**
5. Enter label: `Xcode Cloud InSession`
6. **IMPORTANT**: Copy and save this password - you'll need it for environment variables
7. Keep this password secure - it cannot be viewed again

## Part 2: Xcode Cloud Configuration

### Step 4: Access Xcode Cloud

1. In App Store Connect, navigate to your **InSession** app
2. Click the **"Xcode Cloud"** tab
3. If first time setup, click **"Get Started"**
4. If already set up, click **"Manage Workflows"**

### Step 5: Connect GitHub Repository

1. Click **"Connect SCM Provider"** or **"Add Repository"**
2. Select **"GitHub"**
3. Authorize GitHub access if prompted
4. Select repository: `ajgcsol/ScannerAppFlutter`
5. Grant necessary permissions when prompted
6. Click **"Next"**

### Step 6: Configure Workflow

1. Xcode Cloud should auto-detect the workflow file at `.xcode-cloud/workflows/InSession.yml`
2. If not detected, click **"Create Custom Workflow"**
3. Select the workflow file: `InSession.yml`
4. Review the workflow configuration:
   - **Name**: InSession CI/CD
   - **Branch Triggers**: `main` and `ios-ui-improvements`
   - **Pull Request Triggers**: `main`

### Step 7: Configure Environment Variables

This is the **CRITICAL** step for proper setup:

1. In the workflow configuration, click **"Environment Variables"**
2. Click **"+"** to add each variable:

#### Required Environment Variables:

| Variable Name | Value | Description |
|---------------|-------|-------------|
| `APP_STORE_CONNECT_USERNAME` | `your-email@domain.com` | Your App Store Connect login email |
| `APP_STORE_CONNECT_PASSWORD` | `xxxx-xxxx-xxxx-xxxx` | App-specific password created in Step 3 |
| `DEVELOPMENT_TEAM` | `4BVW4KZPSA` | Your Apple Developer Team ID |
| `FLUTTER_ROOT` | `/Users/local/flutter` | Flutter installation path (set by CI script) |

#### Optional Environment Variables for Enhanced Setup:

| Variable Name | Value | Description |
|---------------|-------|-------------|
| `BUNDLE_ID` | `com.charlestonlaw.insession` | App bundle identifier |
| `APP_NAME` | `InSession` | App display name |
| `EXPORT_METHOD` | `app-store` | Distribution method |

### Step 8: Configure Code Signing

1. In workflow settings, go to **"Code Signing"**
2. Select **"Automatic"** (recommended)
3. Verify **Team ID**: `4BVW4KZPSA`
4. Ensure **Signing Certificate**: Automatically managed

### Step 9: Set Up Test Plans (Optional)

1. Go to **"Test Plans"** section
2. Enable **"Unit Tests"** if you have tests
3. Configure test destinations (iOS Simulator versions)

### Step 10: Enable Workflow

1. Review all settings
2. Click **"Save"** or **"Update Workflow"**
3. Toggle workflow to **"Enabled"**
4. Set branch protection rules if needed

## Part 3: Verification and Testing

### Step 11: Verify Project Configuration

Run this verification checklist:

- [ ] CI scripts are executable: `ci_scripts/ci_post_clone.sh` and `ci_scripts/ci_pre_xcodebuild.sh`
- [ ] Export options configured: `ios/ExportOptions.plist`
- [ ] Flutter dependencies listed in `pubspec.yaml`
- [ ] iOS project settings match Team ID: `4BVW4KZPSA`

### Step 12: Test the Workflow

1. Make a small change to any file (e.g., add a comment)
2. Commit and push to the `main` branch:
   ```bash
   git add .
   git commit -m "Test Xcode Cloud workflow"
   git push origin main
   ```
3. Go to **App Store Connect** > **Xcode Cloud** > **Builds**
4. Monitor the build progress

### Step 13: Monitor First Build

Expected workflow steps:
1. **Source Checkout** ✅
2. **Post-Clone Actions** (Flutter setup) ✅
3. **Pre-Xcodebuild Actions** (Flutter build) ✅
4. **Build & Archive** ✅
5. **Export & Upload** (if configured) ✅

## Part 4: Troubleshooting Guide

### Common Issues and Solutions:

#### 1. **Flutter Not Found Error**
- **Solution**: Ensure `ci_scripts/ci_post_clone.sh` is executable
- **Check**: `chmod +x ci_scripts/ci_post_clone.sh`

#### 2. **Code Signing Failed**
- **Solution**: Verify Team ID in Xcode Cloud matches `4BVW4KZPSA`
- **Check**: App Store Connect > Certificates, Identifiers & Profiles

#### 3. **TestFlight Upload Failed**
- **Solution**: Verify `APP_STORE_CONNECT_USERNAME` and `APP_STORE_CONNECT_PASSWORD`
- **Check**: App-specific password is correct and not expired

#### 4. **Workflow Not Triggering**
- **Solution**: Check branch names match exactly (`main`, `ios-ui-improvements`)
- **Check**: GitHub webhook is properly configured

#### 5. **Flutter Dependencies Failing**
- **Solution**: Update `pubspec.yaml` if needed
- **Check**: All dependencies are compatible with current Flutter version

### Build Logs Location:
- **App Store Connect** > **Xcode Cloud** > **Builds** > Select build > **Logs**

## Part 5: Ongoing Management

### Updating Environment Variables:
1. Go to **App Store Connect** > **Xcode Cloud** > **Workflows**
2. Select **InSession CI/CD** workflow
3. Click **"Environment Variables"**
4. Modify as needed

### Adding New Branches:
1. Edit `.xcode-cloud/workflows/InSession.yml`
2. Add branch names to `trigger: branches: include:` section
3. Commit and push changes

### Monitoring Builds:
- **Dashboard**: App Store Connect > Xcode Cloud > Overview
- **Build History**: App Store Connect > Xcode Cloud > Builds
- **TestFlight Integration**: Automatic uploads on successful builds

## Part 6: Security Best Practices

### Environment Variables Security:
- ✅ Use app-specific passwords, never your main Apple ID password
- ✅ Rotate app-specific passwords regularly (every 6 months)
- ✅ Monitor access logs in Apple ID settings
- ✅ Use least-privilege access for App Store Connect accounts

### Repository Security:
- ✅ Enable branch protection on `main` branch
- ✅ Require pull request reviews for production changes
- ✅ Monitor GitHub webhook deliveries
- ✅ Use signed commits when possible

## Validation Checklist

Before considering setup complete:

- [ ] App created in App Store Connect
- [ ] GitHub repository connected
- [ ] Environment variables configured
- [ ] Workflow enabled and saved
- [ ] Test build triggered successfully
- [ ] Build logs show all steps passing
- [ ] TestFlight upload working (if configured)
- [ ] Team notifications set up

---

## Quick Reference Commands

```bash
# Check script permissions
ls -la ci_scripts/

# Make scripts executable (if needed)
chmod +x ci_scripts/ci_post_clone.sh
chmod +x ci_scripts/ci_pre_xcodebuild.sh

# Trigger workflow test
git commit -m "Test Xcode Cloud" --allow-empty
git push origin main
```

## Support Resources

- **Apple Developer Documentation**: [Xcode Cloud Overview](https://developer.apple.com/xcode-cloud/)
- **Flutter CI/CD Guide**: [Flutter DevTools](https://docs.flutter.dev/deployment/cd)
- **App Store Connect Help**: [App Store Connect User Guide](https://help.apple.com/app-store-connect/)

---

**Setup Complete!** 🎉

Your InSession Flutter app is now configured for Xcode Cloud CI/CD with proper environment variables. Every push to `main` or `ios-ui-improvements` branches will trigger an automatic build, archive, and TestFlight upload.