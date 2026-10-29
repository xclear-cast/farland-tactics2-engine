"""Freeze only converter code/dependencies into a Python-free onedir bundle.

Run natively on Windows x64 or Apple Silicon macOS. The returned executable is
destination/ft2-convert/ft2-convert[.exe]. Original game files are never inputs.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.metadata
import importlib.util
import json
import os
import platform
import shutil
import subprocess
import sys
import uuid
import urllib.request
import tarfile


def _sha(path):
    with Path(path).open('rb')as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()


def _pipeline_identity(root):
    """Match the source converter's identity, before frozen mode uses the stamp."""
    tools=Path(root)/'tools'
    files=[tools/'convert_installation.py',tools/'import_content.py',tools/'converters/font_charset.json',
           *sorted((tools/'converters').rglob('*.py'))]
    rows=[(path.relative_to(tools).as_posix(),_sha(path))for path in files if not path.name.startswith('test_')]
    return hashlib.sha256(json.dumps(rows,sort_keys=True).encode()).hexdigest()


def _assert_input(path):
    if not path.is_file()or path.is_symlink():raise ValueError('Missing or unsafe converter input: '+str(path))


def _compiler_environment():
    """Obtain MSVC environment for this build process without changing settings."""
    locator=Path(os.environ.get('ProgramFiles(x86)','C:/Program Files (x86)'))/'Microsoft Visual Studio/Installer/vswhere.exe'
    if not locator.is_file():raise RuntimeError('Visual Studio C++ Build Tools are required for the Windows Unicorn-compatible bootloader')
    installation=subprocess.check_output([str(locator),'-latest','-products','*','-requires','Microsoft.VisualStudio.Component.VC.Tools.x86.x64','-property','installationPath'],text=True).strip()
    script=Path(installation)/'VC/Auxiliary/Build/vcvars64.bat'
    if not script.is_file():raise RuntimeError('MSVC vcvars64.bat was not found')
    # Compiler activation is read only and scoped to this child process.
    command=f'cmd.exe /d /s /c ""{script}" >nul && set"'
    completed=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=60)
    if completed.returncode:raise RuntimeError('Could not activate MSVC build environment')
    environment={}
    for line in completed.stdout.splitlines():
        if '='in line and not line.startswith('='):
            key,value=line.split('=',1);environment[key]=value
    environment['PYTHONUTF8']='1'
    return environment


def _windows_bootloader(root):
    """Use PyInstaller's documented --no-cfg build for Unicorn's JIT/longjmp.

    The compiler option affects this converter executable only. No system
    mitigation, registry, or installed Python/PyInstaller setting is changed.
    """
    version=importlib.metadata.version('pyinstaller')
    directory=root/'private/build_converter_bootloader'/version
    source=directory/('pyinstaller-'+version)
    bootloader=source/'PyInstaller/bootloader/Windows-64bit-intel/run.exe'
    marker=directory/'bootloader.json'
    if marker.is_file()and bootloader.is_file():
        document=json.loads(marker.read_text(encoding='utf-8'))
        if document.get('cfg_disabled')is True and document.get('sha256')==_sha(bootloader):return source
    directory.mkdir(parents=True,exist_ok=True)
    with urllib.request.urlopen(f'https://pypi.org/pypi/pyinstaller/{version}/json',timeout=30)as response:metadata=json.load(response)
    artifact=next(item for item in metadata['urls']if item['packagetype']=='sdist')
    archive=directory/artifact['filename']
    if not archive.is_file()or _sha(archive)!=artifact['digests']['sha256']:
        with urllib.request.urlopen(artifact['url'],timeout=60)as response:archive.write_bytes(response.read())
    if _sha(archive)!=artifact['digests']['sha256']:raise RuntimeError('PyInstaller source archive hash mismatch')
    if not source.exists():
        with tarfile.open(archive)as package:package.extractall(directory,filter='data')
    environment=_compiler_environment()
    with (directory/'build.log').open('wb')as log:
        result=subprocess.run([sys.executable,str(source/'bootloader/waf'),'all','--no-cfg'],cwd=source/'bootloader',
                              env=environment,stdout=log,stderr=subprocess.STDOUT,timeout=900)
    if result.returncode or not bootloader.is_file():raise RuntimeError('Unicorn-compatible bootloader build failed; inspect '+str(directory/'build.log'))
    marker.write_text(json.dumps({'version':version,'cfg_disabled':True,'sha256':_sha(bootloader),
        'source_url':artifact['url'],'source_sha256':artifact['digests']['sha256'],
        'documentation':'https://pyinstaller.org/en/stable/common-issues-and-pitfalls.html#windows-executables-and-control-flow-guard-cfg'},indent=2),encoding='utf-8')
    return source


