#!/usr/bin/env bash
# Contour lines (10 m step, major every 100, medium every 50) from the HGT zip into a mapsforge .map.
# Env: HGT_ZIP, BBOX, BASE, OUT, WORK; optional WRITER_TYPE (default hd), PARALLEL, JAVA_OPTS. Requires pyhgtmap and osmium.
set -euo pipefail
: "${HGT_ZIP:?}" "${BBOX:?}" "${BASE:?}" "${OUT:?}" "${WORK:?}"
D=$(cd "$(dirname "$0")" && pwd)
R=$(dirname "$D")
source "$D/check-inputs.sh"
mkdir -p "$OUT" "$WORK/hgt" "$WORK/contours"
export OUT
unzip -q -o "$HGT_ZIP" -d "$WORK/hgt"
cd "$WORK"
i=0
: > commands.txt
for f in hgt/*.hgt; do
  i=$((i + 1))
  b=$(basename "$f" .hgt)
  echo "pyhgtmap --step=10 --line-cat=100,50 --pbf --max-nodes-per-way=1000 --simplifyContoursEpsilon=0.00001 --max-nodes-per-tile=0 --start-node-id=$((i * 1000000000)) --start-way-id=$((i * 1000000000)) --output-prefix=contours/$b $f" >> commands.txt
done
( while sleep 30; do echo "resources: $(free -m | sed -n 2p) | disk: $(df -m / | tail -1 | tr -s " " | cut -d" " -f3,4) MB | load: $(cut -d" " -f1-3 /proc/loadavg) | contours: $(du -sm contours | cut -f1) MB, $(ls contours | wc -l) files"; done ) &
monitor=$!
"$D/measure.sh" pyhgtmap bash -c "xargs -P ${PARALLEL:-2} -I{} bash -c '{}' < commands.txt"
kill "$monitor" 2>/dev/null || true
# The tile files are sorted and have disjoint ids, so the merge streams; sort would hold everything in memory.
"$D/measure.sh" osmium-merge osmium merge --overwrite -o contours.pbf contours/*.pbf || "$D/measure.sh" osmium-sort osmium sort --overwrite -o contours.pbf contours/*.pbf
out="$OUT/${BASE}.contours.map"
"$D/measure.sh" write-map osmosis -q --rb file=contours.pbf \
  --mw file="$out" type="${WRITER_TYPE:-hd}" bbox="$BBOX" threads="$(nproc)" \
  tag-conf-file="$R/mapping/contours.xml" zoom-interval-conf=5,0,7,10,8,11,14,12,21 \
  comment="Contours from Copernicus GLO-30 DEM. Produced using Copernicus WorldDEM-30 (c) DLR e.V. 2010-2014 and (c) Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved. The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30."
"$D/write-meta.py" contours "$out" "$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["dataDate"])' "${HGT_ZIP%.zip}.meta.json" 2>/dev/null || date -u +%F)" "Copernicus GLO-30 DEM (AWS Open Data)" "$R/licenses/COPERNICUS.txt" '{"zoom":{"min":12,"max":21},"contourInterval":10}'
