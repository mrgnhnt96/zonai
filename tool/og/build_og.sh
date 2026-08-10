#!/usr/bin/env bash
#
# Regenerate the Open Graph cards for both sites.
#
#   ./tool/og/build_og.sh
#
# The cards are screenshots of a real page, rendered by headless Chrome against
# the same Google Fonts the sites load, so the type is the brand's rather than
# whatever the renderer happened to have installed. The rune is inlined from
# assets/logo.svg and inherits its colour through `currentColor`.
#
# Needs Google Chrome and network access for the fonts. Outputs:
#   apps/website/web/images/og.png   1200x630
#   apps/docs/web/images/og.png      1200x630
#
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

[[ -x $chrome ]] || { echo "Google Chrome not found at $chrome" >&2; exit 1; }

rune="$(sed '1d' "$root/assets/logo.svg")"  # drop the <svg> line; re-opened below with sizing

# card <out> <domain> <headline> <sub> <pills...>
card() {
  local out=$1 domain=$2 headline=$3 sub=$4; shift 4
  local pills='' p
  for p in "$@"; do pills+="<span class=\"pill\">$p</span>"; done

  cat > "$work/card.html" <<HTML
<!doctype html><html><head><meta charset="utf-8">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;700&family=Inter:wght@400&family=JetBrains+Mono:wght@500&display=block">
<style>
  /* Tokens mirror apps/website/lib/src/theme.dart. */
  :root { --void:#05080A; --fg:#E4EFF1; --fg-dim:#A8BCC0; --fg-mute:#6E858B;
          --zon:#2FE0AC; --zon-deep:#0B8F6C; --edge:#1C2A30; }
  * { margin:0; padding:0; box-sizing:border-box; }
  body { width:1200px; height:630px; background:var(--void); color:var(--fg);
         font-family:'Inter',sans-serif; position:relative; overflow:hidden; }
  /* The same cold-basalt surface the site opens on: a grid, and one light source. */
  .grid { position:absolute; inset:0;
          background-image:linear-gradient(var(--edge) 1px,transparent 1px),
                           linear-gradient(90deg,var(--edge) 1px,transparent 1px);
          background-size:60px 60px; opacity:.28; }
  .aura { position:absolute; width:900px; height:900px; top:-420px; left:-220px;
          background:radial-gradient(circle,rgba(47,224,172,.20),transparent 62%); }
  .inner { position:relative; padding:70px 72px; height:100%;
           display:flex; flex-direction:column; }
  .brand { display:flex; align-items:center; gap:22px; }
  .rune { width:76px; height:76px; color:var(--zon); flex:0 0 auto;
          filter:drop-shadow(0 0 18px rgba(47,224,172,.35)); }
  .rune svg { width:100%; height:100%; display:block; }
  .name { font-family:'Space Grotesk',sans-serif; font-weight:700;
          font-size:46px; letter-spacing:-.02em; line-height:1; }
  .domain { font-family:'JetBrains Mono',monospace; font-weight:500;
            font-size:19px; color:var(--fg-mute); margin-top:9px; }
  .head { font-family:'Space Grotesk',sans-serif; font-weight:700; font-size:78px;
          letter-spacing:-.03em; line-height:1.04; margin-top:auto; }
  .sub { font-size:29px; color:var(--fg-dim); margin-top:22px; line-height:1.35; }
  .pills { display:flex; gap:14px; margin-top:auto; flex-wrap:wrap; }
  .pill { font-family:'JetBrains Mono',monospace; font-weight:500; font-size:20px;
          color:var(--zon); border:1.5px solid rgba(47,224,172,.34);
          border-radius:999px; padding:11px 20px; line-height:1; }
  .rule { position:absolute; left:0; right:0; bottom:0; height:6px;
          background:linear-gradient(90deg,var(--zon),var(--zon-deep) 55%,transparent); }
</style></head><body>
<div class="grid"></div><div class="aura"></div>
<div class="inner">
  <div class="brand">
    <span class="rune"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none">$rune</span>
    <span><div class="name">zonai</div><div class="domain">$domain</div></span>
  </div>
  <div class="head">$headline</div>
  <div class="sub">$sub</div>
  <div class="pills">$pills</div>
</div>
<div class="rule"></div>
</body></html>
HTML

  # Chrome reports a bad flag on stderr and still exits 0, so check the file
  # itself rather than the status. Only the two macOS sandbox lines are noise.
  rm -f "$out"
  "$chrome" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 --window-size=1200,630 \
    --virtual-time-budget=8000 \
    --screenshot="$out" "file://$work/card.html" 2>&1 |
    grep -viE 'task_policy_set|Trying to load the allocator' || true
  [[ -s $out ]] || { echo "chrome wrote no screenshot for $out" >&2; exit 1; }
  echo "wrote $out ($(magick identify -format '%wx%h' "$out"))"
}

card "$root/apps/website/web/images/og.png" \
  'zonai.dev' \
  'Your schema is the API.' \
  'A batteries-included Dart backend framework.' \
  auth 'live query streams' rules cron 'one binary'

card "$root/apps/docs/web/images/og.png" \
  'docs.zonai.dev' \
  'Zonai documentation.' \
  'Everything from your first table to production deployment.' \
  'quick start' operations rules streaming deployment

echo done
