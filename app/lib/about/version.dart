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

/// The version shown on the About screen and in the Settings About section.
///
/// Mirrors the `version:` field in `pubspec.yaml`, without the build number
/// after the `+` — that number is a platform store artefact, not something a
/// user reads. `test/about/version_test.dart` reads `pubspec.yaml` off disk
/// and asserts the two agree, so a release that bumps one and forgets the
/// other fails the suite instead of shipping a stale number on screen.
const String appVersion = '0.2.3';
