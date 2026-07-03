import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../theme/app_theme.dart';
import 'score_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Responsive helper
// ─────────────────────────────────────────────────────────────────────────────
class _R {
  final double h, w;
  const _R(this.h, this.w);

  bool get isSmall  => h < 700;
  bool get isMedium => h < 850;
  // Tablets / large phones in landscape: cap content width instead of
  // letting cards and buttons stretch edge-to-edge.
  bool get isTablet => w >= 600;
  double get maxContentWidth => isTablet ? 480.0 : double.infinity;

  // Layout flex ratios
  int get heroFlex => isSmall ? 16 : 20;   // *10 so round() stays accurate
  int get bodyFlex => isSmall ? 28 : 30;

  // Hero section
  double get heroBoxSize   => isSmall ? 100.0 : 130.0;
  double get pulseRingSize => isSmall ?  84.0 : 110.0;
  double get paddleSize    => isSmall ?  68.0 :  88.0;
  double get heroGap1      => isSmall ?  12.0 :  20.0; // below paddle
  double get heroGap2      => isSmall ?   3.0 :   6.0; // below title
  double get heroGap3      => isSmall ?   6.0 :  12.0; // below subtitle

  // Typography
  double get titleFont => isSmall ? 21.0 : 28.0;
  double get subFont   => isSmall ?  9.0 : 10.0;

  // Badge
  double get badgeHPad => isSmall ? 10.0 : 14.0;
  double get badgeVPad => isSmall ?  3.0 :  5.0;
  double get badgeFont => isSmall ?  9.0 : 10.0;
  double get flagFont  => isSmall ? 12.0 : 14.0;

  // Divider
  double get dividerVPad => isSmall ?  8.0 : 14.0;

  // Scan card
  double get cardHPad      => isSmall ? 14.0 : 16.0;
  double get cardHeaderVPad => isSmall ?  8.0 : 12.0;
  double get cardEmptyVPad  => isSmall ? 16.0 : 26.0;
  double get deviceRowVPad  => isSmall ? 10.0 : 13.0;

  // Buttons
  double get btnVPad  => isSmall ? 12.0 : 16.0;
  double get btnGap   => isSmall ? 10.0 : 16.0;
  double get btnGap2  => isSmall ?  7.0 : 10.0;

