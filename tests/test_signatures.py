"""End-to-end tests of the signature pipeline, run with Apache Jena.

Run from the repository root:

    python3 -m unittest discover -s tests -v

The Jena command-line tools (tdb2.tdbloader, tdb2.tdbupdate, tdb2.tdbquery,
shacl) must be on the PATH, or JENA_HOME must point to a Jena distribution;
otherwise every test is skipped (or, with REQUIRE_JENA=1, the run fails,
as in CI). Set UPDATE_SNAPSHOTS=1 to rewrite the
snapshot in tests/expected/ instead of comparing against it (check the diff!).

Each test case builds a TDB2 store in a temporary directory, runs the real
updates and scripts against it, and checks the results with the queries in
queries/ and tests/queries/.
"""

import csv
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TESTS = REPO / "tests"
GRAPH = "http://example.org/synthetic/graph"


def find_jena_bin():
    home = os.environ.get("JENA_HOME")
    if home and (Path(home) / "bin" / "tdb2.tdbquery").exists():
        return str(Path(home) / "bin")
    found = shutil.which("tdb2.tdbquery")
    return str(Path(found).parent) if found else None


JENA_BIN = find_jena_bin()
if JENA_BIN is None and os.environ.get("REQUIRE_JENA"):
    raise RuntimeError("REQUIRE_JENA is set but Apache Jena was not found (set JENA_HOME or PATH)")


@unittest.skipIf(JENA_BIN is None, "Apache Jena not found (set JENA_HOME or PATH)")
class PipelineTestCase(unittest.TestCase):
    """Base class: a TDB2 store in a temp dir and helpers to run Jena on it."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="deep-shapes-test-"))
        cls.loc = cls.tmp / "tdb2"
        cls.env = dict(os.environ)
        cls.env["PATH"] = JENA_BIN + os.pathsep + cls.env.get("PATH", "")
        cls.env.setdefault("JVM_ARGS", "-Xmx2G")
        cls.env["TDB_ARGS"] = f"--loc={cls.loc} --set=tdb:unionDefaultGraph=true"

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    @classmethod
    def run_cmd(cls, *args, check=True):
        result = subprocess.run(
            list(args), cwd=REPO, env=cls.env, capture_output=True, text=True
        )
        if check and result.returncode != 0:
            raise AssertionError(
                f"{' '.join(map(str, args))} exited with {result.returncode}:\n"
                f"{result.stdout}\n{result.stderr}"
            )
        return result

    @classmethod
    def generate(cls, *args):
        cls.data_dir = cls.tmp / "data"
        cls.run_cmd(sys.executable, TESTS / "generate.py", *args, "--out", cls.data_dir)
        cls.expected = json.loads((cls.data_dir / "expected.json").read_text())
        cls.load(cls.data_dir / "data.nt")

    @classmethod
    def load(cls, path):
        cls.run_cmd("tdb2.tdbloader", f"--loc={cls.loc}", f"--graph={GRAPH}", path)

    @classmethod
    def update(cls, name):
        cls.run_cmd(
            "tdb2.tdbupdate", f"--loc={cls.loc}", "--set=tdb:unionDefaultGraph=true",
            "--update", REPO / "updates" / name,
        )

    @classmethod
    def converge(cls, *args, check=True):
        return cls.run_cmd(REPO / "scripts" / "sig-converge.sh", *args, check=check)

    @classmethod
    def query(cls, path):
        """Run a query file and return its rows as a list of dicts."""
        result = cls.run_cmd(
            "tdb2.tdbquery", f"--loc={cls.loc}", "--set=tdb:unionDefaultGraph=true",
            "--results=csv", "--query", path,
        )
        return list(csv.DictReader(io.StringIO(result.stdout)))

    @classmethod
    def convergence(cls):
        return cls.query(REPO / "queries" / "convergence.rq")


class InvariantChecks:
    """Checks that must hold for any graph once sig-converge.sh has run."""

    def test_no_duplicate_signatures(self):
        self.assertEqual(self.query(TESTS / "queries" / "duplicates.rq"), [])

    def test_duplicate_shapes_query_is_empty(self):
        self.assertEqual(self.query(REPO / "queries" / "duplicate-shapes.rq"), [])

    def test_each_level_refines_the_previous_one(self):
        self.assertEqual(self.query(TESTS / "queries" / "refinement.rq"), [])

    def test_parent_and_final_target_links(self):
        self.assertEqual(self.query(TESTS / "queries" / "structure-links.rq"), [])

    def test_counts_increase_and_last_level_is_final(self):
        rows = self.convergence()
        counts = [int(r["signatures"]) for r in rows]
        # Every level adds signatures, except the last (final) one, which has
        # as many as the level below it.
        self.assertGreaterEqual(len(counts), 2, f"counts: {counts}")
        self.assertEqual(counts[:-1], sorted(set(counts[:-1])), f"counts: {counts}")
        self.assertEqual(counts[-1], counts[-2], f"counts: {counts}")
        self.assertEqual([r["final"] for r in rows], ["false"] * (len(rows) - 1) + ["true"])

    def test_rerun_after_convergence_does_nothing(self):
        before = self.convergence()
        result = self.converge()
        self.assertIn("Already converged", result.stdout)
        self.assertEqual(self.convergence(), before)


class LayeredChecks(InvariantChecks):
    """Extra checks for `generate.py layered` graphs, which have a known answer."""

    def test_signature_counts_per_level(self):
        counts = [int(r["signatures"]) for r in self.convergence()]
        self.assertEqual(counts, self.expected["signature_counts"])

    def test_final_level(self):
        final = [int(r["level_value"]) for r in self.convergence() if r["final"] == "true"]
        self.assertEqual(final, [self.expected["final_level"]])

    def test_data_conforms_to_generated_shapes(self):
        result = self.run_cmd(
            "shacl", "validate",
            "--shapes", self.data_dir / "shapes.ttl",
            "--data", self.data_dir / "data.nt",
        )
        self.assertRegex(result.stdout, r"sh:conforms\s+true")

    def test_final_signatures_match_shapes(self):
        """Same SHACL shape <=> same signature at the final level."""
        signature = {
            r["i"]: r["sig"] for r in self.query(TESTS / "queries" / "last-level-signatures.rq")
        }
        shape_of_signature = {}
        for shape, nodes in self.expected["groups"].items():
            sigs = {signature[n] for n in nodes}
            self.assertEqual(len(sigs), 1, f"nodes of {shape} have different signatures")
            sig = sigs.pop()
            self.assertNotIn(
                sig, shape_of_signature,
                f"{shape} and {shape_of_signature.get(sig)} share a signature",
            )
            shape_of_signature[sig] = shape


class LayeredTest(LayeredChecks, PipelineTestCase):
    """Two families of binary trees of depth 4, two copies each."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.generate("layered", "--families", "2", "--depth", "4", "--fanout", "2", "--copies", "2")
        cls.converge()


