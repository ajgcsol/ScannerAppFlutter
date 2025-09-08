#!/bin/sh

echo "🔥 FOUND xcode_cloud_post_clone.sh in project root"
echo "Current directory: $(pwd)"
echo "Directory contents:"
ls -la

# Install Flutter without sudo
echo "Installing Flutter to home directory..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1 ~/flutter
export PATH="$PATH:$HOME/flutter/bin"

echo "Flutter setup..."
flutter doctor -v
flutter pub get

echo "Installing iOS pods..."
cd ios && pod install && cd ..

echo "✅ xcode_cloud_post_clone.sh completed"