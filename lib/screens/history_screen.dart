import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/match_model.dart';
import '../services/game_provider.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Responsive helper
// ─────────────────────────────────────────────────────────────────────────────
class _R {
  final double h, w;
  const _R(this.h, this.w);

  bool get isSmall  => h < 700;
  bool get isMedium => h < 850;
  bool get isTablet => w >= 600;
  double get maxContentWidth => isTablet ? 480.0 : double.infinity;

  // Top bar
  double get topBarVPad  => isSmall ?  8.0 : 12.0;
  double get topBarGapB  => isSmall ? 10.0 : 14.0;
  double get titleFont   => isSmall ? 14.0 : 16.0;
  double get iconBtnSize => isSmall ? 32.0 : 36.0;

  // Stats strip
  double get statsPadB   => isSmall ? 10.0 : 14.0;
  double get statsValFont => isSmall ? 18.0 : 22.0;
  double get statsPadV   => isSmall ?  8.0 : 10.0;

  // Section label
  double get sectionLabelGapB => isSmall ? 6.0 : 8.0;

  // Match card
  double get cardBodyPadV => isSmall ?  8.0 : 10.0;
  double get cardBodyPadB => isSmall ?  8.0 : 12.0;
  double get pipSize      => isSmall ? 24.0 : 28.0;
  double get pipFont      => isSmall ? 12.0 : 14.0;

  // Swipe hint / page dots
  double get hintVPad    => isSmall ?  5.0 :  8.0;
  double get pageDotsT   => isSmall ?  8.0 : 10.0;
  double get bottomPad   => isSmall ?  8.0 : 12.0;

  // Empty state
  double get emptyIconSize  => isSmall ? 60.0 : 72.0;
  double get emptyTitleFont => isSmall ? 17.0 : 20.0;
  double get emptyBodyFont  => isSmall ? 12.0 : 13.0;

