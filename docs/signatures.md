# Signatures

This document describes what the signature updates compute, how the results
are stored, and the known limitations. The examples come from running the
updates on this small graph:

```turtle
@prefix ex: <http://ex.org/> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

ex:alice a ex:Person ;
    ex:name "Alice" ; rdfs:label "Alice" ;
    ex:nick "Al"@en, "Ali"@en ;
    ex:livesIn ex:rome ;
    ex:knows ex:bob .
ex:bob  a ex:Person ; ex:name "Bob" .
ex:rome a ex:City .
```

## Which resources get a signature

`signatures-base.ru` signs every resource that is either:

- the subject of some triple (IRIs and blank nodes), or
- an IRI used as the object of some triple, **including `rdf:type`**. This is
  why classes such as `ex:Person` also get signatures.

`signatures-rec.ru` signs, at the new level, every resource that has a level-0
signature.

## Level 0: `updates/signatures-base.ru`

The level-0 signature is built in steps. Each step stores intermediate
signatures in the signature graph, so that the information needed later to
build shapes (member types, member properties, value counts) is kept, not only
the association between resources and their final signature. All ids at this
level are SHA-1 hashes (hex) of a canonical string.

1. **Type signature** (`sig:TypeSignature`, IRI `sig/signatures/types/0/{id}`):
   id = SHA-1 of the resource's `rdf:type` values, written `<Type>` and sorted
   (empty string for an untyped resource). Linked with
   `?i sig:hasTypeSignature ?type_sig`. A second step stores the types of a
   sample member: `?type_sig sig:hasMemberType ?type`.
2. **Datatype path signature** (`sig:DatatypePathSignature`, IRI
   `sig/signatures/datatype-values/0/{id}`): one per (resource, literal) pair,
   id = SHA-1 of
   ```
   <p1>|<p2> ^^<datatype> @lang
   ```
   where `<p1>|<p2>` is the sorted set of properties that link the resource to
   that *same* literal (usually one; several only when a literal is shared, as
   with `ex:name` and `rdfs:label` both being `"Alice"` above), and `@lang`
   appears only for language-tagged literals. Each pair is stored as
   `?path_sig sig:hasSourceTargetPair [ sig:source ?i ; sig:target ?literal ]`,
   and the properties of a sample pair as `?path_sig sig:hasMemberProperty ?p`.
3. **Datatype property signature** (`sig:DatatypePropertySignature`, IRI
   `sig/signatures/datatype-properties/0/{id}`): per resource and datatype path
   signature, id = SHA-1 of the path signature id followed by the number of
   distinct literals, written `n` when greater than 5. It stores
   `sig:hasDatatypePathSignature`, and either `sig:hasExactValueCount` (the
   count, when at most 5) or `sig:hasMinValueCount` (6, when the count is
   greater than 5). Linked with `?i sig:hasDatatypePropertySignature ?prop_sig`.
4. **Signature** (`sig:Signature`, IRI `sig/signatures/0/{id}`): id = SHA-1 of
   ```
   {type signature id};{datatype property signature ids, sorted, space-separated}
   ```
   Linked with `?i sig:hasSignature ?sig`.

Object (non-literal) values are ignored at this level. A resource with neither
types nor literals (e.g. a class such as `ex:City` above) gets the type
signature of the empty string and no datatype property signatures; all such
resources share one level-0 signature, and keep it at every level if they
have no outgoing edges.

The data patterns read only graphs other than the signature graph
(`GRAPH ?g { ... } FILTER(?g != sigdata:graph)`), since the intermediate
signatures written by earlier steps are visible through the union default
graph.

The update starts with `DROP SILENT GRAPH`, so it always replaces every
existing signature (all levels).

## Level n+1: `updates/signatures-rec.ru`

The update finds the highest existing level `n`, adds the level `n+1`
(`sig:SignatureLevel`), and then builds its signatures in the same steps as
level 0, but over outgoing non-`rdf:type` links to resources that have a
level-n signature (object links) instead of literals:

1. **Object path signature** (`sig:ObjectPathSignature`, IRI
   `sig/signatures/object-values/{n+1}/{id}`): one per (resource, target)
   pair, id = SHA-1 of
   ```
   <p1>|<p2> [<target's level-n signature id>]
   ```
   where `<p1>|<p2>` is the sorted set of properties linking the resource to
   that *same* target. It stores the target's level-n signature
   (`sig:hasTargetSignature`), each pair
   (`sig:hasSourceTargetPair [ sig:source ?i ; sig:target ?o ]`), and the
   properties of a sample pair (`sig:hasMemberProperty`).
