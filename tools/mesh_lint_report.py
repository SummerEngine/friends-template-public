#!/usr/bin/env python3
"""Markdown report (and a diff against an earlier run) of the JSON that `tools/mesh_lint.gd --out=FILE` writes (stdlib only).

    python3 tools/mesh_lint_report.py build/mesh_lint.json [--md report.md] [--top 10] [--baseline earlier.json]

Without --md the Markdown goes to stdout. The report has a summary table per level (triangles, components, coplanar defects, gap and vertical warnings), then per level
and class the top offenders with their level-local position, so a fix can be found in the level at once. With --baseline the table also lists what is NEW and what was
FIXED per finding group (class + the two node paths), the same rule the tool's budget uses.
"""
import argparse
import json
import sys

SECTIONS = (
    ("coplanar", "Coplanar faces (z-fighting) - defects"),
    ("gap", "Hairline gaps between parts - warnings"),
    ("vertical", "Vertical connectivity (loose ends of pillars, legs, panels) - warnings"),
    ("overlap", "Overlaps (decorative / hazard visuals through kit parts or other visuals) - reported"),
    ("double_rim", "Double rims (two parallel rim lines on one coplanar top) - defects"),
)


def cell(text):
    return str(text).replace("|", "\\|").replace("\n", " ")


def groups_by_key(section):
    return {g["key"]: g["findings"] for g in section.get("groups", [])}


def diff_counts(section, base_section):
    """(new, fixed): findings over / under the baseline's count, per group."""
    now = groups_by_key(section)
    before = groups_by_key(base_section or {})
    new = sum(max(0, n - before.get(k, 0)) for k, n in now.items())
    fixed = sum(max(0, n - now.get(k, 0)) for k, n in before.items())
    return new, fixed


LOBBY = "99"  # the pseudo-level of `mesh_lint.sh --lobby`: the built lobby yard


def label(number):
    return "99 (lobby)" if number == LOBBY else number


def level_numbers(report):
    return sorted(report.get("levels", {}), key=int)


def render(report, top=10, baseline=None):
    out = []
    options = report.get("options", {})
    out.append("# Mesh lint report")
    out.append("")
    out.append("Tool `tools/mesh_lint.gd` (rules in its header). eps %s m, normal dot %s, min overlap %s m2, gap %s .. %s m, scopes %s, gap scopes %s." % (
        options.get("eps"), options.get("normal_dot"), options.get("min_area"), options.get("gap_min"), options.get("gap_max"),
        ",".join(options.get("scopes", [])), ",".join(options.get("gap_scopes", []))))
    skipped = {n: lvl.get("skipped_multimesh", []) for n, lvl in report.get("levels", {}).items() if lvl.get("skipped_multimesh")}
    if skipped:
        out.append("")
        out.append("**Incomplete:** the renderer of this run dropped MultiMesh transforms, so tile floors, the arena cage, skyline and clouds were NOT linted (run `tools/mesh_lint.sh` without `--headless`).")
    out.append("")
    out.append("## Summary")
    out.append("")
    header = "| level | triangles | components | seconds | coplanar defects | gap warnings | vertical warnings | overlaps | double rims |"
    rule = "|---|---|---|---|---|---|---|---|---|"
    if baseline:
        header += " new defects | fixed defects |"
        rule += "---|---|"
    out.append(header)
    out.append(rule)
    totals = [0, 0, 0, 0, 0]
    for number in level_numbers(report):
        lvl = report["levels"][number]
        row = "| %s | %d | %d | %.1f | %d | %d | %d | %d | %d |" % (label(number), lvl["triangles"], lvl["components"], lvl.get("seconds", 0.0), lvl["coplanar"]["total"], lvl["gap"]["total"], lvl["vertical"]["total"], lvl.get("overlap", {}).get("total", 0), lvl.get("double_rim", {}).get("total", 0))
        if baseline:
            base_level = baseline.get("levels", {}).get(number, {})
            new, fixed = diff_counts(lvl["coplanar"], base_level.get("coplanar"))
            row += " %d | %d |" % (new, fixed)
        out.append(row)
        totals[0] += lvl["coplanar"]["total"]
        totals[1] += lvl["gap"]["total"]
        totals[2] += lvl["vertical"]["total"]
        totals[3] += lvl.get("overlap", {}).get("total", 0)
        totals[4] += lvl.get("double_rim", {}).get("total", 0)
    out.append("| **all** | | | | %d | %d | %d | %d | %d |%s" % (totals[0], totals[1], totals[2], totals[3], totals[4], " | |" if baseline else ""))
    for number in level_numbers(report):
        lvl = report["levels"][number]
        out.append("")
        out.append("## %s" % ("Lobby (pseudo-level 99)" if number == LOBBY else "Level %s" % number))
        out.append("")
        scopes = ", ".join("%s %d" % (k, v) for k, v in sorted(lvl.get("scopes", {}).items()))
        out.append("%d triangles, %d components (%s)." % (lvl["triangles"], lvl["components"], scopes))
        for key, title in SECTIONS:
            section = lvl.get(key, {"total": 0, "groups": []})
            out.append("")
            out.append("### %s: %d findings in %d groups" % (title, section["total"], section.get("group_count", len(section["groups"]))))
            if not section["groups"]:
                out.append("")
                out.append("None.")
                continue
            out.append("")
            out.append("| class | part A | part B | findings | detail | near (level-local) | plane n, d |")
            out.append("|---|---|---|---|---|---|---|")
            for g in section["groups"][:top]:
                plane = ""
                if len(g.get("plane", [])) == 4:
                    plane = "(%.2f, %.2f, %.2f) %.3f" % tuple(g["plane"])
                near = "(%.2f, %.2f, %.2f)" % tuple(g["loc"])
                part_b = "" if g["a"] == g["b"] else cell(g["b"])
                out.append("| %s | %s | %s | %d | %s | %s | %s |" % (cell(g["cls"]), cell(g["a"]), part_b, g["findings"], cell(g["detail"]), near, plane))
            if section.get("top_pairs"):
                out.append("")
                out.append("Deepest single pairs:")
                out.append("")
                out.append("| class | part A | part B | depth cm | crossings | at (level-local) |")
                out.append("|---|---|---|---|---|---|")
                for p in section["top_pairs"][:top]:
                    out.append("| %s | %s | %s | %.1f | %d | (%.2f, %.2f, %.2f) |" % (cell(p["cls"]), cell(p["a"]), cell(p["b"]), p["depth"] * 100.0, p["hits"], *p["loc"]))
    out.append("")
    return "\n".join(out)


