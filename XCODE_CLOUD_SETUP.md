# Xcode Cloud Setup for InSession

This document provides instructions for setting up Xcode Cloud CI/CD for the InSession Flutter iOS app.

## Prerequisites

1. **Apple Developer Account**: You need an active Apple Developer account
2. **App Store Connect Access**: Access to App Store Connect with admin privileges
3. **GitHub Repository**: The project must be hosted on GitHub

## Setup Steps

### 1. App Store Connect Configuration

1. Sign in to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to "Apps" and create a new app if not already created:
   - **Bundle ID**: `com.charlestonlaw.insession`
   - **App Name**: InSession
   - **Primary Language**: English
   - **Platform**: iOS

### 2. Xcode Cloud Workflow

The project includes a pre-configured Xcode Cloud workflow at `.xcode-cloud/workflows/InSession.yml` that:

- Triggers on pushes to `ios-ui-improvements` and `master` branches
- Uses CI scripts to install Flutter and dependencies  
- Builds the iOS app using Flutter
- Archives and exports IPA automatically via Xcode Cloud
- Uploads to TestFlight (when credentials are configured)

### 3. Required Environment Variables

Set these environment variables in Xcode Cloud:

- `APP_STORE_CONNECT_USERNAME`: Your App Store Connect email
- `APP_STORE_CONNECT_PASSWORD`: App-specific password (create in Apple ID settings)

### 4. Code Signing Configuration

The project is configured for automatic code signing with:
- **Team ID**: Set in Xcode project settings
- **Bundle ID**: `com.charlestonlaw.insession`
- **Signing Style**: Automatic

### 5. CI Scripts

The following scripts are included for Xcode Cloud:

- `ci_scripts/ci_post_clone.sh`: Installs Flutter and dependencies after clone
- `ci_scripts/ci_pre_xcodebuild.sh`: Builds Flutter app before Xcode build
- `ios/ExportOptions.plist`: Export configuration for App Store distribution

## Manual Setup in Xcode Cloud

1. In App Store Connect, navigate to your app
2. Go to "Xcode Cloud" tab
3. Click "Get Started" if not already set up
4. Connect your GitHub repository
5. Select the workflow configuration (should auto-detect the `.yml` file)
6. Configure environment variables in the workflow settings
7. Enable automatic builds for the specified branches

## Testing the Setup

1. **Validate Configuration**: Run the validation script to check your setup:
   ```bash
   ./validate_xcode_cloud.sh
   ```

2. Push changes to the `ios-ui-improvements` or `master` branch
3. Check Xcode Cloud dashboard for build progress
4. Successful builds will appear in TestFlight for internal testing

## Troubleshooting

### Common Issues

- **Flutter not found**: Ensure `ci_post_clone.sh` is executable (`chmod +x`)
- **Code signing issues**: Verify Team ID and certificates in developer portal
- **Build failures**: Check Xcode Cloud logs for specific error messages
- **TestFlight upload fails**: Verify App Store Connect credentials and app configuration
- **Branch not triggering builds**: Ensure your branch name matches the workflow triggers (`ios-ui-improvements` or `master`)
- **Dependency conflicts**: Clear derived data and ensure `pod install` completes successfully

### Debug Steps

1. **Check Xcode Cloud Logs**: In App Store Connect > Xcode Cloud, view the detailed logs for each build step
2. **Verify CI Scripts**: Ensure both `ci_post_clone.sh` and `ci_pre_xcodebuild.sh` are executable
3. **Test Flutter Build Locally**: Run `flutter build ios --release --no-codesign` to verify the app builds
4. **Check iOS Configuration**: Verify Team ID, Bundle ID, and signing certificates are properly configured
5. **Validate Workflow**: Ensure the `.xcode-cloud/workflows/InSession.yml` file is properly formatted

### Configuration Checklist

- [ ] Repository connected to Xcode Cloud in App Store Connect
- [ ] Team ID set correctly in iOS project (`4BVW4KZPSA`)
- [ ] Bundle ID matches: `com.charlestonlaw.insession`
- [ ] App Store Connect credentials configured (if using TestFlight upload)
- [ ] CI scripts have execute permissions
- [ ] Pushing to correct branch (`ios-ui-improvements` or `master`)
- [ ] Xcode Cloud workflow file exists at `.xcode-cloud/workflows/InSession.yml`

## Next Steps

1. Complete the setup in App Store Connect
2. Configure team and certificates for code signing
3. Test the workflow by pushing to the `ios-ui-improvements` or `master` branch
4. Set up automatic TestFlight distribution for beta testing