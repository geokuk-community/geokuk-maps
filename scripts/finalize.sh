#!/usr/bin/env bash
# Verifies the draft release (every file in layers.json is an uploaded asset of the same size) and publishes it as the latest release.
# Published releases are immutable, so nothing is published when a check fails.
# The GeoKuk themes of the release (both ZIPs with their .sha256 as assets, GeoKuk-tema.zip also in layers.json) must match the layers:
# their .sha256 and attestation, and every tag of the layers that GeoKuk-tema.zip draws must be
# in the headers of the tourist and contours maps (scripts/theme-check.py over the first MiB of each map).
# Env: GH_TOKEN, GITHUB_REPOSITORY, TAG (optional; the only draft release layers-* is used by default), DRY_RUN=1 (check only),
# optional GEOKUK_REPO (repository that attests the themes, default geokuk-community/geokuk).
set -euo pipefail
: "${GH_TOKEN:?}" "${GITHUB_REPOSITORY:?}"
R=$(cd "$(dirname "$0")/.." && pwd)
api() { gh api "$@"; }
work=$(mktemp -d)
api "repos/$GITHUB_REPOSITORY/releases?per_page=100" --paginate > "$work/releases.json"
read -r ID TAG < <(python3 "$R/scripts/finalize-check.py" release "$work/releases.json" "${TAG:-}")
echo "Draft release $TAG ($ID)"
api "repos/$GITHUB_REPOSITORY/releases/$ID/assets" --paginate > "$work/assets.json"
aid=$(python3 "$R/scripts/finalize-check.py" asset-id "$work/assets.json" layers.json)
api -H "Accept: application/octet-stream" "repos/$GITHUB_REPOSITORY/releases/assets/$aid" > "$work/layers.json"
python3 "$R/scripts/finalize-check.py" verify "$work/layers.json" "$work/assets.json" "$TAG"
# Every layer of the previous release must still be there (a layer omitted at 2 GiB or a failed region would vanish from GeoKuk).
read -r pid ptag < <(python3 "$R/scripts/finalize-check.py" previous "$work/releases.json" "$TAG") || true
if [ -n "${pid:-}" ]; then
  api "repos/$GITHUB_REPOSITORY/releases/$pid/assets" --paginate > "$work/previous-assets.json"
  paid=$(python3 "$R/scripts/finalize-check.py" asset-id "$work/previous-assets.json" layers.json)
  api -H "Accept: application/octet-stream" "repos/$GITHUB_REPOSITORY/releases/assets/$paid" > "$work/previous-layers.json"
  echo "Previous release $ptag"
  python3 "$R/scripts/finalize-check.py" compare "$work/layers.json" "$work/previous-layers.json"
fi
# Dem and contours kept from older releases (mapping/dem-manifest.json): those releases must still hold the files.
mkdir -p "$work/other"
cp "$work/releases.json" "$work/other/releases.json"
others=$(python3 "$R/scripts/finalize-check.py" other-tags "$work/layers.json" "$TAG")
for other in $others; do
  oid=$(python3 -c 'import json,sys; print(next(r["id"] for r in json.load(open(sys.argv[1])) if r["tag_name"] == sys.argv[2]))' "$work/releases.json" "$other") \
    || { echo "Release $other, which layers.json points to, does not exist" >&2; exit 1; }
  api "repos/$GITHUB_REPOSITORY/releases/$oid/assets" --paginate > "$work/other/$other.assets.json"
done
python3 "$R/scripts/finalize-check.py" verify-other "$work/layers.json" "$TAG" "$work/other"
python3 "$R/scripts/dem-source.py" check "$work/layers.json" "$TAG"
mkdir -p "$work/themes" "$work/headers"
for name in GeoKuk-tema.zip GeoKuk-tema-PAWS.zip; do
  tid=$(python3 "$R/scripts/finalize-check.py" asset-id "$work/assets.json" "$name")
  api -H "Accept: application/octet-stream" "repos/$GITHUB_REPOSITORY/releases/assets/$tid" > "$work/themes/$name"
  sid=$(python3 "$R/scripts/finalize-check.py" asset-id "$work/assets.json" "$name.sha256")
  api -H "Accept: application/octet-stream" "repos/$GITHUB_REPOSITORY/releases/assets/$sid" > "$work/themes/$name.sha256"
  [ "$(awk 'NR == 1 {print tolower($1)}' "$work/themes/$name.sha256")" = "$(sha256sum "$work/themes/$name" | awk '{print $1}')" ] \
    || { echo "$name does not match $name.sha256 of the release" >&2; exit 1; }
  gh attestation verify "$work/themes/$name" --repo "${GEOKUK_REPO:-geokuk-community/geokuk}" > /dev/null \
    || { echo "$name has no valid build provenance attestation" >&2; exit 1; }
done
cp "$work/assets.json" "$work/other/$TAG.assets.json"
python3 "$R/scripts/finalize-check.py" map-assets "$work/layers.json" "$TAG" "$work/other" > "$work/maps.txt"
echo "Reading the headers of $(wc -l < "$work/maps.txt") maps"
export GH_TOKEN GITHUB_REPOSITORY
xargs -r -P 8 -L 1 "$R/scripts/map-header.sh" "$work/headers" < "$work/maps.txt"
for f in "$work"/headers/*.map; do python3 "$R/scripts/map-tags.py" "$f"; done | sort -u > "$work/tags.txt"
echo "Tags of the layers: $(wc -l < "$work/tags.txt")"
python3 "$R/scripts/theme-check.py" geokuk "$work/themes/GeoKuk-tema.zip" --tags "$work/tags.txt" --notice
python3 "$R/scripts/theme-check.py" paws "$work/themes/GeoKuk-tema-PAWS.zip"
if [ "${DRY_RUN:-}" = 1 ]; then
  echo "Dry run: all checks passed, the release was not published"
  exit 0
fi
api -X PATCH "repos/$GITHUB_REPOSITORY/releases/$ID" -F draft=false -F make_latest=true > /dev/null
echo "Release $TAG published"