2. **Object property signature** (`sig:ObjectPropertySignature`, IRI
   `sig/signatures/object-properties/{n+1}/{id}`): per resource and object
   path signature, id = SHA-1 of the path signature id followed by the number
   of distinct targets (`n` when greater than 5). It stores
   `sig:hasObjectPathSignature` and `sig:hasExactValueCount` or
   `sig:hasMinValueCount`, as for literals. Linked with
   `?i sig:hasObjectPropertySignature ?prop_sig`.
3. **Signature** (`sig:Signature`, IRI `sig/signatures/{n+1}/{id}`): id =
   SHA-1 of
   ```
   {level-0 signature id};{object property signature ids, sorted, space-separated}
   ```
   for every resource with a level-0 signature. A resource without object
   links gets SHA-1 of `{level-0 id};`: a different id from its level-0 one,
   but the same one at every level.

Since every id is a SHA-1 hash, an id embeds its targets' previous-level ids
without growing with the level, also on cyclic data. Ids are not readable on
their own: the structure is in the intermediate signatures.

Incoming links are not part of the signature.

## Data model

Everything is written to the named graph
`<https://w3id.org/hacid/data/sig/graph>`. The vocabulary namespace is
`sig: <https://w3id.org/sig/>`, and the base IRI is
`<https://w3id.org/hacid/data/>`.

```turtle
<sig/levels/1> a sig:SignatureLevel ;
    sig:levelValue 1 .

<sig/signatures/1/{ENCODE_FOR_URI(id)}> a sig:Signature ;
    sig:level <sig/levels/1> ;
    sig:id "{id}" .

ex:alice sig:hasSignature <sig/signatures/1/...> .
```

The intermediate signatures of each level are stored next to it, with the
same `sig:level` and `sig:id`:

```turtle
# level 0
ex:alice sig:hasTypeSignature <sig/signatures/types/0/...> ;
    sig:hasDatatypePropertySignature <sig/signatures/datatype-properties/0/...> .
<sig/signatures/types/0/...> a sig:TypeSignature ;
    sig:hasMemberType ex:Person .
<sig/signatures/datatype-properties/0/...> a sig:DatatypePropertySignature ;
    sig:hasDatatypePathSignature <sig/signatures/datatype-values/0/...> ;
    sig:hasExactValueCount 2 .              # or sig:hasMinValueCount 6
<sig/signatures/datatype-values/0/...> a sig:DatatypePathSignature ;
    sig:hasMemberProperty ex:nick ;
    sig:hasSourceTargetPair [ sig:source ex:alice ; sig:target "Al"@en ] .

# level n >= 1
ex:alice sig:hasObjectPropertySignature <sig/signatures/object-properties/1/...> .
<sig/signatures/object-properties/1/...> a sig:ObjectPropertySignature ;
    sig:hasObjectPathSignature <sig/signatures/object-values/1/...> ;
    sig:hasExactValueCount 1 .
<sig/signatures/object-values/1/...> a sig:ObjectPathSignature ;
    sig:hasMemberProperty ex:knows ;
    sig:hasTargetSignature <sig/signatures/0/...> ;   # ex:bob's level-0 signature
    sig:hasSourceTargetPair [ sig:source ex:alice ; sig:target ex:bob ] .
```

Only `sig:Signature` nodes are signatures in the sense of the partition;
queries that count signatures per level must filter on that type (as
`queries/convergence.rq` does).

Once the levels have converged, `scripts/sig-converge.sh` (via
`updates/signatures-finalize.ru`) removes the redundant highest level, with
its intermediate signatures, and marks the last level kept:

```turtle
<sig/levels/8> sig:final true .
```

The level is part of the signature IRI (`sig/signatures/{level}/...`). This is
required: the same id string can occur at several levels (see above), and a
signature node shared across levels would have several `sig:level` values,
making resources appear to have more than one signature per level.

Expected invariant: **every signed resource has exactly one signature per
level.** `queries/duplicate-shapes.rq` checks this for level 1.

## Refinement and convergence

Group resources by their signature at level n; call that partition P(n).

### Each level refines the previous one

If two resources have the same level-(n+1) signature, they also have the same
level-n signature. So P(n+1) refines P(n), and the number of distinct
signatures never decreases from one level to the next.

By induction on n:

- **n = 0.** The level-1 id is computed from the level-0 id, so equal
  level-1 ids imply equal level-0 ids.
