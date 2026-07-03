import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class ScoreButton extends StatefulWidget {
  final String label;
  final String subLabel;
  final Color accentColor;
  final VoidCallback? onTap;
  final bool isUndo;

  const ScoreButton({
    super.key,
    required this.label,
    required this.subLabel,
    required this.accentColor,
    required this.onTap,
    this.isUndo = false,
  });

  @override
  State<ScoreButton> createState() => _ScoreButtonState();
}

class _ScoreButtonState extends State<ScoreButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap() {
    HapticFeedback.mediumImpact();
    _ctrl.forward().then((_) => _ctrl.reverse());
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final dimColor = widget.accentColor.withOpacity(widget.isUndo ? 0.35 : 1.0);

    return GestureDetector(
      onTap: widget.onTap != null ? _onTap : null,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: dimColor.withOpacity(widget.isUndo ? 0.2 : 0.3),
              width: widget.isUndo ? 1 : 1.5,
            ),
          ),
          child: Column(
            children: [
              // Header strip
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: dimColor.withOpacity(widget.isUndo ? 0.06 : 0.12),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!widget.isUndo) ...[
                      Text(
                        widget.label,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: dimColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      widget.subLabel,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: dimColor.withOpacity(0.7),
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              // Big number / symbol
              Expanded(
                child: Center(
                  child: widget.isUndo
                      ? Icon(Icons.remove_rounded,
                          color: dimColor, size: 28)
                      : Text(
                          widget.label,
                          style: GoogleFonts.oswald(
                            fontSize: 42,
                            fontWeight: FontWeight.w700,
                            color: dimColor,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
