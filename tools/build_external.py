"""Build the engine-only candidate in WSL without touching the original build."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
from update_font_charset import update as update_font_charset
from package_converter import copy_converter_payload

ROOT = Path(__file__).resolve().parents[1]
GODOT = Path('/opt/ft2-godot/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64')


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def run(arguments, log):
    result = subprocess.run([str(GODOT), '--headless', '--audio-driver', 'Dummy', *arguments],
        env=dict(os.environ, GODOT_SILENCE_ROOT_WARNING='1'), capture_output=True, text=True, timeout=90)
    output = result.stdout + result.stderr
    log.write_text(output, encoding='utf-8')
    errors = [line for line in output.splitlines() if line.startswith(('ERROR:', 'SCRIPT ERROR:'))]
    if result.returncode or errors:
        raise RuntimeError(f'Godot failed: {log}\n' + '\n'.join(errors))


def main():
    global GODOT
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',type=Path,default=Path(os.environ.get('FT2_GODOT',str(GODOT))))
    parser.add_argument('--windows-godot',type=Path,default=Path(os.environ['FT2_WINDOWS_GODOT'])if os.environ.get('FT2_WINDOWS_GODOT')else None)
    options=parser.parse_args()
    GODOT=options.godot.resolve()
    if not GODOT.is_file():raise ValueError('Godot executable missing; pass --godot or FT2_GODOT')
    update_font_charset(ROOT)
    destination = ROOT / 'dist/FT2-External-Engine'
    destination.mkdir(parents=True, exist_ok=True)
    logs = ROOT / 'private/build'
    logs.mkdir(parents=True, exist_ok=True)
    run(['--path',str(ROOT/'game'),'--editor','--import','--quit'],logs/'import.log')
    pack = destination / 'FT2-External.pck'
    manifest = destination / 'engine_manifest.json'
    run(['--path',str(ROOT/'game'),'--script','res://pack_external.gd','--',str(pack),str(manifest)],logs/'pack.log')
    engine_rows = json.loads(manifest.read_text(encoding='utf-8'))['files']
    allowed = ('res://scripts/','res://scenes/','res://native/bin/')
    exceptions = {'res://project.godot','res://native/ft2_synth.gdextension',
                  'res://.godot/global_script_class_cache.cfg','res://.godot/extension_list.cfg'}
    for row in engine_rows:
        if not (row['path'].startswith(allowed) or row['path'] in exceptions):
            raise RuntimeError(f'Unexpected packed resource: {row["path"]}')
    shutil.copyfile(GODOT,destination/'FT2-External-linux.x86_64')
    (destination/'FT2-External-linux.x86_64').chmod(0o755)
    windows = options.windows_godot
    if windows is not None:
        if not windows.is_file():raise ValueError('The supplied --windows-godot executable does not exist')
        shutil.copyfile(windows,destination/'FT2-External.exe')
    for name in ('ft2synth.dll','libft2synth.so'):
        target = destination/'native/bin'/name
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ROOT/'game/native/bin'/name,target)
    converter_rows=copy_converter_payload(ROOT,destination)
    shutil.copyfile(ROOT/'README.md',destination/'README.md')
    for name in ('LICENSING.md','THIRD_PARTY_NOTICES.md'):
        if(ROOT/name).is_file():shutil.copyfile(ROOT/name,destination/name)
    run(['--path',str(ROOT/'game'),'--script','res://write_notices.gd','--',str(destination/'GODOT_LICENSES.txt')],logs/'licenses.log')
    tsf=(ROOT/'game/native/include/tsf.h').read_text(encoding='utf-8').split('LICENSE (MIT)',1)[1].split('*/',1)[0]
    (destination/'TINYSOUNDFONT_LICENSE.txt').write_text('MIT License\n'+tsf,encoding='utf-8')
    shutil.copytree(ROOT/'mods',destination/'mods',dirs_exist_ok=True)
    (destination/'Launch-Windows.cmd').write_text('@echo off\r\ncd /d "%~dp0"\r\nstart "" "%~dp0FT2-External.exe" --main-pack "%~dp0FT2-External.pck" -- %*\r\n',encoding='ascii')
    (destination/'Game-Setup-Windows.cmd').write_text('@echo off\r\ncd /d "%~dp0"\r\nstart "" "%~dp0FT2-External.exe" --main-pack "%~dp0FT2-External.pck" -- --setup\r\n',encoding='ascii',newline='')
    (destination/'Launch-Linux.sh').write_text('#!/bin/sh\ncd -- "$(dirname -- "$0")" || exit 1\nexec ./FT2-External-linux.x86_64 --main-pack ./FT2-External.pck -- "$@"\n',encoding='utf-8')
    (destination/'Launch-Linux.sh').chmod(0o755)
    report = {'status':'built','pack_sha256':sha(pack),'pack_bytes':pack.stat().st_size,
              'packed_files':len(engine_rows),'original_content_files':0,
              'raw_installation_converter_included':True,
              'converter_files':converter_rows,
              'requires_private_legacy_conversion_cache':False,
              'raw_converter_validation':'Reported separately by integration tests.'}
    report['macos']={'architecture':'arm64','minimum_chip':'M1','build_script_ready':True,'runtime_verified':False,'intel_target':False}
    (logs/'build_result.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps({key:value for key,value in report.items()if key!='converter_files'}))


if __name__ == '__main__': main()
