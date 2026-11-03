#!/bin/sh

export JVM_ARGS=${JVM_ARGS:--Xmx16G}
fuseki-server --conf=kg/config/kg-config.ttl "$@"
