#!/usr/bin/env python3
"""Generate synthetic knowledge graphs for testing the signature pipeline.

Two kinds of graph are supported:

``layered``
    Structured data with a known answer. For each of ``--families`` families
    there are ``--copies`` complete trees of depth ``--depth`` and fan-out
    ``--fanout``. Internal nodes are ``ex:Node`` instances with one
    ``ex:label`` literal and ``--fanout`` ``ex:child`` links; leaves are
    ``ex:Leaf`` instances with one literal on a family-specific property
    ``ex:tag{family}``.

    Nodes look alike up to the distance at which their leaves become visible,
    so the depth controls how many signature levels are needed to tell all
    structures apart. Besides the data, the generator writes:

    - ``shapes.ttl``: the SHACL shapes the data follows, one per family and
      node height (height 0 = leaf), with ``sh:targetNode`` for every node.
      These are the shapes a complete pipeline should discover;
    - ``expected.json``: the expected number of signatures at each level, the
      expected final level after ``scripts/sig-converge.sh``, and the nodes
      of each shape (resources with the same shape must end up with the same
      final signature, and different shapes with different signatures).

``random``
    Unstructured data: ``--nodes`` nodes with random types, an optional
    literal and random links on ``--predicates`` properties (out-degree per
    property up to ``--max-degree``, so counts above 5 occur when it is 6 or
    more). Only general properties can be checked on it; ``expected.json``
    just records the parameters.

Data is written as N-Triples (``data.nt``); load it into a named graph, as
the pipeline relies on the union default graph.

Examples::

    python3 tests/generate.py layered --families 2 --depth 4 --fanout 2 --copies 2 --out /tmp/g1
    python3 tests/generate.py random --nodes 80 --max-degree 9 --seed 7 --out /tmp/g2
"""

import argparse
import json
import random
import sys
from pathlib import Path

EX = "http://example.org/synthetic/"
RDF_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
XSD_STRING = "http://www.w3.org/2001/XMLSchema#string"
GRAPH = EX + "graph"


def iri(local):
    return f"<{EX}{local}>"


