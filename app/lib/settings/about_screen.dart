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

import '../about/version.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';

const _markAsset = 'assets/logo/cirrhy-mark.png';

/// Penpot page "09 · Screens & Flow", screen E3.
///
/// Pushed from the Settings "About Cirrhy" row rather than folded into the
/// settings list itself — it is a destination, not another row of settings,
/// and a full screen is where the wordmark and the tagline get room to
/// breathe.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = CirrhyTheme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutCirrhy)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: ListView(
              padding: const EdgeInsets.all(Space.x6),
              children: [
                Image.asset(_markAsset, width: 72, height: 72),
                const SizedBox(height: Space.x4),
                Center(child: Text(l10n.appTitle, style: text.headlineLarge)),
                const SizedBox(height: Space.x1),
                Center(
                  child: Text(
                    l10n.versionLine(appVersion),
                    style: text.labelSmall?.copyWith(color: colors.textMuted),
                  ),
                ),
                const SizedBox(height: Space.x4),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Text(
                      l10n.aboutBody,
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Space.x8),
                Container(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(Radii.lg),
                    border: Border.all(color: colors.border),
                  ),
                  child: Column(
                    children: [
                      _AboutScreenRow(
                        label: l10n.licenseLabel,
                        trailing: 'Apache 2.0',
                        onTap: () => _showLicense(context),
                      ),
                      Divider(height: 1, color: colors.border),
                      _AboutScreenRow(
                        label: l10n.thirdPartyNotices,
                        // Flutter's own license page already lists every
                        // package's licence text, third-party ones included —
                        // there is no second destination to send this to.
                        onTap: () => _showLicense(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.x8),
                Center(
                  child: Text(
                    l10n.aboutTagline,
                    textAlign: TextAlign.center,
                    style: text.labelSmall?.copyWith(color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLicense(BuildContext context) => showLicensePage(
    context: context,
    applicationName: 'Cirrhy',
    applicationVersion: appVersion,
  );
}

class _AboutScreenRow extends StatelessWidget {
  const _AboutScreenRow({
    required this.label,
    this.trailing,
    required this.onTap,
  });

  final String label;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = CirrhyTheme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x4,
          vertical: Space.x3,
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: text.bodyMedium)),
            if (trailing != null) ...[
              Text(
                trailing!,
                style: text.labelSmall?.copyWith(color: colors.textMuted),
              ),
              const SizedBox(width: Space.x2),
            ],
            Icon(Icons.chevron_right, size: 18, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}