def _frozen_entry():
    return '''import json, sys, os
if sys.argv[1:2] == ['--editor-mcp']:
    import editor_mcp
    editor_mcp.main(sys.argv[2:])
elif sys.argv[1:] == ['--self-test']:
    try:
        def trace(step):
            if os.environ.get('FT2_CONVERTER_TEST_TRACE') == '1': print('FT2_CONVERTER_TEST '+step, file=sys.stderr, flush=True)
        trace('imports')
        import codecs
        from pathlib import Path
        from importlib.metadata import version
        from PIL import Image
        from unicorn import Uc, UC_ARCH_X86, UC_MODE_32
        from unicorn.x86_const import UC_X86_REG_EAX
        import convert_installation
        trace('pillow')
        image = Image.new('L', (2, 2), 123)
        assert image.getpixel((1, 1)) == 123
        trace('codec')
        assert codecs.decode(bytes([0xb0, 0xa1]), 'cp949') == chr(0xac00)
        trace('unicorn-open')
        emulator = Uc(UC_ARCH_X86, UC_MODE_32)
        trace('unicorn-map')
        emulator.mem_map(0x1000, 0x1000)
        code = bytes([0xb8, 42, 0, 0, 0, 0x40])
        emulator.mem_write(0x1000, code)
        trace('unicorn-run')
        emulator.emu_start(0x1000, 0x1000 + len(code), count=16)
        trace('unicorn-result')
        assert emulator.reg_read(UC_X86_REG_EAX) == 43
        stamp = convert_installation.pipeline_identity()
        trace('stamp')
        catalog = Path(sys._MEIPASS) / 'converters' / 'font_charset.json'
        assert 215 in json.loads(catalog.read_text(encoding='utf-8'))['codepoints']
        import editor_mcp
        assert len(editor_mcp.TOOLS) == 14
        trace('empty-save-slots')
        import tempfile
        from converters.tables_audio import _convert_saves, finalize_save_bindings
        with tempfile.TemporaryDirectory(prefix='ft2-empty-save-test-') as temporary:
            test_root = Path(temporary)
            save_dir = test_root / 'installation' / 'SAVE'
            save_dir.mkdir(parents=True)
            for slot in range(31): (save_dir / ('SAVE%02d.DAT' % slot)).write_bytes(b'')
            result = _convert_saves(test_root / 'installation', test_root / 'cache')
            assert result['saves'] == 0 and result['empty_saves_skipped'] == 31
            assert not finalize_save_bindings(test_root / 'cache')['unresolved']
        print(json.dumps({'status':'self-test-passed', 'frozen':bool(getattr(sys,'frozen',False)),
                          'pipeline_sha256':stamp, 'cp949':True, 'pillow':version('pillow'),
                          'unicorn':version('unicorn'), 'x86_result':43, 'font_catalog':True,
                          'empty_save_slots_supported':31, 'editor_mcp_tools':14}))
    except Exception as error:
        print(json.dumps({'status':'self-test-failed','error':str(error)}))
        raise SystemExit(1)
else:
    import convert_installation
    convert_installation.main()
'''