class LayeredCappedCountsTest(LayeredChecks, PipelineTestCase):
    """Three families with fan-out 7, so link counts are capped ('n')."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.generate("layered", "--families", "3", "--depth", "2", "--fanout", "7")
        cls.converge()


class ChainTest(LayeredChecks, PipelineTestCase):
    """A single chain of depth 6: one more signature per level.

    Built in two runs (stopped by --max-levels, then resumed) to test that
    sig-converge.sh picks up where it left off.
    """

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.generate("layered", "--families", "1", "--depth", "6", "--fanout", "1")
        cls.first_run = cls.converge("--max-levels", "2", check=False)
        cls.counts_after_first_run = [int(r["signatures"]) for r in cls.convergence()]
        cls.converge()

    def test_max_levels_stops_early(self):
        self.assertEqual(self.first_run.returncode, 2, self.first_run.stdout)
        self.assertEqual(self.counts_after_first_run, self.expected["signature_counts"][:3])


class RandomTest(InvariantChecks, PipelineTestCase):
    """Unstructured graph with cycles and link counts above the cap."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.generate("random", "--nodes", "80", "--max-degree", "9", "--seed", "7")
        cls.converge()


class RestartTest(PipelineTestCase):
    """--restart recomputes everything from level 0 with the same result."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.generate("layered", "--families", "2", "--depth", "2")
        cls.converge()
        cls.first = cls.query(TESTS / "queries" / "all-signatures.rq")
        cls.restart = cls.converge("--restart")
        cls.second = cls.query(TESTS / "queries" / "all-signatures.rq")

    def test_restart_starts_from_level_0(self):
        self.assertIn("Computing level 0", self.restart.stdout)

    def test_restart_gives_the_same_signatures(self):
        self.assertEqual(self.first, self.second)


class SnapshotTest(PipelineTestCase):
    """Exact ids on a small graph for levels 0-2, against a stored snapshot.

    Levels are computed with the updates directly (not sig-converge.sh), so
    level 2, the first one with hashed references, is kept even though the
    partition converges earlier.
    """

    snapshot = TESTS / "expected" / "people-signatures.tsv"

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.load(TESTS / "data" / "people.ttl")
        cls.update("signatures-base.ru")
        cls.update("signatures-rec.ru")
        cls.update("signatures-rec.ru")
        cls.rows = cls.query(TESTS / "queries" / "all-signatures.rq")

    def test_ids_match_snapshot(self):
        text = "".join(f"{r['i']}\t{r['level_value']}\t{r['id']}\n" for r in self.rows)
        if os.environ.get("UPDATE_SNAPSHOTS"):
            self.snapshot.write_text(text)
            self.skipTest(f"snapshot written to {self.snapshot}")
        self.assertEqual(text, self.snapshot.read_text())

    def test_one_signature_per_resource_and_level(self):
        self.assertEqual(self.query(TESTS / "queries" / "duplicates.rq"), [])

    def test_level_2_references_are_hashes(self):
        import re
        for r in self.rows:
            if r["level_value"] == "2":
                for ref in re.findall(r"\[([^\]]*)\]", r["id"]):
                    self.assertRegex(ref, r"^#[0-9a-f]{40}$", r["id"])


if __name__ == "__main__":
    unittest.main()
