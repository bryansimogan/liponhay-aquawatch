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

## Mortality and management logs

Mortality records under `ponds/pond1/mortality` retain the report time, optional remarks, and the matched sensor snapshot. Editing the count or remarks preserves the original evidence. The existing 30-minute matching window applies, and missing or incomplete readings are identified in the details. Management and report totals follow this same saved mortality collection.

The response center saves incident history under `ponds/pond1/management_logs`. The app requires read and write access to this node in the existing Realtime Database rules. Transactions deduplicate readings across clients, update severity and the latest measured value, and retain the 10-minute continuous safety verification. Incidents continue to require live incoming readings while the app is running. A missing-reading gap restarts verification. Demo data remains in the existing local demo storage.

The separate Stocking button in Management saves the stocked count, pond area, and stocking date under ponds/pond1/stocking. This node requires read and write access. Fingerlings alive is calculated from stocking, mortality, and harvest. Existing saved stocking details are retained. Fresh live installations use zero fish until stocking is configured.
