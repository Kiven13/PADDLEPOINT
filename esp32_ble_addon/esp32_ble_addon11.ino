#include <Adafruit_NeoPixel.h>
#include <IRremote.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <BLESecurity.h>
#include <ArduinoJson.h>
#include "esp_system.h"
#include "esp_gap_ble_api.h"

// =====================================================================
//  HARDWARE
// =====================================================================
#define LED_PIN              27
#define NUM_LEDS_PER_PANEL   256
#define PANEL_SCORE          0
#define PANEL_SERVE          1

Adafruit_NeoPixel strip(NUM_LEDS_PER_PANEL * 2, LED_PIN, NEO_GRB + NEO_KHZ800);

#define IR_RECEIVE_PIN 33

// ── IR Codes ──────────────────────────────────────────────────────────
#define IR_LEFT  0x44
#define IR_RIGHT 0x43
#define IR_UP    0x46
#define IR_DOWN  0x15
#define IR_STAR  0x42
#define IR_NUM1  0x16
#define IR_NUM2  0x19

// ── Dynamic scoring: app sends [CMD_SET_TARGET, value] as a 2-byte
//    write to set how many points win the CURRENT set (11 / 15 / 20 /
//    custom). This is a different code path from the single-byte IR
//    command bytes above. ──────────────────────────────────────────
#define CMD_SET_TARGET 0x54

// ── Direct per-player scoring (BLE app only): these add/undo a point for
//    a SPECIFIC player without touching `selected` (the serve indicator).
//    Unlike IR_UP/IR_DOWN, which act on whichever team is `selected`,
//    these let the app's per-player score buttons work independently of
//    who is currently marked as serving. The arrow (arrowTeam) still
//    moves to reflect who just scored — only `selected`/serve stays put.
#define CMD_SCORE_P1 0x60
#define CMD_SCORE_P2 0x61
#define CMD_UNDO_P1  0x62
#define CMD_UNDO_P2  0x63

// ── Colors ────────────────────────────────────────────────────────────
#define COL_P1       strip.Color(255, 200, 0)
#define COL_P2       strip.Color(0, 150, 255)
#define COL_IND      strip.Color(255, 255, 255)
#define COL_SET_NUM  strip.Color(180, 180, 180)
#define COL_PIN      strip.Color(255, 60, 220)
#define COL_ID       strip.Color(120, 255, 120)

// ── Game State ────────────────────────────────────────────────────────
int  score1    = 0;
int  score2    = 0;
int  setsWonP1 = 0;
int  setsWonP2 = 0;
int  selected  = 1;     // which TEAM is currently selected to receive the next point (1 = yellow, 2 = blue)
int  arrowTeam = 1;     // which team's LED arrow is lit — follows whoever last SCORED, independent of `selected`
int  serverNum = 1;     // which PARTNER (1 or 2) on that team is serving
bool gameOver  = false;

// Dynamic scoring: how many points win the CURRENT set. Defaults follow
// the standard progression (Set 1 = 11, Set 2 = 15, Set 3 = 20), but the
// app can override this at any time — including to a custom value — via
// CMD_SET_TARGET.
int targetScore = 11;

const int SETS_TO_WIN_MATCH = 2;

// ── BLE UUIDs — must match ble_constants.dart in the Flutter app ──────
#define BLE_SERVICE_UUID    "12345678-1234-1234-1234-123456789abc"
#define BLE_CMD_CHAR_UUID   "12345678-1234-1234-1234-123456789abd"
#define BLE_STATE_CHAR_UUID "12345678-1234-1234-1234-123456789abe"

BLEServer*         pServer       = nullptr;
BLECharacteristic* pCmdChar      = nullptr;
BLECharacteristic* pStateChar    = nullptr;
bool               bleConnected  = false;
volatile uint8_t   blePendingCmd = 0;

// =====================================================================
//  BOARD IDENTITY  (fixes: "which board am I actually connecting to?")
//  A short 4-digit ID derived from the chip's own MAC address, so it's
//  stable across reboots but unique per physical board. It is:
//    1. Appended to the advertised BLE name  ("PB-ScoreBoard-3821")
//    2. Flashed on the LED score panel at boot
//  The person compares the number on the LED panel to the number shown
//  in the app's scan list before tapping Connect.
// =====================================================================
char boardIdStr[5] = "0000";   // 4 decimal digits
char bleDeviceName[32];

