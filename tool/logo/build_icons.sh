#!/usr/bin/env bash
#
# Regenerate every logo derivative from assets/logo.svg.
#
# The vector is the only hand-edited artwork; favicons, touch icons and the
# per-site SVGs all fall out of it. Run from anywhere:
#
#   ./tool/logo/build_icons.sh
#
# Needs rsvg-convert (librsvg) and magick (ImageMagick 7):
#   brew install librsvg imagemagick
#
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$root/assets/logo.svg"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Brand values, kept in step with apps/website/lib/src/theme.dart.
zon='#2FE0AC'       # --zon,      the mark on dark surfaces
zon_deep='#0B8F6C'  # --zon-deep, legible on the docs' light *and* dark themes
void='#05080A'      # --void,     the badge behind the mark on icons

for tool in rsvg-convert magick; do
  command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 1; }
done

# tint <out> <colour> [--no-core]
# Stamps a literal colour in place of currentColor. --no-core drops the centre
# dot, which fills the ring solid once the mark is under ~20px.
tint() {
  local out=$1 colour=$2 body
  body=$(cat "$src")
  [[ ${3:-} == --no-core ]] && body=$(sed '/rune-core/d' <<<"$body")
  # Drop the comment block. It documents the master; these copies are served to
  # browsers, where it is most of the file.
  python3 -c 'import re,sys; s=re.sub(r"\s*<!--.*?-->","",sys.stdin.read(),flags=re.S); sys.stdout.write(re.sub(r"\n\s*\n","\n",s))' \
    <<<"$body" | sed "s/currentColor/$colour/g" > "$out"
}

tint "$work/mark.svg" "$zon"
tint "$work/mark-small.svg" "$zon" --no-core

# badge <out> <px>
# The mark on a rounded-square of --void. Icons sit on browser and OS chrome we
# do not control, so they carry their own background rather than trusting it.
badge() {
  local out=$1 px=$2 r inset src_svg
  r=$(python3 -c "print(round($px * 0.2232))")
  inset=$(python3 -c "print(round($px * 0.78))")
  src_svg="$work/mark.svg"
  (( px <= 20 )) && src_svg="$work/mark-small.svg"
  rsvg-convert -w "$inset" -h "$inset" -o "$work/m$px.png" "$src_svg"
  magick -size "${px}x${px}" xc:none \
    -fill "$void" -draw "roundrectangle 0,0,$((px - 1)),$((px - 1)),$r,$r" \
    "$work/m$px.png" -gravity center -composite "$out"
}

for site in website docs; do
  webdir="$root/apps/$site/web"
  [[ -d $webdir ]] || { echo "no $webdir, skipping" >&2; continue; }

  # The header mark. Docs renders it through <img>, which cannot inherit a
  # colour, and its light theme washes out --zon -- hence the deeper teal.
  if [[ $site == docs ]]; then
    tint "$webdir/images/logo.svg" "$zon_deep"
  else
    tint "$webdir/images/logo.svg" "$zon"
  fi

  for px in 16 32 48 64; do badge "$work/ico$px.png" "$px"; done
  magick "$work/ico16.png" "$work/ico32.png" "$work/ico48.png" "$work/ico64.png" \
    "$webdir/favicon.ico"
  cp "$work/ico32.png" "$webdir/favicon.png"

  # Only the marketing site links an apple-touch-icon; docs has no <head> hook
  # for one, so generating it there would just ship a file nothing requests.
  [[ $site == website ]] && badge "$webdir/images/logo-192.png" 192

  echo "built $site"
done

# For the README. GitHub renders on a light *or* a dark theme and strips
# `currentColor` out of an <img>, so this one carries its own background
# instead of trying to suit both.
badge "$root/assets/logo-badge.png" 256
echo "built assets/logo-badge.png"

# The CLI seeds every new project with a favicon, so the bytes ship inside the
# binary rather than as a file. Sizes and their order match what was there
# before: 64, 32, 16.
dart_out="$root/apps/zonai/lib/src/commands/dev/actions/init_favicon.dart"
for px in 64 32 16; do badge "$work/cli$px.png" "$px"; done
magick "$work/cli64.png" "$work/cli32.png" "$work/cli16.png" "$work/cli.ico"
python3 - "$work/cli.ico" "$dart_out" <<'PY'
import sys

data = open(sys.argv[1], 'rb').read()
rows = ['  ' + ' '.join(f'0x{b:02X},' for b in data[i:i + 16])
        for i in range(0, len(data), 16)]
open(sys.argv[2], 'w').write(
    '// Zonai logo favicon (64x64, 32x32, 16x16 px).\n'
    '//\n'
    '// Generated from assets/logo.svg by tool/logo/build_icons.sh -- do not\n'
    '// hand-edit. `zonai dev` writes this into a new project as its favicon.\n'
    'const List<int> kDefaultFavicon = [\n'
    + '\n'.join(rows) + '\n];\n')
print(f'  {len(data)} bytes -> {sys.argv[2]}')
PY
echo "built cli favicon"

echo "done"
