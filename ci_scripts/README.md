# Xcode Cloud scripts

`ci_post_clone.sh` installs a pinned Flutter SDK, resolves packages, writes
`ios/Flutter/Generated.xcconfig` via `flutter build ios --config-only`, and runs
`pod install`. Xcode Cloud then archives with plain xcodebuild.

The workflow must define `INSESSION_API_KEY` as a **secret** environment
variable; the script fails fast without it rather than shipping an app that
cannot reach the backend.
