# Deployment guide

## 1. First-time setup

```bash
./tool/bootstrap.sh
```

This generates the native platform folders, fetches packages and runs code
generation. Platform folders are not vendored: `flutter create` emits them
correctly for whatever Flutter version you have, which avoids stale Gradle and
CocoaPods pins that break builds months later.

## 2. Configuration

Copy `tool/dart_define.example.json` to `tool/dart_define.json` (git-ignored)
and fill in what you need. Every key is optional.

```bash
flutter run --dart-define-from-file=tool/dart_define.json
```

**Never commit secrets.** `Env` only reads compile-time values, and anything the
user enters at runtime goes to the platform keychain. The `.gitignore` already
excludes `google-services.json`, `GoogleService-Info.plist`,
`firebase_options.dart`, keystores and `key.properties`.

## 3. Native permissions

`flutter create` does not know what LifeOS needs. Add these after bootstrap.

### Android — `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>

<queries>
  <intent>
    <action android:name="android.speech.RecognitionService"/>
  </intent>
</queries>
```

Inside `<application>`, for scheduled notifications:

```xml
<receiver android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
<receiver android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
  <intent-filter>
    <action android:name="android.intent.action.BOOT_COMPLETED"/>
  </intent-filter>
</receiver>
```

`local_auth` requires `FlutterFragmentActivity`, not `FlutterActivity`, in
`MainActivity.kt`:

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity
class MainActivity : FlutterFragmentActivity()
```

Minimum SDK 23 (biometrics), target the current stable. `desugaring` must be on
for `flutter_local_notifications`:

```gradle
compileOptions { coreLibraryDesugaringEnabled true }
dependencies { coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4' }
```

### iOS — `ios/Runner/Info.plist`

```xml
<key>NSCameraUsageDescription</key>
<string>Attach photos to journal entries and scan receipts.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Add photos to your journal entries.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Record voice notes and capture entries by speaking.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Turn what you say into journal entries, tasks and expenses.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Tag journal entries with where you were.</string>
<key>NSFaceIDUsageDescription</key>
<string>Unlock LifeOS.</string>
<key>UIBackgroundModes</key>
<array><string>remote-notification</string><string>fetch</string></array>
```

Deployment target 13.0 or later. For Sign in with Apple, enable the capability in
Xcode and add the entitlement.

## 4. Firebase (optional)

Push notifications are optional — every reminder LifeOS actually needs is
scheduled locally, and `_initPush` treats a missing Firebase config as normal.

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Place `google-services.json` and `GoogleService-Info.plist`, and add the Google
services Gradle plugin. Both files stay out of version control.

## 5. Supabase (optional)

1. Create a project; copy the URL and anon key into your dart-define file.
2. Create the nine tables and RLS policies from [API.md](API.md).
3. Add the `delete_current_user()` RPC.
4. For Google sign-in, register the OAuth client and add the reversed client id
   to iOS URL schemes.

Without any of this, LifeOS runs on the local-only account and syncs nothing.

## 6. Home-screen widgets

The Dart side already publishes every value the widgets read
(`HomeWidgetService`). The widget UIs themselves are native views:

- **Android** — an `AppWidgetProvider` named `LifeOsWidgetProvider` plus layout
  XML. Read the values with `HomeWidgetPlugin.getData(context)`.
- **iOS** — a WidgetKit extension named `LifeOsWidget`, sharing the App Group
  `group.com.lifeos.widgets` (must match `HomeWidgetService.iosAppGroupId`).

Keys are listed as constants in `HomeWidgetService` so the two platforms cannot
drift apart.

## 7. Receipt OCR (opt-in)

Off by default because ML Kit adds roughly 30 MB to an Android build.

1. Uncomment `google_mlkit_text_recognition` in `pubspec.yaml`.
2. Implement `ReceiptScanner` with `TextRecognizer`, returning
   `ReceiptParser.parse(recognisedText.text)`.
3. Return it from `receiptScannerProvider`.
4. Build with `--dart-define=ENABLE_OCR=true`.

`ReceiptParser` — the part that turns OCR text into a transaction — is already
real and unit-tested, so this is a dependency change rather than a rewrite.

## 8. Hardening before a real release

**Database encryption at rest.** Replace `sqlite3_flutter_libs` with
`sqlcipher_flutter_libs` and pass a key from `SecureStore` in
`_openConnection()`. The OS sandbox is the current protection.

**Backup key derivation.** `EncryptionService` derives a passphrase key with
salted SHA-256. Move to PBKDF2 (or Argon2) with a high iteration count before
shipping; the envelope format already carries a version field for exactly this.

**Certificate pinning** for provider calls, if your threat model includes it.

**Crash reporting.** `AppLogger.installErrorHandlers()` is where Crashlytics or
Sentry hooks in — both global handlers are already routed there.

## 9. Build and release

```bash
flutter build appbundle --release --dart-define-from-file=tool/dart_define.json
flutter build ipa       --release --dart-define-from-file=tool/dart_define.json
```

Signing: create `android/key.properties` (git-ignored) and reference it from
`build.gradle`; use Xcode automatic signing or fastlane match for iOS.

### Store submission notes

Both stores will ask about data collection. The honest answers for a default
build:

- Data is stored **on device**; cloud sync is opt-in and off without
  configuration.
- No analytics or advertising SDKs are included.
- If the user connects a cloud AI provider, the records needed to answer their
  question are sent to that provider. Declare this, and name which providers are
  offered.
- Health data is user-entered, not read from HealthKit or Google Fit unless you
  add that integration — in which case both stores require additional
  disclosures.

## 10. CI

```yaml
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable }
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: dart format --set-exit-if-changed .
      - run: flutter analyze
      - run: flutter test --coverage
```

Code generation must run **before** analyze and test: `*.g.dart` and
`*.freezed.dart` are git-ignored, so a clean checkout does not compile without
it.

## 11. Troubleshooting

| Symptom | Cause |
| --- | --- |
| `Target of URI hasn't been generated` | Run `build_runner` |
| Notifications never fire on Android | Missing receivers, or desugaring off |
| Biometrics crash on Android | `MainActivity` still extends `FlutterActivity` |
| `PlatformException(sign_in_failed)` | SHA-1 not registered in Firebase/Google Cloud |
| Drift "no such table" after a schema change | `schemaVersion` not bumped, or `onUpgrade` step missing |
| Ollama unreachable from a device | `localhost` is the phone; use the host's LAN IP |
