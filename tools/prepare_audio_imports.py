#!/usr/bin/env python3
"""Keep the effect and music WAV imports lossless (no default QOA compression); reimport/export is a separate step."""
import argparse
import json
from pathlib import Path
import re

PROJECT = Path(__file__).resolve().parents[1] / 'demo'
FOLDERS = ('audio/music', 'audio/sfx')
OPTIONS = {'force/8_bit': 'false', 'force/mono': 'false', 'force/max_rate': 'false',
           'edit/trim': 'false', 'edit/normalize': 'false', 'edit/loop_mode': '0',
           'compress/mode': '0'}


def prepare(project=PROJECT):
    changed = []
    waves = sorted(wave for folder in FOLDERS for wave in (project / folder).glob('*.wav'))
    for wave in waves:
        metadata = wave.with_suffix('.wav.import')
        previous = metadata.read_text() if metadata.exists() else ''
        text = previous or '[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n\n[params]\n'
        assert '[params]' in text and 'importer="wav"' in text, str(metadata)
        head, params = text.split('[params]', 1)
        assert not re.search(r'^\[', params, re.M), 'Unexpected WAV import section order'
        for option, value in OPTIONS.items():
            pattern = r'^' + re.escape(option) + r'=.*$'
            if re.search(pattern, params, re.M):
                params = re.sub(pattern, option + '=' + value, params, flags=re.M)
            else:
                params = params.rstrip() + '\n' + option + '=' + value + '\n'
        text = head + '[params]' + params
        if text != previous:
            temporary = metadata.with_suffix(metadata.suffix + '.tmp')
            temporary.write_text(text)
            temporary.replace(metadata)
            changed.append(str(metadata.relative_to(project)))
    return {'waves': len(waves), 'changed_import_configs': changed,
            'scope': 'Lossless import configuration only; reimport and export proof are separate'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', type=Path, default=PROJECT)
    args = parser.parse_args()
    print(json.dumps(prepare(args.project)))
