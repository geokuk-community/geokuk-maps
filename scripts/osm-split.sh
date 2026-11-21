#!/usr/bin/env bash
# Cuts several regions from their planet block with their outlines mapping/poly/<key>.poly in one read of the block (osmium extract
# with a config of several extracts), so that a block is downloaded once per slice of regions
# (scripts/osm-blocks.py slices) instead of once per region: downloading the 14 GB france block took about 15 min for each region
# (run 44886196372). OSM_SPLIT_PASS regions are cut per read (default 3): osmium keeps id sets for each region, about 3.1 GB of RAM
# per region with data even for Monaco (6.3 GB for two), so all regions of a slice in one read would not fit in the 16 GB of a runner.
# Smart strategy, as in the Geofabrik extracts: ways that cross the outline keep all their nodes, and multipolygon and boundary
# relations keep all their members. With complete_ways, areas reaching beyond the outline (deserts in Egypt) lost their outer
# members and were dropped by the map writer (tourist layer of africa/egypt 27 % smaller, run 44854005546).
# Usage: osm-split.sh block.osm.pbf output_dir key [key ...]. Env: OUT (measurements), WORK, optional OSM_SPLIT_PASS.
# Writes output_dir/<base>/region.osm.pbf for each key (base = key with / replaced by _).
set -euo pipefail
: "${OUT:?}" "${WORK:?}"
D=$(cd "$(dirname "$0")" && pwd)
block=$1 dir=$2
shift 2
[ $# -gt 0 ] || { echo "No regions" >&2; exit 2; }
pass=${OSM_SPLIT_PASS:-3}
[[ "$pass" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid OSM_SPLIT_PASS: $pass" >&2; exit 2; }
mkdir -p "$WORK/split" "$OUT" "$dir"
keys=("$@")
for key in "${keys[@]}"; do
  "$D/region-poly.sh" "$key" "$WORK/split/${key//\//_}.poly"
done
for ((i = 0; i < ${#keys[@]}; i += pass)); do
  group=("${keys[@]:i:pass}")
  python3 - "$WORK/split" "${group[@]}" > "$WORK/split/extracts.json" <<'PY'
import json, sys
work, keys = sys.argv[1], sys.argv[2:]
print(json.dumps({'directory': work, 'extracts': [
    {'output': k.replace('/', '_') + '.osm.pbf', 'polygon': {'file_name': '%s/%s.poly' % (work, k.replace('/', '_')), 'file_type': 'poly'}}
    for k in keys]}, indent=1))
PY
  echo "Cutting ${group[*]}"
  "$D/measure.sh" "osm-split-$((i / pass + 1))" osmium extract --overwrite -s smart -S types=multipolygon,boundary -c "$WORK/split/extracts.json" "$block"
  for key in "${group[@]}"; do
    base=${key//\//_}
    mkdir -p "$dir/$base"
    mv "$WORK/split/$base.osm.pbf" "$dir/$base/region.osm.pbf"
  done
done
ls -l "$dir"/*/region.osm.pbf
