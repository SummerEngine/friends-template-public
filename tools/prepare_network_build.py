#!/usr/bin/env python3
"""Prepare one disposable project clone; never exports, authenticates or uploads.

Default is an engine-free plan. --execute is a separate, coordinated engine job:
  0. prepare the clone's cast (tools/cast_prep.py: transparent logo, balloon and goal sign into cast/prepared/);
  1. prune the clone to what the entry scenes reach, lossless audio imports (tools/build_domain_graph.py);
  2. import, regenerate the network entry scenes and composition;
  3. write the domain graph, resource manifests, UID owners and export preset filters;
  4. import again, drop unreferenced code UID sidecars, write the final graph, compile both entries and run the analyzer for both profiles.
Every generator receives the selected project explicitly; ROOT/demo is rejected.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time

import build_domain_graph as graph
from cast_prep import prepare as prepare_cast
from prepare_audio_imports import prepare as prepare_audio_imports
from prune_unreferenced_graph_uids import prune as prune_graph_uids
from stage_build import project_snapshot

ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path(__file__).resolve().parent
ENGINE = Path('/Applications/Summer Engine.app/Contents/MacOS/Summer')
REQUIRED = ('project.godot', 'summer.build.json', 'world.json', 'runtime-manifest.json',
            'export_presets.cfg', 'network/game.gd', 'network/composition.tres', 'client/main.gd', 'client/main.tscn',
            'authority/main.gd', 'authority/main.tscn')
TOOL_FILES = ('prepare_network_build.py', 'cast_prep.py', 'cast_prep.gd', 'build_network.gd', 'check_network_build.gd', 'build_domain_graph.py',
              'prepare_audio_imports.py', 'prune_unreferenced_graph_uids.py')


def validate_project(value):
    project = Path(value).resolve(strict=True)
    live = (ROOT / 'demo').resolve()
    if project == live or live in project.parents or project in live.parents:
        raise ValueError('Select a disposable clone outside live ROOT/demo')
    if not project.is_dir():
        raise ValueError('Project must be a directory')
    for name in REQUIRED:
        if not (project / name).is_file():
            raise ValueError('Missing preparation input: ' + name)
    # Importers and generators write sidecars. A symlinked cache or asset folder
    # can otherwise mutate a historical candidate even with an explicit --path.
    for path in project.rglob('*'):
        if path.is_symlink():
            raise ValueError('Clone must not contain symlinks: ' + str(path))
        if path.is_file() and path.stat().st_nlink > 1:
            raise ValueError('Use APFS clonefile, not hardlinks: ' + str(path))
    return project


def protocol(project):
    value = json.loads((project / 'summer.build.json').read_text())['runtime']['protocolVersion']
    if not isinstance(value, str) or not value:
        raise ValueError('Missing build runtime.protocolVersion')
    return value


def commands(project, engine):
    base = [str(engine), '--headless', '--audio-driver', 'Dummy', '--path', str(project)]
    return {
        'initial_import': base + ['--editor', '--import'],
        'network': base + ['--script', str(TOOLS / 'build_network.gd')],
        'canonical_import': base + ['--editor', '--import'],
        'analyzers': base + ['--script', str(TOOLS / 'check_network_build.gd')],
    }


def file_sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


# Harmless cloud call the engine makes at shutdown (seen 19.10 on every binary): its failed TLS handshake is not a build error.
ENGINE_SHUTDOWN_TLS = re.compile(r'(?m)^ERROR: TLS handshake error: -?\d+\n(?:   at: [^\n]*\n)?(?:mbedtls error: [^\n]*\n)?')


def run_step(name, command, directory, timeout):
    log = directory / (name + '.log')
    started = time.monotonic()
    with log.open('w') as output:
        result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=timeout, check=False)
    text = log.read_text()
    if result.returncode or re.search(r'(?m)^(?:SCRIPT ERROR:|ERROR:)', ENGINE_SHUTDOWN_TLS.sub('', text)):
        raise RuntimeError(f'{name} failed (exit {result.returncode}); inspect {log}')
    return {'command': command, 'exit_code': result.returncode,
            'seconds': time.monotonic() - started, 'log': str(log), 'output': text}


def analyzer_result(output, expected_protocol):
    lines = [line.removeprefix('GW_BUILD_CHECK ') for line in output.splitlines()
             if line.startswith('GW_BUILD_CHECK ')]
    if len(lines) != 1:
        raise ValueError('Build checker did not emit exactly one result')
    report = json.loads(lines[0])
    if (not report.get('passed') or report.get('protocol') != expected_protocol
            or len(report.get('profiles', [])) != 2
            or {row.get('profile') for row in report['profiles']} != {0, 1}
            or report.get('failures')
            or any(not row.get('ok') or row.get('diagnostics') for row in report['profiles'])):
        raise ValueError('Compilation/composition/domain graph checks failed')
    return report


def execute(project, engine, receipt, timeout=300):
    # Revalidate immediately before any write or engine launch.
    project = validate_project(project)
    expected = protocol(project)
    if receipt.resolve().is_relative_to(project):
        raise ValueError('Keep preparation receipts/logs outside the project input fence')
    receipt.parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='prepare-', dir=receipt.parent))
    report = {'passed': False, 'project': str(project), 'scope': 'Clone preparation only; no export/runtime/SDK/publication proof',
              'protocol': expected, 'log_directory': str(work), 'steps': {},
              'engine_sha256': file_sha(engine), 'tool_sha256': {name: file_sha(TOOLS / name) for name in TOOL_FILES}}
    try:
        steps = commands(project, engine)
        if (project / 'cast' / 'cast.json').is_file():
            report['cast_prep'] = prepare_cast(project / 'cast', engine=engine)
        report['pruning'] = graph.prepare_clone(project)['pruned']
        report['audio_imports'] = prepare_audio_imports(project)
        before = project_snapshot(project)
        report['inputs_before'] = before
        for name in ('initial_import', 'network'):
            report['steps'][name] = run_step(name, steps[name], work, timeout)
        graph.generate(project)
        report['steps']['canonical_import'] = run_step('canonical_import', steps['canonical_import'], work, timeout)
        report['unreferenced_code_uid_pruning'] = prune_graph_uids(project)
        report['graph'] = graph.generate(project)  # the final graph lists exactly the files that are left
        report['steps']['analyzers'] = run_step('analyzers', steps['analyzers'], work, timeout)
        report['analyzer_check'] = analyzer_result(report['steps']['analyzers']['output'], expected)
        if any(file_sha(TOOLS / name) != value for name, value in report['tool_sha256'].items()):
            raise RuntimeError('Preparation tool inputs changed during execution; retain logs and retry on stable tools')
        after = project_snapshot(project)
        report['inputs_after'] = after
        report['changed_inputs'] = {name: {'before': before.get(name), 'after': after.get(name)}
                                    for name in sorted(before.keys() | after.keys()) if before.get(name) != after.get(name)}
        report['inputs_sha256'] = hashlib.sha256(json.dumps(after, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        report['passed'] = True
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        # Logs remain the complete source; keep the JSON receipt concise.
        for step in report['steps'].values():
            step.pop('output', None)
        receipt.write_text(json.dumps(report, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--engine', type=Path, default=ENGINE)
    parser.add_argument('--receipt', type=Path)
    parser.add_argument('--execute', action='store_true', help='Run coordinated headless import/compile/analyzer preparation (never export)')
    parser.add_argument('--timeout', type=float, default=300, help='Positive per-engine-step watchdog in seconds')
    args = parser.parse_args()
    try:
        project = validate_project(args.project)
        if args.timeout <= 0:
            raise ValueError('timeout must be positive')
        if args.execute:
            if args.receipt is None:
                raise ValueError('--execute requires --receipt outside project')
            report = execute(project, args.engine.resolve(), args.receipt.resolve(), args.timeout)
            print(json.dumps({k: v for k, v in report.items() if k not in ('inputs_before', 'inputs_after', 'changed_inputs', 'steps')}, indent=2))
        else:
            print(json.dumps({'executed': False, 'project': str(project), 'protocol': protocol(project),
                              'engine_steps': commands(project, args.engine),
                              'python_steps': ['cast_prep.prepare(selected_clone/cast)',
                                               'build_domain_graph.prepare_clone(selected_clone)',
                                               'prepare_audio_imports.prepare(selected_clone)',
                                               'build_domain_graph.generate(selected_clone)'],
                              'scope': 'Plan only: no writes, engines, export or upload'}, indent=2))
    except (OSError, ValueError, RuntimeError, graph.GraphError, subprocess.TimeoutExpired) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
