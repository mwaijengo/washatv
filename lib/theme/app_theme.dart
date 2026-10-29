import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Cinematic streaming design system — deep space blacks, electric cyan, premium gold.
class AppTheme {
  // ── Core palette ──────────────────────────────────────────────────────────
  static const Color background = Color(0xFF010208);
  static const Color surface = Color(0xFF0A0E1A);
  static const Color surfaceElevated = Color(0xFF12182B);
  static const Color panel = Color(0x6612182B);
  static const Color navPanel = Color(0xB30A0E1A);

  // Accent — electric cyan / teal
  static const Color cyan = Color(0xFF00D4FF);
  static const Color teal = Color(0xFF00E5C7);
  static const Color violet = Color(0xFF7B61FF);
  static const Color indigo = Color(0xFF6366F1);
  static const Color purple = Color(0xFFA855F7);

  // Premium — gold
  static const Color gold = Color(0xFFFFD700);
  static const Color amber = Color(0xFFFFB020);
  static const Color orange = Color(0xFFFF6B35);

  // Status
  static const Color emerald = Color(0xFF00E676);
  static const Color danger = Color(0xFFFF3B5C);
  static const Color live = Color(0xFFFF2D55);

  // Glass borders
  static const Color white04 = Color(0x0AFFFFFF);
  static const Color white07 = Color(0x12FFFFFF);
  static const Color white10 = Color(0x1AFFFFFF);
  static const Color white14 = Color(0x24FFFFFF);
  static const Color white20 = Color(0x33FFFFFF);

  // Text
  static const Color textPrimary = Color(0xFFF0F4FF);
  static const Color textSecondary = Color(0xFF8B95B0);
  static const Color textMuted = Color(0xFF5A6478);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyan, teal],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, cyan],
  );

  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gold, orange],
  );

  static const LinearGradient heroOverlay = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Color(0xEE010208), Color(0x99010208), Color(0x00010208)],
    stops: [0.0, 0.45, 1.0],
  );

  static const LinearGradient cardOverlay = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Color(0xDD010208), Color(0x66010208), Colors.transparent],
    stops: [0.0, 0.5, 1.0],
  );

  // Blur presets
  static ImageFilter blur16 = ImageFilter.blur(sigmaX: 16, sigmaY: 16);
  static ImageFilter blur24 = ImageFilter.blur(sigmaX: 24, sigmaY: 24);
  static ImageFilter blur32 = ImageFilter.blur(sigmaX: 32, sigmaY: 32);

  static TextStyle get displayLarge => GoogleFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: textPrimary,
        letterSpacing: -0.8,
        height: 1.1,
      );

  static TextStyle get displayMedium => GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: textPrimary,
        letterSpacing: -0.5,
        height: 1.15,
      );

  static TextStyle get titleLarge => GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.2,
      );

  static TextStyle get titleMedium => GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      );

  static TextStyle get bodyMedium => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: textSecondary,
        height: 1.45,
      );

  static TextStyle get labelSmall => GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: textMuted,
        letterSpacing: 0.6,
      );

  static ThemeData build() {
    final base = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData.dark().textTheme,
    );
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: cyan,
        secondary: violet,
        surface: surface,
        error: danger,
      ),
      textTheme: base.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cyan,
          foregroundColor: background,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle: GoogleFonts.plusJakartaSans(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: cyan,
        linearTrackColor: white07,
      ),
    );
  }

  static BoxDecoration glass({
    BorderRadius? radius,
    Color? color,
    Border? border,
    List<BoxShadow>? shadow,
    Gradient? gradient,
  }) {
    return BoxDecoration(
      color: gradient == null ? (color ?? panel) : null,
      gradient: gradient,
      borderRadius: radius ?? BorderRadius.circular(20),
      border: border ?? Border.all(color: white07),
      boxShadow: shadow ??
          [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 32,
              offset: const Offset(0, 16),
              spreadRadius: -8,
            ),
          ],
    );
  }

  static BoxDecoration glowBorder({
    required BorderRadius radius,
    Color glowColor = cyan,
    double glowOpacity = 0.35,
  }) {
    return BoxDecoration(
      borderRadius: radius,
      border: Border.all(color: glowColor.withValues(alpha: 0.4)),
      boxShadow: [
        BoxShadow(
          color: glowColor.withValues(alpha: glowOpacity),
          blurRadius: 20,
          spreadRadius: -4,
        ),
      ],
    );
  }
}
