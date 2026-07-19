import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_constants.dart';

enum BleStatus { off, scanning, connecting, connected, disconnected, error }

// Distinguishes *why* a connection attempt failed, so the UI can react
// differently to a wrong PIN (show a retry dialog, stay put) than to a
// timeout or unknown error (generic message). The ESP32 doesn't send an
// explicit "bad PIN" signal — it just drops the link mid-handshake — so
// this is inferred rather than read directly off the wire.
enum BleFailureReason { none, wrongPin, timeout, unknown }

class BleService extends ChangeNotifier {
  // ── Public state ──────────────────────────────────────────────
  BleStatus status = BleStatus.disconnected;
  List<ScanResult> scanResults = [];
  BluetoothDevice? connectedDevice;
  String? errorMessage;
  BleFailureReason failureReason = BleFailureReason.none;

  // Live scoreboard state pushed from ESP32 notify characteristic
  int score1   = 0;
  int score2   = 0;
  int setsP1   = 0;
  int setsP2   = 0;
  int serving  = 1;   // 1 or 2
  bool gameOver = false;
  int targetScore = 11;   // points needed to win the current set

  // ── Private ───────────────────────────────────────────────────
  BluetoothCharacteristic? _commandChar;
  BluetoothCharacteristic? _stateChar;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _notifySub;

