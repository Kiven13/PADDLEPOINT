import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/match_model.dart';
import 'database_service.dart';

class GameProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();

  int score1  = 0;
  int score2  = 0;
  int setsP1  = 0;
  int setsP2  = 0;
  int serving = 1;
  bool gameOver = false;

  final List<SetResult> _currentSets = [];
  List<SetResult> get completedSetScores => List.unmodifiable(_currentSets);

  List<MatchRecord> matchHistory = [];
  bool historyLoaded = false;

  // ── Internal tracking ─────────────────────────────────────────
  int  _prevSetsTotal      = 0;
  bool _awaitingScoreReset = false;
  bool _matchSaved         = false; // guard so we only save once per match

  // ─────────────────────────────────────────────────────────────
  //  ESP32 BLE packet sequence for a set ending:
  //
  //    Packet A  →  s1=11, s2=9,  sp1=1, sp2=0   (winning point + set++)
  //    Packet B  →  s1=0,  s2=0,  sp1=1, sp2=0   (score reset for next set)
  //
  //  The winning score IS in Packet A alongside the incremented set count.
  //  We record s1/s2 directly from that packet.
  //
  //  Match save trigger: we do NOT rely on the ESP32's "go" flag because
  //  it may never be sent.  Instead we detect the win condition ourselves:
  //  first player to reach setsToWin (default 2) wins the match.
  // ─────────────────────────────────────────────────────────────
  static const int setsToWin = 2; // best-of-3

  void updateFromBle({
    required int s1,
    required int s2,
    required int sp1,
    required int sp2,
    required int sv,
    required bool go,
  }) {
    final newSetsTotal = sp1 + sp2;
    final setJustEnded = newSetsTotal > _prevSetsTotal;

    // ── True match reset: all zeros AND not a post-set score clear ──
    final isFullReset = s1 == 0 && s2 == 0 && sp1 == 0 && sp2 == 0;
    if (isFullReset && !_awaitingScoreReset) {
      score1              = 0;
      score2              = 0;
      setsP1              = 0;
      setsP2              = 0;
      serving             = sv;
      gameOver            = false;
      _prevSetsTotal      = 0;
      _awaitingScoreReset = false;
      _matchSaved         = false;
      _currentSets.clear();
      notifyListeners();
      return;
    }

    // ── Normal state update ──────────────────────────────────────
    score1   = s1;
    score2   = s2;
    setsP1   = sp1;
    setsP2   = sp2;
    serving  = sv;
    gameOver = go;

    if (setJustEnded) {
      // Record the winning scores from THIS packet (they are correct here).
      _currentSets.add(SetResult(s1, s2));
      _awaitingScoreReset = true;

      // BUG FIX: Save when a player wins enough sets, not only when go==true.
      // go flag from ESP32 may never arrive, so we check the win condition
      // ourselves: first to setsToWin sets wins the match.
      final matchWon = sp1 >= setsToWin || sp2 >= setsToWin;
      if ((matchWon || go) && !_matchSaved) {
        _matchSaved = true;
        gameOver    = true;
        _saveCurrentMatch(sp1: sp1, sp2: sp2);
      }
    } else if (_awaitingScoreReset && s1 == 0 && s2 == 0) {
      // Post-set score-reset packet — clear flag, nothing else to do.
      _awaitingScoreReset = false;
    }

    _prevSetsTotal = newSetsTotal;
    notifyListeners();
  }

  void setServing(int player) {
    serving = player;
    notifyListeners();
  }

  void resetLocalState() {
    score1              = 0;
    score2              = 0;
    setsP1              = 0;
    setsP2              = 0;
    serving             = 1;
    gameOver            = false;
    _prevSetsTotal      = 0;
    _awaitingScoreReset = false;
    _matchSaved         = false;
    _currentSets.clear();
    notifyListeners();
  }

  // BUG FIX: Always reload from DB so History screen shows the latest data.
  // Previously historyLoaded=true would cause the screen to skip reloading
  // after a new match was saved.
  Future<void> loadHistory() async {
    historyLoaded = false;
    notifyListeners(); // show spinner while loading
    matchHistory  = await _db.loadMatches();
    historyLoaded = true;
    notifyListeners();
  }

  Future<void> _saveCurrentMatch({required int sp1, required int sp2}) async {
    final winner = sp1 >= sp2 ? 1 : 2;

    final record = MatchRecord(
      id:       const Uuid().v4(),
      playedAt: DateTime.now(),
      sets:     List.from(_currentSets),
      winner:   winner,
      setsP1:   sp1,
      setsP2:   sp2,
    );

    try {
      await _db.saveMatch(record);
      matchHistory.insert(0, record);
      notifyListeners();
    } catch (e) {
      debugPrint('GameProvider: failed to save match — $e');
    }
  }

  Future<void> deleteMatch(String id) async {
    await _db.deleteMatch(id);
    matchHistory.removeWhere((m) => m.id == id);
    notifyListeners();
  }
}