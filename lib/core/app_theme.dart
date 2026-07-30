import 'package:flutter/material.dart';

/// Every colour in this file is a step from the project's validated data-viz
/// palette. The categorical slots (used only by [ExpenseCategory]) were checked
/// with the palette validator in both modes:
///
///   light  surface #fcfcfb -> lightness band PASS, chroma PASS,
///          adjacent CVD dE 9.1 PASS, normal-vision dE 19.6 PASS,
///          contrast WARN for aqua/yellow/magenta -> relief is satisfied
///          because every category is rendered with an icon, a text label and
///          a visible amount, plus the full table view on the Expenses tab.
///   dark   surface #1a1a19 -> every check PASS.
///
/// Do not invent new hues: a 9th categorical colour is indistinguishable from
/// an existing slot under colour-vision deficiency.
abstract final class AppColors {
  // Surfaces / chrome.
  static const lightPage = Color(0xFFF9F9F7);
  static const lightSurface = Color(0xFFFCFCFB);
  static const lightSurfaceAlt = Color(0xFFF1F1EE);
  static const darkPage = Color(0xFF0D0D0D);
  static const darkSurface = Color(0xFF1A1A19);
  static const darkSurfaceAlt = Color(0xFF232322);

  // Ink.
  static const lightInk = Color(0xFF0B0B0B);
  static const lightInkSecondary = Color(0xFF52514E);
  static const darkInk = Color(0xFFFFFFFF);
  static const darkInkSecondary = Color(0xFFC3C2B7);
  static const inkMuted = Color(0xFF898781);

  // Lines.
  static const lightGrid = Color(0xFFE1E0D9);
  static const darkGrid = Color(0xFF2C2C2A);
  static const lightBaseline = Color(0xFFC3C2B7);
  static const darkBaseline = Color(0xFF383835);

  // Series hue: categorical slot 1 (blue) + its sequential ramp. Reserved for
  // magnitude marks (trend bars, share meters) so it never doubles as a
  // category identity colour.
  static const seriesLight = Color(0xFF2A78D6); // ramp 450
  static const seriesDark = Color(0xFF3987E5); // ramp 400
  static const seriesDeEmphasisLight = Color(0xFF9EC5F4); // ramp 200
  static const seriesDeEmphasisDark = Color(0xFF184F95); // ramp 600
  static const seriesTrackLight = Color(0xFFCDE2FB); // ramp 100
  static const seriesTrackDark = Color(0xFF0D366B); // ramp 700

  // Status scale (fixed, never themed, always shipped with an icon + label).
  static const good = Color(0xFF0CA30C);
  static const critical = Color(0xFFD03B3B);
  static const successTextLight = Color(0xFF006300);
  static const successTextDark = Color(0xFF0CA30C);
}

/// Mode-aware chart + chrome roles, resolved once per theme.
@immutable
class VizColors extends ThemeExtension<VizColors> {
  const VizColors({
    required this.page,
    required this.surface,
    required this.surfaceAlt,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkMuted,
    required this.grid,
    required this.baseline,
    required this.hairline,
    required this.series,
    required this.seriesDeEmphasis,
    required this.seriesTrack,
    required this.good,
    required this.critical,
    required this.successText,
  });

  static const light = VizColors(
    page: AppColors.lightPage,
    surface: AppColors.lightSurface,
    surfaceAlt: AppColors.lightSurfaceAlt,
    inkPrimary: AppColors.lightInk,
    inkSecondary: AppColors.lightInkSecondary,
    inkMuted: AppColors.inkMuted,
    grid: AppColors.lightGrid,
    baseline: AppColors.lightBaseline,
    hairline: Color(0x1A0B0B0B),
    series: AppColors.seriesLight,
    seriesDeEmphasis: AppColors.seriesDeEmphasisLight,
    seriesTrack: AppColors.seriesTrackLight,
    good: AppColors.good,
    critical: AppColors.critical,
    successText: AppColors.successTextLight,
  );

  static const dark = VizColors(
    page: AppColors.darkPage,
    surface: AppColors.darkSurface,
    surfaceAlt: AppColors.darkSurfaceAlt,
    inkPrimary: AppColors.darkInk,
    inkSecondary: AppColors.darkInkSecondary,
    inkMuted: AppColors.inkMuted,
    grid: AppColors.darkGrid,
    baseline: AppColors.darkBaseline,
    hairline: Color(0x1AFFFFFF),
    series: AppColors.seriesDark,
    seriesDeEmphasis: AppColors.seriesDeEmphasisDark,
    seriesTrack: AppColors.seriesTrackDark,
    good: AppColors.good,
    critical: AppColors.critical,
    successText: AppColors.successTextDark,
  );

