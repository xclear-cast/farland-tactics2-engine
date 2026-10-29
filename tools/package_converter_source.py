"""Package the standalone converter's corresponding source without game data.

SPDX-License-Identifier: GPL-2.0-only
Run after the release source revision is frozen. Upload the resulting ZIP at the
same release location as every frozen converter binary that it accompanies.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.metadata
import json
import subprocess
import sys
import tarfile
import urllib.request
import zipfile

ROOT=Path(__file__).resolve().parents[1]
SOURCE_FILES={
    'COPYING-converter','CONVERTER_LICENSE.json','LICENSING.md','THIRD_PARTY_NOTICES.md','EXAMPLES_LICENSE',
    'requirements.txt','build-requirements.txt','tools/convert_installation.py',
    'tools/import_content.py','tools/build_converter_binary.py','tools/update_font_charset.py',
    'tools/package_converter_source.py',
}


def digest(path):
    with Path(path).open('rb')as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def fetch(url,target,expected=None):
    target=Path(target)
    if target.is_file()and(expected is None or digest(target)==expected):return target
    target.parent.mkdir(parents=True,exist_ok=True)
    request=urllib.request.Request(url,headers={'User-Agent':'FT2-converter-source-packager'})
    with urllib.request.urlopen(request,timeout=60)as response:raw=response.read()
    if expected and hashlib.sha256(raw).hexdigest()!=expected:raise ValueError('Source archive SHA-256 mismatch: '+target.name)
    target.write_bytes(raw)
    return target


def published_source(name,version,directory):
    url=f'https://pypi.org/pypi/{name}/{version}/json'
    with urllib.request.urlopen(url,timeout=30)as response:metadata=json.load(response)
    candidates=[item for item in metadata['urls']if item['packagetype']=='sdist']
    if len(candidates)!=1:raise ValueError('Expected one published source archive for '+name)
    artifact=candidates[0]
    path=fetch(artifact['url'],directory/artifact['filename'],artifact['digests']['sha256'])
    with tarfile.open(path,'r:*')as archive:
        names=archive.getnames()
        if name=='unicorn':
            if not any('/src/qemu/'in item for item in names)or not any(item.endswith('/src/CMakeLists.txt')for item in names):
                raise ValueError('Unicorn archive lacks the native core/build source')
        elif name=='pyinstaller':
            if not any(item.endswith('/bootloader/waf')for item in names)or not any(item.endswith('/COPYING.txt')for item in names):
                raise ValueError('PyInstaller archive lacks bootloader/build source')
    return path,{'name':name,'version':version,'source_url':artifact['url'],'sha256':digest(path),
                 'archive_file':artifact['filename'],'archive_entries':len(names)}


def requirements_version(filename,name):
    for line in (ROOT/filename).read_text(encoding='utf-8').splitlines():
        if line.casefold().startswith(name.casefold()+'=='):return line.split('==',1)[1].strip()
    raise ValueError('A pinned dependency version is required for '+name)


def dependency_records(names):
    records=[]
    for name in names:
        try:distribution=importlib.metadata.distribution(name)
        except importlib.metadata.PackageNotFoundError:continue
        native=[]
        for entry in distribution.files or []:
            if Path(entry.name).suffix.lower()not in ('.dll','.dylib','.so'):continue
            path=Path(distribution.locate_file(entry))
            if path.is_file():native.append({'path':entry.as_posix(),'sha256':digest(path)})
        records.append({'name':name,'version':distribution.version,'native_files':native})
    return records


def package(output):
    output=Path(output).resolve();output.mkdir(parents=True,exist_ok=True)
    scope=json.loads((ROOT/'CONVERTER_LICENSE.json').read_text(encoding='utf-8'))
    if scope.get('license')!='GPL-2.0-only':raise ValueError('Converter licence scope has not been declared')
    source_paths={ROOT/name for name in SOURCE_FILES}
    for path in (ROOT/'tools/converters').rglob('*'):
        if not path.is_file()or'__pycache__'in path.parts:continue
        if path.suffix=='.py'or path.name in ('README.md','requirements.txt','font_charset.json'):source_paths.add(path)
    for path in source_paths:
        if not path.is_file()or path.is_symlink()or not path.resolve().is_relative_to(ROOT):raise ValueError('Unsafe or missing converter source: '+path.name)
    dependencies=[];payload={}
    for name,version in [('unicorn',requirements_version('requirements.txt','unicorn')),
                         ('pyinstaller',requirements_version('build-requirements.txt','pyinstaller'))]:
        archive,record=published_source(name,version,output/'downloads')
        dependencies.append(record);payload[f'third_party/{name}/{archive.name}']=archive
    unicorn_version=dependencies[0]['version']
    for filename in ('COPYING','COPYING.LGPL2','COPYING_GLIB','README.md'):
        url=f'https://raw.githubusercontent.com/unicorn-engine/unicorn/{unicorn_version}/{filename}'
        path=fetch(url,output/'downloads/unicorn-notices'/filename)
        payload['third_party/unicorn/'+filename]=path
    try:revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True,stderr=subprocess.DEVNULL).strip()
    except(subprocess.CalledProcessError,FileNotFoundError):revision=None
    rows=[{'path':path.relative_to(ROOT).as_posix(),'bytes':path.stat().st_size,'sha256':digest(path)}for path in sorted(source_paths)]
    manifest={'schema':1,'component':'FT2 standalone installation converter','license':'GPL-2.0-only',
              'git_head_at_packaging':revision,'source_files':rows,'third_party_sources':dependencies,
              'installed_build_dependencies':dependency_records(('unicorn','pillow','pyinstaller')),
              'windows_pyinstaller_bootloader':{'upstream_unmodified':True,'build_command':['python','bootloader/waf','all','--no-cfg'],
                  'reason':'Avoid Control Flow Guard rejecting Unicorn JIT execution in the frozen Windows process'},
              'original_game_content_included':False,'engine_code_included':False,
              'source_delivery':'Upload this archive beside the matching binary release; preserve the enclosed source and notices.'}
    notes='''# FT2 converter corresponding source

This archive contains the GPL-2.0-only standalone converter component, its
freezer/build scripts, and matching unmodified Unicorn and PyInstaller source
archives. It contains no original game files and no independent engine code.
The source file SHA-256 list is in SOURCE_MANIFEST.json.

## Rebuild the converter

Use native x64 Python 3.11+ on Windows or arm64 Python 3.11+ on an Apple Silicon
Mac. A clean virtual environment is recommended:

    python -m venv .venv
    # Activate .venv using your platform's activation command.
    python -m pip install -r requirements.txt -r build-requirements.txt
    python tools/build_converter_binary.py --root . --destination build

Windows needs the Visual Studio C/C++ Build Tools. The build script obtains the
matching official PyInstaller source and rebuilds its bootloader with:

    python bootloader/waf all --no-cfg

No PyInstaller source-file patch is applied. The flag is needed for the bundled
Unicorn JIT in this Windows converter. The exact unmodified PyInstaller source
archive is also included under third_party/pyinstaller/.

Apple Silicon builds use the arm64 Python/Pillow/Unicorn/PyInstaller packages.
The existing converters/font_charset.json is the engine-authored UI character
catalogue; converter-only rebuilds preserve it and do not need engine sources.

The exact published Unicorn native core/Python binding source archive and its
upstream copying notices are under third_party/unicorn/. It includes the native
QEMU-derived C code, interface files, CMake and Python packaging build scripts.
To modify/rebuild that dependency, unpack its source archive and follow its own
setup/build scripts. Original upstream per-file notices remain in force.

CPython and Pillow retain their permissive upstream licences and the notices
that accompany the binary distribution. PyInstaller retains its GPL terms,
bootloader exception and any separately licensed runtime-hook notices.

## Licence and source delivery

Read COPYING-converter, CONVERTER_LICENSE.json, LICENSING.md and
THIRD_PARTY_NOTICES.md. The scope grant covers our converter component only.
It does not grant rights over original game content, user fonts/music/caches,
the independent engine, or upstream code under another existing licence.

Keep this corresponding-source download available at the same release location
as the matching converter binaries. This source package is not a project-wide
copyright clearance or a claim that game data can be redistributed.
'''
    archive_path=output/'FT2-Converter-Source.zip'
    prefix='FT2-Converter-Source/'
    with zipfile.ZipFile(archive_path,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6)as archive:
        for path in sorted(source_paths):archive.write(path,prefix+path.relative_to(ROOT).as_posix())
        for name,path in sorted(payload.items()):archive.write(path,prefix+name)
        archive.writestr(prefix+'BUILDING-CONVERTER.md',notes)
        archive.writestr(prefix+'SOURCE_MANIFEST.json',json.dumps(manifest,ensure_ascii=False,indent=2))
    result={'status':'ready','file':str(archive_path),'bytes':archive_path.stat().st_size,
            'sha256':digest(archive_path),'converter_source_files':len(rows),'dependencies':dependencies,
            'original_game_content_included':False,'engine_code_included':False}
    (output/'source-package.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir',type=Path,default=ROOT/'private/release_sources')
    package(parser.parse_args().output_dir)
