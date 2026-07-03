import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../services/game_provider.dart';
import '../services/ble_constants.dart';
import '../models/match_model.dart';
import '../theme/app_theme.dart';
import 'history_screen.dart';
import 'connect_screen.dart';

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

  // Typography
  double get scoreFont   => isSmall ? 58 : isMedium ? 72 : 86;

  // Spacing
  double get topGap      => isSmall ?  2.0 :  4.0;
  double get setsGapB    => isSmall ?  6.0 : 10.0;
  double get targetGapB  => isSmall ?  6.0 : 10.0;
  double get panelGapB   => isSmall ?  6.0 : 12.0;
  double get gridGapRow  => isSmall ?  7.0 : 10.0;
  double get bottomGapT  => isSmall ?  6.0 : 10.0;
  double get pageDotsT   => isSmall ?  8.0 : 12.0;
  double get bottomGapB  => isSmall ?  6.0 : 12.0;

  // Score panel inner padding
  double get panelPadV   => isSmall ? 10.0 : 16.0;
  double get servingH    => isSmall ? 17.0 : 20.0;
  double get servingGapB => isSmall ?  4.0 :  8.0;
  double get scoreLabelGapB => isSmall ? 2.0 : 6.0;
  double get pipsGapT    => isSmall ?  4.0 :  8.0;

  // In-panel +1 / undo buttons — same size, matching the client's sketch
  double get scoreBtnSize => isSmall ? 42.0 : isMedium ? 48.0 : 54.0;
  double get scoreBtnIcon => isSmall ? 20.0 : isMedium ? 23.0 : 26.0;

  // Center serve selector
  // Serve bar — now a full-width strip at the top of the panel
  double get serveBarPadV   => isSmall ? 8.0 : 12.0;
  double get serveDotSize   => isSmall ? 30.0 : 34.0;
  double get serveChevron   => isSmall ? 20.0 : 22.0;

  // History button
  double get histBtnSize => isSmall ? 42.0 : 46.0;
  double get resetVPad   => isSmall ? 10.0 : 12.0;

  // Horizontal padding
  double get hPad => w < 380 ? 12.0 : 16.0;

  // Score panel is capped to a comfortable share of the screen instead of
  // stretching to fill 100% of the leftover space — any extra room is
  // distributed as breathing space above/below it instead.
  double get maxPanelHeight => h * (isSmall ? 0.46 : isMedium ? 0.5 : 0.54);
}

class ScoreScreen extends StatefulWidget {
  const ScoreScreen({super.key});

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  bool _navigating = false;

