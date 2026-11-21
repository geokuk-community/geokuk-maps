#!/usr/bin/env bash
# Refreshes mapping/copernicus-tilelist.txt, the list of Copernicus GLO-30 tiles (AWS Open Data copernicus-dem-30m, tileList.txt),
# which cop2hgt.py, region-parts.py and dem-source.py read instead of downloading it in every job.
# Run by the workflow Copernicus tile list (.github/workflows/tilelist.yml), which proposes the change as a pull request.
# The data set has not changed since 2022; a changed list changes the Copernicus fingerprint of the regions it touches (dem-source.py).
set -euo pipefail
R=$(cd "$(dirname "$0")/.." && pwd)
out="$R/mapping/copernicus-tilelist.txt"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL --retry 5 --retry-delay 10 --connect-timeout 30 https://copernicus-dem-30m.s3.amazonaws.com/tileList.txt | tr -d '\r' | sed '/^$/d' | sort -u > "$tmp"
bad=$(grep -cvE '^Copernicus_DSM_COG_10_[NS][0-9]{2}_00_[EW][0-9]{3}_00_DEM$' "$tmp" || true)
count=$(wc -l < "$tmp")
[ "$bad" = 0 ] && [ "$count" -gt 20000 ] || { echo "Unexpected tile list: $count lines, $bad not matching" >&2; exit 1; }
if cmp -s "$tmp" "$out"; then
  echo "Tile list unchanged ($count tiles)"
else
  cp "$tmp" "$out"
  echo "Tile list updated ($count tiles)"
fi
