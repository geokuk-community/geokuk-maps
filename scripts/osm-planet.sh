#!/usr/bin/env bash
# Reads the weekly OSM planet from the AWS Open Data bucket osm-planet-eu-central-1 as a stream (it does not fit on the runner disk
# next to its blocks) and writes the given blocks of mapping/osm-blocks.json in one pass (osmium extract, simple strategy; a stream
# can only be read once). The MD5 of the stream is checked against the .md5 of the planet afterwards.
# Usage: osm-planet.sh planet-YYMMDD output_dir block [block ...]. Env: OUT (measurements), optional OSMIUM_THREADS.
# Writes output_dir/BLOCK.osm.pbf and output_dir/planet.txt (planet name, OSM data timestamp).
set -euo pipefail
: "${OUT:?}"
D=$(cd "$(dirname "$0")" && pwd)
planet=$1 dir=$2
shift 2
[[ "$planet" =~ ^planet-[0-9]{6}$ ]] || { echo "Invalid planet: $planet" >&2; exit 2; }
for b in "$@"; do [[ "$b" =~ ^[a-z0-9-]+$ ]] || { echo "Invalid block: $b" >&2; exit 2; }; done
mkdir -p "$dir" "$OUT"
key="planet/pbf/20${planet:7:2}/$planet.osm.pbf"
url="https://osm-planet-eu-central-1.s3.amazonaws.com/$key"
expected=$(curl -fsSL --retry 5 --retry-delay 10 --connect-timeout 30 "$url.md5" | awk '{print $1}')
[[ "$expected" =~ ^[0-9a-f]{32}$ ]] || { echo "No MD5 for $url" >&2; exit 1; }
python3 "$D/osm-blocks.py" config "$@" > "$dir/extracts.json"
cat "$dir/extracts.json"
fifo="$dir/md5.fifo"
rm -f "$fifo"
mkfifo "$fifo"
md5sum < "$fifo" | awk '{print $1}' > "$dir/planet.md5" &
md5_pid=$!
# The AWS CLI fetches parts in parallel and retries them; curl is the fallback without it.
if command -v aws > /dev/null; then
  read_planet() { aws s3 cp --no-sign-request --region eu-central-1 --only-show-errors "s3://osm-planet-eu-central-1/$key" -; }
else
  read_planet() { curl -fsSL --connect-timeout 30 "$url"; }
fi
export -f read_planet
export key url fifo dir
"$D/measure.sh" planet-blocks bash -c 'set -o pipefail; read_planet | tee "$fifo" | osmium extract --overwrite -s simple -F pbf -c "$dir/extracts.json" -d "$dir" -'
wait "$md5_pid"
rm -f "$fifo"
actual=$(cat "$dir/planet.md5")
if [ "$actual" != "$expected" ]; then
  echo "MD5 of the planet stream $actual does not match $expected" >&2
  rm -f "$dir"/*.osm.pbf
  exit 1
fi
stamp=$(osmium fileinfo -g header.option.osmosis_replication_timestamp "$dir/$1.osm.pbf" 2>/dev/null || true)
[ -n "$stamp" ] || stamp="20${planet:7:2}-${planet:9:2}-${planet:11:2}T00:00:00Z"
printf '%s\t%s\n' "$planet" "$stamp" > "$dir/planet.txt"
ls -l "$dir"
