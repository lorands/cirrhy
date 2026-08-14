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

/// The rename dialog behind the pencil icon on the client (C2) and project
/// (C3) detail screens: a single text field prefilled with [currentName].
/// Returns the trimmed new name, or null if cancelled or left blank.
Future<String?> showRenameDialog(
  BuildContext context, {
  required String currentName,
}) async {
  final value = await showDialog<String>(
    context: context,
    builder: (dialogContext) => _RenameDialog(currentName: currentName),
  );
  return (value == null || value.isEmpty) ? null : value;
}

/// Owns the [TextEditingController] itself, disposing it from its own
/// [State.dispose] rather than from the caller's `showDialog` continuation.
/// That continuation runs as soon as the route is popped, which is *before*
/// the dialog's exit transition finishes animating it out of the tree — a
/// controller disposed there is used-after-dispose on the next frame.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.currentName});

  final String currentName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.currentName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.renameAction),
      content: TextField(
        key: const Key('renameDialogField'),
        controller: _controller,
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.saveAction),
        ),
      ],
    );
  }
}
