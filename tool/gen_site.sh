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

# Builds the product site into build/site/ (or the directory given as $1).
#
# The legal pages are rendered from docs/legal/*.md, which stay canonical: the
# store listings and the runbooks point at that text, so the site never carries
# a hand-edited copy that could drift from it. Needs pandoc.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/build/site}"
repo_blob="https://github.com/lorands/cirrhy/blob/main"

command -v pandoc >/dev/null || { echo "gen_site: pandoc is required" >&2; exit 1; }

rm -rf "$out"
mkdir -p "$out/assets"
cp "$root/site/index.html" "$root/site/site.css" "$out/"
cp "$root/site/assets/"* "$out/assets/"
for shot in phone-timer phone-reports phone-projects; do
  cp "$root/docs/screenshots/$shot.png" "$out/assets/"
done

# A ready-made document, for anyone (App Review included) who wants to see the
# app with a year of data in it rather than an empty timer. It is the example
# document, not a copy of it, so it cannot fall behind the format.
mkdir -p "$out/sample"
cp "$root/docs/reporting/cirrhy.json" "$out/sample/cirrhy.json"

# source markdown -> published directory
pages=(privacy-policy:privacy support:support terms:terms)

for pair in "${pages[@]}"; do
  src="${pair%%:*}"; dir="${pair##*:}"
  mkdir -p "$out/$dir"
  title="$(sed -n 's/^# //p;q' "$root/docs/legal/$src.md")"
  pandoc "$root/docs/legal/$src.md" \
    --from gfm --to html5 \
    --template "$root/site/page.html" \
    --metadata pagetitle="$title" \
    --output "$out/$dir/index.html"
  # Sibling legal documents become site pages; anything else relative to the
  # repository (DESIGN.md, the format spec) points at GitHub.
  sed -i.bak \
    -e 's#href="privacy-policy\.md"#href="../privacy/"#g' \
    -e 's#href="support\.md"#href="../support/"#g' \
    -e 's#href="terms\.md"#href="../terms/"#g' \
    -e "s#href=\"\\.\\./\\.\\./#href=\"$repo_blob/#g" \
    "$out/$dir/index.html"
  rm "$out/$dir/index.html.bak"
done

echo "gen_site: wrote $out"