void deriveBoardId() {
  uint64_t chipId = ESP.getEfuseMac();  // built-in Arduino-ESP32 core, no extra headers
  uint16_t id = (uint16_t)(chipId % 10000);
  snprintf(boardIdStr, sizeof(boardIdStr), "%04u", id);
  snprintf(bleDeviceName, sizeof(bleDeviceName), "PB-ScoreBoard-%s", boardIdStr);
}

// =====================================================================
//  BLE PAIRING PIN  (fixes: "stop strangers from connecting at all")
//  With IO capability ESP_IO_CAP_OUT (display-only), the ESP-IDF BLE
//  stack generates its OWN random 6-digit passkey internally the moment
//  a phone starts pairing — it does not use any value we pick in
//  advance. We find out what it is via onPassKeyNotify(), and must show
//  that exact number on the LED panel in real time, right as pairing
//  begins, not before.
// =====================================================================
volatile bool pairingInProgress = false;

// =====================================================================
//  LED INDEX HELPERS
// =====================================================================
int idx(int col, int row) {
  return (col % 2 == 0) ? col * 8 + row : col * 8 + (7 - row);
}

int ledIndex(int panel, int col, int row) {
  return panel * NUM_LEDS_PER_PANEL + idx(col, row);
}

int ledIndexServe(int col, int row) {
  return ledIndex(PANEL_SERVE, (31 - col), (7 - row));
}

void clearPanel(int panel) {
  strip.fill(0, panel * NUM_LEDS_PER_PANEL, NUM_LEDS_PER_PANEL);
}

void fillPanel(int panel, uint32_t color) {
  strip.fill(color, panel * NUM_LEDS_PER_PANEL, NUM_LEDS_PER_PANEL);
}

// =====================================================================
//  5x7 FONT
// =====================================================================
const uint8_t FONT5X7[10][5] = {
  { 0x3E, 0x51, 0x49, 0x45, 0x3E }, // 0
  { 0x00, 0x42, 0x7F, 0x40, 0x00 }, // 1
  { 0x42, 0x61, 0x51, 0x49, 0x46 }, // 2
  { 0x21, 0x41, 0x45, 0x4B, 0x31 }, // 3
  { 0x18, 0x14, 0x12, 0x7F, 0x10 }, // 4
  { 0x27, 0x45, 0x45, 0x45, 0x39 }, // 5
  { 0x3C, 0x4A, 0x49, 0x49, 0x30 }, // 6
  { 0x01, 0x71, 0x09, 0x05, 0x03 }, // 7
  { 0x36, 0x49, 0x49, 0x49, 0x36 }, // 8
  { 0x06, 0x49, 0x49, 0x29, 0x1E }, // 9
};

void drawDigit(int panel, int digit, int xOffset, uint32_t color) {
  if (digit < 0 || digit > 9) return;
  for (int col = 0; col < 5; col++) {
    uint8_t colBits = FONT5X7[digit][col];
    for (int row = 0; row < 7; row++) {
      if (colBits & (1 << row)) {
        strip.setPixelColor(
          panel == PANEL_SERVE
            ? ledIndexServe(xOffset + col, row)
            : ledIndex(panel, xOffset + col, row),
          color
        );
      }
    }
  }
}

// =====================================================================
//  COMPACT 3x5 FONT — used only for the small server-number indicator
//  (index 0 is an unused placeholder so digit 1 and 2 line up with their
//  own array index)
// =====================================================================
const uint8_t FONT3X5[3][3] = {
  { 0x00, 0x00, 0x00 }, // 0 (unused)
  { 0x12, 0x1F, 0x10 }, // 1
  { 0x1D, 0x15, 0x17 }, // 2
};

void drawSmallDigit(int panel, int digit, int xOffset, int yOffset, uint32_t color) {
  if (digit < 1 || digit > 2) return;
  for (int col = 0; col < 3; col++) {
    uint8_t colBits = FONT3X5[digit][col];
    for (int row = 0; row < 5; row++) {
      if (colBits & (1 << row)) {
        strip.setPixelColor(
          panel == PANEL_SERVE
            ? ledIndexServe(xOffset + col, yOffset + row)
            : ledIndex(panel, xOffset + col, yOffset + row),
          color
        );
      }
    }
  }
}

void drawScore(int score, int xStart, uint32_t color) {
  drawDigit(PANEL_SCORE, score / 10, xStart,     color);
  drawDigit(PANEL_SCORE, score % 10, xStart + 6, color);
}

