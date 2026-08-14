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


# Static checks: the analyzer over the whole workspace, then formatting.
#
# Formatting is reported rather than enforced. app/lib/theme/tokens.dart is
# committed in a shape dart format disagrees with — its aligned colour tables
# read better than the formatter's output — so failing the build on it would
# only teach people to skip this script.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

require_flutter

say "analyze"
( cd "$REPO_ROOT" && flutter analyze )

say "format"
if ( cd "$REPO_ROOT" && dart format --output=none --set-exit-if-changed \
       packages app/lib app/test >/dev/null 2>&1 ); then
  printf '%s  ✓ formatted%s\n' "$GREEN" "$OFF"
else
  warn "files differ from dart format — run 'dart format packages app/lib app/test' to apply"
  ( cd "$REPO_ROOT" && dart format --output=none --show=changed \
      packages app/lib app/test 2>/dev/null | sed 's/^/    /' ) || true
fi
