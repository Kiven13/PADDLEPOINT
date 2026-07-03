#include <Adafruit_NeoPixel.h>
#include <IRremote.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>

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

// ── Colors ────────────────────────────────────────────────────────────
#define COL_P1       strip.Color(255, 200, 0)
#define COL_P2       strip.Color(0, 150, 255)
#define COL_IND      strip.Color(255, 255, 255)
#define COL_SET_NUM  strip.Color(180, 180, 180)

// ── Game State ────────────────────────────────────────────────────────
int  score1    = 0;
int  score2    = 0;
int  setsWonP1 = 0;
int  setsWonP2 = 0;
int  selected  = 1;     // which TEAM is currently serving (1 = yellow, 2 = blue)
int  serverNum = 1;     // which PARTNER (1 or 2) on that team is serving
bool gameOver  = false;

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
//  DISPLAY REFRESH
// =====================================================================
void updateScoreDisplay() {
  clearPanel(PANEL_SCORE);
  drawScore(score1, 1, COL_P1);

  // Divider mark between P1's score and the server number
  //drawDivider(12, COL_IND);
  //drawDivider(13, COL_IND);
  // Server indicator digit (1 or 2) — which partner on the serving team
  // is serving. Color still reflects which team is currently serving.
  uint32_t serverColor = (selected == 1) ? COL_P1 : COL_P2;
  drawSmallDigit(PANEL_SCORE, serverNum, 14, 1, serverColor);

  // Divider mark between the server number and P2's score
  //drawDivider(19, COL_IND);
  //drawDivider(18, COL_IND);
  drawScore(score2, 20, COL_P2);
  strip.show();
}

void updateServeDisplay() {
  clearPanel(PANEL_SERVE);
  if (selected == 1) drawDoubleChevronLeft(0, COL_P1);
  else               drawDoubleChevronRight(21, COL_P2);

  int totalSets = setsWonP1 + setsWonP2;
  drawDigit(PANEL_SERVE, totalSets, 13, COL_SET_NUM);
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
  serverNum = 1;
  gameOver  = false;
}

// =====================================================================
//  BLE — FORWARD DECLARATION
// =====================================================================
void blePushState();

// ===================================================================== h
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
    Serial.println("[BLE] App disconnected — restarting advertising");
    BLEDevice::startAdvertising();
  }
};
 
// =====================================================================
//  BLE — COMMAND CHARACTERISTIC CALLBACK (app → ESP32)
// =====================================================================
class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) override {
    String val = pChar->getValue();
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

  char buf[128];
  serializeJson(doc, buf);

  pStateChar->setValue(buf);
  pStateChar->notify();

  Serial.print("[BLE] State pushed: ");
  Serial.println(buf);
}

// =====================================================================
//  BLE — INITIALISE SERVER + CHARACTERISTICS + ADVERTISING
// =====================================================================
void bleSetup() {
  BLEDevice::init("PB-ScoreBoard-01");

  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService* pService = pServer->createService(BLE_SERVICE_UUID);

  // Command characteristic — app writes one byte here
  pCmdChar = pService->createCharacteristic(
    BLE_CMD_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pCmdChar->setCallbacks(new CommandCallbacks());

  // State characteristic — ESP32 notifies app after every change
  pStateChar = pService->createCharacteristic(
    BLE_STATE_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pStateChar->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising* pAdv = BLEDevice::getAdvertising();
  pAdv->addServiceUUID(BLE_SERVICE_UUID);
  pAdv->setScanResponse(true);
  pAdv->setMinPreferred(0x06);
  pAdv->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("[BLE] Ready — advertising as 'PB-ScoreBoard-01'");
}

// =====================================================================
//  UNIFIED COMMAND PROCESSOR
//  Called by BOTH the IR remote path and the BLE app path.
//  Behaviour is 100% identical regardless of which input triggered it.
// =====================================================================
void processCommand(uint8_t cmd) {

  if (cmd == IR_STAR) {
    resetMatch();
    clearPanel(PANEL_SERVE);
    strip.show();
    Serial.println("RESET (full match)");

  } else if (!gameOver) {

    switch (cmd) {

      case IR_LEFT:
        selected = 1;
        Serial.println("Serving team: Yellow (P1)");
        break;

      case IR_RIGHT:
        selected = 2;
        Serial.println("Serving team: Blue (P2)");
        break;

      case IR_NUM1:
        serverNum = 1;
        Serial.println("Server number: 1");
        break;

      case IR_NUM2:
        serverNum = 2;
        Serial.println("Server number: 2");
        break;

      case IR_UP: {
        if (selected == 1) score1++;
        if (selected == 2) score2++;

        int setWinner = 0;
        if (score1 >= 11 && (score1 - score2) >= 2) setWinner = 1;
        if (score2 >= 11 && (score2 - score1) >= 2) setWinner = 2;

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
          return;                    // skip the updateDisplay at the bottom
        }
        break;
      }

      case IR_DOWN:
        if (selected == 1 && score1 > 0) score1--;
        if (selected == 2 && score2 > 0) score2--;
        break;
    }
  }

  updateDisplay();
  blePushState();   // notify app after every non-set-win command

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

  updateDisplay();

  Serial.println("Ready! IR remote + BLE app both active.");

  bleSetup();  // start BLE advertising
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
