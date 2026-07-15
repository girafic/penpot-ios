#!/usr/bin/env bash
#
# Fetch the Penpot UI icons used by the app and bundle them as tintable template
# vector assets in Sources/Assets.xcassets/PenpotIcons/.
#
# Penpot's icons are stroke-outline SVGs (mostly on a 16x16 grid) that rely on external
# CSS (`fill:none; stroke:currentColor; stroke-width`) — rendered as-is they'd fill solid
# black, and several are inconsistent (missing stroke, hardcoded colors, odd grids). This
# script normalizes each one: strips any baked stroke/fill, then sets a solid black stroke
# with a consistent width so Xcode's "template" rendering intent can tint them like an
# SF Symbol. Re-run to update the set (idempotent).
#
# Requires: curl, python3, and rsvg-convert (`brew install librsvg`).
# Usage: ./Scripts/fetch-penpot-icons.sh
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/penpot/penpot/develop/frontend/resources/images/icons"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/../Sources/Assets.xcassets/PenpotIcons"
STROKE_WIDTH="1.33"
BASE=48   # base logical size in pt (largest use); @2x/@3x derived from it

command -v rsvg-convert >/dev/null || { echo "error: rsvg-convert not found (brew install librsvg)"; exit 1; }
rm -rf "$OUT_DIR"   # rebuild the whole group cleanly (drops any stale renditions)

# asset-name  penpot-source-name   (asset becomes ic-<asset-name>)
ICONS=(
  "add:add"
  "delete:delete"
  "folder:folder"
  "user:user"
  "lock:lock"
  "info:info"
  "document:document"
  "clipboard:clipboard"
  "text:text"
  "library:library"
  "comments:comments"
  "tick:tick"
  "msg-warning:msg-warning"
  "expand:expand"
  "open-link:open-link"
  "help:help"
  "img:img"
  "pin:pin"
  "board:board"
  "arrow-left:arrow-left"   # navigation back-button chevron
  "menu:menu"               # three-dot overflow menu
)

mkdir -p "$OUT_DIR"

# Top-level Contents.json — a plain group (NO namespace) so each imageset is addressable
# by its bare name, e.g. Image("ic-add"). (provides-namespace would require "PenpotIcons/…".)
cat > "$OUT_DIR/Contents.json" <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

for entry in "${ICONS[@]}"; do
  asset="${entry%%:*}"
  src="${entry##*:}"
  set="$OUT_DIR/ic-$asset.imageset"
  mkdir -p "$set"

  raw="$(curl -fsSL "$REPO_RAW/$src.svg")"
  tmp_svg="$(mktemp -t ic-$asset.XXXX.svg)"
  SVG_RAW="$raw" STROKE_WIDTH="$STROKE_WIDTH" python3 - "$tmp_svg" <<'PY'
import os, re, sys
svg = os.environ["SVG_RAW"]
out = sys.argv[1]
sw = os.environ["STROKE_WIDTH"]

# Drop any baked presentation attributes anywhere in the file (colors, widths, and the
# line-cap/join attrs we re-add) so injecting our own can't produce duplicate attributes.
for attr in ("stroke-width", "stroke-linecap", "stroke-linejoin", "stroke", "fill"):
    svg = re.sub(rf'\s{attr}="[^"]*"', "", svg)

# Inject a consistent, tintable stroke on the root <svg> element (attributes inherit
# down to child paths). Solid black so the "template" rendering intent can recolor it.
inject = f' fill="none" stroke="#000000" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"'
svg = re.sub(r'<svg\b', '<svg' + inject, svg, count=1)

with open(out, "w") as f:
    f.write(svg.strip() + "\n")
PY

  # Rasterize with rsvg (renders Penpot's tight path encoding perfectly) instead of shipping
  # the SVG — iOS's asset-catalog SVG renderer garbles some of these paths at small sizes.
  # Base logical size 48pt (the largest use, empty states); @2x/@3x for crisp downscaling.
  rsvg-convert -w "$BASE"   -h "$BASE"   "$tmp_svg" -o "$set/ic-$asset@1x.png"
  rsvg-convert -w "$((BASE*2))" -h "$((BASE*2))" "$tmp_svg" -o "$set/ic-$asset@2x.png"
  rsvg-convert -w "$((BASE*3))" -h "$((BASE*3))" "$tmp_svg" -o "$set/ic-$asset@3x.png"
  rm -f "$tmp_svg"

  cat > "$set/Contents.json" <<JSON
{
  "images" : [
    { "filename" : "ic-$asset@1x.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "ic-$asset@2x.png", "idiom" : "universal", "scale" : "2x" },
    { "filename" : "ic-$asset@3x.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : {
    "template-rendering-intent" : "template"
  }
}
JSON
  echo "  ✓ ic-$asset  (from $src.svg)"
done

echo "Done → $OUT_DIR"
