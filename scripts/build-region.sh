#!/usr/bin/env bash
# Builds the selected layers of one region and its catalog fragment.
# Env: REGION = mapsforge key, or key=geofabrik/path when the Geofabrik path differs, TYPES (all|routes|dem|contours), OUT, WORK; optional PARALLEL, WRITER_TYPE, JAVA_OPTS.
set -euo pipefail
: "${REGION:?}" "${OUT:?}" "${WORK:?}"
D=$(cd "$(dirname "$0")" && pwd)
TYPES=${TYPES:-all}
GEOFABRIK=${REGION#*=}
REGION=${REGION%%=*}
export GEOFABRIK
[[ "$GEOFABRIK" =~ ^[a-z0-9-]+(/[a-z0-9-]+)*$ ]] || { echo "Invalid Geofabrik path: $GEOFABRIK" >&2; exit 2; }
[[ "$REGION" =~ ^[a-z0-9-]+(/[a-z0-9-]+)*$ ]] || { echo "Invalid REGION: $REGION" >&2; exit 2; }
export BASE=${REGION//\//_}
mkdir -p "$OUT" "$WORK/$BASE"
curl -fsSL --retry 5 -o "$OUT/$BASE.poly" "https://download.geofabrik.de/${GEOFABRIK}.poly" \
  || { echo "Geofabrik path ${GEOFABRIK} not found (https://download.geofabrik.de/${GEOFABRIK}.poly)" >&2; exit 1; }
export BBOX=$(python3 "$D/region-info.py" "$OUT/$BASE.poly")
last=${REGION##*/}
NAME=$(python3 -c 'import sys; print(sys.argv[1].replace("-"," ").title())' "$last")
echo "Region $REGION, name $NAME, bbox $BBOX"
export WORK="$WORK/$BASE"
if [ "$TYPES" = all ] || [ "$TYPES" = routes ]; then
  "$D/build-routes.sh"
  rm -rf "$WORK"/*
fi
if [ "$TYPES" = all ] || [ "$TYPES" = dem ] || [ "$TYPES" = contours ]; then
  "$D/build-dem.sh"
  if [ "$TYPES" = all ] || [ "$TYPES" = contours ]; then
    HGT_ZIP="$OUT/$BASE.dem.zip" WRITER_TYPE=hd "$D/build-contours.sh"
  fi
  if [ "$TYPES" = contours ]; then
    rm -f "$OUT/$BASE.dem.zip" "$OUT/$BASE.dem.meta.json"
  fi
fi
python3 "$D/build-catalog.py" "$OUT" "$REGION" "$NAME" "$BBOX" "layers-$(date -u +%Y-%m)/"
