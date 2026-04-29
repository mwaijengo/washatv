import 'dart:ui';

import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF03050A);
  static const Color panel = Color(0x730C0F1C);
  static const Color navPanel = Color(0xA6080A16);
  static const Color white07 = Color(0x12FFFFFF);
  static const Color white10 = Color(0x1AFFFFFF);
  static const Color white14 = Color(0x24FFFFFF);
  static const Color indigo = Color(0xFF6366F1);
  static const Color purple = Color(0xFFA855F7);
  static const Color amber = Color(0xFFFBBF24);
  static const Color orange = Color(0xFFF97316);
  static const Color emerald = Color(0xFF34D399);
  static const Color danger = Color(0xFFEF4444);

  static ThemeData build() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      fontFamily: 'Inter',
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: indigo,
        secondary: purple,
        surface: background,
      ),
    );
  }

  static BoxDecoration glass({
    BorderRadius? radius,
    Color? color,
    Border? border,
    List<BoxShadow>? shadow,
  }) {
    return BoxDecoration(
      color: color ?? panel,
      borderRadius: radius ?? BorderRadius.circular(24),
      border: border ?? Border.all(color: white07),
      boxShadow: shadow ??
          const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 35,
              offset: Offset(0, 20),
              spreadRadius: -10,
            ),
          ],
    );
  }

  static ImageFilter blur20 = ImageFilter.blur(sigmaX: 20, sigmaY: 20);
  static ImageFilter blur28 = ImageFilter.blur(sigmaX: 28, sigmaY: 28);
}
