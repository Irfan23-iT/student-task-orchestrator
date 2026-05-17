import 'package:flutter/material.dart';

import '../../core/app_theme.dart' as core_theme;

class AppTheme {
  static const scaffoldBackground = Color(0xFFF5F7FF);
  static const primary = Color(0xFF2B3D8A);
  static const error = Color(0xFFBA1A1A);

  static ThemeData light() => core_theme.RakanAppTheme.lightTheme;

  static ThemeData dark() => core_theme.RakanAppTheme.darkTheme;
}
