"""Unit tests for tools/clean_scan.py word matching (python3 -m unittest discover -s tools -p 'test_*.py').

The real word list is fingerprinted, so these tests add a made-up word to the tables and check how it is found."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import clean_scan  # noqa: E402


class WordMatchTest(unittest.TestCase):
    def setUp(self):
        self.joined = {k: dict(v) for k, v in clean_scan.JOINED.items()}
        self.prefix = {k: dict(v) for k, v in clean_scan.PREFIX.items()}
        word, stem = b"zorbleflux", b"quaxim"
        clean_scan.JOINED.setdefault(len(word), {})[clean_scan.fingerprint(word)] = "rule test-joined"
        clean_scan.PREFIX.setdefault(len(stem), {})[clean_scan.fingerprint(stem)] = "rule test-prefix"

    def tearDown(self):
        clean_scan.JOINED.clear()
        clean_scan.JOINED.update(self.joined)
        clean_scan.PREFIX.clear()
        clean_scan.PREFIX.update(self.prefix)

    def rules(self, text):
        hits = []
        clean_scan.scan_bytes(text.encode(), "t", hits)
        return {rule for _, rule, _ in hits}

    def test_joined_word_in_every_spelling(self):
        for text in ("zorble flux", "zorble_flux", "Zorble-Flux", "ZorbleFlux", "a zorbleflux b"):
            self.assertIn("rule test-joined", self.rules(text), text)

    def test_joined_word_needs_whole_tokens(self):
        for text in ("zorblefluxes", "xzorble flux", "zorble"):
            self.assertNotIn("rule test-joined", self.rules(text), text)

    def test_prefix_matches_token_beginnings(self):
        self.assertIn("rule test-prefix", self.rules("Quaximal mode"))
        self.assertNotIn("rule test-prefix", self.rules("the quaxi mode"))

    def test_one_hit_per_rule_per_file(self):
        hits = []
        clean_scan.scan_bytes(b"zorbleflux zorble_flux ZorbleFlux", "t", hits)
        self.assertEqual(1, len(hits))

    def test_joins_need_real_words(self):
        clean_scan.JOINED.setdefault(3, {})[clean_scan.fingerprint(b"qzk")] = "rule test-short"
        self.assertNotIn("rule test-short", self.rules("q*zk"))
        self.assertIn("rule test-short", self.rules("a qzk b"))

    def test_binary_skips_short_single_words(self):
        clean_scan.JOINED.setdefault(3, {})[clean_scan.fingerprint(b"qzk")] = "rule test-short"
        hits = []
        clean_scan.scan_bytes(b"\x00\x01noise qzk noise\x02", "t", hits, strings_only=True)
        self.assertEqual([], [h for h in hits if h[1] == "rule test-short"])
        hits = []
        clean_scan.scan_bytes(b"\x00\x01noise zorbleflux noise\x02", "t", hits, strings_only=True)
        self.assertEqual(["rule test-joined"], [h[1] for h in hits])

    def test_cast_text_may_use_ordinary_words(self):
        clean_scan.JOINED[len(b"zorbleflux")][clean_scan.fingerprint(b"zorbleflux")] = "rule 11"  # an ordinary-English rule
        for cast_text, expected in ((False, ["rule 11", "rule test-prefix"]), (True, ["rule test-prefix"])):
            hits = []
            clean_scan.scan_bytes(b'{"title": "THE ZORBLEFLUX FROG", "egg": "quaximal"}', "t", hits, cast_text=cast_text)
            self.assertEqual(expected, sorted(h[1] for h in hits))
        self.assertTrue(clean_scan.is_cast_text("res://cast/cast.json") and clean_scan.is_cast_text("demo/cast/cast.json"))
        self.assertFalse(clean_scan.is_cast_text("demo/levels/level_1.json"))

    def test_clean_text_has_no_hits(self):
        self.assertEqual(set(), self.rules("Two players carry a painting; three keep a balloon in the air."))


if __name__ == "__main__":
    unittest.main()
