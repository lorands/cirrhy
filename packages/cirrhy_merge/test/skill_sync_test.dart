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

import 'dart:io';

import 'package:test/test.dart';

/// The cirrhy-report skill (.claude/skills/cirrhy-report) bundles copies of
/// the schema and the agent guide so a user can hand an agent just their
/// cirrhy.json and a prompt. Copies drift; this test is the tether. When it
/// fails, re-copy from doc/ — that direction, always: doc/ is canonical, the
/// schema-sync test in provenance_test.dart ties it to the codec.
void main() {
  const canonical = 'doc';
  const bundled = '../../.claude/skills/cirrhy-report/references';

  for (final name in ['cirrhy-document.schema.json', 'llms.md']) {
    test('$name is bundled verbatim in the cirrhy-report skill', () {
      expect(
        File('$bundled/$name').readAsStringSync(),
        File('$canonical/$name').readAsStringSync(),
        reason:
            'cp packages/cirrhy_merge/doc/$name '
            '.claude/skills/cirrhy-report/references/$name',
      );
    });
  }
}
