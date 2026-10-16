#!/usr/bin/env bash
# measure.sh STEP command... – runs the command and appends time and peak memory to $OUT/measurements.tsv
step=$1; shift
t=$(mktemp)
/usr/bin/time -f '%e	%M' -o "$t" "$@"
rc=$?
IFS=$'\t' read -r s kb < <(tail -n 1 "$t")
printf '%s\t%s\t%s\t%s\n' "$step" "$s" "$((kb / 1024))" "$rc" >> "${OUT:?}/measurements.tsv"
rm -f "$t"
exit "$rc"