void drawDivider(int col, uint32_t color) {
  for (int row = 0; row <= 7; row++) {
    strip.setPixelColor(ledIndex(PANEL_SCORE, col, row), color);
  }
}

// =====================================================================
//  CHEVRON (SERVE ARROWS)
// =====================================================================
void drawChevron(int xStart, bool pointLeft, uint32_t color) {
  for (int row = 0; row < 8; row++) {
    int dist = (row <= 3) ? (3 - row) : (row - 4);
    int col  = pointLeft ? (xStart + dist) : (xStart + (3 - dist));
    strip.setPixelColor(ledIndexServe(col, row), color);
  }
}

void drawDoubleChevronLeft(int xStart, uint32_t color) {
  drawChevron(xStart,     true, color);
  drawChevron(xStart + 6, true, color);
}

void drawDoubleChevronRight(int xStart, uint32_t color) {
  drawChevron(xStart,     false, color);
  drawChevron(xStart + 6, false, color);
}

// =====================================================================
//  BOARD ID / PIN DISPLAY  (shown at boot, before normal score display)
// =====================================================================
void showFourDigitsOnBothPanels(const char* fourDigits, uint32_t color) {
  clearPanel(PANEL_SCORE);
  clearPanel(PANEL_SERVE);
  // 4 digits x 5px wide + 3 gaps x 1px = 23px total; center on the
  // 32-column panel: (32 - 23) / 2 = 4.
  int xStart = 4;
  for (int i = 0; i < 4; i++) {
    int d = fourDigits[i] - '0';
    drawDigit(PANEL_SCORE, d, xStart, color);
    drawDigit(PANEL_SERVE, d, xStart, color);
    xStart += 6;
  }
  strip.show();
}

// Shows the board's 4-digit ID once at boot, so the person can confirm
// they're picking the right board in the app before attempting to pair.
void showBoardIdOnBoot() {
  showFourDigitsOnBothPanels(boardIdStr, COL_ID);
  Serial.print("[ID] Board ID: ");
  Serial.println(boardIdStr);
  delay(3000);
  clearPanel(PANEL_SCORE);
  clearPanel(PANEL_SERVE);
  strip.show();
}

// Shows the REAL passkey the moment the BLE stack generates it (during
// an actual pairing attempt) — all 6 digits fit on ONE 32-column panel
// (the score panel) using tight 5px-per-digit spacing (6 digits x 5px =
// 30px, fits within the 32-wide panel). The serve panel stays blank so
// there's a single, unambiguous place to read the PIN from.
void showPasskeyLive(uint32_t passKey) {
  char pinStr[7];
  snprintf(pinStr, sizeof(pinStr), "%06u", passKey);

  clearPanel(PANEL_SCORE);
  clearPanel(PANEL_SERVE);

  int xStart = 1;
  for (int i = 0; i < 6; i++) {
    drawDigit(PANEL_SCORE, pinStr[i] - '0', xStart, COL_PIN);
    xStart += 5;   // tight spacing — no 1px gap between digits
  }
  strip.show();
}

// =====================================================================
//  DISPLAY REFRESH
// =====================================================================
void updateScoreDisplay() {
  clearPanel(PANEL_SCORE);
  drawScore(score1, 1, COL_P1);

  // Server indicator digit (1 or 2) — which partner on the serving team
  // is serving. Color still reflects which team is currently selected.
  uint32_t serverColor = (selected == 1) ? COL_P1 : COL_P2;
  drawSmallDigit(PANEL_SCORE, serverNum, 14, 1, serverColor);

  drawScore(score2, 20, COL_P2);
  strip.show();
}

void updateServeDisplay() {
  clearPanel(PANEL_SERVE);

  // Arrow follows whoever last SCORED (arrowTeam), not the team
  // currently selected via Left/Right (selected).
  if (arrowTeam == 1) drawDoubleChevronLeft(0, COL_P1);
  else                drawDoubleChevronRight(21, COL_P2);

  // Show the CURRENT set number (1, 2, 3) rather than the count of
  // completed sets (0, 1, 2). Once the match is over, hold at 3 rather
  // than incrementing past the max.
  int totalSetsCompleted = setsWonP1 + setsWonP2;
  int currentSetNumber   = totalSetsCompleted + 1;
  if (currentSetNumber > 3) currentSetNumber = 3;
  drawDigit(PANEL_SERVE, currentSetNumber, 13, COL_SET_NUM);
  strip.show();
}

void updateDisplay() {
  updateScoreDisplay();
  updateServeDisplay();
}