  // Page
  double get hPad       => w < 380 ? 14.0 : 18.0;
  double get bottomPad  => isSmall ? 10.0 : 16.0;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Board ID helper
//  The ESP32 advertises as "PB-ScoreBoard-<4-digit-ID>". The ID is also
//  flashed on the board's own LED panel at boot, so the person can visually
//  confirm they're connecting to the board in front of them and not a
//  neighboring court's board.
// ─────────────────────────────────────────────────────────────────────────────
String? boardIdFromName(String platformName) {
  final parts = platformName.split('-');
  if (parts.isEmpty) return null;
  final last = parts.last;
  if (last.length == 4 && int.tryParse(last) != null) return last;
  return null;
}

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen>
    with SingleTickerProviderStateMixin {
  ScanResult? _selected;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _requestPermissions();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    }
  }

  // ── Board-ID confirmation step ────────────────────────────────────────
  // Before connecting, the user must confirm the ID shown in the app
  // matches the ID currently flashing on the physical board's LED panel.
  // This prevents accidentally (or intentionally, by someone else) pairing
  // with the wrong board when several are advertising nearby.
  Future<bool> _confirmBoardId(BuildContext context, String? boardId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Confirm your board',
            style: GoogleFonts.oswald(
                color: AppColors.textPrimary, fontSize: 19, letterSpacing: 1)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The board\'s LED panel flashes an ID number when it powers on.',
              style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.p1Lime.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.p1Lime.withOpacity(0.3)),
              ),
              child: Center(
                child: Text(
                  boardId ?? '----',
                  style: GoogleFonts.oswald(
                    fontSize: 32, fontWeight: FontWeight.w700,
                    color: AppColors.p1Lime, letterSpacing: 4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Only tap Confirm if this exact ID is on your board\'s panel. '
              'You\'ll then be asked to enter a 6-digit pairing PIN shown on the panel — '
              'a new PIN is generated every time you connect, even to a board you\'ve paired with before.',
              style: GoogleFonts.inter(color: AppColors.textHint, fontSize: 11.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.p1Lime,
              foregroundColor: AppColors.courtDark,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CONFIRM & PAIR'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _connect(BleService ble) async {
    if (_selected == null) return;

    final boardId = boardIdFromName(_selected!.device.platformName);
    final confirmed = await _confirmBoardId(context, boardId);
    if (!confirmed) return;
    if (!mounted) return;

    await _attemptConnect(ble);
  }

  // Shared by the initial connect attempt and the "Try Again" button in
  // the wrong-PIN dialog. Only ever navigates to ScoreScreen when the
  // board reports a genuine `connected` status — a failed pairing
  // attempt (wrong PIN) always leaves the person right here.
  Future<void> _attemptConnect(BleService ble) async {
    await ble.connectTo(_selected!.device);
    if (!mounted) return;

    if (ble.status == BleStatus.connected) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ScoreScreen()),
      );
    } else if (ble.failureReason == BleFailureReason.wrongPin) {
      _showWrongPinDialog(ble);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ble.errorMessage ?? 'Connection failed'),
          backgroundColor: AppColors.disconnected,
        ),
      );
    }
  }

  // ── Wrong-PIN dialog ─────────────────────────────────────────────────
  // The board generates a fresh PIN on every attempt, so the fix is
  // simply: look at the panel again and retry — no need to re-confirm
  // the board ID, since that part was already right.
  void _showWrongPinDialog(BleService ble) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.lock_outline_rounded,
                color: AppColors.disconnected, size: 20),
            const SizedBox(width: 8),
            Text('Incorrect PIN',
                style: GoogleFonts.oswald(
                    color: AppColors.textPrimary, fontSize: 19, letterSpacing: 1)),
          ],
        ),
        content: Text(
          'The PIN you entered didn\'t match the one shown on the board\'s '
          'LED panel. A new PIN is generated every attempt — check the '
          'panel and try again.',
          style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.p1Lime,
              foregroundColor: AppColors.courtDark,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _attemptConnect(ble);
            },
            child: const Text('TRY AGAIN'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ble  = context.watch<BleService>();
    final size = MediaQuery.of(context).size;
    final r    = _R(size.height, size.width);

    return Scaffold(
      backgroundColor: AppColors.courtDark,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: r.maxContentWidth),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
          children: [
            Expanded(
              flex: r.heroFlex,
              child: _HeroSection(pulseCtrl: _pulseCtrl, r: r),
            ),
            _SectionDivider(r: r),
            Expanded(
              flex: r.bodyFlex,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: r.hPad),
                child: Column(
                  children: [
                    _ScanCard(
                      ble: ble,
                      selected: _selected,
                      onSelect: (res) => setState(() => _selected = res),
                      r: r,
                    ),
                    SizedBox(height: r.btnGap),
                    _ConnectButton(
                      ble: ble,
                      hasSelection: _selected != null,
                      onConnect: () => _connect(context.read<BleService>()),
                      onScan:    () => context.read<BleService>().startScan(),
                      onStop:    () => context.read<BleService>().stopScan(),
                      r: r,
                    ),
                    if (_selected != null &&
                        ble.status != BleStatus.scanning &&
                        ble.status != BleStatus.connecting) ...[
                      SizedBox(height: r.btnGap2),
                      _ScanSecondaryButton(
                          onTap: () => context.read<BleService>().startScan(),
                          r: r),
                    ],
                    if (ble.status == BleStatus.error && ble.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          ble.errorMessage!,
                          style: GoogleFonts.inter(
                            fontSize: 12, color: AppColors.disconnected),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const _PageDots(),
            SizedBox(height: r.bottomPad),
          ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hero section
// ─────────────────────────────────────────────────────────────────────────────
class _HeroSection extends StatelessWidget {
  final AnimationController pulseCtrl;
  final _R r;
  const _HeroSection({required this.pulseCtrl, required this.r});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: r.heroBoxSize, height: r.heroBoxSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _PulseRing(controller: pulseCtrl, delay: 0.0,  r: r),
              _PulseRing(controller: pulseCtrl, delay: 0.33, r: r),
              _PulseRing(controller: pulseCtrl, delay: 0.66, r: r),
              _PaddleSvg(size: r.paddleSize),
            ],
          ),
        ),
        SizedBox(height: r.heroGap1),
        Text(
          'PICKLEBALL\nSCOREBOARD',
          textAlign: TextAlign.center,
          style: GoogleFonts.oswald(
            fontSize: r.titleFont, fontWeight: FontWeight.w700,
            color: AppColors.textPrimary, letterSpacing: 3, height: 1.1,
          ),
        ),
        SizedBox(height: r.heroGap2),
        Text(
          'BLE REMOTE CONTROLLER',
          style: GoogleFonts.inter(
            fontSize: r.subFont, fontWeight: FontWeight.w700,
            color: AppColors.p1Lime, letterSpacing: 4,
          ),
        ),
        SizedBox(height: r.heroGap3),
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: r.badgeHPad, vertical: r.badgeVPad),
          decoration: BoxDecoration(
            color: AppColors.p1Lime.withOpacity(0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.p1Lime.withOpacity(0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🇵🇭', style: TextStyle(fontSize: r.flagFont)),
              const SizedBox(width: 6),
              Text(
                'PHILIPPINES EDITION',
                style: GoogleFonts.inter(
                  fontSize: r.badgeFont, fontWeight: FontWeight.w600,
                  color: AppColors.p1Lime, letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Pulse ring
// ─────────────────────────────────────────────────────────────────────────────
class _PulseRing extends StatelessWidget {
  final AnimationController controller;
  final double delay;
  final _R r;
  const _PulseRing(
      {required this.controller, required this.delay, required this.r});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t       = (controller.value + delay) % 1.0;
        final scale   = 0.7 + (t * 0.8);
        final opacity = ((1.0 - t) * 0.7).clamp(0.0, 1.0);
        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: r.pulseRingSize, height: r.pulseRingSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppColors.p1Lime.withOpacity(0.6), width: 1.5),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Paddle (scales with size parameter)
// ─────────────────────────────────────────────────────────────────────────────
class _PaddleSvg extends StatelessWidget {
  final double size;
  const _PaddleSvg({required this.size});

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: -0.349,
        child: CustomPaint(size: Size(size, size), painter: _PaddlePainter()),
      );
}

class _PaddlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const lime = Color(0xFFC8F400);
    const grip = Color(0xFF8BAB00);
    const dark = Color(0xFF0A1F2B);
    final sx = size.width / 88;
    final sy = size.height / 88;

    canvas.drawRRect(
      RRect.fromLTRBR(18*sx, 10*sy, 70*sx, 62*sy, Radius.circular(26*sx)),
      Paint()..color = lime,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(36*sx, 58*sy, 52*sx, 80*sy, Radius.circular(6*sx)),
      Paint()..color = grip,
    );
    final lp = Paint()
      ..color = dark.withOpacity(0.3)
      ..strokeWidth = 2 * sx;
    for (final y in [63.0, 68.0, 73.0]) {
      canvas.drawLine(Offset(36*sx, y*sy), Offset(52*sx, y*sy), lp);
    }
    final hp = Paint()..color = dark.withOpacity(0.22);
    for (final cx in [32.0, 44.0, 56.0]) {
      for (final cy in [26.0, 38.0, 50.0]) {
        canvas.drawCircle(Offset(cx*sx, cy*sy), 4*sx, hp);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section divider
// ─────────────────────────────────────────────────────────────────────────────
class _SectionDivider extends StatelessWidget {
  final _R r;
  const _SectionDivider({required this.r});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, r.dividerVPad),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: AppColors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('NEARBY DEVICES',
                style: GoogleFonts.inter(
                  fontSize: 10, fontWeight: FontWeight.w600,
                  color: AppColors.textHint, letterSpacing: 2,
                )),
          ),
          Expanded(child: Container(height: 1, color: AppColors.border)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Scan card
// ─────────────────────────────────────────────────────────────────────────────
class _ScanCard extends StatelessWidget {
  final BleService ble;
  final ScanResult? selected;
  final ValueChanged<ScanResult> onSelect;
  final _R r;

  const _ScanCard(
      {required this.ble,
      required this.selected,
      required this.onSelect,
      required this.r});

  @override
  Widget build(BuildContext context) {
    final isScanning = ble.status == BleStatus.scanning;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
                r.cardHPad, r.cardHeaderVPad, r.cardHPad, r.cardHeaderVPad),
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(
              children: [
                _BlinkDot(active: isScanning),
                const SizedBox(width: 8),
                Text(
                  isScanning ? 'SCANNING NEARBY…' : 'NEARBY DEVICES',
                  style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary, letterSpacing: 1.8,
                  ),
                ),
                const Spacer(),
                if (isScanning) const _ScanSpinner(),
              ],
            ),
          ),
          if (ble.scanResults.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: r.cardEmptyVPad),
              child: Center(
                child: Text(
                  isScanning
                      ? 'Looking for scoreboards…'
                      : 'Tap "Scan for Boards" to start',
                  style: GoogleFonts.inter(
                      fontSize: r.isSmall ? 12 : 13,
                      color: AppColors.textHint),
                ),
              ),
            )
          else
            ...ble.scanResults.map((res) => _DeviceRow(
                  result:     res,
                  isSelected: selected?.device.remoteId == res.device.remoteId,
                  bars:       ble.barsFromRssi(res.rssi),
                  rssi:       res.rssi,
                  isLast:     res == ble.scanResults.last,
                  onTap:      () => onSelect(res),
                  r:          r,
                )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Device row
// ─────────────────────────────────────────────────────────────────────────────
class _DeviceRow extends StatelessWidget {
  final ScanResult result;
  final bool isSelected, isLast;
  final int bars, rssi;
  final VoidCallback onTap;
  final _R r;

  const _DeviceRow({
    required this.result,
    required this.isSelected,
    required this.isLast,
    required this.bars,
    required this.rssi,
    required this.onTap,
    required this.r,
  });

  String get _signalLabel {
    if (bars >= 4) return 'Strong signal';
    if (bars >= 3) return 'Good signal';
    if (bars >= 2) return 'Medium signal';
    return 'Weak signal';
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = r.isSmall ? 34.0 : 36.0;
    final boardId  = boardIdFromName(result.device.platformName);
    return Material(
      color: isSelected ? AppColors.p1Lime.withOpacity(0.06) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.p1Lime.withOpacity(0.12),
        highlightColor: AppColors.p1Lime.withOpacity(0.06),
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: r.cardHPad, vertical: r.deviceRowVPad),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: isSelected ? AppColors.p1Lime : Colors.transparent,
              width: 2.5,
            ),
            bottom: isLast ? BorderSide.none : BorderSide(color: AppColors.border),
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: iconSize, height: iconSize,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.p1Lime.withOpacity(0.12)
                    : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.memory_rounded,
                  size: r.isSmall ? 16 : 18,
                  color: isSelected ? AppColors.p1Lime : AppColors.textSecondary),
            ),
            SizedBox(width: r.isSmall ? 10 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.device.platformName.isNotEmpty
                        ? result.device.platformName
                        : result.device.remoteId.toString(),
                    style: GoogleFonts.inter(
                      fontSize: r.isSmall ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppColors.p1Lime : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text('ESP32 · $_signalLabel',
                          style: GoogleFonts.inter(
                            fontSize: r.isSmall ? 9 : 10,
                            color: isSelected
                                ? AppColors.textSecondary
                                : AppColors.textHint,
                            fontWeight: FontWeight.w500,
                          )),
                      if (isSelected) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.connected.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: AppColors.connected.withOpacity(0.2)),
                          ),
                          child: Text('$rssi dBm',
                              style: GoogleFonts.inter(
                                fontSize: 9, fontWeight: FontWeight.w600,
                                color: AppColors.connected, letterSpacing: 0.5,
                              )),
                        ),
                      ],
                    ],
                  ),
                  if (boardId != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.p1Lime.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: AppColors.p1Lime.withOpacity(0.25)),
                      ),
                      child: Text('BOARD ID $boardId',
                          style: GoogleFonts.inter(
                            fontSize: 9, fontWeight: FontWeight.w700,
                            color: AppColors.p1Lime, letterSpacing: 1,
                          )),
                    ),
                  ],
                ],
              ),
            ),
            _SignalBars(bars: bars),
            const SizedBox(width: 4),
            if (isSelected)
              Container(
                width: 20, height: 20,
                margin: const EdgeInsets.only(left: 4),
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: AppColors.p1Lime),
                child: const Icon(Icons.check_rounded,
                    size: 13, color: AppColors.courtDark),
              ),
          ],
        ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Signal bars — fixed icon size, responsive to content only
