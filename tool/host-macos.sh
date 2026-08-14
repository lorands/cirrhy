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


# Everything a macOS host can build: macOS, iOS and Android. This is the only
# host that can produce all three Apple-adjacent targets, so it is the one that
# has to run before any release.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

require_flutter
[[ "$(host_os)" == "macos" ]] || die "this is host-macos.sh but the host is $(host_os)"

run_target macos "$@"
run_target ios "$@"
run_target android "$@"
skip_target linux   "needs a Linux host"
skip_target windows "needs a Windows host"

summarise
