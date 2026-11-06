# CLAUDE.md

Guidance for Claude Code (and other agents) working in this repository.

## What this project is

SPARQL-only tooling to discover SHACL shapes in an existing knowledge graph.
Resources get structural "signatures", refined level by level (level n covers
the n-hop neighbourhood); the final level is turned into SHACL shapes. Read
`README.md` for the aim, `docs/signatures.md` for the exact signature format
and data model and `docs/shapes.md` for the shapes before changing the
updates.

## Layout

- `updates/signatures-base.ru`: level-0 signatures (drops the signature graph first).
- `updates/signatures-rec.ru`: next level after the highest existing one.
- `updates/signatures-finalize.ru`: on convergence, marks the highest level
  `sig:final true` and links its object property signatures to the final
  target signatures (`sig:refersToTargetNodeSignature`).
- `updates/shapes.ru`: SHACL shapes from the final level, into the graph
  `<shapes/graph>` (dropped by `signatures-base.ru` too).
- `queries/*.rq`: inspection and sanity-check queries.
- `scripts/*.sh`: Jena CLI wrappers; run them from the repo root.
- `tests/`: end-to-end tests (`test_signatures.py`), the synthetic graph
  generator (`generate.py`), test-only queries, fixtures and snapshots.
- `kg/config/kg-config.ttl`: TDB2 + Fuseki config (`unionDefaultGraph true`).
- `input/` and `kg/tdb2/`: git-ignored data (the user's KG and its TDB2 store).
  Never commit data from them.

## Running things

There is no build. The user runs the pipeline on a large KG with the scripts
(`load.sh`, `sig-base.sh`, `sig-rec.sh` repeated or `sig-converge.sh`,
`check.sh`). That KG is not in the repo.

Run the test suite after any change to the updates, queries or scripts:

```sh
JENA_HOME=/path/to/apache-jena-5.x python3 -m unittest discover -s tests -v
```

It takes a few minutes (run it in the background). CI runs the same suite on
every push (`.github/workflows/tests.yml`, Jena 5.2.0,
`REQUIRE_JENA=1` so a missing Jena fails instead of skipping); keep the
Jena version and checksum there in sync if you change it. Get Jena from
archive.apache.org/dist/jena/binaries/ if it isn't installed. If a change to
the id format is intended, regenerate the snapshot with `UPDATE_SNAPSHOTS=1`
and check the diff of `tests/expected/`. New test graphs belong in
`tests/generate.py`. For structured ones, also generate the SHACL shapes the
data follows and the expected results, as `layered` does.

To experiment by hand, use a small graph in a scratch directory, not the repo:

```sh
J=/path/to/apache-jena-5.x/bin   # download from archive.apache.org/dist/jena/binaries/ if needed
O="--loc=tdb2 --set=tdb:unionDefaultGraph=true"
$J/tdb2.tdbloader --loc=tdb2 sample.trig
$J/tdb2.tdbupdate $O --update <repo>/updates/signatures-base.ru
$J/tdb2.tdbupdate $O --update <repo>/updates/signatures-rec.ru   # repeat per level
$J/tdb2.tdbquery  $O --query  <repo>/queries/signatures.rq
```

`scripts/sig-converge.sh` can run the same way from the repo root, with the
Jena `bin` directory on the `PATH` and
`TDB_ARGS="--loc=<scratch>/tdb2 --set=tdb:unionDefaultGraph=true"`.

Use `--loc` + `--set` rather than `--tdb=kg/config/kg-config.ttl`: Jena 5.2's
`tdb2.*` tools reject that config file's dataset type.

Sample data must go in a named graph, since the dataset relies on the union
default graph: use quads (N-Quads or TriG), or load triples with
`tdb2.tdbloader --graph=<iri>`.

## Invariants to preserve

- Every signed resource has exactly one signature per level. Check with a
  `GROUP BY ?level ?i HAVING (COUNT(*) > 1)` query over the signature graph
  after running at least two levels.
- Node signature IRIs include the level: `sig/signatures/nodes/{level}/{ENCODE_FOR_URI(id)}`
  (object property signatures too).
  The same id string can legitimately appear at several levels (a resource with
  no object links keeps the same id at every level from 1 on), so dropping the
  level from the IRI reintroduces duplicate signatures.
- Every id is a SHA-1 hash, and `signatures-rec.ru` embeds the targets'
  previous-level ids (hashes). Embedding unhashed ids makes ids grow
  exponentially on cyclic data.
- Type, datatype path/property, base node and object path signatures are
  level-independent (no `sig:level`, no level in the IRI). Each level from 1
  on stores object property signatures with the same `sig:level` as its node
  signatures. Anything that counts or compares signatures per level must
  restrict to `a sig:NodeSignature`.
- Each node signature from level 1 on has `sig:hasParentSignature` to the
  previous-level signature of the same resources; the converged level is kept
  as the final one (not deleted), so the finalize step can resolve
  `sig:containsTargetNodeSignature` to final signatures through it.
- Value counts are not part of node signature ids: signatures that differ
  only by counts are merged, and their datatype/object property signatures
  store the interval of the members' counts (`sig:hasMinValueCount`, and
  `sig:hasMaxValueCount` unless a count is above 5). Keep the refinement
  argument in `docs/signatures.md` valid if you change this.
- Convergence is detected by signature counts per level, not by ids
  (`queries/convergence.rq`): on cyclic data ids keep changing even when the
  partition is stable.
- Ids must be deterministic for a given structure: keep the `ORDER BY` before
  every `GROUP_CONCAT`.
- Shape IRIs are built from signature ids, and lists use IRIs, not blank
  nodes, so that shared shapes are written once and the output is
  deterministic (snapshot in `tests/expected/people-places-shapes.nt`).
- The signature graph is part of the default graph (union). Any new pattern
  over the default graph also sees `sig:` triples; filter them out where they
  would distort results.

## Conventions

- SPARQL files use tabs for indentation and the shared prefix block
  (`BASE <https://w3id.org/hacid/data/>`, `sig:`, `sigdata:`, `siglevels:`,
  `sigs:`). Keep it consistent across files.
- Commented-out `FILTER NOT EXISTS` blocks (subclass/subproperty pruning) are
  intentional ideas kept for later; don't delete them without asking.
- When behaviour or the signature format changes, update
  `docs/signatures.md` (or `docs/shapes.md` for the shapes) in the same
  commit.
