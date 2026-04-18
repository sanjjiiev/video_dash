import 'package:flutter/material.dart';

/// HUB 2.0 color system — premium dark palette with vibrant accents.
/// All colors are HSL-tuned for cohesion (not arbitrary hex values).
abstract class AppColors {

  // ── Brand gradient (used on hero elements, CTAs, progress bars) ──────────
  static const Color accentOrange = Color(0xFFFF6B35);
  static const Color accentPink   = Color(0xFFFF3B5C);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end:   Alignment.centerRight,
    colors: [accentOrange, accentPink],
  );

  static const LinearGradient brandGradientVertical = LinearGradient(
    begin: Alignment.topCenter,
    end:   Alignment.bottomCenter,
    colors: [accentOrange, accentPink],
  );

  // ── Dark Theme Surfaces ────────────────────────────────────────────────
  static const Color darkBg       = Color(0xFF080808);  // true dark
  static const Color darkSurface  = Color(0xFF111111);
  static const Color darkCard     = Color(0xFF1C1C1C);
  static const Color darkElevated = Color(0xFF242424);
  static const Color darkDivider  = Color(0xFF2A2A2A);
  static const Color darkBorder   = Color(0xFF333333);

  // ── Light Theme Surfaces ───────────────────────────────────────────────
  static const Color lightBg       = Color(0xFFF8F8F8);
  static const Color lightSurface  = Color(0xFFFFFFFF);
  static const Color lightCard     = Color(0xFFF2F2F2);
  static const Color lightElevated = Color(0xFFE8E8E8);
  static const Color lightDivider  = Color(0xFFE0E0E0);

  // ── Text ──────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFAAAAAA);
  static const Color textTertiary  = Color(0xFF666666);
  static const Color textDisabled  = Color(0xFF444444);

  static const Color textLightPrimary   = Color(0xFF0A0A0A);
  static const Color textLightSecondary = Color(0xFF555555);
  static const Color textLightTertiary  = Color(0xFF888888);

  // ── Semantic ──────────────────────────────────────────────────────────
  static const Color success = Color(0xFF2ECC71);
  static const Color warning = Color(0xFFF39C12);
  static const Color error   = Color(0xFFE74C3C);
  static const Color info    = Color(0xFF3498DB);

  // ── Like / Dislike ─────────────────────────────────────────────────────
  static const Color like    = Color(0xFF2196F3);
  static const Color dislike = Color(0xFFFF5252);

  // ── Live Badge ────────────────────────────────────────────────────────
  static const Color live = Color(0xFFFF3B3B);

  // ── Overlay (player controls background) ─────────────────────────────
  static const Color overlayDark  = Color(0xCC000000);
  static const Color overlayLight = Color(0x66000000);

  // ── Glassmorphism ─────────────────────────────────────────────────────
  static const Color glass     = Color(0x1AFFFFFF);
  static const Color glassBorder = Color(0x33FFFFFF);

  // ── Shimmer ───────────────────────────────────────────────────────────
  static const Color shimmerBase      = Color(0xFF1C1C1C);
  static const Color shimmerHighlight = Color(0xFF2A2A2A);

  // ── Channel avatar placeholder colors (cycle through these) ───────────
  static const List<Color> avatarColors = [
    Color(0xFFFF6B35), Color(0xFF3498DB), Color(0xFF2ECC71),
    Color(0xFF9B59B6), Color(0xFFF39C12), Color(0xFFE74C3C),
  ];
}
