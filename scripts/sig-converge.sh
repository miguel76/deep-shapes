#!/bin/bash
#
# Compute signature levels until the partition converges, i.e. until a level
# adds no new signatures (see queries/convergence.rq). Run from the repo root.
#
# Usage: scripts/sig-converge.sh [--base] [--max-levels N]
#
#   --base          recompute level 0 first (drops all existing signatures)
#   --max-levels N  compute at most N new levels in this run, even if the
#                   partition hasn't converged yet (default: no limit;
#                   convergence is always reached eventually, but each level
#                   costs a full pass over the KG)
#
# Exit status: 0 when converged, 2 when --max-levels was reached first,
# 1 on errors.
#
# Environment:
#   JVM_ARGS  JVM options for the Jena tools (default: -Xmx16G)
#   TDB_ARGS  dataset options for the Jena tools
#             (default: --tdb=kg/config/kg-config.ttl)

set -euo pipefail

export JVM_ARGS=${JVM_ARGS:--Xmx16G}
TDB_ARGS=${TDB_ARGS:---tdb=kg/config/kg-config.ttl}

run_base=false
max_levels=
while [ $# -gt 0 ]; do
	case "$1" in
		--base) run_base=true; shift ;;
		--max-levels)
			[ $# -ge 2 ] || { echo "--max-levels needs a value" >&2; exit 1; }
			max_levels=$2; shift 2 ;;
		-h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "Unknown option: $1" >&2; exit 1 ;;
	esac
done
if [ -n "$max_levels" ] && ! [[ "$max_levels" =~ ^[0-9]+$ ]]; then
	echo "--max-levels must be a non-negative integer" >&2
	exit 1
fi

# Prints "level signatures new_signatures converged" for the highest level,
# or nothing if there are no signatures yet.
last_level_status() {
	# shellcheck disable=SC2086
	tdb2.tdbquery $TDB_ARGS --results=csv --query queries/convergence.rq \
		| tr -d '\r' \
		| tail -n +2 \
		| tail -n 1 \
		| awk -F, '{ print $1, $2, ($4 == "" ? "-" : $4), ($5 == "" ? "false" : $5) }'
}

if $run_base; then
	echo "Computing level 0..."
	# shellcheck disable=SC2086
	tdb2.tdbupdate $TDB_ARGS --update updates/signatures-base.ru
fi

computed=0
while true; do
	status=$(last_level_status)
	if [ -z "$status" ]; then
		echo "No signatures found: run with --base (or scripts/sig-base.sh) first." >&2
		exit 1
	fi
	read -r level signatures new_signatures converged <<< "$status"
	echo "Level $level: $signatures signatures ($new_signatures new)"

	if [ "$converged" = "true" ]; then
		echo "Converged: the partition is final from level $((level - 1)) on" \
			"(level $level adds no signatures)."
		exit 0
	fi
	if [ -n "$max_levels" ] && [ "$computed" -ge "$max_levels" ]; then
		echo "Stopped after $computed new level(s) without converging." >&2
		exit 2
	fi

	echo "Computing level $((level + 1))..."
	# shellcheck disable=SC2086
	tdb2.tdbupdate $TDB_ARGS --update updates/signatures-rec.ru
	computed=$((computed + 1))
done
