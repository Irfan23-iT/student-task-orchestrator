import 'package:flutter/material.dart';

class AppTheme {
  static const scaffoldBackground = Color(0xFFF5F5F7);
  static const primary = Color(0xFF2F628F);
  static const error = Color(0xFFFF3B30);

  static ThemeData light() {
    return ThemeData(
      scaffoldBackgroundColor: scaffoldBackground,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        error: error,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      useMaterial3: true,
    );
  }
}
