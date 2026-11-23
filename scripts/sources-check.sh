#!/usr/bin/env bash
# Checks that the sources of the map layers are available, with light requests only (HEAD, the first bytes by Range, small indexes):
# the mapsforge base maps and their mirror (size and date of the mirror against the original), the OSM planet on AWS, Geofabrik,
# Copernicus GLO-30, ČÚZK DMR 4G, the tools the workflows download, and layers.json of the latest release.
# Each check is tried 3 times (RETRY_DELAY seconds apart, default 30); only the third failure counts as an outage.
# Geofabrik is only a warning (state warn): the layers use the planet on AWS, Geofabrik only with osm_source=geofabrik and as the
# fallback of the pull request checks when tests/osm has no sample; it was unreachable from the GitHub runners in November 2026.
# Writes OUT/results.tsv (source, URL, state, time in ms, detail; state ok|warn|fail) and OUT/summary.md (table in Czech).
# Env: OUT; optional TEST_URL (an extra URL to check, for testing the outage handling), RETRY_DELAY, GITHUB_REPOSITORY.
set -uo pipefail
: "${OUT:?}"
mkdir -p "$OUT"
D=$(cd "$(dirname "$0")" && pwd)
REPO=${GITHUB_REPOSITORY:-geokuk-community/geokuk-maps}
DELAY=${RETRY_DELAY:-30}
MAPSFORGE=https://download.mapsforge.org
MIRROR=https://ftp-stud.hs-esslingen.de/pub/Mirrors/download.mapsforge.org
PLANET=https://osm-planet-eu-central-1.s3.amazonaws.com
COPERNICUS=https://copernicus-dem-30m.s3.amazonaws.com
UA="geokuk-maps-sources-check (+https://github.com/$REPO)"
results="$OUT/results.tsv"
: > "$results"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# probe URL: HEAD (following redirects); servers that refuse HEAD get a GET of the first KiB. Sets code, ms, size, modified.
probe() {
  local url=$1 out
  out=$(curl -sS -I -L --max-time 60 --connect-timeout 20 -A "$UA" -o "$tmp/headers" -w '%{http_code} %{time_total}' "$url" 2>"$tmp/err") || out="000 0"
  code=${out%% *}
  if [ "$code" = 405 ] || [ "$code" = 403 ] || [ "$code" = 501 ]; then
    out=$(curl -sS -L --max-time 60 --connect-timeout 20 -A "$UA" -r 0-1023 -D "$tmp/headers" -o /dev/null -w '%{http_code} %{time_total}' "$url" 2>"$tmp/err") || out="000 0"
    code=${out%% *}
  fi
  ms=$(awk -v t="${out#* }" 'BEGIN {printf "%d", t * 1000}')
  # The headers of the last response (after redirects).
  size=$(awk 'BEGIN {IGNORECASE = 1} /^HTTP\//{s = ""} /^content-length:/{s = $2} END {gsub(/\r/, "", s); print s}' "$tmp/headers" 2>/dev/null)
  modified=$(awk 'BEGIN {IGNORECASE = 1} /^HTTP\//{m = ""} /^last-modified:/{sub(/^[^:]*: */, ""); m = $0} END {gsub(/\r/, "", m); print m}' "$tmp/headers" 2>/dev/null)
}

record() { # source url state ms detail
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$results"
  echo "$3 $1 $2 ($4 ms) $5"
}

# check SOURCE URL [function that checks the response further and sets detail; returns non-zero on a failure]
check() {
  local source=$1 url=$2 test=${3:-} try
  for try in 1 2 3; do
    detail=
    probe "$url"
    if [[ "$code" =~ ^2 ]] && { [ -z "$test" ] || "$test" "$url"; }; then
      record "$source" "$url" ok "$ms" "HTTP $code${detail:+, $detail}"
      return 0
    fi
    [ -n "$detail" ] || detail="HTTP $code $(head -c 200 "$tmp/err" | tr '\n\t' '  ')"
    [ "$try" -lt 3 ] && sleep $((try * DELAY))
  done
  record "$source" "$url" "${FAIL_STATE:-fail}" "$ms" "$detail"
  return 1
}

# get SOURCE URL RANGE FILE: a small GET (whole file or Range), 3 tries; sets code, ms.
get() {
  local source=$1 url=$2 range=$3 file=$4 try out
  for try in 1 2 3; do
    out=$(curl -sS -L --max-time 120 --connect-timeout 20 -A "$UA" ${range:+-r "$range"} -o "$file" -w '%{http_code} %{time_total}' "$url" 2>"$tmp/err") || out="000 0"
    code=${out%% *}
    ms=$(awk -v t="${out#* }" 'BEGIN {printf "%d", t * 1000}')
    if [[ "$code" =~ ^2 ]] && [ -s "$file" ]; then return 0; fi
    [ "$try" -lt 3 ] && sleep $((try * DELAY))
  done
  record "$source" "$url" fail "$ms" "HTTP $code $(head -c 200 "$tmp/err" | tr '\n\t' '  ')"
  return 1
}

# 1. Base maps of mapsforge and the mirror the scripts read (maps/v5 for the headers, maps/poly for the outlines).
map=maps/v5/europe/monaco.map
poly=maps/poly/europe/monaco.poly
if check "mapsforge: mapa" "$MAPSFORGE/$map"; then orig_size=$size orig_modified=$modified; else orig_size='' orig_modified=''; fi
check "mapsforge: obrys .poly" "$MAPSFORGE/$poly"
same_as_original() {
  [ -z "$orig_size" ] && return 0
  if [ "$size" != "$orig_size" ] || [ "$modified" != "$orig_modified" ]; then
    detail="zrcadlo $size B, $modified; originál $orig_size B, $orig_modified"
    return 1
  fi
  detail="stejná velikost a datum jako originál ($size B, $modified)"
}
check "zrcadlo Esslingen: mapa" "$MIRROR/$map" same_as_original
check "zrcadlo Esslingen: obrys .poly" "$MIRROR/$poly"

