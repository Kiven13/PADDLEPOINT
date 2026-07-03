# Pickleball Scoreboard — Flutter BLE Remote App
### Philippines Edition

A Flutter app that controls your ESP32 NeoPixel scoreboard over Bluetooth Low Energy.
Works on both **Android** and **iOS** alongside the existing IR remote.

---

## Project Structure

```
pickleball_app/
├── lib/
│   ├── main.dart                        # App entry point
│   ├── theme/
│   │   └── app_theme.dart               # Colors, typography, ThemeData
│   ├── models/
│   │   └── match_model.dart             # MatchRecord, SetResult data classes
│   ├── services/
│   │   ├── ble_constants.dart           # UUIDs and command byte values
│   │   ├── ble_service.dart             # BLE scan / connect / send / notify
│   │   ├── database_service.dart        # SQLite match history (sqflite)
│   │   └── game_provider.dart           # Game state + history (ChangeNotifier)
│   ├── screens/
│   │   ├── connect_screen.dart          # Screen 1 — BLE scan & pair
│   │   ├── score_screen.dart            # Screen 2 — Scoreboard remote
│   │   └── history_screen.dart          # Screen 3 — Match history
│   └── widgets/
│       ├── signal_bars.dart             # RSSI signal strength indicator
│       └── score_button.dart            # Animated +1 / undo score button
├── esp32_ble_addon.ino                  # Paste into your Arduino sketch
├── android_AndroidManifest.xml          # BLE permissions for Android
├── ios_Info_plist_additions.xml         # BLE usage strings for iOS
└── pubspec.yaml                         # Flutter dependencies
```

---

## Part 1 — Flutter App Setup

### Prerequisites
- Flutter SDK 3.x installed: https://flutter.dev/docs/get-started/install
- Android Studio or Xcode (for emulator/device deploy)
- A physical device (BLE does not work on emulators)

### Step 1 — Create the Flutter project

```bash
flutter create pickleball_scoreboard
cd pickleball_scoreboard
```

### Step 2 — Replace files

Copy every file from this package into the matching path inside your
new Flutter project. The `lib/` folder contents replace the default ones.

### Step 3 — Install dependencies

```bash
flutter pub get
```

### Step 4 — Android permissions

Replace the content of `android/app/src/main/AndroidManifest.xml`
with the content of `android_AndroidManifest.xml` provided here.

Also open `android/app/build.gradle` and confirm:
```gradle
android {
    compileSdkVersion 34   // must be 31 or higher for BLE
    defaultConfig {
        minSdkVersion 21   // minimum for flutter_blue_plus
        targetSdkVersion 34
    }
}
```

### Step 5 — iOS permissions

Open `ios/Runner/Info.plist` and add the keys from
`ios_Info_plist_additions.xml` inside the root `<dict>`.

In Xcode, also enable the **Background Modes** capability and tick
**Uses Bluetooth LE accessories** if you want the app to maintain
connection when backgrounded.

### Step 6 — Run the app

```bash
# List available devices
flutter devices

# Run on a specific device
flutter run -d <device-id>
```

### Step 7 — Build for release

**Android APK (sideload)**
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

**Android App Bundle (Play Store)**
```bash
flutter build appbundle --release
```

**iOS (App Store / TestFlight)**
```bash
flutter build ipa --release
# Then open Xcode → Product → Archive → Distribute App
```

---

## Part 2 — ESP32 Arduino Sketch Changes

### Required Libraries (install via Arduino Library Manager)
| Library | Author | Purpose |
|---------|--------|---------|
| ESP32 BLE Arduino | Neil Kolban / Espressif | BLE server stack |
| ArduinoJson | Benoit Blanchon | State JSON serialisation |
| Adafruit NeoPixel | Adafruit | Already installed |
| IRremote | Armin Joachimsmeyer | Already installed |

### What changes in the sketch

Only **four things** are added to your existing code:

1. Two new `#include` lines at the top
2. BLE globals and callbacks (before `setup()`)
3. `bleSetup()` call at the end of `setup()`
4. `processCommand()` helper that both IR and BLE call

The complete merged sketch is at the bottom of `esp32_ble_addon.ino`
inside the block comment — copy everything between `/*` and `*/`.

### Uploading
- Board: **ESP32 Dev Module**
- Partition Scheme: **Default 4MB with spiffs** (needed for BLE stack)
- Upload Speed: 115200

> **Important:** BLE requires more flash than the default Arduino
> partition. In Arduino IDE go to:
> Tools → Partition Scheme → **Huge APP (3MB No OTA/1MB SPIFFS)**
> or **Default 4MB with spiffs**. If you see `Sketch too large` errors,
> this is why.

---

## BLE Communication Protocol

### Command characteristic (app → ESP32)
App writes a single byte. Same values as the IR remote codes:

| Action | Byte (hex) | IR equivalent |
|--------|-----------|---------------|
| +1 point | `0x46` | IR_UP |
| −1 undo  | `0x15` | IR_DOWN |
| P1 serves | `0x44` | IR_LEFT |
| P2 serves | `0x43` | IR_RIGHT |
| Reset match | `0x42` | IR_STAR |

### State characteristic (ESP32 → app, notify)
After every command the ESP32 sends a JSON notification:

```json
{"s1":7,"s2":4,"sp1":1,"sp2":0,"sv":1,"go":0}
```

| Key | Value |
|-----|-------|
| `s1` | Player 1 score |
| `s2` | Player 2 score |
| `sp1` | Sets won by P1 |
| `sp2` | Sets won by P2 |
| `sv` | Currently serving (1 or 2) |
| `go` | Game over flag (0 or 1) |

---

## Troubleshooting

**"No devices found" during scan**
- Make sure Bluetooth is on and Location permission is granted (Android)
- The ESP32 must be powered and running the updated sketch
- Try moving closer — BLE range drops quickly through walls

**"Sketch too large" when uploading to ESP32**
- Change partition scheme: Tools → Partition Scheme → Huge APP

**App connects but score buttons do nothing**
- Open Arduino Serial Monitor at 115200 baud
- Check for `[BLE] App connected` message
- Check for `[BLE] Command received: 0x46` etc. when tapping buttons
- If UUIDs do not match between app and sketch, nothing will work —
  copy-paste them; do not retype

**iOS won't scan**
- Info.plist must have the `NSBluetoothAlwaysUsageDescription` key
- On iOS 13+ the user must grant Bluetooth permission at the dialog

**Match history not saving**
- History only saves when a match reaches the win condition (score 11,
  sets to SETS_TO_WIN_MATCH). Partial matches are not recorded.

---

## Customisation

**Change board name** (shows in scan list):
In `esp32_ble_addon.ino` → `BLEDevice::init("PB-ScoreBoard-01");`

**Multiple boards** — give each a unique suffix:
`PB-ScoreBoard-01`, `PB-ScoreBoard-02`, etc.
All will appear in the app's scan list.

**Change win score (e.g. 15 instead of 11)**:
In the ESP32 sketch, change `score1 < 11` and `score1 == 11` to 15.

**Change player names**:
In `score_screen.dart`, search for `'PLAYER 1'` and `'PLAYER 2'`
and replace with your preferred labels (e.g. `'TEAM MANILA'`).
