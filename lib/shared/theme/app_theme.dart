import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system for the app — replaces the Phase 0-9 default
/// `ColorScheme.fromSeed` placeholder. Style: "Data-Dense Dashboard"
/// (navy/slate + a single blue accent, Plus Jakarta Sans, minimal
/// padding, flat surfaces over heavy elevation) — the Stripe/Linear/
/// Notion-level polish the original brief called for in Section 19
/// ("Design System") but Phases 0-9 never actually built, only
/// described. Desktop/web-first: dense by default, not a mobile layout
/// stretched wide.
class AppColors {
  AppColors._();

  static const primary = Color(0xFF0F172A); // slate-900
  static const onPrimary = Color(0xFFFFFFFF);
  static const secondary = Color(0xFF334155); // slate-700
  static const accent = Color(0xFF0369A1); // sky-700 — the one CTA color
  static const background = Color(0xFFF8FAFC); // slate-50
  static const foreground = Color(0xFF020617); // slate-950
  static const muted = Color(0xFFE8ECF1);
  static const border = Color(0xFFE2E8F0); // slate-200
  static const destructive = Color(0xFFDC2626);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);

  // Dark mode: desaturated/lighter tonal variants, not a raw inversion —
  // see the skill's `color-dark-mode` rule.
  static const darkBackground = Color(0xFF0B1220);
  static const darkSurface = Color(0xFF111827);
  static const darkBorder = Color(0xFF1F2937);
  static const darkForeground = Color(0xFFE2E8F0);
}

/// 4px-increment spacing scale — use these instead of ad-hoc `EdgeInsets`
/// values, so every screen shares the same rhythm.
class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = isDark
        ? ColorScheme.fromSeed(
            seedColor: AppColors.accent,
            brightness: Brightness.dark,
            surface: AppColors.darkSurface,
            onSurface: AppColors.darkForeground,
          )
        : ColorScheme.fromSeed(
            seedColor: AppColors.accent,
            brightness: Brightness.light,
            primary: AppColors.primary,
            surface: Colors.white,
            onSurface: AppColors.foreground,
          );

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(
      isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    ).copyWith(
      // Tabular figures for any data column/price — see skill's
      // `number-tabular` rule. Applied to body text broadly since most
      // of this app's body text *is* financial figures.
      bodyMedium: GoogleFonts.plusJakartaSans(
        fontFeatures: const [FontFeature.tabularFigures()],
        color: isDark ? AppColors.darkForeground : AppColors.foreground,
      ),
    );

    final borderColor = isDark ? AppColors.darkBorder : AppColors.border;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      textTheme: textTheme,
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,

      // Flat surfaces with a hairline border instead of heavy drop
      // shadows — the "Data-Dense Dashboard" style's signature look.
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderColor),
        ),
        margin: EdgeInsets.zero,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        foregroundColor: isDark ? AppColors.darkForeground : AppColors.foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        shape: Border(bottom: BorderSide(color: borderColor)),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        indicatorColor: AppColors.accent.withValues(alpha: 0.12),
        selectedIconTheme: const IconThemeData(color: AppColors.accent),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.accent,
          fontWeight: FontWeight.w600,
        ),
        unselectedIconTheme: IconThemeData(color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
        ),
      ),

      dividerTheme: DividerThemeData(color: borderColor, thickness: 1, space: 1),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkBackground : AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        titleTextStyle: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.darkBackground : AppColors.muted,
        side: BorderSide(color: borderColor),
        labelStyle: textTheme.labelMedium,
      ),

      dataTableTheme: DataTableThemeData(
        headingTextStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        dataTextStyle: textTheme.bodyMedium,
        dividerThickness: 1,
      ),
    );
  }
}
