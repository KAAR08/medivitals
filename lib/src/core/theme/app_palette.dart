import 'package:flutter/material.dart';

abstract final class AppPalette {
  // Backgrounds
  static const Color background = Color(0xFFF4F6F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFAFBFC);

  // Text — obsidian to slate scale
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textOnBrand = Color(0xFFFFFFFF);

  // Brand — deep clinical teal-blue (muted, deliberate)
  static const Color brand = Color(0xFF1A5F73);
  static const Color brandMid = Color(0xFF2A8FA6);
  static const Color brandLight = Color(0xFFE6F4F8);
  static const Color brandSubtle = Color(0xFFCCEBF2);

  // Critical — reserved exclusively for physiological anomalies
  static const Color critical = Color(0xFFC8102E);
  static const Color criticalLight = Color(0xFFFEF2F2);
  static const Color criticalBorder = Color(0xFFFCA5A5);

  // Semantic states
  static const Color success = Color(0xFF059669);
  static const Color successLight = Color(0xFFECFDF5);
  static const Color warning = Color(0xFFD97706);
  static const Color warningLight = Color(0xFFFFFBEB);

  // Structure
  static const Color border = Color(0xFFE5E7EB);
  static const Color borderStrong = Color(0xFFD1D5DB);
  static const Color divider = Color(0xFFF3F4F6);

  // Chart series — distinct but not saturated
  static const Color chartHR = Color(0xFFE95B5B);
  static const Color chartSpO2 = Color(0xFF3B82F6);
  static const Color chartBP = Color(0xFF8B5CF6);
}
