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

import '../l10n/generated/app_localizations.dart';
import '../theme/theme.dart';

/// The confirmation every path to deleting an entry goes through — the entry
/// editor's Delete button (B5), the timer list's per-row button on desktop
/// and its swipe-left on mobile. One dialog, so the warning about history
/// going with the entry never drifts between them.
///
/// Returns true only on an explicit confirmation; dismissing the dialog any
/// other way answers no.
Future<bool> confirmDeleteEntry(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final colors = CirrhyTheme.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.deleteEntryConfirmTitle),
      content: Text(l10n.deleteEntryConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancelAction),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: colors.danger),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.deleteAction),
        ),
      ],
    ),
  );
  return confirmed == true;
}
