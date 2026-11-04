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

A level-0 signature id is:

```
a <Type1>,<Type2>;<group1>;<group2>;...
```

- `a <Type1>,<Type2>` lists the resource's `rdf:type` values, sorted.
- Each `<group>` describes the literal values of the resource, grouped by
  property set and datatype:
  ```
  <p1>|<p2> ^^<datatype> @lang (count)
  ```
  - `<p1>|<p2>` is the set of properties that link the resource to the *same*
    literal. Usually this is a single property; it has several only when one
    literal value is shared, as with `ex:name` and `rdfs:label` both being
    `"Alice"` above.
  - `@lang` appears only for language-tagged literals.
  - `(count)` is the number of distinct literals in that group, written `n`
    when it is greater than 5.
- Object (non-literal) values are ignored at this level.

Parts that would be empty are left out. A resource with no types starts
directly with its literal groups, and a resource with neither types nor
literals (e.g. a class such as `ex:City` above) gets the **empty id `""`**.
This is intended: resources with no outgoing edges at all, typically
classes or other resources that only appear as objects, keep the empty id at
every level. A different representation may be adopted later.

Example, for `ex:alice`:

```
a <http://ex.org/Person>;<http://ex.org/name>|<http://www.w3.org/2000/01/rdf-schema#label> ^^<http://www.w3.org/2001/XMLSchema#string> (1);<http://ex.org/nick> ^^<http://www.w3.org/1999/02/22-rdf-syntax-ns#langString> @en (2)
```

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
<p1>|<p2> [<level-n id of the target>] (count)
```

- `<p1>|<p2>` is the set of properties linking the resource to the same
  target.
- `(count)` is the number of distinct targets with that property set and
  target signature (`n` when greater than 5).
- If the resource has no such links, its id at level n+1 equals its level-0 id.
- If the level-0 id is empty, the level-n+1 id is just the link groups (no
  leading `; `).

Example, `ex:alice` at level 1:

```
<level-0 id of ex:alice>; <http://ex.org/knows> [a <http://ex.org/Person>;<http://ex.org/name> ^^<http://www.w3.org/2001/XMLSchema#string> (1)] (1);<http://ex.org/livesIn> [a <http://ex.org/City>] (1)
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

The level is part of the signature IRI (`sig/signatures/{level}/...`). This is
required: the same id string can occur at several levels (see above), and a
signature node shared across levels would have several `sig:level` values,
making resources appear to have more than one signature per level.

Expected invariant: **every signed resource has exactly one signature per
level.** `queries/duplicate-shapes.rq` checks this for level 1.

## Known limitations and quirks

- **Ordering inside ids relies on Jena.** The updates sort with `ORDER BY` in
  subqueries and then `GROUP_CONCAT`. SPARQL doesn't guarantee that
  `GROUP_CONCAT` follows that order; Jena does in practice, but another engine
  might produce different ids for the same structure.
- **The level-n partition may not strictly refine level n-1.** Counts are
  capped at `n` (> 5), so two resources can share a level-(n+1) id even with
  different numbers of links at deeper levels.
- **The signature graph is visible in the default graph.** Because of
  `tdb2:unionDefaultGraph true`, queries over the default graph (including the
  updates themselves and `queries/without-signature.rq`) also see the
  signature triples.
- **Config file and Jena 5.x.** With Jena 5.2, the `tdb2.*` tools reject
  `kg/config/kg-config.ttl` ("No such type ... DatasetTDB2"); using
  `--loc=kg/tdb2 --set=tdb:unionDefaultGraph=true` works instead.
