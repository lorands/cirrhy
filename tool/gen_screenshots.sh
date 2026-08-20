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

# App Store screenshots, generated rather than captured by hand — the same
# rule tool/gen_app_icons.py follows, and for the same reason: a screenshot
# taken by hand is a screenshot nobody can reproduce next release.
#
#   tool/gen_screenshots.sh                 # both required sizes
#   tool/gen_screenshots.sh --iphone        # just the 6.9" set
#   tool/gen_screenshots.sh --locale hu     # a localized set
#
# The real app runs on a real simulator against a seeded copy of the example
# document, and app/integration_test/screenshots_test.dart taps between the
# tabs. What lands in build/screenshots is the shipping UI at exact device
# resolution, ready to upload with no cropping or scaling.
#
# Both sizes are mandatory while the app ships for iPad: Apple requires an
# iPhone 6.9" set, and an iPad 13" set for as long as TARGETED_DEVICE_FAMILY
# stays "1,2". See docs/release/app-store.md.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DEVICES=(iphone ipad)
LOCALE=en

# Simulator model names, and the pixel size each is expected to produce. The
# size is asserted afterwards rather than trusted: Apple rejects an upload
# whose dimensions are a few pixels off, and that is a slow way to find out.
iphone_model='iPhone 16 Pro Max'; iphone_size='1320x2868'
ipad_model='iPad Pro 13-inch (M4)'; ipad_size='2064x2752'

usage() {
  cat <<USAGE
usage: $(basename "$0") [--iphone|--ipad] [--locale <code>]

  (no arguments)   both required App Store sizes
  --iphone         only the iPhone 6.9" set ($iphone_size)
  --ipad           only the iPad 13" set ($ipad_size)
  --locale <code>  render the UI in one of the shipped languages (default en)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iphone) DEVICES=(iphone) ;;
    --ipad) DEVICES=(ipad) ;;
    --locale) [[ $# -ge 2 ]] || die "--locale needs a language code"; LOCALE="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

require_host macos "screenshot"
require_flutter
command -v python3 >/dev/null 2>&1 || die "python3 not on PATH"

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

SEED="$(mktemp -d)/cirrhy.json"
trap 'rm -rf "$(dirname "$SEED")"' EXIT

say "seed document"
python3 "$REPO_ROOT/tool/gen_screenshot_seed.py" \
  "$REPO_ROOT/docs/reporting/cirrhy.json" "$SEED"

for device in "${DEVICES[@]}"; do
  model_var="${device}_model"; size_var="${device}_size"
  model="${!model_var}"; expected="${!size_var}"

  say "$model  ($expected)"
  udid="$(simulator_udid "$model")"
  [[ -n "$udid" ]] || { warn "no '$model' simulator installed — skipped"; continue; }

  # Every other booted simulator is shut down first, and the target is made
  # the visible device. This is not tidiness: a simulator that is booted but
  # not the one Simulator.app is showing never composites its surface, so the
  # capture silently returns a blank frame at exactly the right dimensions.
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

  out="$APP_DIR/build/screenshots/$device"
  rm -rf "$out"
  if ! CIRRHY_SHOT_DIR="$out" flutter drive \
      --driver=test_driver/screenshots.dart \
      --target=integration_test/screenshots_test.dart \
      -d "$udid" \
      --dart-define=CIRRHY_SEED="$SEED" \
      --dart-define=CIRRHY_LOCALE="$LOCALE" >/dev/null 2>&1; then
    warn "capture failed on $model"
    continue
  fi

  # Three different screens cannot produce identical bytes. When they do, the
  # surface never painted and every file is the same blank frame — the failure
  # that dimensions alone cannot see.
  if [[ "$(md5 -q "$out"/*.png | sort -u | wc -l | tr -d ' ')" == 1 ]]; then
    warn "$model captured the same frame three times — the surface never painted"
    warn "check that Simulator.app is showing $model, then rerun"
    continue
  fi

  for shot in "$out"/*.png; do
    [[ -e "$shot" ]] || { warn "$model produced nothing"; break; }
    actual="$(sips -g pixelWidth -g pixelHeight "$shot" | awk '/pixel/{printf "%s", $2; if (!x++) printf "x"}')"
    if [[ "$actual" == "$expected" ]]; then
      printf '%s  ✓%s %s  %s%s%s\n' "$GREEN" "$OFF" "$(basename "$shot")" "$DIM" "$actual" "$OFF"
    else
      warn "$(basename "$shot") is $actual, expected $expected — App Store will reject it"
    fi
  done
done

echo
say "upload from $APP_DIR/build/screenshots"