  // Horizontal padding
  double get hPad => w < 380 ? 14.0 : 16.0;
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  String _formatDate(DateTime dt) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d     = DateTime(dt.year, dt.month, dt.day);
    final diff  = today.difference(d).inDays;
    final h     = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min   = dt.minute.toString().padLeft(2, '0');
    final ampm  = dt.hour < 12 ? 'AM' : 'PM';
    final time  = '$h:$min $ampm';
    if (diff == 0) return 'TODAY · $time';
    if (diff == 1) return 'YESTERDAY · $time';
    return '${_months[dt.month - 1]} ${dt.day}, ${dt.year} · $time'.toUpperCase();
  }

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final game  = context.watch<GameProvider>();
    final size  = MediaQuery.of(context).size;
    final r     = _R(size.height, size.width);

    final total  = game.matchHistory.length;
    final p1wins = game.matchHistory.where((m) => m.winner == 1).length;
    final p2wins = game.matchHistory.where((m) => m.winner == 2).length;

    return Scaffold(
      backgroundColor: AppColors.courtDark,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: r.maxContentWidth),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TopBar(
              hasHistory: game.matchHistory.isNotEmpty,
              onClearAll: () => _confirmClearAll(context, game),
              r: r,
            ),
            _StatsStrip(total: total, p1wins: p1wins, p2wins: p2wins, r: r),

            Expanded(
              child: !game.historyLoaded
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.p1Lime),
                    )
                  : game.matchHistory.isEmpty
                      ? _EmptyState(r: r)
                      : _MatchList(
                          matches:    game.matchHistory,
                          formatDate: _formatDate,
                          onDelete:   (id) => game.deleteMatch(id),
                          r:          r,
                        ),
            ),

            _PageDots(r: r),
            SizedBox(height: r.bottomPad),
          ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmClearAll(BuildContext context, GameProvider game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Clear History?',
            style: GoogleFonts.oswald(
                color: AppColors.textPrimary, fontSize: 20, letterSpacing: 1)),
        content: Text('All match records will be permanently deleted.',
            style: GoogleFonts.inter(
                color: AppColors.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.disconnected,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              for (final m in List.from(game.matchHistory)) {
                await game.deleteMatch(m.id);
              }
            },
            child: const Text('CLEAR ALL'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Top bar
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final bool hasHistory;
  final VoidCallback onClearAll;
  final _R r;

  const _TopBar({
    required this.hasHistory,
    required this.onClearAll,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          r.hPad, r.topBarVPad, r.hPad, r.topBarGapB),
      child: Row(
        children: [
          _IconBtn(
            icon: Icons.arrow_back_rounded,
            size: r.iconBtnSize,
            onTap: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          Text('MATCH HISTORY',
              style: GoogleFonts.oswald(
                fontSize: r.titleFont, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary, letterSpacing: 2,
              )),
          const Spacer(),
          _IconBtn(
            icon: Icons.delete_outline_rounded,
            size: r.iconBtnSize,
            onTap: hasHistory ? onClearAll : null,
            muted: !hasHistory,
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback? onTap;
  final bool muted;

  const _IconBtn({
    required this.icon,
    required this.size,
    required this.onTap,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        splashColor: AppColors.p1Lime.withOpacity(0.12),
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon,
              size: size * 0.47,
              color: muted ? AppColors.textHint : AppColors.textSecondary),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Stats strip
// ─────────────────────────────────────────────────────────────────────────────
class _StatsStrip extends StatelessWidget {
  final int total, p1wins, p2wins;
  final _R r;

  const _StatsStrip({
    required this.total, required this.p1wins,
    required this.p2wins, required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(r.hPad, 0, r.hPad, r.statsPadB),
      child: Row(
        children: [
          _StatCard(value: '$total', label: 'MATCHES',
              valueColor: AppColors.textPrimary, r: r),
          const SizedBox(width: 8),
          _StatCard(value: '$p1wins', label: 'P1 WINS',
              valueColor: AppColors.p1Lime, r: r),
          const SizedBox(width: 8),
          _StatCard(value: '$p2wins', label: 'P2 WINS',
              valueColor: AppColors.p2Sky, r: r),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value, label;
  final Color valueColor;
  final _R r;

  const _StatCard({
    required this.value, required this.label,
    required this.valueColor, required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: 12, vertical: r.statsPadV),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: GoogleFonts.oswald(
                  fontSize: r.statsValFont, fontWeight: FontWeight.w700,
                  color: valueColor,
                )),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.inter(
                  fontSize: 9, fontWeight: FontWeight.w600,
                  color: AppColors.textHint, letterSpacing: 1,
                )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Match list
// ─────────────────────────────────────────────────────────────────────────────
class _MatchList extends StatelessWidget {
  final List<MatchRecord> matches;
  final String Function(DateTime) formatDate;
  final void Function(String) onDelete;
  final _R r;

  const _MatchList({
    required this.matches, required this.formatDate,
    required this.onDelete, required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(r.hPad + 4, 0, r.hPad, r.sectionLabelGapB),
          child: Text('RECENT MATCHES',
              style: GoogleFonts.inter(
                fontSize: 9, fontWeight: FontWeight.w700,
                color: AppColors.textHint, letterSpacing: 2,
              )),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(r.hPad, 0, r.hPad, r.isSmall ? 8 : 12),
            itemCount: matches.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _MatchCard(
              match:     matches[i],
              dateLabel: formatDate(matches[i].playedAt),
              onDelete:  () => onDelete(matches[i].id),
              r:         r,
            ),
          ),
        ),
        // Swipe hint
        Padding(
          padding: EdgeInsets.symmetric(vertical: r.hintVPad),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.swipe_left_rounded,
                  size: 12, color: AppColors.textHint),
              const SizedBox(width: 5),
              Text('SWIPE LEFT TO DELETE',
                  style: GoogleFonts.inter(
                    fontSize: 9, fontWeight: FontWeight.w500,
                    color: AppColors.textHint, letterSpacing: 1,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Match card
// ─────────────────────────────────────────────────────────────────────────────
class _MatchCard extends StatelessWidget {
  final MatchRecord match;
  final String dateLabel;
  final VoidCallback onDelete;
  final _R r;

  const _MatchCard({
    required this.match, required this.dateLabel,
    required this.onDelete, required this.r,
  });

  @override
  Widget build(BuildContext context) {
    final winnerColor = match.winner == 1 ? AppColors.p1Lime : AppColors.p2Sky;

    return Dismissible(
      key: Key(match.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.disconnected.withOpacity(0.15),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(Icons.delete_outline_rounded,
            color: AppColors.disconnected,
            size: r.isSmall ? 20 : 22),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          children: [
            // Card header
            Container(
              padding: EdgeInsets.fromLTRB(
                  14, r.isSmall ? 8 : 10, 14, r.isSmall ? 7 : 8),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border))),
              child: Row(
                children: [
                  Text(dateLabel,
                      style: GoogleFonts.inter(
                        fontSize: 9, fontWeight: FontWeight.w600,
                        color: AppColors.textHint, letterSpacing: 1,
                      )),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: winnerColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: winnerColor.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.emoji_events_rounded,
                            size: r.isSmall ? 9 : 10,
                            color: winnerColor),
                        const SizedBox(width: 4),
                        Text(match.resultLabel.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 9, fontWeight: FontWeight.w700,
                              color: winnerColor, letterSpacing: 0.5,
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Card body
            Padding(
              padding: EdgeInsets.fromLTRB(
                  14, r.cardBodyPadV, 14, r.cardBodyPadB),
              child: Column(
                children: [
                  _PlayerScoreRow(
                      label: 'Player 1', dotColor: AppColors.p1Lime,
                      sets: match.sets, playerIndex: 0, r: r),
                  Container(
                      height: 1, color: AppColors.border,
                      margin: const EdgeInsets.symmetric(vertical: 4)),
                  _PlayerScoreRow(
                      label: 'Player 2', dotColor: AppColors.p2Sky,
                      sets: match.sets, playerIndex: 1, r: r),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Player score row
// ─────────────────────────────────────────────────────────────────────────────
class _PlayerScoreRow extends StatelessWidget {
  final String label;
  final Color dotColor;
  final List<SetResult> sets;
  final int playerIndex;
  final _R r;

  const _PlayerScoreRow({
    required this.label, required this.dotColor,
    required this.sets, required this.playerIndex, required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: r.isSmall ? 4 : 5),
      child: Row(
        children: [
          Container(
            width: r.isSmall ? 7 : 8,
            height: r.isSmall ? 7 : 8,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          SizedBox(width: r.isSmall ? 7 : 8),
          Expanded(
            child: Text(label,
                style: GoogleFonts.inter(
                  fontSize: r.isSmall ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary.withOpacity(0.85),
                )),
          ),
          Row(
            children: sets.map((s) {
              final score      = playerIndex == 0 ? s.score1 : s.score2;
              final otherScore = playerIndex == 0 ? s.score2 : s.score1;
              final wonSet     = score > otherScore;
              return Container(
                width: r.pipSize, height: r.pipSize,
                margin: const EdgeInsets.only(left: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: wonSet
                      ? dotColor.withOpacity(0.12)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text('$score',
                    style: GoogleFonts.oswald(
                      fontSize: r.pipFont, fontWeight: FontWeight.w700,
                      color: wonSet
                          ? dotColor
                          : AppColors.textSecondary.withOpacity(0.4),
                    )),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Empty state
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final _R r;
  const _EmptyState({required this.r});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: r.emptyIconSize, height: r.emptyIconSize,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(Icons.sports_tennis_rounded,
                  size: r.emptyIconSize * 0.47,
                  color: AppColors.textHint),
            ),
            SizedBox(height: r.isSmall ? 16 : 20),
            Text('NO MATCHES YET',
                style: GoogleFonts.oswald(
                  fontSize: r.emptyTitleFont,
                  color: AppColors.textSecondary, letterSpacing: 2,
                )),
            SizedBox(height: r.isSmall ? 6 : 8),
            Text(
              'Completed matches will appear\nhere automatically.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: r.emptyBodyFont,
                color: AppColors.textHint, height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Page dots  (history = dot 2 active)
// ─────────────────────────────────────────────────────────────────────────────
class _PageDots extends StatelessWidget {
  final _R r;
  const _PageDots({required this.r});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: r.pageDotsT),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          final active = i == 2;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: active ? 18 : 5, height: 5,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: active ? AppColors.p1Lime : AppColors.border,
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }
}