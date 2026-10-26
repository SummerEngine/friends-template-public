"""Drop unused code UID sidecars in a disposable clone, never asset UID owners.

The 0.7.x analyzer counts directory sidecars toward its 4096-file ceiling.
All source bytes (including binary resources) outside caches are searched before
removing a code/shader UID. Payloads and referenced UID identities are preserved.
"""
from pathlib import Path
import re


LIVE = Path(__file__).resolve().parents[1] / 'demo'
CODE = {'.gd', '.gdshader', '.gdshaderinc'}


def prune(project):
    project = Path(project).resolve(strict=True)
    if project == LIVE.resolve() or LIVE.resolve() in project.parents:
        raise ValueError('UID pruning requires a disposable clone outside demo')
    candidates = {path: path.read_text().strip() for path in project.rglob('*.uid')
                  if '.godot' not in path.parts and path.with_suffix('').suffix in CODE
                  and path.with_suffix('').is_file()}
    referenced = set()
    for path in project.rglob('*'):
        if (not path.is_file() or path.suffix == '.uid'
                or any(part in ('.godot', '.summer', '.git', '__pycache__') for part in path.relative_to(project).parts)):
            continue
        data = path.read_bytes()
        if path.suffix in ('.res', '.scn'):
            # Binary resources may store numeric UIDs instead of uid:// text: their references cannot be audited here.
            raise ValueError('Binary resource UID references need an engine audit before pruning: ' + str(path.relative_to(project)))
        referenced.update(token.decode() for token in re.findall(rb'uid://[a-z0-9]+', data))
    removed = []
    for path, uid in sorted(candidates.items()):
        if re.fullmatch(r'uid://[a-z0-9]+', uid) and uid not in referenced:
            removed.append({'path': str(path.relative_to(project)), 'uid': uid})
            path.unlink()
    return {'scope': 'Disposable clone only; unreferenced code/shader UID sidecars, never imported asset owners',
            'removed': removed, 'retained_referenced_code_uids': sum(uid in referenced for uid in candidates.values())}