void flashWin(uint32_t color, bool isMatchWin) {
  int cycles = isMatchWin ? 10 : 4;
  int onTime = isMatchWin ? 150 : 200;
  for (int i = 0; i < cycles; i++) {
    fillPanel(PANEL_SERVE, color); strip.show(); delay(onTime);
    clearPanel(PANEL_SERVE);       strip.show(); delay(onTime);
  }
}

// =====================================================================
//  GAME RESET HELPERS
// =====================================================================
void resetSet() {
  score1 = 0;
  score2 = 0;
}

void resetMatch() {
  score1    = 0;
  score2    = 0;
  setsWonP1 = 0;
  setsWonP2 = 0;
  selected  = 1;
  arrowTeam = 1;
  serverNum = 1;
  gameOver  = false;
  targetScore = 11;   // back to the Set 1 default
}

// =====================================================================
//  BLE — FORWARD DECLARATION
// =====================================================================
void blePushState();

// =====================================================================
//  BLE — SECURITY CALLBACKS  (handles the PIN-entry pairing flow)
// =====================================================================
class SecurityCallbacks : public BLESecurityCallbacks {
  // Not used for IO_CAP_OUT (display-only) — this device never needs to
  // accept keyboard input, only display a number. Kept only because the
  // base class requires an implementation.
  uint32_t onPassKeyRequest() override {
    return 0;
  }
  // This is where the REAL passkey shows up. The BLE stack generates it
  // internally the moment a phone starts pairing, and hands it to us
  // here — we must display it right now, not before.
  void onPassKeyNotify(uint32_t pass_key) override {
    Serial.print("[BLE] Passkey — enter this on your phone: ");
    Serial.println(pass_key);
    pairingInProgress = true;
    showPasskeyLive(pass_key);
  }
  bool onConfirmPIN(uint32_t pass_key) override {
    return true;
  }
  bool onSecurityRequest() override {
    return true;
  }
  void onAuthenticationComplete(esp_ble_auth_cmpl_t auth_cmpl) override {
    pairingInProgress = false;
    if (auth_cmpl.success) {
      Serial.println("[BLE] Pairing SUCCESS — app authenticated");
    } else {
      Serial.print("[BLE] Pairing FAILED, reason: ");
      Serial.println(auth_cmpl.fail_reason);

      // Force the link down on a failed pairing. Without this the GATT
      // connection can stay alive even though auth failed, so a retry
      // just resumes the stale link instead of starting a fresh pairing
      // handshake — and the passkey is only regenerated at the start of
      // a fresh handshake. This is why no new PIN appeared.
      esp_ble_gap_disconnect(auth_cmpl.bd_addr);
    }
    updateDisplay();
  }
};

// =====================================================================
//  BLE — SERVER CALLBACKS (connect / disconnect)
// =====================================================================
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* s) override {
    bleConnected = true;
    Serial.println("[BLE] App connected");
    blePushState();  // immediately sync app with current board state
  }
  void onDisconnect(BLEServer* s) override {
    bleConnected = false;
    Serial.println("[BLE] App disconnected — clearing bond, restarting advertising");

    // Belt-and-suspenders: even though bonding is disabled above, wipe
    // any bond record the stack may still be holding, so a returning
    // phone can never skip the PIN prompt.
    int bondedCount = esp_ble_get_bond_device_num();
    if (bondedCount > 0) {
      esp_ble_bond_dev_t bondedDevices[bondedCount];
      esp_ble_get_bond_device_list(&bondedCount, bondedDevices);
      for (int i = 0; i < bondedCount; i++) {
        esp_ble_remove_bond_device(bondedDevices[i].bd_addr);
      }
      Serial.print("[BLE] Cleared ");
      Serial.print(bondedCount);
      Serial.println(" bond record(s)");
    }

    BLEDevice::startAdvertising();
  }
};

// =====================================================================
//  BLE — COMMAND CHARACTERISTIC CALLBACK (app → ESP32)
// =====================================================================
class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) override {
    String val = pChar->getValue();

    // 2-byte dynamic-scoring command: [CMD_SET_TARGET, targetValue]
    if (val.length() >= 2 && (uint8_t)val[0] == CMD_SET_TARGET) {
      uint8_t t = (uint8_t)val[1];
      if (t >= 1) {
        targetScore = t;
        Serial.print("[BLE] Target score set to: ");
        Serial.println(targetScore);
      }
      return;
    }

