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


# The engine suite and the app suite. The engine is the one that can lose user
# data, so it runs first and its failure is the one that matters.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

require_flutter

say "engine — packages/cirrhy_merge"
( cd "$REPO_ROOT/packages/cirrhy_merge" && dart test )

say "app"
( cd "$APP_DIR" && flutter test )
