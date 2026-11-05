# deep-shapes

[![Tests](https://github.com/miguel76/deep-shapes/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/miguel76/deep-shapes/actions/workflows/tests.yml?query=branch%3Amain)

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

Once the partition stops changing, the signatures of the final level are
turned into SHACL shapes: one `sh:NodeShape` per signature, with property
shapes derived from the signature contents (see
[`docs/shapes.md`](docs/shapes.md)).

## Current status

What exists today:

| Path | Purpose |
| --- | --- |
| `updates/signatures-base.ru` | SPARQL update: drops the signature graph and computes level-0 signatures. |
| `updates/signatures-rec.ru` | SPARQL update: computes signatures for the level after the highest existing one. Run it repeatedly to go deeper. |
| `updates/signatures-finalize.ru` | SPARQL update: after convergence, marks the highest level as final and links its object property signatures to the final signatures of their targets. |
| `updates/shapes.ru` | SPARQL update: generates SHACL shapes from the final level (see [`docs/shapes.md`](docs/shapes.md)). |
| `queries/signatures.rq` | Number of distinct signatures and of signed resources per level. |
| `queries/convergence.rq` | Signature count per level compared with the previous level; tells when more levels stop being useful, and which level is marked final. |
| `queries/duplicate-shapes.rq` | Sanity check: resources with more than one level-1 signature (expected: none). |
| `queries/without-signature.rq` | Triples whose subject has no signature. |
| `queries/shapes.rq` | The generated shapes. |
| `scripts/sig-converge.sh` | Computes levels one after another until the partition converges, then marks the last level as final. |
| `scripts/*.sh` | Wrappers around the Apache Jena command-line tools (see below). |
| `kg/config/kg-config.ttl` | TDB2 dataset + Fuseki service configuration. |
| `scripts/shapes.sh` | Generates the shapes and writes them as Turtle. |
| `docs/signatures.md` | Detailed description of the signature format and data model. |
| `docs/shapes.md` | How shapes are generated from the signatures, and their limitations. |
| `tests/` | End-to-end tests and the synthetic graph generator (see [Tests](#tests)). |

Shape generation is a first version: see the limitations in
[`docs/shapes.md`](docs/shapes.md).

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
   scripts/sig-converge.sh                         # continue (or start) until convergence
   scripts/sig-converge.sh --max-levels 5          # at most 5 new levels in this run
   scripts/sig-converge.sh --restart               # discard all signatures, start from level 0
   ```
   - It computes level 0 first if there are no signatures yet, and otherwise
     continues from the highest existing level.
   - Convergence is only visible once a level adds no signatures. That level
     has the same partition as the previous one, so the script stops there
     and marks it with `sig:final true` (`updates/signatures-finalize.ru`).
     Its signatures are the candidate shapes: each is linked to the
     previous-level signature with the same members
     (`sig:hasParentSignature`), so the targets of its links can be resolved
     to final signatures too. Later runs see the mark and stop immediately.
   - It exits with status 0 when converged and 2 when `--max-levels` was
     reached first.
   - `TDB_ARGS` overrides the dataset options (default
     `--tdb=kg/config/kg-config.ttl`).
5. Generate the SHACL shapes from the final level, written as Turtle
   (`sh:qualifiedEquals` in them is an extension of SHACL, see
   [`docs/shapes.md`](docs/shapes.md)):
   ```sh
   scripts/shapes.sh shapes.ttl
   ```
6. Inspect the results:
   ```sh
   scripts/check.sh
   ```
7. Optionally, expose the dataset as a SPARQL endpoint
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

## Tests

The tests run the real updates and scripts with Jena on small graphs, each in
a temporary TDB2 store. They need Python 3 (standard library only) and the
Jena tools on the `PATH`, or `JENA_HOME` pointing to a Jena distribution;
without Jena they are skipped (unless `REQUIRE_JENA=1` is set). They also run
on GitHub Actions on every push
(`.github/workflows/tests.yml`). From the repository root:

```sh
python3 -m unittest discover -s tests -v
```

They take a few minutes, mostly JVM start-up for each Jena call. What they
check:

- on every graph: one signature per resource and level, each level refining
  the previous one, signature counts increasing up to a final level marked
  `sig:final` (which has as many signatures as the level below), and a rerun of `sig-converge.sh` doing nothing;
- on structured graphs with a known answer: the exact signature count at
  each level and the final level, and that resources share a final signature
  exactly when they follow the same SHACL shape;
- `--max-levels` and resuming, and `--restart`;
- the generated shapes: their structure on every graph; on the structured
  graphs and on `tests/data/people-places.ttl`, that the data conforms to
  them (with Jena SHACL), and on the latter a snapshot of the shapes;
- the exact ids for levels 0–2 on a small hand-written graph
  (`tests/data/people.ttl`) against a snapshot in `tests/expected/`. If the
  id format changes on purpose, regenerate it with `UPDATE_SNAPSHOTS=1` and
  review the diff.

### Synthetic graphs

`tests/generate.py` writes the test graphs, and can be used on its own to
produce larger ones:

```sh
python3 tests/generate.py layered --families 3 --depth 6 --fanout 2 --copies 100 --out /tmp/layered
python3 tests/generate.py random --nodes 10000 --max-degree 9 --seed 1 --out /tmp/random
```

- **`layered`**: for each family, `--copies` complete trees of depth `--depth`
  and fan-out `--fanout`. Leaves differ by family, and internal nodes look
  alike until their leaves are within reach, so `--depth` sets how many
  levels are needed to tell all nodes apart. Besides `data.nt`, it writes
  `shapes.ttl`, the SHACL shapes the data follows (one per family and node
  height, the shapes a complete discovery pipeline should find), and
  `expected.json`, with the expected signature counts per level, the final
  level, and the nodes of each shape.
- **`random`**: an unstructured graph with cycles and link counts above the
  cap of 5. Only the general properties can be checked on it.

Load `data.nt` into a named graph, e.g.
`tdb2.tdbloader --loc=… --graph=http://example.org/synthetic/graph data.nt`.

## License

See [LICENSE](LICENSE).
