#!/usr/bin/env bash
# Region outline without buffer from the OSM administrative boundaries (region-polygon.py); the region .poly when that fails.
# Usage: build-border.sh output.poly. Env: REGION (mapsforge key, optionally key=geofabrik/path), GEOFABRIK (Geofabrik path), OUT, BASE, WORK;
# optional OSM_PBF (extract of the region, used instead of the Geofabrik download).
set -euo pipefail
: "${REGION:?}" "${GEOFABRIK:?}" "${OUT:?}" "${BASE:?}" "${WORK:?}"
D=$(cd "$(dirname "$0")" && pwd)
border=$1
tmp="$WORK/border"
mkdir -p "$tmp" "$OUT"
# The workflow prints the measurements even when no step was measured (e.g. the Geofabrik index could not be downloaded).
touch "$OUT/measurements.tsv"
key=${REGION%%:*}
[ -s "$OUT/$BASE.poly" ] || "$D/region-poly.sh" "${key%%=*}" "$OUT/$BASE.poly"
pbf=${OSM_PBF:-$tmp/region.osm.pbf}
if { [ -n "${OSM_PBF:-}" ] || "$D/geofabrik-pbf.sh" "$GEOFABRIK" "$pbf" border-pbf; } \
  && "$D/measure.sh" border-polygon python3 "$D/region-polygon.py" "$pbf" "$OUT/$BASE.poly" "$border" "$tmp"; then
  :
else
  echo "::warning::Region outline from OSM boundaries failed for $GEOFABRIK, using the region polygon"
  cp "$OUT/$BASE.poly" "$border"
fi
rm -rf "$tmp"
