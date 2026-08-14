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

import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

/// A small coloured dot next to a label on a subtle pill background.
///
/// Extracted from the timer screen (B1/B2), which uses it for the inert
/// "Select task" placeholder and the client/project chip on entries. The
/// start-timer sheet and task picker (B3/B4) reuse it verbatim for the task
/// selector, the chosen-task chip and the "Recent" quick-start chips — one
/// visual vocabulary for "a coloured thing with a name" everywhere it shows
/// up, rather than four near-identical copies.
class EntityChip extends StatelessWidget {
  const EntityChip({super.key, required this.label, required this.dotColor});

  final String label;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x3,
        vertical: Space.x1,
      ),
      decoration: BoxDecoration(
        color: colors.subtle,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: Space.x2),
          // Flexible, not bare: the chip hugs its label, but a long
          // "Client › Project" in a narrow entry row has to give way rather
          // than overflow the row it sits in.
          Flexible(
            child: Text(
              label,
              style: text.labelSmall?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The same chip, but tappable and with a selected state — the filter chips
/// on the report filters sheet (D2) and the presets on the custom range sheet
/// (D4).
///
/// Selected is carried by three things at once (a brand hairline, a brand
/// tint and a brand label), and the hairline is the load-bearing one. The
/// Penpot board tints the selected chip with a brand step the semantic token
/// set does not expose; the nearest one it does, `brandSubtle`, sits within a
/// couple of points of `subtle` — so tint alone would leave selected and
/// unselected chips looking identical.
class SelectableChip extends StatelessWidget {
  const SelectableChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dotColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Omitted for chips that name no coloured thing — the range presets.
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;
    final dot = dotColor;

    return Material(
      color: selected ? colors.brandSubtle : colors.subtle,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? colors.brand : Colors.transparent),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x3,
            vertical: Space.x2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: Space.x2),
              ],
              Flexible(
                child: Text(
                  label,
                  style: text.labelSmall?.copyWith(
                    color: selected ? colors.brandHover : colors.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Client › Project", or just the project name when it has no client. The
/// dot takes the project's own colour when it parses as `#RRGGBB`, and falls
/// back to the brand colour otherwise — an unset or malformed colour should
/// never mean an invisible dot.
class ProjectChip extends StatelessWidget {
  const ProjectChip({super.key, required this.project, this.client});

  final Project project;
  final Client? client;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final owner = client;
    final label = owner == null
        ? project.name
        : '${owner.name} › ${project.name}';
    return EntityChip(
      label: label,
      dotColor: parseProjectColor(project.color) ?? colors.brand,
    );
  }
}

/// The fixed set of colours a project can be assigned, for the swatch pickers
/// on the new-project sheet (C4) and the project detail screen (C3).
///
/// Starts with the brand green so a freshly created project defaults to it
/// without a separate "brand" special case. The rest are chosen to sit apart
/// from each other and from the brand on the colour wheel, so two projects
/// are never one glance away from looking like the same colour.
const projectColorPalette = <String>[
  '#0E9F6E', // brand green
  '#3B82F6', // blue
  '#F59E0B', // orange
  '#8B5CF6', // purple
  '#EC4899', // pink
  '#14B8A6', // teal
  '#6366F1', // indigo
  '#EF4444', // red
];

final _hexColor = RegExp(r'^#([0-9a-fA-F]{6})$');

/// Parses a project's `#RRGGBB` colour, or null for anything unset or
/// malformed. Callers fall back to a colour of their own — usually the brand
/// colour — rather than ever showing an invisible dot.
Color? parseProjectColor(String? hex) {
  final match = hex == null ? null : _hexColor.firstMatch(hex);
  if (match == null) return null;
  return Color(int.parse('FF${match.group(1)}', radix: 16));
}
