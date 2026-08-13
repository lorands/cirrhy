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

import 'package:cirrhy/settings/document_location_preference.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const home = DocumentLocation(
  handle: '/home/u/Dropbox',
  label: '/home/u/Dropbox',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('DocumentLocationPreference', () {
    test('starts with nothing chosen', () async {
      final pref = await DocumentLocationPreference.load();
      expect(pref.location, isNull);
      expect(pref.isChosen, isFalse);
    });

    test('a choice survives a restart', () async {
      await (await DocumentLocationPreference.load()).set(home);

      final reloaded = await DocumentLocationPreference.load();
      expect(reloaded.location, home);
      expect(reloaded.isChosen, isTrue);
    });

    test('relocating replaces the previous folder', () async {
      final pref = await DocumentLocationPreference.load();
      await pref.set(home);
      const moved = DocumentLocation(handle: '/mnt/sync', label: '/mnt/sync');
      await pref.set(moved);

      expect((await DocumentLocationPreference.load()).location, moved);
    });

    // §4.4: a revoked or stale handle sends the user back to the picker. It
    // must not leave a "chosen but broken" state for every screen downstream
    // to carry.
    test('clearing goes back to nothing chosen', () async {
      final pref = await DocumentLocationPreference.load();
      await pref.set(home);
      await pref.clear();

      expect(pref.isChosen, isFalse);
      expect((await DocumentLocationPreference.load()).location, isNull);
    });

    test('a stored value that cannot be read is treated as unchosen', () async {
      // Never a crash on the way to the first frame: an unreadable preference
      // means "ask again", not "fail to start".
      SharedPreferences.setMockInitialValues({
        'settings.documentLocation': 'not json',
      });
      expect((await DocumentLocationPreference.load()).location, isNull);
    });

    test('notifies listeners when the folder changes', () async {
      final pref = await DocumentLocationPreference.load();
      var notified = 0;
      pref.addListener(() => notified++);

      await pref.set(home);
      await pref.set(home); // Same folder: nothing changed, nothing to notify.
      await pref.clear();

      expect(notified, 2);
    });
  });

  group('DocumentLocation', () {
    test('round-trips through storage', () {
      expect(DocumentLocation.tryParse(home.encode()), home);
    });

    test('rejects a value missing its handle', () {
      expect(DocumentLocation.tryParse('{"label":"Dropbox"}'), isNull);
    });

    test('keeps the handle out of its string form', () {
      // This ends up in logs and error messages, where a base64 bookmark blob
      // helps nobody.
      const apple = DocumentLocation(handle: 'Ym9va21hcms=', label: 'Cirrhy');
      expect(apple.toString(), isNot(contains('Ym9va21hcms')));
      expect(apple.toString(), contains('Cirrhy'));
    });
  });
}
