// Copyright 2026 Lóránd Somogyi
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// The design tokens, mirroring the Penpot library one-for-one.
///
/// Penpot holds the same three sets — `core`, `semantic.light`,
/// `semantic.dark` — and the same names. Keep them in step: the Penpot file is
/// where the design is decided, this file is where it is executed.
///
/// Contrast was measured, not assumed. Ratios noted below are against the
/// surface the value sits on; WCAG 2.1 AA wants 4.5:1 for text and 3:1 for
/// control boundaries and focus rings.
library;

import 'package:flutter/widgets.dart';

/// Primitives. Never referenced directly by a widget — go through
/// [CirrhyColors] so the theme can swap underneath.
abstract final class CorePalette {
  // Brand — deep emerald.
  static const brand50 = Color(0xFFE8F7F0);
  static const brand100 = Color(0xFFC7EBDC);
  static const brand200 = Color(0xFF9BDCC2);
  static const brand300 = Color(0xFF63C9A3);
  static const brand400 = Color(0xFF2FB588);
  static const brand500 = Color(0xFF0E9F6E);
  static const brand600 = Color(0xFF0B8560);
  static const brand700 = Color(0xFF047857);
  static const brand800 = Color(0xFF065F46);
  static const brand900 = Color(0xFF064E3B);

  // Accent — reserved for the running-timer state and nothing else.
  static const accent300 = Color(0xFF6EE7B7);
  static const accent400 = Color(0xFF34D399);
  static const accent500 = Color(0xFF10B981);

  // Neutrals, green-tinted so they never look cold beside the brand.
  static const neutral0 = Color(0xFFFFFFFF);
  static const neutral50 = Color(0xFFF6FAF8);
  static const neutral100 = Color(0xFFECF2EF);
  static const neutral200 = Color(0xFFDCE7E1);
  static const neutral300 = Color(0xFFC3D3CB);
  static const neutral400 = Color(0xFF9DB0A6);
  static const neutral450 = Color(0xFF7E9188); // control border, 3.34:1 on white
  static const neutral500 = Color(0xFF74857C);
  static const neutral550 = Color(0xFF667A70); // muted text, 4.58:1 on white
  static const neutral600 = Color(0xFF4A5B53);
  static const neutral700 = Color(0xFF33443C);
  static const neutral800 = Color(0xFF1C2C25);
  static const neutral900 = Color(0xFF0F1A16);
  static const neutral950 = Color(0xFF0B1512);

  // Dark-scheme surfaces. Dark separates depth by lightness, not by shadow.
  static const darkSurface = Color(0xFF121F1A);
  static const darkSubtle = Color(0xFF182822);
  static const darkOverlay = Color(0xFF1E332B);
  static const darkBorder = Color(0xFF223129);
  static const darkBorderStrong = Color(0xFF33473C);
  static const darkControlBorder = Color(0xFF557060); // 3.13:1 on darkSurface
  static const darkTextPrimary = Color(0xFFE8F0EC);
  static const darkTextSecondary = Color(0xFFA9BBB2);
  static const darkTextMuted = Color(0xFF7E9188);
  static const darkBrandSubtle = Color(0xFF0E2A20);
  static const darkDangerSubtle = Color(0xFF3B1A1A);
  static const darkWarningSubtle = Color(0xFF3A2A0E);
  static const darkInfoSubtle = Color(0xFF0B2E3D);

  // Status. Success is deliberately brand500 — two greens a shade apart would
  // read as a bug, not a distinction.
  static const danger = Color(0xFFDC2626);
  static const dangerSubtle = Color(0xFFFEE2E2);
  static const dangerDark = Color(0xFFF87171);
  static const warning = Color(0xFFD97706);
  static const warningSubtle = Color(0xFFFEF3C7);
  static const warningDark = Color(0xFFFBBF24);
  static const info = Color(0xFF0EA5E9);
  static const infoSubtle = Color(0xFFE0F2FE);
  static const infoDark = Color(0xFF38BDF8);
}

/// The semantic layer. Both schemes carry identical names, so no widget needs
/// to know which one is active.
final class CirrhyColors {
  const CirrhyColors({
    required this.canvas,
    required this.surface,
    required this.raised,
    required this.subtle,
    required this.inverse,
    required this.border,
    required this.borderStrong,
    required this.borderControl,
    required this.focusRing,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textInverse,
    required this.textOnBrand,
    required this.brand,
    required this.brandHover,
    required this.brandPressed,
    required this.brandSubtle,
    required this.brandEmphasis,
    required this.running,
    required this.danger,
    required this.dangerSubtle,
    required this.warning,
    required this.warningSubtle,
    required this.info,
    required this.infoSubtle,
  });

  /// `semantic.light`.
  static const light = CirrhyColors(
    canvas: CorePalette.neutral50,
    surface: CorePalette.neutral0,
    raised: CorePalette.neutral0,
    subtle: CorePalette.neutral100,
    inverse: CorePalette.neutral900,
    border: CorePalette.neutral200,
    borderStrong: CorePalette.neutral300,
    borderControl: CorePalette.neutral450,
    focusRing: CorePalette.brand600,
    textPrimary: CorePalette.neutral900,
    textSecondary: CorePalette.neutral600,
    textMuted: CorePalette.neutral550,
    textInverse: CorePalette.neutral0,
    textOnBrand: CorePalette.neutral0,
    // brand600, not brand500: white on brand500 is only 3.39:1 and fails AA.
    // brand500 survives as brandEmphasis, where no text sits on it.
    brand: CorePalette.brand600,
    brandHover: CorePalette.brand700,
    brandPressed: CorePalette.brand800,
    brandSubtle: CorePalette.brand50,
    brandEmphasis: CorePalette.brand500,
    running: CorePalette.accent400,
    danger: CorePalette.danger,
    dangerSubtle: CorePalette.dangerSubtle,
    warning: CorePalette.warning,
    warningSubtle: CorePalette.warningSubtle,
    info: CorePalette.info,
    infoSubtle: CorePalette.infoSubtle,
  );

