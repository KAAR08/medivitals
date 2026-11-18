import 'package:flutter/material.dart';
import 'app_palette.dart';

/// Custom ThemeExtension for semantic color roles.
/// Supports light mode now, dark mode by creating a separate extension instance.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textOnBrand,
    required this.brand,
    required this.brandMid,
    required this.brandLight,
    required this.brandSubtle,
    required this.critical,
    required this.criticalLight,
    required this.criticalBorder,
    required this.success,
    required this.successLight,
    required this.warning,
    required this.warningLight,
    required this.border,
    required this.borderStrong,
    required this.divider,
    required this.chartHR,
    required this.chartSpO2,
    required this.chartBP,
  });

  // Backgrounds
  final Color background;
  final Color surface;
  final Color surfaceElevated;

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textOnBrand;

  // Brand
  final Color brand;
  final Color brandMid;
  final Color brandLight;
  final Color brandSubtle;

  // Critical (anomalies)
  final Color critical;
  final Color criticalLight;
  final Color criticalBorder;

  // Semantic states
  final Color success;
  final Color successLight;
  final Color warning;
  final Color warningLight;

  // Structure
  final Color border;
  final Color borderStrong;
  final Color divider;

  // Charts
  final Color chartHR;
  final Color chartSpO2;
  final Color chartBP;

  /// Light mode color scheme
  static const AppColors light = AppColors(
    background: AppPalette.background,
    surface: AppPalette.surface,
    surfaceElevated: AppPalette.surfaceElevated,
    textPrimary: AppPalette.textPrimary,
    textSecondary: AppPalette.textSecondary,
    textTertiary: AppPalette.textTertiary,
    textOnBrand: AppPalette.textOnBrand,
    brand: AppPalette.brand,
    brandMid: AppPalette.brandMid,
    brandLight: AppPalette.brandLight,
    brandSubtle: AppPalette.brandSubtle,
    critical: AppPalette.critical,
    criticalLight: AppPalette.criticalLight,
    criticalBorder: AppPalette.criticalBorder,
    success: AppPalette.success,
    successLight: AppPalette.successLight,
    warning: AppPalette.warning,
    warningLight: AppPalette.warningLight,
    border: AppPalette.border,
    borderStrong: AppPalette.borderStrong,
    divider: AppPalette.divider,
    chartHR: AppPalette.chartHR,
    chartSpO2: AppPalette.chartSpO2,
    chartBP: AppPalette.chartBP,
  );

  static const AppColors dark = AppColors(
    background: Color(0xFF0F1419),
    surface: Color(0xFF1A1F26),
    surfaceElevated: Color(0xFF252C35),
    textPrimary: Color(0xFFF5F7FA),
    textSecondary: Color(0xFFA8B0BA),
    textTertiary: Color(0xFF6F7785),
    textOnBrand: Color(0xFFFFFFFF),
    brand: Color(0xFF2A8FA6),
    brandMid: Color(0xFF3BA8C2),
    brandLight: Color(0xFF1A3D4D),
    brandSubtle: Color(0xFF0F2A35),
    critical: Color(0xFFFF6B6B),
    criticalLight: Color(0xFF2D1014),
    criticalBorder: Color(0xFF7A3D3D),
    success: Color(0xFF51CF66),
    successLight: Color(0xFF1B3D2E),
    warning: Color(0xFFFFA94D),
    warningLight: Color(0xFF3D2C14),
    border: Color(0xFF3A4250),
    borderStrong: Color(0xFF2F3844),
    divider: Color(0xFF252C35),
    chartHR: Color(0xFFFF7A7A),
    chartSpO2: Color(0xFF4A9EFF),
    chartBP: Color(0xFFA78BFA),
  );

  @override
  ThemeExtension<AppColors> copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textOnBrand,
    Color? brand,
    Color? brandMid,
    Color? brandLight,
    Color? brandSubtle,
    Color? critical,
    Color? criticalLight,
    Color? criticalBorder,
    Color? success,
    Color? successLight,
    Color? warning,
    Color? warningLight,
    Color? border,
    Color? borderStrong,
    Color? divider,
    Color? chartHR,
    Color? chartSpO2,
    Color? chartBP,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textOnBrand: textOnBrand ?? this.textOnBrand,
      brand: brand ?? this.brand,
      brandMid: brandMid ?? this.brandMid,
      brandLight: brandLight ?? this.brandLight,
      brandSubtle: brandSubtle ?? this.brandSubtle,
      critical: critical ?? this.critical,
      criticalLight: criticalLight ?? this.criticalLight,
      criticalBorder: criticalBorder ?? this.criticalBorder,
      success: success ?? this.success,
      successLight: successLight ?? this.successLight,
      warning: warning ?? this.warning,
      warningLight: warningLight ?? this.warningLight,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      divider: divider ?? this.divider,
      chartHR: chartHR ?? this.chartHR,
      chartSpO2: chartSpO2 ?? this.chartSpO2,
      chartBP: chartBP ?? this.chartBP,
    );
  }

  @override
  ThemeExtension<AppColors> lerp(
    ThemeExtension<AppColors>? other,
    double t,
  ) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t) ?? background,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t) ??
          surfaceElevated,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textTertiary:
          Color.lerp(textTertiary, other.textTertiary, t) ?? textTertiary,
      textOnBrand: Color.lerp(textOnBrand, other.textOnBrand, t) ?? textOnBrand,
      brand: Color.lerp(brand, other.brand, t) ?? brand,
      brandMid: Color.lerp(brandMid, other.brandMid, t) ?? brandMid,
      brandLight: Color.lerp(brandLight, other.brandLight, t) ?? brandLight,
      brandSubtle: Color.lerp(brandSubtle, other.brandSubtle, t) ?? brandSubtle,
      critical: Color.lerp(critical, other.critical, t) ?? critical,
      criticalLight:
          Color.lerp(criticalLight, other.criticalLight, t) ?? criticalLight,
      criticalBorder:
          Color.lerp(criticalBorder, other.criticalBorder, t) ?? criticalBorder,
      success: Color.lerp(success, other.success, t) ?? success,
      successLight:
          Color.lerp(successLight, other.successLight, t) ?? successLight,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      warningLight:
          Color.lerp(warningLight, other.warningLight, t) ?? warningLight,
      border: Color.lerp(border, other.border, t) ?? border,
      borderStrong:
          Color.lerp(borderStrong, other.borderStrong, t) ?? borderStrong,
      divider: Color.lerp(divider, other.divider, t) ?? divider,
      chartHR: Color.lerp(chartHR, other.chartHR, t) ?? chartHR,
      chartSpO2: Color.lerp(chartSpO2, other.chartSpO2, t) ?? chartSpO2,
      chartBP: Color.lerp(chartBP, other.chartBP, t) ?? chartBP,
    );
  }
}

/// Extension on BuildContext for convenient color access
extension AppColorsX on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;

  /// A card: separated from the page by its fill, not an outline. In light
  /// mode white-on-near-white needs a soft shadow to read as a surface.
  BoxDecoration card({double radius = 14, Color? color}) {
    final dark = Theme.of(this).brightness == Brightness.dark;
    return BoxDecoration(
      color: color ?? colors.surface,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: dark
          ? null
          : [
              BoxShadow(
                  color: const Color(0xFF0F1419).fade(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 2))
            ],
    );
  }
}

/// SDK-neutral translucency helper. `withOpacity` is deprecated on newer
/// Flutter versions and `withValues` doesn't exist on older ones;
/// `withAlpha` works on both.
extension ColorFade on Color {
  Color fade(double opacity) =>
      withAlpha((opacity.clamp(0.0, 1.0) * 255).round());
}
