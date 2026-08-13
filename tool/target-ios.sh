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


# Builds iOS. macOS host only — it needs Xcode.
#
# Builds unsigned by default, which is all you need to prove the project
# compiles. Pass --codesign once a development team is configured; installing
# on a physical device requires it.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

CODESIGN=no
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--codesign" ]]; then CODESIGN=yes; else ARGS+=("$arg"); fi
done
parse_args ${ARGS[@]+"${ARGS[@]}"}
require_flutter
require_host macos "iOS"

SIGN_FLAG=(--no-codesign)
if [[ "$CODESIGN" == "yes" ]]; then
  SIGN_FLAG=()
  say "signing enabled — needs a development team in Xcode"
fi

say "flutter build ios --$MODE ${SIGN_FLAG[*]:-}"
flutter build ios "--$MODE" ${SIGN_FLAG[@]+"${SIGN_FLAG[@]}"} ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}

report "ios ($MODE)" "$(find_artifact "build/ios/iphoneos/Runner.app")"