  /// `semantic.dark`.
  ///
  /// The brand steps *up* rather than down, and near-black text sits on it —
  /// white on brand400 is 2.60:1 and fails badly. This is the one place the two
  /// schemes genuinely invert rather than just re-point.
  static const dark = CirrhyColors(
    canvas: CorePalette.neutral950,
    surface: CorePalette.darkSurface,
    raised: CorePalette.darkOverlay,
    subtle: CorePalette.darkSubtle,
    inverse: CorePalette.neutral50,
    border: CorePalette.darkBorder,
    borderStrong: CorePalette.darkBorderStrong,
    borderControl: CorePalette.darkControlBorder,
    focusRing: CorePalette.brand400,
    textPrimary: CorePalette.darkTextPrimary,
    textSecondary: CorePalette.darkTextSecondary,
    textMuted: CorePalette.darkTextMuted,
    textInverse: CorePalette.neutral900,
    textOnBrand: CorePalette.neutral950,
    brand: CorePalette.brand400,
    brandHover: CorePalette.brand300,
    brandPressed: CorePalette.brand500,
    brandSubtle: CorePalette.darkBrandSubtle,
    brandEmphasis: CorePalette.accent400,
    running: CorePalette.accent400,
    danger: CorePalette.dangerDark,
    dangerSubtle: CorePalette.darkDangerSubtle,
    warning: CorePalette.warningDark,
    warningSubtle: CorePalette.darkWarningSubtle,
    info: CorePalette.infoDark,
    infoSubtle: CorePalette.darkInfoSubtle,
  );

  final Color canvas;
  final Color surface;
  final Color raised;
  final Color subtle;
  final Color inverse;

  final Color border;
  final Color borderStrong;
  final Color borderControl;
  final Color focusRing;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textInverse;
  final Color textOnBrand;

  final Color brand;
  final Color brandHover;
  final Color brandPressed;
  final Color brandSubtle;

  /// Decorative only — dots, rails, the running marker. Never a text ground.
  final Color brandEmphasis;

  final Color running;
  final Color danger;
  final Color dangerSubtle;
  final Color warning;
  final Color warningSubtle;
  final Color info;
  final Color infoSubtle;
}

/// A strict 4px grid.
abstract final class Space {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;
  static const double x16 = 64;
}

/// Radii climb with surface size: controls sm/md, cards lg, sheets xl,
/// avatars and the run button full.
abstract final class Radii {
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;
  static const double full = 999;
}

/// Light-scheme elevation. Dark deliberately has no equivalent — it separates
/// surfaces by lightness, because a drop shadow on a dark ground says nothing.
abstract final class Elevation {
  static const List<BoxShadow> level1 = [
    BoxShadow(
      color: Color(0x0F0F1A16),
      offset: Offset(0, 1),
      blurRadius: 3,
    ),
  ];
  static const List<BoxShadow> level2 = [
    BoxShadow(
      color: Color(0x1A0F1A16),
      offset: Offset(0, 4),
      blurRadius: 12,
    ),
  ];
  static const List<BoxShadow> level3 = [
    BoxShadow(
      color: Color(0x240F1A16),
      offset: Offset(0, 12),
      blurRadius: 28,
    ),
  ];
}

/// The type scale.
///
/// Sizes, weights and line heights are the design decision and are fixed here.
/// The *families* are not yet bundled: the design specifies Inter for interface
/// text and JetBrains Mono for durations, but shipping them means adding the
/// TTFs under `app/assets/fonts/` and declaring them in pubspec.yaml. Until
/// then these resolve to the platform default, which is why [duration] sets
/// [FontFeature.tabularFigures] explicitly — without fixed-width digits the
/// running timer visibly jitters every second.
abstract final class Type {
  static const String? sansFamily = null; // 'Inter' once bundled
  static const String? monoFamily = null; // 'JetBrains Mono' once bundled

  static const h1 = TextStyle(
    fontFamily: sansFamily,
    fontSize: 28,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  );
  static const h2 = TextStyle(
    fontFamily: sansFamily,
    fontSize: 22,
    height: 1.27,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );
  static const h3 = TextStyle(
    fontFamily: sansFamily,
    fontSize: 18,
    height: 1.33,
    fontWeight: FontWeight.w600,
  );
  static const bodyLarge = TextStyle(
    fontFamily: sansFamily,
    fontSize: 16,
    height: 1.5,
  );
  static const body = TextStyle(
    fontFamily: sansFamily,
    fontSize: 14,
    height: 1.43,
  );
  static const label = TextStyle(
    fontFamily: sansFamily,
    fontSize: 13,
    height: 1.38,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );
  static const caption = TextStyle(
    fontFamily: sansFamily,
    fontSize: 12,
    height: 1.33,
    letterSpacing: 0.1,
  );

  /// The big readout on the timer card.
  static const timer = TextStyle(
    fontFamily: monoFamily,
    fontSize: 48,
    height: 1.05,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Durations in the entry list.
  static const duration = TextStyle(
    fontFamily: monoFamily,
    fontSize: 15,
    height: 1.33,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
