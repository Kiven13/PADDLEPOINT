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
//  Scoring mode
//  - sideOut : official pickleball rule — only the SERVING side can score
//              a point. The other side must win the rally to earn serve
//              first ("side out") before it can add to its own score.
//  - rally   : "rally scoring" variant — either side can score on any
//              rally regardless of who's serving. Handy for casual /
//              timed games where side-out's strict serve rotation isn't
//              wanted.
//  Side-out is the default, since it's the standard pickleball rule.
// ─────────────────────────────────────────────────────────────────────────────
enum ScoringMode { sideOut, rally }

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
  double get modeGapB    => isSmall ?  6.0 : 10.0;
  double get panelGapB   => isSmall ?  6.0 : 12.0;
  double get gridGapRow  => isSmall ?  7.0 : 10.0;
  double get bottomGapT  => isSmall ?  6.0 : 10.0;
  double get pageDotsT   => isSmall ?  8.0 : 12.0;
  double get bottomGapB  => isSmall ?  6.0 : 12.0;

  // Score panel inner padding
  double get panelPadV   => isSmall ? 10.0 : 16.0;
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

  // ── Scoring mode ────────────────────────────────────────────────────
  // Defaults to side-out — the official pickleball rule where only the
  // serving side can add to its score. Users can switch to rally scoring
  // (either side scores on any rally) via the toggle under the target
  // score row. This only gates which +1 buttons are tappable from this
  // screen; it doesn't change anything on the board itself.
  ScoringMode _scoringMode = ScoringMode.sideOut;

  void _onScoringModeChanged(ScoringMode mode) {
    setState(() => _scoringMode = mode);
  }

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
            SizedBox(height: r.modeGapB),
            _ScoringModeRow(
              mode: _scoringMode, r: r,
              onChanged: _onScoringModeChanged,
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
              child: _ScorePanel(ble: ble, r: r, scoringMode: _scoringMode),
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
//  Scoring mode row — a small segmented toggle between SIDE-OUT (the
//  official pickleball rule: only the serving side can score) and RALLY
//  (either side can score any rally). Sits right under the target score
//  row, out of the way of the main tap targets, matching that row's
//  visual weight so the two read as a pair of match settings.
// ─────────────────────────────────────────────────────────────────────────────
class _ScoringModeRow extends StatelessWidget {
  final ScoringMode mode;
  final _R r;
  final ValueChanged<ScoringMode> onChanged;
  const _ScoringModeRow({required this.mode, required this.r, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(r.hPad, 0, r.hPad, 0),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: _ModeSegment(
                label: 'SIDE-OUT',
                subLabel: 'Official rule',
                selected: mode == ScoringMode.sideOut,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(ScoringMode.sideOut);
                },
                r: r,
              ),
            ),
            Expanded(
              child: _ModeSegment(
                label: 'RALLY',
                subLabel: 'Either side scores',
                selected: mode == ScoringMode.rally,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(ScoringMode.rally);
                },
                r: r,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  final String label, subLabel;
  final bool selected;
  final VoidCallback onTap;
  final _R r;
  const _ModeSegment({
    required this.label, required this.subLabel,
    required this.selected, required this.onTap, required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(vertical: r.isSmall ? 6 : 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.p1Lime.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? AppColors.p1Lime.withOpacity(0.5) : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: GoogleFonts.inter(
                  fontSize: r.isSmall ? 10 : 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.p1Lime : AppColors.textSecondary,
                  letterSpacing: 1,
                )),
            const SizedBox(height: 1),
            Text(subLabel,
                style: GoogleFonts.inter(
                  fontSize: r.isSmall ? 7.5 : 8.5,
                  fontWeight: FontWeight.w500,
                  color: selected
                      ? AppColors.p1Lime.withOpacity(0.8)
                      : AppColors.textHint,
                )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Score panel
//  A full-width SERVE bar sits across the top — a sliding pill indicator
//  moves between the two player labels to show who's serving. Below it,
//  each player column carries its own +1 (top) and undo (bottom)
//  controls, matching sizes, hugging the score tightly.
//
//  Doubles server tracking: each player side has its OWN independent
//  "server 1 / server 2" counter (_server1Num / _server2Num) with its own
//  up/down arrows. Only the currently-serving side's stepper is shown
//  (docked beneath the pill and cross-fading when serve flips), but each
//  side's local counter persists independently across side-outs.
//  Only the currently-serving side's number is actually pushed to the
//  physical board (since the BLE command has no player argument).
// ─────────────────────────────────────────────────────────────────────────────
class _ScorePanel extends StatefulWidget {
  final BleService ble;
  final _R r;
  final ScoringMode scoringMode;
  const _ScorePanel({required this.ble, required this.r, required this.scoringMode});

  @override
  State<_ScorePanel> createState() => _ScorePanelState();
}

class _ScorePanelState extends State<_ScorePanel> {
  BleService get ble => widget.ble;
  _R get r => widget.r;

  // Score buttons call direct per-player commands (scorePlayer1/2,
  // undoPlayer1/2) that add/undo a point on the board WITHOUT touching
  // serve at all. Serve only ever changes via the SERVE pill in
  // _ServeTopBar. The hardware's LED arrow still updates on its own to
  // reflect who just scored — that's handled entirely by the firmware.
  int get _displayServer => ble.serving;

  // Independent doubles "server number" (1 or 2) for each side — Player 1
  // and Player 2 each rotate through their own two servers before a
  // side-out, and each side's up/down arrows are always active.
  int _server1Num = 1;
  int _server2Num = 1;
  int _lastServingSide = 0;

  @override
  void didUpdateWidget(covariant _ScorePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The actual reset-to-1 happens immediately in _setServe (optimistic
    // update). This just keeps _lastServingSide in sync in case serve
    // changes from some other source (e.g. the physical remote) rather
    // than the in-app serve pill — in that case we still reset the
    // newly-serving side's counter once the BLE value catches up.
    if (_lastServingSide != 0 && ble.serving != _lastServingSide) {
      _server1Num = 1;
      _server2Num = 1;
    }
    _lastServingSide = ble.serving;
  }

  void _bumpServerNum(int player, int delta) {
    final current = player == 1 ? _server1Num : _server2Num;
    final next = (current + delta).clamp(1, 2);
    if (next == current) return;
    setState(() {
      if (player == 1) {
        _server1Num = next;
      } else {
        _server2Num = next;
      }
    });
    HapticFeedback.selectionClick();
    // The board's server-number command applies to whichever side is
    // currently serving, so only forward it to hardware when this
    // player's side actually holds serve right now.
    if (_displayServer == player) {
      if (next == 1) {
        ble.setServerNum1();
      } else {
        ble.setServerNum2();
      }
    }
  }

  // In SIDE-OUT mode (the official pickleball rule) only the serving
  // side's +1 button is tappable — the receiving side can't add to its
  // score until it wins the rally and gets serve. In RALLY mode both
  // sides can always score. Undo is never gated by scoring mode — it's
  // a correction tool, not a scoring action.
  // Called when the serve pill is tapped to a side — assigns serve to
  // that side and immediately resets BOTH sides' server counters to 1.
  // This is optimistic (updates local state right away via setState)
  // rather than waiting for `ble.serving` to change and come back
  // through didUpdateWidget, so the reset feels instant instead of
  // lagging a BLE round-trip.
  void _setServe(BuildContext context, int player) {
    HapticFeedback.selectionClick();
    setState(() {
      _server1Num = 1;
      _server2Num = 1;
    });
    if (player == 1) {
      ble.setServe1();
    } else {
      ble.setServe2();
    }
    // setServerNum1() resets the CURRENT server slot to 1 — it's not
    // "player 1", it's "slot 1". A side switch always starts serving from
    // slot 1, so this is always the right call regardless of which
    // player just gained serve.
    ble.setServerNum1();
    _lastServingSide = player;
  }

  bool _canScore(int player) {
    if (widget.scoringMode == ScoringMode.rally) return true;
    return _displayServer == player;
  }

  Future<void> _scoreFor(int player) async {
    if (!_canScore(player)) return;
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
            _ServeTopBar(
              r: r, serving: displayServer,
              server1Num: _server1Num, server2Num: _server2Num,
              onSetServe1: () => _setServe(context, 1),
              onSetServe2: () => _setServe(context, 2),
              onServer1Up: () => _bumpServerNum(1, 1),
              onServer1Down: () => _bumpServerNum(1, -1),
              onServer2Up: () => _bumpServerNum(2, 1),
              onServer2Down: () => _bumpServerNum(2, -1),
            ),
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
                      scoreEnabled: connected && _canScore(1),
                      onAdd: () {
                        if (!_canScore(1)) return;
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
                      scoreEnabled: connected && _canScore(2),
                      onAdd: () {
                        if (!_canScore(2)) return;
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
//  Serve bar — a single sliding pill indicator moves between the two
//  player labels to show who's serving, instead of two independently
//  animating cards. The motion itself communicates the handoff: your eye
//  follows the pill from left to right (or back), so "serve just
//  changed" reads instantly even out of the corner of your eye.
//
//  Tapping either half of the bar assigns serve to that side. The
//  server-number stepper for the currently-serving side is docked
//  directly beneath the pill and cross-fades in place when serve flips.
//  `serving` is passed in explicitly (rather than read live from `ble`)
//  so the parent panel can pin it and avoid mid-tap flicker.
// ─────────────────────────────────────────────────────────────────────────────
class _ServeTopBar extends StatelessWidget {
  final _R r;
  final int serving;
  final int server1Num, server2Num;
  final VoidCallback onSetServe1, onSetServe2;
  final VoidCallback onServer1Up, onServer1Down;
  final VoidCallback onServer2Up, onServer2Down;

  const _ServeTopBar({
    required this.r, required this.serving,
    required this.server1Num, required this.server2Num,
    required this.onSetServe1, required this.onSetServe2,
    required this.onServer1Up, required this.onServer1Down,
    required this.onServer2Up, required this.onServer2Down,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = serving == 1 ? AppColors.p1Lime : AppColors.p2Sky;
    final activeServerNum = serving == 1 ? server1Num : server2Num;
    final onActiveUp = serving == 1 ? onServer1Up : onServer2Up;
    final onActiveDown = serving == 1 ? onServer1Down : onServer2Down;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          vertical: r.serveBarPadV, horizontal: r.hPad),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withOpacity(0.35),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sliding pill track ──────────────────────────────────────
          Container(
            height: r.isSmall ? 40 : 46,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(r.isSmall ? 20 : 23),
              border: Border.all(color: AppColors.border),
            ),
            child: Stack(
              children: [
                // The pill itself — slides left/right and recolors to
                // match whichever side is currently serving.
                AnimatedAlign(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: serving == 1
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: 0.5,
                    heightFactor: 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      decoration: BoxDecoration(
                        color: activeColor.withOpacity(0.16),
                        borderRadius:
                            BorderRadius.circular(r.isSmall ? 17 : 20),
                        border: Border.all(color: activeColor, width: 1.5),
                      ),
                    ),
                  ),
                ),
                // Static labels + tap targets, laid on top of the pill.
                Row(
                  children: [
                    Expanded(
                      child: _ServeLabel(
                        label: 'PLAYER 1',
                        color: AppColors.p1Lime,
                        isServing: serving == 1,
                        onTap: onSetServe1,
                        r: r,
                      ),
                    ),
                    Expanded(
                      child: _ServeLabel(
                        label: 'PLAYER 2',
                        color: AppColors.p2Sky,
                        isServing: serving == 2,
                        onTap: onSetServe2,
                        r: r,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: r.isSmall ? 6 : 8),

          // ── Server-number stepper for whichever side is serving ────
          // Cross-fades + keys off `serving` so it visibly "hands off"
          // in sync with the pill above rather than just snapping.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Row(
              key: ValueKey(serving),
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sports_tennis_rounded,
                    size: r.isSmall ? 11 : 12, color: activeColor),
                SizedBox(width: r.isSmall ? 6 : 8),
                _StepArrow(
                  icon: Icons.remove_rounded,
                  color: activeColor,
                  active: activeServerNum > 1,
                  onTap: activeServerNum > 1 ? onActiveDown : null,
                ),
                SizedBox(width: r.isSmall ? 6 : 8),
                Text('SERVER $activeServerNum OF 2',
                    style: GoogleFonts.oswald(
                      fontSize: r.isSmall ? 11 : 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: activeColor,
                    )),
                SizedBox(width: r.isSmall ? 6 : 8),
                _StepArrow(
                  icon: Icons.add_rounded,
                  color: activeColor,
                  active: activeServerNum < 2,
                  onTap: activeServerNum < 2 ? onActiveUp : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// A single label + tap target inside the sliding-pill track. Purely
// presentational — the pill behind it (drawn by the parent Stack in
// _ServeTopBar) is what actually shows selection state, so this just
// handles text color and the gesture.
class _ServeLabel extends StatelessWidget {
  final String label;
  final Color color;
  final bool isServing;
  final VoidCallback onTap;
  final _R r;

  const _ServeLabel({
    required this.label, required this.color,
    required this.isServing, required this.onTap, required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: r.isSmall ? 10 : 11,
            fontWeight: FontWeight.w700,
            color: isServing ? color : AppColors.textHint,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

// Small +/- stepper button used beneath the serve pill to change the
// active side's doubles server number. Uses plain +/- glyphs (rather
// than up/down chevrons) so it doesn't visually compete with the pill's
// own left/right motion — this control means "change the number", full
// stop.
class _StepArrow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool active;
  final VoidCallback? onTap;
  const _StepArrow({
    required this.icon, required this.color,
    required this.active, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(active ? 0.16 : 0.04),
          border: Border.all(color: color.withOpacity(active ? 0.5 : 0.15)),
        ),
        child: Icon(icon, size: 13,
            color: color.withOpacity(active ? 1 : 0.25)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  One player's half of the score panel — carries its own +1 / undo.
//  Server rotation is now owned entirely by the sliding pill + stepper in
//  _ServeTopBar, so this column stays purely about scoring: no badge
//  crammed in above the label.
// ─────────────────────────────────────────────────────────────────────────────
class _PlayerSide extends StatelessWidget {
  final String label;
  final int score, setsWon;
  final Color accentColor;
  final bool isServing, rightBorder, enabled;
  // Whether the +1 button is actually tappable right now. Distinct from
  // `enabled` (which just reflects BLE connection) — in SIDE-OUT scoring
  // mode this is false for whichever side isn't currently serving.
  final bool scoreEnabled;
  final _R r;
  final VoidCallback onAdd, onUndo;

  const _PlayerSide({
    required this.label, required this.score, required this.setsWon,
    required this.accentColor, required this.isServing,
    required this.rightBorder, required this.r,
    required this.enabled, required this.onAdd, required this.onUndo,
    this.scoreEnabled = true,
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
            enabled: enabled && scoreEnabled,
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
            enabled: enabled && scoreEnabled,
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