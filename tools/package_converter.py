"""Copy only standalone converter code and its documentation into a release."""
from pathlib import Path
import hashlib
import shutil
import json


def copy_converter_payload(root: Path, destination: Path) -> list[dict]:
    root, destination = Path(root).resolve(), Path(destination).resolve()
    sources = [root/'tools/convert_installation.py', root/'tools/import_content.py',
               root/'tools/editor_mcp.py',
               root/'requirements.txt',root/'COPYING-converter',root/'CONVERTER_LICENSE.json',
               root/'LICENSING.md',root/'THIRD_PARTY_NOTICES.md',root/'EXAMPLES_LICENSE',root/'CONTRIBUTING.md']
    sources += [root/'docs'/name for name in ('usage-guide.md',
                                             'MODDING.md','FORMATS.md','ASSET_POLICY.md',
                                             'EXPANSION_EDITOR.md','EXTENSION_RUNTIME_CONTRACT.md','EDITOR_DESIGN.md',
                                             'EDITOR_MCP.md','EDITOR_MCP_CLIENTS.md')]
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
    # Remove only retired tutorial outputs from a reused build tree.
    # Signed Mac release archives are rebuilt/re-signed by the normal Mac build.
    for name in ('usage-guide.gif','usage-guide-mac.gif','usage-guide.mp4','usage-guide-mac.mp4','usage-guide.json'):
        legacy=destination/'docs'/name
        if legacy.exists():
            if legacy.is_symlink()or not legacy.resolve().is_relative_to(destination)or not legacy.is_file():
                raise ValueError('Unsafe retired tutorial path: '+str(legacy))
            legacy.unlink()
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
    bundle=tools/'ft2-convert'
    if bundle.is_dir():
        marker=bundle/'converter_build_result.json'
        stamp=bundle/'_internal/converter_build.json'
        if not marker.is_file()or not stamp.is_file():raise ValueError('Bundled converter is incomplete')
        report=json.loads(marker.read_text(encoding='utf-8'))
        identity=json.loads(stamp.read_text(encoding='utf-8'))
        if report.get('kind')!='standalone-converter-binary' or report.get('original_game_data_included')is not False or report.get('requires_python_installation')is not False or report.get('pipeline_sha256')!=identity.get('pipeline_sha256'):
            raise ValueError('Bundled converter identity/scope does not match its build record')
        pipeline_files=[root/'tools/convert_installation.py',root/'tools/import_content.py',
                        root/'tools/converters/font_charset.json',
                        *sorted((root/'tools/converters').rglob('*.py'))]
        pipeline_rows=[(path.relative_to(root/'tools').as_posix(),hashlib.sha256(path.read_bytes()).hexdigest())
                       for path in pipeline_files if not path.name.startswith('test_')]
        current=hashlib.sha256(json.dumps(pipeline_rows,sort_keys=True).encode()).hexdigest()
        if identity.get('pipeline_sha256')!=current:
            raise ValueError('Bundled converter is stale; rebuild it from the current converter sources')
        if report.get('editor_mcp_included')is not True or identity.get('editor_mcp_source_sha256')!=hashlib.sha256((root/'tools/editor_mcp.py').read_bytes()).hexdigest():
            raise ValueError('Bundled editor MCP server is missing or stale; rebuild the standalone tools')
    for path in tools.rglob('*'):
        if bundle.is_dir()and path.is_relative_to(bundle):continue
        if path.is_file() and path.relative_to(destination).as_posix() not in expected:
            raise ValueError('Unexpected file in converter release payload: '+str(path))
    return rows
