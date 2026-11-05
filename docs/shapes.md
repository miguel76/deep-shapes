# Shapes

`updates/shapes.ru` turns the final signature level (see
[signatures.md](signatures.md)) into SHACL shapes. Run it after
`scripts/sig-converge.sh` has converged, or use `scripts/shapes.sh`, which
runs it and writes the shapes as Turtle:

```sh
scripts/shapes.sh shapes.ttl
```

The update replaces any shapes generated before, and does nothing if no level
is marked `sig:final` yet. `signatures-base.ru` drops the shapes too, since
they no longer match the new signatures.

## Where the shapes are

The shapes are written to the named graph
`<https://w3id.org/hacid/data/shapes/graph>` (`queries/shapes.rq` returns
them). Each final node signature is linked to its shape in the signature
graph:

```turtle
<sig/signatures/nodes/{final level}/{id}> sig:hasShape <shapes/nodes/{id}> .
```

so `?i sig:hasNodeSignature/sig:hasShape ?shape` (restricted to the final
level) gives the shape of a resource.

Every IRI is built from signature ids (relative to
`<https://w3id.org/hacid/data/>`):

| IRI | What |
| --- | --- |
| `shapes/nodes/{node signature id}` | node shape |
| `shapes/datatype-properties/{datatype property signature id}` | property shape, unqualified |
| `shapes/qualified-datatype-properties/{datatype property signature id}` | property shape, qualified |
| `shapes/object-properties/{object property signature id}` | property shape, unqualified |
| `shapes/qualified-object-properties/{object property signature id}` | property shape, qualified |
| `{property shape}/{SHA-1 of the property IRI}` | companion property shape for another property of the path |
| `shapes/literals/{SHA-1 of "<datatype>" or "<datatype> @lang"}` | value shape of qualified datatype property shapes |
| `shapes/languages/{lang}` | the list `("lang")` for `sh:languageIn` |
| `shapes/ignored-properties` | the list `(rdf:type)` for `sh:ignoredProperties` |

There are no blank nodes, not even in lists, so a shape used by several node
shapes is written once and the output is deterministic.

## Node shapes

One per final node signature, with no target:

```turtle
<shapes/nodes/{id}> a sh:NodeShape ;
    sh:class ex:Person ;                      # one per member type, if any
    sh:closed true ;
    sh:ignoredProperties <shapes/ignored-properties> ;   # (rdf:type)
    sh:property ... .
```

The shape is closed because a signature describes every outgoing property of
its members (rdf:type aside, which `sh:class` covers). Every property of a
path signature is the `sh:path` of some property shape, so closing it
doesn't reject any member.

## Property shapes

Each datatype property signature (through the base node signature) and each
object property signature of the node signature gives a property shape. Its
path is the **main property** of the path signature: the smallest of its
properties by IRI. The value constraint is:

- datatype property signature: the datatype (`sh:datatype`) and, for
  language-tagged literals, the language (`sh:languageIn ("lang")`);
- object property signature: the shape of the target's final signature
  (`sh:node`, from `sig:refersToTargetNodeSignature`).

The value count gives the cardinality: min = max = count when it is at most
5, and only min = 6 when it was capped (`sig:hasMinValueCount`).

When the path signature has several properties (the same values reached
through several properties), each **other property** gets a companion
property shape on that property, which makes its values equal to the main
property's.

### Unqualified and qualified property shapes

A property shape is **unqualified** when its properties appear in no other
property signature (datatype or object) of the same node signature: then all
the values of the main property are described by this shape alone.

```turtle
<shapes/datatype-properties/{id}> a sh:PropertyShape ;
    sh:path ex:name ;
    sh:datatype xsd:string ;
    sh:minCount 1 ; sh:maxCount 1 .
<shapes/datatype-properties/{id}/{hash}> a sh:PropertyShape ;   # companion
    sh:path rdfs:label ;
    sh:equals ex:name .
<shapes/object-properties/{id}> a sh:PropertyShape ;
    sh:path ex:livesIn ;
    sh:node <shapes/nodes/{target id}> ;
    sh:minCount 1 ; sh:maxCount 1 .
```

