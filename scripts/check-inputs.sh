#!/usr/bin/env bash
# Validates REGION, BBOX, BASE and PARALLEL before they are used in URLs and commands.
[[ "${REGION:-x}" =~ ^[a-z0-9-]+(/[a-z0-9-]+)*$ ]] || { echo "Invalid REGION: $REGION" >&2; exit 2; }
num='-?[0-9]+(\.[0-9]+)?'
[[ "${BBOX:?}" =~ ^$num,$num,$num,$num$ ]] || { echo "Invalid BBOX: $BBOX" >&2; exit 2; }
IFS=, read -r south west north east <<< "$BBOX"
awk -v a="$south" -v b="$north" -v c="$west" -v d="$east" 'BEGIN{exit !(a<b && c<d && a>=-90 && b<=90 && c>=-180 && d<=180)}' \
  || { echo "BBOX out of range: $BBOX" >&2; exit 2; }
[[ "${BASE:?}" =~ ^[a-z0-9_-]+$ ]] || { echo "Invalid BASE: $BASE" >&2; exit 2; }
[[ "${PARALLEL:-2}" =~ ^[1-9][0-9]?$ ]] || { echo "Invalid PARALLEL: $PARALLEL" >&2; exit 2; }
