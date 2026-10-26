#!/usr/bin/env python3
"""Tests of the pack audit against the generated graph, with synthetic packs."""
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

import audit_staged_pack as audit
import build_domain_graph as graph
import stage_build
from test_domain_graph import BASE, make


def pack(names):
    """Minimal unencrypted PCK v4: header, file data, directory."""
    header = 112
    data, directory = b"", struct.pack("<I", len(names))
    for name in names:
        body = name.encode()
        path = ("res://" + name).encode()
        path += b"\0" * (-len(path) % 4)
        directory += struct.pack("<I", len(path)) + path + struct.pack("<QQ", len(data), len(body)) + b"\0" * 16 + struct.pack("<I", 0)
        data += body
    head = b"GDPC" + struct.pack("<IIIII", 4, 4, 7, 2, 0) + struct.pack("<QQ", header, header + len(data))
    return head + b"\0" * (header - len(head)) + data + directory


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.root = make(self.base / "project", BASE)
        make(self.root, {"assets/looks/shine.png": "png", "game/rules.gd": 'extends RefCounted\nvar s := "res" + "://assets/looks/shine.png"\n'})
        graph.prepare_clone(self.root)
        self.both, self.client_only, self.authority_only, self.presentation = audit.expectations(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def bundle(self, client, server):
        path = self.base / "bundle.zip"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("client.pck", pack(sorted(client)))
            archive.writestr("server.pck", pack(sorted(server)))
            archive.writestr("summer-bundle.json", json.dumps({"client": {"path": "client.pck"}, "server": {"path": "server.pck"}}))
        return path

    def good(self):
        client = self.both | self.client_only | self.presentation
        server = self.both | self.authority_only
        return client, server

    def test_expectations_come_from_the_graph(self):
        self.assertIn("game/rules.gd", self.both)
        self.assertIn("levels/level_01.json", self.both)
        self.assertIn("client/menu.gd", self.client_only)
        self.assertIn("audio/music/theme.wav", self.client_only)
        self.assertIn("authority/main.gd", self.authority_only)
        self.assertIn("assets/looks/shine.png", self.presentation)
        self.assertNotIn("assets/looks/shine.png", self.both)

    def test_matching_packs_pass(self):
        result = audit.audit(self.bundle(*self.good()), self.root)
        self.assertEqual(result["failures"], [])

    def test_client_payload_on_the_server_fails(self):
        client, server = self.good()
        server.add("audio/music/theme.wav")
        server.add("assets/looks/shine.png")
        failures = "\n".join(audit.audit(self.bundle(client, server), self.root)["failures"])
        self.assertIn("server: client-only files present", failures)
        self.assertIn("server: client presentation payloads present", failures)

    def test_missing_shared_file_and_authority_file_in_client_fail(self):
        client, server = self.good()
        client.discard("game/rules.gd")
        client.add("authority/main.gd")
        server.discard("authority/main.gd")
        failures = "\n".join(audit.audit(self.bundle(client, server), self.root)["failures"])
        self.assertIn("client: missing shared files", failures)
        self.assertIn("client: authority files present", failures)
        self.assertIn("server: missing authority files", failures)

    def test_probes_and_lab_fail_and_unresolved_imports_fail(self):
        client, server = self.good()
        client.add("game/x_probe.gd")
        server.add("lab/main.tscn")
        packed = self.bundle(client, server)
        failures = "\n".join(audit.audit(packed, self.root)["failures"])
        self.assertIn("probe scripts", failures)
        self.assertIn("offline test lab", failures)

    def test_stage_audit_visual_payload_rule(self):
        for path in ("a/b.png", "audio/music/x.ogg", "assets/prop_kit/a.gltf", ".godot/imported/a.png-abc.ctex"):
            self.assertTrue(stage_build.is_authority_visual_payload(path), path)
        for path in ("levels/level_01.json", "game/rules.gd", "assets/fonts/Font.ttf"):
            self.assertFalse(stage_build.is_authority_visual_payload(path), path)

    def test_pack_membership_helpers(self):
        data = pack(["a.gd", "b.gdc", "c.png.import", "d.png.remap"])
        entries = stage_build.pack_entries(data)
        self.assertTrue(stage_build.pack_has(data, entries, "res://a.gd"))
        self.assertTrue(stage_build.pack_has(data, entries, "b.gd"))
        self.assertTrue(stage_build.pack_has(data, entries, "d.png"))
        self.assertFalse(stage_build.pack_has(data, entries, "e.gd"))


if __name__ == "__main__":
    unittest.main()
