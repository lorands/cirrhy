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

# Store screenshots, generated rather than captured by hand — the same rule
# tool/gen_app_icons.py follows, and for the same reason: a screenshot taken by
# hand is a screenshot nobody can reproduce next release.
#
#   tool/gen_screenshots.sh                 # every set this host can produce
#   tool/gen_screenshots.sh --iphone        # just the App Store 6.9" set
#   tool/gen_screenshots.sh --android       # both Play sets
#   tool/gen_screenshots.sh --locale hu     # a localized set
#
# The real app runs on a real device against a seeded copy of the example
# document, and app/integration_test/screenshots_test.dart taps between the
# tabs. What lands in build/screenshots is the shipping UI at device
# resolution, ready to upload with no cropping or scaling.
#
# Four sets, because the two stores count differently:
#
#   iphone   App Store, mandatory, exactly 1320x2868
#   ipad     App Store, mandatory while TARGETED_DEVICE_FAMILY stays "1,2"
#   phone    Play Store, mandatory, at least 2 shots
#   tablet   Play Store, needed for the large-screen surfaces, at least 4
#
# Apple demands exact pixel sizes, so those two are asserted against a number.
# Google demands a *range* — 320-3840px a side for phones, 1080-7680 for
# tablets — plus one rule that catches people out: the long side may not be
# more than twice the short side. Every modern phone AVD is 1080x2400, which
# is 2.22:1 and refused. See docs/release/play-store.md for the AVD to make
# instead; this script checks the rule rather than trusting the device.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DEVICES=()
LOCALE=en
PHONE_AVD="${CIRRHY_PHONE_AVD:-cirrhy_phone}"
TABLET_AVD="${CIRRHY_TABLET_AVD:-cirrhy_tablet}"

# Simulator model names, and the pixel size each is expected to produce. The
# size is asserted afterwards rather than trusted: Apple rejects an upload
# whose dimensions are a few pixels off, and that is a slow way to find out.
iphone_model='iPhone 16 Pro Max'; iphone_size='1320x2868'
ipad_model='iPad Pro 13-inch (M4)'; ipad_size='2064x2752'

# Play's bounds, as "<shortest side>:<longest side>".
phone_bounds='320:3840'
tablet_bounds='1080:7680'

# Where the seed lands on an Android device. The app's own external files
# directory is the one place adb can write to and the app can read from
# without a runtime permission — an emulator, unlike a simulator, cannot see
# the host's filesystem at all.
REMOTE_DIR='/sdcard/Android/data/com.lorands.cirrhy/files'
REMOTE_SEED="$REMOTE_DIR/cirrhy-seed.json"

