import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Backgrounds
  static const Color background = Color(0xFF090C10);
  static const Color surface = Color(0xFF131720);
  static const Color surfaceLight = Color(0xFF1C212D);
  static const Color surfaceCard = Color(0xFF181D27);
  
  // Accents
  static const Color primary = Color(0xFF00E5FF);      // Electric Cyan
  static const Color secondary = Color(0xFF7C4DFF);    // Neon Violet
  static const Color accentLive = Color(0xFFFF2A6D);    // Hot Pink / Red for LIVE tag
  static const Color accentGreen = Color(0xFF00E676);   // Emerald Green for Online/Success
  static const Color accentOrange = Color(0xFFFF9100);  // Bright Orange for Favorites
  
  // Text Colors
  static const Color textPrimary = Color(0xFFF0F6FC);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF586069);
  
  // Focus & Borders
  static const Color focusBorder = Color(0xFF00E5FF);
  static const Color cardBorder = Color(0xFF262C3A);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        onPrimary: Colors.black,
        onSecondary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceCard,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.cardBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceLight,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        const TextTheme(
          displayLarge: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
          titleLarge: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(color: AppColors.textPrimary),
          bodyMedium: TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
