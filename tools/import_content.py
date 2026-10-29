"""Prepare a PRIVATE external content cache using the existing port's converter output.

This migration adapter is deliberately not a standalone raw-game converter. It
requires the user's existing port workspace and a matching game installation.
Neither the resulting cache nor the legacy workspace belongs in an engine release.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import uuid

SCHEMA = 1
REQUIRED = ('assets/indexed/manifest.json', 'assets/indexed/fonts.json',
            'assets/indexed/font_masks.bin', 'assets/cp949.json',
            'fixtures/item.dat', 'fixtures/magic.dat', 'fixtures/race.dat',
            'data/port_ready/maps/index.json', 'data/port_ready/tables/stages.json',
            'data/port_ready/scripts/spec/runtime_bindings.json')


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def case_file(root, relative):
    path = Path(root)
    for part in Path(relative).parts:
        matches = [p for p in path.iterdir() if p.name.casefold() == part.casefold()]
        if len(matches) != 1:
            raise ValueError(f'Missing or ambiguous installation file: {relative}')
        path = matches[0]
        if path.is_symlink():
            raise ValueError(f'Installation links are unsupported: {relative}')
    return path


def source_identity(source, legacy):
    game = legacy / 'game'
    signatures = {}
    for name in ('item', 'magic', 'race'):
        path = case_file(source, f'DATA/{name.upper()}.DAT')
        if sha(path) != sha(game / f'fixtures/{name}.dat'):
            raise ValueError(f'Unsupported edition or modified base {name}.dat; use mods for changes')
        signatures[f'DATA/{name.upper()}.DAT'] = sha(path)
    evidence = json.loads((game / 'runtime/data/port_ready/effects/source_index.json').read_text(encoding='utf-8'))
    exe = case_file(source, 'FTO_O.EXE')
    if sha(exe) != evidence['source_sha256']:
        raise ValueError('This migration cache does not match the selected FTO_O.EXE edition')
    signatures['FTO_O.EXE'] = sha(exe)
    manifest = json.loads((game / 'assets/indexed/manifest.json').read_text(encoding='utf-8'))
    # Verify every decoded image and APD against the selected installation.
    for relative, record in manifest['images'].items():
        if sha(case_file(source, relative)) != record['source_sha256']:
            raise ValueError(f'Selected installation differs from converted image: {relative}')
    for stem, relative in manifest['apds'].items():
        record = json.loads((game / relative.removeprefix('res://')).read_text(encoding='utf-8'))
        if sha(case_file(source, f'SPRITE/{stem}.APD')) != record['source_sha256']:
            raise ValueError(f'Selected installation differs from converted APD: {stem}')
    # Bind the cache to all installation files; this is identity, not a purchase check.
    for path in sorted(source.rglob('*')):
        if path.is_file():
            if path.is_symlink():
                raise ValueError(f'Installation links are unsupported: {path.name}')
            signatures[path.relative_to(source).as_posix()] = sha(path)
    inventory_path = legacy / 'data/port_ready/source_inventory.json'
    inventory = json.loads(inventory_path.read_text(encoding='utf-8'))
    actual = {name.casefold():value for name,value in signatures.items()}
    for row in inventory['files']:
        relative = row['path']
        # These directories feed the migrated cache, including its save bindings.
        if relative.split('/')[0].upper() not in ('DATA','MAP','BMP','SPRITE','WAVE','MIDI','SAVE') and relative.upper() != 'FTO_O.EXE':
            continue
        if actual.get(relative.casefold()) != row['sha256']:
            raise ValueError(f'Existing conversion output does not match selected installation: {relative}')
    key = hashlib.sha256(json.dumps(signatures, sort_keys=True).encode()).hexdigest()[:24]
    return key, signatures


def content_inputs(legacy):
    game = legacy / 'game'
    inputs = {}
    for folder in ('assets', 'fixtures', 'runtime'):
        for path in (game / folder).rglob('*'):
            if not path.is_file() or path.name.startswith('.') or path.suffix in ('.import', '.uid', '.log'):
                continue
            relative = path.relative_to(game / 'runtime') if folder == 'runtime' else path.relative_to(game)
            if path.suffix.lower() not in ('.json', '.bin', '.idx', '.pal', '.dat', '.wav', '.mid', '.sf2'):
                continue
            if path.is_symlink():
                raise ValueError(f'Legacy content symlink unsupported: {path}')
            key = relative.as_posix()
            if key in inputs:
                raise ValueError(f'Ambiguous content path: {key}')
            inputs[key] = path
    missing = [key for key in REQUIRED if key not in inputs]
    if missing:
        raise ValueError(f'Incomplete legacy conversion output: {missing}')
    return inputs


def prepare(source, legacy, cache_parent):
    source, legacy, cache_parent = (Path(p).resolve() for p in (source, legacy, cache_parent))
    if cache_parent.is_relative_to(source) or cache_parent.is_relative_to(legacy):
        raise ValueError('Cache must be outside the installation and existing port workspace')
    inputs = content_inputs(legacy)
    key, signatures = source_identity(source, legacy)
    destination = cache_parent / key
    if destination.exists():
        verify(destination)
        existing = json.loads((destination / 'content.json').read_text(encoding='utf-8'))
        if existing['source_files'] != signatures:
            raise ValueError('Existing cache belongs to a different installation')
        return {'status':'ready', 'reused':True, 'content_root':str(destination), 'source_root':str(source)}
    cache_parent.mkdir(parents=True, exist_ok=True)
    stage = cache_parent / ('.import-' + uuid.uuid4().hex)
    stage.mkdir()
    rows = []
    # No hardlinks: all edits and cache mutations remain independent of the port.
    for relative, original in sorted(inputs.items()):
        target = stage / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        before = sha(original)
        shutil.copyfile(original, target)
        if sha(original) != before or sha(target) != before:
            raise RuntimeError(f'Converter output changed during migration: {relative}; retry after its build finishes')
        rows.append({'path':relative, 'bytes':target.stat().st_size, 'sha256':before})
    # Selected installation must stay immutable throughout preparation.
    for relative, expected in signatures.items():
        if sha(case_file(source, relative)) != expected:
            raise RuntimeError(f'Installation changed during preparation: {relative}')
    document = {'schema':SCHEMA, 'status':'ready', 'content_id':key,
                'adapter':'legacy-port-migration-v1', 'redistributable':False,
                'source_root':str(source), 'source_files':signatures, 'required':list(REQUIRED),
                'files':rows, 'bytes':sum(row['bytes'] for row in rows)}
    (stage / 'content.json').write_text(json.dumps(document, ensure_ascii=False, indent=2), encoding='utf-8')
    os.replace(stage, destination)
    return {'status':'ready', 'reused':False, 'content_root':str(destination),
            'source_root':str(source), 'files':len(rows), 'bytes':document['bytes']}


def verify(root):
    root = Path(root).resolve()
    document = json.loads((root / 'content.json').read_text(encoding='utf-8'))
    if document.get('schema') != SCHEMA or document.get('status') != 'ready':
        raise ValueError('Invalid or incomplete cache manifest')
    rows = {row['path']:row for row in document['files']}
    if any(name not in rows for name in REQUIRED):
        raise ValueError('Required cache entries missing')
    for name, row in rows.items():
        path = (root / name).resolve()
        if not path.is_relative_to(root) or path == root or not path.is_file():
            raise ValueError(f'Unsafe or missing cache entry: {name}')
        if path.stat().st_size != row['bytes'] or sha(path) != row['sha256']:
            raise ValueError(f'Corrupt cache entry: {name}')
    return {'status':'verified', 'files':len(rows), 'content_id':document['content_id']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--legacy-port', type=Path)
    parser.add_argument('--cache-parent', type=Path)
    parser.add_argument('--verify', type=Path)
    args = parser.parse_args()
    try:
        if args.verify:
            result = verify(args.verify)
        elif all((args.source, args.legacy_port, args.cache_parent)):
            result = prepare(args.source, args.legacy_port, args.cache_parent)
        else:
            parser.error('Use --verify or --source, --legacy-port, --cache-parent together')
        print(json.dumps(result, ensure_ascii=False))
    except Exception as error:
        print(json.dumps({'status':'error', 'error':str(error)}, ensure_ascii=False))
        raise SystemExit(1)
