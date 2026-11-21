#!/usr/bin/env bash
# Cuts one region from its planet block with the outline mapping/poly/<key>.poly (osmium extract, smart strategy: ways that cross the
# outline keep all their nodes, and multipolygon and boundary relations keep all their members, as in the Geofabrik extracts), so that
# the tourist layer and the border need no Geofabrik. With complete_ways, areas reaching beyond the outline (deserts in Egypt) lost
# their outer members and were dropped by the map writer (tourist layer of africa/egypt 27 % smaller, run 44854005546).
# Usage: osm-region.sh block.osm.pbf key output.osm.pbf. Env: OUT (measurements), WORK.
set -euo pipefail
: "${OUT:?}" "${WORK:?}"
D=$(cd "$(dirname "$0")" && pwd)
block=$1 key=$2 output=$3
mkdir -p "$WORK" "$OUT" "$(dirname "$output")"
"$D/region-poly.sh" "$key" "$WORK/extract.poly"
"$D/measure.sh" osm-region osmium extract --overwrite -s smart -S types=multipolygon,boundary -p "$WORK/extract.poly" -o "$output" "$block"
osmium fileinfo "$output"
