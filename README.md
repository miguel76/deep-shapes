# deep-shapes

Beyond simple class shapes: complex SHACL shapes discovery.

## Aim

Most shape-extraction tools build one SHACL shape per class: the shape for
`ex:Person` lists the properties seen on instances of `ex:Person`. Real
knowledge graphs are messier. Instances of one class can follow several
patterns, and a resource's structure often depends on what it is linked to,
not just on its own type.

**deep-shapes** aims to discover such shapes directly from an existing
knowledge graph, using only SPARQL. The idea is to give each resource a
**signature**, a canonical string describing its structure, and to refine it
level by level:

- **Level 0** describes the resource by itself: its types and the
  datatype/language of its literal values, with their cardinalities.
- **Level n+1** adds, for each outgoing link, the **level-n signature** of the
  linked resource. Level n therefore describes the resource's neighbourhood up
  to n hops away.

Resources with the same signature at a given level have the same structure up
to that depth, so they are candidates for the same shape. This is similar in
spirit to colour refinement (the Weisfeiler–Lehman test) on graphs. Going
deeper separates resources that look alike locally but differ in their
surroundings.

The planned next step, not yet implemented, is to turn the signatures into
SHACL shapes, e.g. one `sh:NodeShape` per signature (or group of signatures),
with property shapes derived from the signature contents.

## Current status

What exists today:

| Path | Purpose |
| --- | --- |
| `updates/signatures-base.ru` | SPARQL update: drops the signature graph and computes level-0 signatures. |
| `updates/signatures-rec.ru` | SPARQL update: computes signatures for the level after the highest existing one. Run it repeatedly to go deeper. |
| `queries/signatures.rq` | Number of distinct signatures and of signed resources per level. |
| `queries/convergence.rq` | Signature count per level compared with the previous level; tells when more levels stop being useful. |
| `queries/duplicate-shapes.rq` | Sanity check: resources with more than one level-1 signature (expected: none). |
| `queries/without-signature.rq` | Triples whose subject has no signature. |
| `scripts/sig-converge.sh` | Computes levels one after another until the partition converges (optionally starting from level 0). |
| `scripts/*.sh` | Wrappers around the Apache Jena command-line tools (see below). |
| `kg/config/kg-config.ttl` | TDB2 dataset + Fuseki service configuration. |
| `docs/signatures.md` | Detailed description of the signature format and data model. |

Not there yet: shape generation, automated tests, sample data.

## Requirements

- [Apache Jena](https://jena.apache.org/) command-line tools on the `PATH`
  (`tdb2.tdbloader`, `tdb2.tdbupdate`, `tdb2.tdbquery`), plus
  [Fuseki](https://jena.apache.org/documentation/fuseki2/) (`fuseki-server`)
  if you want a SPARQL endpoint.
- Enough memory: the scripts set `-Xmx16G`.

## Usage

Run every script from the repository root.

1. Put the knowledge graph, as gzipped N-Quads, in `input/kg.nq.gz`. `input/`
   is git-ignored.
2. Load it into TDB2 (stored in `kg/tdb2/`, also git-ignored):
   ```sh
   scripts/load.sh
   ```
3. Compute level-0 signatures (this replaces all existing signatures):
   ```sh
   scripts/sig-base.sh
   ```
4. Compute one more level each time you run:
   ```sh
   scripts/sig-rec.sh   # level 1
   scripts/sig-rec.sh   # level 2, ...
   ```
   Once `queries/convergence.rq` reports `converged = true` for the last
   level, more levels won't separate any more resources.

   Alternatively, let the loop script do steps 3 and 4, stopping at
   convergence:
   ```sh
   scripts/sig-converge.sh --base                 # from level 0 to convergence
   scripts/sig-converge.sh                        # continue from the last level
   scripts/sig-converge.sh --base --max-levels 5  # at most 5 levels after level 0
   ```
   It exits with status 0 when converged and 2 when `--max-levels` was reached
   first. The last level it computes is the one that confirms convergence, so
   it duplicates the previous level's partition. `TDB_ARGS` overrides the
   dataset options (default `--tdb=kg/config/kg-config.ttl`).
5. Inspect the results:
   ```sh
   scripts/check.sh
   ```
6. Optionally, expose the dataset as a SPARQL endpoint
   (`http://localhost:3030/shapes/`):
   ```sh
   scripts/serve_kg.sh
   ```

The signatures are written to the named graph
`<https://w3id.org/hacid/data/sig/graph>`. The dataset uses
`tdb2:unionDefaultGraph true`, so the default graph is the union of all named
graphs, including the signature graph.

See [`docs/signatures.md`](docs/signatures.md) for the signature format, the
RDF vocabulary used, and known limitations.

## License

See [LICENSE](LICENSE).