  final Color page;
  final Color surface;
  final Color surfaceAlt;
  final Color inkPrimary;
  final Color inkSecondary;
  final Color inkMuted;
  final Color grid;
  final Color baseline;
  final Color hairline;
  final Color series;
  final Color seriesDeEmphasis;
  final Color seriesTrack;
  final Color good;
  final Color critical;
  final Color successText;

  @override
  VizColors copyWith({
    Color? page,
    Color? surface,
    Color? surfaceAlt,
    Color? inkPrimary,
    Color? inkSecondary,
    Color? inkMuted,
    Color? grid,
    Color? baseline,
    Color? hairline,
    Color? series,
    Color? seriesDeEmphasis,
    Color? seriesTrack,
    Color? good,
    Color? critical,
    Color? successText,
  }) {
    return VizColors(
      page: page ?? this.page,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      inkPrimary: inkPrimary ?? this.inkPrimary,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkMuted: inkMuted ?? this.inkMuted,
      grid: grid ?? this.grid,
      baseline: baseline ?? this.baseline,
      hairline: hairline ?? this.hairline,
      series: series ?? this.series,
      seriesDeEmphasis: seriesDeEmphasis ?? this.seriesDeEmphasis,
      seriesTrack: seriesTrack ?? this.seriesTrack,
      good: good ?? this.good,
      critical: critical ?? this.critical,
      successText: successText ?? this.successText,
    );
  }

  @override
  VizColors lerp(ThemeExtension<VizColors>? other, double t) {
    if (other is! VizColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return VizColors(
      page: mix(page, other.page),
      surface: mix(surface, other.surface),
      surfaceAlt: mix(surfaceAlt, other.surfaceAlt),
      inkPrimary: mix(inkPrimary, other.inkPrimary),
      inkSecondary: mix(inkSecondary, other.inkSecondary),
      inkMuted: mix(inkMuted, other.inkMuted),
      grid: mix(grid, other.grid),
      baseline: mix(baseline, other.baseline),
      hairline: mix(hairline, other.hairline),
      series: mix(series, other.series),
      seriesDeEmphasis: mix(seriesDeEmphasis, other.seriesDeEmphasis),
      seriesTrack: mix(seriesTrack, other.seriesTrack),
      good: mix(good, other.good),
      critical: mix(critical, other.critical),
      successText: mix(successText, other.successText),
    );
  }
}

/// Layout constants, so spacing stays on one scale.
abstract final class AppSizes {
  static const gutter = 20.0;
  static const cardRadius = 22.0;
  static const chipRadius = 14.0;
  static const cardPadding = 18.0;
  static const gap = 14.0;
}

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final viz = isDark ? VizColors.dark : VizColors.light;
  final base = ThemeData(brightness: brightness, useMaterial3: true);

  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.seriesLight,
        brightness: brightness,
      ).copyWith(
        primary: viz.series,
        onPrimary: Colors.white,
        surface: viz.surface,
        onSurface: viz.inkPrimary,
        error: AppColors.critical,
        onError: Colors.white,
        outlineVariant: viz.hairline,
      );

  final text = base.textTheme
      .apply(bodyColor: viz.inkPrimary, displayColor: viz.inkPrimary)
      .copyWith(
        // The hero figure and stat values stay in the system sans with
        // proportional figures; tabular figures are reserved for axis ticks
        // and list columns.
        displaySmall: base.textTheme.displaySmall?.copyWith(
          fontSize: 48,
          height: 1.05,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.4,
          color: viz.inkPrimary,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: viz.inkPrimary,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: viz.inkPrimary,
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          color: viz.inkMuted,
          letterSpacing: 0.4,
          fontWeight: FontWeight.w500,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(color: viz.inkSecondary),
      );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: viz.page,
    canvasColor: viz.page,
    dividerColor: viz.hairline,
    extensions: <ThemeExtension<dynamic>>[viz],
    textTheme: text,
    iconTheme: IconThemeData(color: viz.inkSecondary, size: 22),
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: viz.page,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleMedium,
      iconTheme: IconThemeData(color: viz.inkSecondary),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: viz.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: viz.baseline,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? AppColors.lightSurfaceAlt : AppColors.darkSurface,
      contentTextStyle: TextStyle(
        color: isDark ? AppColors.lightInk : AppColors.darkInk,
        fontSize: 14,
      ),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: viz.surfaceAlt,
      hintStyle: TextStyle(color: viz.inkMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.chipRadius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.chipRadius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.chipRadius),
        borderSide: BorderSide(color: viz.series, width: 1.5),
      ),
    ),
  );
}

extension VizThemeAccess on BuildContext {
  VizColors get viz => Theme.of(this).extension<VizColors>() ?? VizColors.light;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}
