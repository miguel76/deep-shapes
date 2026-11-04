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

The update finds the highest existing level `n` and computes level `n+1`.
The id is:

```
<level-0 id>; <group1>;<group2>;...
```

where each group describes outgoing non-`rdf:type` links to resources that
have a level-n signature:

```
<p1>|<p2> [<target ref>] (count)
```

- `<p1>|<p2>` is the set of properties linking the resource to the same
  target.
- `<target ref>` identifies the target's level-n signature:
  - at **level 1** it is the target's full level-0 id (itself a hash);
  - from **level 2** on it is `#` followed by the SHA-1 (hex) of the target's
    level-n id. Embedding full ids would nest every previous level, making ids
    grow exponentially on cyclic data. With hashes, an id's length depends only
    on the resource's level-0 id and its number of link groups.
- `(count)` is the number of distinct targets with that property set and
  target signature (`n` when greater than 5).
- If the resource has no such links, its id at level n+1 equals its level-0 id.

Example, `ex:alice` at level 1:

```
<level-0 id of ex:alice>; <http://ex.org/knows> [<level-0 id of ex:bob>] (1);<http://ex.org/livesIn> [<level-0 id of ex:rome>] (1)
```

The same resource at level 2:

```
<level-0 id of ex:alice>; <http://ex.org/knows> [#1c3e63c840f97fefec28689493b24e02ffe7ac3d] (1);<http://ex.org/livesIn> [#16250d1c5c8c813ff0481e66908d9cada20d4686] (1)
```

To resolve a reference `#h` in a level-(n+1) id, look for the level-n
signature whose id hashes to `h`:

```sparql
?target_sig sig:level <sig/levels/1> ; sig:id ?target_id .
FILTER(SHA1(?target_id) = "1c3e63c840f97fefec28689493b24e02ffe7ac3d")
```

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

Once the levels have converged, `scripts/sig-converge.sh` (via
`updates/signatures-finalize.ru`) marks the last level kept:

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

- **n = 0.** The level-1 id starts with the level-0 id, so equal level-1 ids
  imply equal level-0 ids.
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
never produce the same id. That holds because IRIs are written between `<` and
`>`, which cannot occur inside an IRI, and target references are wrapped in
balanced `[`…`]`. From level 2 on it also assumes SHA-1 has no collisions
among the signature ids of a level, which is safe in practice for accidental
collisions.

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
signatures. Since targets are referenced by
hash from level 2 on, id length stays bounded either way.

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
- **Ids are not self-describing.** Level-0 ids and their parts are hashes;
  the readable information is in the intermediate signatures (member types,
  member properties, value counts). From level 2 on target references are
  hashes too, so reading one requires looking up the target's signature at the
  previous level (see the query above).
- **The signature graph is visible in the default graph.** Because of
  `tdb2:unionDefaultGraph true`, queries over the default graph (including the
  updates themselves and `queries/without-signature.rq`) also see the
  signature triples.
- **Config file and Jena 5.x.** With Jena 5.2, the `tdb2.*` tools reject
  `kg/config/kg-config.ttl` ("No such type ... DatasetTDB2"); using
  `--loc=kg/tdb2 --set=tdb:unionDefaultGraph=true` works instead.
