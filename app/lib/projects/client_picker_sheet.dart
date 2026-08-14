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

/// What the client chooser hands back: the chosen client, or explicitly no
/// client. Distinct from the sheet returning null outright, which means
/// dismissed without choosing anything — exactly the shape [TaskChoice] and
/// the task picker (B4) already use for the same "explicit none" problem.
class ClientChoice {
  const ClientChoice(this.clientId);

  /// Null means "No client" was chosen on purpose, not that nothing was.
  final String? clientId;
}

/// Opens the client chooser: non-archived clients, a "No client" row and a
/// way to create a client on the spot. Shared by the project detail screen's
/// CLIENT row (C3) and the new-project sheet's CLIENT row (C4) — one sheet,
/// one set of strings, rather than two near-identical pickers.
Future<ClientChoice?> showClientPicker(
  BuildContext context,
  DocumentSession session,
) {
  return showModalBottomSheet<ClientChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ClientPickerSheet(session: session),
  );
}

class _ClientPickerSheet extends StatefulWidget {
  const _ClientPickerSheet({required this.session});

  final DocumentSession session;

  @override
  State<_ClientPickerSheet> createState() => _ClientPickerSheetState();
}

class _ClientPickerSheetState extends State<_ClientPickerSheet> {
  void _choose(String? clientId) =>
      Navigator.of(context).pop(ClientChoice(clientId));

  Future<void> _createClient(String name) async {
    final now = DateTime.now().toUtc();
    final client = Client(id: uuidV4(), modified: now, name: name);
    await widget.session.put(client);
    if (mounted) _choose(client.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final clients =
        widget.session.document.clients.values
            .where((c) => !c.archived)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: FractionallySizedBox(
        heightFactor: 0.7,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(Radii.xl),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: Space.x3),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(Radii.full),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.x6,
                    Space.x4,
                    Space.x6,
                    Space.x2,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.chooseClientTitle,
                      style: text.headlineSmall,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      Space.x6,
                      0,
                      Space.x6,
                      Space.x4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ClientRow(
                          key: const Key('clientPickerNoClient'),
                          label: l10n.noClientLabel,
                          muted: true,
                          onTap: () => _choose(null),
                        ),
                        for (final client in clients)
                          _ClientRow(
                            label: client.name,
                            onTap: () => _choose(client.id),
                          ),
                        const SizedBox(height: Space.x2),
                        Divider(color: colors.border, height: 1),
                        const SizedBox(height: Space.x3),
                        _NewClientRow(onCreate: _createClient),
                      ],
                    ),
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

class _ClientRow extends StatelessWidget {
  const _ClientRow({
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
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x3),
          child: Text(
            label,
            style: muted
                ? text.bodyMedium?.copyWith(color: colors.textMuted)
                : text.bodyMedium,
          ),
        ),
      ),
    );
  }
}

/// "New client…", which turns into an inline text field on tap — the same
/// shape as the task picker's own new-task row.
class _NewClientRow extends StatefulWidget {
  const _NewClientRow({required this.onCreate});

  final Future<void> Function(String name) onCreate;

  @override
  State<_NewClientRow> createState() => _NewClientRowState();
}

class _NewClientRowState extends State<_NewClientRow> {
  bool _editing = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    widget.onCreate(name);
  }

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    if (!_editing) {
      return InkWell(
        onTap: () => setState(() => _editing = true),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 18, color: colors.brand),
              const SizedBox(width: Space.x2),
              Text(
                l10n.newClientAction,
                style: text.bodyMedium?.copyWith(
                  color: colors.brand,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('clientPickerNewClientField'),
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(hintText: l10n.clientNameHint),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: Space.x2),
        IconButton(
          icon: const Icon(Icons.check),
          onPressed: _submit,
          color: colors.brand,
        ),
      ],
    );
  }
}
