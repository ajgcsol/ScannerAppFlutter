# Xcode Cloud

Xcode Cloud looks for `ci_scripts` **beside the Xcode project/workspace**, so
this directory — not a `ci_scripts/` at the repo root — is the one that runs.
Keep exactly one copy of these scripts here.

`ci_post_clone.sh` installs a pinned Flutter SDK (matching the version
developers build with — never `stable`, which drifts and breaks dependency
resolution), resolves packages, writes `ios/Flutter/Generated.xcconfig` via
`flutter build ios --config-only`, and runs `pod install`.

Set `INSESSION_API_KEY` as a **secret** workflow environment variable in
App Store Connect; without it the build still succeeds but testers must sign
in with Microsoft 365.
