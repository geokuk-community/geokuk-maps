#!/usr/bin/env bash
# Cuts one region from its planet block with the outline mapping/poly/<key>.poly (osmium extract, complete_ways strategy: ways that
# cross the outline keep all their nodes, as in the Geofabrik extracts), so that the tourist layer and the border need no Geofabrik.
# Usage: osm-region.sh block.osm.pbf key output.osm.pbf. Env: OUT (measurements), WORK.
set -euo pipefail
: "${OUT:?}" "${WORK:?}"
D=$(cd "$(dirname "$0")" && pwd)
block=$1 key=$2 output=$3
mkdir -p "$WORK" "$(dirname "$output")"
"$D/region-poly.sh" "$key" "$WORK/extract.poly"
"$D/measure.sh" osm-region osmium extract --overwrite -s complete_ways -p "$WORK/extract.poly" -o "$output" "$block"
osmium fileinfo "$output"
