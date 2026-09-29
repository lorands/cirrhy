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

# Points the Android release build at an upload keystore, without committing
# which one.
#
#   tool/android-signing.sh                      # what is set, and its fingerprint
#   tool/android-signing.sh --create             # mint a new upload keystore
#   tool/android-signing.sh ~/keys/cirrhy.jks    # point at an existing one
#   tool/android-signing.sh --clear              # back to debug-signed builds
#
# The counterpart of tool/ios-signing.sh, and the same argument: which key
# signs a build says nothing about the project, and nobody's signing material
# belongs in a public repository. This writes app/android/key.properties,
# which is gitignored and which app/build.gradle.kts reads. No file, no
# signing config, and a release build falls back to debug keys — buildable,
# installable, not publishable.
#
# What this key is, precisely: under **Play App Signing** — which is mandatory
# for new apps — Google holds the *app signing key* that end users' devices
# verify, and it never leaves their infrastructure. What this script makes is
# the *upload key*, which only proves to the Play Console that an upload came
# from you. That distinction is the reassuring one:
#
#   - Lose the upload key and it is recoverable. Play Console → Test and
#     release → Setup → App signing → request an upload key reset, and Google
#     registers a new certificate within a couple of days.
#   - Lose the app signing key and the app is unrecoverable — but you cannot,
#     because you never had it.
#
# It is still worth backing up: a reset costs days you would rather not spend
# mid-release. Back up the keystore *and* key.properties together, since the
# passwords live in the latter — and keep the backup somewhere a `git clean`
# or a reinstall cannot reach, which is why the default location is outside
# the repository.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

KEY_PROPERTIES="$APP_DIR/android/key.properties"
DEFAULT_KEYSTORE="$HOME/.cirrhy/upload-keystore.jks"
DEFAULT_ALIAS="upload"

usage() {
  cat <<EOF
usage: $(basename "$0") [--create [<path>] | <path> | --clear]

  (no arguments)   show the configured key and its upload certificate
  --create [path]  create a new upload keystore (default $DEFAULT_KEYSTORE)
                   and point the release build at it
  <path>           point at a keystore that already exists
  --clear          remove the setting; release builds go back to debug keys
EOF
}

require_keytool() {
  command -v keytool >/dev/null 2>&1 \
    || die "keytool not on PATH — it ships with the JDK that Android builds already need"
}

# One value out of key.properties, or nothing.
configured() {
  [[ -f "$KEY_PROPERTIES" ]] || return 1
  local line
  while IFS= read -r line; do
    [[ "$line" == "$1"=* ]] || continue
    printf '%s\n' "${line#*=}"
    return 0
  done <"$KEY_PROPERTIES"
  return 1
}

# Gradle expands a leading ~ (build.gradle.kts does it by hand); this has to
# agree with it, or the two disagree about whether the keystore exists.
expand() {
  case "$1" in
    "~/"*) printf '%s\n' "$HOME/${1#\~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

write_properties() {
  local store="$1" store_pass="$2" alias="$3" key_pass="$4"

  # Created empty and locked down *before* the passwords go in, so they are
  # never briefly world-readable on a shared machine.
  : >"$KEY_PROPERTIES"
  chmod 600 "$KEY_PROPERTIES"
  cat >"$KEY_PROPERTIES" <<EOF
# Written by tool/android-signing.sh. Untracked on purpose — which key signs a
# build is a property of this machine, not of the project. Delete it, or run
# the script with --clear, to go back to debug-signed release builds.
#
# Back this file up together with the keystore it points at: the passwords are
# here, not there.
storeFile=$store
storePassword=$store_pass
keyAlias=$alias
keyPassword=$key_pass
EOF
}

# The certificate the Play Console will pin to this app. Printed on every
# `show`, because "is the Console expecting the key I am actually holding?" is
# the question behind almost every upload rejection.
fingerprints() {
  local store="$1" store_pass="$2" alias="$3"
  keytool -list -v -keystore "$store" -alias "$alias" \
    -storepass "$store_pass" 2>/dev/null |
    while IFS= read -r line; do
      case "${line#"${line%%[![:space:]]*}"}" in
        SHA1:*|SHA256:*) printf '      %s\n' "${line#"${line%%[![:space:]]*}"}" ;;
      esac
    done
}

show() {
  local store alias store_pass expanded
  if ! store="$(configured storeFile)"; then
    say "no upload key set — release builds are signed with debug keys"
    cat <<EOF

    That is enough to install and test a release build, and not enough to
    publish one: the Play Console refuses a debug-signed bundle. Run

      tool/android-signing.sh --create

    when you are ready to upload. See docs/release/play-store.md.
EOF
    return
  fi

  alias="$(configured keyAlias || echo '?')"
  store_pass="$(configured storePassword || echo '')"
  expanded="$(expand "$store")"

  say "signing with the upload key in $store"
  printf '    alias %s\n' "$alias"

  if [[ ! -f "$expanded" ]]; then
    warn "that file does not exist — a release build will fail rather than"
    warn "quietly fall back to debug keys. Restore it from your backup, or"
    warn "run --clear and then --create to start over with a new upload key."
    return
  fi

  require_keytool
  local prints
  prints="$(fingerprints "$expanded" "$store_pass" "$alias")"
  if [[ -n "$prints" ]]; then
    printf '\n    upload certificate:\n%s\n' "$prints"
    printf '\n    %sPlay Console → Test and release → Setup → App signing%s\n' "$DIM" "$OFF"
    printf '    %sshows the same pair under "Upload key certificate".%s\n' "$DIM" "$OFF"
  else
    warn "could not read the certificate — wrong password, or wrong alias"
  fi
}

