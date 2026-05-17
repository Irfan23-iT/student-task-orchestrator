import 'package:flutter/material.dart';

class RakanAppTheme {
  static const Color _lightPrimary = Color(0xFF2B3D8A);
  static const Color _darkPrimary = Color(0xFF6F8CFF);
  static const Color _lightBackground = Color(0xFFF5F7FF);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceVariant = Color(0xFFEFF3FF);
  static const Color _lightOutline = Color(0xFFDDE3F3);
  static const Color _lightText = Color(0xFF172033);
  static const Color _lightMutedText = Color(0xFF667085);

  static const Color _darkBackground = Color(0xFF12121A);
  static const Color _darkSurface = Color(0xFF1E1E28);
  static const Color _darkSurfaceVariant = Color(0xFF292A36);
  static const Color _darkOutline = Color(0xFF3A3D4E);
  static const Color _darkText = Color(0xFFFFFFFF);
  static const Color _darkMutedText = Color(0xFFC8CEDA);

  static const Color _coral = Color(0xFFFF8A8A);
  static const Color _mint = Color(0xFF7DDDC3);
  static const Color _error = Color(0xFFBA1A1A);

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: _lightBackground,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: _lightPrimary,
      onPrimary: Colors.white,
      secondary: _coral,
      onSecondary: Color(0xFF421313),
      tertiary: _mint,
      onTertiary: Color(0xFF0C332A),
      error: _error,
      onError: Colors.white,
      errorContainer: Color(0xFFFFE3E3),
      onErrorContainer: Color(0xFF8E1B1B),
      primaryContainer: Color(0xFFE7EBFF),
      onPrimaryContainer: _lightPrimary,
      secondaryContainer: Color(0xFFFFE8E8),
      onSecondaryContainer: Color(0xFF7A2A2A),
      tertiaryContainer: Color(0xFFE4FBF5),
      onTertiaryContainer: Color(0xFF145345),
      surface: _lightSurface,
      onSurface: _lightText,
      surfaceContainerHighest: _lightSurfaceVariant,
      onSurfaceVariant: _lightMutedText,
      outline: _lightOutline,
    ),
    textTheme: _textTheme(
      headline: _lightText,
      body: _lightText,
      muted: _lightMutedText,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: _lightBackground,
      foregroundColor: _lightText,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: const TextStyle(
        color: _lightText,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      iconTheme: const IconThemeData(color: _lightText),
    ),
    cardTheme: CardThemeData(
      color: _lightSurface,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: _lightSurface,
      selectedItemColor: _lightPrimary,
      unselectedItemColor: _lightMutedText,
    ),
    chipTheme: _chipTheme(
      background: _lightSurfaceVariant,
      foreground: _lightMutedText,
      selectedBackground: Color(0xFFE7EBFF),
      selectedForeground: _lightPrimary,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _lightSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _lightSurface,
      labelStyle: const TextStyle(color: _lightMutedText),
      hintStyle: const TextStyle(color: _lightMutedText),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: _lightOutline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: _lightPrimary, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _lightPrimary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _lightPrimary,
        side: const BorderSide(color: _lightOutline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? _coral : _lightMutedText;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? _lightPrimary.withValues(alpha: 0.30)
            : _lightMutedText.withValues(alpha: 0.24);
      }),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _darkBackground,
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: _darkPrimary,
      onPrimary: Color(0xFF07133F),
      secondary: Color(0xFFFFA7A7),
      onSecondary: Color(0xFF4A1212),
      tertiary: Color(0xFF9AF2D8),
      onTertiary: Color(0xFF082F26),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF4D1B1F),
      onErrorContainer: Color(0xFFFFDAD6),
      primaryContainer: Color(0xFF25315F),
      onPrimaryContainer: Color(0xFFDDE4FF),
      secondaryContainer: Color(0xFF4B2A33),
      onSecondaryContainer: Color(0xFFFFD9DD),
      tertiaryContainer: Color(0xFF183D37),
      onTertiaryContainer: Color(0xFFC7FFF0),
      surface: _darkSurface,
      onSurface: _darkText,
      surfaceContainerHighest: _darkSurfaceVariant,
      onSurfaceVariant: _darkMutedText,
      outline: _darkOutline,
    ),
    textTheme: _textTheme(
      headline: _darkText,
      body: _darkText,
      muted: _darkMutedText,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: _darkBackground,
      foregroundColor: _darkText,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: const TextStyle(
        color: _darkText,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      iconTheme: const IconThemeData(color: _darkText),
    ),
    cardTheme: CardThemeData(
      color: _darkSurface,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: _darkSurface,
      selectedItemColor: _darkPrimary,
      unselectedItemColor: _darkMutedText,
    ),
    chipTheme: _chipTheme(
      background: _darkSurfaceVariant,
      foreground: _darkMutedText,
      selectedBackground: Color(0xFF25315F),
      selectedForeground: _darkPrimary,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _darkSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _darkSurfaceVariant,
      labelStyle: const TextStyle(color: _darkMutedText),
      hintStyle: const TextStyle(color: _darkMutedText),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: _darkOutline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: _darkPrimary, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _darkPrimary,
        foregroundColor: const Color(0xFF07133F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _darkPrimary,
        side: const BorderSide(color: _darkOutline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? _darkPrimary
            : _darkMutedText;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? _darkPrimary.withValues(alpha: 0.45)
            : _darkMutedText.withValues(alpha: 0.20);
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

  static ChipThemeData _chipTheme({
    required Color background,
    required Color foreground,
    required Color selectedBackground,
    required Color selectedForeground,
  }) {
    return ChipThemeData(
      backgroundColor: background,
      selectedColor: selectedBackground,
      disabledColor: background.withValues(alpha: 0.52),
      labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w700),
      secondaryLabelStyle: TextStyle(
        color: selectedForeground,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}
