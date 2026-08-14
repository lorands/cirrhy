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

import 'package:cirrhy/about/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appVersion matches pubspec.yaml, without the build number', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'no version: field in pubspec.yaml');

    // versionName / build number, e.g. "0.1.0+1" — the part before '+' is
    // the only part a user should ever see on screen.
    final pubspecVersion = match!.group(1)!.split('+').first;

    expect(
      appVersion,
      pubspecVersion,
      reason:
          'lib/about/version.dart has drifted from pubspec.yaml — update '
          'appVersion to match',
    );
  });
}