create() {
  local store="${1:-$DEFAULT_KEYSTORE}"
  local expanded pass confirm
  expanded="$(expand "$store")"

  [[ ! -f "$expanded" ]] || die "$expanded already exists — pass a different path,
  or point at it directly with: $(basename "$0") $store"

  require_keytool
  mkdir -p "$(dirname "$expanded")"

  cat <<EOF
  Creating an upload key for the Play Console.

  It is stored outside the repository on purpose, so that a git clean or a
  fresh clone cannot destroy it. Back up $expanded together with
  app/android/key.properties once this finishes.

EOF

  printf '%s==>%s keystore password (empty generates a strong one): ' "$BOLD" "$OFF"
  read -rs pass; echo
  if [[ -z "$pass" ]]; then
    # The password is going into a plaintext file either way, so a generated
    # one is strictly better than a memorable one: nothing is reused, and
    # nobody is tempted to type it somewhere else.
    #
    # Read a bounded amount and trim in bash rather than the obvious
    # `tr -dc ... </dev/urandom | head -c 32`: that leaves `tr` reading an
    # endless file into a pipe `head` has already closed, and the SIGPIPE it
    # dies of is a pipeline failure that `set -o pipefail` turns into the
    # script exiting at the password prompt. 48 bytes of base64 leaves well
    # over 32 usable characters after the punctuation is stripped.
    pass="$(head -c 48 /dev/urandom | base64 | LC_ALL=C tr -dc 'A-Za-z0-9')"
    pass="${pass:0:32}"
    say "generated one — it is written into key.properties, which you are backing up"
  else
    printf '%s==>%s again: ' "$BOLD" "$OFF"
    read -rs confirm; echo
    [[ "$pass" == "$confirm" ]] || die "those did not match — nothing created"
    (( ${#pass} >= 6 )) || die "keytool requires at least six characters"
  fi

  # One password for the store and the key. Two would be a second thing to
  # lose for no gain: both live in the same plaintext file regardless.
  #
  # RSA 2048 is the Play Console's floor. 10000 days is a shade over 27 years,
  # comfortably past Google's "valid until at least 2033" requirement, and the
  # expiry is one less thing to be surprised by in a decade.
  keytool -genkeypair \
    -keystore "$expanded" \
    -alias "$DEFAULT_ALIAS" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "$pass" -keypass "$pass" \
    -dname "CN=Cirrhy, O=Lorand Somogyi, C=HU" \
    >/dev/null 2>&1 \
    || die "keytool failed — nothing written"

  chmod 600 "$expanded"
  write_properties "$store" "$pass" "$DEFAULT_ALIAS" "$pass"

  say "created $expanded"
  echo
  show
  cat <<EOF

  Before you rely on it:

    1. Copy $expanded and app/android/key.properties
       somewhere that survives this machine. A password manager's file
       attachment is enough; a folder synced to the same account you would
       lose along with the laptop is not.
    2. tool/target-android.sh --release --aab, and check the line it prints
       says upload-signed rather than debug-signed.

  The DN above is cosmetic — Play never shows it, and the certificate is
  identified by its fingerprint. Nothing depends on it being right.
EOF
}

adopt() {
  local store="$1" expanded alias pass
  expanded="$(expand "$store")"
  [[ -f "$expanded" ]] || die "no keystore at $expanded"
  require_keytool

  printf '%s==>%s key alias [%s]: ' "$BOLD" "$OFF" "$DEFAULT_ALIAS"
  read -r alias
  alias="${alias:-$DEFAULT_ALIAS}"

  printf '%s==>%s keystore password: ' "$BOLD" "$OFF"
  read -rs pass; echo

  keytool -list -keystore "$expanded" -alias "$alias" -storepass "$pass" >/dev/null 2>&1 \
    || die "keytool could not open that alias — wrong password, or wrong alias"

  write_properties "$store" "$pass" "$alias" "$pass"
  say "release builds will use $store"
  echo
  show
}

case "${1-}" in
  -h|--help) usage ;;
  --clear)
    if [[ -f "$KEY_PROPERTIES" ]]; then
      rm -f "$KEY_PROPERTIES"
      say "cleared — release builds are signed with debug keys again"
      say "the keystore itself is untouched"
    else
      say "nothing to clear"
    fi
    ;;
  --create) create "${2-}" ;;
  '') show ;;
  -*) die "unknown option: $1 (try --help)" ;;
  *) adopt "$1" ;;
esac
