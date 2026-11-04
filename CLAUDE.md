# CLAUDE.md

Guidance for Claude Code (and other agents) working in this repository.

## What this project is

SPARQL-only tooling to discover SHACL shapes in an existing knowledge graph.
Resources get structural "signatures", refined level by level (level n covers
the n-hop neighbourhood). Shape generation from signatures is planned but not
implemented yet. Read `README.md` for the aim and `docs/signatures.md` for the
exact signature format and data model before changing the updates.

## Layout

- `updates/signatures-base.ru`: level-0 signatures (drops the signature graph first).
- `updates/signatures-rec.ru`: next level after the highest existing one.
- `queries/*.rq`: inspection and sanity-check queries.
- `scripts/*.sh`: Jena CLI wrappers; run them from the repo root.
- `kg/config/kg-config.ttl`: TDB2 + Fuseki config (`unionDefaultGraph true`).
- `input/` and `kg/tdb2/`: git-ignored data (the user's KG and its TDB2 store).
  Never commit data from them.

## Running things

There is no build and no test suite. The user runs the pipeline on a large KG
with the scripts (`load.sh`, `sig-base.sh`, `sig-rec.sh` repeated,
`check.sh`). That KG is not in the repo.

To check a change, use a small hand-written graph in a scratch directory, not
the repo:

```sh
J=/path/to/apache-jena-5.x/bin   # download from archive.apache.org/dist/jena/binaries/ if needed
O="--loc=tdb2 --set=tdb:unionDefaultGraph=true"
$J/tdb2.tdbloader --loc=tdb2 sample.trig
$J/tdb2.tdbupdate $O --update <repo>/updates/signatures-base.ru
$J/tdb2.tdbupdate $O --update <repo>/updates/signatures-rec.ru   # repeat per level
$J/tdb2.tdbquery  $O --query  <repo>/queries/signatures.rq
```

Use `--loc` + `--set` rather than `--tdb=kg/config/kg-config.ttl`: Jena 5.2's
`tdb2.*` tools reject that config file's dataset type.

Sample data must be quads (N-Quads or TriG) in a named graph, since the
dataset relies on the union default graph.

## Invariants to preserve

- Every signed resource has exactly one signature per level. Check with a
  `GROUP BY ?level ?i HAVING (COUNT(*) > 1)` query over the signature graph
  after running at least two levels.
- Signature IRIs include the level: `sig/signatures/{level}/{ENCODE_FOR_URI(id)}`.
  The same id string can legitimately appear at several levels (a resource with
  no object links keeps its level-0 id), so dropping the level from the IRI
  reintroduces duplicate signatures.
- Ids must be deterministic for a given structure: keep the `ORDER BY` before
  every `GROUP_CONCAT`.
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
  `docs/signatures.md` in the same commit.
