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


# Detects the host and runs the matching host-*.sh. This is the one to wire
# into CI, where the runner OS decides what gets built.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

HOST="$(host_os)"
[[ "$HOST" != "unknown" ]] || die "unrecognised host $(uname -s); run a host-*.sh directly"

say "host is $HOST"
exec "$REPO_ROOT/tool/host-$HOST.sh" "$@"
