import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seedColor = Color(0xFF275C82);

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
    scaffoldBackgroundColor: const Color(0xFFF5F8FB),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ),
  );
}
