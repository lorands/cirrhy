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

import 'package:cirrhy/main.dart';
import 'package:cirrhy/theme/theme.dart';
import 'package:cirrhy/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(const CirrhyApp());
    expect(find.text('Cirrhy'), findsOneWidget);
  });

  testWidgets('both schemes resolve the semantic palette', (tester) async {
    for (final (mode, expected) in [
      (ThemeMode.light, CirrhyColors.light),
      (ThemeMode.dark, CirrhyColors.dark),
    ]) {
      late CirrhyColors seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: cirrhyLightTheme(),
          darkTheme: cirrhyDarkTheme(),
          themeMode: mode,
          home: Builder(
            builder: (context) {
              seen = CirrhyTheme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // MaterialApp animates between themes, and CirrhyTheme.lerp deliberately
      // snaps at the midpoint rather than interpolating — a half-way palette is
      // never one anyone checked the contrast of. So settle before reading.
      await tester.pumpAndSettle();

      expect(seen.brand, expected.brand);
      expect(seen.textOnBrand, expected.textOnBrand);
    }
  });

  test('the light brand is the AA-safe step, not brand500', () {
    // White on brand500 measures 3.39:1 and fails AA for button labels, so the
    // semantic brand points one stop down. Guarding it here because the tempting
    // "fix" is to point it back at the prettier 500.
    expect(CirrhyColors.light.brand, CorePalette.brand600);
    expect(CirrhyColors.light.brandEmphasis, CorePalette.brand500);
  });

  test('dark puts near-black on the brand, not white', () {
    // White on brand400 is 2.60:1.
    expect(CirrhyColors.dark.textOnBrand, CorePalette.neutral950);
  });
}
