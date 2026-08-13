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

# Runs the desktop and the mobile build side by side with one hot reload
# driving both, so a layout change can be judged on both outlines at once.
#
#   on Linux    Linux desktop + Android
#   on macOS    macOS desktop + iOS
#   on Windows  Windows desktop + Android
#
# A physically attached phone always wins over an emulator. If none is
# attached, the first available emulator or simulator is booted.
#
# `flutter run` has no multi-device mode worth relying on here — `-d all`
# takes whatever is plugged in, including Chrome. So this starts one run per
# device and drives both through the pid-file signals flutter documents:
# SIGUSR1 is hot reload, SIGUSR2 is hot restart. Keystrokes are read here and
# forwarded to both, which is why the two runs stay in lockstep.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DESKTOP_ONLY=no
MOBILE_ONLY=no
for arg in "$@"; do
  case "$arg" in
    --desktop-only) DESKTOP_ONLY=yes ;;
    --mobile-only)  MOBILE_ONLY=yes ;;
    -h|--help)
      cat <<EOF
usage: dev.sh [--desktop-only|--mobile-only]

Runs desktop and mobile together with a shared hot reload.

  r  hot reload both      R  hot restart both      q  quit
EOF
      exit 0 ;;
    *) die "unknown option: $arg (try --help)" ;;
  esac
done

require_flutter

HOST="$(host_os)"
case "$HOST" in
  linux)   DESKTOP=linux;   MOBILE_PLATFORM=android ;;
  macos)   DESKTOP=macos;   MOBILE_PLATFORM=ios ;;
  windows) DESKTOP=windows; MOBILE_PLATFORM=android ;;
  *) die "unrecognised host $(uname -s)" ;;
esac

# --- device discovery -------------------------------------------------------
#
# pick_device / resolve_mobile_device live in _lib.sh; the run-*.sh scripts
# select devices the same way.

MOBILE_ID=""
if [[ "$DESKTOP_ONLY" != "yes" ]]; then
  say "looking for a $MOBILE_PLATFORM device"
  FOUND="$(resolve_mobile_device "$MOBILE_PLATFORM" || true)"
  if [[ -z "$FOUND" ]]; then
    warn "no $MOBILE_PLATFORM device and none could be booted — desktop only"
  else
    MOBILE_ID="$(cut -f1 <<<"$FOUND")"
    printf '    %s (%s)\n' "$(cut -f2 <<<"$FOUND")" "$(cut -f3 <<<"$FOUND")"
    if [[ "$MOBILE_PLATFORM" == "ios" && "$(cut -f3 <<<"$FOUND")" == "physical" ]]; then
      say "a physical iPhone needs a signing team set in Xcode; unsigned runs will be rejected"
    fi
  fi
fi

# --- launch -----------------------------------------------------------------

RUN_DIR="$(mktemp -d)"
PIDS=()
LABELS=()

cleanup() {
  local pid pidfile
  # Ask each flutter run to stop first — it needs to tear down its device
  # connection — then clean up the wrapper subshells.
  for pidfile in "$RUN_DIR"/*.pid; do
    [[ -s "$pidfile" ]] || continue
    kill "$(cat "$pidfile")" 2>/dev/null || true
  done
  for pid in ${PIDS[@]+"${PIDS[@]}"}; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  rm -rf "$RUN_DIR"
  stty echo 2>/dev/null || true
  echo
}
trap cleanup EXIT INT TERM

start_run() {
  # Three statements, not one: bash expands every word of a `local` before it
  # performs any of the assignments, so pidfile could not reference label.
  local device="$1"
  local label="$2"
  local pidfile="$RUN_DIR/$label.pid"
  say "starting $label on $device"
  # stdin is /dev/null on purpose: flutter's own interactive console would
  # otherwise swallow the keystrokes this script needs to read, and both runs
  # would fight over the terminal. Signals are the only channel used.
  #
  # awk rather than `sed -u`: line buffering has to work on BSD sed too.
  ( flutter run -d "$device" --pid-file "$pidfile" </dev/null 2>&1 \
      | awk -v tag="$label" '{ printf "[%s] %s\n", tag, $0; fflush() }' ) &
  PIDS+=("$!")
  LABELS+=("$label:$pidfile")
}

# Resolve dependencies once up front. Two runs starting together otherwise
# collide on pub's startup lock and the second sits waiting for the first.
say "resolving dependencies"
flutter pub get >/dev/null

[[ "$MOBILE_ONLY" == "yes" ]] || start_run "$DESKTOP" "$DESKTOP"
[[ -z "$MOBILE_ID" ]]        || start_run "$MOBILE_ID" "$MOBILE_PLATFORM"

[[ ${#LABELS[@]} -gt 0 ]] || die "nothing to run"

# The pid files appear once each run reaches the point where it can be
# signalled; until then a reload keystroke has nothing to talk to.
say "waiting for both runs to come up (first Android build takes a minute)"
for entry in "${LABELS[@]}"; do
  pidfile="${entry#*:}"
  waited=0
  while [[ ! -s "$pidfile" ]] && (( waited < 600 )); do
    sleep 2; waited=$(( waited + 2 ))
  done
done

signal_all() {
  local sig="$1" entry pidfile pid sent=0
  for entry in "${LABELS[@]}"; do
    pidfile="${entry#*:}"
    [[ -s "$pidfile" ]] || continue
    pid="$(cat "$pidfile")"
    if kill -"$sig" "$pid" 2>/dev/null; then sent=$(( sent + 1 )); fi
  done
  echo "  ($sent run(s) signalled)"
}

cat <<EOF

${BOLD}r${OFF} hot reload both   ${BOLD}R${OFF} hot restart both   ${BOLD}q${OFF} quit

EOF

while true; do
  IFS= read -rsn1 key || break
  case "$key" in
    r) echo "${BOLD}hot reload${OFF}";  signal_all USR1 ;;
    R) echo "${BOLD}hot restart${OFF}"; signal_all USR2 ;;
    q) break ;;
  esac
done
