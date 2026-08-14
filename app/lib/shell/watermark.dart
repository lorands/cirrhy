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

import '../theme/theme.dart';

/// The product's watermark: the mark, tinted and nearly invisible, sitting on
/// the canvas behind every tab's content.
///
/// This is the one piece of brand presence that never moves and never scrolls
/// away — it sits on the canvas layer, content is drawn over it, and it
/// ignores every pointer event because it is decoration, not a control.
class CirrhyWatermark extends StatelessWidget {
  const CirrhyWatermark({super.key, this.alignEnd = false});

  /// `false` is the phone placement: centered, high on the screen.
  /// `true` is the desktop placement: anchored low and to the right, clear of
  /// a left rail.
  final bool alignEnd;

  static const _assetPath = 'assets/logo/cirrhy-mark.png';

  @override
  Widget build(BuildContext context) {
    final brand = CirrhyTheme.of(context).brand;

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;

          if (alignEnd) {
            return Align(
              alignment: Alignment.bottomRight,
              child: _mark(brand, width: 420),
            );
          }

          final width = (size.width * 0.75).clamp(280.0, 420.0).toDouble();
          return Stack(
            children: [
              Positioned(
                top: size.height * 0.42,
                left: 0,
                right: 0,
                child: Center(child: _mark(brand, width: width)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _mark(Color brand, {required double width}) {
    return Opacity(
      opacity: 0.05,
      child: Image.asset(
        _assetPath,
        width: width,
        color: brand,
        colorBlendMode: BlendMode.srcIn,
      ),
    );
  }
}