    // Normal 1-byte IR-style command
    if (val.length() > 0) {
      blePendingCmd = (uint8_t)val[0];
      Serial.print("[BLE] Command received: 0x");
      Serial.println(blePendingCmd, HEX);
    }
  }
};

// =====================================================================
//  BLE — PUSH STATE TO APP (ESP32 → app, notify)
//  JSON: {"s1":7,"s2":4,"sp1":1,"sp2":0,"sv":1,"go":0}
// =====================================================================
void blePushState() {
  if (!bleConnected || pStateChar == nullptr) return;

  StaticJsonDocument<128> doc;
  doc["s1"]  = score1;
  doc["s2"]  = score2;
  doc["sp1"] = setsWonP1;
  doc["sp2"] = setsWonP2;
  doc["sv"]  = selected;
  doc["go"]  = gameOver ? 1 : 0;
  doc["tg"]  = targetScore;

  char buf[128];
  serializeJson(doc, buf);

  pStateChar->setValue(buf);
  pStateChar->notify();

  Serial.print("[BLE] State pushed: ");
  Serial.println(buf);
}

// =====================================================================
//  BLE — INITIALISE SERVER + CHARACTERISTICS + ADVERTISING + SECURITY
// =====================================================================
void bleSetup() {
  deriveBoardId();

  BLEDevice::init(bleDeviceName);

  // ── Security: require MITM-protected bonding with a passkey ────────
  // IO capability "DISPLAY_ONLY" tells the phone: "the peripheral will
  // show you a number, type/confirm it on your phone." This is what
  // produces the system pairing dialog on Android/iOS.
  BLEDevice::setSecurityCallbacks(new SecurityCallbacks());

  BLESecurity* pSecurity = new BLESecurity();
  // NOTE: deliberately using SC_MITM WITHOUT the _BOND flag. Bonding
  // would let the phone and board remember each other's keys, so after
  // the first successful pairing, later connections would skip the PIN
  // entirely. Without bonding, encryption keys are discarded the moment
  // the link drops — every single connection (even from the same phone)
  // re-runs the full pairing handshake and asks for a fresh PIN.
  pSecurity->setAuthenticationMode(ESP_LE_AUTH_REQ_SC_MITM);
  pSecurity->setCapability(ESP_IO_CAP_OUT);   // display-only (shows passkey)
  pSecurity->setInitEncryptionKey(ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK);
  pSecurity->setRespEncryptionKey(ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK);

  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService* pService = pServer->createService(BLE_SERVICE_UUID);

  // Command characteristic — app writes one byte here. Requires an
  // encrypted, authenticated (bonded) link before writes are accepted.
  pCmdChar = pService->createCharacteristic(
    BLE_CMD_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pCmdChar->setCallbacks(new CommandCallbacks());
  pCmdChar->setAccessPermissions(ESP_GATT_PERM_WRITE_ENCRYPTED | ESP_GATT_PERM_WRITE_ENC_MITM);

  // State characteristic — ESP32 notifies app after every change.
  // Also requires an authenticated link to read/subscribe.
  pStateChar = pService->createCharacteristic(
    BLE_STATE_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pStateChar->setAccessPermissions(ESP_GATT_PERM_READ_ENCRYPTED | ESP_GATT_PERM_READ_ENC_MITM);
  pStateChar->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising* pAdv = BLEDevice::getAdvertising();
  pAdv->addServiceUUID(BLE_SERVICE_UUID);
  pAdv->setScanResponse(true);
  pAdv->setMinPreferred(0x06);
  pAdv->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.print("[BLE] Ready — advertising as '");
  Serial.print(bleDeviceName);
  Serial.println("'");
}

// =====================================================================
//  AWARD / UNDO A POINT FOR A SPECIFIC TEAM
//  Shared by the IR_UP/IR_DOWN path (which acts on `selected`) and the
//  new direct per-player BLE commands (which act on an explicit team
//  and never touch `selected`). Handles score increment, arrow update,
//  set/match win detection, display, and BLE push.
// =====================================================================
void awardPoint(int team) {
  if (team == 1) score1++;
  if (team == 2) score2++;
  arrowTeam = team;   // arrow follows whoever just scored

  int setWinner = 0;
  if (score1 >= targetScore && (score1 - score2) >= 2) setWinner = 1;
  if (score2 >= targetScore && (score2 - score1) >= 2) setWinner = 2;

  if (setWinner != 0) {
    uint32_t setColor = (setWinner == 1)
      ? strip.Color(255, 200, 0)
      : strip.Color(0, 150, 255);

    if (setWinner == 1) setsWonP1++;
    else                setsWonP2++;

    bool isMatchWin = (setsWonP1 >= SETS_TO_WIN_MATCH) ||
                      (setsWonP2 >= SETS_TO_WIN_MATCH);

    Serial.print("Player ");
    Serial.print(setWinner);
    Serial.println(isMatchWin ? " WINS THE MATCH!" : " wins the set!");

    updateDisplay();
    blePushState();            // notify app: set/match just ended
    flashWin(setColor, isMatchWin);

    if (isMatchWin) {
      gameOver = true;
      fillPanel(PANEL_SERVE, setColor);
      strip.show();
    } else {
      resetSet();
      updateDisplay();
    }

    blePushState();            // push final state after reset
    return;
  }

  updateDisplay();
  blePushState();
}

void undoPointForTeam(int team) {
  if (team == 1 && score1 > 0) score1--;
  if (team == 2 && score2 > 0) score2--;
  arrowTeam = team;   // arrow follows whoever's point was just undone
  updateDisplay();
  blePushState();
}

// =====================================================================
//  UNIFIED COMMAND PROCESSOR
//  Called by BOTH the IR remote path and the BLE app path.
//  Behaviour is 100% identical regardless of which input triggered it.
// =====================================================================
void processCommand(uint8_t cmd) {

  if (cmd == IR_STAR) {
    resetMatch();
    Serial.println("RESET (full match)");
    updateDisplay();   // redraw arrow + set number instead of leaving PANEL_SERVE blank
    blePushState();
    return;

  } else if (!gameOver) {

    switch (cmd) {

      case IR_LEFT:
        selected = 1;
        arrowTeam = 1;
        Serial.println("Selected team: Yellow (P1)");
        break;

      case IR_RIGHT:
        selected = 2;
        arrowTeam = 2;
        Serial.println("Selected team: Blue (P2)");
        break;

      case IR_NUM1:
        serverNum = 1;
        Serial.println("Server number: 1");
        break;

      case IR_NUM2:
        serverNum = 2;
        Serial.println("Server number: 2");
        break;

      case IR_UP:
        awardPoint(selected);
        return;   // awardPoint already did display+blePushState

      case IR_DOWN:
        undoPointForTeam(selected);
        return;   // undoPointForTeam already did display+blePushState

      // ── Direct per-player scoring (BLE app only) ──────────────────
      // Scores/undoes a specific team WITHOUT touching `selected`, so
      // the serve indicator never moves just because someone scored.
      case CMD_SCORE_P1:
        awardPoint(1);
        return;

      case CMD_SCORE_P2:
        awardPoint(2);
        return;

      case CMD_UNDO_P1:
        undoPointForTeam(1);
        return;

      case CMD_UNDO_P2:
        undoPointForTeam(2);
        return;
    }
  }

  updateDisplay();
  blePushState();   // notify app after every non-scoring command (select/server-num)

  Serial.print("P1: ");    Serial.print(score1);
  Serial.print(" | P2: "); Serial.print(score2);
  Serial.print(" | Sets P1: "); Serial.print(setsWonP1);
  Serial.print(" | Sets P2: "); Serial.println(setsWonP2);
}

// =====================================================================
//  SETUP
// =====================================================================
void setup() {
  Serial.begin(115200);

  strip.begin();
  strip.setBrightness(40);
  strip.clear();
  strip.show();

  IrReceiver.begin(IR_RECEIVE_PIN, ENABLE_LED_FEEDBACK);

  bleSetup();  // derives board ID, starts advertising with security

  showBoardIdOnBoot();  // flash board ID on the LEDs so the app-side ID can be matched

  updateDisplay();

  Serial.println("Ready! IR remote + BLE app both active.");
}

// =====================================================================
//  LOOP
// =====================================================================
void loop() {

  // ── BLE path: process any command queued by the app ─────────────────
  if (blePendingCmd != 0) {
    uint8_t cmd  = blePendingCmd;
    blePendingCmd = 0;           // clear queue before processing
    processCommand(cmd);
  }

  // ── IR path: unchanged behaviour ────────────────────────────────────
  if (IrReceiver.decode()) {
    if (!(IrReceiver.decodedIRData.flags & IRDATA_FLAGS_IS_REPEAT)) {
      processCommand(IrReceiver.decodedIRData.command);
    }
    IrReceiver.resume();
  }
}
