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

import '../data/document_session.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/entity_chip.dart';
import 'client_picker_sheet.dart';
import 'color_swatch_row.dart';

/// Opens the new-project sheet (Penpot "09 · Screens & Flow", C4): a name
/// field, a client selector (via the shared client chooser) and a colour
/// swatch row, ending in a full-width Create button.
///
/// [initialClientId] preselects the client — the entry point from a client's
/// own "New project…" row (C2), where re-choosing it would be pointless.
Future<void> showNewProjectSheet(
  BuildContext context,
  DocumentSession session, {
  String? initialClientId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        _NewProjectSheet(session: session, initialClientId: initialClientId),
  );
}

class _NewProjectSheet extends StatefulWidget {
  const _NewProjectSheet({required this.session, this.initialClientId});

  final DocumentSession session;
  final String? initialClientId;

  @override
  State<_NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends State<_NewProjectSheet> {
  final _name = TextEditingController();
  String? _clientId;
  late String _color;

  @override
  void initState() {
    super.initState();
    _clientId = widget.initialClientId;
    _color = projectColorPalette.first;
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickClient() async {
    final choice = await showClientPicker(context, widget.session);
    if (choice != null && mounted) setState(() => _clientId = choice.clientId);
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final now = DateTime.now().toUtc();
    final project = Project(
      id: uuidV4(),
      modified: now,
      name: name,
      clientId: _clientId,
      locationChanged: now,
      color: _color,
    );
    final navigator = Navigator.of(context);
    await widget.session.put(project);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final client = widget.session.clientById(_clientId);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Radii.xl),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.x6,
              Space.x3,
              Space.x6,
              Space.x6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(Radii.full),
                    ),
                  ),
                ),
                const SizedBox(height: Space.x4),
                Text(l10n.newProjectTitle, style: text.headlineSmall),
                const SizedBox(height: Space.x5),
                _FieldLabel(l10n.nameLabel),
                const SizedBox(height: Space.x1),
                TextField(
                  key: const Key('newProjectNameField'),
                  controller: _name,
                  autofocus: true,
                  decoration: InputDecoration(hintText: l10n.projectNameHint),
                ),
                const SizedBox(height: Space.x5),
                _FieldLabel(l10n.clientLabel),
                const SizedBox(height: Space.x1),
                _SelectorRow(
                  key: const Key('newProjectClientSelector'),
                  label: client?.name ?? l10n.noClientLabel,
                  muted: client == null,
                  onTap: _pickClient,
                ),
                const SizedBox(height: Space.x5),
                _FieldLabel(l10n.colorLabel),
                const SizedBox(height: Space.x2),
                ColorSwatchRow(
                  selected: _color,
                  onSelect: (hex) => setState(() => _color = hex),
                ),
                const SizedBox(height: Space.x6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('createProjectButton'),
                    onPressed: _name.text.trim().isEmpty ? null : _create,
                    child: Text(l10n.createProjectAction),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: colors.textMuted),
    );
  }
}

class _SelectorRow extends StatelessWidget {
  const _SelectorRow({
    super.key,
    required this.label,
    required this.onTap,
    this.muted = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x4,
            vertical: Space.x3,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: colors.borderControl),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: muted
                      ? text.bodyLarge?.copyWith(color: colors.textMuted)
                      : text.bodyLarge,
                ),
              ),
              Icon(Icons.expand_more, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
