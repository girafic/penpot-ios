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
BASE=26   # PDF natural size in pt — sets the size UIKit uses in context menus / swipe
          # actions (it ignores SwiftUI's frame there); tuned to match SF Symbols. List rows
          # (.frame(18)) and empty states (.frame(48)) scale this vector crisply.

command -v rsvg-convert >/dev/null || { echo "error: rsvg-convert not found (brew install librsvg)"; exit 1; }
rm -rf "$OUT_DIR"   # rebuild the whole group cleanly (drops any stale renditions)

# asset-name  penpot-source-name   (asset becomes ic-<asset-name>)
ICONS=(
  "add:add"
  "delete:delete"
  "folder:folder"
  "user:user"
  "lock:lock"
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
  "view-as-icons:view-as-icons"   # files grid layout toggle
  "view-as-list:view-as-list"     # files list layout toggle
  "history:history"         # version history (clock with a rewind arrow)
  "clock:clock"             # recent searches
  "curve:curve"             # pencil — rename / edit
  "search:search"
  "code:code"               # the board detail's Inspect mode
  "download:download"
  "filter:filter"
  "at:at"                   # @mention
  "play:play"               # prototype view mode
  "share:share"
  "exit:exit"               # leave team / log out
  "arrow-down:arrow-down"   # dropdown chevron (Penpot's select arrow)
  "arrow-right:arrow-right" # row disclosure chevron
  "close:close"
  "files:files"             # duplicate
  "reload:reload"           # restore / reopen
  "boards-thumbnail:boards-thumbnail"   # canvas title of the file's thumbnail board
  "component:component"     # canvas title of a main component / variant container
  "swatches:swatches"       # a file's colors (Assets)
  "text-palette:text-palette"   # a file's typographies (Assets)
  "tokens:tokens"           # a file's design tokens (Assets)
)

# Icons Penpot doesn't ship, drawn in its style (16x16 grid, 1.33 stroke, round caps —
# Penpot's own set is Feather scaled to 2/3) and kept in Scripts/penpot-icons-extra/.
# They are already in final form (some use a deliberate fill), so they skip normalization.
EXTRA_DIR="$SCRIPT_DIR/penpot-icons-extra"
EXTRA_ICONS=(bell key contrast camera users send pin-off comment-add
             layout-template library-off filter-active
             info-i)   # Penpot's own `info` is an exclamation mark ("!"), which reads as a warning

mkdir -p "$OUT_DIR"

# Top-level Contents.json — a plain group (NO namespace) so each imageset is addressable
# by its bare name, e.g. Image("ic-add"). (provides-namespace would require "PenpotIcons/…".)
cat > "$OUT_DIR/Contents.json" <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

write_contents() {   # $1 = imageset dir, $2 = asset name
  cat > "$1/Contents.json" <<JSON
{
  "images" : [
    { "filename" : "ic-$2.pdf", "idiom" : "universal" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
JSON
}

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

  # Convert to a single-scale VECTOR PDF via rsvg (renders Penpot's tight path encoding
  # perfectly, unlike iOS's asset-catalog SVG renderer). PDF keeps a small natural size
  # (16pt, the viewBox) so UIKit renders it correctly in context menus / swipe actions —
  # a large-base raster showed at its full point size there. "preserves-vector-representation"
  # lets SwiftUI scale it up crisply (e.g. 48pt empty states).
  rsvg-convert -f pdf -w "$BASE" -h "$BASE" "$tmp_svg" -o "$set/ic-$asset.pdf"
  rm -f "$tmp_svg"
  write_contents "$set" "$asset"
  echo "  ✓ ic-$asset  (from $src.svg)"
done

for asset in "${EXTRA_ICONS[@]}"; do
  set="$OUT_DIR/ic-$asset.imageset"
  mkdir -p "$set"
  rsvg-convert -f pdf -w "$BASE" -h "$BASE" "$EXTRA_DIR/$asset.svg" -o "$set/ic-$asset.pdf"
  write_contents "$set" "$asset"
  echo "  ✓ ic-$asset  (drawn, penpot-icons-extra/$asset.svg)"
done

echo "Done → $OUT_DIR"