def _licenses(work):
    directory=work/'licenses';directory.mkdir()
    for name in ('pillow','unicorn','pyinstaller'):
        dist=importlib.metadata.distribution(name)
        destination=directory/name;destination.mkdir()
        for item in dist.files or []:
            if any(word in item.name.lower()for word in ('license','copying','notice')):
                source=Path(dist.locate_file(item))
                if source.is_file():shutil.copyfile(source,destination/source.name)
    # Some Windows wheels omit these upstream text files. Fetch the exact
    # runtime-version notices rather than silently shipping no license text.
    sources={
        directory/'python-LICENSE.txt':[
            f'https://raw.githubusercontent.com/python/cpython/v{platform.python_version()}/LICENSE',
            f'https://raw.githubusercontent.com/python/cpython/{sys.version_info.major}.{sys.version_info.minor}/LICENSE'],
        directory/'unicorn/COPYING.txt':[
            f'https://raw.githubusercontent.com/unicorn-engine/unicorn/{importlib.metadata.version("unicorn")}/COPYING',
        ],
        directory/'unicorn/COPYING.LGPL2':[
            f'https://raw.githubusercontent.com/unicorn-engine/unicorn/{importlib.metadata.version("unicorn")}/COPYING.LGPL2'],
        directory/'unicorn/COPYING_GLIB':[
            f'https://raw.githubusercontent.com/unicorn-engine/unicorn/{importlib.metadata.version("unicorn")}/COPYING_GLIB'],
    }
    source_rows=[]
    for path,urls in sources.items():
        errors=[]
        for url in urls:
            try:
                with urllib.request.urlopen(url,timeout=30)as response:raw=response.read()
                if len(raw)<100:raise ValueError('License notice is unexpectedly short')
                path.write_bytes(raw);source_rows.append({'file':path.relative_to(directory).as_posix(),'url':url,'sha256':_sha(path)})
                break
            except Exception as error:errors.append(str(error))
        else:raise RuntimeError('Could not obtain required upstream license notice: '+str(path.name)+'; '+str(errors))
    # The native Unicorn core is GPLv2 even though its Python wheel metadata
    # describes the bindings as BSD. Include its matching published source.
    version=importlib.metadata.version('unicorn')
    with urllib.request.urlopen(f'https://pypi.org/pypi/unicorn/{version}/json',timeout=30)as response:metadata=json.load(response)
    artifact=next(item for item in metadata['urls']if item['packagetype']=='sdist')
    path=directory/'unicorn'/artifact['filename']
    with urllib.request.urlopen(artifact['url'],timeout=60)as response:path.write_bytes(response.read())
    if _sha(path)!=artifact['digests']['sha256']:raise RuntimeError('Unicorn corresponding-source archive hash mismatch')
    source_rows.append({'file':path.relative_to(directory).as_posix(),'url':artifact['url'],'sha256':_sha(path)})
    (directory/'NOTICE_SOURCES.json').write_text(json.dumps(source_rows,indent=2),encoding='utf-8')
    (directory/'THIRD_PARTY_NOTICES.txt').write_text(
        'Bundled converter runtime: CPython, Pillow, Unicorn Engine, and PyInstaller bootloader.\n'
        'See the accompanying license files and installed distribution metadata.\n'
        'Unicorn native core: GPLv2; its Python wheel metadata describes the bindings as BSD.\n'
        'The matching published Unicorn source archive is included in licenses/unicorn/.\n'
        'Unicorn upstream source: https://github.com/unicorn-engine/unicorn/tree/'+version+'\n'
        'PyInstaller license includes its bootloader distribution exception.\n'
        'No original game files or fonts are bundled by this build.\n',encoding='utf-8')
    return directory


def _specification(root,stamp,entry,licenses):
    tools=root/'tools'
    exclusions=['converters.'+path.relative_to(tools/'converters').with_suffix('').as_posix().replace('/','.')
                for path in (tools/'converters').rglob('test_*.py')]
    arm64=platform.system()=='Darwin'
    return f'''# Generated only from the converter source allowlist.
import sys
from PyInstaller.utils.hooks import collect_all, collect_submodules, copy_metadata
sys.path.insert(0, {str(tools)!r})
pil_data, pil_bins, pil_hidden = collect_all('PIL')
unicorn_data, unicorn_bins, unicorn_hidden = collect_all('unicorn')
converter_hidden = collect_submodules('converters', filter=lambda name: not any(part.startswith('test_') or part == 'tests' for part in name.split('.')))
a = Analysis(
    [{str(entry)!r}],
    pathex=[{str(tools)!r}],
    binaries=pil_bins + unicorn_bins,
    datas=pil_data + unicorn_data + copy_metadata('pillow') + copy_metadata('unicorn') + copy_metadata('pyinstaller') + [({str(tools/'converters/font_charset.json')!r}, 'converters'), ({str(stamp)!r}, '.'), ({str(licenses)!r}, 'licenses')],
    hiddenimports=pil_hidden + unicorn_hidden + converter_hidden + ['editor_mcp'],
    hookspath=[], hooksconfig={{}}, runtime_hooks=[], excludes={exclusions!r},
    noarchive=False, optimize=0,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz, a.scripts, [], exclude_binaries=True, name='ft2-convert',
    debug=False, bootloader_ignore_signals=False, strip=False, upx=False,
    console=True, disable_windowed_traceback=False, argv_emulation=False,
    target_arch={'arm64' if arm64 else None!r}, codesign_identity=None,
    entitlements_file=None, contents_directory='_internal',
)
coll = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False, name='ft2-convert')
'''


