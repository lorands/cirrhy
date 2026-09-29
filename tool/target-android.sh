#!/usr/bin/env bash
# Copyright 2026 Lóránd Somogyi
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Builds Android. Runs on any host with the Android SDK installed, which is why
# it is the one target every host-*.sh includes.
#
# Produces an APK by default; pass --aab for the App Bundle the Play Console
# wants. A --release build is signed with the upload key that
# tool/android-signing.sh configured, and with debug keys when there is none —
# installable either way, publishable only in the first case. Which one you
# got is printed rather than assumed.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

FORMAT=apk
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--aab" ]]; then FORMAT=appbundle; else ARGS+=("$arg"); fi
done
parse_args ${ARGS[@]+"${ARGS[@]}"}
require_flutter

SDK="$(android_sdk)" || warn "no Android SDK found; flutter will say where it looked"

if [[ "$MODE" == "release" ]]; then
  report_android_signing

  # Flutter checks that a release *bundle* had its native libraries stripped,
  # and it runs apkanalyzer from the SDK's cmdline-tools to do it. With those
  # missing the check cannot run, so it reports "not stripped" and the build
  # fails — after Gradle has already succeeded and written the .aab — with a
  # message about debug symbols that never mentions cmdline-tools. Caught here
  # because the difference is a one-line install against three lost minutes
  # and a misdirected search.
  if [[ "$FORMAT" == "appbundle" && -n "${SDK:-}" ]] \
     && ! compgen -G "$SDK/cmdline-tools/*/bin/apkanalyzer" >/dev/null; then
    warn "the SDK has no cmdline-tools, so this build will fail at the last step"
    warn "claiming it could not strip debug symbols — install them in Android"
    warn "Studio (SDK Manager → SDK Tools → Android SDK Command-line Tools),"
    warn "or with sdkmanager \"cmdline-tools;latest\""
  fi
fi

say "flutter build $FORMAT --$MODE"
flutter build "$FORMAT" "--$MODE" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}

if [[ "$FORMAT" == "apk" ]]; then
  report "android apk ($MODE)" "$(find_artifact "build/app/outputs/flutter-apk/app-$MODE.apk")"
else
  report "android aab ($MODE)" "$(find_artifact "build/app/outputs/bundle/${MODE}/app-$MODE.aab")"
fi
