import 'package:flutter/material.dart';

/// TetalDJ look: black stage, cyan deck A, magenta deck B (the logo's glow).
class SideDeckTheme {
  static const bg = Color(0xFF000000);
  static const panel = Color(0xFF101114);
  static const panelAlt = Color(0xFF1A1C22);
  static const stroke = Color(0xFF2A2D36);
  static const accentA = Color(0xFF2EE6FF);
  static const accentB = Color(0xFFFF2BD6);
  static const text = Color(0xFFF2F4F8);
  static const muted = Color(0xFF8A90A0);
  static const loop = Color(0xFF1DE9B6);
  static const danger = Color(0xFFFF3B30);
  static const fx = Color(0xFFFFB300);
  static const stems = Color(0xFF7CFF4A);

  /// Camelot wheel colours, index 0 = 1A/1B … 11 = 12A/12B.
  static const camelot = [
    Color(0xFF3EE0A0),
    Color(0xFF30D6C8),
    Color(0xFF34B8F0),
    Color(0xFF5C8CFF),
    Color(0xFF9C6CFF),
    Color(0xFFD65CFF),
    Color(0xFFFF5CC8),
    Color(0xFFFF5C7A),
    Color(0xFFFF7A4D),
    Color(0xFFFFA43C),
    Color(0xFFE6D23C),
    Color(0xFF9EE03C),
  ];

  static Color accent(int deck) => deck == 0 ? accentA : accentB;

  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accentA,
        brightness: Brightness.dark,
        surface: panel,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      dialogTheme: const DialogThemeData(backgroundColor: panel),
    );
  }
}