def build_converter(root: Path,destination: Path) -> Path:
    root,destination=Path(root).resolve(),Path(destination).resolve()
    if platform.system()=='Darwin'and platform.machine()!='arm64':
        raise ValueError('Build macOS converter with an arm64 Python on Apple Silicon; Intel is not a target')
    for module in ('PyInstaller','PIL','unicorn'):
        if importlib.util.find_spec(module)is None:
            raise RuntimeError(f'Missing {module}; install requirements.txt and build-requirements.txt in this interpreter')
    tools=root/'tools'
    # The repertoire is engine-authored text codepoints, not captured glyphs.
    import runpy
    if(root/'game/scripts').is_dir():
        runpy.run_path(str(tools/'update_font_charset.py'))['update'](root)
    elif not(tools/'converters/font_charset.json').is_file():
        raise ValueError('Converter-only source archive must include its UI character repertoire')
    for path in (tools/'convert_installation.py',tools/'import_content.py',tools/'converters/font_charset.json'):
        _assert_input(path)
    for path in (tools/'converters').rglob('*.py'):_assert_input(path)
    pipeline=_pipeline_identity(root)
    mcp_source=tools/'editor_mcp.py'
    _assert_input(mcp_source)
    mcp_hash=_sha(mcp_source)
    bootloader_source=_windows_bootloader(root)if os.name=='nt'else None
    work=root/'private/build_converter'/uuid.uuid4().hex
    work.mkdir(parents=True)
    stamp=work/'converter_build.json'
    identity={'pipeline_sha256':pipeline,'editor_mcp_source_sha256':mcp_hash}
    stamp.write_text(json.dumps(identity),encoding='utf-8',newline='\n')
    generated=root/'private/generated';generated.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(stamp,generated/'converter_build.json')
    specification=work/'ft2-convert.spec'
    entry=work/'frozen_entry.py';entry.write_text(_frozen_entry(),encoding='utf-8',newline='\n')
    licenses=_licenses(work)
    specification.write_text(_specification(root,stamp,entry,licenses),encoding='utf-8',newline='\n')
    command=[sys.executable,'-m','PyInstaller','--noconfirm','--clean','--distpath',str(work/'dist'),
             '--workpath',str(work/'work'),str(specification)]
    environment=dict(os.environ,PYTHONUTF8='1')
    if bootloader_source:
        environment['PYTHONPATH']=str(bootloader_source)+(os.pathsep+environment['PYTHONPATH']if environment.get('PYTHONPATH')else'')
    with (work/'build.log').open('wb')as log:
        result=subprocess.run(command,cwd=root,env=environment,stdout=log,stderr=subprocess.STDOUT,timeout=900)
    if result.returncode:raise RuntimeError('Converter freeze failed; inspect '+str(work/'build.log'))
    stage=work/'dist/ft2-convert'
    suffix='.exe'if os.name=='nt'else''
    executable=stage/('ft2-convert'+suffix)
    if not executable.is_file():raise RuntimeError('Frozen executable missing')
    actual=json.loads((stage/'_internal/converter_build.json').read_text(encoding='utf-8'))
    if actual!=identity:raise RuntimeError('Frozen identity stamp mismatch')
    if _sha(stage/'_internal/converters/font_charset.json')!=_sha(tools/'converters/font_charset.json'):
        raise RuntimeError('Frozen UI character repertoire missing or stale')
    if platform.system()=='Darwin':
        architecture=subprocess.check_output(['lipo','-archs',str(executable)],text=True).strip().split()
        if architecture!=['arm64']:raise RuntimeError('Mac converter executable is not arm64-only')
    report={'schema':1,'kind':'standalone-converter-binary','pipeline_sha256':pipeline,
            'editor_mcp_included':True,'editor_mcp_source_sha256':mcp_hash,
            'python':platform.python_version(),'platform':platform.system(),'architecture':platform.machine(),
            'pyinstaller':importlib.metadata.version('pyinstaller'),
            'pillow':importlib.metadata.version('pillow'),'unicorn':importlib.metadata.version('unicorn'),
            'original_game_data_included':False,'requires_python_installation':False,
            'windows_unicorn_compatible_bootloader':bool(bootloader_source),
            'files':sum(1 for path in stage.rglob('*')if path.is_file()),
            'bytes':sum(path.stat().st_size for path in stage.rglob('*')if path.is_file())}
    (stage/'converter_build_result.json').write_text(json.dumps(report,indent=2),encoding='utf-8',newline='\n')
    destination.mkdir(parents=True,exist_ok=True)
    target=destination/'ft2-convert'
    if target.is_symlink():raise ValueError('Refusing to replace a linked converter directory')
    if target.exists():
        marker=target/'converter_build_result.json'
        if not marker.is_file()or json.loads(marker.read_text(encoding='utf-8')).get('kind')!='standalone-converter-binary':
            raise ValueError('Refusing to replace an unknown converter directory')
        previous=root/'private/build_converter_previous'/uuid.uuid4().hex
        previous.parent.mkdir(parents=True,exist_ok=True)
        if target.resolve().parent!=destination:raise ValueError('Converter target escaped the destination')
        # Atomic rename only: shutil.move falls back to copy/delete on a locked
        # Windows executable, which can partially remove a running bundle.
        target.rename(previous)
    if stage.drive.casefold()==target.drive.casefold():
        stage.rename(target)
    else:
        # Cross-volume builds copy to a new target and retain the private stage.
        shutil.copytree(stage,target,symlinks=True)
    return target/('ft2-convert'+suffix)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    parser.add_argument('--destination',type=Path,required=True)
    args=parser.parse_args()
    executable=build_converter(args.root,args.destination)
    print(json.dumps({'status':'built','executable':str(executable),'requires_python_installation':False,'original_game_data_included':False}))


if __name__=='__main__':main()