- **Step.** Assume P(n) refines P(n-1), so the level-(n-1) signature of a
  resource is a function of its level-n signature. Take two resources with the
  same level-(n+1) id. They have the same level-0 id and the same groups
  `(property set, level-n target signature, capped count)`. Their level-n ids
  consist of the same level-0 id plus the groups
  `(property set, level-(n-1) target signature, capped count)`, obtained by
  mapping each level-n target signature to its level-(n-1) signature and
  merging groups that become equal. Merging adds the counts of disjoint target
  sets, and the capped total depends only on the capped parts: it is `n` if any
  part is `n` or the exact sum exceeds 5, and the exact sum otherwise. So both
  resources get the same level-n id.

Capping counts at `n` therefore does not break refinement. It only makes each
P(n) coarser than it would be with exact counts.

The argument assumes the ids are unambiguous, i.e. two different structures
never produce the same id. The strings that get hashed are unambiguous because
IRIs are written between `<` and `>`, which cannot occur inside an IRI, the
target reference is wrapped in `[`…`]`, and the other parts are fixed-length
hashes or counts. It also assumes SHA-1 has no collisions among the ids
computed, which is safe in practice for accidental collisions.

### Convergence

The same set of resources is signed at every level, and the number of
distinct signatures can't exceed the number of resources. So the count can
increase only finitely many times. Once two consecutive levels have the same
count, P(n+1) = P(n), and every later level has the same partition too: the
level-(n+1) signatures are then a one-to-one renaming of the level-n ones, so
the groups at level n+2 are a renaming of those at level n+1, with nothing
merged. This is the usual stopping rule for colour refinement
(Weisfeiler–Lehman): **stop at the first level whose signature count equals the
previous level's**. Since each level before that adds at least one signature,
this happens after at most (number of signed resources − number of level-0
signatures) levels. A chain of k nodes that differ only by their distance to
the end needs about k levels.

Partitions converge, but ids need not. On acyclic data the ids eventually stop
changing. With cycles, a resource's id references its targets' previous-level
ids, which keep changing, so the ids change at every level even after the
partition is stable: they are just renamed. Detect convergence by comparing
signature **counts** between levels, not ids: `queries/convergence.rq` does
this, reporting `converged = true` at the first level that adds no
signatures. Since ids are hashes, their length is fixed either way.

That first level that adds nothing is redundant: it repeats the previous
level's partition under new names. `scripts/sig-converge.sh` computes levels
until it appears, then removes it and marks the previous level with
`sig:final true` (`final = true` in `queries/convergence.rq`), so the
highest level kept is the converged one, and later runs don't recompute it.

### Empirical check

Both properties are checked by the test suite (`tests/`, see the README),
with `tests/queries/refinement.rq`, which looks for two resources with the
same level-(n+1) signature but different level-n signatures. On the
`layered` graphs of `tests/generate.py` the exact counts are known: with F
families of trees of depth D, level n has

```
1 (classes, no types or literals) + F (leaves) + F·min(n, D) + (1 if n < D else 0)
```

signatures, so the partition is final at level D (level D − 1 when F = 1).

Before the test suite, the properties were checked by hand on two graphs:

- an 80-node random graph with out-degrees up to 9 (so the cap is exercised):
  6 signatures at level 0, then 78 from level 1 through level 10. The longest
  id is 794 characters at level 1 and 1,055 from level 2 on. Before targets
  were hashed it grew to 9.4 million characters at level 6, and level 7 ran
  out of memory. The partition is stable from level 1, but the ids of the 74
  resources with links change at every level (the graph has cycles);
- a 9-node chain of typed nodes: 2, 3, 4, …, 10 signatures at levels 0–8, then
  stable at 10, and from then on the ids no longer change either.

## Known limitations and quirks

- **Ordering inside ids relies on Jena.** The updates sort with `ORDER BY` in
  subqueries and then `GROUP_CONCAT`. SPARQL doesn't guarantee that
  `GROUP_CONCAT` follows that order; Jena does in practice, but another engine
  might produce different ids for the same structure.
- **Ids are not self-describing.** All ids are hashes; the readable
  information is in the intermediate signatures (member types, member
  properties, target signatures, value counts).
- **The signature graph is visible in the default graph.** Because of
  `tdb2:unionDefaultGraph true`, queries over the default graph (including the
  updates themselves and `queries/without-signature.rq`) also see the
  signature triples.
- **Config file and Jena 5.x.** With Jena 5.2, the `tdb2.*` tools reject
  `kg/config/kg-config.ttl` ("No such type ... DatasetTDB2"); using
  `--loc=kg/tdb2 --set=tdb:unionDefaultGraph=true` works instead.
