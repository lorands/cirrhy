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

import 'theme/theme.dart';
import 'theme/tokens.dart';

void main() => runApp(const CirrhyApp());

class CirrhyApp extends StatelessWidget {
  const CirrhyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cirrhy',
      debugShowCheckedModeBanner: false,
      theme: cirrhyLightTheme(),
      darkTheme: cirrhyDarkTheme(),
      // Follows the OS. Both schemes are fully specified, so there is no
      // "unfinished" side to hide behind a forced default.
      themeMode: ThemeMode.system,
      home: const _Placeholder(),
    );
  }
}

/// Deliberately empty.
///
/// DESIGN.md §9: the storage engine is built first, standalone and headless,
/// because it is the part that can lose user data. Screens come after it, on
/// top of the design system in the Penpot file.
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.x8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Cirrhy', style: text.headlineLarge),
              const SizedBox(height: Space.x2),
              Text(
                'No UI yet — the merge engine comes first.',
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: Space.x6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.x3,
                  vertical: Space.x2,
                ),
                decoration: BoxDecoration(
                  color: colors.brandSubtle,
                  borderRadius: BorderRadius.circular(Radii.full),
                ),
                child: Text(
                  'package:cirrhy_merge',
                  style: text.labelSmall?.copyWith(color: colors.brand),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
