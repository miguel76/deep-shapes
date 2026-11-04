#!/bin/bash
#
# Compute signature levels until the partition converges, i.e. until a level
# adds no new signatures (see queries/convergence.rq). Run from the repo root.
#
# Usage: scripts/sig-converge.sh [--restart] [--max-levels N]
#
# Starts from level 0 if there are no signatures yet; otherwise continues from
# the highest existing level. On convergence, the level that confirmed it is
# removed (it only repeats the previous partition) and the level below is
# marked final, so later runs do nothing.
#
#   --restart       discard all existing signatures and start again from
#                   level 0
#   --max-levels N  compute at most N new levels in this run (not counting
#                   level 0), even if the partition hasn't converged yet
#                   (default: no limit; convergence is always reached
#                   eventually, but each level costs a full pass over the KG)
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

restart=false
max_levels=
while [ $# -gt 0 ]; do
	case "$1" in
		--restart) restart=true; shift ;;
		--max-levels)
			[ $# -ge 2 ] || { echo "--max-levels needs a value" >&2; exit 1; }
			max_levels=$2; shift 2 ;;
		-h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "Unknown option: $1" >&2; exit 1 ;;
	esac
done
if [ -n "$max_levels" ] && ! [[ "$max_levels" =~ ^[0-9]+$ ]]; then
	echo "--max-levels must be a non-negative integer" >&2
	exit 1
fi

update() {
	# shellcheck disable=SC2086
	tdb2.tdbupdate $TDB_ARGS --update "$1"
}

# Prints "level signatures new_signatures converged final" for the highest
# level, or nothing if there are no signatures yet.
last_level_status() {
	# shellcheck disable=SC2086
	tdb2.tdbquery $TDB_ARGS --results=csv --query queries/convergence.rq \
		| tr -d '\r' \
		| tail -n +2 \
		| tail -n 1 \
		| awk -F, '{ print $1, $2, ($4 == "" ? "-" : $4), ($5 == "" ? "false" : $5), $6 }'
}

if $restart || [ -z "$(last_level_status)" ]; then
	echo "Computing level 0..."
	update updates/signatures-base.ru
fi

computed=0
while true; do
	status=$(last_level_status)
	if [ -z "$status" ]; then
		echo "No signatures after computing level 0: is the dataset empty?" >&2
		exit 1
	fi
	read -r level signatures new_signatures converged final <<< "$status"

	if [ "$final" = "true" ]; then
		echo "Already converged: level $level ($signatures signatures) is final."
		exit 0
	fi
	echo "Level $level: $signatures signatures ($new_signatures new)"

	if [ "$converged" = "true" ]; then
		echo "Level $level adds no signatures: removing it and marking level" \
			"$((level - 1)) as final..."
		update updates/signatures-finalize.ru
		echo "Converged: level $((level - 1)) is final."
		exit 0
	fi
	if [ -n "$max_levels" ] && [ "$computed" -ge "$max_levels" ]; then
		echo "Stopped after $computed new level(s) without converging." >&2
		exit 2
	fi

	echo "Computing level $((level + 1))..."
	update updates/signatures-rec.ru
	computed=$((computed + 1))
done
