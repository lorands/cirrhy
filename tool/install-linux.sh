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

# Installs the desktop integration for the current user: the .desktop entry
# and the hicolor icons, into ~/.local/share. Linux host only.
#
# This is what puts Cirrhy's own icon on the taskbar. A Wayland compositor
# never asks the window for an icon — it takes the window's app id
# (com.lorands.cirrhy, set by the runner) and looks for a matching .desktop
# file in the standard data dirs. Without this install there is no match, so
# KDE and GNOME fall back to the generic Wayland cog. Once installed the match
# works for every launch of the app id, including `flutter run` dev sessions.
#
# The bundle itself stays where the build put it; the desktop entry points at
# it in place. Re-run after moving the repo. A distro package would instead
# install the same files under /usr/share and its own Exec — see
# app/linux/CMakeLists.txt.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

require_host linux "Linux desktop"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APPLICATION_ID=com.lorands.cirrhy
RESOURCES="$APP_DIR/linux/runner/resources"

refresh_caches() {
  command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$DATA_HOME/applications" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 \
    && gtk-update-icon-cache -f -t "$DATA_HOME/icons/hicolor" 2>/dev/null || true
}

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -f "$DATA_HOME/applications/$APPLICATION_ID.desktop"
  find "$DATA_HOME/icons/hicolor" \
    \( -name "$APPLICATION_ID.png" -o -name "$APPLICATION_ID.svg" \
       -o -name "$APPLICATION_ID-running.png" -o -name "$APPLICATION_ID-running.svg" \) \
    2>/dev/null | xargs -r rm -f
  refresh_caches
  say "uninstalled the $APPLICATION_ID desktop entry and icons"
  exit 0
fi

explicit_mode=""
for arg in "$@"; do
  case "$arg" in --debug|--profile|--release) explicit_mode=1 ;; esac
done
parse_args "$@"

# With no explicit mode, point at whichever bundle exists, preferring release.
BUNDLE=""
if [[ -n "$explicit_mode" ]]; then
  match="$(find_artifact "build/linux/*/$MODE/bundle")"
  [[ -x "$APP_DIR/$match/cirrhy" ]] && BUNDLE="$APP_DIR/$match"
else
  for candidate in "build/linux/"*/release/bundle "build/linux/"*/debug/bundle; do
    [[ -x "$APP_DIR/$candidate/cirrhy" ]] && { BUNDLE="$APP_DIR/$candidate"; break; }
  done
fi
[[ -n "$BUNDLE" ]] || die "no built bundle found — run tool/target-linux.sh first"

# Icons: the generated hicolor tree, both the plain icon and its -running
# companion, installed file by file so nothing else in the theme is touched.
while IFS= read -r icon; do
  install -Dm644 "$icon" "$DATA_HOME/icons/${icon#"$RESOURCES/icons/"}"
done < <(find "$RESOURCES/icons/hicolor" -type f \( -name '*.png' -o -name '*.svg' \))

# The desktop entry: the generated file, with Exec pointed at the bundle in
# place. %f survives — a file manager can hand the app a document to open.
install -d "$DATA_HOME/applications"
sed "s|^Exec=cirrhy|Exec=$BUNDLE/cirrhy|" \
  "$RESOURCES/$APPLICATION_ID.desktop" \
  > "$DATA_HOME/applications/$APPLICATION_ID.desktop"

refresh_caches

say "installed for this user"
printf '    %s\n' "$DATA_HOME/applications/$APPLICATION_ID.desktop"
printf '    Exec → %s/cirrhy\n' "$BUNDLE"
say "the taskbar icon applies to new windows; already-running ones keep the old one"
