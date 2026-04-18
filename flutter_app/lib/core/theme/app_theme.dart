import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

abstract class AppTheme {

  static TextTheme _buildTextTheme(Color primary, Color secondary, Color tertiary) {
    final base = GoogleFonts.interTextTheme();
    return base.copyWith(
      displayLarge:  base.displayLarge!.copyWith(color: primary,   fontWeight: FontWeight.w700, letterSpacing: -1.5),
      displayMedium: base.displayMedium!.copyWith(color: primary,   fontWeight: FontWeight.w700, letterSpacing: -0.5),
      displaySmall:  base.displaySmall!.copyWith(color: primary,   fontWeight: FontWeight.w600),
      headlineLarge: base.headlineLarge!.copyWith(color: primary,   fontWeight: FontWeight.w700, fontSize: 28),
      headlineMedium:base.headlineMedium!.copyWith(color: primary,  fontWeight: FontWeight.w600, fontSize: 22),
      headlineSmall: base.headlineSmall!.copyWith(color: primary,   fontWeight: FontWeight.w600, fontSize: 18),
      titleLarge:    base.titleLarge!.copyWith(color: primary,   fontWeight: FontWeight.w600, fontSize: 16),
      titleMedium:   base.titleMedium!.copyWith(color: primary,   fontWeight: FontWeight.w500, fontSize: 14),
      titleSmall:    base.titleSmall!.copyWith(color: secondary, fontWeight: FontWeight.w500, fontSize: 12),
      bodyLarge:     base.bodyLarge!.copyWith(color: primary,   fontSize: 15, height: 1.5),
      bodyMedium:    base.bodyMedium!.copyWith(color: secondary, fontSize: 13, height: 1.4),
      bodySmall:     base.bodySmall!.copyWith(color: tertiary,  fontSize: 12, height: 1.3),
      labelLarge:    base.labelLarge!.copyWith(color: primary,   fontWeight: FontWeight.w600, fontSize: 14),
      labelMedium:   base.labelMedium!.copyWith(color: secondary, fontWeight: FontWeight.w500, fontSize: 12),
      labelSmall:    base.labelSmall!.copyWith(color: tertiary,  fontWeight: FontWeight.w400, fontSize: 11),
    );
  }

  // ── Dark Theme ───────────────────────────────────────────────────────────
  static final ThemeData dark = ThemeData(
    useMaterial3:     true,
    brightness:       Brightness.dark,
    scaffoldBackgroundColor: AppColors.darkBg,

    colorScheme: const ColorScheme.dark(
      primary:    AppColors.accentOrange,
      secondary:  AppColors.accentPink,
      surface:    AppColors.darkSurface,
      error:      AppColors.error,
      onPrimary:  Colors.white,
      onSecondary:Colors.white,
      onSurface:  AppColors.textPrimary,
    ),

    textTheme: _buildTextTheme(
      AppColors.textPrimary,
      AppColors.textSecondary,
      AppColors.textTertiary,
    ),

    appBarTheme: AppBarTheme(
      backgroundColor:    AppColors.darkBg,
      surfaceTintColor:   Colors.transparent,
      elevation:          0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.inter(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkSurface,
      selectedItemColor:   AppColors.accentOrange,
      unselectedItemColor: AppColors.textSecondary,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
    ),

    cardTheme: CardTheme(
      color:     AppColors.darkCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled:      true,
      fillColor:   AppColors.darkElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.darkBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accentOrange, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accentOrange,
        foregroundColor: Colors.white,
        elevation:       0,
        padding:         const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accentOrange,
        side: const BorderSide(color: AppColors.accentOrange),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentOrange,
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor:    AppColors.darkElevated,
      selectedColor:      AppColors.accentOrange.withOpacity(0.15),
      side: const BorderSide(color: AppColors.darkBorder),
      labelStyle: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),

    dividerTheme: const DividerThemeData(
      color: AppColors.darkDivider,
      thickness: 1,
      space: 1,
    ),

    iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 22),

    listTileTheme: const ListTileThemeData(
      textColor:  AppColors.textPrimary,
      iconColor:  AppColors.textSecondary,
      tileColor:  Colors.transparent,
    ),

    sliderTheme: const SliderThemeData(
      activeTrackColor:   AppColors.accentOrange,
      inactiveTrackColor: AppColors.darkElevated,
      thumbColor:         AppColors.accentOrange,
      overlayColor:       Color(0x33FF6B35),
      trackHeight:        3,
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color:            AppColors.accentOrange,
      linearTrackColor: AppColors.darkDivider,
    ),

    dialogTheme: DialogTheme(
      backgroundColor: AppColors.darkCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.darkElevated,
      contentTextStyle: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.accentOrange : AppColors.textSecondary),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? AppColors.accentOrange.withOpacity(0.4)
              : AppColors.darkDivider),
    ),

    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS:     CupertinoPageTransitionsBuilder(),
      },
    ),
  );

  // ── Light Theme (mirrors dark but inverted surfaces) ─────────────────────
  static final ThemeData light = dark.copyWith(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.lightBg,
    colorScheme: const ColorScheme.light(
      primary:    AppColors.accentOrange,
      secondary:  AppColors.accentPink,
      surface:    AppColors.lightSurface,
      error:      AppColors.error,
      onPrimary:  Colors.white,
      onSecondary:Colors.white,
      onSurface:  AppColors.textLightPrimary,
    ),
    textTheme: _buildTextTheme(
      AppColors.textLightPrimary,
      AppColors.textLightSecondary,
      AppColors.textLightTertiary,
    ),
    appBarTheme: dark.appBarTheme.copyWith(
      backgroundColor: AppColors.lightSurface,
      systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
    ),
    cardTheme: dark.cardTheme.copyWith(color: AppColors.lightCard),
  );
}
