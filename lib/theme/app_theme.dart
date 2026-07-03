import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Core backgrounds
  static const courtDark   = Color(0xFF0A1F2B);
  static const surface     = Color(0xFF112535);
  static const surfaceHigh = Color(0xFF1A3448);
  static const border      = Color(0xFF1E3A4A);

  // Player accent colors
  static const p1Lime  = Color(0xFFC8F400);  // Player 1 — yellow-green
  static const p2Sky   = Color(0xFF00AAFF);  // Player 2 — sky blue

  // State colors
  static const connected    = Color(0xFF00D4AA);
  static const disconnected = Color(0xFFFF5C5C);

  // Text
  static const textPrimary   = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF8BAAB8);
  static const textHint      = Color(0xFF6B93A3);

  // Overlay helpers
  static Color p1Overlay(double opacity) => p1Lime.withOpacity(opacity);
  static Color p2Overlay(double opacity) => p2Sky.withOpacity(opacity);
}

class AppTheme {
  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.courtDark,
    colorScheme: const ColorScheme.dark(
      primary:   AppColors.p1Lime,
      secondary: AppColors.p2Sky,
      surface:   AppColors.surface,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.p1Lime,
        foregroundColor: AppColors.courtDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: GoogleFonts.oswald(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
        ),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.courtDark,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.oswald(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: 2,
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
    ),
    dividerColor: AppColors.border,
  );
}