# 2. OSM planet on AWS Open Data: the listing of the year (scripts/planet-latest.py), then the newest planet and its .md5.
for try in 1 2 3; do
  start=$(date +%s%N)
  if planet=$(python3 "$D/planet-latest.py" 2>"$tmp/err"); then break; fi
  planet=
  [ "$try" -lt 3 ] && sleep $((try * DELAY))
done
ms=$(( ($(date +%s%N) - start) / 1000000 ))
if [ -n "$planet" ]; then
  record "OSM planeta: výpis" "$PLANET/?list-type=2&prefix=planet/pbf/" ok "$ms" "nejnovější $planet"
  key="planet/pbf/20${planet:7:2}/$planet.osm.pbf"
  check "OSM planeta: .md5" "$PLANET/$key.md5"
  check "OSM planeta: soubor (HEAD)" "$PLANET/$key"
else
  record "OSM planeta: výpis" "$PLANET/?list-type=2&prefix=planet/pbf/" fail "$ms" "$(head -c 200 "$tmp/err" | tr '\n\t' '  ')"
fi

# 3. Geofabrik (osm_source=geofabrik): the index and one small extract.
FAIL_STATE=warn check "Geofabrik: index" "https://download.geofabrik.de/index-v1-nogeom.json"
FAIL_STATE=warn check "Geofabrik: extrakt" "https://download.geofabrik.de/europe/monaco-latest.osm.pbf"

# 4. Copernicus GLO-30: the tile list and one tile.
check "Copernicus: tileList.txt" "$COPERNICUS/tileList.txt"
check "Copernicus: dlaždice" "$COPERNICUS/Copernicus_DSM_COG_10_N50_00_E014_00_DEM/Copernicus_DSM_COG_10_N50_00_E014_00_DEM.tif"

# 5. ČÚZK DMR 4G: the first 64 KiB of the ATOM feed with the code of a sheet, then that sheet (scripts/cuzk2hgt.py).
feed=https://atom.cuzk.gov.cz/DMR4G-SJTSK/DMR4G-SJTSK.xml
if get "ČÚZK: ATOM feed" "$feed" 0-65535 "$tmp/feed.xml"; then
  sheet=$(grep -oE 'CUZK_DMR4G-SJTSK_[A-Z0-9]+\.xml' "$tmp/feed.xml" | head -1 | sed -E 's/CUZK_DMR4G-SJTSK_([A-Z0-9]+)\.xml/\1/')
  if [ -n "$sheet" ]; then
    record "ČÚZK: ATOM feed" "$feed" ok "$ms" "HTTP $code, list $sheet"
    check "ČÚZK: list DMR 4G" "https://openzu.cuzk.gov.cz/opendata/DMR4G/epsg-5514/$sheet.zip"
  else
    record "ČÚZK: ATOM feed" "$feed" fail "$ms" "ve feedu není žádný list"
  fi
fi

# 6. Tools that the workflows download (scripts/install-tools.sh, scripts/writer/pom.xml, scripts/requirements.txt).
check "Osmosis (GitHub)" "https://github.com/openstreetmap/osmosis/releases/download/0.49.2/osmosis-0.49.2.tar"
check "Maven Central: mapsforge-map-writer" "https://repo1.maven.org/maven2/org/mapsforge/mapsforge-map-writer/0.25.0/mapsforge-map-writer-0.25.0.pom"
check "PyPI: pyhgtmap" "https://pypi.org/pypi/pyhgtmap/4.1/json"

# 7. Our own output: layers.json of the latest release is valid JSON with version 1.
catalog="https://github.com/$REPO/releases/latest/download/layers.json"
if get "layers.json (latest)" "$catalog" "" "$tmp/layers.json"; then
  if info=$(python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1])); assert c.get("version") == 1, "version %r" % c.get("version"); print("version 1, %d vrstev" % len(c["layers"]))' "$tmp/layers.json" 2>&1); then
    record "layers.json (latest)" "$catalog" ok "$ms" "$info"
  else
    record "layers.json (latest)" "$catalog" fail "$ms" "neplatný katalog: $(echo "$info" | tail -1)"
  fi
fi

# 8. Test input: an extra URL (workflow_dispatch input test_url).
if [ -n "${TEST_URL:-}" ]; then
  check "test (vstup test_url)" "$TEST_URL"
fi

failed=$(awk -F'\t' '$3 == "fail"' "$results" | wc -l)
warned=$(awk -F'\t' '$3 == "warn"' "$results" | wc -l)
total=$(wc -l < "$results")
{
  echo "### Dostupnost zdrojů map"
  echo
  echo "Dostupné: $((total - failed - warned)) z $total, nedostupné: $failed, varování: $warned (Geofabrik je jen záložní zdroj a výpadek neohlašuje)."
  echo
  echo "| Zdroj | URL | Stav | Čas | Podrobnosti |"
  echo "|---|---|---|---|---|"
  awk -F'\t' '{printf "| %s | %s | %s | %s ms | %s |\n", $1, $2, ($3 == "ok" ? "dostupný" : ($3 == "warn" ? "varování: nedostupný" : "**nedostupný**")), $4, $5}' "$results"
} > "$OUT/summary.md"
echo "$((total - failed - warned)) of $total sources available, $failed unavailable, $warned warnings"
awk -F'\t' '$3 == "warn" {printf "::warning::%s unavailable: %s\n", $1, $5}' "$results"