  // ── Dynamic scoring state ──────────────────────────────────────────
  // The target score is whatever the user picks, and it stays that way
  // for the rest of the match — it does NOT change automatically when a
  // new set starts. We only push a default once, the very first time
  // this screen appears for a fresh match (set index 0, i.e. no sets
  // played yet), so a freshly connected/reset board starts at 11.
  bool _defaultAppliedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ble = context.read<BleService>();
      ble.addListener(_onBleChanged);
      _applyStartingDefaultIfNeeded(ble);
    });
  }

  void _onBleChanged() {
    if (!mounted || _navigating) return;
    final ble = context.read<BleService>();
    context.read<GameProvider>().updateFromBle(
      s1: ble.score1, s2: ble.score2,
      sp1: ble.setsP1, sp2: ble.setsP2,
      sv: ble.serving, go: ble.gameOver,
    );
    if (ble.status == BleStatus.disconnected) {
      _navigating = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ConnectScreen()),
      );
    }
  }

  // Only fires once, and only if we're at the very start of a match
  // (no sets played yet) — never overrides a target the user is
  // actively using mid-match, e.g. after reconnecting.
  void _applyStartingDefaultIfNeeded(BleService ble) {
    if (_defaultAppliedOnce) return;
    _defaultAppliedOnce = true;
    final setIndex = ble.setsP1 + ble.setsP2;
    if (setIndex == 0) {
      ble.setTargetScore(DefaultTargets.forSetIndex(0));
    }
  }

  // Called when the user manually picks a target from the selector.
  // This is the ONLY thing that changes the target from here on —
  // it stays this value across sets until the user picks again.
  void _onManualTargetPicked(BleService ble, int target) {
    ble.setTargetScore(target);
  }

  @override
  void dispose() {
    context.read<BleService>().removeListener(_onBleChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ble  = context.watch<BleService>();
    final game = context.watch<GameProvider>();
    final size = MediaQuery.of(context).size;
    final r    = _R(size.height, size.width);

    return Scaffold(
      backgroundColor: AppColors.courtDark,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: r.maxContentWidth),
            child: Column(
          children: [
            SizedBox(height: r.topGap),
            _TopBar(ble: ble, r: r),
            _SetsRow(
              setsP1: ble.setsP1, setsP2: ble.setsP2,
              setScores: game.completedSetScores, r: r,
            ),
            _TargetScoreRow(
              ble: ble, r: r,
              onPick: (t) => _onManualTargetPicked(ble, t),
            ),
            SizedBox(height: r.gridGapRow),
            // The panel is capped to a comfortable size (see
            // r.maxPanelHeight) rather than stretching edge-to-edge —
            // leftover vertical space is split evenly above and below it
            // instead, so the layout still uses the full screen without
            // the card itself looking oversized.
            const Spacer(flex: 1),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: r.maxPanelHeight),
              child: _ScorePanel(ble: ble, r: r),
            ),
            const Spacer(flex: 1),
            SizedBox(height: r.panelGapB),
            _BottomStrip(ble: ble, r: r),
            _PageDots(r: r),
            SizedBox(height: r.bottomGapB),
          ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Top bar
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final BleService ble;
  final _R r;
  const _TopBar({required this.ble, required this.r});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(r.hPad, 4, r.hPad, 4),
      child: Row(
        children: [
          _IconBtn(
            icon: Icons.arrow_back_rounded,
            size: r.isSmall ? 30.0 : 34.0,
            onTap: () => context.read<BleService>().disconnect(),
          ),
          const Spacer(),
          Text('LIVE SCORE',
              style: GoogleFonts.oswald(
                fontSize: r.isSmall ? 13 : 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary, letterSpacing: 2,
              )),
          const Spacer(),
          const _BlePill(),
        ],
      ),
    );
  }
}

class _BlePill extends StatefulWidget {
  const _BlePill();
  @override
  State<_BlePill> createState() => _BlePillState();
}

class _BlePillState extends State<_BlePill>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _anim = Tween(begin: 1.0, end: 0.3).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.connected.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.connected.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _anim,
            child: Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.connected),
            ),
          ),
          const SizedBox(width: 5),
          Text('BLE',
              style: GoogleFonts.inter(
                fontSize: 9, fontWeight: FontWeight.w700,
                color: AppColors.connected, letterSpacing: 1,
              )),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: size * 0.5, color: AppColors.textSecondary),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sets row
// ─────────────────────────────────────────────────────────────────────────────
class _SetsRow extends StatelessWidget {
  final int setsP1, setsP2;
  final List<SetResult> setScores;
  final _R r;

  const _SetsRow({
    required this.setsP1, required this.setsP2,
    required this.setScores, required this.r,
  });

