#!/bin/bash

export JVM_ARGS=-Xmx16G
tdb2.tdbquery --tdb=kg/config/kg-config.ttl --query queries/signatures.rq
tdb2.tdbquery --tdb=kg/config/kg-config.ttl --query queries/convergence.rq
tdb2.tdbquery --tdb=kg/config/kg-config.ttl --query queries/duplicate-shapes.rq
#tdb2.tdbquery --tdb=kg/config/kg-config.ttl --query queries/without-signature.rq