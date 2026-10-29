"""Copy only standalone converter code and its documentation into a release."""
from pathlib import Path
import hashlib
import shutil


def copy_converter_payload(root: Path, destination: Path) -> list[dict]:
    root, destination = Path(root).resolve(), Path(destination).resolve()
    sources = [root/'tools/convert_installation.py', root/'tools/import_content.py',
               root/'requirements.txt']
    for source in (root/'tools/converters').rglob('*'):
        if not source.is_file():continue
        relative = source.relative_to(root/'tools/converters')
        if any(part in ('__pycache__','tests','private') for part in relative.parts):continue
        if source.name.startswith(('test_','tests_')):continue
        if source.suffix == '.py' or source.name=='font_charset.json' or source.name.casefold().startswith(('readme','requirements')):
            sources.append(source)
    for source in sources:
        if not source.is_file() or source.is_symlink():
            raise ValueError('Missing or unsafe converter source: '+str(source))
    tools = destination/'tools'
    tools.mkdir(parents=True,exist_ok=True)
    # A prior local smoke test may have compiled Python caches in the output.
    # Remove only those named cache directories, after resolving their boundary.
    for cache in list(tools.rglob('__pycache__')):
        resolved = cache.resolve()
        if resolved == tools or not resolved.is_relative_to(tools.resolve()) or cache.is_symlink():
            raise ValueError('Unsafe build cache cleanup path: '+str(cache))
        if cache.is_dir():shutil.rmtree(cache)
    rows=[]
    for source in sorted(sources):
        relative = source.relative_to(root)
        target = destination/relative
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(source,target)
        rows.append({'path':relative.as_posix(),'bytes':target.stat().st_size,
                     'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
    expected={row['path'] for row in rows}
    for path in tools.rglob('*'):
        if path.is_file() and path.relative_to(destination).as_posix() not in expected:
            raise ValueError('Unexpected file in converter release payload: '+str(path))
    return rows
