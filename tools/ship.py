#!/usr/bin/env python3
"""One command from a finished cast to a playable build: `python3 tools/ship.py`.

Runs every step in order and stops at the first failure with the step's output:
  1. fonts   tools/cast_fonts.py (the cast's Japanese and Chinese letters into demo/cast/fonts/; nothing for other casts)
  2. prep    tools/cast_prep.py (the logo, balloon and goal sign lose their plain background: demo/cast/prepared/; the originals stay)
  3. cast    tools/cast_check.py (the cast is valid, nothing outside demo/cast/ changed)
  4. clean   tools/clean_scan.py --tree . (nothing that is not ours)
  5. import  the engine imports the project and the cast's files (needed on a fresh copy and after new pictures)
  6. engine  the in-engine cast check (tools/cast_runtime_check.gd), headless
  7. web     the Web export into build/web/
  8. link    the play link: today a local link (upload to Summer Games is pending)
The last line is always `SHIP ok=<true|false> step=<last step> link=<link or ->`.

Engine: $SUMMER (default /Applications/Summer Engine.app/Contents/MacOS/Summer). $SUMMER_RUN is an optional command prefix for the engine
(for example a process guard); it is split on spaces and put in front of the engine path."""
import argparse
import os
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ENGINE = "/Applications/Summer Engine.app/Contents/MacOS/Summer"
WEB_DIR = ROOT / "build" / "web"


def engine_command(args):
    engine = os.environ.get("SUMMER", DEFAULT_ENGINE)
    return shlex.split(os.environ.get("SUMMER_RUN", "")) + [engine, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "demo")] + args


def run(step, command, ok_text=None, timeout=900):
    print(f"SHIP step={step} ...", flush=True)
    try:
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f"SHIP step={step} timed out after {timeout} s")
        return False
    except FileNotFoundError as exc:
        print(f"SHIP step={step} cannot start: {exc}")
        return False
    output = result.stdout + result.stderr
    passed = result.returncode == 0 and (ok_text is None or ok_text in output)
    if not passed:
        print(output[-4000:])
        print(f"SHIP step={step} failed (exit {result.returncode})")
    return passed


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=8000, help="port of the local link (default 8000)")
    options = parser.parse_args()
    python = sys.executable or "python3"
    steps = [
        ("fonts", [python, "tools/cast_fonts.py"], "cast_fonts: ok"),
        ("prep", [python, "tools/cast_prep.py"], "cast_prep: ok"),
        ("cast", [python, "tools/cast_check.py"], "cast_check: ok"),
        ("clean", [python, "tools/clean_scan.py", "--tree", "."], "clean_scan: ok"),
        ("import", engine_command(["--import"]), None),
        ("engine", engine_command(["-s", str(ROOT / "tools" / "cast_runtime_check.gd")]), "CAST_RUNTIME_CHECK ok=true"),
        ("web", engine_command(["--export-release", "Web", str(WEB_DIR / "index.html")]), None),
    ]
    WEB_DIR.mkdir(parents=True, exist_ok=True)
    for step, command, ok_text in steps:
        if not run(step, command, ok_text):
            print(f"SHIP ok=false step={step} link=-")
            return 1
    for name in ("index.html", "index.pck", "index.wasm"):
        if not (WEB_DIR / name).is_file():
            print(f"SHIP step=web missing build/web/{name}")
            print("SHIP ok=false step=web link=-")
            return 1
    link = f"http://localhost:{options.port}/"
    print(f"SHIP step=link serve it with: (cd build/web && python3 -m http.server {options.port})")
    print("SHIP step=link upload to Summer Games is pending; until then the link is local and two players share one keyboard")
    print(f"SHIP ok=true step=link link={link}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
