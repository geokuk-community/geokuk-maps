#!/usr/bin/env bash
# Tourist layer from an OSM extract (Geofabrik, or OSM_PBF cut from the planet) into a mapsforge .map: routes (hiking, foot, bicycle, mtb, horse, ski) with the names of official
# hiking routes, and the points, lines and areas of mapping/tourist-features.xml.
# Env: REGION (mapsforge key), optional GEOFABRIK (Geofabrik path when different), BBOX (south,west,north,east), BASE (file name), OUT, WORK;
# optional OSM_PBF (extract of the region, used instead of the Geofabrik download) with OSM_PLANET (planet name) and OSM_STAMP
# (data timestamp when the extract has none), MAPSFORGE_MIRROR, WRITER_TYPE (auto|ram|hd; auto = hd when the filtered input exceeds WRITER_RAM_LIMIT_MB, default 400), JAVA_OPTS.
set -euo pipefail
: "${REGION:?}" "${BBOX:?}" "${BASE:?}" "${OUT:?}" "${WORK:?}"
D=$(cd "$(dirname "$0")" && pwd)
R=$(dirname "$D")
source "$D/check-inputs.sh"
mkdir -p "$OUT" "$WORK"
export OUT
if [ -n "${OSM_PBF:-}" ]; then
  pbf=$OSM_PBF
  [ -s "$pbf" ] || { echo "OSM_PBF $pbf is missing" >&2; exit 1; }
  [[ "${OSM_PLANET:-}" =~ ^planet-[0-9]{6}$ ]] || { echo "Invalid OSM_PLANET: ${OSM_PLANET:-}" >&2; exit 2; }
else
  pbf="$WORK/source.osm.pbf"
  "$D/geofabrik-pbf.sh" "${GEOFABRIK:-$REGION}" "$pbf" download-pbf
fi
stamp=$(osmium fileinfo -g header.option.osmosis_replication_timestamp "$pbf" || true)
stamp=${stamp:-${OSM_STAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}}
[[ "$stamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z$ ]] || { echo "Invalid data timestamp: $stamp" >&2; exit 2; }
if [ -n "${OSM_PBF:-}" ]; then
  source_label="OSM planet $stamp"
  source_name="OpenStreetMap $OSM_PLANET.osm.pbf (AWS Open Data), extract $REGION ($stamp)"
else
  source_label="Geofabrik $stamp"
  source_name="Geofabrik ${GEOFABRIK:-$REGION}-latest.osm.pbf ($stamp)"
fi
"$D/measure.sh" osmium-routes osmium tags-filter --overwrite -o "$WORK/routes.pbf" "$pbf" r/route=hiking,foot,bicycle,mtb,horse,ski
mapfile -t features < <(python3 "$D/tourist-filter.py")
"$D/measure.sh" osmium-features osmium tags-filter --overwrite -o "$WORK/features.pbf" "$pbf" "${features[@]}"
[ -n "${OSM_PBF:-}" ] || rm -f "$pbf"
"$D/measure.sh" addfmreltags perl "$D/addfmreltags.pl" "$WORK/routes.pbf" "$WORK"
test -s "$WORK/routes.pbf-fmrel.pbf"
osmium tags-filter --overwrite -o "$WORK/named.pbf" "$WORK/routes.pbf-fmrel.pbf" w/fmrelhikingname
echo "Ways with the name of an official hiking route: $(osmium fileinfo -e -g data.count.ways "$WORK/named.pbf")"
rm -f "$WORK/named.pbf"
writer=${WRITER_TYPE:-auto}
input_mb=$(( ($(stat -c %s "$WORK/features.pbf") + $(stat -c %s "$WORK/routes.pbf-fmrel.pbf")) / 1048576 ))
if [ "$writer" = auto ]; then
  writer=ram
  [ "$input_mb" -le "${WRITER_RAM_LIMIT_MB:-400}" ] || writer=hd
fi
echo "Writer input $input_mb MB, type=$writer"
out="$OUT/${BASE}.tourist.map"
# Osmosis takes the first --rb as the last source, so the copy of a way from the routes (with the fmrel* tags) wins over the same way from the features.
"$D/measure.sh" "write-map-$writer" osmosis -q --rb file="$WORK/routes.pbf-fmrel.pbf" --rb file="$WORK/features.pbf" \
  --merge conflictResolutionMethod=lastSource --tt file="$R/mapping/tourist-transform.xml" \
  --mw file="$out" type="$writer" bbox="$BBOX" threads="$(nproc)" \
  tag-conf-file="$R/mapping/tourist.xml" zoom-interval-conf=5,0,7,10,8,11,14,12,21 \
  comment="(c) OpenStreetMap contributors (ODbL), $source_label"
"$D/write-meta.py" tourist "$out" "${stamp%%T*}" "$source_name" "$R/licenses/OSM.txt" '{"zoom":{"min":0,"max":21}}'
[ -s "$OUT/${BASE}.poly" ] || "$D/region-poly.sh" "$REGION" "$OUT/${BASE}.poly"
# Tags that the mapsforge base map also has would be drawn twice; list them for review (header from the mapsforge mirror).
if curl -fsSL --retry 3 -r 0-1048575 -o "$WORK/base-head.map" "${MAPSFORGE_MIRROR:-https://ftp-stud.hs-esslingen.de/pub/Mirrors/download.mapsforge.org}/maps/v5/${REGION}.map"; then
  comm -12 <(python3 "$D/map-tags.py" "$WORK/base-head.map" | sort) <(python3 "$D/map-tags.py" "$out" | sort) \
    | grep -v '^way fmrel' | sed 's/^/::notice::tag also in the base map: /' || true
fi
