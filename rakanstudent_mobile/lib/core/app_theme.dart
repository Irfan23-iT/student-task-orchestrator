import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design system for RakanStudent.
///
/// Light theme: warm cream base, pure-white cards, soft-mint secondary
/// surfaces, and a vibrant lime accent.
/// Dark theme: warm charcoal base, dark-gray cards, dark-mint secondary
/// surfaces, and a slightly softened lime accent.
class RakanAppTheme {
  RakanAppTheme._();

  // ---- Light palette -------------------------------------------------------
  static const Color _lBackground = Color(0xFFF5F5ED); // warm cream
  static const Color _lSurface = Color(0xFFFFFFFF); // pure white
  static const Color _lSurfaceVariant = Color(0xFFE8F2E7); // soft mint
  static const Color _lPrimary = Color(0xFFCDEB40); // vibrant lime
  static const Color _lSecondary = Color(0xFFB3D236); // darker lime
  static const Color _lTertiary = Color(0xFF9EE2B8); // medium mint
  static const Color _lText = Color(0xFF1C1C1C); // near black
  static const Color _lMutedText = Color(0xFF7A7A7A); // medium gray
  static const Color _lOutline = Color(0x337A7A7A); // gray @20%

  // ---- Dark palette --------------------------------------------------------
  static const Color _dBackground = Color(0xFF13130F); // warm deep charcoal
  static const Color _dSurface = Color(0xFF1E1E18); // elevated card
  static const Color _dSurfaceVariant = Color(0xFF2A3024); // olive-mint card
  static const Color _dPrimary = Color(0xFFCDEB40); // vivid brand lime
  static const Color _dSecondary = Color(0xFFB3D236); // darker lime
  static const Color _dTertiary = Color(0xFF8FBF9C); // soft sage
  static const Color _dText = Color(0xFFF3F3EC); // warm off-white
  static const Color _dMutedText = Color(0xFF9E9E94); // warm gray
  static const Color _dOutline = Color(0x29FFFFFF); // light hairline ~16%

  // ---- Shared semantic -----------------------------------------------------
  static const Color _error = Color(0xFFE5484D);

  // ---- Shape tokens --------------------------------------------------------
  static const double radiusCard = 30; // structural cards 28-32
  static const double radiusPill = 50; // chips, buttons, nav
  static const double radiusInput = 28;

  /// Subtle elevation token used across the app.
  static List<BoxShadow> get softShadow => const [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static final ThemeData lightTheme = _buildTheme(
    brightness: Brightness.light,
    background: _lBackground,
    surface: _lSurface,
    surfaceVariant: _lSurfaceVariant,
    primary: _lPrimary,
    secondary: _lSecondary,
    tertiary: _lTertiary,
    text: _lText,
    mutedText: _lMutedText,
    outline: _lOutline,
    onPrimary: _lText,
  );

  static final ThemeData darkTheme = _buildTheme(
    brightness: Brightness.dark,
    background: _dBackground,
    surface: _dSurface,
    surfaceVariant: _dSurfaceVariant,
    primary: _dPrimary,
    secondary: _dSecondary,
    tertiary: _dTertiary,
    text: _dText,
    mutedText: _dMutedText,
    outline: _dOutline,
    onPrimary: const Color(0xFF1A1A14),
  );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceVariant,
    required Color primary,
    required Color secondary,
    required Color tertiary,
    required Color text,
    required Color mutedText,
    required Color outline,
    required Color onPrimary,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: surfaceVariant,
      onPrimaryContainer: text,
      secondary: secondary,
      onSecondary: onPrimary,
      secondaryContainer: surfaceVariant,
      onSecondaryContainer: text,
      tertiary: tertiary,
      onTertiary: onPrimary,
      tertiaryContainer: surfaceVariant,
      onTertiaryContainer: text,
      error: _error,
      onError: Colors.white,
      errorContainer: const Color(0xFFFFE3E3),
      onErrorContainer: const Color(0xFF8E1B1B),
      surface: surface,
      onSurface: text,
      surfaceContainerHighest: surfaceVariant,
      onSurfaceVariant: mutedText,
      outline: outline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: colorScheme,
      textTheme: _textTheme(headline: text, body: text, muted: mutedText),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.poppins(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: text),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shadowColor: const Color(0x0A000000),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: mutedText,
      ),
      chipTheme: _chipTheme(
        background: surfaceVariant,
        foreground: mutedText,
        selectedBackground: primary,
        selectedForeground: onPrimary,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        labelStyle: TextStyle(color: mutedText),
        hintStyle: TextStyle(color: mutedText),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusPill),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusPill),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: outline),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusPill),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: text,
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected) ? primary : mutedText;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? primary.withValues(alpha: 0.40)
              : mutedText.withValues(alpha: 0.24);
        }),
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1),
    );
  }

  static TextTheme _textTheme({
    required Color headline,
    required Color body,
    required Color muted,
  }) {
    final base = GoogleFonts.poppinsTextTheme();
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        color: headline,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      displayMedium: base.displayMedium?.copyWith(
        color: headline,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      displaySmall: base.displaySmall?.copyWith(
        color: headline,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        color: headline,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        color: headline,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        color: headline,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: base.titleLarge?.copyWith(
        color: headline,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.titleMedium?.copyWith(
        color: headline,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: base.titleSmall?.copyWith(
        color: headline,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        color: body,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        color: body,
        fontWeight: FontWeight.w500,
      ),
      bodySmall: base.bodySmall?.copyWith(
        color: muted,
        fontWeight: FontWeight.w500,
      ),
      labelLarge: base.labelLarge?.copyWith(
        color: body,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: base.labelMedium?.copyWith(
        color: muted,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: base.labelSmall?.copyWith(
        color: muted,
        fontWeight: FontWeight.w600,
      ),
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
      labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w600),
      secondaryLabelStyle: TextStyle(
        color: selectedForeground,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusPill),
      ),
    );
  }
}