Otherwise, the values of a property are split between several property
shapes (e.g. `ex:nick` with values in two languages, or `ex:knows` with
targets of two shapes), and the shape is **qualified**: the value constraint
becomes the qualified value shape and the counts are qualified counts.

```turtle
<shapes/qualified-datatype-properties/{id}> a sh:PropertyShape ;
    sh:path ex:nick ;
    sh:qualifiedValueShape <shapes/literals/{hash}> ;
    sh:qualifiedMinCount 1 ; sh:qualifiedMaxCount 1 .
<shapes/literals/{hash}> a sh:NodeShape ;
    sh:datatype rdf:langString ;
    sh:languageIn <shapes/languages/en> .                    # ("en")
<shapes/qualified-object-properties/{id}> a sh:PropertyShape ;
    sh:path ex:knows ;
    sh:qualifiedValueShape <shapes/nodes/{target id}> ;
    sh:qualifiedMinCount 1 ; sh:qualifiedMaxCount 1 .
```

A qualified companion has the same qualified value shape and counts, and
`sh:qualifiedEquals` instead of `sh:equals`:

```turtle
<shapes/qualified-datatype-properties/{id}/{hash}> a sh:PropertyShape ;
    sh:path rdfs:label ;
    sh:qualifiedValueShape <shapes/literals/{hash}> ;
    sh:qualifiedMinCount 1 ; sh:qualifiedMaxCount 1 ;
    sh:qualifiedEquals ex:name .
```

(SHACL requires a qualified count with `sh:qualifiedValueShape`; the
companion's counts are implied by the equality anyway.)

### `sh:qualifiedEquals`

`sh:qualifiedEquals` is **not part of SHACL**: it is an extension, the
qualified counterpart of `sh:equals`. On a property shape with path `p` and
qualified value shape `S`, `sh:qualifiedEquals q` means that the values of
`p` that conform to `S` are the same as the values of `q` that conform to
`S`. SHACL engines ignore it (Jena does), so with a standard engine a
qualified companion only checks its qualified counts.

The decision is per (node signature, property signature): the same property
signature can be unqualified in one node shape and qualified in another,
which is why the two kinds have different IRIs.

## Validation

The tests add `sh:targetNode` for every resource to the shape of its final
signature (`tests/queries/shapes-with-targets.rq`) and validate the data
with Jena SHACL: the `layered` graphs and `tests/data/people-places.ttl`
conform to their shapes. `tests/queries/shape-structure.rq` checks the
structure (one shape per final signature, one property shape per property
signature and property, no shape both qualified and unqualified) on every
test graph, and `tests/expected/people-places-shapes.nt` is a snapshot of
the shapes of `people-places.ttl`.

## Known limitations

- **Overlapping paths.** The signatures distinguish values by the exact set
  of properties reaching them, which SHACL can't express. If a node
  signature has a value reached by `p` only and one reached by `p` and `q`,
  with value shapes they both satisfy, the qualified property shape on `p`
  counts both, and the members don't conform with a standard SHACL engine.
  Data with such overlaps (frequent in the `random` test graph) needs an
  engine that reads the qualified shapes as exact path sets.
- **Types are not exact.** `sh:class` accepts instances of subclasses and
  doesn't exclude other types, so a resource with more types also conforms
  to a shape with fewer. Qualified counts on object properties whose targets
  differ only in that way count the same targets twice.
- **Language ranges.** `sh:languageIn ("en")` also accepts `en-US`, while
  signatures distinguish the two tags.
- **Capped counts.** Above 5 values, only the minimum (6) is known.
- **Classes.** Classes are signed (as objects of `rdf:type`), so they get
  shapes too, usually the empty closed shape.