  // ─────────────────────────────────────────────────────────────
  //  SCANNING
  // ─────────────────────────────────────────────────────────────
  Future<void> startScan() async {
    if (status == BleStatus.scanning) return;

    scanResults = [];
    status = BleStatus.scanning;
    notifyListeners();

    await FlutterBluePlus.stopScan();

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      // Only show devices whose advertised name starts with our prefix
      scanResults = results
          .where((r) => r.device.platformName
              .startsWith(BleUuids.deviceNamePrefix))
          .toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi)); // strongest first
      notifyListeners();
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      androidUsesFineLocation: false,
    );

    await Future.delayed(const Duration(seconds: 10));
    _scanSub?.cancel();
    if (status == BleStatus.scanning) {
      status = BleStatus.disconnected;
      notifyListeners();
    }
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    if (status == BleStatus.scanning) {
      status = BleStatus.disconnected;
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  CONNECTING
  // ─────────────────────────────────────────────────────────────
  Future<void> connectTo(BluetoothDevice device) async {
    stopScan();
    status = BleStatus.connecting;
    errorMessage = null;
    failureReason = BleFailureReason.none;
    notifyListeners();

    // Force a clean slate before (re)connecting. A prior failed attempt
    // (e.g. wrong PIN) only ever called removeBond() — never
    // disconnect() — so the BLE *link* itself can still be up at the OS
    // level even though we already surfaced an error to the user. If the
    // link is still alive, device.connect() below can resolve almost
    // instantly without ever re-triggering pairing, the ESP32 (which
    // only rotates its PIN on an actual disconnect event) never
    // generates a new one, and createBond() below can hang indefinitely
    // waiting on a pairing flow the OS thinks is unnecessary — which is
    // exactly the "stuck on Connecting…" symptom after tapping Try Again.
    try {
      await device.disconnect();
    } catch (e) {
      debugPrint('BLE disconnect (pre-connect) skipped: $e');
    }
    // Give the OS a beat to finish tearing down the link/bond state
    // before asking it to reconnect — doing this back-to-back on some
    // Android versions races the teardown and the new connect silently
    // reuses stale state instead of starting fresh.
    await Future.delayed(const Duration(milliseconds: 300));

    // Tracks whether we ever made it all the way to `connected`. With
    // SC_MITM + no bonding, a wrong PIN doesn't come back as a distinct
    // error — the ESP32 just drops the link mid-handshake. So: if the
    // connection drops before we've finished connecting, that's the
    // signature of a failed pairing attempt (almost always a wrong PIN),
    // as opposed to a normal disconnect after we were already connected.
    bool reachedConnected = false;

    try {
      // The ESP32 wipes its own bond record on every disconnect (see
      // firmware), but the PHONE keeps its bond record independently —
      // clearing one side doesn't clear the other. Without this step,
      // the second+ connect attempt has the phone silently try to reuse
      // a key the board no longer recognizes, which fails the encryption
      // handshake and just disconnects instead of prompting a new PIN.
      // Removing the phone-side bond here forces a genuinely fresh
      // pairing exchange (and a new PIN) on every single connect.
      if (Platform.isAndroid) {
        try {
          await device.removeBond();
        } catch (e) {
          // Fails harmlessly if there was nothing bonded yet (e.g. very
          // first connect ever to this board) — safe to ignore.
          debugPrint('BLE removeBond (pre-connect) skipped: $e');
        }
      }

      await device.connect(timeout: const Duration(seconds: 10));
      connectedDevice = device;

      _connSub?.cancel();
      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          if (!reachedConnected) {
            failureReason = BleFailureReason.wrongPin;
            errorMessage = 'Incorrect PIN. Please try again.';
            status = BleStatus.error;
            notifyListeners();
          } else {
            _handleDisconnect();
          }
        }
      });

      // Proactively kick off pairing right away, rather than waiting for
      // the first encrypted characteristic access to trigger it — more
      // reliable timing on some Android versions.
      if (Platform.isAndroid) {
        try {
          await device.createBond().timeout(const Duration(seconds: 15));
        } on TimeoutException {
          // createBond() never resolved — almost always because the OS
          // still thinks a bond/link exists from a previous attempt and
          // silently declined to start a fresh pairing flow. Treat this
          // the same as a wrong PIN so the user gets a live retry
          // instead of a frozen "Connecting…" screen.
          debugPrint('BLE createBond timed out');
          failureReason = BleFailureReason.wrongPin;
          errorMessage = 'Incorrect PIN. Please try again.';
          status = BleStatus.error;
          notifyListeners();
          return;
        } catch (e) {
          debugPrint('BLE createBond error: $e');
          failureReason = BleFailureReason.wrongPin;
          errorMessage = 'Incorrect PIN. Please try again.';
          status = BleStatus.error;
          notifyListeners();
          return;
        }
      }

      await _discoverServices(device);
      reachedConnected = true;
      status = BleStatus.connected;
      notifyListeners();
    } on TimeoutException {
      failureReason = BleFailureReason.timeout;
      errorMessage = 'Could not find the board. Move closer and try again.';
      status = BleStatus.error;
      notifyListeners();
    } catch (e) {
      // Reading/writing the encrypted characteristics during service
      // discovery fails with an "insufficient authentication"-style
      // error when pairing didn't actually complete — same root cause
      // as a wrong PIN (especially common on iOS, where the system
      // pairing sheet is triggered here rather than by createBond()),
      // just surfaced at a different step.
      final msg = e.toString().toLowerCase();
      if (msg.contains('auth') || msg.contains('encrypt') || msg.contains('bond')) {
        failureReason = BleFailureReason.wrongPin;
        errorMessage = 'Incorrect PIN. Please try again.';
      } else {
        failureReason = BleFailureReason.unknown;
        errorMessage = 'Could not connect: ${e.toString()}';
      }
      status = BleStatus.error;
      notifyListeners();
    }
  }

  Future<void> _discoverServices(BluetoothDevice device) async {
    final services = await device.discoverServices();
    for (final svc in services) {
      if (svc.uuid.toString().toLowerCase() ==
          BleUuids.serviceUuid.toLowerCase()) {
        for (final char in svc.characteristics) {
          final uuid = char.uuid.toString().toLowerCase();
          if (uuid == BleUuids.commandCharUuid.toLowerCase()) {
            _commandChar = char;
          } else if (uuid == BleUuids.stateCharUuid.toLowerCase()) {
            _stateChar = char;
            // Subscribe to ESP32 state notifications
            await char.setNotifyValue(true);
            _notifySub?.cancel();
            _notifySub = char.onValueReceived.listen(_onStateNotify);
          }
        }
        break;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  STATE NOTIFICATIONS FROM ESP32
  //  ESP32 sends a compact JSON: {"s1":7,"s2":4,"sp1":1,"sp2":0,"sv":1,"go":0}
  // ─────────────────────────────────────────────────────────────
  void _onStateNotify(List<int> bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      score1   = json['s1']  as int? ?? score1;
      score2   = json['s2']  as int? ?? score2;
      setsP1   = json['sp1'] as int? ?? setsP1;
      setsP2   = json['sp2'] as int? ?? setsP2;
      serving  = json['sv']  as int? ?? serving;
      gameOver = (json['go'] as int? ?? 0) == 1;
      targetScore = json['tg'] as int? ?? targetScore;
      notifyListeners();
    } catch (_) {
      // Ignore malformed packets
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  SENDING COMMANDS
  // ─────────────────────────────────────────────────────────────
  Future<void> sendCommand(int commandByte) async {
    if (_commandChar == null) return;
    try {
      await _commandChar!.write([commandByte], withoutResponse: false);
    } catch (e) {
      debugPrint('BLE write error: $e');
    }
  }

  // Convenience helpers used by the UI.
  //
  // addPoint()/undoPoint() act on whichever team is currently SELECTED
  // (serve indicator) on the board — this mirrors the physical remote's
  // Up/Down buttons and is kept for anything that intentionally wants
  // "score for whoever is serving" behaviour.
  Future<void> addPoint()      => sendCommand(BleCommand.up);
  Future<void> undoPoint()     => sendCommand(BleCommand.down);
  Future<void> setServe1()     => sendCommand(BleCommand.left);
  Future<void> setServe2()     => sendCommand(BleCommand.right);
  Future<void> setServerNum1() => sendCommand(BleCommand.num1);
  Future<void> setServerNum2() => sendCommand(BleCommand.num2);
  Future<void> resetMatch()    => sendCommand(BleCommand.star);

  // ── Direct per-player scoring — independent of serve ───────────────
  // Adds/undoes a point for a SPECIFIC player WITHOUT touching the
  // board's serve selection at all. Use these from the score screen's
  // per-player +1/undo buttons so tapping a score never moves the serve
  // indicator — only the hardware's LED arrow updates, automatically,
  // to reflect who just scored.
  Future<void> scorePlayer1() => sendCommand(BleCommand.scoreP1);
  Future<void> scorePlayer2() => sendCommand(BleCommand.scoreP2);
  Future<void> undoPlayer1()  => sendCommand(BleCommand.undoP1);
  Future<void> undoPlayer2()  => sendCommand(BleCommand.undoP2);

  // Dynamic scoring: tells the board how many points win the CURRENT
  // set (11 / 15 / 20 / a custom value). This is a 2-byte write, unlike
  // the single-byte commands above, so it doesn't go through
  // sendCommand().
  Future<void> setTargetScore(int target) async {
    final clamped = target.clamp(1, 255);
    targetScore = clamped;
    notifyListeners();
    if (_commandChar == null) return;
    try {
      await _commandChar!.write(
        [BleCommand.setTarget, clamped],
        withoutResponse: false,
      );
    } catch (e) {
      debugPrint('BLE write error (target score): $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  DISCONNECT
  // ─────────────────────────────────────────────────────────────
  void _handleDisconnect() {
    _commandChar = null;
    _stateChar   = null;
    _notifySub?.cancel();
    connectedDevice = null;
    status = BleStatus.disconnected;
    notifyListeners();
  }

  Future<void> disconnect() async {
    final device = connectedDevice;
    await device?.disconnect();
    if (device != null && Platform.isAndroid) {
      try {
        await device.removeBond();
      } catch (e) {
        debugPrint('BLE removeBond (on disconnect) skipped: $e');
      }
    }
    _handleDisconnect();
  }

  // Signal strength helper (0–4 bars)
  int barsFromRssi(int rssi) {
    if (rssi >= -55) return 4;
    if (rssi >= -67) return 3;
    if (rssi >= -78) return 2;
    if (rssi >= -88) return 1;
    return 0;
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _notifySub?.cancel();
    super.dispose();
  }
}