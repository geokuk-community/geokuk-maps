#!/usr/bin/env bash
# Osmosis 0.49.2 with the mapsforge-map-writer 0.25.0 plugin into $TOOLS (default ./tools); adds bin to $GITHUB_PATH.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
T=${TOOLS:-$PWD/tools}
mkdir -p "$T"
plugin="$HOME/.openstreetmap/osmosis/plugins/mapsforge-map-writer-0.25.0-jar-with-dependencies.jar"
# The workflow restores $T/osmosis and the plugin from actions/cache (key: hash of this script and of writer/pom.xml).
cached=$(find "$T/osmosis" -path '*/bin/osmosis' 2>/dev/null | head -1 || true)
if [ -n "$cached" ] && [ -x "$cached" ] && [ -s "$plugin" ]; then
  echo "Osmosis and the map writer plugin restored from the cache"
else
  url=https://github.com/openstreetmap/osmosis/releases/download/0.49.2/osmosis-0.49.2.tar
  curl -fL --retry 5 --retry-delay 10 -o "$T/osmosis.tar" "$url"
  expected=${OSMOSIS_SHA256:-2a23a7bf7499a0727ae6987cf66fcafc03b37379dc02177c730f352bd67a0b97}
  sha=$(sha256sum "$T/osmosis.tar" | cut -d' ' -f1)
  echo "osmosis.tar sha256: $sha"
  [ "$sha" = "$expected" ] || { echo "Osmosis sha256 mismatch" >&2; exit 1; }
  mkdir -p "$T/osmosis"
  tar -xf "$T/osmosis.tar" -C "$T/osmosis"
  mkdir -p "$T/deps" "$T/fat" "$HOME/.openstreetmap/osmosis/plugins"
  mvn -q -B -f "$D/writer/pom.xml" dependency:copy-dependencies -DoutputDirectory="$T/deps" -DincludeScope=runtime
  # The Osmosis (JPF) plugin sees only its own jar, so the dependencies are merged into one (the writer last, for plugin.xml).
  for j in "$T"/deps/*.jar; do case "$j" in *mapsforge-map-writer-*) ;; *) unzip -qo "$j" -x 'META-INF/*' -d "$T/fat" || [ $? -eq 11 ];; esac; done
  rm -f "$T/fat/module-info.class"
  unzip -qo "$T"/deps/mapsforge-map-writer-*.jar -x 'META-INF/MANIFEST.MF' -d "$T/fat"
  (cd "$T/fat" && jar cf "$plugin" .)
  # Only the extracted Osmosis and the plugin are kept (and cached).
  rm -rf "$T/osmosis.tar" "$T/deps" "$T/fat"
fi
O=$(dirname "$(dirname "$(find "$T/osmosis" -path '*/bin/osmosis' | head -1)")")
"$O/bin/osmosis" -v | head -3 || true
echo "$O/bin" >> "${GITHUB_PATH:-/dev/null}"
echo "$O"