def merge(reports):
    """One report from the single-level runs of mesh_lint.sh (one engine process per level: a 470k-triangle level plus its predecessors does not fit one process)."""
    merged = {"tool": "mesh_lint", "version": 1, "options": reports[0].get("options", {}), "levels": {}}
    for report in reports:
        merged["levels"].update(report.get("levels", {}))
    merged["levels"] = {k: merged["levels"][k] for k in sorted(merged["levels"], key=int)}
    return merged


def totals(report):
    """(defects, warnings, overlaps, double rims) NEW against the baseline the runs were given (all of them without one)."""
    levels = report.get("levels", {}).values()
    return (sum(lvl.get("new_defects", 0) for lvl in levels), sum(lvl.get("new_warnings", 0) for lvl in levels), sum(lvl.get("new_overlaps", 0) for lvl in levels), sum(lvl.get("double_rim", {}).get("total", 0) for lvl in levels))


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] == "--merge":  # --merge OUT.json IN1.json IN2.json ...
        reports = []
        for name in argv[2:]:
            with open(name, encoding="utf-8") as handle:
                reports.append(json.load(handle))
        merged = merge(reports)
        with open(argv[1], "w", encoding="utf-8") as handle:
            json.dump(merged, handle, indent=2)
        print("MESHLINT sweep: levels %s, new defects=%d warnings=%d overlaps=%d double_rim=%d" % ((",".join(merged["levels"]),) + totals(merged)))
        return 0
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("json", help="the file written by mesh_lint.gd --out")
    parser.add_argument("--md", help="write the Markdown here (default: stdout)")
    parser.add_argument("--top", type=int, default=10, help="offenders per class and level")
    parser.add_argument("--baseline", help="an earlier JSON: list new / fixed defects")
    args = parser.parse_args(argv)
    with open(args.json, encoding="utf-8") as handle:
        report = json.load(handle)
    baseline = None
    if args.baseline:
        with open(args.baseline, encoding="utf-8") as handle:
            baseline = json.load(handle)
    text = render(report, top=args.top, baseline=baseline)
    if args.md:
        with open(args.md, "w", encoding="utf-8") as handle:
            handle.write(text)
        print("mesh_lint_report: wrote %s" % args.md)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
