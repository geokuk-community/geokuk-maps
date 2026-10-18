#!/usr/bin/env bash
# Region outline without buffer from the OSM administrative boundaries (region-polygon.py); the Geofabrik .poly when that fails.
# Usage: build-border.sh output.poly. Env: GEOFABRIK (Geofabrik path), OUT, BASE, WORK.
set -euo pipefail
: "${GEOFABRIK:?}" "${OUT:?}" "${BASE:?}" "${WORK:?}"
D=$(cd "$(dirname "$0")" && pwd)
border=$1
tmp="$WORK/border"
mkdir -p "$tmp" "$OUT"
[ -s "$OUT/$BASE.poly" ] || curl -fsSL --retry 5 -o "$OUT/$BASE.poly" "https://download.geofabrik.de/${GEOFABRIK}.poly"
if "$D/measure.sh" border-pbf curl -fL --retry 5 --retry-delay 10 -o "$tmp/region.osm.pbf" "https://download.geofabrik.de/${GEOFABRIK}-latest.osm.pbf" \
  && "$D/measure.sh" border-polygon python3 "$D/region-polygon.py" "$tmp/region.osm.pbf" "$OUT/$BASE.poly" "$border" "$tmp"; then
  :
else
  echo "::warning::Region outline from OSM boundaries failed for $GEOFABRIK, using the Geofabrik polygon"
  cp "$OUT/$BASE.poly" "$border"
fi
rm -rf "$tmp"
