import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  /// Inter, bundled in assets/fonts (SIL Open Font License): the app looks
  /// the same offline and never fetches fonts at runtime.
  static const fontFamily = 'Inter';

  static TextStyle _inter({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    final textTheme = base.textTheme.apply(fontFamily: fontFamily).copyWith(
          displayLarge: _inter(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
              letterSpacing: -0.5),
          displayMedium: _inter(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
              letterSpacing: -0.3),
          headlineLarge: _inter(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
              letterSpacing: -0.2),
          headlineMedium: _inter(
              fontSize: 20, fontWeight: FontWeight.w600, color: c.textPrimary),
          headlineSmall: _inter(
              fontSize: 18, fontWeight: FontWeight.w600, color: c.textPrimary),
          titleLarge: _inter(
              fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary),
          titleMedium: _inter(
              fontSize: 14, fontWeight: FontWeight.w500, color: c.textPrimary),
          titleSmall: _inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: c.textSecondary),
          bodyLarge: _inter(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: c.textPrimary,
              height: 1.6),
          bodyMedium: _inter(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: c.textPrimary,
              height: 1.5),
          bodySmall: _inter(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: c.textSecondary,
              height: 1.4),
          labelLarge: _inter(
              fontSize: 14, fontWeight: FontWeight.w500, color: c.textPrimary),
          labelMedium: _inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: c.textSecondary),
          labelSmall: _inter(
              fontSize: 11, fontWeight: FontWeight.w400, color: c.textTertiary),
        );

    final colorScheme =
        (isDark ? const ColorScheme.dark() : const ColorScheme.light())
            .copyWith(
      primary: c.brand,
      onPrimary: c.textOnBrand,
      primaryContainer: c.brandLight,
      onPrimaryContainer: isDark ? c.textPrimary : c.brand,
      secondary: c.brandMid,
      onSecondary: c.textOnBrand,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surfaceElevated,
      error: c.critical,
      onError: c.textOnBrand,
      outline: c.border,
      outlineVariant: c.borderStrong,
    );

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: fontFamily),
      extensions: <ThemeExtension<dynamic>>[c],
      colorScheme: colorScheme,
      scaffoldBackgroundColor: c.background,
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        shadowColor: c.border,
        centerTitle: false,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: _inter(
            fontSize: 18, fontWeight: FontWeight.w600, color: c.textPrimary),
      ),
      cardTheme: CardTheme(
        color: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.brand, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.critical)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.critical, width: 1.5)),
        hintStyle: _inter(fontSize: 14, color: c.textTertiary),
        labelStyle: _inter(fontSize: 14, color: c.textSecondary),
        errorStyle: _inter(fontSize: 12, color: c.critical),
        floatingLabelStyle:
            _inter(fontSize: 13, color: c.brand, fontWeight: FontWeight.w500),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: c.textOnBrand,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: _inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.brand,
          side: BorderSide(color: c.brand),
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: _inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? c.brandMid : c.brand,
          textStyle: _inter(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? (isDark ? c.brand.fade(0.35) : c.brandLight)
                  : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? c.textPrimary
                  : c.textSecondary),
          side: WidgetStatePropertyAll(BorderSide(color: c.border)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: isDark ? c.brand.fade(0.35) : c.brandLight,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 24,
              color: states.contains(WidgetState.selected)
                  ? (isDark ? c.textPrimary : c.brand)
                  : c.textTertiary,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => _inter(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? c.textPrimary
                  : c.textTertiary,
            )),
      ),
      // The bottom bar's look, for the side rail used on wide screens.
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        elevation: 0,
        indicatorColor: isDark ? c.brand.fade(0.35) : c.brandLight,
        selectedIconTheme:
            IconThemeData(size: 24, color: isDark ? c.textPrimary : c.brand),
        unselectedIconTheme: IconThemeData(size: 24, color: c.textTertiary),
        selectedLabelTextStyle: _inter(
            fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary),
        unselectedLabelTextStyle: _inter(
            fontSize: 12, fontWeight: FontWeight.w500, color: c.textTertiary),
      ),
      dividerTheme: DividerThemeData(color: c.divider, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceElevated,
        selectedColor: c.brandLight,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: _inter(fontSize: 13, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.brand),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
