#!/usr/bin/env bash
# Downloads the first MiB of a .map release asset (its header with the tag lists) into DIR/<release>_<name>.
# Usage: map-header.sh DIR release asset_id name   Env: GH_TOKEN, GITHUB_REPOSITORY.
set -euo pipefail
: "${GH_TOKEN:?}" "${GITHUB_REPOSITORY:?}"
dir=$1 release=$2 id=$3 name=$4
[[ "$id" =~ ^[0-9]+$ && "$release" =~ ^layers-[0-9a-z-]+$ && "$name" =~ ^[A-Za-z0-9._-]+\.map$ ]] || { echo "Invalid asset: $*" >&2; exit 2; }
# The API redirects to the storage host; curl does not send the token there. --max-filesize fails when the range is not honoured.
curl -fsSL --retry 5 --retry-all-errors -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/octet-stream" \
  -r 0-1048575 --max-filesize 1048576 -o "$dir/${release}_$name" "https://api.github.com/repos/$GITHUB_REPOSITORY/releases/assets/$id"
