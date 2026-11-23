#!/usr/bin/env bash
# Downloads the GeoKuk themes GeoKuk-tema.zip (for the maps of GeoKuk, rules fmrel*) and GeoKuk-tema-PAWS.zip (for the maps of
# osm.paws.cz) from a release of geokuk-community/geokuk, checks each against its .sha256 and its build provenance attestation
# (gh attestation verify) and keeps both with their .sha256 in DIR, for the release; writes DIR/themes.meta.json for scripts/theme-catalog.py.
# Env: GH_TOKEN, DIR; optional GEOKUK (release tag, also a prerelease such as v6.5.0-beta.36; default the latest release, which is never
# a prerelease), GEOKUK_REPO.
set -euo pipefail
: "${GH_TOKEN:?}" "${DIR:?}"
REPO=${GEOKUK_REPO:-geokuk-community/geokuk}
THEMES=(GeoKuk-tema.zip GeoKuk-tema-PAWS.zip)
mkdir -p "$DIR"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [ -n "${GEOKUK:-}" ]; then
  [[ "$GEOKUK" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid GEOKUK tag: $GEOKUK" >&2; exit 2; }
  gh api "repos/$REPO/releases/tags/$GEOKUK" > "$work/release.json"
else
  gh api "repos/$REPO/releases/latest" > "$work/release.json"
fi
read -r tag published url < <(python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r["tag_name"], r["published_at"][:10], r["html_url"])' "$work/release.json")
echo "GeoKuk release $tag ($published)"
for name in "${THEMES[@]}"; do
  rm -f "$DIR/$name" "$DIR/$name.sha256" "$work/$name.sha256"
  gh release download "$tag" --repo "$REPO" --pattern "$name" --pattern "$name.sha256" --dir "$work" --clobber \
    || { echo "Release $tag of $REPO has no $name with $name.sha256" >&2; exit 1; }
  [ -s "$work/$name" ] && [ -s "$work/$name.sha256" ] || { echo "$name or $name.sha256 is missing in release $tag" >&2; exit 1; }
  expected=$(awk 'NR == 1 {print tolower($1)}' "$work/$name.sha256")
  actual=$(sha256sum "$work/$name" | awk '{print $1}')
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || { echo "$name.sha256 holds no SHA-256" >&2; exit 1; }
  [ "$expected" = "$actual" ] || { echo "$name has SHA-256 $actual, $name.sha256 says $expected" >&2; exit 1; }
  # A missing attestation is an error: the release job of GeoKuk attests every release file (actions/attest-build-provenance).
  gh attestation verify "$work/$name" --repo "$REPO" > /dev/null \
    || { echo "$name has no valid build provenance attestation of $REPO" >&2; exit 1; }
  mv "$work/$name" "$DIR/$name"
  mv "$work/$name.sha256" "$DIR/$name.sha256"
  echo "$name: $(stat -c %s "$DIR/$name") bytes, sha256 $actual, attestation of $REPO verified"
done
python3 -I - "$DIR/themes.meta.json" "$tag" "$published" "$url" <<'PY'
import json, sys
out, tag, published, url = sys.argv[1:5]
json.dump({'geokuk': tag, 'geokukVersion': tag[1:] if tag[:1] == 'v' else tag, 'date': published, 'source': url},
          open(out, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
PY
