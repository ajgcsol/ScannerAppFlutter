# InSession - Charleston Law Event Scanner

A Flutter iOS application for scanning student ID barcodes at Charleston Law events.

## 📱 About

InSession is a mobile application designed for event organizers at Charleston Law to efficiently manage attendance by scanning student ID barcodes. The app provides real-time attendance tracking with offline capabilities and Firebase integration.

## 🚀 Features

- **Barcode Scanning**: Mobile scanner for student ID barcodes
- **Event Management**: Create and manage multiple events
- **Attendance Tracking**: Real-time attendance recording
- **Offline Support**: Works without internet connection
- **Data Export**: Export attendance data to CSV/Excel
- **Firebase Integration**: Cloud storage and synchronization

## 🛠 Development Setup

### Prerequisites
- Flutter SDK (^3.5.3)
- iOS development environment
- Xcode 15.2 or later
- Apple Developer Account

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/ajgcsol/ScannerAppFlutter.git
   cd ScannerAppFlutter
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   cd ios && pod install && cd ..
   ```

3. Run the app:
   ```bash
   flutter run
   ```

## 🏗 CI/CD with Xcode Cloud

This project is configured for automated iOS builds using Xcode Cloud. 

### Quick Setup
1. See **[Complete Setup Guide](XCODE_CLOUD_SETUP.md)** for detailed instructions
2. Use **[Quick Reference](QUICK_SETUP_REFERENCE.md)** for essential configuration
3. Run validation: `./ci_scripts/validate_setup.sh`

### Key Configuration
- **Bundle ID**: `com.charlestonlaw.insession`
- **Team ID**: `4BVW4KZPSA`
- **Triggers**: `main` and `ios-ui-improvements` branches
- **Output**: Automatic TestFlight uploads

## 📁 Project Structure

```
lib/
├── models/          # Data models
├── services/        # Firebase and API services
├── screens/         # UI screens
├── widgets/         # Reusable UI components
└── utils/           # Helper utilities

ios/
├── Runner/          # iOS app configuration
├── ci_scripts/      # Xcode Cloud build scripts
└── ExportOptions.plist

.xcode-cloud/
└── workflows/       # CI/CD workflow configuration
```

## 🧪 Testing

```bash
# Run unit tests
flutter test

# Run integration tests
flutter test integration_test/
```

## 📋 Dependencies

### Core
- **Flutter**: ^3.5.3
- **Provider**: State management
- **Riverpod**: Advanced state management

### Camera & Scanning
- **camera**: Camera functionality
- **mobile_scanner**: Barcode scanning
- **permission_handler**: Camera permissions

### Storage & Database
- **sqflite**: Local database
- **path_provider**: File system access
- **csv/excel**: Data export

### Networking (HTTP-only for Xcode 16 compatibility)
- **http**: HTTP client
- **dio**: Advanced HTTP client
- **connectivity_plus**: Network status

## 🔧 Configuration

### Environment Variables (Xcode Cloud)
- `APP_STORE_CONNECT_USERNAME`: App Store Connect email
- `APP_STORE_CONNECT_PASSWORD`: App-specific password
- `DEVELOPMENT_TEAM`: 4BVW4KZPSA
- `FLUTTER_ROOT`: /Users/local/flutter

### Firebase Configuration
Firebase dependencies are temporarily disabled for iOS Xcode 16 compatibility. HTTP-only implementation is used for cloud functions.

## 📄 License

Private repository - Charleston Law internal use only.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📞 Support

For issues and questions, please contact the development team or create an issue in the repository.
