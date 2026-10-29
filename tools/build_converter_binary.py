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


def _frozen_entry():
    return '''import json, sys
if sys.argv[1:] == ['--self-test']:
    try:
        import codecs
        from pathlib import Path
        from importlib.metadata import version
        from PIL import Image
        from unicorn import Uc, UC_ARCH_X86, UC_MODE_32
        from unicorn.x86_const import UC_X86_REG_EAX
        import convert_installation
        image = Image.new('L', (2, 2), 123)
        assert image.getpixel((1, 1)) == 123
        assert codecs.decode(bytes([0xb0, 0xa1]), 'cp949') == chr(0xac00)
        emulator = Uc(UC_ARCH_X86, UC_MODE_32)
        emulator.mem_map(0x1000, 0x1000)
        code = bytes([0xb8, 42, 0, 0, 0, 0x40])
        emulator.mem_write(0x1000, code)
        emulator.emu_start(0x1000, 0x1000 + len(code), count=16)
        assert emulator.reg_read(UC_X86_REG_EAX) == 43
        stamp = convert_installation.pipeline_identity()
        catalog = Path(sys._MEIPASS) / 'converters' / 'font_charset.json'
        assert 215 in json.loads(catalog.read_text(encoding='utf-8'))['codepoints']
        print(json.dumps({'status':'self-test-passed', 'frozen':bool(getattr(sys,'frozen',False)),
                          'pipeline_sha256':stamp, 'cp949':True, 'pillow':version('pillow'),
                          'unicorn':version('unicorn'), 'x86_result':43, 'font_catalog':True}))
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
            f'https://raw.githubusercontent.com/unicorn-engine/unicorn/{importlib.metadata.version("unicorn")}/COPYING.LGPL2'],
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
    (directory/'NOTICE_SOURCES.json').write_text(json.dumps(source_rows,indent=2),encoding='utf-8')
    (directory/'THIRD_PARTY_NOTICES.txt').write_text(
        'Bundled converter runtime: CPython, Pillow, Unicorn Engine, and PyInstaller bootloader.\n'
        'See the accompanying license files and installed distribution metadata.\n'
        'Unicorn upstream source: https://github.com/unicorn-engine/unicorn/tree/'+importlib.metadata.version('unicorn')+'\n'
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
    hiddenimports=pil_hidden + unicorn_hidden + converter_hidden,
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
    runpy.run_path(str(tools/'update_font_charset.py'))['update'](root)
    for path in (tools/'convert_installation.py',tools/'import_content.py',tools/'converters/font_charset.json'):
        _assert_input(path)
    for path in (tools/'converters').rglob('*.py'):_assert_input(path)
    pipeline=_pipeline_identity(root)
    work=root/'private/build_converter'/uuid.uuid4().hex
    work.mkdir(parents=True)
    stamp=work/'converter_build.json'
    stamp.write_text(json.dumps({'pipeline_sha256':pipeline}),encoding='utf-8',newline='\n')
    generated=root/'private/generated';generated.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(stamp,generated/'converter_build.json')
    specification=work/'ft2-convert.spec'
    entry=work/'frozen_entry.py';entry.write_text(_frozen_entry(),encoding='utf-8',newline='\n')
    licenses=_licenses(work)
    specification.write_text(_specification(root,stamp,entry,licenses),encoding='utf-8',newline='\n')
    command=[sys.executable,'-m','PyInstaller','--noconfirm','--clean','--distpath',str(work/'dist'),
             '--workpath',str(work/'work'),str(specification)]
    with (work/'build.log').open('wb')as log:
        result=subprocess.run(command,cwd=root,env=dict(os.environ,PYTHONUTF8='1'),stdout=log,stderr=subprocess.STDOUT,timeout=900)
    if result.returncode:raise RuntimeError('Converter freeze failed; inspect '+str(work/'build.log'))
    stage=work/'dist/ft2-convert'
    suffix='.exe'if os.name=='nt'else''
    executable=stage/('ft2-convert'+suffix)
    if not executable.is_file():raise RuntimeError('Frozen executable missing')
    actual=json.loads((stage/'_internal/converter_build.json').read_text(encoding='utf-8'))
    if actual!={'pipeline_sha256':pipeline}:raise RuntimeError('Frozen identity stamp mismatch')
    if _sha(stage/'_internal/converters/font_charset.json')!=_sha(tools/'converters/font_charset.json'):
        raise RuntimeError('Frozen UI character repertoire missing or stale')
    if platform.system()=='Darwin':
        architecture=subprocess.check_output(['lipo','-archs',str(executable)],text=True).strip().split()
        if architecture!=['arm64']:raise RuntimeError('Mac converter executable is not arm64-only')
    report={'schema':1,'kind':'standalone-converter-binary','pipeline_sha256':pipeline,
            'python':platform.python_version(),'platform':platform.system(),'architecture':platform.machine(),
            'pyinstaller':importlib.metadata.version('pyinstaller'),
            'pillow':importlib.metadata.version('pillow'),'unicorn':importlib.metadata.version('unicorn'),
            'original_game_data_included':False,'requires_python_installation':False,
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
        shutil.move(str(target),str(previous))
    shutil.move(str(stage),str(target))
    return target/('ft2-convert'+suffix)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    parser.add_argument('--destination',type=Path,required=True)
    args=parser.parse_args()
    executable=build_converter(args.root,args.destination)
    print(json.dumps({'status':'built','executable':str(executable),'requires_python_installation':False,'original_game_data_included':False}))


if __name__=='__main__':main()