// ─────────────────────────────────────────────────────────────────────────────
class _SignalBars extends StatelessWidget {
  final int bars;
  const _SignalBars({required this.bars});

  @override
  Widget build(BuildContext context) {
    const heights = [5.0, 8.0, 11.0, 16.0];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (i) => Container(
        width: 4, height: heights[i],
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: i < bars ? AppColors.p1Lime : AppColors.border,
          borderRadius: BorderRadius.circular(2),
        ),
      )),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Connect / Scan / Stop button
// ─────────────────────────────────────────────────────────────────────────────
class _ConnectButton extends StatelessWidget {
  final BleService ble;
  final bool hasSelection;
  final VoidCallback onConnect, onScan, onStop;
  final _R r;

  const _ConnectButton({
    required this.ble,
    required this.hasSelection,
    required this.onConnect,
    required this.onScan,
    required this.onStop,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    final isScanning   = ble.status == BleStatus.scanning;
    final isConnecting = ble.status == BleStatus.connecting;

    if (isConnecting) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.p1Lime,
            disabledBackgroundColor: AppColors.p1Lime.withOpacity(0.6),
            padding: EdgeInsets.symmetric(vertical: r.btnVPad),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.courtDark),
              ),
              const SizedBox(width: 10),
              Text('CONNECTING…',
                  style: GoogleFonts.inter(
                    fontSize: r.isSmall ? 12 : 13, fontWeight: FontWeight.w700,
                    color: AppColors.courtDark, letterSpacing: 2,
                  )),
            ],
          ),
        ),
      );
    }

    if (hasSelection && !isScanning) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onConnect,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.p1Lime,
            foregroundColor: AppColors.courtDark,
            padding: EdgeInsets.symmetric(vertical: r.btnVPad),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.bluetooth_connected_rounded, size: 16),
              const SizedBox(width: 8),
              Text('CONNECT TO BOARD',
                  style: GoogleFonts.inter(
                    fontSize: r.isSmall ? 12 : 13, fontWeight: FontWeight.w700,
                    color: AppColors.courtDark, letterSpacing: 2,
                  )),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isScanning ? onStop : onScan,
        style: ElevatedButton.styleFrom(
          backgroundColor: isScanning ? AppColors.surfaceHigh : AppColors.p1Lime,
          foregroundColor: isScanning ? AppColors.textPrimary : AppColors.courtDark,
          padding: EdgeInsets.symmetric(vertical: r.btnVPad),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          side: isScanning ? BorderSide(color: AppColors.border) : BorderSide.none,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isScanning ? Icons.stop_rounded : Icons.radar_rounded, size: 16),
            const SizedBox(width: 8),
            Text(
              isScanning ? 'STOP SCAN' : 'SCAN FOR BOARDS',
              style: GoogleFonts.inter(
                fontSize: r.isSmall ? 12 : 13, fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Secondary scan button
// ─────────────────────────────────────────────────────────────────────────────
class _ScanSecondaryButton extends StatelessWidget {
  final VoidCallback onTap;
  final _R r;
  const _ScanSecondaryButton({required this.onTap, required this.r});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(vertical: r.isSmall ? 10 : 13),
          side: BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.radar_rounded,
                size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text('SCAN AGAIN',
                style: GoogleFonts.inter(
                  fontSize: r.isSmall ? 11 : 12, fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary, letterSpacing: 2,
                )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Page dots (connect = dot 0 active)
// ─────────────────────────────────────────────────────────────────────────────
class _PageDots extends StatelessWidget {
  const _PageDots();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Dot(active: true),
          const SizedBox(width: 5),
          _Dot(active: false),
          const SizedBox(width: 5),
          _Dot(active: false),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;
  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 18 : 5, height: 5,
      decoration: BoxDecoration(
        color: active ? AppColors.p1Lime : AppColors.border,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Blinking dot
// ─────────────────────────────────────────────────────────────────────────────
class _BlinkDot extends StatefulWidget {
  final bool active;
  const _BlinkDot({required this.active});

  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot>
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
    return FadeTransition(
      opacity: widget.active ? _anim : const AlwaysStoppedAnimation(1.0),
      child: Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.active ? AppColors.connected : AppColors.textHint,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Scan spinner
// ─────────────────────────────────────────────────────────────────────────────
class _ScanSpinner extends StatefulWidget {
  const _ScanSpinner();

  @override
  State<_ScanSpinner> createState() => _ScanSpinnerState();
}

class _ScanSpinnerState extends State<_ScanSpinner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: Container(
        width: 14, height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border, width: 2),
        ),
        child: ClipOval(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(width: 14, height: 7, color: AppColors.connected),
          ),
        ),
      ),
    );
  }
}