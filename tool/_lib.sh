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

# Shared plumbing for the build and run scripts. Source it, do not run it.
#
# Every target-*.sh is a thin wrapper: parse the mode, guard the host, call
# flutter. Every host-*.sh just calls the target scripts it can. All the
# argument handling, host detection and reporting lives here so the wrappers
# stay readable.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/app"

# flutter build resolves lib/main.dart relative to the working directory, so
# every command has to run from app/, never the workspace root.
cd "$APP_DIR"

if [[ -t 1 ]]; then
  BOLD=$'\e[1m'; RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; DIM=$'\e[2m'; OFF=$'\e[0m'
else
  BOLD=''; RED=''; GREEN=''; YELLOW=''; DIM=''; OFF=''
fi

say()  { printf '%s==>%s %s\n' "$BOLD" "$OFF" "$*"; }
warn() { printf '%s==>%s %s\n' "$YELLOW" "$OFF" "$*" >&2; }
die()  { printf '%s==>%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

# Mode defaults to debug: nothing in this repo is signed yet, so --release
# fails outright on iOS and quietly debug-signs on Android. See tool/README.md.
MODE=debug
EXTRA_ARGS=()

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --debug|--profile|--release) MODE="${1#--}" ;;
      -h|--help)
        cat <<EOF
usage: $(basename "$0") [--debug|--profile|--release] [-- <extra flutter args>]

  --debug     default; no signing needed on any target
  --profile   release-ish build with tracing left in, for performance work
  --release   needs signing configured for Android and iOS

Anything after -- is passed through to flutter untouched, e.g.
  $(basename "$0") --release -- --split-per-abi
EOF
        exit 0 ;;
      --) shift; EXTRA_ARGS+=("$@"); break ;;
      *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
  done
}

host_os() {
  case "$(uname -s)" in
    Linux)   echo linux ;;
    Darwin)  echo macos ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *)       echo unknown ;;
  esac
}

# Targets whose toolchain only exists on one host. Android is deliberately
# absent — it builds anywhere the SDK is installed.
require_host() {
  local needed="$1" target="$2" actual
  actual="$(host_os)"
  if [[ "$actual" != "$needed" ]]; then
    # Deliberately not "cannot be built" — the run-*.sh scripts share this.
    die "the $target target needs a $needed host (this is $actual)"
  fi
}

require_flutter() {
  command -v flutter >/dev/null 2>&1 || die "flutter not on PATH"
}

# Resolves a glob to the one path that exists. The Linux bundle sits under an
# architecture directory (x64, arm64) that depends on the machine, so the
# scripts cannot hard-code it.
find_artifact() {
  local match
  for match in $1; do
    [[ -e "$APP_DIR/$match" ]] && { echo "$match"; return; }
  done
  echo "$1"
}

# Prints where the artefact landed, since flutter's own path is relative to
# app/ and easy to lose in the scrollback.
report() {
  local label="$1" path="$2"
  if [[ -e "$APP_DIR/$path" ]]; then
    printf '%s  ✓ %s%s  %s%s%s\n' "$GREEN" "$label" "$OFF" "$DIM" "$APP_DIR/$path" "$OFF"
  else
    printf '%s  ✓ %s%s\n' "$GREEN" "$label" "$OFF"
  fi
}

# --- device selection -------------------------------------------------------
#
# Shared by dev.sh and the run-*.sh scripts so there is one answer to "which
# device did you mean".

# Asks flutter for the machine-readable device list and picks the best match
# for a platform, preferring a physical device over an emulated one. Prints
# "<id>\t<name>\t<physical|emulated>", or nothing when there is no candidate.
pick_device() {
  python3 - "$1" <<'PY'
import json, subprocess, sys

want = sys.argv[1]
try:
    raw = subprocess.run(["flutter", "devices", "--machine"],
                         capture_output=True, text=True, timeout=180).stdout
except Exception:
    sys.exit(0)

start = raw.find("[")
if start < 0:
    sys.exit(0)
try:
    devices = json.loads(raw[start:])
except json.JSONDecodeError:
    sys.exit(0)

matches = [d for d in devices if d.get("targetPlatform", "").startswith(want)]
if not matches:
    sys.exit(0)

# False sorts before True, so a real phone is chosen over an emulator.
matches.sort(key=lambda d: bool(d.get("emulator")))
best = matches[0]
kind = "emulated" if best.get("emulator") else "physical"
print(f"{best['id']}\t{best.get('name', best['id'])}\t{kind}")
PY
}

