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


# Everything a Windows host can build: the Windows desktop app and Android.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

require_flutter
[[ "$(host_os)" == "windows" ]] || die "this is host-windows.sh but the host is $(host_os)"

run_target windows "$@"
run_target android "$@"
skip_target linux "needs a Linux host"
skip_target macos "needs a macOS host"
skip_target ios   "needs a macOS host"

summarise