def literal(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def triple(s, p, o):
    return f"{s} {p} {o} .\n"


# --------------------------------------------------------------------------
# layered


def layered_expected_counts(families, depth, max_level):
    """Number of distinct signatures at each level 0..max_level.

    At level n, a node of height h <= n "sees" its leaves, so it is told apart
    by family and height; all nodes of height > n look the same. Leaves are
    told apart by family from level 0. The classes ex:Node and ex:Leaf are
    signed too (as objects of rdf:type) and share the empty signature.
    """
    counts = []
    for n in range(max_level + 1):
        count = 1  # the classes, with the empty id
        count += families  # leaves
        count += families * min(n, depth)  # internal nodes of height <= n
        if n < depth:
            count += 1  # all internal nodes of height > n
        counts.append(count)
    return counts


def layered_final_level(counts):
    """First level n that adds no signatures over level n - 1.

    sig-converge.sh keeps that level and marks it final: its signatures
    have the same partition as the level below, and each one is linked to
    the corresponding signature of the level below with sig:hasParentSignature.
    """
    for n in range(1, len(counts)):
        if counts[n] == counts[n - 1]:
            return n
    raise ValueError("counts did not converge; extend max_level")


def shape_name(family, height):
    if height == 0:
        return f"LeafShape_f{family}"
    return f"NodeShape_f{family}_h{height}"


def generate_layered(args, out):
    if args.depth < 1 or args.families < 1 or args.fanout < 1 or args.copies < 1:
        sys.exit("--depth, --families, --fanout and --copies must be >= 1")

    groups = {}  # shape IRI -> node IRIs
    lines = []

    def build(family, height, local):
        node = iri(local)
        groups.setdefault(EX + shape_name(family, height), []).append(node[1:-1])
        if height == 0:
            lines.append(triple(node, f"<{RDF_TYPE}>", iri("Leaf")))
            lines.append(triple(node, iri(f"tag{family}"), literal(local)))
            return node
        lines.append(triple(node, f"<{RDF_TYPE}>", iri("Node")))
        lines.append(triple(node, iri("label"), literal(local)))
        for k in range(args.fanout):
            child = build(family, height - 1, f"{local}.{k}")
            lines.append(triple(node, iri("child"), child))
        return node

    for family in range(args.families):
        for copy in range(args.copies):
            build(family, args.depth, f"f{family}/t{copy}/r")

    (out / "data.nt").write_text("".join(lines))
    (out / "shapes.ttl").write_text(layered_shapes(args, groups))

    counts = layered_expected_counts(args.families, args.depth, args.depth + 2)
    final_level = layered_final_level(counts)
    expected = {
        "kind": "layered",
        "params": vars_without_out(args),
        "graph": GRAPH,
        "signature_counts": counts[: final_level + 1],
        "final_level": final_level,
        "groups": groups,
    }
    (out / "expected.json").write_text(json.dumps(expected, indent=2) + "\n")
    return len(lines)


def layered_shapes(args, groups):
    out = [
        "@prefix sh: <http://www.w3.org/ns/shacl#> .\n",
        "@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .\n",
        "@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n",
        f"@prefix ex: <{EX}> .\n",
        "\n",
        f"# Shapes followed by `generate.py layered` data with families={args.families},\n",
        f"# depth={args.depth}, fanout={args.fanout}, copies={args.copies}.\n",
        "# One shape per family and node height (height 0 = leaf). Each shape is\n",
        "# closed and fixes every outgoing property, so nodes of different shapes\n",
        "# differ in structure, and a complete shape-discovery pipeline should find\n",
        "# exactly these shapes.\n",
    ]
    for family in range(args.families):
        for height in range(args.depth + 1):
            name = shape_name(family, height)
            targets = " ,\n\t\t".join(f"<{n}>" for n in groups[EX + name])
            out.append(f"\nex:{name}\n\ta sh:NodeShape ;\n\tsh:closed true ;\n")
            out.append(f"\tsh:targetNode\n\t\t{targets} ;\n")
            if height == 0:
                out.append(property_shape("rdf:type", "sh:hasValue ex:Leaf", 1))
                out.append(property_shape(f"ex:tag{family}", "sh:datatype xsd:string", 1, last=True))
            else:
                child = shape_name(family, height - 1)
                out.append(property_shape("rdf:type", "sh:hasValue ex:Node", 1))
                out.append(property_shape("ex:label", "sh:datatype xsd:string", 1))
                out.append(property_shape("ex:child", f"sh:node ex:{child}", args.fanout, last=True))
    return "".join(out)


def property_shape(path, constraint, count, last=False):
    end = " ." if last else " ;"
    return (
        f"\tsh:property [\n\t\tsh:path {path} ;\n\t\t{constraint} ;\n"
        f"\t\tsh:minCount {count} ;\n\t\tsh:maxCount {count}\n\t]{end}\n"
    )


# --------------------------------------------------------------------------
# random


def generate_random(args, out):
    if args.nodes < 1 or args.max_degree < 0:
        sys.exit("--nodes must be >= 1 and --max-degree >= 0")
    rng = random.Random(args.seed)
    types = [iri(f"T{t}") for t in range(args.types)]
    predicates = [iri(f"p{p}") for p in range(args.predicates)]
    lines = []
    for i in range(args.nodes):
        node = iri(f"n{i}")
        if types and rng.random() < 0.5:
            lines.append(triple(node, f"<{RDF_TYPE}>", rng.choice(types)))
        if rng.random() < args.literal_prob:
            lines.append(triple(node, iri("name"), literal(f"x{i}")))
        for p in predicates:
            # Skewed towards low degrees, with some above the count cap (5).
            degree = min(int(rng.expovariate(1 / 2.5)), args.max_degree, args.nodes)
            for o in rng.sample(range(args.nodes), degree):
                lines.append(triple(node, p, iri(f"n{o}")))
    (out / "data.nt").write_text("".join(lines))
    expected = {"kind": "random", "params": vars_without_out(args), "graph": GRAPH}
    (out / "expected.json").write_text(json.dumps(expected, indent=2) + "\n")
    return len(lines)


# --------------------------------------------------------------------------


def vars_without_out(args):
    return {k: v for k, v in vars(args).items() if k not in ("out", "kind")}


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0],
        epilog="See the module docstring for details on each kind of graph.",
    )
    sub = parser.add_subparsers(dest="kind", required=True)

    p = sub.add_parser("layered", help="families of trees with known SHACL shapes")
    p.add_argument("--families", type=int, default=2, help="number of families (default 2)")
    p.add_argument("--depth", type=int, default=3, help="tree depth (default 3)")
    p.add_argument("--fanout", type=int, default=2, help="children per internal node (default 2)")
    p.add_argument("--copies", type=int, default=1, help="trees per family (default 1)")

    p = sub.add_parser("random", help="unstructured random graph")
    p.add_argument("--nodes", type=int, default=80, help="number of nodes (default 80)")
    p.add_argument("--types", type=int, default=2, help="number of classes (default 2)")
    p.add_argument("--predicates", type=int, default=2, help="number of link properties (default 2)")
    p.add_argument("--max-degree", type=int, default=9, help="max out-degree per property (default 9)")
    p.add_argument("--literal-prob", type=float, default=0.5, help="chance of a literal per node (default 0.5)")
    p.add_argument("--seed", type=int, default=7, help="random seed (default 7)")

    for p in sub.choices.values():
        p.add_argument("--out", required=True, type=Path, help="output directory")

    args = parser.parse_args(argv)
    args.out.mkdir(parents=True, exist_ok=True)
    generate = generate_layered if args.kind == "layered" else generate_random
    n = generate(args, args.out)
    print(f"Wrote {n} triples to {args.out / 'data.nt'}", file=sys.stderr)


if __name__ == "__main__":
    main()