# Boots the first emulator or simulator flutter knows about for a platform and
# waits for it to register. Only reached when nothing is physically attached.
boot_emulator() {
  local platform="$1" avd waited=0
  avd="$(flutter emulators 2>/dev/null | awk -F' *• *' -v p="$platform" \
        '$0 ~ ("• " p "$") {print $1; exit}')"
  [[ -n "$avd" ]] || return 1

  say "no $platform device attached — booting $avd"
  flutter emulators --launch "$avd" >/dev/null 2>&1 || return 1

  while (( waited < 180 )); do
    [[ -n "$(pick_device "$platform")" ]] && { echo >&2; return 0; }
    sleep 3; waited=$(( waited + 3 ))
    printf '.' >&2
  done
  echo >&2
  return 1
}

# pick_device, falling back to booting one. Prints the same tab-separated
# triple; fails only when there is no device and none could be started.
resolve_mobile_device() {
  local platform="$1" found
  found="$(pick_device "$platform" || true)"
  if [[ -z "$found" ]]; then
    boot_emulator "$platform" || return 1
    found="$(pick_device "$platform" || true)"
  fi
  [[ -n "$found" ]] || return 1
  printf '%s' "$found"
}

# --- run-*.sh ---------------------------------------------------------------

# The whole body of every run-*.sh. Guards the host, works out which device to
# talk to, then hands the terminal to flutter — unlike dev.sh this is a single
# run, so flutter keeps its own interactive console (r, R, q, and the rest).
start_frontend() {
  local platform="$1"; shift
  local device='' args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--device) [[ $# -ge 2 ]] || die "$1 needs a device id"; device="$2"; shift ;;
      -h|--help)
        cat <<EOF
usage: $(basename "$0") [--debug|--profile|--release] [-d <device>] [-- <extra flutter args>]

Starts the $platform frontend and hands you flutter's own console.

  -d, --device   run on a specific device id; see 'flutter devices'
                 defaults to the attached $platform device, preferring a
                 physical one, booting an emulator only if nothing is attached

To drive desktop and mobile together with one hot reload, use tool/dev.sh.
EOF
        exit 0 ;;
      *) args+=("$1") ;;
    esac
    shift
  done

  parse_args ${args[@]+"${args[@]}"}
  require_flutter

  case "$platform" in
    linux)   require_host linux   "Linux desktop"; device="${device:-linux}" ;;
    macos)   require_host macos   "macOS";         device="${device:-macos}" ;;
    windows) require_host windows "Windows";       device="${device:-windows}" ;;
    ios)     require_host macos   "iOS" ;;
    android) ;;
  esac

  if [[ -z "$device" ]]; then
    local found
    say "looking for an attached $platform device"
    found="$(resolve_mobile_device "$platform")" \
      || die "no $platform device attached and no emulator could be started"
    device="$(cut -f1 <<<"$found")"
    printf '    %s (%s)\n' "$(cut -f2 <<<"$found")" "$(cut -f3 <<<"$found")"
    if [[ "$platform" == "ios" && "$(cut -f3 <<<"$found")" == "physical" ]]; then
      say "a physical iPhone needs a signing team set in Xcode"
    fi
  fi

  say "flutter run -d $device --$MODE"
  exec flutter run -d "$device" "--$MODE" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
}

# --- host-*.sh support ------------------------------------------------------

HOST_RESULTS=()

# Runs one target script, recording success or failure instead of aborting, so
# one broken target does not hide the state of the others.
run_target() {
  local target="$1"; shift
  say "building $target"
  if "$REPO_ROOT/tool/target-$target.sh" "$@"; then
    HOST_RESULTS+=("ok $target")
  else
    HOST_RESULTS+=("FAILED $target")
  fi
  echo
}

skip_target() {
  HOST_RESULTS+=("skipped $1 — $2")
}

summarise() {
  local failed=0 line status name
  printf '%s──── summary ────%s\n' "$BOLD" "$OFF"
  for line in "${HOST_RESULTS[@]}"; do
    status="${line%% *}"; name="${line#* }"
    case "$status" in
      ok)      printf '%s  ✓%s %s\n' "$GREEN" "$OFF" "$name" ;;
      FAILED)  printf '%s  ✗%s %s\n' "$RED" "$OFF" "$name"; failed=1 ;;
      skipped) printf '%s  ·%s %s\n' "$DIM" "$OFF" "$name" ;;
    esac
  done
  return $failed
}
