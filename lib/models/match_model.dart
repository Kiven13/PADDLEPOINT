class SetResult {
  final int score1;
  final int score2;
  const SetResult(this.score1, this.score2);

  Map<String, dynamic> toMap() => {'s1': score1, 's2': score2};
  factory SetResult.fromMap(Map<String, dynamic> m) =>
      SetResult(m['s1'] as int, m['s2'] as int);
}

class MatchRecord {
  final String id;
  final DateTime playedAt;
  final List<SetResult> sets;
  final int winner;   // 1 or 2
  final int setsP1;
  final int setsP2;

  const MatchRecord({
    required this.id,
    required this.playedAt,
    required this.sets,
    required this.winner,
    required this.setsP1,
    required this.setsP2,
  });

  String get resultLabel => 'Player $winner wins · $setsP1–$setsP2';
}