  @override
  Widget build(BuildContext context) {
    final totalSets = setsP1 + setsP2;
    return Padding(
      padding: EdgeInsets.fromLTRB(r.hPad, 0, r.hPad, r.setsGapB),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(3, (i) {
          final isCompleted = i < totalSets;
          final score       = i < setScores.length ? setScores[i] : null;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
              decoration: BoxDecoration(
                color: isCompleted
                    ? AppColors.p1Lime.withOpacity(0.06)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isCompleted
                      ? AppColors.p1Lime.withOpacity(0.3)
                      : AppColors.border,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isCompleted)
                          Text('SET ${i + 1}',
                              style: GoogleFonts.oswald(
                                fontSize: 11, fontWeight: FontWeight.w700,
                                color: AppColors.p1Lime,
                              ))
                        else ...[
                          Text('• – •',
                              style: GoogleFonts.oswald(
                                fontSize: 11, fontWeight: FontWeight.w700,
                                color: AppColors.textHint,
                              )),
                          const SizedBox(width: 4),
                          Text('SET ${i + 1}',
                              style: GoogleFonts.inter(
                                fontSize: 8, fontWeight: FontWeight.w600,
                                color: AppColors.textHint, letterSpacing: 1,
                              )),
                        ],
                      ],
                    ),
                  ),
                  if (isCompleted && score != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(bottom: 5),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(
                            color: AppColors.p1Lime.withOpacity(0.15))),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('${score.score1}',
                                style: GoogleFonts.oswald(
                                  fontSize: 13, fontWeight: FontWeight.w700,
                                  color: score.score1 > score.score2
                                      ? AppColors.p1Lime : AppColors.textHint,
                                )),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: Text('–',
                                  style: GoogleFonts.oswald(
                                    fontSize: 11, color: AppColors.textHint)),
                            ),
                            Text('${score.score2}',
                                style: GoogleFonts.oswald(
                                  fontSize: 13, fontWeight: FontWeight.w700,
                                  color: score.score2 > score.score1
                                      ? AppColors.p2Sky : AppColors.textHint,
                                )),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Target score row  (dynamic scoring: 11 / 15 / 20 / Custom)
//  Sits right under the Sets row — visible before every point is played,
//  out of the way of the main tap targets (arrows + score panel).
// ─────────────────────────────────────────────────────────────────────────────
class _TargetScoreRow extends StatelessWidget {
  final BleService ble;
  final _R r;
  final ValueChanged<int> onPick;
  const _TargetScoreRow({required this.ble, required this.r, required this.onPick});

