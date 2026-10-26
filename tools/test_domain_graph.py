#!/usr/bin/env python3
"""Tests of the domain graph generator on small synthetic projects."""
import json
from pathlib import Path
import tempfile
import unittest

import build_domain_graph as graph

WORLD = {"client_entry_point": "res://client/main.tscn", "source_graph": "source-domains.json",
         "components": [{"component_id": "match", "profile": "headless_engine", "runtime_descriptor": "runtime-manifest.json",
                         "entry_point": "authority/main.tscn", "owns": ["match"]}],
         "network_compositions": ["res://network/composition.tres"]}
PROJECT = ('config_version=5\n[application]\nrun/main_scene="res://main.tscn"\n'
           'run/main_scene.summer_client="res://client/main.tscn"\nrun/main_scene.summer_authority="res://authority/main.tscn"\n')
PRESETS = ('[preset.0]\n\nname="summer.games"\nplatform="summer.games"\ninclude_filter=""\nexclude_filter=""\n\n[preset.0.options]\n\n'
           '[preset.1]\n\nname="Authority"\nplatform="Linux"\ninclude_filter=""\nexclude_filter=""\n\n[preset.1.options]\n\nbinary=1\n')
BASE = {
    "world.json": json.dumps(WORLD), "project.godot": PROJECT, "export_presets.cfg": PRESETS,
    "summer.build.json": json.dumps({"server": {"exportPreset": "Authority"}}), "runtime-manifest.json": "{}",
    "network/composition.tres": '[gd_resource type="Resource" format=3]\n[ext_resource type="Script" path="res://network/game.gd" id="1"]\n',
    "network/game.gd": 'extends RefCounted\nconst Rules := preload("res://game/rules.gd")\n',
    "game/rules.gd": 'extends RefCounted\nfunc levels() -> String:\n\treturn load("res" + "://levels/level_%02d.json" % 1)\n',
    "levels/level_01.json": '{"k": 1}', "levels/level_02.json": '{"k": 2}',
    "authority/main.tscn": '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://authority/main.gd" id="1"]\n',
    "authority/main.gd": 'extends Node\nconst Game := preload("res://network/game.gd")\n',
    "client/main.tscn": '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://client/main.gd" id="1"]\n',
    "client/main.gd": 'extends Node\nconst Rules := preload("res://game/rules.gd")\nconst Menu := preload("res://client/menu.gd")\n',
    "client/menu.gd": 'extends Node\nvar art := "res" + "://client/menu_art/back.png"\nconst Look := preload("res://style/look.gdshader")\n',
    "client/menu_art/back.png": "png", "client/menu_art/back.png.import": 'uid="uid://aaa"\n',
    "style/look.gdshader": 'shader_type canvas_item;\n#include "res://style/common.gdshaderinc"\n', "style/common.gdshaderinc": "// shared",
    "main.tscn": '[gd_scene]\n[ext_resource type="Script" path="res://client/main.gd" id="1"]\n',
    "audio/music/theme.wav": "wav", "audio/sfx/mix.json": "{}",
    "assets/fonts/Font.ttf": "ttf", "assets/fonts/font-OFL.txt": "licence",
    "tools_leftover/probe.gd": 'extends Node\n', "notes.md": "text",
}


