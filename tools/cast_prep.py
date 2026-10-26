#!/usr/bin/env python3
"""Cast prep: key the plain background out of the cast's logo-like pictures, so they sit on the game without a visible square.

    python3 tools/cast_prep.py                       # prepares demo/cast
    python3 tools/cast_prep.py --cast samples/acme   # another cast folder
    python3 tools/cast_prep.py --also mascot.png,badge.jpg   # more pictures of the cast folder

Sources: brand.logo and balloon.picture of cast.json, a goal_sign.png|.jpg|.jpeg|.webp in the cast folder, and --also. For each one the
engine (headless, tools/cast_prep.gd) either flood-fills the edge colour away with a soft edge and writes <cast>/prepared/<name>.png
(the original stays), or skips it: "transparent" (already has a transparent border), "busy" (a photo or scene, not one flat colour),
"empty" (nothing would be left). <cast>/prepared/manifest.json records the result and the sha256 of every source; tools/cast_check.py
checks it and the game loads the prepared picture instead of the original. Same input bytes give the same output bytes. Prepared
files whose source is gone are deleted. tools/ship.py runs this on demo/cast; the build tools run it on their disposable copy.

Engine: $SUMMER (default /Applications/Summer Engine.app/Contents/MacOS/Summer, else the older Summer app); $SUMMER_RUN is an optional
command prefix (a process guard, an engine slot). The last line is `cast_prep: ok (keyed=<n> skipped=<n>)` or `cast_prep: FAILED: <why>`."""
import argparse
import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "tools" / "cast_prep.gd"
ENGINES = ("/Applications/Summer Engine.app/Contents/MacOS/Summer", "/Applications/Summer.app/Contents/MacOS/Summer")
DEFAULT_CAST = ROOT / "demo" / "cast"
TIMEOUT = 300
RESULT = re.compile(r"^CAST_PREP ok=(true|false) ?(.*)$")
ENGINE_ERROR = re.compile(r"(?m)^(?:SCRIPT ERROR:|Parse Error|ERROR: Can't run script|ERROR: Failed to load script)[^\n]*")


class CastPrepError(RuntimeError):
    """The engine run did not finish with `CAST_PREP ok=true`; the message says why."""


def engine_path():
    chosen = os.environ.get("SUMMER")
    if chosen:
        return chosen
    return next((path for path in ENGINES if Path(path).is_file()), ENGINES[0])


def prepare(cast_dir, also=(), engine=None, timeout=TIMEOUT):
    """Prepare one cast folder; returns {"keyed": n, "skipped": n}. Raises CastPrepError on any failure.

    The engine runs on an empty throw-away project (the script needs nothing of a project and works on absolute paths), so a project that
    is being edited or not imported never matters, and nothing is written outside the cast folder."""
    cast_dir = Path(cast_dir).resolve()
    if not cast_dir.is_dir():
        raise CastPrepError(f"{cast_dir} is not a folder")
    arguments = [f"--cast={cast_dir}"]
    if also:
        arguments.append("--also=" + ",".join(also))
    with tempfile.TemporaryDirectory(prefix="cast-prep-") as project:
        (Path(project) / "project.godot").write_text('config_version=5\n\n[application]\nconfig/name="cast-prep"\n', encoding="utf-8")
        command = shlex.split(os.environ.get("SUMMER_RUN", "")) + [str(engine or engine_path()), "--headless", "--audio-driver", "Dummy",
                                                                    "--path", project, "-s", str(SCRIPT), "--"] + arguments
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            raise CastPrepError(f"the engine did not finish within {timeout} s") from None
        except FileNotFoundError as error:
            raise CastPrepError(f"cannot start the engine ({error}); set $SUMMER") from None
    output = result.stdout + result.stderr
    error = ENGINE_ERROR.search(output)
    if error:
        raise CastPrepError(f"engine error: {error.group(0)}")
    outcome = None
    for line in output.splitlines():
        found = RESULT.match(line)
        if found:
            outcome = found
    if outcome is None:
        raise CastPrepError(f"the engine printed no CAST_PREP result (exit {result.returncode}): {output[-500:].strip()}")
    if outcome.group(1) != "true" or result.returncode != 0:
        raise CastPrepError(outcome.group(2) or f"exit {result.returncode}")
    counts = dict(re.findall(r"(\w+)=(\d+)", outcome.group(2)))
    return {"keyed": int(counts["keyed"]), "skipped": int(counts["skipped"])}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cast", default=str(DEFAULT_CAST), help="the cast folder (default demo/cast)")
    parser.add_argument("--also", default="", help="more picture file names of the cast folder to prepare, comma separated")
    options = parser.parse_args()
    try:
        counts = prepare(options.cast, [name for name in options.also.split(",") if name.strip()])
    except CastPrepError as error:
        print(f"cast_prep: FAILED: {error}")
        return 1
    print(f"cast_prep: ok (keyed={counts['keyed']} skipped={counts['skipped']})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
