"""Tests of the mesh lint (tools/mesh_lint.gd, mesh_lint.sh, mesh_lint_report.py): the report rendering and baseline diff (pure Python), and the engine side: the GDScript
self-test with synthetic known-bad and clean meshes (two coplanar quads must fail, a flush stack must pass, a 1 cm gap is found, ...) and a headless run of level 29 whose
JSON is its own baseline (python3 -m unittest discover -s tools -p 'test_*.py'; the engine tests are skipped when no Summer binary is found: SUMMER=<binary>)."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mesh_lint_report  # noqa: E402

TOOLS = Path(__file__).resolve().parent
ENGINE = Path(os.environ.get("SUMMER", "/Applications/Summer Engine.app/Contents/MacOS/Summer"))


def group(cls, a, b, findings, area=1.0, detail="x"):
    return {"key": "%s|%s|%s" % (cls, a, b), "cls": cls, "a": a + " 1x1x1 @(0.00, 0.00, 0.00)", "b": b + " 1x1x1 @(0.00, 0.00, 0.00)", "findings": findings, "pairs": findings, "area": area,
            "loc": [1.0, 2.0, 3.0], "extra": -1.0, "detail": detail, "plane": [0.0, 1.0, 0.0, 2.0], "same": False}


def section(groups):
    return {"total": sum(g["findings"] for g in groups), "pairs": 0, "groups": groups, "group_count": len(groups)}


def report(coplanar, gap=None, vertical=None, skipped=None):
    level = {"level": 29, "triangles": 100, "components": 10, "seconds": 0.5, "scopes": {"level": 10}, "coplanar": section(coplanar), "gap": section(gap or []),
             "vertical": section(vertical or []), "skipped_multimesh": skipped or []}
    return {"tool": "mesh_lint", "version": 1, "options": {"eps": 0.002, "scopes": ["level"], "gap_scopes": ["level"]}, "levels": {"29": level}}


class ReportTest(unittest.TestCase):
    def test_render_lists_levels_classes_and_locations(self):
        text = mesh_lint_report.render(report([group("zfight", "A/Floor", "A/Wall", 3)], gap=[group("gap", "A/Pillar", "A/Panel", 1)]))
        self.assertIn("| 29 | 100 | 10 | 0.5 | 3 | 1 | 0 | 0 |", text)
        self.assertIn("A/Floor 1x1x1 @(0.00, 0.00, 0.00)", text)
        self.assertIn("(1.00, 2.00, 3.00)", text)
        self.assertIn("Hairline gaps", text)
        self.assertNotIn("Incomplete", text)

    def test_render_flags_an_incomplete_run(self):
        text = mesh_lint_report.render(report([], skipped=[{"path": "ArenaWorld25/Cage/Pillars", "instances": 8}]))
        self.assertIn("Incomplete", text)

    def test_top_limits_the_rows(self):
        groups = [group("zfight", "A/%d" % i, "B/%d" % i, 1) for i in range(12)]
        text = mesh_lint_report.render(report(groups), top=4)
        self.assertEqual(text.count("| zfight |"), 4)

    def test_pipes_in_names_do_not_break_the_table(self):
        self.assertEqual(mesh_lint_report.cell("a|b"), "a\\|b")

    def test_diff_counts_new_and_fixed(self):
        before = section([group("zfight", "A", "B", 3), group("zfight", "C", "D", 2)])
        now = section([group("zfight", "A", "B", 5), group("zfight", "E", "F", 1)])
        self.assertEqual(mesh_lint_report.diff_counts(now, before), (3, 2))
        self.assertEqual(mesh_lint_report.diff_counts(now, None), (6, 0))

    def test_render_with_baseline_adds_new_and_fixed_columns(self):
        base = report([group("zfight", "A", "B", 2)])
        now = report([group("zfight", "A", "B", 1), group("zfight", "C", "D", 4)])
        text = mesh_lint_report.render(now, baseline=base)
        self.assertIn("new defects", text)
        self.assertIn("| 29 | 100 | 10 | 0.5 | 5 | 0 | 0 | 0 | 0 | 4 | 1 |", text)


@unittest.skipUnless(ENGINE.exists(), "no Summer binary (set SUMMER)")
class EngineTest(unittest.TestCase):
    def run_lint(self, *args):
        env = dict(os.environ, SUMMER=str(ENGINE))
        done = subprocess.run([str(TOOLS / "mesh_lint.sh"), "--headless", *args], capture_output=True, text=True, env=env, timeout=600)
        return done.returncode, done.stdout + done.stderr

    def test_selftest_green(self):
        code, output = self.run_lint("--selftest")
        self.assertEqual(code, 0, output)
        self.assertIn("MESHLINT selftest ok=true", output)
        self.assertIn("ok   two coplanar up-facing quads: one zfight finding", output)
        self.assertIn("ok   a flush stack is clean", output)
        self.assertNotIn("FAIL", output)

    def test_a_level_is_its_own_baseline_and_a_budget_is_honoured(self):
        with tempfile.TemporaryDirectory() as folder:
            out = str(Path(folder) / "l29.json")
            code, output = self.run_lint("--levels=29", "--out=" + out, "--budget=1000000")
            self.assertEqual(code, 0, output)
            data = json.loads(Path(out).read_text())
            self.assertEqual(list(data["levels"]), ["29"])
            self.assertGreater(data["levels"]["29"]["triangles"], 1000)
            code, output = self.run_lint("--levels=29", "--baseline=" + out)
            self.assertEqual(code, 0, output)
            self.assertIn("MESHLINT ok=true", output)
            self.assertIn("new defects 0", output)


if __name__ == "__main__":
    unittest.main()
