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
# wants. A --release build here is signed with debug keys until a signing
# config exists, so it installs but cannot be published.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

FORMAT=apk
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--aab" ]]; then FORMAT=appbundle; else ARGS+=("$arg"); fi
done
parse_args ${ARGS[@]+"${ARGS[@]}"}
require_flutter

[[ -n "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" || -d "$HOME/Android/Sdk" ]] \
  || warn "no Android SDK found; flutter will say where it looked"

if [[ "$MODE" == "release" ]]; then
  warn "release build with no signing config — debug-signed, not publishable"
fi

say "flutter build $FORMAT --$MODE"
flutter build "$FORMAT" "--$MODE" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}

if [[ "$FORMAT" == "apk" ]]; then
  report "android apk ($MODE)" "$(find_artifact "build/app/outputs/flutter-apk/app-$MODE.apk")"
else
  report "android aab ($MODE)" "$(find_artifact "build/app/outputs/bundle/${MODE}/app-$MODE.aab")"
fi
