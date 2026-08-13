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

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Exposes the semantic palette to widgets, so nothing reaches for a raw hex.
///
/// Read with `CirrhyTheme.of(context)`.
final class CirrhyTheme extends ThemeExtension<CirrhyTheme> {
  const CirrhyTheme({required this.colors});

  final CirrhyColors colors;

  static CirrhyColors of(BuildContext context) =>
      Theme.of(context).extension<CirrhyTheme>()!.colors;

  @override
  CirrhyTheme copyWith({CirrhyColors? colors}) =>
      CirrhyTheme(colors: colors ?? this.colors);

  /// Deliberately not interpolated. A half-way palette during a theme
  /// animation is never a palette anyone checked the contrast of, so the
  /// scheme snaps instead.
  @override
  CirrhyTheme lerp(ThemeExtension<CirrhyTheme>? other, double t) =>
      t < 0.5 ? this : (other as CirrhyTheme? ?? this);
}

ThemeData cirrhyLightTheme() => _build(CirrhyColors.light, Brightness.light);

ThemeData cirrhyDarkTheme() => _build(CirrhyColors.dark, Brightness.dark);

ThemeData _build(CirrhyColors c, Brightness brightness) {
  // Handed to the constructor rather than to copyWith, and that is
  // load-bearing. The constructor merges this over Typography's black/white
  // theme, so a role the design system does not map still comes out with a
  // colour. copyWith replaces the TextTheme wholesale, which leaves every
  // unmapped role — titleSmall, bodySmall, the rest — with a null colour; the
  // text then paints in the renderer's own default, which on the light theme
  // is white on a white ground. Invisible, and invisible only at runtime.
  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    textTheme: TextTheme(
      displayLarge: Type.timer.copyWith(color: c.textPrimary),
      headlineLarge: Type.h1.copyWith(color: c.textPrimary),
      headlineMedium: Type.h2.copyWith(color: c.textPrimary),
      headlineSmall: Type.h3.copyWith(color: c.textPrimary),
      bodyLarge: Type.bodyLarge.copyWith(color: c.textPrimary),
      bodyMedium: Type.body.copyWith(color: c.textPrimary),
      labelLarge: Type.label.copyWith(color: c.textPrimary),
      labelMedium: Type.label.copyWith(color: c.textSecondary),
      labelSmall: Type.caption.copyWith(color: c.textMuted),
    ),
  );

  return base.copyWith(
    extensions: [CirrhyTheme(colors: c)],
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: c.brand,
      onPrimary: c.textOnBrand,
      primaryContainer: c.brandSubtle,
      onPrimaryContainer: c.brandPressed,
      secondary: c.brandEmphasis,
      onSecondary: c.textOnBrand,
      error: c.danger,
      onError: c.textOnBrand,
      errorContainer: c.dangerSubtle,
      onErrorContainer: c.danger,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      outline: c.borderControl,
      outlineVariant: c.border,
    ),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.brand,
        foregroundColor: c.textOnBrand,
        textStyle: Type.body.copyWith(fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x5,
          vertical: Space.x3,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.md)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textPrimary,
        backgroundColor: c.surface,
        side: BorderSide(color: c.borderControl),
        textStyle: Type.body.copyWith(fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x5,
          vertical: Space.x3,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.md)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.brand,
        textStyle: Type.body.copyWith(fontWeight: FontWeight.w500),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.md)),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      hintStyle: Type.body.copyWith(color: c.textMuted),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.x4,
        vertical: Space.x3,
      ),
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        borderSide: BorderSide(color: c.borderControl),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        borderSide: BorderSide(color: c.borderControl),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        borderSide: BorderSide(color: c.focusRing, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        borderSide: BorderSide(color: c.danger),
      ),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Radii.lg)),
        side: BorderSide(color: c.border),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.subtle,
      labelStyle: Type.caption.copyWith(
        color: c.textSecondary,
        fontWeight: FontWeight.w500,
      ),
      side: BorderSide.none,
      shape: const StadiumBorder(),
    ),
  );
}
