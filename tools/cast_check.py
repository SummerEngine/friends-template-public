#!/usr/bin/env python3
"""The one check an agent runs after editing the team cast. Exit 0 = the game can be built from this cast.

    python3 tools/cast_check.py            # validate demo/cast/cast.json
    python3 tools/cast_check.py --lock     # optional: record the project as it is now, so later changes outside demo/cast/ fail

Two parts:
1. Cast: demo/cast/cast.json is a valid team-cast-v2 file (docs/slots.md; a team-cast-v1 file is still accepted): every field,
   lengths, colours, letters the comic font has, the fixed file names, and every named file (pictures, voice clips, videos) is
   there, in the right format and size; so is every file of the team pack (announcer/, voice/, team/). demo/cast/prepared/, when
   it exists, is what tools/cast_prep.py wrote (docs/build-tooling.md): its manifest matches the pictures it was made from and every prepared
   picture is a valid PNG. No text reads like an
   ad (links, prices, calls to action: the only link is team.credit_link on the results screen) or carries a name this
   project must not use (tools/clean_scan.py).
2. Guard (optional, off by default): when tools/locked_files.json exists (written by --lock), every file outside demo/cast/
   must match it byte for byte. The public template ships without a lock: change anything you like.
"""
import argparse
import fnmatch
import hashlib
import json
import math
import re
import struct
import sys
import zlib
from pathlib import Path

import cast_fonts

ROOT = Path(__file__).resolve().parents[1]
CAST_DIR = "demo/cast/"
CAST_FILE = ROOT / CAST_DIR / "cast.json"
MUSIC_DIR = ROOT / "demo/audio/music"
CATALOG_FILE = ROOT / "demo/character/catalog.json"
MODES_FILE = ROOT / "demo/modes/modes.json"
LOCK_FILE = ROOT / "tools/locked_files.json"
LOCK_FORMAT = "locked-files-v1"
# Not part of the template: VCS, engine and editor state, build output.
ALWAYS_SKIPPED_DIRS = {".git", ".godot", ".summer", "build", "analysis", "__pycache__", ".claude"}
ALWAYS_SKIPPED_NAMES = {".DS_Store"}

FORMAT = "team-cast-v2"
FORMAT_V1 = "team-cast-v1"
OBJECT_KINDS = ("landscape", "portrait", "glass")
PICTURE_FITS = ("contain", "cover")
THEMES = ("office", "outdoor")
WORLD_STYLES = ("party", "night", "auto")  # first = the default
BRAND_WALLS = ("auto", "stripe", "accent", "full")  # first = the default
BALLOON_SHAPES = ("balloon", "blimp", "ball")
PICTURE_SUFFIXES = (".png", ".jpg", ".jpeg", ".webp")
MAX_PICTURE_BYTES = 4 * 1024 * 1024
# tools/cast_prep.py: demo/cast/prepared/manifest.json and one PNG per keyed picture, named after the source's stem.
PREPARED_DIR = "prepared"
PREPARED_FORMAT = "cast-prep-v1"
PREPARED_RESULTS = ("keyed", "transparent", "busy", "empty")
PREPARED_FIELDS = {"sha256", "result", "background", "size"}
MIN_PICTURE_SIDE = 256
# Sound clips (player voices and the announcer): Ogg Vorbis, mono, short, small.
MAX_CLIP_BYTES = 300 * 1024
MAX_CLIP_SECONDS = 4.0
# The team pack (docs/slots.md): files found by their fixed names.
ANNOUNCER_EVENTS = ("start", "near_drop", "break", "pop", "zap", "goal", "perfect")
ANNOUNCER_VARIANTS = 4
VOICE_VARIANTS = 3
MAX_TEAM_WALL = 10
MAX_PHOTO_BYTES = 1024 * 1024
PHOTO_SIDE = (256, 1024)  # square, 512 x 512 is the size the pack makes
MAX_VIDEO_BYTES = 16 * 1024 * 1024
MAX_PLAYERS = 8
MAX_OBSTACLES = 5
MAX_POSTERS = 3
MAX_EGGS = 5
MAX_BRAND_COLORS = 3
# The title screen's own art (docs/slots.md): demo/cast/title_backdrop.<ending>, found by its name; landscape, at least
# 1280 x 720 px (1536 x 1024 is the size the template's art has). title.pet_ground says where the title pet stands on it.
TITLE_BACKDROP = "title_backdrop"
TITLE_BACKDROP_MIN = (1280, 720)
WORDS = ("delivered", "break", "fall", "pop", "zap", "burnt")
# The show (mode "show", docs/slots.md): the lines of its moments, banner / billboard pictures and an own crown model, all optional.
SHOW_WORDS = ("qualified", "eliminated", "champion", "go")
SLOT_PICTURES = ("banner_1", "banner_2", "billboard_1", "billboard_2")  # demo/cast/<name>.png (.jpg, .webp)
CROWN_FILE = "crown.glb"
MAX_CROWN_BYTES = 5 * 1024 * 1024
# The hero prop (docs/hero-prop.md): demo/cast/hero_prop.glb, the stand the crown floats over. The game fits any model into a box of
# HERO_BOX (footprint, height in metres) and its collision is three stacked cylinders: the model's tiers keep inside them.
HERO_PROP_FILE = "hero_prop.glb"
MAX_HERO_PROP_BYTES = 5 * 1024 * 1024
HERO_BOX = (4.5, 3.0)
HERO_TIER_RADII = tuple(HERO_BOX[0] / 2 * share for share in (1.0, 2.0 / 3.0, 1.0 / 3.0))
HERO_SLACK = (1.04, 0.03)  # a vertex may stand this far out of its tier: radius * 1.04 + 0.03 m
# Rounds as metaphors (docs/swappables.md): show.rounds.<round id> renames a round and dresses its hazard. The round id is r<file number of the
# round's first show level> (demo/levels/level_<n>.json; POSTER RUSH is levels 17 and 20 = r17). Which keys each round takes, as the game's
# TeamCast.ROUND_KEYS: title, rule and hint for every round, label for the rounds with a hazard that wears words, model (round_<id>.glb) for two.
ROUND_NAMES = {"r14": "CIRCUIT BREAKER", "r15": "LAST TILE STANDING", "r16": "CROWN CLIMB", "r17": "POSTER RUSH", "r18": "PICTURE MATCH",
               "r19": "BOUNCE HOUSE", "r21": "SPIN BARS", "r22": "SHOVE RING", "r23": "ROLLING ROAD", "r24": "KEEP THE LOGO",
               "r25": "SQUARE STACK A", "r26": "HEX STACK A", "r27": "SQUARE STACK B", "r28": "HEX STACK B", "r29": "ROOFTOP RUN", "r30": "FERRY CROSSING", "r31": "SPINNER GARDEN", "r32": "GATE RUSH"}
ROUND_TEXT_KEYS = ("title", "rule", "hint")
ROUND_LABEL_IDS = ("r15", "r17", "r21", "r23")
ROUND_MODEL_IDS = ("r21", "r23")
ROUND_KEYS = {round_id: ROUND_TEXT_KEYS + (("label",) if round_id in ROUND_LABEL_IDS else ()) + (("model",) if round_id in ROUND_MODEL_IDS else ())
              for round_id in ROUND_NAMES}
MAX_LABELS = 8
MAX_ROUND_MODEL_BYTES = 5 * 1024 * 1024
# Items and events of the race rounds (docs/items.md): show.items[] = {id, name, banner, line, pass, pop (the eggplant only), off, voice, sfx, media, tuning}; the ids, the tuning keys and their
# ranges are the template's demo/modes/show/items/items.json, the files are demo/cast/items/<file>. Item words are jokes about a made-up business, so the price
# and "subscribe" patterns of the ad filter do not apply to them; links and calls to action still do.
ITEMS_FILE = ROOT / "demo" / "modes" / "show" / "items" / "items.json"
# GHOST PIGEON (docs/pigeon.md): show.pigeon = {off, banner, coo, splat, line, drop_line, tuning}; the defaults, tuning keys and ranges are the template's demo/modes/show/shared/pigeon/pigeon.json.
PIGEON_FILE = ROOT / "demo" / "modes" / "show" / "shared" / "pigeon" / "pigeon.json"
ITEM_DIR = "items"
# THE MANAGER (experiment, docs/party-show.md): show.manager = {off, title, line, you, prompt, waiting, made, rules: [{id, name, banner, line, off, tuning}]}; the rule ids and the defaults
# are the template's demo/modes/show/shared/manager/manager.json. The words are team jokes about the made-up business, like the items'.
MANAGER_FILE = ROOT / "demo" / "modes" / "show" / "shared" / "manager" / "manager.json"
MANAGER_TEXTS = ("title", "line", "you", "prompt", "waiting", "made")
MANAGER_DURATION = (3.0, 30.0)
ITEM_ADVERT_JOKES = re.compile(r"[$€£¥]\s?\d|\d\s?(?:[$€£¥]|usd|eur|gbp)\b|\bsubscribe\b", re.I)
# (section, key) -> max characters. The wordmark and the comic words are drawn at a size that fits their length,
# so these limits are about readability on a phone, not about overflow.
LIMITS = {"team.name": 18, "team.tagline": 60, "player.name": 12, "player.catchphrase": 60, "word": 16, "obstacle.label": 16,
          "poster.caption": 24, "egg": 60, "look": 16, "reveal": 40, "team_wall.name": 16, "team.title": 40, "player.title": 16,
          "show.word": 16, "round.title": 24, "round.line": 48, "round.label": 16, "item.name": 16, "item.banner": 30, "item.line": 48, "item.pass": 48, "item.pop": 30,
          "pigeon.banner": 30, "pigeon.coo": 16, "pigeon.splat": 16, "pigeon.line": 48, "pigeon.drop_line": 48,
          "manager.title": 24, "manager.line": 48, "manager.you": 48, "manager.prompt": 24, "manager.waiting": 48, "manager.made": 48,
          "manager_rule.name": 16, "manager_rule.banner": 30, "manager_rule.line": 48}
