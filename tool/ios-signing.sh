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


# Points the iOS build at an Apple development team, without committing which
# one.
#
#   tool/ios-signing.sh                 # what is set, and what could be
#   tool/ios-signing.sh ABCDE12345      # set it
#   tool/ios-signing.sh --clear         # back to simulator-only
#
# Which Apple ID signs a build is a property of the machine, not of the
# project: a clone with no Apple ID has to keep building for the simulator,
# and nobody's team ID belongs in a public repository. So this writes
# app/ios/Flutter/Signing.xcconfig, which is gitignored and which
# Debug.xcconfig and Release.xcconfig pull in with an optional include — no
# file, no setting, same build as before.
#
# A free personal team is enough to put Cirrhy on your own iPhone: the iOS
# target declares no entitlements at all, so nothing here needs a paid
# membership. What it does not do is distribute. No TestFlight, no App Store,
# no installing on a device you have not registered by plugging it into
# Xcode, a seven-day expiry per build and three apps per device. That is the
# $99/yr Developer Program, not this.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

SIGNING="$APP_DIR/ios/Flutter/Signing.xcconfig"
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

usage() {
  cat <<EOF
usage: $(basename "$0") [<TEAMID> | --clear]

  (no arguments)  show the configured team and the teams this Mac can sign for
  <TEAMID>        a ten-character Apple team ID, e.g. ABCDE12345
  --clear         remove the setting; iOS goes back to simulator-only
EOF
}

# The team currently written into the xcconfig, if any.
configured_team() {
  [[ -f "$SIGNING" ]] || return 1
  local line
  while IFS= read -r line; do
    if [[ "$line" == DEVELOPMENT_TEAM* ]]; then
      printf '%s\n' "${line##*= }"
      return 0
    fi
  done <"$SIGNING"
  return 1
}

# Teams reachable from the signing certificates in the keychain, as
# "<id><tab><organisation>". The team ID is the certificate's OU.
identity_teams() {
  local name subject team org
  while IFS= read -r name; do
    subject="$(
      security find-certificate -c "$name" -p 2>/dev/null |
        openssl x509 -noout -subject 2>/dev/null
    )" || continue
    # OpenSSL has printed this both as "OU=X" and "OU = X" over the years.
    subject="${subject// = /=}"
    [[ "$subject" == *OU=* ]] || continue
    team="${subject##*OU=}"
    team="${team%%,*}"
    org="${subject##*, O=}"
    org="${org%%, C=*}"
    printf '%s\t%s\n' "$team" "$org"
  done < <(
    security find-identity -v -p codesigning 2>/dev/null |
      grep -o '"[^"]*"' | tr -d '"'
  )
}

# Teams reachable from the profiles Xcode has already downloaded. Worth
# reading separately: a team can be signed into without the certificate for
# it existing on this machine yet, and vice versa.
profile_teams() {
  [[ -d "$PROFILES" ]] || return 0
  local file plist team org
  for file in "$PROFILES"/*.mobileprovision; do
    [[ -f "$file" ]] || continue
    plist="$(security cms -D -i "$file" 2>/dev/null)" || continue
    team="$(printf '%s' "$plist" | plutil -extract TeamIdentifier.0 raw -o - - 2>/dev/null)" ||
      continue
    org="$(printf '%s' "$plist" | plutil -extract TeamName raw -o - - 2>/dev/null)" || org=''
    printf '%s\t%s\n' "$team" "$org"
  done
}

known_teams() {
  { identity_teams; profile_teams; } | sort -u
}

show() {
  local team
  if team="$(configured_team)"; then
    say "signing with team $team"
  else
    say "no team set — iOS builds for the simulator only"
  fi

  local teams
  teams="$(known_teams)"
  if [[ -z "$teams" ]]; then
    printf '    %sthis Mac has no signing certificates or profiles yet%s\n' "$DIM" "$OFF"
  else
    printf '\n    teams this Mac can sign for:\n'
    printf '%s\n' "$teams" | while IFS=$'\t' read -r id org; do
      printf '      %-12s %s\n' "$id" "$org"
    done
  fi

  cat <<EOF

  A free personal team is listed under your own name rather than a company's.
  If none is there, add the Apple ID in Xcode — Settings, Accounts, + — then
  open app/ios/Runner.xcworkspace once and pick the team on the Runner
  target's Signing & Capabilities tab. That is what makes Xcode mint the
  certificate; after it exists this script can see it.
EOF
}

set_team() {
  local team="$1"
  [[ "$team" =~ ^[A-Z0-9]{10}$ ]] ||
    die "'$team' is not a team ID — they are ten characters, like ABCDE12345"

  if ! known_teams | grep -q "^$team	"; then
    warn "no certificate or profile for $team on this Mac yet"
    warn "writing it anyway — Xcode mints those on the first device build"
  fi

  cat >"$SIGNING" <<EOF
// Written by tool/ios-signing.sh. Untracked on purpose: which Apple ID signs
// a build says nothing about the project. Delete it, or run the script with
// --clear, to go back to simulator-only builds.
DEVELOPMENT_TEAM = $team
CODE_SIGN_STYLE = Automatic
// The project carries the legacy "iPhone Developer" alias at project level.
// A target xcconfig outranks that, which is the point of naming it here.
CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Development
EOF

  say "signing with team $team"
  cat <<EOF

  Still yours to do, once per phone:

    1. Plug it in, unlock it, trust this Mac. Xcode, Window, Devices and
       Simulators should then list it without a pairing prompt.
    2. On the phone: Settings, Privacy & Security, Developer Mode, on. It
       restarts, and asks again after you unlock.
    3. tool/run-ios.sh — an attached phone wins over the simulator.
    4. First launch under a personal team, the phone refuses to open the app
       until you trust the certificate: Settings, General, VPN & Device
       Management.

  A personal team's build stops launching after seven days. Re-running
  tool/run-ios.sh is the whole fix.
EOF
}

require_host macos "iOS"

case "${1-}" in
  -h|--help) usage ;;
  --clear)
    if [[ -f "$SIGNING" ]]; then
      rm -f "$SIGNING"
      say "cleared — iOS builds for the simulator only"
    else
      say "nothing to clear"
    fi
    ;;
  '') show ;;
  -*) die "unknown option: $1 (try --help)" ;;
  *) set_team "$1" ;;
esac
