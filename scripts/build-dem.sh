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
license="$R/licenses/COPERNICUS.txt"
if [ "${DEM_CUZK:-0}" = 1 ]; then
  "$D/measure.sh" cuzk2hgt python3 "$D/cuzk2hgt.py" "$BBOX" "$WORK/hgt" "$WORK/cuzk"
  license="$WORK/LICENSES.txt"
  cat "$R/licenses/CUZK.txt" <(echo) "$R/licenses/COPERNICUS.txt" > "$license"
fi
out="$OUT/${BASE}.dem${PART_SUFFIX:-}.zip"
rm -f "$out"
"$D/measure.sh" zip-hgt bash -c "cp '$license' '$WORK/hgt/LICENSE.txt' && cd '$WORK/hgt' && zip -q -j -9 '$out' *.hgt LICENSE.txt"
stamp=$(cat "$WORK/dem-date.txt" 2>/dev/null || date -u +%F)
if [ "${DEM_CUZK:-0}" = 1 ]; then
  "$D/write-meta.py" dem "$out" "$stamp" "ČÚZK DMR 4G; Copernicus GLO-30 DEM (AWS Open Data copernicus-dem-30m) outside the Czech Republic" "$license" \
    '{"license":"CC BY 4.0 (ČÚZK); Copernicus COP-DEM-GLO-30-F","attribution":"Elevation: Zdroj: ČÚZK, CC BY 4.0; Copernicus DEM GLO-30 © DLR/Airbus, ESA","attributionFull":"Zdroj: ČÚZK, CC BY 4.0. Copernicus: produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved."}'
else
  "$D/write-meta.py" dem "$out" "$stamp" "Copernicus GLO-30 DEM (AWS Open Data copernicus-dem-30m)" "$license"
fi
