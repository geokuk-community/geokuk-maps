#!/usr/bin/env bash
# Tourist layer from a Geofabrik pbf into a mapsforge .map: routes (hiking, foot, bicycle, mtb, horse, ski) with the names of official
# hiking routes, and the points, lines and areas of mapping/tourist-features.xml.
# Env: REGION (mapsforge key), optional GEOFABRIK (Geofabrik path when different), BBOX (south,west,north,east), BASE (file name), OUT, WORK;
# optional WRITER_TYPE (auto|ram|hd; auto = hd when the filtered input exceeds WRITER_RAM_LIMIT_MB, default 400), JAVA_OPTS.
set -euo pipefail
: "${REGION:?}" "${BBOX:?}" "${BASE:?}" "${OUT:?}" "${WORK:?}"
D=$(cd "$(dirname "$0")" && pwd)
R=$(dirname "$D")
source "$D/check-inputs.sh"
mkdir -p "$OUT" "$WORK"
export OUT
pbf="$WORK/source.osm.pbf"
"$D/measure.sh" download-pbf curl -fL --retry 5 --retry-delay 10 -o "$pbf" "https://download.geofabrik.de/${GEOFABRIK:-$REGION}-latest.osm.pbf"
url="https://download.geofabrik.de/${GEOFABRIK:-$REGION}-latest.osm.pbf"
for attempt in 1 2 3; do
  expected=""
  for try in 1 2 3 4 5 6; do
    expected=$(curl -fsSL "$url.md5" | awk '{print $1}') && [ -n "$expected" ] && break
    expected=""
    sleep $((try * 20))
  done
  if [ -z "$expected" ]; then
    echo "::warning::Checksum of $url is not available; checking that the file can be read completely"
    osmium fileinfo -e "$pbf" > /dev/null && break
    [ "$attempt" -lt 3 ] || exit 1
    sleep 60
    "$D/measure.sh" download-pbf curl -fL --retry 5 --retry-delay 10 -o "$pbf" "$url"
    continue
  fi
  [ "$(md5sum "$pbf" | awk '{print $1}')" = "$expected" ] && break
  [ "$attempt" -lt 3 ] || { echo "Checksum mismatch for $url" >&2; exit 1; }
  sleep 60
  "$D/measure.sh" download-pbf curl -fL --retry 5 --retry-delay 10 -o "$pbf" "$url"
done
stamp=$(osmium fileinfo -g header.option.osmosis_replication_timestamp "$pbf" || true)
stamp=${stamp:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
"$D/measure.sh" osmium-routes osmium tags-filter --overwrite -o "$WORK/routes.pbf" "$pbf" r/route=hiking,foot,bicycle,mtb,horse,ski
mapfile -t features < <(python3 "$D/tourist-filter.py")
"$D/measure.sh" osmium-features osmium tags-filter --overwrite -o "$WORK/features.pbf" "$pbf" "${features[@]}"
rm -f "$pbf"
"$D/measure.sh" addfmreltags perl "$D/addfmreltags.pl" "$WORK/routes.pbf" "$WORK"
test -s "$WORK/routes.pbf-fmrel.pbf"
writer=${WRITER_TYPE:-auto}
input_mb=$(( ($(stat -c %s "$WORK/features.pbf") + $(stat -c %s "$WORK/routes.pbf-fmrel.pbf")) / 1048576 ))
if [ "$writer" = auto ]; then
  writer=ram
  [ "$input_mb" -le "${WRITER_RAM_LIMIT_MB:-400}" ] || writer=hd
fi
echo "Writer input $input_mb MB, type=$writer"
out="$OUT/${BASE}.tourist.map"
# The routes are the last source, so their copy of a way (with the fmrel* tags) wins over the same way from the features.
"$D/measure.sh" "write-map-$writer" osmosis -q --rb file="$WORK/features.pbf" --rb file="$WORK/routes.pbf-fmrel.pbf" \
  --merge conflictResolutionMethod=lastSource --tt file="$R/mapping/tourist-transform.xml" \
  --mw file="$out" type="$writer" bbox="$BBOX" threads="$(nproc)" \
  tag-conf-file="$R/mapping/tourist.xml" zoom-interval-conf=5,0,7,10,8,11,14,12,21 \
  comment="(c) OpenStreetMap contributors (ODbL), Geofabrik $stamp"
"$D/write-meta.py" tourist "$out" "${stamp%%T*}" "Geofabrik ${GEOFABRIK:-$REGION}-latest.osm.pbf ($stamp)" "$R/licenses/OSM.txt" '{"zoom":{"min":0,"max":21}}'
curl -fsSL --retry 3 -o "$OUT/${BASE}.poly" "https://download.geofabrik.de/${GEOFABRIK:-$REGION}.poly" || true
# Tags that the base map from download.mapsforge.org also has would be drawn twice; list them for review.
if curl -fsSL --retry 3 -r 0-1048575 -o "$WORK/base-head.map" "https://download.mapsforge.org/maps/v5/${REGION}.map"; then
  comm -12 <(python3 "$D/map-tags.py" "$WORK/base-head.map" | sort) <(python3 "$D/map-tags.py" "$out" | sort) \
    | grep -v '^way fmrel' | sed 's/^/::notice::tag also in the base map: /' || true
fi
