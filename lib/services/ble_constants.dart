// ---------------------------------------------------------------
//  BLE UUIDs — must match exactly what is defined in the ESP32
//  sketch (ble_scoreboard.ino additions shown in esp32_ble_addon.ino).
// ---------------------------------------------------------------
class BleUuids {
  static const serviceUuid        = '12345678-1234-1234-1234-123456789abc';
  static const commandCharUuid    = '12345678-1234-1234-1234-123456789abd';
  static const stateCharUuid      = '12345678-1234-1234-1234-123456789abe';
  static const deviceNamePrefix   = 'PB-ScoreBoard';
}
// ---------------------------------------------------------------
//  Command bytes — mirror the IR codes in the original ESP32 sketch.
//  The ESP32 reads these from the BLE characteristic and routes them
//  through the same switch-case that handles IR.
// ---------------------------------------------------------------
class BleCommand {
  static const int up        = 0x46;  // IR_UP    — +1 point for the currently SELECTED player
  static const int down      = 0x15;  // IR_DOWN  — −1 point (undo) for the currently SELECTED player
  static const int left      = 0x44;  // IR_LEFT  — Team 1 (Yellow) now selected (serve indicator)
  static const int right     = 0x43;  // IR_RIGHT — Team 2 (Blue) now selected (serve indicator)
  static const int num1      = 0x16;  // IR_NUM1  — Server number 1 (which partner is serving)
  static const int num2      = 0x19;  // IR_NUM2  — Server number 2 (which partner is serving)
  static const int star      = 0x42;  // IR_STAR  — Full match reset
  static const int setTarget = 0x54;  // 2-byte write: [setTarget, value] — sets the winning score for the current set

  // ── Direct per-player scoring — independent of serve ───────────────
  // Unlike `up`/`down`, these score/undo a SPECIFIC player without
  // moving the serve indicator (`selected`) on the board at all. The
  // hardware's LED arrow still moves to reflect who just scored — only
  // the serve/select state stays untouched.
  static const int scoreP1   = 0x60;
  static const int scoreP2   = 0x61;
  static const int undoP1    = 0x62;
  static const int undoP2    = 0x63;
}
// ---------------------------------------------------------------
//  Dynamic scoring defaults — Set 1 plays to 11, Set 2 to 15,
//  Set 3 to 20. Any of these can be overridden with a custom value
//  from the score screen; the override only applies to that one set.
// ---------------------------------------------------------------
class DefaultTargets {
  static const List<int> bySetIndex = [11, 15, 20];
  static int forSetIndex(int setIndex) {
    if (setIndex < 0) return bySetIndex.first;
    if (setIndex >= bySetIndex.length) return bySetIndex.last;
    return bySetIndex[setIndex];
  }
}