SCHEMA_V1 = {
    "": {"format", "team", "object", "players", "words"},
    "team": {"name", "tagline"},
    "object": {"kind", "picture", "fit"},
    "player": {"name", "color", "hair", "skin", "catchphrase"},
    "words": set(WORDS),
}
SCHEMA = {
    "": {"format", "team", "brand", "world", "object", "balloon", "obstacles", "posters", "eggs", "players", "words", "music", "video",
         "team_wall", "title", "run", "mode", "show"},
    "person": {"name", "picture"},
    "team": {"name", "tagline", "credit_link", "title"},
    "brand": {"logo", "colors", "walls"},
    "world": {"theme", "style"},
    "object": {"kind", "picture", "fit"},
    "balloon": {"shape", "picture"},
    "obstacle": {"label", "picture", "color"},
    "poster": {"picture", "caption"},
    # hat, eyes and body belong to the courier look (docs/courier-api.md); here they are only short text.
    # look picks the character's items: catalog slot -> item id (demo/character/catalog.json).
    "player": {"name", "color", "hair", "skin", "catchphrase", "voice", "hat", "eyes", "body", "title", "look", "emote"},
    "words": set(WORDS) | {"reveal"},
    "video": {"intro", "win"},
    "title": {"pet_ground"},
    "show": {"words", "rounds", "items", "item_lab", "tandem", "pigeon", "manager"},
    "pigeon": {"off", "banner", "coo", "splat", "line", "drop_line", "tuning"},
    "item": {"id", "name", "banner", "line", "pass", "pop", "off", "voice", "sfx", "media", "tuning"},
    "tandem": {"off", "name", "banner", "line"},
    "manager": {"off"} | set(MANAGER_TEXTS) | {"rules"},
    "manager_rule": {"id", "name", "banner", "line", "off", "tuning"},
    "show_words": set(SHOW_WORDS),
}
LOOK_FIELDS = ("hat", "eyes", "body")
# Letters the display type (Inter) draws: printable Latin-1 and Latin Extended-A. Big words are set in capitals.
FONT_CHARS = re.compile(r"^[ -~\u00a0-ſ]*$")
HEX_COLOR = re.compile(r"^#[0-9a-fA-F]{6}$")
# The game is never an ad (docs/slots.md, content rules): no links, prices or calls to action in any text it shows.
ADVERT = re.compile(r"https?://|www\.|\b[a-z0-9-]+\.(?:com|io|ai|app|co|dev|net|org|gg|xyz|games|shop|store)\b"
                    r"|[$€£¥]\s?\d|\d\s?(?:[$€£¥]|usd|eur|gbp)\b|\bper (?:month|year|seat|user)\b|\d+\s?% off\b"
                    r"|\b(?:sign ?up|buy now|order now|subscribe|book a demo|request a demo|free trial|try (?:it|us) (?:free|now|today)"
                    r"|get started|join (?:us|now|the waitlist)|waitlist|learn more|use code|promo code|discount|coupon|download now"
                    r"|visit (?:us|our)|check out our|available now|link in bio)\b", re.I)
CREDIT_LINK = re.compile(r"^https://[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+(?::\d+)?(?:/[A-Za-z0-9._~%/?=&#-]*)?$")
MAX_CREDIT_LINK = 100


