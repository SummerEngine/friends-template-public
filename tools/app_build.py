"""Shared steps of the two standalone Mac apps (tools/build_levels_game.py, tools/build_solo_levels.py).

Local only: never uploads, no Android package. Freeze (APFS clone of demo/, pruned to what the entry reaches; the clone's cast is prepared
by tools/cast_prep.py, so the pack holds cast/prepared/*) -> import -> export-pack ->
check the pack against the generated domain graph -> app bundle from the official player template -> ad-hoc sign -> headless boot check.
Run the whole script inside one engine slot:  FRIENDS_PRIORITY=1 tools/engine_slot.sh python3 tools/build_levels_game.py --output build/<new dir>
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import zipfile

import build_domain_graph as graph
from cast_prep import prepare as prepare_cast
from audit_staged_pack import expectations
from prepare_audio_imports import prepare as prepare_audio_imports
from stage_build import pack_entries, pack_has, project_snapshot

ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path('/Applications/Summer Engine.app/Contents/MacOS/Summer')  # --engine for another install
ENGINE_SHA = '2e8baaffc5d0853180e3e33e49c35a7b876491087ff0c9e27c6e2a4a7bb6fcd8'
PLAYER_SHA = '0b3732af78c5c68fcfd28fbfeabd99e5cd27c4ed2ca453cd0c2ab56d47fa0c77'
EXCLUDES = 'authority/*,*_probe.gd,build_scene.gd,*.py,*.md,*.bak,__pycache__/*,*/_ref/*'
BOOT_FRAMES = 240
BOOT_ERRORS = re.compile(r'(?m)^(?:SCRIPT ERROR:|ERROR:)|Parse Error')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def engine_errors(text):
    """Error lines of an engine log; the failed TLS handshake and the script-destructor note the engine prints at shutdown are not errors."""
    # Two harmless engine messages at shutdown: the failed TLS handshake (an account check) and a script-function destructor note.
    harmless = ('TLS handshake', 'Parameter "script" is null', 'resources still in use at exit', 'leaked at exit', 'Pages in use exist at exit')  # exit-time reports of the static caches (meshes, materials, fonts) the looks keep for the whole run
    return BOOT_ERRORS.findall('\n'.join(line for line in text.splitlines() if not any(mark in line for mark in harmless)))


def run(command, log, timeout=900):
    with log.open('w') as output:
        process = subprocess.run([str(x) for x in command], stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
    if process.returncode or engine_errors(log.read_text(errors='replace')):
        raise RuntimeError(f'Build step failed ({process.returncode}); inspect {log}')


def boot_check(binary, log, timeout=120):
    """Start the exported app headless for a few frames; any script or load error fails the build."""
    with log.open('w') as output:
        process = subprocess.run([str(binary), '--headless', '--audio-driver', 'Dummy', '--quit-after', str(BOOT_FRAMES)],
                                 stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
    text = log.read_text(errors='replace')
    errors = engine_errors(text)
    if process.returncode or errors:
        raise RuntimeError(f'Exported app failed its headless boot check ({process.returncode}, {len(errors)} error lines); inspect {log}')
    return {'frames': BOOT_FRAMES, 'script_errors': 0, 'log': str(log)}


def build(*, name, identity, entry, executable, tag, description, cast=None):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('--engine', type=Path, default=ENGINE)
    parser.add_argument('--project', type=Path, default=ROOT / 'demo')
    parser.add_argument('--output', type=Path, required=True, help='New output directory; refuses overwrite')
    parser.add_argument('--cast', type=Path, default=cast, help='A cast directory (cast.json and its pictures) the freeze wears instead of demo/cast/; demo/ is never changed')
    args = parser.parse_args()
    engine = args.engine.resolve(strict=True)
    assert sha(engine) == ENGINE_SHA, 'Requires the verified installed Summer 0.7.3 exporter (ENGINE_SHA)'
    assert (args.project / 'levels/level_01.json').is_file(), 'The level files demo/levels/level_NN.json are missing'
    entry_file = entry.removeprefix('res://')
    assert (args.project / entry_file).is_file(), f'Entry scene missing: {entry_file}'
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    project = args.output / 'project'
    before = project_snapshot(args.project)
    subprocess.run(['cp', '-cR', str(args.project.resolve()), str(project)], check=True)
    assert before == project_snapshot(project) == project_snapshot(args.project), 'Source changed during freeze; use a new output directory'
    if args.cast is not None:  # the freeze wears another cast; the source's own cast stays as it is
        assert (args.cast / 'cast.json').is_file(), f'No cast.json in {args.cast}'
        shutil.rmtree(project / 'cast')
        subprocess.run(['cp', '-cR', str(args.cast.resolve()), str(project / 'cast')], check=True)
    # The logo, balloon and goal sign lose their plain background (cast/prepared/*, tools/cast_prep.py) in the clone's cast, before the import.
    cast_prep = prepare_cast(project / 'cast', engine=engine)
    # A distinct standalone identity and main scene on every runtime feature.
    config = project / 'project.godot'
    text = config.read_text()
    text = re.sub(r'^config/name=.*$', f'config/name="{name}"', text, flags=re.M)
    text = re.sub(r'^run/main_scene(?:\.[^=]+)?=.*$', f'run/main_scene="{entry}"', text, flags=re.M)
    text = re.sub(r'(?m)^(run/main_scene=.*)(?:\n\1)+', r'\1', text)
    text = text.replace('[application]\n', f'[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="{name}"\n')
    config.write_text(text)
    # Keep what the entry scene reaches (roles, kit models, manifests); the graph is regenerated for the pruned clone.
    pruning = graph.prepare_clone(project, client_entries=[entry_file])
    prepare_audio_imports(project)  # music and effects must not acquire the default lossy QOA import
    presets = (f'[preset.0]\nname="{name} macOS"\nplatform="macOS"\nrunnable=false\ndedicated_server=false\ncustom_features=""\n'
               'export_filter="all_resources"\ninclude_filter="*.json,assets/fonts/*-OFL.txt"\n'
               f'exclude_filter={json.dumps(EXCLUDES)}\nexport_path=""\nencrypt_pck=false\nencrypt_directory=false\nscript_export_mode=2\n\n'
               '[preset.0.options]\nbinary_format/architecture="universal"\ncodesign/codesign=0\n')
    (project / 'export_presets.cfg').write_text(presets)
    base = [engine, '--headless', '--audio-driver', 'Dummy', '--path', project]
    run(base + ['--editor', '--import'], args.output / 'import.log')
    frozen = project_snapshot(project)
    pck = args.output / f'{executable}.pck'
    run(base + ['--export-pack', f'{name} macOS', pck], args.output / 'export-macos.log')
    assert frozen == project_snapshot(project), 'Frozen inputs changed during export'
    pack_data = pck.read_bytes()
    entries = pack_entries(pack_data)
    both, client_only, authority_only, presentation = expectations(project)
    required = sorted({*both, *client_only, *presentation} - {graph.SHARED_MANIFEST, graph.CLIENT_MANIFEST, graph.AUTHORITY_MANIFEST})
    missing = [resource for resource in [entry_file, *required] if not pack_has(pack_data, entries, resource)]
    assert not missing, f'Missing resources in the pack ({len(missing)}): {missing[:8]}'
    assert not any(n.endswith(('_probe.gd', '_probe.gd.remap')) for n in entries)
    assert not any(n.startswith('authority/') for n in entries), 'Standalone app must exclude the authority scripts'
    template = engine.parents[1] / 'Resources/export_templates/4.7.2.stable/macos.zip'
    app = args.output / f'{name}.app'
    binary = app / f'Contents/MacOS/{executable}'
    resources = app / 'Contents/Resources'
    binary.parent.mkdir(parents=True)
    resources.mkdir(parents=True)
    with zipfile.ZipFile(template) as archive:
        binary.write_bytes(archive.read('macos_template.app/Contents/MacOS/godot_macos_release.universal'))
    player_before_sign = sha(binary)
    assert player_before_sign == PLAYER_SHA, 'Mac template differs from the installed Summer 0.7.3 player (PLAYER_SHA)'
    binary.chmod(0o755)
    subprocess.run(['cp', '-c', str(pck), str(resources / pck.name)], check=True)
    commit = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', '--short', 'HEAD'], stdout=subprocess.PIPE, text=True).stdout.strip() or 'unknown'
    with (app / 'Contents/Info.plist').open('wb') as stream:
        plistlib.dump({'CFBundleName': name, 'CFBundleDisplayName': name, 'CFBundleIdentifier': identity, 'CFBundleVersion': '1',
                       'CFBundleShortVersionString': f'{tag}-{commit}', 'CFBundleExecutable': binary.name,
                       'CFBundlePackageType': 'APPL', 'NSHighResolutionCapable': True, 'LSMinimumSystemVersion': '13.0'}, stream)
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', '--identifier', identity, str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    boot = boot_check(binary, args.output / 'boot-check.log')
    receipt = {'scope': 'local only (the staged build is the hosted one); package integrity and a headless boot, not gameplay acceptance',
               'app': str(app), 'pck': str(pck), 'project': str(project), 'entry': entry, 'identity': identity, 'cast': str(args.cast) if args.cast else 'demo/cast',
               'cast_prep': cast_prep, 'engine_sha256': sha(engine), 'template_sha256': sha(template),
               'player_unsigned_sha256': player_before_sign, 'player_signed_sha256': sha(binary),
               'pck_sha256': sha(pck), 'pck_bytes': pck.stat().st_size, 'pck_entries': len(entries), 'required_resources': len(required),
               'pruning': pruning, 'boot_check': boot, 'inputs_before_freeze': before, 'frozen_inputs': frozen}
    (args.output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({k: v for k, v in receipt.items() if k not in ('inputs_before_freeze', 'frozen_inputs', 'pruning')}, indent=2))