  Future<void> _openPicker(BuildContext context) async {
    HapticFeedback.lightImpact();
    final setIndex = ble.setsP1 + ble.setsP2;
    final recommended = DefaultTargets.forSetIndex(setIndex);

    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _TargetPickerSheet(
        currentTarget: ble.targetScore,
        recommended: recommended,
        setNumber: setIndex + 1,
      ),
    );

    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(r.hPad, 0, r.hPad, r.targetGapB),
      child: GestureDetector(
        onTap: () => _openPicker(context),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.flag_rounded, size: 13, color: AppColors.p1Lime),
              const SizedBox(width: 6),
              Text('PLAYING TO',
                  style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppColors.textHint, letterSpacing: 1.5,
                  )),
              const SizedBox(width: 6),
              Text('${ble.targetScore}',
                  style: GoogleFonts.oswald(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: AppColors.p1Lime, letterSpacing: 1,
                  )),
              const SizedBox(width: 6),
              Icon(Icons.expand_more_rounded, size: 15, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetPickerSheet extends StatefulWidget {
  final int currentTarget;
  final int recommended;
  final int setNumber;
  const _TargetPickerSheet({
    required this.currentTarget,
    required this.recommended,
    required this.setNumber,
  });

  @override
  State<_TargetPickerSheet> createState() => _TargetPickerSheetState();
}

class _TargetPickerSheetState extends State<_TargetPickerSheet> {
  late final TextEditingController _customCtrl;

  @override
  void initState() {
    super.initState();
    final isStandard = DefaultTargets.bySetIndex.contains(widget.currentTarget);
    _customCtrl = TextEditingController(
      text: isStandard ? '' : '${widget.currentTarget}',
    );
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Playing to — Set ${widget.setNumber}',
              style: GoogleFonts.oswald(
                  color: AppColors.textPrimary, fontSize: 19, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text('Recommended for this set: ${widget.recommended} points',
              style: GoogleFonts.inter(color: AppColors.textHint, fontSize: 12)),
          const SizedBox(height: 16),
          Row(
            children: DefaultTargets.bySetIndex.map((t) {
              final selected = widget.currentTarget == t &&
                  _customCtrl.text.isEmpty;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context, t);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.p1Lime.withOpacity(0.12)
                            : AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? AppColors.p1Lime
                              : AppColors.border,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text('$t',
                              style: GoogleFonts.oswald(
                                fontSize: 22, fontWeight: FontWeight.w700,
                                color: selected
                                    ? AppColors.p1Lime
                                    : AppColors.textPrimary,
                              )),
                          const SizedBox(height: 2),
                          Text(
                            t == widget.recommended ? 'RECOMMENDED' : 'POINTS',
                            style: GoogleFonts.inter(
                              fontSize: 8, fontWeight: FontWeight.w700,
                              color: t == widget.recommended
                                  ? AppColors.p1Lime
                                  : AppColors.textHint,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text('OR CUSTOM',
              style: GoogleFonts.inter(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: AppColors.textHint, letterSpacing: 1.5,
              )),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customCtrl,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.oswald(
                      color: AppColors.textPrimary, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'e.g. 21',
                    hintStyle: GoogleFonts.inter(color: AppColors.textHint),
                    filled: true,
                    fillColor: AppColors.surfaceHigh,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.p1Lime,
                  foregroundColor: AppColors.courtDark,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final parsed = int.tryParse(_customCtrl.text.trim());
                  if (parsed == null || parsed < 1) return;
                  HapticFeedback.selectionClick();
                  Navigator.pop(context, parsed.clamp(1, 255));
                },
                child: const Text('SET'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Score panel
//  A full-width SERVE bar sits across the top — a lit number badge (1 or 2)
//  flanked by left/right chevrons that assign serve to Player 1 (left) or
//  Player 2 (right), mirroring the physical remote. Below it, each player
//  column carries its own +1 (top) and undo (bottom) controls, matching
//  sizes, hugging the score tightly.
// ─────────────────────────────────────────────────────────────────────────────
class _ScorePanel extends StatefulWidget {
  final BleService ble;
  final _R r;
  const _ScorePanel({required this.ble, required this.r});

  @override
  State<_ScorePanel> createState() => _ScorePanelState();
}

class _ScorePanelState extends State<_ScorePanel> {
  BleService get ble => widget.ble;
  _R get r => widget.r;

  // Score buttons now call direct per-player commands (scorePlayer1/2,
  // undoPlayer1/2) that add/undo a point on the board WITHOUT touching
  // serve at all. Serve only ever changes via the SERVE chevrons in
  // _ServeTopBar. The hardware's LED arrow still updates on its own to
  // reflect who just scored — that's handled entirely by the firmware.
  int get _displayServer => ble.serving;

  Future<void> _scoreFor(int player) async {
    if (player == 1) {
      await ble.scorePlayer1();
    } else {
      await ble.scorePlayer2();
    }
  }

  Future<void> _undoFor(int player) async {
    if (player == 1) {
      await ble.undoPlayer1();
    } else {
      await ble.undoPlayer2();
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = ble.status == BleStatus.connected;
    final displayServer = _displayServer;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.hPad),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
          children: [
            _ServeTopBar(ble: ble, r: r, serving: displayServer),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _PlayerSide(
                      label: 'PLAYER 1', score: ble.score1,
                      setsWon: ble.setsP1, accentColor: AppColors.p1Lime,
                      isServing: displayServer == 1, rightBorder: true, r: r,
                      enabled: connected,
                      onAdd: () {
                        HapticFeedback.mediumImpact();
                        _scoreFor(1);
                      },
                      onUndo: () {
                        HapticFeedback.lightImpact();
                        _undoFor(1);
                      },
                    ),
                  ),
                  Expanded(
                    child: _PlayerSide(
                      label: 'PLAYER 2', score: ble.score2,
                      setsWon: ble.setsP2, accentColor: AppColors.p2Sky,
                      isServing: displayServer == 2, rightBorder: false, r: r,
                      enabled: connected,
                      onAdd: () {
                        HapticFeedback.mediumImpact();
                        _scoreFor(2);
                      },
                      onUndo: () {
                        HapticFeedback.lightImpact();
                        _undoFor(2);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Serve bar — full-width strip across the top of the panel, above both
//  player columns. Left chevron assigns serve to Player 1, right chevron
//  to Player 2; the number badge in the middle shows who's currently up.
//  `serving` is passed in explicitly (rather than read live from `ble`) so
//  the parent panel can pin it and avoid mid-tap flicker.
// ─────────────────────────────────────────────────────────────────────────────
class _ServeTopBar extends StatelessWidget {
  final BleService ble;
  final _R r;
  final int serving;
  const _ServeTopBar({required this.ble, required this.r, required this.serving});

  @override
  Widget build(BuildContext context) {
    final activeColor = serving == 2 ? AppColors.p2Sky : AppColors.p1Lime;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: r.serveBarPadV),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withOpacity(0.35),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('SERVE',
              style: GoogleFonts.inter(
                fontSize: 9, fontWeight: FontWeight.w700,
                color: AppColors.textHint, letterSpacing: 2,
              )),
          SizedBox(height: r.isSmall ? 4 : 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ServeChevron(
                icon: Icons.chevron_left_rounded,
                color: AppColors.p1Lime,
                size: r.serveChevron,
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.read<BleService>().setServe1();
                  context.read<BleService>().setServerNum1();
                },
              ),
              SizedBox(width: r.isSmall ? 10 : 14),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: r.serveDotSize, height: r.serveDotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: activeColor.withOpacity(0.14),
                  border: Border.all(color: activeColor, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text('$serving',
                    style: GoogleFonts.oswald(
                      fontSize: r.isSmall ? 15 : 17,
                      fontWeight: FontWeight.w700,
                      color: activeColor,
                    )),
              ),
              SizedBox(width: r.isSmall ? 10 : 14),
              _ServeChevron(
                icon: Icons.chevron_right_rounded,
                color: AppColors.p2Sky,
                size: r.serveChevron,
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.read<BleService>().setServe2();
                  context.read<BleService>().setServerNum2();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServeChevron extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;
  const _ServeChevron({
    required this.icon, required this.color,
    required this.size, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.08),
        ),
        child: Icon(icon, size: size, color: color.withOpacity(0.85)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  One player's half of the score panel — carries its own +1 / undo now.
// ─────────────────────────────────────────────────────────────────────────────
class _PlayerSide extends StatelessWidget {
  final String label;
  final int score, setsWon;
  final Color accentColor;
  final bool isServing, rightBorder, enabled;
  final _R r;
  final VoidCallback onAdd, onUndo;

  const _PlayerSide({
    required this.label, required this.score, required this.setsWon,
    required this.accentColor, required this.isServing,
    required this.rightBorder, required this.r,
    required this.enabled, required this.onAdd, required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isServing ? accentColor.withOpacity(0.035) : null,
        border: rightBorder
            ? Border(right: BorderSide(color: AppColors.border))
            : null,
      ),
      padding: EdgeInsets.fromLTRB(10, r.panelPadV, 10, r.panelPadV),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Serving badge
          AnimatedOpacity(
            opacity: isServing ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              height: r.servingH,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accentColor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: accentColor),
                  ),
                  const SizedBox(width: 4),
                  Text('SERVING',
                      style: GoogleFonts.inter(
                        fontSize: 8, fontWeight: FontWeight.w700,
                        color: accentColor, letterSpacing: 1,
                      )),
                ],
              ),
            ),
          ),
          SizedBox(height: r.servingGapB),
          Text(label,
              style: GoogleFonts.inter(
                fontSize: 9, fontWeight: FontWeight.w700,
                color: accentColor, letterSpacing: 2,
              )),

          const Spacer(flex: 1),

          // +1 button — same size as the undo button below, hugging the
          // score tightly on both sides per the sketch.
          _RoundIconBtn(
            icon: Icons.arrow_upward_rounded,
            size: r.scoreBtnSize,
            iconSize: r.scoreBtnIcon,
            color: accentColor,
            filled: true,
            enabled: enabled,
            onTap: onAdd,
          ),
          SizedBox(height: r.scoreLabelGapB),

          // Score — grows to fill the space between the buttons.
          Expanded(
            flex: 6,
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: Text('$score',
                    style: GoogleFonts.oswald(
                      fontSize: r.scoreFont, fontWeight: FontWeight.w700,
                      color: accentColor, height: 1,
                    )),
              ),
            ),
          ),
          SizedBox(height: r.scoreLabelGapB),

          // Undo — identical size to the +1 button above.
          _RoundIconBtn(
            icon: Icons.arrow_downward_rounded,
            size: r.scoreBtnSize,
            iconSize: r.scoreBtnIcon,
            color: accentColor,
            filled: true,
            enabled: enabled,
            onTap: onUndo,
          ),

          const Spacer(flex: 1),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reusable circular tap target used for +1 / undo, with a light press
//  animation for tactile feedback.
// ─────────────────────────────────────────────────────────────────────────────
class _RoundIconBtn extends StatefulWidget {
  final IconData icon;
  final double size, iconSize;
  final Color color;
  final bool filled, enabled;
  final VoidCallback onTap;

  const _RoundIconBtn({
    required this.icon, required this.size, required this.iconSize,
    required this.color, required this.filled, required this.enabled,
    required this.onTap,
  });

  @override
  State<_RoundIconBtn> createState() => _RoundIconBtnState();
}

class _RoundIconBtnState extends State<_RoundIconBtn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80));
    _scale = Tween(begin: 1.0, end: 0.92)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _onTap() {
    if (!widget.enabled) return;
    _ctrl.forward().then((_) => _ctrl.reverse());
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return GestureDetector(
      onTap: _onTap,
      child: ScaleTransition(
        scale: _scale,
        child: Opacity(
          opacity: widget.enabled ? 1.0 : 0.35,
          child: Container(
            width: widget.size, height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.filled ? c.withOpacity(0.12) : Colors.transparent,
              border: Border.all(
                color: c.withOpacity(widget.filled ? 0.4 : 0.2),
                width: widget.filled ? 1.5 : 1,
              ),
            ),
            child: Icon(widget.icon, size: widget.iconSize,
                color: c.withOpacity(widget.filled ? 1 : 0.55)),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bottom strip  (Reset + History)
// ─────────────────────────────────────────────────────────────────────────────
class _BottomStrip extends StatelessWidget {
  final BleService ble;
  final _R r;
  const _BottomStrip({required this.ble, required this.r});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(r.hPad, r.bottomGapT, r.hPad, 0),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _confirmReset(context),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: r.resetVPad),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh_rounded,
                        size: r.isSmall ? 13 : 14, color: AppColors.textHint),
                    const SizedBox(width: 6),
                    Text('RESET MATCH',
                        style: GoogleFonts.inter(
                          fontSize: r.isSmall ? 9 : 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textHint, letterSpacing: 1.5,
                        )),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () {
              context.read<GameProvider>().loadHistory();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
            child: Container(
              width: r.histBtnSize, height: r.histBtnSize,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(Icons.history_rounded,
                  size: r.isSmall ? 18 : 20,
                  color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmReset(BuildContext context) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Reset Match?',
            style: GoogleFonts.oswald(
                color: AppColors.textPrimary, fontSize: 20, letterSpacing: 1)),
        content: Text('This will reset the scoreboard to 0 – 0.',
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
            onPressed: () {
              context.read<BleService>().resetMatch();
              context.read<GameProvider>().resetLocalState();
              Navigator.pop(ctx);
            },
            child: const Text('RESET'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Page dots
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
          final active = i == 1;
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