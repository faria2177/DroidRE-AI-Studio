# Android and GitHub build setup

## Prerequisites

- Flutter 3.47.4 stable target (or adapt Gradle/AGP to your supported Flutter).
- JDK 17.
- Android SDK Platform 36 and required command-line tools.
- A GitHub repository with Actions enabled.

## Commands

```bash
flutter create . --platforms=android --org com.jahid --project-name droidre_ai_studio
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release --split-per-abi
```

Generated Android platform files from `flutter create` are needed for
Gradle launcher scripts/jar; CI runs this command before building.

## GitHub Actions

- `flutter-ci.yml`: formatting, analyze, tests, debug APK and SHA-256 artifact.
- `android-apk.yml`: manually builds ABI-specific **test-signed** release-mode APKs.

Default branch is `main`; workflow creation/updates can require the GitHub
token or GitHub App to have **Workflows** permission. A push denied by that
protection must be resolved through GitHub's authorized permission controls.

## Signing

The initial release build type is debug-key signed for testing. Do not
distribute it as a production release. Configure an owner-controlled release
keystore and protected GitHub secrets before adding public release automation.
The release certificate's SHA-1/SHA-256 must be registered for Google Sign-In.

## Android 16

When JNI libraries are added, audit arm64 16 KB page-size alignment and ensure
ABI completeness. Current Dart archive code does not ship a custom JNI parser.
