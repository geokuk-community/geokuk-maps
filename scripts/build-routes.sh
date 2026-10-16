#!/usr/bin/env bash
# Routes (hiking, foot, bicycle, mtb, horse, ski) from a Geofabrik pbf into a mapsforge .map.
# Env: REGION (mapsforge key), optional GEOFABRIK (Geofabrik path when different), BBOX (south,west,north,east), BASE (file name), OUT, WORK; optional WRITER_TYPE (ram|hd), JAVA_OPTS.
set -euo pipefail
: "${REGION:?}" "${BBOX:?}" "${BASE:?}" "${OUT:?}" "${WORK:?}"
D=$(cd "$(dirname "$0")" && pwd)
R=$(dirname "$D")
source "$D/check-inputs.sh"
mkdir -p "$OUT" "$WORK"
export OUT
pbf="$WORK/source.osm.pbf"
"$D/measure.sh" download-pbf curl -fL --retry 5 --retry-delay 10 -o "$pbf" "https://download.geofabrik.de/${GEOFABRIK:-$REGION}-latest.osm.pbf"
for attempt in 1 2 3; do
  curl -fsSL --retry 5 "https://download.geofabrik.de/${GEOFABRIK:-$REGION}-latest.osm.pbf.md5" | awk -v f="$pbf" '{print $1"  "f}' | md5sum -c - && break
  [ "$attempt" -lt 3 ] || exit 1
  "$D/measure.sh" download-pbf curl -fL --retry 5 --retry-delay 10 -o "$pbf" "https://download.geofabrik.de/${GEOFABRIK:-$REGION}-latest.osm.pbf"
done
stamp=$(osmium fileinfo -g header.option.osmosis_replication_timestamp "$pbf" || true)
stamp=${stamp:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
"$D/measure.sh" osmium-filter osmium tags-filter --overwrite -o "$WORK/routes.pbf" "$pbf" r/route=hiking,foot,bicycle,mtb,horse,ski
rm -f "$pbf"
"$D/measure.sh" addfmreltags perl "$D/addfmreltags.pl" "$WORK/routes.pbf" "$WORK"
test -s "$WORK/routes.pbf-fmrel.pbf"
out="$OUT/${BASE}.routes.map"
"$D/measure.sh" write-map osmosis -q --rb file="$WORK/routes.pbf-fmrel.pbf" \
  --mw file="$out" type="${WRITER_TYPE:-ram}" bbox="$BBOX" threads="$(nproc)" \
  tag-conf-file="$R/mapping/routes.xml" zoom-interval-conf=5,0,7,10,8,11,14,12,21 \
  comment="(c) OpenStreetMap contributors (ODbL), Geofabrik $stamp"
"$D/write-meta.py" routes "$out" "${stamp%%T*}" "Geofabrik ${GEOFABRIK:-$REGION}-latest.osm.pbf ($stamp)" "$R/licenses/OSM.txt" '{"zoom":{"min":0,"max":21}}'
curl -fsSL --retry 3 -o "$OUT/${BASE}.poly" "https://download.geofabrik.de/${GEOFABRIK:-$REGION}.poly" || true
