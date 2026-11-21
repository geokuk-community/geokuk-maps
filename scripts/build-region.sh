#!/usr/bin/env bash
# Builds the selected layers of one region and its catalog fragment.
# Env: REGION = mapsforge key, optionally key=geofabrik/path when the Geofabrik path differs and/or key:part/total[/lat|/lon] to build
# one part of the dem and contours layers (the tourist layer is not split), TAG (release tag, default layers-YYYY-MM), TYPES (all|tourist|dem|contours), OUT, WORK; optional DEM_REUSE (changed|all), PARALLEL, WRITER_TYPE, JAVA_OPTS.
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
"$D/region-poly.sh" "$REGION" "$OUT/$BASE.poly"
BBOX=$(python3 "$D/region-info.py" "$OUT/$BASE.poly")
export BBOX
export PART_SUFFIX=""
if [ -n "$PARTSPEC" ]; then
  IFS=/ read -r part total axis <<< "$PARTSPEC"
  BBOX=$(python3 "$D/region-parts.py" "$BBOX" "$part" "$total" ${axis:+"$axis"})
  export BBOX PART_SUFFIX=".$part"
  [ "$TYPES" = tourist ] && { echo "The tourist layer is not split into parts" >&2; exit 2; }
  [ "$TYPES" = all ] && TYPES=dem+contours
fi
# A region in mapping/region-parts.json builds dem and contours only in its parts (key:part/total); as a whole only its tourist layer.
if [ -z "$PARTSPEC" ] && [ "$TYPES" != tourist ] && [ -n "$(python3 "$D/region-list.py" --parts "$REGION")" ]; then
  echo "$REGION: dem and contours are built in parts (mapping/region-parts.json), not as a whole"
  if [ "$TYPES" = all ]; then TYPES=tourist; else TYPES=none; fi
fi
# DMR 4G (bare ground) replaces the Copernicus surface model in the Czech Republic.
[ "$REGION" = europe/czech-republic ] && export DEM_CUZK=1
# Dem and contours stay in the previous release when their sources have not changed (mapping/dem-manifest.json, dem-source.py);
# DEM_REUSE=all builds them anyway (for example after a change of the processing).
[[ "${DEM_REUSE:-changed}" =~ ^(changed|all)$ ]] || { echo "Invalid DEM_REUSE: $DEM_REUSE" >&2; exit 2; }
if [ "${DEM_REUSE:-changed}" = changed ] && [ "$TYPES" != tourist ] && python3 "$D/dem-source.py" reuse "$REGION"; then
  if [ "$TYPES" = all ]; then TYPES=tourist; else TYPES=none; fi
fi
last=${REGION##*/}
NAME=$(python3 -c 'import sys; print(sys.argv[1].replace("-"," ").title())' "$last")
echo "Region $REGION, name $NAME, bbox $BBOX"
export WORK="$WORK/$BASE"
if [ "$TYPES" = all ] || [ "$TYPES" = tourist ]; then
  "$D/build-tourist.sh"
  rm -rf "${WORK:?}"/*
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
# Nothing to build: the catalog fragment stays empty and the outline is not published again.
[ "$TYPES" = none ] && rm -f "$OUT/$BASE.poly"
PART_TOTAL=${total:-} python3 "$D/build-catalog.py" "$OUT" "$REGION" "$NAME" "$BBOX" "${TAG:-layers-$(date -u +%Y-%m)}/"
