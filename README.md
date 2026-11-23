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

The app opens in live mode. Demo Mode controls and the alternate demo entry point have been removed. The legacy demo preference is cleared on startup, and demo stock/harvest data is not imported into a fresh live store.

## Connection status and printing

Dashboard and Settings distinguish Android's validated internet connection, the Firebase session, and ESP32 freshness. The app watches both `ponds/pond1/current` and recent `ponds/pond1/history` and uses the newest valid measurement. Last Sync updates from the timestamp and shows elapsed seconds using Firebase's server clock estimate. The ESP32 is Offline at two minutes without a fresh reading. Temporary read failures preserve the last measurement and the app retries automatically.

Alerts and Notifications share one local feed generated from the same readings and warning thresholds used in Dashboard and Management. Each pond, parameter, and measurement timestamp identifies one alert. The feed retains the latest 500 alerts and catches up from up to 200 recent hardware history rows on reconnect. Clearing alerts clears this feed on the current phone. This feed does not verify SMS delivery.

Open **Summary of Reports**, choose a day, week, or month, and tap the printer icon. Android's print dialog lets you choose a printer or Save as PDF. The report contains the selected period's incidents, actions, mortality, and harvest, plus a separately labeled cycle-to-date production summary. PDF fonts are bundled for offline generation. Copy report remains available. Offline reports reflect records already saved on the phone.

## Mortality and management logs

Mortality records under `ponds/pond1/mortality` retain the report time, optional remarks, and the matched sensor snapshot. Editing the count or remarks preserves the original evidence. The existing 30-minute matching window applies, and missing or incomplete readings are identified in the details. Management and report totals follow this same saved mortality collection.

The response center saves incident history under `ponds/pond1/management_logs`. The app requires read and write access to this node in the existing Realtime Database rules. Transactions deduplicate readings across clients, update severity and the latest measured value, and retain the 10-minute continuous safety verification. Incidents continue to require live incoming readings while the app is running. A missing-reading gap restarts verification. Existing live records are retained.

The separate Stocking button in Management saves the stocked count, pond area, and stocking date under ponds/pond1/stocking. This node requires read and write access. Fingerlings alive uses the stocked count minus saved, operator-entered deaths and harvests from the stocking date onward. Water-quality alerts do not deduct any fish. Earlier records remain in history and date-filtered reports.