def make(root, files):
    for name, text in files.items():
        path = Path(root, name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    return Path(root)


class ComputedLoadTests(unittest.TestCase):
    def test_same_rule_as_the_analyzer(self):
        self.assertTrue(graph.has_computed_load('var a = load(PATH)', 'load'))
        self.assertTrue(graph.has_computed_load('x = preload( CONST )', 'preload'))
        self.assertTrue(graph.has_computed_load('ResourceLoader.load(p)', 'load'))
        self.assertFalse(graph.has_computed_load('load("res://a.gd")', 'load'))
        self.assertFalse(graph.has_computed_load('load("res" + "://a/" + name)', 'load'))  # starts with a quote
        self.assertFalse(graph.has_computed_load('player_data.load(session); upload(x); get_payload(y)', 'load'))
        self.assertFalse(graph.has_computed_load('var x = reload(a)', 'load'))


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = make(self.temp.name, BASE)

    def tearDown(self):
        self.temp.cleanup()

    def plan(self):
        return graph.build_plan(self.root)

    def test_roles_follow_the_entries(self):
        plan = self.plan()
        self.assertEqual(plan.errors, [])
        self.assertEqual(plan.role["authority/main.gd"], "authority")
        for shared in ("network/game.gd", "network/composition.tres", "game/rules.gd", "levels/level_01.json", "levels/level_02.json",
                       "assets/fonts/Font.ttf"):
            self.assertEqual(plan.role[shared], "shared", shared)
        for client in ("client/main.gd", "client/menu.gd", "main.tscn", "style/look.gdshader", "style/common.gdshaderinc",
                       "client/menu_art/back.png", "audio/music/theme.wav", "audio/sfx/mix.json"):
            self.assertEqual(plan.role[client], "client", client)
        self.assertEqual(plan.role["client/menu_art/back.png.import"], "client")
        self.assertIn("tools_leftover/probe.gd", plan.unreached)
        self.assertIn("notes.md", plan.unreached)

    def test_soft_token_classes(self):
        # data named by authority-side code is shared, presentation files are client-only and noted
        self.root.joinpath("game/rules.gd").write_text(
            'extends RefCounted\nvar a := "res" + "://levels/level_"\nvar b := "res" + "://game/skin.png"\nvar c := "res" + "://game/notes.json"\n')
        make(self.root, {"game/skin.png": "png", "game/notes.json": "{}"})
        plan = self.plan()
        self.assertEqual(plan.role["game/notes.json"], "shared")
        self.assertEqual(plan.role["game/skin.png"], "client")
        self.assertEqual(plan.role["levels/level_02.json"], "shared")
        self.assertTrue(any("skin.png" in note for note in plan.notes) or any("game/skin" in note for note in plan.notes))

    def test_hard_token_problems_are_reported(self):
        make(self.root, {"game/bad.gd": '# see res://missing/file.gd\nvar d := preload("res://levels")\n'})
        self.root.joinpath("game/rules.gd").write_text('extends RefCounted\nconst B := preload("res://game/bad.gd")\n')
        plan = self.plan()
        joined = "\n".join(plan.errors)
        self.assertIn("res://missing/file.gd is a missing file", joined)
        self.assertIn("res://levels is a directory", joined)

    def test_authority_cannot_name_client_payloads_or_preload_visuals(self):
        make(self.root, {"game/bad.gd": 'var a := "res://audio/sfx/mix.json"\nconst T := preload("res://assets/looks/x.png")\n',
                         "assets/looks/x.png": "png"})
        self.root.joinpath("game/rules.gd").write_text('extends RefCounted\nconst B := preload("res://game/bad.gd")\n')
        errors = "\n".join(self.plan().errors)
        self.assertIn("names client-only payload res://audio/sfx/mix.json", errors)
        self.assertIn("preloads res://assets/looks/x.png, which the authority pack leaves out", errors)

    def test_client_cannot_reach_authority_files(self):
        self.root.joinpath("client/menu.gd").write_text('extends Node\nconst A := preload("res://authority/main.gd")\n')
        self.assertIn("client file reaches authority file", "\n".join(self.plan().errors))

    def test_computed_loads_get_manifest_edges(self):
        make(self.root, {"client/menu.gd": 'extends Node\nvar p := ART\nfunc f(): return load(p)\n'})
        edges = graph.edges(self.plan())
        self.assertIn({"from": "client/menu.gd", "to": graph.CLIENT_MANIFEST}, edges)
        self.assertIn({"from": "client/menu.gd", "to": graph.SHARED_MANIFEST}, edges)
        self.assertNotIn("game/rules.gd", {e["from"] for e in edges})  # its load starts with a quote

    def test_rows_collapse_whole_directories(self):
        plan = self.plan()
        for name in graph.MANIFESTS:
            plan.files.add(name)
        rows = graph.rows(plan)
        self.assertIn("levels", rows["shared"])
        self.assertIn("assets/fonts", rows["shared"])
        self.assertIn("network", rows["shared"])
        self.assertIn("audio", rows["client"])  # music and sfx are both client-only: one root
        self.assertIn("client", rows["client"])
        self.assertIn("authority", rows["authority"])
        self.assertIn("runtime-manifest.json", rows["authority"])
        self.assertNotIn("tools_leftover", " ".join(rows["shared"] + rows["client"]))

    def test_directory_with_unreached_code_is_listed_by_file(self):
        make(self.root, {"game/stray.gd": 'extends Node\n'})
        plan = self.plan()
        self.assertIn("game/stray.gd", plan.unreached)
        rows = graph.rows(plan)
        self.assertNotIn("game", rows["shared"])
        self.assertIn("game/rules.gd", rows["shared"])

    def test_global_class_names_and_uids_are_references(self):
        make(self.root, {"flags/flag.gd": 'class_name FeatureFlag\nstatic func on() -> bool:\n\treturn true\n',
                         "flags/talk.gd": 'class_name FeatureTalk\n# FeatureFlag is only named in this comment\n',
                         "game/uses.gd": 'extends RefCounted\nvar t := FeatureFlag.on()\nvar u = preload("uid://lamp1")\n',
                         "game/lamp.tres": '[gd_resource type="Resource" format=3 uid="uid://lamp1"]\n',
                         "game/rules.gd": 'extends RefCounted\nconst U := preload("res://game/uses.gd")\n'})
        plan = self.plan()
        self.assertEqual(plan.errors, [])
        self.assertEqual(plan.role["flags/flag.gd"], "shared")
        self.assertEqual(plan.role["game/lamp.tres"], "shared")
        self.assertIn("flags/talk.gd", plan.unreached)


class GenerateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = make(self.temp.name, BASE)

    def tearDown(self):
        self.temp.cleanup()

    def test_prepare_clone_prunes_and_writes_a_valid_graph(self):
        make(self.root, {"assets/prop_kit/bench.gltf": "{}", "assets/prop_kit/tree.gltf": "{}", "assets/prop_kit/bench.bin": "b",
                         "assets/prop_kit/tree.bin": "b", "assets/prop_kit/kit_texture.png": "png",
                         "game/rules.gd": 'extends RefCounted\nconst M := "res" + "://assets/prop_kit/"\nvar n := "bench"\nfunc f(): return load(M + n)\n'})
        report = graph.prepare_clone(self.root)
        self.assertEqual(report["pruned"]["kit_files"], 2)
        self.assertFalse((self.root / "assets/prop_kit/tree.gltf").exists())
        self.assertTrue((self.root / "assets/prop_kit/bench.gltf").exists())
        self.assertFalse((self.root / "tools_leftover").exists())
        self.assertFalse((self.root / "notes.md").exists())
        document = json.loads((self.root / graph.GRAPH_FILE).read_text())
        self.assertEqual(document["schema"], graph.GRAPH_SCHEMA)
        self.assertEqual({row["domain"] for row in document["roots"]}, {"shared", "client", "authority_engine"})
        self.assertIn({"from": "game/rules.gd", "to": graph.SHARED_MANIFEST}, document["dependencies"])
        shared = json.loads((self.root / graph.SHARED_MANIFEST).read_text())["resources"]
        self.assertIn("res://levels/level_01.json", shared)
        authority = json.loads((self.root / graph.AUTHORITY_MANIFEST).read_text())["resources"]
        self.assertIn("res://levels/level_01.json", authority)
        self.assertFalse([r for r in authority if r.endswith((".png", ".gltf", ".wav"))])
        self.assertFalse([r for r in authority if "prop_kit" in r])
        client = json.loads((self.root / graph.CLIENT_MANIFEST).read_text())["resources"]
        self.assertIn("res://audio/music/theme.wav", client)
        # a graph never lists a path twice across domains
        owned = graph.expand(self.root, document)
        self.assertFalse(owned["shared"] & owned["client"])
        self.assertFalse(owned["shared"] & owned["authority_engine"])
        self.assertFalse(owned["client"] & owned["authority_engine"])

    def test_presets_follow_the_roles(self):
        graph.prepare_clone(self.root)
        text = (self.root / "export_presets.cfg").read_text()
        client, authority = text.split("[preset.1]")
        self.assertIn('include_filter="*.json,assets/fonts/*-OFL.txt"', client)
        self.assertIn("authority/*", client)
        include = next(line for line in authority.splitlines() if line.startswith("include_filter="))
        exclude = next(line for line in authority.splitlines() if line.startswith("exclude_filter="))
        self.assertIn("levels/*.json", include)
        self.assertIn("runtime-manifest.json", include)
        for pattern in ("client/*", "audio/*", "*.png", "*.wav", "main.tscn", graph.SHARED_MANIFEST, "lab/*"):
            self.assertIn(pattern, exclude)
        self.assertNotIn("network/", exclude)
        self.assertNotIn("levels", exclude)
        # applying twice changes nothing
        before = text
        graph.generate(self.root)
        self.assertEqual(before, (self.root / "export_presets.cfg").read_text())

    def test_extra_client_entry_keeps_its_files(self):
        make(self.root, {"lab/main.tscn": '[gd_scene]\n[ext_resource type="Script" path="res://lab/lab.gd" id="1"]\n',
                         "lab/lab.gd": 'extends Node\nconst R := preload("res://game/rules.gd")\n'})
        plan = graph.build_plan(self.root, client_entries=["lab/main.tscn"])
        self.assertEqual(plan.role["lab/lab.gd"], "client")
        self.assertEqual(plan.role["game/rules.gd"], "shared")

    def test_row_limit_is_enforced(self):
        files = {f"game/g{i}.gd": "extends Node\n" for i in range(140)}
        files["game/rules.gd"] = "extends RefCounted\n" + "".join(f'const C{i} := preload("res://game/g{i}.gd")\n' for i in range(140))
        files["game/stray.gd"] = "extends Node\n"  # keeps `game` from collapsing
        make(self.root, files)
        with self.assertRaisesRegex(graph.GraphError, "row has"):
            graph.generate(self.root)

    def test_missing_entry_is_an_error(self):
        (self.root / "authority/main.tscn").unlink()
        with self.assertRaisesRegex(graph.GraphError, "entry file missing"):
            graph.generate(self.root)

    def test_import_uids_become_uid_owners(self):
        (self.root / "assets/fonts/Font.ttf.import").write_text('[remap]\nuid="uid://font1"\n')
        graph.generate(self.root)
        self.assertEqual((self.root / "assets/fonts/Font.ttf.uid").read_text().strip(), "uid://font1")


if __name__ == "__main__":
    unittest.main()
