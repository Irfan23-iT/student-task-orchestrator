import 'package:flutter/material.dart';

class RakanAppTheme {
  static const Color midnight = Color(0xFF121212);
  static const Color midnightPurple = Color(0xFF1A1028);
  static const Color neonPurple = Color(0xFF8B5CF6);
  static const Color neonPurpleSoft = Color(0xFFB56CFF);
  static const Color amber = Color(0xFFFFC857);
  static const Color offWhite = Color(0xFFF7F4FB);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color darkCard = Color(0xFF1F1A27);
  static const Color darkText = Color(0xFF24212B);
  static const Color mutedLightText = Color(0xFF6B6578);
  static const Color mutedDarkText = Color(0xFFC9BED8);
  static const Color error = Color(0xFFFF5A5F);

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: offWhite,
    cardColor: lightCard,
    colorScheme: ColorScheme.fromSeed(
      seedColor: neonPurple,
      brightness: Brightness.light,
      primary: neonPurple,
      secondary: amber,
      surface: lightCard,
      error: error,
    ),
    textTheme: _textTheme(
      headline: darkText,
      body: darkText,
      muted: mutedLightText,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: offWhite,
      foregroundColor: darkText,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: darkText,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      iconTheme: IconThemeData(color: darkText),
    ),
    cardTheme: CardThemeData(
      color: lightCard,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightCard,
      labelStyle: const TextStyle(color: mutedLightText),
      hintStyle: const TextStyle(color: mutedLightText),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE1DCEB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: neonPurple, width: 1.6),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? amber : mutedLightText;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? neonPurple.withValues(alpha: 0.42)
            : mutedLightText.withValues(alpha: 0.24);
      }),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: midnight,
    cardColor: darkCard,
    colorScheme: ColorScheme.fromSeed(
      seedColor: neonPurple,
      brightness: Brightness.dark,
      primary: neonPurpleSoft,
      secondary: amber,
      surface: darkCard,
      error: error,
    ),
    textTheme: _textTheme(
      headline: Colors.white,
      body: Colors.white,
      muted: mutedDarkText,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: midnight,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      iconTheme: IconThemeData(color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: darkCard,
      elevation: 2,
      shadowColor: neonPurple.withValues(alpha: 0.24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF18141F),
      labelStyle: const TextStyle(color: mutedDarkText),
      hintStyle: const TextStyle(color: mutedDarkText),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF30283A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: neonPurpleSoft, width: 1.6),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? amber : mutedDarkText;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? neonPurple.withValues(alpha: 0.50)
            : mutedDarkText.withValues(alpha: 0.20);
      }),
    ),
  );

  static TextTheme _textTheme({
    required Color headline,
    required Color body,
    required Color muted,
  }) {
    return TextTheme(
      displaySmall: TextStyle(color: headline, fontWeight: FontWeight.w900),
      headlineMedium: TextStyle(color: headline, fontWeight: FontWeight.w800),
      headlineSmall: TextStyle(color: headline, fontWeight: FontWeight.w800),
      titleLarge: TextStyle(color: headline, fontWeight: FontWeight.w800),
      titleMedium: TextStyle(color: headline, fontWeight: FontWeight.w700),
      titleSmall: TextStyle(color: headline, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(color: body, fontWeight: FontWeight.w500),
      bodyMedium: TextStyle(color: body, fontWeight: FontWeight.w500),
      bodySmall: TextStyle(color: muted, fontWeight: FontWeight.w500),
      labelLarge: TextStyle(color: body, fontWeight: FontWeight.w700),
      labelMedium: TextStyle(color: muted, fontWeight: FontWeight.w700),
      labelSmall: TextStyle(color: muted, fontWeight: FontWeight.w700),
    );
  }
}
