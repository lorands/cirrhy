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

// What the shipping Android build is allowed to ask the OS for.
//
// This is asserted rather than trusted because the Play Console's Data safety
// declaration is a statement Google holds the publisher to, and the one this
// project makes is absolute: no data collected, none shared, no network code.
// The strongest evidence for that claim is not the source — it is that the
// release manifest never requests INTERNET, so the shipped app cannot open a
// socket even if some future dependency tried to. A permission added here
// without a matching Data safety update turns a true declaration into a false
// one, so adding one should cost a failing test first.
//
// Scope, honestly: this reads the source manifests. The *merged* manifest can
// still gain permissions from a dependency, which only the built artifact
// shows — docs/release/play-store.md has the bundletool check to run against
// the .aab before an upload.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Everything the shipping build may request. Both entries earn their place
/// in the running-timer badge (CLAUDE.md): one to post the notification the
/// launcher dot rides on, one for the Huawei launchers that ignore dots.
const shippedPermissions = {
  'android.permission.POST_NOTIFICATIONS',
  'com.huawei.android.launcher.permission.CHANGE_BADGE',
};

Set<String> permissionsIn(File manifest) {
  expect(manifest.existsSync(), isTrue, reason: 'missing ${manifest.path}');
  return RegExp(
    r'<uses-permission\s+android:name="([^"]+)"',
  ).allMatches(manifest.readAsStringSync()).map((m) => m.group(1)!).toSet();
}

void main() {
  final main = File('android/app/src/main/AndroidManifest.xml');

  test('the shipping build requests exactly the permissions it needs', () {
    expect(permissionsIn(main), shippedPermissions);
  });

  test('the shipping build cannot reach the network', () {
    expect(
      permissionsIn(main),
      isNot(contains('android.permission.INTERNET')),
      reason:
          'Cirrhy declares "no data collected" to the Play Console and "no '
          'network code" to its users. Requesting INTERNET in the shipping '
          'manifest makes both of those statements need re-examining.',
    );
  });

  test('the development builds are the ones that carry INTERNET', () {
    // Not incidental — this is why the shipping manifest can stay clean. The
    // Flutter tool needs a socket for hot reload, so the template puts the
    // permission in the debug and profile manifests, where it is merged into
    // those variants alone. Someone "fixing" the inconsistency by hoisting it
    // into main would break the test above; this one explains where it went.
    for (final variant in ['debug', 'profile']) {
      expect(
        permissionsIn(File('android/app/src/$variant/AndroidManifest.xml')),
        contains('android.permission.INTERNET'),
        reason: '$variant needs it for hot reload',
      );
    }
  });

  test('no advertising ID', () {
    // Play asks about this one by name, and a dependency pulling it in is the
    // usual way an app that shows no ads ends up declaring that it does.
    expect(
      permissionsIn(main),
      isNot(contains('com.google.android.gms.permission.AD_ID')),
    );
  });

  test('the application ID is the one Play will pin forever', () {
    // Unlike almost everything else in a listing, this cannot be changed after
    // the first upload: on Play the applicationId *is* the app's identity, and
    // a new one is a new app with no users, no reviews and no install base.
    // DESIGN.md §7 is why Android keeps the plain reverse domain while the
    // Apple bundle ID carries the `app` suffix.
    final gradle = File('android/app/build.gradle.kts');
    expect(gradle.existsSync(), isTrue, reason: 'missing ${gradle.path}');
    expect(
      gradle.readAsStringSync(),
      contains('applicationId = "com.lorands.cirrhy"'),
    );
  });
}
