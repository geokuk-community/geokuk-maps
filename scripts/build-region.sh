#!/usr/bin/env bash
# Builds the selected layers of one region and its catalog fragment.
# Env: REGION = mapsforge key, optionally key=geofabrik/path when the Geofabrik path differs and/or key:part/total[/lat|/lon] to build
# one part of the dem and contours layers (routes are not split), TAG (release tag, default layers-YYYY-MM), TYPES (all|routes|dem|contours), OUT, WORK; optional PARALLEL, WRITER_TYPE, JAVA_OPTS.
set -euo pipefail
: "${REGION:?}" "${OUT:?}" "${WORK:?}"
D=$(cd "$(dirname "$0")" && pwd)
TYPES=${TYPES:-all}
PARTSPEC=""
if [[ "$REGION" == *:* ]]; then
  PARTSPEC=${REGION##*:}
  REGION=${REGION%:*}
  [[ "$PARTSPEC" =~ ^[1-9][0-9]*/[1-9][0-9]*(/(lat|lon))?$ ]] || { echo "Invalid part: $PARTSPEC" >&2; exit 2; }
fi
GEOFABRIK=${REGION#*=}
REGION=${REGION%%=*}
export GEOFABRIK
[[ "$GEOFABRIK" =~ ^[a-z0-9-]+(/[a-z0-9-]+)*$ ]] || { echo "Invalid Geofabrik path: $GEOFABRIK" >&2; exit 2; }
[[ "${TAG:-layers-2000-01}" =~ ^layers-[0-9]{4}-[0-9]{2}[a-z0-9-]*$ ]] || { echo "Invalid TAG: $TAG" >&2; exit 2; }
[[ "$REGION" =~ ^[a-z0-9-]+(/[a-z0-9-]+)*$ ]] || { echo "Invalid REGION: $REGION" >&2; exit 2; }
export BASE=${REGION//\//_}
mkdir -p "$OUT" "$WORK/$BASE"
curl -fsSL --retry 5 -o "$OUT/$BASE.poly" "https://download.geofabrik.de/${GEOFABRIK}.poly" \
  || { echo "Geofabrik path ${GEOFABRIK} not found (https://download.geofabrik.de/${GEOFABRIK}.poly)" >&2; exit 1; }
export BBOX=$(python3 "$D/region-info.py" "$OUT/$BASE.poly")
export PART_SUFFIX=""
if [ -n "$PARTSPEC" ]; then
  IFS=/ read -r part total axis <<< "$PARTSPEC"
  BBOX=$(python3 "$D/region-parts.py" "$BBOX" "$part" "$total" ${axis:+"$axis"})
  export BBOX PART_SUFFIX=".$part"
  [ "$TYPES" = routes ] && { echo "Routes are not split into parts" >&2; exit 2; }
  [ "$TYPES" = all ] && TYPES=dem+contours
fi
last=${REGION##*/}
NAME=$(python3 -c 'import sys; print(sys.argv[1].replace("-"," ").title())' "$last")
echo "Region $REGION, name $NAME, bbox $BBOX"
export WORK="$WORK/$BASE"
if [ "$TYPES" = all ] || [ "$TYPES" = routes ]; then
  "$D/build-routes.sh"
  rm -rf "$WORK"/*
fi
if [ "$TYPES" = all ] || [ "$TYPES" = dem ] || [ "$TYPES" = contours ] || [ "$TYPES" = dem+contours ]; then
  "$D/build-dem.sh"
  if [ "$TYPES" = all ] || [ "$TYPES" = contours ] || [ "$TYPES" = dem+contours ]; then
    HGT_ZIP="$OUT/$BASE.dem$PART_SUFFIX.zip" WRITER_TYPE=hd "$D/build-contours.sh"
  fi
  if [ "$TYPES" = contours ]; then
    rm -f "$OUT/$BASE.dem$PART_SUFFIX.zip" "$OUT/$BASE.dem$PART_SUFFIX.meta.json"
  fi
fi
PART_TOTAL=${total:-} python3 "$D/build-catalog.py" "$OUT" "$REGION" "$NAME" "$BBOX" "${TAG:-layers-$(date -u +%Y-%m)}/"
