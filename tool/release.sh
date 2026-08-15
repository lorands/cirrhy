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

# Cuts a release, in the one order that works:
#
#   tool/release.sh 0.2.0
#
# 1. Bumps app/pubspec.yaml to the version — and its +N build number, which
#    the Play Console requires to increase on every upload — and commits.
# 2. Tags v<version> on that commit and pushes branch and tag. The tag push
#    is the release: CI verifies the tag against pubspec, builds the four
#    platform packages and publishes the GitHub release. Tagging first and
#    bumping second is exactly the mistake the verify job refuses, and
#    exactly the one this script makes impossible.
# 3. Prepares the app-store packages it honestly can into dist/: the Play
#    Console .aab on any host with the Android SDK (debug-signed until a
#    keystore exists, so buildable but not yet uploadable), and the App
#    Store .ipa only on a macOS host with a signing team set — a free
#    personal team cannot sign for distribution, so that one also needs a
#    paid membership before it succeeds.
#
# --force moves an existing v<version> tag — the recovery for a tag that
# failed verify — and force-pushes it; CI adopts the existing GitHub release
# and replaces its assets rather than failing on it.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

VERSION='' FORCE=0 YES=0 STORES=1

usage() {
  cat <<EOF
usage: $(basename "$0") <version> [--force] [--yes] [--no-stores]

  <version>     x.y.z, with or without the leading v
  --force       move an existing v<version> tag (for redoing a tag that
                failed CI's verify) and force-push it
  --yes         skip the confirmation before pushing
  --no-stores   stop after the push; skip the .aab/.ipa store packages
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1 ;;
    --yes) YES=1 ;;
    --no-stores) STORES=0 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option: $1 (try --help)" ;;
    *)
      [[ -z "$VERSION" ]] || die "expected one version, got '$VERSION' and '$1'"
      VERSION="${1#v}" ;;
  esac
  shift
done

[[ -n "$VERSION" ]] || { usage >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die "version must be x.y.z (got '$VERSION')"
TAG="v$VERSION"

git diff-index --quiet HEAD -- \
  || die "the working tree has uncommitted changes — commit or stash first"
BRANCH="$(git branch --show-current)"
[[ -n "$BRANCH" ]] || die "detached HEAD — check out the branch to release from"
[[ "$BRANCH" == "main" ]] || warn "releasing from '$BRANCH', not main"

# The collision check comes before the bump, so a refused run mutates
# nothing — no stray release commit to clean up.
TAG_EXISTS=0
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  (( FORCE )) || die "$TAG already exists — pass --force to move it here"
  TAG_EXISTS=1
fi

# --- bump -------------------------------------------------------------------
#
# Idempotent on purpose: a pubspec already at the version (a bump committed by
# hand, or a --force re-run after a failed push) skips straight to tagging.

CURRENT="$(sed -n 's/^version: *//p' pubspec.yaml)"
BASE="${CURRENT%%+*}"
BUILD="${CURRENT#*+}"; [[ "$BUILD" == "$CURRENT" ]] && BUILD=0

if [[ "$BASE" == "$VERSION" ]]; then
  say "pubspec already says $CURRENT — nothing to bump"
else
  NEW="$VERSION+$((BUILD + 1))"
  # The .bak dance keeps BSD sed happy, so this also runs on the MacBook.
  sed -i.bak "s/^version: .*/version: $NEW/" pubspec.yaml && rm pubspec.yaml.bak
  git add pubspec.yaml
  git commit -m "Release $VERSION"
  say "bumped pubspec to $NEW and committed"
fi

# --- tag and push -----------------------------------------------------------

if (( TAG_EXISTS )); then
  git tag -fa "$TAG" -m "Cirrhy $VERSION"
  say "moved $TAG to $(git rev-parse --short HEAD)"
else
  git tag -a "$TAG" -m "Cirrhy $VERSION"
  say "tagged $TAG at $(git rev-parse --short HEAD)"
fi

if (( ! YES )); then
  printf '%s==>%s push %s and %s to origin? the tag push is the release [y/N] ' \
    "$BOLD" "$OFF" "$BRANCH" "$TAG"
  read -r ANSWER
  [[ "$ANSWER" == [yY]* ]] \
    || die "not pushed — the commit and tag stay local; re-run when ready"
fi

git push origin "$BRANCH"
if (( FORCE )); then
  git push --force origin "refs/tags/$TAG"
else
  git push origin "refs/tags/$TAG"
fi
say "pushed — CI verifies, builds and publishes the GitHub release from here"

# --- store packages ---------------------------------------------------------

(( STORES )) || exit 0

DIST="$REPO_ROOT/dist"
mkdir -p "$DIST"

say "Play Store package"
if "$REPO_ROOT/tool/target-android.sh" --release --aab; then
  AAB="$(find_artifact "build/app/outputs/bundle/release/app-release.aab")"
  cp "$APP_DIR/$AAB" "$DIST/cirrhy-$VERSION-playstore.aab"
  printf '%s  ✓ play aab%s  %s%s%s\n' \
    "$GREEN" "$OFF" "$DIM" "$DIST/cirrhy-$VERSION-playstore.aab" "$OFF"
  warn "debug-signed until a keystore exists — the Play Console will refuse it as-is"
else
  warn "aab build failed — no Play package prepared"
fi

say "App Store package"
if [[ "$(host_os)" != macos ]]; then
  warn "needs a macOS host — run this script on the MacBook for the .ipa; skipped"
elif [[ ! -f ios/Flutter/Signing.xcconfig ]]; then
  warn "no signing team set (tool/ios-signing.sh) — skipped"
elif flutter build ipa --release; then
  IPA="$(find_artifact "build/ios/ipa/*.ipa")"
  cp "$APP_DIR/$IPA" "$DIST/cirrhy-$VERSION-appstore.ipa"
  printf '%s  ✓ app store ipa%s  %s%s%s\n' \
    "$GREEN" "$OFF" "$DIM" "$DIST/cirrhy-$VERSION-appstore.ipa" "$OFF"
else
  warn "ipa build failed — App Store distribution needs a paid Apple team;" \
       "a free personal one cannot sign for it"
fi
