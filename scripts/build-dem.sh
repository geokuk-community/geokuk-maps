#!/usr/bin/env bash
# Copernicus GLO-30 DEM -> HGT 1" in a zip. Env: BBOX, BASE, OUT, WORK.
set -euo pipefail
: "${BBOX:?}" "${BASE:?}" "${OUT:?}" "${WORK:?}"
D=$(cd "$(dirname "$0")" && pwd)
R=$(dirname "$D")
source "$D/check-inputs.sh"
mkdir -p "$OUT" "$WORK"
export OUT
"$D/measure.sh" cop2hgt python3 "$D/cop2hgt.py" "$BBOX" "$WORK/hgt" "$WORK"
out="$OUT/${BASE}.dem.zip"
rm -f "$out"
"$D/measure.sh" zip-hgt bash -c "cp '$R/licenses/COPERNICUS.txt' '$WORK/hgt/LICENSE.txt' && cd '$WORK/hgt' && zip -q -j -9 '$out' *.hgt LICENSE.txt"
stamp=$(cat "$WORK/dem-date.txt" 2>/dev/null || date -u +%F)
"$D/write-meta.py" dem "$out" "$stamp" "Copernicus GLO-30 DEM (AWS Open Data copernicus-dem-30m)" "$R/licenses/COPERNICUS.txt"
