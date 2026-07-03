import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SignalBars extends StatelessWidget {
  final int bars; // 0–4
  final Color activeColor;
  final double height;

  const SignalBars({
    super.key,
    required this.bars,
    this.activeColor = AppColors.p1Lime,
    this.height = 20,
  });

  @override
  Widget build(BuildContext context) {
    const barCount = 4;
    const barWidth = 5.0;
    const gap      = 3.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(barCount, (i) {
        final active = i < bars;
        final barH   = height * (0.3 + 0.175 * i);
        return Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
          child: Container(
            width: barWidth,
            height: barH,
            decoration: BoxDecoration(
              color: active ? activeColor : AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}
