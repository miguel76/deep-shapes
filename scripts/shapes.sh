#!/bin/bash
#
# Generate SHACL shapes from the final signature level (see docs/shapes.md)
# and write them as Turtle to the given file (default: stdout). Run from the
# repo root, after scripts/sig-converge.sh has converged.
#
# Usage: scripts/shapes.sh [output.ttl]
#
# Environment: JVM_ARGS and TDB_ARGS, as for scripts/sig-converge.sh.

set -euo pipefail

export JVM_ARGS=${JVM_ARGS:--Xmx16G}
TDB_ARGS=${TDB_ARGS:---tdb=kg/config/kg-config.ttl}

# shellcheck disable=SC2086
tdb2.tdbupdate $TDB_ARGS --update updates/shapes.ru
# shellcheck disable=SC2086
tdb2.tdbquery $TDB_ARGS --results=ttl --query queries/shapes.rq > "${1:-/dev/stdout}"