# ------------------------------------------------------------------ cast
def check_cast(cast_path=CAST_FILE, music_dir=MUSIC_DIR, warnings=None):
    """Every problem with the cast, as readable lines; empty means valid. `warnings` (a list) collects what is not a problem
    but the show changes (a people head in a look: the show wears the seat's animal instead)."""
    if not cast_path.is_file():
        return [f"{rel(cast_path)} is missing"]
    try:
        cast = json.loads(cast_path.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        return [f"{rel(cast_path)} is not valid JSON: {error}"]
    if not isinstance(cast, dict):
        return [f"{rel(cast_path)} must be a JSON object"]
    check = Check(cast_path.parent, SCHEMA_V1 if cast.get("format") == FORMAT_V1 else SCHEMA)
    if cast.get("format") not in (FORMAT, FORMAT_V1):
        check.problem(f'"format" must be "{FORMAT}" (got {cast.get("format")!r})')
    check.unknown(cast, "", "the cast")
    v2 = check.schema is SCHEMA

    team = check.section(cast, "team")
    check.text(team, "name", "team.name", required=True)
    check.text(team, "tagline", "team.tagline")
    if v2:
        check.text(team, "title", "team.title")
    link = team.get("credit_link", "") if v2 else ""
    if link != "" and not (isinstance(link, str) and len(link) <= MAX_CREDIT_LINK and CREDIT_LINK.match(link)):
        check.problem(f'team.credit_link must be one https:// link of up to {MAX_CREDIT_LINK} characters, like "https://acme.example" (got {link!r}); '
                      "it is shown only on the results screen")

    item = check.section(cast, "object")
    if item.get("kind", "landscape") not in OBJECT_KINDS:
        check.problem(f'object.kind must be one of {", ".join(OBJECT_KINDS)} (got {item.get("kind")!r})')
    if item.get("fit", "contain") not in PICTURE_FITS:
        check.problem(f'object.fit must be one of {", ".join(PICTURE_FITS)} (got {item.get("fit")!r})')
    check.picture(item.get("picture", ""), "object.picture", "print" if v2 else None)

    if v2:
        brand = check.section(cast, "brand")
        check.picture(brand.get("logo", ""), "brand.logo", "logo")
        for shirt in sorted(p for p in check.folder.glob("shirt_print.*") if p.suffix != ".import"): # printed on the wardrobe's team shirt instead of logo and tagline
            check.picture(shirt.name, f"demo/cast/{shirt.name}", "shirt_print")
        for sign in sorted(p for p in check.folder.glob("goal_sign.*") if p.suffix != ".import"):  # the goal sign's face instead of the logo
            check.picture(sign.name, f"demo/cast/{sign.name}", "goal_sign")
        check.slot_pictures()  # banner_1/2 and billboard_1/2 of the show's level slots
        check.crown()  # the show's own crown model instead of the built-in one
        check.hero_prop()  # the show's own hero prop (the stand under the crown) instead of the built-in one
        colors = brand.get("colors", [])
        if not isinstance(colors, list) or len(colors) > MAX_BRAND_COLORS:
            check.problem(f'brand.colors must be a list of 1 to {MAX_BRAND_COLORS} colours like "#ff6a13"')
        else:
            for index, value in enumerate(colors):
                check.color(value, f"brand.colors[{index}]")
        check.choice(brand, "walls", BRAND_WALLS, "brand.walls")
        world = check.section(cast, "world")
        check.choice(world, "theme", THEMES, "world.theme")
        check.choice(world, "style", WORLD_STYLES, "world.style")
        balloon = check.section(cast, "balloon")
        check.choice(balloon, "shape", BALLOON_SHAPES, "balloon.shape")
        check.picture(balloon.get("picture", ""), "balloon.picture", "balloon")
        for index, entry in enumerate(check.listed(cast, "obstacles", MAX_OBSTACLES, "obstacles")):
            label = f"obstacles[{index}]"
            if check.entry(entry, "obstacle", label):
                check.text(entry, "label", "obstacle.label", label=f"{label}.label")
                if not str(entry.get("label", "")).strip():
                    check.problem(f"{label} has no label; a sign without a label is not drawn (give it a label of up to 16 letters)")
                check.picture(entry.get("picture", ""), f"{label}.picture", f"obstacle_{index + 1}")
                if "color" in entry:
                    check.color(entry["color"], f"{label}.color")
        for index, entry in enumerate(check.listed(cast, "posters", MAX_POSTERS, "posters")):
            label = f"posters[{index}]"
            if check.entry(entry, "poster", label):
                check.text(entry, "caption", "poster.caption", label=f"{label}.caption")
                check.picture(entry.get("picture", ""), f"{label}.picture", f"poster_{index + 1}")
        eggs = check.listed(cast, "eggs", MAX_EGGS, "eggs")
        music = cast.get("music", "")
        if music != "":
            ids = music_ids(music_dir)
            if not isinstance(music, str) or music not in ids:
                check.problem(f'music must be one of {", ".join(ids)} (got {music!r}); each id is a demo/audio/music/friends-<id>.ogg or .wav')
        video = check.section(cast, "video")
        for kind in ("intro", "win"):
            check.video(video.get(kind, ""), f"video.{kind}", f"video/{kind}.ogv")
        show = check.section(cast, "show")
        show_words = show.get("words", {})
        if not isinstance(show_words, dict):
            check.problem('"show.words" must be an object')
        else:
            check.unknown(show_words, "show_words", "show.words")
            for key in SHOW_WORDS:
                check.text(show_words, key, "show.word", label=f"show.words.{key}")
        check.rounds(show.get("rounds", {}))  # the rounds' own titles, rules, hints, labels and models
        if "item_lab" in show and not isinstance(show["item_lab"], bool):
            check.problem('"show.item_lab" must be true or false')
        check.items(show.get("items", []))  # the items and events of the races: words, sounds, footage, tuning
        check.tandem(show.get("tandem", {}))  # the TANDEM experiment's words (docs/party-show.md "Tandem (experiment)")
        check.pigeon(show.get("pigeon", {}))  # GHOST PIGEON: its words and tuning, or off
        if "manager" in show:
            check.manager(show["manager"])  # THE MANAGER experiment: its words, the rules' words, durations and which rules are off
        on_wall = set()
        for index, entry in enumerate(check.listed(cast, "team_wall", MAX_TEAM_WALL, "team_wall")):
            label = f"team_wall[{index}]"
            if check.entry(entry, "person", label):
                check.text(entry, "name", "team_wall.name", required=True, label=f"{label}.name")
                check.photo(entry.get("picture", ""), f"{label}.picture", f"team/member_{index + 1}")
                on_wall.add(entry.get("picture", ""))
        check.pack_files(on_wall)
        spot = check.section(cast, "title").get("pet_ground")
        if spot is not None and not (isinstance(spot, list) and len(spot) == 2
                                     and all(isinstance(v, (int, float)) and not isinstance(v, bool) and 0 <= v <= 1 for v in spot)):
            check.problem(f"title.pet_ground must be [x, y], two numbers from 0 to 1 across the title backdrop picture (got {spot!r})")
    else:
        eggs = []
    check.title_backdrop()
    check.prepared()

    players = cast.get("players", [])
    if not isinstance(players, list) or not 1 <= len(players) <= MAX_PLAYERS:
        check.problem(f"players must be a list of 1 to {MAX_PLAYERS} cast members")
        players = []
    names = []
    for index, member in enumerate(players):
        label = f"players[{index}]"
        if not check.entry(member, "player", label):
            continue
        check.text(member, "name", "player.name", required=True, label=f"{label}.name")
        check.text(member, "catchphrase", "player.catchphrase", label=f"{label}.catchphrase")
        for key in ("color", "hair", "skin"):
            if key == "color" or member.get(key) is not None:
                check.color(member.get(key), f"{label}.{key}")
        if v2:
            for key in LOOK_FIELDS:
                if key in member:
                    check.text(member, key, "look", label=f"{label}.{key}")
            check.text(member, "title", "player.title", label=f"{label}.title")
            if "look" in member:
                check.look(member["look"], f"{label}.look", index)
            emotes = catalog_emotes()
            if member.get("emote", "") not in emotes + [""]:
                check.problem(f"{label}.emote must be one of {', '.join(emotes)} (got {member.get('emote')!r})")
            if member.get("voice", "") != "":  # the name here; the clip itself with every file in voice/ (pack_files)
                check.file(member["voice"], f"{label}.voice", f"voice/member_{index + 1}.ogg", (".ogg",))
        if isinstance(member.get("name"), str) and len(member["name"].strip()) >= 2:
            names.append(member["name"].strip())

    for index, line in enumerate(eggs):
        label = f"eggs[{index}]"
        if not isinstance(line, str) or not line.strip():
            check.problem(f"{label} must be a line of text (up to {LIMITS['egg']} characters)")
            continue
        check.text({"egg": line}, "egg", "egg", label=label)
        for name in names:
            if re.search(rf"(?<!\w){re.escape(name)}(?!\w)", line, re.I):
                check.problem(f"{label} names a cast member ({name}); an easter egg never names a person, write the joke without the name")

    words = check.section(cast, "words")
    for key in WORDS:
        check.text(words, key, "word", label=f"words.{key}")
    if v2:
        check.choice(cast, "run", ["time_attack", "endless"], "run")  # the one lobby circle the game shows
        check.choice(cast, "mode", mode_ids(), "mode")  # the one mode the game shows (demo/modes/modes.json, docs/modes.md)
        check.text(words, "reveal", "reveal", label="words.reveal")  # the results' surprise line of a delivered run

    check.problems.extend(forbidden_names(cast_path.parent))
    if warnings is not None:
        warnings.extend(check.warnings)
    return check.problems


def catalog_items(catalog_file=CATALOG_FILE):
    """Slot -> item ids of the character catalog, in its order (what players[i].look may pick; people heads are not offered)."""
    catalog = json.loads(catalog_file.read_text(encoding="utf-8"))
    items = {slot: [] for slot in catalog.get("slots", [])}
    for entry in catalog.get("items", []):
        if isinstance(entry, dict) and entry.get("slot") in items and not (entry["slot"] == "head" and is_people_head(entry.get("id"), catalog.get("people_heads", []))):
            items[entry["slot"]].append(entry.get("id"))
    return items


def catalog_people(catalog_file=CATALOG_FILE):
    """Head ids that read as a person (catalog `people_heads`): the show never wears them (demo/character/catalog.gd is_people)."""
    return list(json.loads(catalog_file.read_text(encoding="utf-8")).get("people_heads", []))


def is_people_head(item, people):
    return isinstance(item, str) and (item.startswith("head_human") or item in people)


def seat_animal(seat, catalog_file=CATALOG_FILE):
    """The head the show gives a seat (catalog `seat_heads`, cycling, people heads and heads without a catalog item skipped):
    what CharacterLook uses when a cast asks for a people head."""
    catalog = json.loads(catalog_file.read_text(encoding="utf-8"))
    order = [h for h in catalog.get("seat_heads", []) if not is_people_head(h, catalog.get("people_heads", []))]
    offered = catalog_items(catalog_file).get("head", [])
    order = [h for h in order if h in offered] or offered
    return order[seat % len(order)] if order else ""


def mode_ids(modes_file=MODES_FILE):
    """The game's modes, the default first (what `mode` may pick)."""
    modes = json.loads(modes_file.read_text(encoding="utf-8"))
    ids = list(modes.get("modes", {}))
    default = modes.get("default", "carry")
    return [default] + [i for i in ids if i != default]


def catalog_emotes(catalog_file=CATALOG_FILE):
    """The emote ids of the character catalog (what players[i].emote may pick)."""
    return list(json.loads(catalog_file.read_text(encoding="utf-8")).get("emotes", {}))


def music_ids(music_dir=MUSIC_DIR):
    """The music ids a cast may pick: demo/audio/music/friends-<id>.ogg or .wav."""
    return sorted({path.stem[len("friends-"):] for ending in ("ogg", "wav") for path in Path(music_dir).glob("friends-*." + ending)})


class Check:
    def __init__(self, folder, schema):
        self.folder = folder
        self.schema = schema
        self.problems = []
        self.warnings = []

    def problem(self, text):
        self.problems.append(text)

    def section(self, cast, key):
        value = cast.get(key, {})
        if not isinstance(value, dict):
            self.problem(f'"{key}" must be an object')
            return {}
        self.unknown(value, key, key)
        return value

    def listed(self, cast, key, most, label):
        value = cast.get(key, [])
        if not isinstance(value, list) or len(value) > most:
            self.problem(f"{label} must be a list of at most {most}")
            return []
        return value

    def entry(self, value, schema, label):
        if not isinstance(value, dict):
            self.problem(f"{label} must be an object")
            return False
        self.unknown(value, schema, label)
        return True

    def unknown(self, value, schema, label):
        for key in sorted(set(value) - self.schema[schema]):
            self.problem(f'{label} has no field "{key}" (the game would ignore it); fields: {", ".join(sorted(self.schema[schema]))}')

    def text(self, part, key, limit, required=False, label=None, jokes=False):
        label = label or limit
        value = part.get(key, "")
        if not isinstance(value, str):
            self.problem(f"{label} must be text")
            return
        if required and not value.strip():
            self.problem(f"{label} must not be empty")
        if len(value) > LIMITS[limit]:
            self.problem(f"{label} is {len(value)} characters; keep it to {LIMITS[limit]}")
        if not FONT_CHARS.match(value):
            drawn = self.fallback_letters()
            bad = "".join(sorted({c for c in value if not FONT_CHARS.match(c) and c not in drawn}))
            if any(cast_fonts.cjk(c) for c in bad):
                self.problem(f"{label} has Japanese or Chinese letters the cast fonts do not have yet: {bad!r}; run python3 tools/cast_fonts.py")
            elif bad:
                self.problem(f"{label} has letters the game's font cannot draw: {bad!r} (no emoji; Latin letters, æøå, accents, Japanese and Chinese are fine)")
        advert = ADVERT.search(ITEM_ADVERT_JOKES.sub("", value) if jokes else value)
        if advert:
            self.problem(f"{label} reads like an ad ({advert.group(0)!r}); the game never pitches: no links, prices or calls to action "
                         "(the team's link goes only in team.credit_link, shown on the results screen)")

    def fallback_letters(self):
        """The letters the cast fonts draw (demo/cast/fonts/, made by tools/cast_fonts.py), empty without them."""
        if not hasattr(self, "_fallback"):
            fonts = self.folder / cast_fonts.FONTS
            listed = fonts / "fallback.txt"
            self._fallback = set(listed.read_text(encoding="utf-8").strip()) if listed.is_file() and (fonts / "fallback_1.ttf").is_file() else set()
        return self._fallback

    def choice(self, part, key, options, label):
        value = part.get(key, options[0])
        if value not in options:
            self.problem(f'{label} must be one of {", ".join(options)} (got {value!r})')

    def look(self, value, label, seat=0):
        if not isinstance(value, dict):
            self.problem(f"{label} must be an object: catalog slot -> item id, such as {{\"head\": \"head_bear\", \"hat\": \"hat_cap\"}}")
            return
        items = catalog_items()
        for slot, item in value.items():
            if slot not in items:
                self.problem(f'{label} has no slot "{slot}"; slots: {", ".join(items)}')
            elif slot == "head" and is_people_head(item, catalog_people()):
                self.warnings.append(f"{label}.head {item!r} reads as a person: the show never shows people, it wears {seat_animal(seat)} "
                                     f"for seat {seat} instead; pick an animal or bean head ({', '.join(items['head'])})")
            elif not (isinstance(item, str) and (item in items[slot] or (item == "" and slot != "head"))):
                choices = ", ".join(items[slot]) + ("" if slot == "head" else ' or "" for nothing')
                self.problem(f"{label}.{slot} must be one of {choices} (got {item!r})")

    def color(self, value, label):
        if not (isinstance(value, str) and HEX_COLOR.match(value)):
            self.problem(f'{label} must be a colour like "#ff5a36" (got {value!r})')

    def file(self, name, label, expected, suffixes, subdir=None):
        """The path of a named cast file when it is well named and present, else None (the problem is reported)."""
        if not isinstance(name, str):
            self.problem(f"{label} must be a file name in demo/cast/ (or empty)")
            return None
        if "\\" in name or ".." in name or name.startswith("/") or name.startswith("."):
            self.problem(f"{label} must be a plain file name inside demo/cast/ (got {name!r})")
            return None
        if expected is not None:
            stem = expected.rsplit(".", 1)[0] if "." in expected.rsplit("/", 1)[-1] else expected
            allowed = [stem + suffix for suffix in suffixes]
            if name not in allowed:
                self.problem(f"{label} must be {' or '.join(repr(a) for a in allowed)} in demo/cast/ (got {name!r}); the slots use fixed file names")
                return None
        elif subdir is not None:
            if not name.startswith(subdir + "/") or "/" in name[len(subdir) + 1:] or name == subdir + "/":
                self.problem(f"{label} must be {subdir}/<file> inside demo/cast/ (got {name!r})")
                return None
        elif "/" in name:
            self.problem(f"{label} must be a plain file name inside demo/cast/ (got {name!r})")
            return None
        path = self.folder / name
        if not path.is_file():
            self.problem(f"{label} {name!r} is not in demo/cast/; add the file or leave the field empty")
            return None
        if path.suffix.lower() not in suffixes:
            self.problem(f"{label} must be one of {', '.join(suffixes)}")
            return None
        return path

    def picture(self, name, label, expected):
        if name == "":
            return
        path = self.file(name, label, expected, PICTURE_SUFFIXES)
        if path is None:
            return
        size = path.stat().st_size
        if size > MAX_PICTURE_BYTES:
            self.problem(f"{label} is {size // 1024} KB; keep it under {MAX_PICTURE_BYTES // 1024 // 1024} MB (the game scales it to 1024 px anyway)")
            return
        data = path.read_bytes()
        kind = picture_format(data)
        if kind is None or kind != {".png": "png", ".jpg": "jpeg", ".jpeg": "jpeg", ".webp": "webp"}[path.suffix.lower()]:
            self.problem(f"{label} {name!r} is not a {path.suffix[1:].upper()} picture (its bytes say {kind or 'unknown'}); save it as PNG, JPEG or WebP with the matching ending")
            return
        dims = image_size(data)
        if dims and min(dims) < MIN_PICTURE_SIDE:
            self.problem(f"{label} is {dims[0]}x{dims[1]} px; use at least {MIN_PICTURE_SIDE} px on the short side")

    def clip(self, path, label):
        """A sound clip (voice or announcer): Ogg Vorbis, mono, up to MAX_CLIP_SECONDS and MAX_CLIP_BYTES."""
        data = path.read_bytes()
        if len(data) > MAX_CLIP_BYTES:
            self.problem(f"{label} is {len(data) // 1024} KB; keep a clip under {MAX_CLIP_BYTES // 1024} KB")
            return
        seconds = vorbis_seconds(data)
        if seconds is None:
            self.problem(f"{label} is not an Ogg Vorbis clip; export it as .ogg (Vorbis, mono)")
        elif vorbis_channels(data) != 1:
            self.problem(f"{label} has {vorbis_channels(data)} channels; export it as mono")
        elif seconds > MAX_CLIP_SECONDS:
            self.problem(f"{label} is {seconds:.1f} s long; keep a clip to {MAX_CLIP_SECONDS:.0f} s")

    def photo(self, name, label, expected):
        """A team wall photo: the person's own, square, PNG/JPEG/WebP, under MAX_PHOTO_BYTES."""
        if name == "":
            return
        path = self.file(name, label, expected, PICTURE_SUFFIXES)
        if path is None:
            return
        data = path.read_bytes()
        kind = picture_format(data)
        if kind is None or kind != {".png": "png", ".jpg": "jpeg", ".jpeg": "jpeg", ".webp": "webp"}[path.suffix.lower()]:
            self.problem(f"{label} {name!r} is not a {path.suffix[1:].upper()} picture (its bytes say {kind or 'unknown'}); save it as PNG, JPEG or WebP")
            return
        if len(data) > MAX_PHOTO_BYTES:
            self.problem(f"{label} is {len(data) // 1024} KB; keep a photo under {MAX_PHOTO_BYTES // 1024 // 1024} MB")
        dims = image_size(data)
        if dims and (dims[0] != dims[1] or not PHOTO_SIDE[0] <= dims[0] <= PHOTO_SIDE[1]):
            self.problem(f"{label} is {dims[0]}x{dims[1]} px; use a square photo, 512x512 px (from {PHOTO_SIDE[0]} to {PHOTO_SIDE[1]})")

    def pack_files(self, on_wall):
        """Every file in announcer/, voice/ and team/ has a name the game looks for, and every clip passes clip()."""
        events = "|".join(ANNOUNCER_EVENTS)
        folders = {
            "announcer": (re.compile(rf"^({events})_[1-{ANNOUNCER_VARIANTS}]\.ogg$"), f"<event>_<1..{ANNOUNCER_VARIANTS}>.ogg, event one of {', '.join(ANNOUNCER_EVENTS)}"),
            "voice": (re.compile(rf"^member_[1-{MAX_PLAYERS}](_[1-{VOICE_VARIANTS}])?\.ogg$"), f"member_<1..{MAX_PLAYERS}>.ogg or member_<n>_<1..{VOICE_VARIANTS}>.ogg"),
            "team": (re.compile(r"^member_([1-9]|10)\.(png|jpe?g|webp)$"), f"member_<1..{MAX_TEAM_WALL}>.png (or .jpg / .webp)"),
        }
        for folder, (pattern, names) in folders.items():
            base = self.folder / folder
            if not base.is_dir():
                continue
            for path in sorted(p for p in base.rglob("*") if p.is_file() and p.name not in ALWAYS_SKIPPED_NAMES and p.suffix != ".import"):
                name = path.relative_to(self.folder).as_posix()
                if path.parent != base or not pattern.match(path.name):
                    self.problem(f"demo/cast/{name}: the game never looks for this file; names in {folder}/ are {names}")
                elif folder == "team" and name not in on_wall:
                    self.problem(f'demo/cast/{name} is not on the team wall; add {{"name": ..., "picture": "{name}"}} to team_wall (or remove the file)')
                elif folder != "team":
                    self.clip(path, f"demo/cast/{name}")

    def title_backdrop(self):
        """The title art, when the cast has one: one file, PNG/JPEG/WebP matching its ending, landscape, big enough, under 4 MB."""
        found = sorted(p for p in self.folder.glob(TITLE_BACKDROP + ".*") if p.suffix != ".import")
        if len(found) > 1:
            self.problem(f"demo/cast/ has {len(found)} title backdrops ({', '.join(p.name for p in found)}); keep one")
        for path in found:
            label = f"demo/cast/{path.name}"
            if path.suffix.lower() not in PICTURE_SUFFIXES:
                self.problem(f"{label} must be {TITLE_BACKDROP}.png (or .jpg / .webp)")
                continue
            data = path.read_bytes()
            kind = picture_format(data)
            if kind is None or kind != {".png": "png", ".jpg": "jpeg", ".jpeg": "jpeg", ".webp": "webp"}[path.suffix.lower()]:
                self.problem(f"{label} is not a {path.suffix[1:].upper()} picture (its bytes say {kind or 'unknown'}); save it as PNG, JPEG or WebP with the matching ending")
                continue
            if len(data) > MAX_PICTURE_BYTES:
                self.problem(f"{label} is {len(data) // 1024} KB; keep it under {MAX_PICTURE_BYTES // 1024 // 1024} MB (a JPEG at 1536 x 1024 is plenty)")
            dims = image_size(data)
            if dims and (dims[0] <= dims[1] or dims[0] < TITLE_BACKDROP_MIN[0] or dims[1] < TITLE_BACKDROP_MIN[1]):
                self.problem(f"{label} is {dims[0]}x{dims[1]} px; use a landscape picture of at least {TITLE_BACKDROP_MIN[0]}x{TITLE_BACKDROP_MIN[1]} (1536x1024 is best)")

    def prepared(self):
        """demo/cast/prepared/, when it exists: the manifest tools/cast_prep.py wrote and exactly the PNGs it names as keyed.

        Every manifest entry must still match its source file's bytes (else the prepared picture is stale), and a prepared picture must be a
        valid PNG of the size the manifest says, under MAX_PICTURE_BYTES."""
        base = self.folder / PREPARED_DIR
        if not base.exists():
            return
        label = f"demo/cast/{PREPARED_DIR}"
        again = "run python3 tools/cast_prep.py (ship.py does) or delete the folder"
        if not base.is_dir():
            self.problem(f"{label} must be a folder (tools/cast_prep.py writes it); {again}")
            return
        manifest_file = base / "manifest.json"
        if not manifest_file.is_file():
            self.problem(f"{label}/manifest.json is missing; {again}")
            return
        try:
            manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            self.problem(f"{label}/manifest.json is not valid JSON ({error}); {again}")
            return
        if not isinstance(manifest, dict) or manifest.get("format") != PREPARED_FORMAT or not isinstance(manifest.get("files"), dict) \
                or set(manifest) != {"format", "files"}:
            self.problem(f'{label}/manifest.json must be {{"format": "{PREPARED_FORMAT}", "files": {{...}}}}; {again}')
            return
        keyed = {}
        for name, entry in sorted(manifest["files"].items()):
            where = f"{label}/manifest.json {name!r}"
            if not (isinstance(name, str) and name == Path(name).name and not name.startswith(".")
                    and Path(name).suffix.lower() in PICTURE_SUFFIXES):
                self.problem(f"{where} is not a plain picture file name of demo/cast/; {again}")
                continue
            if not isinstance(entry, dict) or set(entry) - PREPARED_FIELDS:
                self.problem(f"{where} must be an object with sha256, result and (keyed only) background and size; {again}")
                continue
            if entry.get("result") not in PREPARED_RESULTS:
                self.problem(f"{where} result must be one of {', '.join(PREPARED_RESULTS)} (got {entry.get('result')!r}); {again}")
                continue
            digest_text = entry.get("sha256")
            if not (isinstance(digest_text, str) and re.fullmatch(r"[0-9a-f]{64}", digest_text)):
                self.problem(f"{where} sha256 must be 64 hex digits; {again}")
                continue
            source = self.folder / name
            if not source.is_file():
                self.problem(f"{where}: {name} is not in demo/cast/ any more; run python3 tools/cast_prep.py again (ship.py does)")
            elif hashlib.sha256(source.read_bytes()).hexdigest() != digest_text:
                self.problem(f"{name} changed since tools/cast_prep.py ran; run it again (ship.py does)")
            if entry["result"] != "keyed":
                if "background" in entry or "size" in entry:
                    self.problem(f"{where} has a background or size but its result is {entry['result']}; {again}")
                continue
            size = entry.get("size")
            if not (isinstance(entry.get("background"), str) and HEX_COLOR.match(entry["background"])
                    and isinstance(size, list) and len(size) == 2 and all(isinstance(v, int) and not isinstance(v, bool) and v > 0 for v in size)):
                self.problem(f'{where} is keyed, so it needs "background" like "#ffffff" and "size" [width, height]; {again}')
                continue
            target = Path(name).stem + ".png"
            if target in keyed:
                self.problem(f"{where} and {keyed[target]!r} would both be {label}/{target}; {again}")
                continue
            keyed[target] = name
            path = base / target
            if not path.is_file():
                self.problem(f"{label}/{target} is missing (keyed from {name}); {again}")
                continue
            data = path.read_bytes()
            if len(data) > MAX_PICTURE_BYTES:
                self.problem(f"{label}/{target} is {len(data) // 1024} KB; keep it under {MAX_PICTURE_BYTES // 1024 // 1024} MB")
            elif not png_ok(data):
                self.problem(f"{label}/{target} is not a valid PNG; {again}")
            elif list(image_size(data)) != size:
                self.problem(f"{label}/{target} is {image_size(data)[0]}x{image_size(data)[1]} px but the manifest says {size[0]}x{size[1]}; {again}")
        for path in sorted(base.iterdir()):
            if path.name in ALWAYS_SKIPPED_NAMES or path.name == "manifest.json" or path.suffix in (".import", ".uid") and path.is_file():
                continue
            if path.name not in keyed or not path.is_file():
                self.problem(f"{label}/{path.name} is not a prepared picture the manifest names (only manifest.json and the keyed PNGs belong "
                             f"here); {again}")

    def crown(self):
        """The cast's own crown, when it has one: demo/cast/crown.glb, a glTF binary (valid header) under MAX_CROWN_BYTES."""
        for path in sorted(p for p in self.folder.glob(CROWN_FILE.rsplit(".", 1)[0] + ".*") if p.suffix != ".import"):
            label = f"demo/cast/{path.name}"
            if path.name != CROWN_FILE:
                self.problem(f"{label}: the game never looks for this file; the show's crown model is demo/cast/{CROWN_FILE}")
                continue
            size = path.stat().st_size
            if size > MAX_CROWN_BYTES:
                self.problem(f"{label} is {size // 1024} KB; keep the crown model under {MAX_CROWN_BYTES // 1024 // 1024} MB")
            elif not glb_ok(path.read_bytes()):
                self.problem(f"{label} is not a glTF binary; export the model as .glb (glTF Binary, version 2)")

    def hero_prop(self):
        """The cast's own hero prop, when it has one: demo/cast/hero_prop.glb, a glTF binary under MAX_HERO_PROP_BYTES whose tiers keep inside
        the stepped stand the level's collision makes (docs/hero-prop.md)."""
        for path in sorted(p for p in self.folder.glob(HERO_PROP_FILE.rsplit(".", 1)[0] + ".*") if p.suffix != ".import"):
            label = f"demo/cast/{path.name}"
            if path.name != HERO_PROP_FILE:
                self.problem(f"{label}: the game never looks for this file; the show's hero prop is demo/cast/{HERO_PROP_FILE}")
                continue
            data = path.read_bytes()
            if len(data) > MAX_HERO_PROP_BYTES:
                self.problem(f"{label} is {len(data) // 1024} KB; keep the hero prop under {MAX_HERO_PROP_BYTES // 1024 // 1024} MB")
            elif not glb_ok(data):
                self.problem(f"{label} is not a glTF binary; export the model as .glb (glTF Binary, version 2)")
            else:
                for text in hero_prop_problems(data):
                    self.problem(f"{label} {text}")

    def rounds(self, rounds):
        """show.rounds: {round id: {title, rule, hint, label, model}}. The id must be a round of the show, a key must be one that round takes,
        the texts keep to their lengths, a label is a text or a list of up to MAX_LABELS, a model is the round's own file round_<id>.glb."""
        ids = ", ".join(f"{round_id} {name}" for round_id, name in ROUND_NAMES.items())
        if not isinstance(rounds, dict):
            self.problem('"show.rounds" must be an object: round id -> {"title": ..., "label": ...}')
            rounds = {}
        named = set()
        for round_id, entry in rounds.items():
            label = f"show.rounds.{round_id}"
            if round_id not in ROUND_NAMES:
                extra = " (POSTER RUSH is one round, r17: both of its levels)" if round_id == "r20" else ""
                self.problem(f"{label}: {round_id!r} is not a round of the show{extra}; the rounds are {ids}")
                continue
            if not isinstance(entry, dict):
                self.problem(f"{label} must be an object (keys: {', '.join(ROUND_KEYS[round_id])})")
                continue
            for key in sorted(set(entry) - set(ROUND_KEYS[round_id])):
                if key in ("title", "rule", "hint", "label", "model"):
                    where = {"label": "r15, r17, r21 and r23", "model": "r21 and r23"}[key]
                    self.problem(f'{label}.{key}: {ROUND_NAMES[round_id]} takes no {key}; {key} is for {where} only (it takes {", ".join(ROUND_KEYS[round_id])})')
                else:
                    self.problem(f'{label} has no field "{key}" (the game would ignore it); fields: {", ".join(ROUND_KEYS[round_id])}')
            for key in ROUND_TEXT_KEYS:
                if key in entry:
                    self.text(entry, key, "round.title" if key == "title" else "round.line", label=f"{label}.{key}")
            if "label" in entry and "label" in ROUND_KEYS[round_id]:
                self.round_labels(entry["label"], f"{label}.label")
            if "model" in entry and "model" in ROUND_KEYS[round_id]:
                if self.round_model(entry["model"], round_id, f"{label}.model"):
                    named.add(f"round_{round_id}.glb")
        for path in sorted(p for p in self.folder.glob("round_*") if p.is_file() and p.suffix != ".import"):
            expected = [f"round_{round_id}.glb" for round_id in ROUND_MODEL_IDS]
            if path.name not in expected:
                self.problem(f"demo/cast/{path.name}: the game never looks for this file; the round models are {', '.join(expected)}")
            elif path.name not in named:
                self.problem(f'demo/cast/{path.name} is not used; name it in "show.rounds.{path.stem[len("round_"):]}.model" (or remove the file)')

    def items(self, entries):
        """show.items: a list of {id, name, banner, line, pass, pop, off, voice, sfx, media, tuning}: each id once and one of the template's items, texts to their
        lengths, voice and sfx clips and the call's footage under items/, tuning keys and ranges as items.json says."""
        spec = json.loads(ITEMS_FILE.read_text())["items"] if ITEMS_FILE.is_file() else {}
        ids = ", ".join(spec)
        if not isinstance(entries, list) or len(entries) > max(len(spec), 1):
            self.problem(f"show.items must be a list of at most {len(spec)} entries (ids: {ids})")
            return
        seen = set()
        for index, entry in enumerate(entries):
            label = f"show.items[{index}]"
            if not self.entry(entry, "item", label):
                continue
            item_id = entry.get("id")
            if item_id not in spec:
                self.problem(f"{label}.id {item_id!r} is not an item of the show; the ids are {ids}")
                continue
            label = f"show.items[{index}] ({item_id})"
            if item_id in seen:
                self.problem(f"{label}: {item_id!r} is there twice; one entry per id")
            seen.add(item_id)
            for key in ("name", "banner", "line", "pass", "pop"):
                if key in entry and key in ("pass", "pop") and item_id != "eggplant":
                    self.problem(f"{label}.{key}: only the eggplant has a {key} sentence")
                elif key in entry:
                    self.text(entry, key, "item." + key, required=True, label=f"{label}.{key}", jokes=True)
            if "off" in entry and not isinstance(entry["off"], bool):
                self.problem(f"{label}.off must be true or false")
            for key in ("voice", "sfx"):
                if entry.get(key, "") != "":
                    path = self.file(entry[key], f"{label}.{key}", None, (".ogg",), ITEM_DIR)
                    if path is not None:
                        self.clip(path, f"{label}.{key}")
            if entry.get("media", "") != "":
                if item_id != "call":
                    self.problem(f"{label}.media: only the call takes footage")
                else:
                    self.video(entry["media"], f"{label}.media", None, ITEM_DIR)
            tuning = entry.get("tuning", {})
            if not isinstance(tuning, dict):
                self.problem(f"{label}.tuning must be an object of numbers")
                continue
            ranges = spec[item_id].get("tuning", {})
            for key, value in tuning.items():
                if key not in ranges:
                    self.problem(f"{label}.tuning has no key {key!r}; keys: {', '.join(ranges) or 'none'}")
                elif isinstance(value, bool) or not isinstance(value, (int, float)):
                    self.problem(f"{label}.tuning.{key} must be a number")
                elif not ranges[key]["min"] <= value <= ranges[key]["max"]:
                    self.problem(f"{label}.tuning.{key} is {value}; the game keeps it between {ranges[key]['min']} and {ranges[key]['max']}")
        for path in sorted((self.folder / ITEM_DIR).glob("*")) if (self.folder / ITEM_DIR).is_dir() else []:
            if path.suffix not in (".ogg", ".ogv", ".import") and path.is_file():
                self.problem(f"demo/cast/{ITEM_DIR}/{path.name}: items take .ogg clips and the call's .ogv only")

    def tandem(self, entry):
        """show.tandem (the TANDEM experiment): {off, name, banner, line}; the line keeps {a} and {b} for the two players' names."""
        if not self.entry(entry, "tandem", "show.tandem"):
            return
        for key in ("name", "banner", "line"):
            if key in entry:
                self.text(entry, key, "item." + key, required=True, label=f"show.tandem.{key}", jokes=True)
        if "off" in entry and not isinstance(entry["off"], bool):
            self.problem("show.tandem.off must be true or false")

    def pigeon(self, entry):
        """show.pigeon: {off, banner, coo, splat, line, drop_line, tuning}: texts to their lengths ({user} and {victim} in the two lines only), `off` a switch, tuning keys and ranges as pigeon.json says."""
        if not self.entry(entry, "pigeon", "show.pigeon"):
            return
        spec = json.loads(PIGEON_FILE.read_text()) if PIGEON_FILE.is_file() else {}
        for key in ("banner", "coo", "splat", "line", "drop_line"):
            if key in entry:
                self.text(entry, key, "pigeon." + key, required=True, label=f"show.pigeon.{key}", jokes=True)
                if key not in ("line", "drop_line") and isinstance(entry[key], str) and ("{user}" in entry[key] or "{victim}" in entry[key]):
                    self.problem(f"show.pigeon.{key} has no names to fill in; only line and drop_line take {{user}} and {{victim}}")
        if "off" in entry and not isinstance(entry["off"], bool):
            self.problem("show.pigeon.off must be true or false")
        tuning = entry.get("tuning", {})
        if not isinstance(tuning, dict):
            self.problem("show.pigeon.tuning must be an object of numbers")
            return
        ranges = spec.get("tuning", {})
        for key, value in tuning.items():
            if key not in ranges:
                self.problem(f"show.pigeon.tuning has no key {key!r}; keys: {', '.join(ranges) or 'none'}")
            elif isinstance(value, bool) or not isinstance(value, (int, float)):
                self.problem(f"show.pigeon.tuning.{key} must be a number")
            elif not ranges[key]["min"] <= value <= ranges[key]["max"]:
                self.problem(f"show.pigeon.tuning.{key} is {value}; the game keeps it between {ranges[key]['min']} and {ranges[key]['max']}")

    def manager(self, value):
        """show.manager: {off, title, line, you, prompt, waiting, made, rules: [{id, name, banner, line, off, tuning}]}: texts to their lengths, each rule id once and one of
        the template's manager.json, tuning.duration (seconds) between MANAGER_DURATION."""
        if not self.entry(value, "manager", "show.manager"):
            return
        spec = json.loads(MANAGER_FILE.read_text()).get("rules", {}) if MANAGER_FILE.is_file() else {}
        ids = ", ".join(spec)
        if "off" in value and not isinstance(value["off"], bool):
            self.problem("show.manager.off must be true or false")
        for key in MANAGER_TEXTS:
            if key in value:
                self.text(value, key, "manager." + key, required=True, label=f"show.manager.{key}", jokes=True)
        entries = value.get("rules", [])
        if not isinstance(entries, list) or len(entries) > max(len(spec), 1):
            self.problem(f"show.manager.rules must be a list of at most {len(spec)} entries (ids: {ids})")
            return
        seen = set()
        for index, entry in enumerate(entries):
            label = f"show.manager.rules[{index}]"
            if not self.entry(entry, "manager_rule", label):
                continue
            rule_id = entry.get("id")
            if rule_id not in spec:
                self.problem(f"{label}.id {rule_id!r} is not a rule of the manager; the ids are {ids}")
                continue
            label = f"{label} ({rule_id})"
            if rule_id in seen:
                self.problem(f"{label}: {rule_id!r} is there twice; one entry per id")
            seen.add(rule_id)
            for key in ("name", "banner", "line"):
                if key in entry:
                    self.text(entry, key, "manager_rule." + key, required=True, label=f"{label}.{key}", jokes=True)
            if "off" in entry and not isinstance(entry["off"], bool):
                self.problem(f"{label}.off must be true or false")
            tuning = entry.get("tuning", {})
            if not isinstance(tuning, dict):
                self.problem(f"{label}.tuning must be an object of numbers")
                continue
            for key, number in tuning.items():
                if key != "duration":
                    self.problem(f"{label}.tuning has no key {key!r}; keys: duration")
                elif isinstance(number, bool) or not isinstance(number, (int, float)):
                    self.problem(f"{label}.tuning.duration must be a number")
                elif not MANAGER_DURATION[0] <= number <= MANAGER_DURATION[1]:
                    self.problem(f"{label}.tuning.duration is {number}; the game keeps it between {MANAGER_DURATION[0]:g} and {MANAGER_DURATION[1]:g} seconds")

    def round_labels(self, value, label):
        """A label is a text, or a list of up to MAX_LABELS texts; none of them empty."""
        items = value if isinstance(value, list) else [value]
        if isinstance(value, list) and len(value) > MAX_LABELS:
            self.problem(f"{label} has {len(value)} labels; keep it to {MAX_LABELS}")
            items = value[:MAX_LABELS]
        if not items:
            self.problem(f"{label} is an empty list; give it a text or up to {MAX_LABELS} texts (or leave it out)")
        for index, item in enumerate(items):
            where = f"{label}[{index}]" if isinstance(value, list) else label
            if not isinstance(item, str):
                self.problem(f"{where} must be text")
            elif not item.strip():
                self.problem(f"{where} must not be empty")
            else:
                self.text({"label": item}, "label", "round.label", label=where)

    def round_model(self, name, round_id, label):
        """show.rounds.<id>.model: exactly round_<id>.glb in demo/cast/, a glTF binary under MAX_ROUND_MODEL_BYTES. True when it names the file."""
        expected = f"round_{round_id}.glb"
        if not isinstance(name, str):
            self.problem(f"{label} must be the file name {expected!r}")
            return False
        if name != expected:
            self.problem(f"{label} is {name!r}; the model of {round_id} is the file {expected} in demo/cast/ (name it exactly that)")
            return False
        path = self.folder / expected
        if not path.is_file():
            self.problem(f"{label}: {expected} is not in demo/cast/; put the glb there (docs/swappables.md, Rounds as metaphors)")
            return True
        data = path.read_bytes()
        if len(data) > MAX_ROUND_MODEL_BYTES:
            self.problem(f"demo/cast/{expected} is {len(data) // 1024} KB; keep a round model under {MAX_ROUND_MODEL_BYTES // 1024 // 1024} MB")
        elif not glb_ok(data):
            self.problem(f"demo/cast/{expected} is not a glTF binary; export the model as .glb (glTF Binary, version 2)")
        return True

    def slot_pictures(self):
        """The banner and billboard pictures: banner_1/2 and billboard_1/2 (png, jpg or webp), each a picture like the others."""
        for path in sorted(p for pattern in ("banner_*", "billboard_*") for p in self.folder.glob(pattern) if p.suffix != ".import"):
            if path.stem not in SLOT_PICTURES:
                self.problem(f"demo/cast/{path.name}: the game never looks for this file; the pictures are {', '.join(SLOT_PICTURES)} (.png, .jpg or .webp)")
            else:
                self.picture(path.name, f"demo/cast/{path.name}", path.stem)

    def video(self, name, label, expected, subdir=None):
        if name == "":
            return
        path = self.file(name, label, expected, (".ogv",), subdir)
        if path is None:
            return
        size = path.stat().st_size
        if size > MAX_VIDEO_BYTES:
            self.problem(f"{label} is {size // 1024 // 1024} MB; keep a video under {MAX_VIDEO_BYTES // 1024 // 1024} MB")
            return
        head = path.read_bytes()[:4096]
        if not head.startswith(b"OggS") or b"\x80theora" not in head:
            self.problem(f"{label} {name!r} is not an Ogg Theora video; convert it to .ogv (Theora)")


def picture_format(data):
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if data[:3] == b"\xff\xd8\xff":
        return "jpeg"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    return None


def png_ok(data):
    """True for a structurally valid PNG: signature, IHDR first, every chunk's length and CRC, IDAT present, IEND last."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return False
    pos, kinds = 8, []
    while pos + 12 <= len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        end = pos + 8 + length
        if end + 4 > len(data) or struct.unpack(">I", data[end:end + 4])[0] != zlib.crc32(data[pos + 4:end]):
            return False
        kinds.append(kind)
        pos = end + 4
    return pos == len(data) and kinds[:1] == [b"IHDR"] and kinds[-1:] == [b"IEND"] and b"IDAT" in kinds


def glb_ok(data):
    """True for a glTF binary: the 12-byte header (magic, version 2, total length) and a JSON chunk first."""
    if len(data) < 20 or data[:4] != b"glTF":
        return False
    version, length = struct.unpack("<II", data[4:12])
    return version == 2 and length == len(data) and data[16:20] == b"JSON"


def glb_points(data):
    """The vertices of a glTF binary's meshes in the model's own space (the node transforms applied, +Y up, metres): a list of (x, y, z)."""
    json_length = struct.unpack("<I", data[12:16])[0]
    document = json.loads(data[20:20 + json_length])
    at = 20 + json_length
    binary = b""
    if at + 8 <= len(data):
        chunk_length, chunk_kind = struct.unpack("<II", data[at:at + 8])
        if chunk_kind == 0x004E4942:
            binary = data[at + 8:at + 8 + chunk_length]
    nodes = document.get("nodes", [])
    points = []

    def local(node):
        if "matrix" in node:
            m = node["matrix"]  # column major
            return [[m[0], m[4], m[8], m[12]], [m[1], m[5], m[9], m[13]], [m[2], m[6], m[10], m[14]], [0, 0, 0, 1]]
        x, y, z, w = node.get("rotation", [0, 0, 0, 1])
        sx, sy, sz = node.get("scale", [1, 1, 1])
        tx, ty, tz = node.get("translation", [0, 0, 0])
        rotation = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                    [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                    [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
        return [[rotation[0][0] * sx, rotation[0][1] * sy, rotation[0][2] * sz, tx],
                [rotation[1][0] * sx, rotation[1][1] * sy, rotation[1][2] * sz, ty],
                [rotation[2][0] * sx, rotation[2][1] * sy, rotation[2][2] * sz, tz], [0, 0, 0, 1]]

    def multiply(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]

    def positions(accessor_index):
        accessor = document["accessors"][accessor_index]
        view = document["bufferViews"][accessor["bufferView"]]
        start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        stride = view.get("byteStride", 12)
        return [struct.unpack_from("<fff", binary, start + i * stride) for i in range(accessor["count"])]

    def visit(index, parent):
        node = nodes[index]
        world = multiply(parent, local(node))
        if "mesh" in node:
            for primitive in document["meshes"][node["mesh"]]["primitives"]:
                for x, y, z in positions(primitive["attributes"]["POSITION"]):
                    points.append((world[0][0] * x + world[0][1] * y + world[0][2] * z + world[0][3],
                                   world[1][0] * x + world[1][1] * y + world[1][2] * z + world[1][3],
                                   world[2][0] * x + world[2][1] * y + world[2][2] * z + world[2][3]))
        for child in node.get("children", []):
            visit(child, world)

    identity = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
    scene = document.get("scenes", [{}])[document.get("scene", 0)] if document.get("scenes") else {}
    for root in scene.get("nodes", range(len(nodes)) if not document.get("scenes") else []):
        visit(root, identity)
    return points


def hero_prop_problems(data):
    """What is wrong with a hero prop's geometry, as sentences that continue "<file> ...": no meshes, or tiers wider than the stand. The
    model is fitted the way the game does (docs/hero-prop.md): scaled evenly into HERO_BOX, its footprint centred, its bottom at 0."""
    try:
        points = glb_points(data)
    except (KeyError, IndexError, ValueError, struct.error, TypeError, RecursionError) as error:
        return [f"could not be read as a model with meshes ({type(error).__name__}); export it again from Blender as glTF Binary"]
    if not points:
        return ["has no meshes; the hero prop is a model with geometry"]
    xs, ys, zs = zip(*points)
    footprint, height = max(max(xs) - min(xs), max(zs) - min(zs)), max(ys) - min(ys)
    if footprint < 1e-4 or height < 1e-4:
        return ["has no size (flat or a single point); model it in metres, standing on y 0"]
    fit = min(HERO_BOX[0] / footprint, HERO_BOX[1] / height)
    centre = ((max(xs) + min(xs)) / 2, (max(zs) + min(zs)) / 2)
    tier_height = HERO_BOX[1] / len(HERO_TIER_RADII)
    worst = None
    for x, y, z in points:
        up = (y - min(ys)) * fit
        tier = min(len(HERO_TIER_RADII) - 1, max(0, int((up - 0.03) // tier_height)))
        allowed = HERO_TIER_RADII[tier] * HERO_SLACK[0] + HERO_SLACK[1]
        out = math.hypot(x - centre[0], z - centre[1]) * fit - allowed
        if out > 0 and (worst is None or out > worst[0]):
            worst = (out, up, out + allowed, allowed)
    if worst is not None:
        return [f"leaves the stand: {worst[2]:.2f} m from the middle at {worst[1]:.2f} m up, where the tier allows {worst[3]:.2f} m "
                f"(the box is {HERO_BOX[0]:g} x {HERO_BOX[1]:g} m: tiers {', '.join(f'{r:g}' for r in HERO_TIER_RADII)} m of radius; docs/hero-prop.md)"]
    return []


def image_size(data):
    """(width, height) of PNG, JPEG or WebP bytes, None when unknown."""
    if data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) >= 24:
        return struct.unpack(">II", data[16:24])
    if data[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF:
                return None
            marker, length = data[i + 1], struct.unpack(">H", data[i + 2:i + 4])[0]
            if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                height, width = struct.unpack(">HH", data[i + 5:i + 9])
                return width, height
            i += 2 + length
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP" and len(data) >= 30:
        chunk = data[12:16]
        if chunk == b"VP8 ":
            width, height = struct.unpack("<HH", data[26:30])
            return width & 0x3FFF, height & 0x3FFF
        if chunk == b"VP8L":
            bits = int.from_bytes(data[21:25], "little")
            return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
        if chunk == b"VP8X":
            return int.from_bytes(data[24:27], "little") + 1, int.from_bytes(data[27:30], "little") + 1
    return None


def vorbis_seconds(data):
    """Length in seconds of an Ogg Vorbis file (last page's sample position / the sample rate), None when it is not one."""
    if data[:4] != b"OggS":
        return None
    header = data.find(b"\x01vorbis")
    if header < 0 or header + 16 > len(data):
        return None
    rate = struct.unpack("<I", data[header + 12:header + 16])[0]
    last = data.rfind(b"OggS")
    if rate <= 0 or last + 14 > len(data):
        return None
    return struct.unpack("<q", data[last + 6:last + 14])[0] / rate


def vorbis_channels(data):
    """Channels of an Ogg Vorbis file (its identification header), 0 when unknown."""
    header = data.find(b"\x01vorbis")
    return data[header + 11] if 0 <= header and header + 12 <= len(data) else 0


def forbidden_names(folder):
    sys.path.insert(0, str(ROOT / "tools"))
    import clean_scan
    hits = []
    for path in sorted(p for p in folder.rglob("*") if p.is_file() and p.name not in ALWAYS_SKIPPED_NAMES):
        clean_scan.scan_name(rel(path), rel(path), hits)
        if path.suffix.lower() in (".json", ".txt", ".md"):
            clean_scan.scan_bytes(path.read_bytes(), rel(path), hits, cast_text=path.name == "cast.json" and path.parent == folder)
    return [f"forbidden name: {hit}" for hit in hits]


# ------------------------------------------------------------------ guard
def ignore_rules(root):
    """(base, pattern) pairs from the template's .gitignore files, read the simple way git does for these files."""
    rules = []
    for ignore in sorted(root.rglob(".gitignore")):
        if any(part in ALWAYS_SKIPPED_DIRS for part in ignore.relative_to(root).parts):
            continue
        base = ignore.parent.relative_to(root).as_posix()
        base = "" if base == "." else base + "/"
        for line in ignore.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and not line.startswith("!"):
                rules.append((base, line))
    return rules


def ignored(path, rules):
    for base, pattern in rules:
        if base and not path.startswith(base):
            continue
        local = path[len(base):]
        directory = pattern.endswith("/")
        body = pattern.rstrip("/")
        if body.startswith("**/"):
            body = body[3:]
            anchored = False
        else:
            anchored = "/" in body
            body = body.lstrip("/")
        parts = local.split("/")
        if anchored:
            prefixes = ["/".join(parts[:n]) for n in range(1, len(parts) + 1)]
            if any(fnmatch.fnmatchcase(p, body) for p in (prefixes[:-1] if directory else prefixes)):
                return True
        else:
            names = parts[:-1] if directory else parts
            if any(fnmatch.fnmatchcase(name, body) for name in names):
                return True
    return False


def template_files(root=ROOT):
    """Every template file (repo-relative, posix) that the guard locks: all of it except demo/cast/ and ignored files."""
    rules = ignore_rules(root)
    files = []
    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if any(part in ALWAYS_SKIPPED_DIRS for part in relative.parts) or not path.is_file():
            continue
        name = relative.as_posix()
        if path.name in ALWAYS_SKIPPED_NAMES or name.startswith(CAST_DIR) or ignored(name, rules):
            continue
        files.append(name)
    return sorted(files)


# The engine stamps its own version into project.godot on every editor run or export; that line is not the template's.
ENGINE_STAMPED = {"demo/project.godot": re.compile(rb"^version=\"[^\"]*\"\r?\n", re.M)}


def digest(path, root=ROOT):
    data = path.read_bytes()
    stamp = ENGINE_STAMPED.get(path.relative_to(root).as_posix())
    if stamp is not None:
        data = stamp.sub(b"", data)
    return hashlib.sha256(data).hexdigest()


def lock(root=ROOT, lock_file=LOCK_FILE):
    files = {name: digest(root / name, root) for name in template_files(root) if (root / name) != lock_file}
    lock_file.write_text(json.dumps({"format": LOCK_FORMAT, "editable": [CAST_DIR], "files": files}, indent=1, sort_keys=True) + "\n")
    return len(files)


def check_guard(root=ROOT, lock_file=LOCK_FILE):
    if not lock_file.is_file():
        return []  # no lock recorded: the whole project is yours to change
    locked = json.loads(lock_file.read_text(encoding="utf-8")).get("files", {})
    present = set(template_files(root)) - {lock_file.relative_to(root).as_posix()}
    problems = []
    for name in sorted(set(locked) - present):
        problems.append(f"locked file removed: {name}")
    for name in sorted(present - set(locked)):
        problems.append(f"file added outside {CAST_DIR}: {name}")
    for name in sorted(present & set(locked)):
        if digest(root / name, root) != locked[name]:
            problems.append(f"locked file changed: {name}")
    return problems


def rel(path):
    try:
        return Path(path).resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--lock", action="store_true", help="template maintainers only: record every template file as locked")
    args = parser.parse_args()
    if args.lock:
        print(f"cast_check: locked {lock()} template files in {rel(LOCK_FILE)}")
        return 0
    cast_warnings = []
    cast_problems = check_cast(warnings=cast_warnings)
    guard_problems = check_guard()
    for line in cast_warnings:
        print(f"WARNING: {line}")
    for line in cast_problems:
        print(f"CAST: {line}")
    for line in guard_problems:
        print(f"LOCKED: {line}")
    if guard_problems:
        print(f"Only {CAST_DIR} may change. Put the change back (git checkout -- <file>, or copy it from the template) and do it in the cast instead.")
    ok = not cast_problems and not guard_problems
    print(f"cast_check: {'ok' if ok else 'FAILED'} ({len(cast_problems)} cast, {len(guard_problems)} locked-file problem(s), {len(cast_warnings)} warning(s))")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
