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

// Host side of the screenshot run: receives each frame the on-device test
// captures and writes it where tool/gen_screenshots.sh expects it. Driven by
// that script, never run directly.

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final out = Platform.environment['CIRRHY_SHOT_DIR'] ?? 'build/screenshots';
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final file = File('$out/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      stdout.writeln('  wrote ${file.path} (${bytes.length ~/ 1024} KB)');
      return true;
    },
  );
}