usage() {
  cat <<USAGE
usage: $(basename "$0") [--iphone|--ipad|--android|--phone|--tablet] [--locale <code>]

  (no arguments)   every set this host can produce
  --iphone         App Store iPhone 6.9" set ($iphone_size)
  --ipad           App Store iPad 13" set ($ipad_size)
  --android        both Play sets
  --phone          Play phone set, from the $PHONE_AVD emulator
  --tablet         Play tablet set, from the $TABLET_AVD emulator
  --locale <code>  render the UI in one of the shipped languages (default en)

  \$CIRRHY_PHONE_AVD and \$CIRRHY_TABLET_AVD override the emulator names.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iphone) DEVICES+=(iphone) ;;
    --ipad) DEVICES+=(ipad) ;;
    --android) DEVICES+=(phone tablet) ;;
    --phone) DEVICES+=(phone) ;;
    --tablet) DEVICES+=(tablet) ;;
    --locale) [[ $# -ge 2 ]] || die "--locale needs a language code"; LOCALE="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

# Nothing asked for means everything this host can do. Apple's two need a Mac;
# Android's two need only the SDK, which is why they are the pair that runs on
# the Linux machine.
if [[ ${#DEVICES[@]} -eq 0 ]]; then
  DEVICES=(phone tablet)
  [[ "$(host_os)" == macos ]] && DEVICES=(iphone ipad phone tablet)
fi

require_flutter
command -v python3 >/dev/null 2>&1 || die "python3 not on PATH"

# --- checking what was captured ---------------------------------------------
#
# Two failures this catches, both of which look like success. A capture at the
# wrong size is refused by the store days later; a capture of a surface that
# never painted is a blank frame at exactly the right size, which dimensions
# alone cannot see — so identical bytes across three different screens is
# treated as the failure it is.
check_shots() {
  python3 - "$1" "$2" "$3" <<'PY'
import hashlib, pathlib, struct, sys

folder, mode, spec = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
shots = sorted(folder.glob("*.png"))
if not shots:
    print("fail|nothing was captured")
    sys.exit(1)

def size(path):
    data = path.read_bytes()
    # PNG: 8-byte signature, then the IHDR length/type, then width and height.
    return struct.unpack(">II", data[16:24])

digests = {hashlib.sha256(p.read_bytes()).hexdigest() for p in shots}
if len(digests) == 1 and len(shots) > 1:
    print("fail|every capture is byte-identical — the surface never painted")
    sys.exit(1)

bad = False
for shot in shots:
    w, h = size(shot)
    problems = []
    if mode == "exact":
        if f"{w}x{h}" != spec:
            problems.append(f"expected {spec} — the store will reject it")
    else:
        low, high = (int(n) for n in spec.split(":"))
        short, long_ = min(w, h), max(w, h)
        if short < low:
            problems.append(f"shorter side {short}px is under Play's {low}px floor")
        if long_ > high:
            problems.append(f"longer side {long_}px is over Play's {high}px ceiling")
        if long_ > 2 * short:
            problems.append(
                f"{long_/short:.2f}:1 is past Play's 2:1 cap — use a 9:16 device"
            )
    if problems:
        bad = True
        print(f"bad|{shot.name}|{w}x{h}|{'; '.join(problems)}")
    else:
        print(f"ok|{shot.name}|{w}x{h}")

sys.exit(1 if bad else 0)
PY
}

# Turns the checker's output into the same ✓/warn lines every other script
# prints, and passes its exit status through.
report_shots() {
  local verdicts status=0 kind name size detail
  # Collected before it is read, not piped into the loop: a process
  # substitution's exit status never reaches the `while` that consumes it, so
  # the version of this that reads `done < <(check_shots ...) || status=1`
  # reports every failure and then returns success.
  verdicts="$(check_shots "$1" "$2" "$3")" || status=1
  while IFS='|' read -r kind name size detail; do
    case "$kind" in
      ok) printf '%s  ✓%s %s  %s%s%s\n' "$GREEN" "$OFF" "$name" "$DIM" "$size" "$OFF" ;;
      bad) warn "$name is $size — $detail" ;;
      fail) warn "$name" ;;
    esac
  done <<<"$verdicts"
  return $status
}

# --- the capture itself ------------------------------------------------------

SEED="$(mktemp -d)/cirrhy.json"
trap 'rm -rf "$(dirname "$SEED")"' EXIT

say "seed document"
python3 "$REPO_ROOT/tool/gen_screenshot_seed.py" \
  "$REPO_ROOT/docs/reporting/cirrhy.json" "$SEED"

# Runs the on-device test and writes into build/screenshots/<name>. The seed
# is handed over as a host path, which is all the simulator needs; the Android
# path pushes the file separately and the test finds it on the device.
drive() {
  local device="$1" name="$2"
  local out="$APP_DIR/build/screenshots/$name"
  rm -rf "$out"
  CIRRHY_SHOT_DIR="$out" flutter drive \
    --driver=test_driver/screenshots.dart \
    --target=integration_test/screenshots_test.dart \
    -d "$device" \
    --dart-define=CIRRHY_SEED="$SEED" \
    --dart-define=CIRRHY_LOCALE="$LOCALE" >/dev/null 2>&1
}

# --- Apple simulators --------------------------------------------------------

# Newest runtime wins: an older simulator renders older system fonts and
# corner radii, which shows up in the screenshots even though the app is
# identical.
simulator_udid() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
want = sys.argv[1]
runtimes = json.load(sys.stdin)["devices"]

def order(runtime):
    digits = [int(n) for n in runtime.split(".")[-1].split("-")[1:] if n.isdigit()]
    return digits or [0]

for runtime in sorted((r for r in runtimes if "iOS" in r), key=order, reverse=True):
    for device in runtimes[runtime]:
        if device["name"] == want:
            print(device["udid"])
            sys.exit(0)
' "$1"
}

capture_apple() {
  local device="$1"
  local model_var="${device}_model" size_var="${device}_size"
  local model="${!model_var}" expected="${!size_var}"
  local udid

  say "$model  ($expected)"
  udid="$(simulator_udid "$model")"
  [[ -n "$udid" ]] || { warn "no '$model' simulator installed — skipped"; return 1; }

  # Every other booted simulator is shut down first, and the target is made
  # the visible device. This is not tidiness: a simulator that is booted but
  # not the one Simulator.app is showing never composites its surface, so the
  # capture silently returns a blank frame at exactly the right dimensions.
  local other
  for other in $(xcrun simctl list devices booted -j |
      python3 -c 'import json,sys
booted = json.load(sys.stdin)["devices"]
print(" ".join(d["udid"] for r in booted for d in booted[r]))'); do
    [[ "$other" == "$udid" ]] || xcrun simctl shutdown "$other" 2>/dev/null || true
  done
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  open -a Simulator --args -CurrentDeviceUDID "$udid"
  sleep 3

  drive "$udid" "$device" || { warn "capture failed on $model"; return 1; }
  report_shots "$APP_DIR/build/screenshots/$device" exact "$expected"
}

# --- Android emulators -------------------------------------------------------

# adb is rarely on PATH even when the SDK is installed.
find_adb() {
  local sdk
  command -v adb >/dev/null 2>&1 && { command -v adb; return 0; }
  sdk="$(android_sdk)" || return 1
  [[ -x "$sdk/platform-tools/adb" ]] || return 1
  printf '%s\n' "$sdk/platform-tools/adb"
}

# The serial of a running emulator with this AVD name. `adb devices` reports
# ports, not names, so each one has to be asked what it is.
avd_serial() {
  local want="$1" serial rest name
  while read -r serial rest; do
    [[ "$serial" == emulator-* && "$rest" == device* ]] || continue
    name="$("$ADB" -s "$serial" emu avd name 2>/dev/null | head -1 | tr -d '\r')"
    [[ "$name" == "$want" ]] && { printf '%s\n' "$serial"; return 0; }
  done < <("$ADB" devices 2>/dev/null | tail -n +2)
  return 1
}

boot_avd() {
  local want="$1" serial waited=0
  serial="$(avd_serial "$want")" && { printf '%s\n' "$serial"; return 0; }

  # Collected first: `flutter emulators | grep -q` has grep exit the moment it
  # matches, which SIGPIPEs flutter, which under `set -o pipefail` reads as a
  # failed pipeline — so finding the emulator would report not finding it.
  local known
  known="$(flutter emulators 2>/dev/null || true)"
  grep -q "^$want " <<<"$known" \
    || { warn "no '$want' emulator — see docs/release/play-store.md" >&2; return 1; }

  say "booting $want" >&2
  flutter emulators --launch "$want" >/dev/null 2>&1 || return 1

  while (( waited < 300 )); do
    if serial="$(avd_serial "$want")"; then
      # Registering as a device and having finished booting are different
      # moments, and installing into the gap fails in confusing ways.
      while [[ "$("$ADB" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]]; do
        sleep 2
        (( waited += 2 )); (( waited < 300 )) || return 1
      done
      echo >&2
      printf '%s\n' "$serial"
      return 0
    fi
    sleep 3; (( waited += 3 )); printf '.' >&2
  done
  echo >&2
  return 1
}

capture_android() {
  local kind="$1" avd="$2" bounds_var="${1}_bounds" bounds serial
  bounds="${!bounds_var}"

  say "$kind  (Play: ${bounds%:*}-${bounds#*:}px a side, at most 2:1)"

  ADB="$(find_adb)" || { warn "adb not found — install the Android SDK platform-tools; skipped"; return 1; }
  serial="$(boot_avd "$avd")" || { warn "could not start $avd — skipped"; return 1; }
  printf '    %s (%s)\n' "$avd" "$serial"

  # The seed has to be on the device before the app looks for it. mkdir first,
  # because the directory only exists once the app has been installed once,
  # and the very first run on a fresh emulator has not installed it yet.
  "$ADB" -s "$serial" shell mkdir -p "$REMOTE_DIR" >/dev/null 2>&1 || true
  "$ADB" -s "$serial" push "$SEED" "$REMOTE_SEED" >/dev/null 2>&1 \
    || { warn "could not push the seed document to $serial — skipped"; return 1; }

  drive "$serial" "$kind" || { warn "capture failed on $avd"; return 1; }
  report_shots "$APP_DIR/build/screenshots/$kind" play "$bounds"
}

# --- run ---------------------------------------------------------------------

FAILED=0
for device in "${DEVICES[@]}"; do
  case "$device" in
    iphone|ipad)
      if [[ "$(host_os)" != macos ]]; then
        warn "$device needs a macOS host — skipped"
        FAILED=1
      else
        capture_apple "$device" || FAILED=1
      fi
      ;;
    phone) capture_android phone "$PHONE_AVD" || FAILED=1 ;;
    tablet) capture_android tablet "$TABLET_AVD" || FAILED=1 ;;
  esac
  echo
done

say "upload from $APP_DIR/build/screenshots"
exit $FAILED
