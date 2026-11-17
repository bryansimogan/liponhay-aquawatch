# Liponhay AquaWatch

Android app for monitoring water quality and fish mortality at Liponhay Fish Farm. The app reads ESP32 sensor history from Firebase Realtime Database, displays alerts, and tracks the 10-minute safety verification period after a reading returns to range.

## Build for Android

1. Install Flutter and the Android SDK.
2. Register an Android app with package ID `com.example.fish_farm_app` in the Firebase project for your pond. Place its `google-services.json` in `android/app/`.
3. Configure Firebase Authentication and Realtime Database for the app and ESP32. The app uses anonymous authentication. It reads pond data under `ponds/pond1`, and history queries use an index on `timestamp`.
4. Run the commands below from the repository root.

```sh
flutter pub get
flutter test
flutter build apk --release
```

To display the pond's GSM SIM number in Settings, pass `--dart-define=GSM_NUMBER=<number>` when building. SMS recipients are managed separately in the app.

For simulated readings and incident recovery, open **Settings → Demo Mode**.
