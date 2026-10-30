"""Build a data-free Apple Silicon macOS app and converter distribution."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import platform
import plistlib
import shutil
import subprocess
from update_font_charset import update as update_font_charset
from package_converter import copy_converter_payload
from build_converter_binary import build_converter

ROOT=Path(__file__).resolve().parents[2]
APP_NAME='FT2 External Engine.app'


def run(command,timeout=180):
    result=subprocess.run([str(x)for x in command],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=timeout,
                          env=dict(os.environ,GODOT_SILENCE_ROOT_WARNING='1'))
    output=result.stdout+result.stderr
    if result.returncode or any(line.startswith(('ERROR:','SCRIPT ERROR:'))for line in output.splitlines()):
        raise RuntimeError(output)
    return output


def copy_runtime(source,target):
    information=run(['lipo','-info',source])
    if 'Non-fat file' in information and 'arm64' in information:shutil.copyfile(source,target)
    else:run(['lipo',source,'-thin','arm64','-output',target])
    target.chmod(0o755)
    run(['codesign','--force','--sign','-',target])
    if run(['lipo','-archs',target]).strip()!='arm64':raise RuntimeError('Intel executable was not excluded')


def thin_frameworks(directory):
    if not directory.is_dir():return
    magic={b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca',b'\xca\xfe\xba\xbf',b'\xbf\xba\xfe\xca',
           b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf'}
    for path in directory.rglob('*'):
        if not path.is_file()or path.is_symlink():continue
        with path.open('rb')as stream:header=stream.read(4)
        if header not in magic:continue
        architectures=run(['lipo','-archs',path]).strip().split()
        if 'arm64'not in architectures:raise RuntimeError('Official runtime framework lacks arm64: '+str(path))
        if architectures!=['arm64']:
            temporary=path.with_name(path.name+'.arm64-building')
            run(['lipo',path,'-thin','arm64','-output',temporary])
            temporary.chmod(path.stat().st_mode&0o777)
            temporary.replace(path)
        run(['codesign','--force','--sign','-',path])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',type=Path,default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    args=parser.parse_args()
    if platform.system()!='Darwin' or platform.machine()!='arm64':
        parser.error('Run on Apple Silicon macOS using arm64 Python. Intel is not a target.')
    args.godot=args.godot.resolve()
    if not args.godot.is_file():parser.error('Godot executable missing')
    # Use the official runtime's advertised deployment floor for every native
    # helper we compile, rather than inheriting the runner SDK's macOS version.
    official_contents=args.godot.parent.parent
    minimum='11.0'
    if (official_contents/'Info.plist').is_file():
        official_metadata=plistlib.loads((official_contents/'Info.plist').read_bytes())
        minimum=str(official_metadata.get('LSMinimumSystemVersion',minimum))
    components=minimum.split('.')
    if not 1<=len(components)<=3 or not all(part.isdigit()for part in components):
        raise RuntimeError('Invalid official runtime minimum macOS version: '+minimum)
    if tuple([int(part)for part in components]+[0]*(3-len(components)))<(11,0,0):
        minimum='11.0' # Apple Silicon has no macOS release below 11.
    deployment_flag='-mmacosx-version-min='+minimum
    update_font_charset(ROOT)
    destination=ROOT/'dist/FT2-External-macos-arm64';destination.mkdir(parents=True,exist_ok=True)
    library=ROOT/'game/native/bin/libft2synth.macos.arm64.dylib'
    library.parent.mkdir(parents=True,exist_ok=True)
    run(['xcrun','clang','-arch','arm64',deployment_flag,'-dynamiclib','-O2','-fvisibility=hidden',
         '-I',ROOT/'game/native',ROOT/'game/native/ft2_synth.c','-framework','CoreGraphics','-o',library])
    run(['codesign','--force','--sign','-',library])
    if run(['lipo','-archs',library]).strip()!='arm64':raise RuntimeError('Native module is not arm64 only')
    # Godot #111048: extension documentation can race immediate editor shutdown.
    # Give the importer a full event-loop interval; never ignore its exit status.
    run([args.godot,'--headless','--audio-driver','Dummy','--frame-delay','1000','--path',ROOT/'game','--editor','--import','--quit'])
    app=destination/APP_NAME
    macos=app/'Contents/MacOS';resources=app/'Contents/Resources'
    macos.mkdir(parents=True,exist_ok=True);resources.mkdir(parents=True,exist_ok=True)
    pack=resources/'FT2-External.pck'
    run([args.godot,'--headless','--path',ROOT/'game','--script','res://pack_external.gd','--',pack,resources/'engine_manifest.json'])
    copy_runtime(args.godot,macos/'GodotRuntime')
    run(['xcrun','clang','-arch','arm64',deployment_flag,'-O2',ROOT/'tools/ci/macos_app_launcher.c','-o',macos/'FT2External'])
    run(['codesign','--force','--sign','-',macos/'FT2External'])
    target=resources/'native/bin'/library.name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(library,target)
    if (official_contents/'Frameworks').is_dir():
        shutil.copytree(official_contents/'Frameworks',app/'Contents/Frameworks',dirs_exist_ok=True,symlinks=True)
        thin_frameworks(app/'Contents/Frameworks')
    metadata={'CFBundleDevelopmentRegion':'en','CFBundleExecutable':'FT2External',
              'CFBundleIdentifier':'org.ft2.external-engine','CFBundleInfoDictionaryVersion':'6.0',
              'CFBundleName':'FT2 External Engine','CFBundleDisplayName':'FT2 External Engine',
              'CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.3.1',
              'CFBundleVersion':'9','LSMinimumSystemVersion':minimum,'LSArchitecturePriority':['arm64'],
              'NSHighResolutionCapable':True,'NSSupportsAutomaticGraphicsSwitching':True}
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps(metadata))
    # Keep Python metadata/data under Resources, not macOS's nested-code folders.
    converter_rows=copy_converter_payload(ROOT,resources)
    copy_converter_payload(ROOT,destination)
    converter=build_converter(ROOT,resources/'converter')
    if not converter.is_file():raise RuntimeError('Bundled converter binary missing')
    if run(['lipo','-archs',converter]).strip()!='arm64':raise RuntimeError('Converter is not arm64 only')
    bridge=macos/'tools/ft2-convert/ft2-convert';bridge.parent.mkdir(parents=True,exist_ok=True)
    run(['xcrun','clang','-arch','arm64',deployment_flag,'-O2','-DFT2_CONVERTER_BRIDGE',ROOT/'tools/ci/macos_app_launcher.c','-o',bridge])
    run(['codesign','--force','--sign','-',bridge])
    framework_checks=[]
    for framework in sorted((path for path in app.rglob('*.framework')if path.is_dir()and not path.is_symlink()),key=lambda path:len(path.parts),reverse=True):
        before=subprocess.run(['codesign','--verify','--deep','--strict',str(framework)],capture_output=True,text=True,encoding='utf-8',errors='replace')
        framework_checks.append({'framework':framework.relative_to(app).as_posix(),'before_exit_code':before.returncode,'before_output':before.stdout+before.stderr})
        run(['codesign','--force','--sign','-',framework])
        run(['codesign','--verify','--deep','--strict',framework])
    diagnostics=ROOT/'private/macos-ci';diagnostics.mkdir(parents=True,exist_ok=True)
    (diagnostics/'framework_signing.json').write_text(json.dumps(framework_checks,indent=2),encoding='utf-8')
    for output in (destination,resources):
        shutil.copyfile(ROOT/'README.md',output/'README.md')
        shutil.copytree(ROOT/'mods',output/'mods',dirs_exist_ok=True)
        run([args.godot,'--headless','--path',ROOT/'game','--script','res://write_notices.gd','--',output/'GODOT_LICENSES.txt'])
        tsf=(ROOT/'game/native/include/tsf.h').read_text(encoding='utf-8').split('LICENSE (MIT)',1)[1].split('*/',1)[0]
        (output/'TINYSOUNDFONT_LICENSE.txt').write_text('MIT License\n'+tsf,encoding='utf-8')
    run(['codesign','--force','--deep','--sign','-',app])
    run(['codesign','--verify','--deep','--strict',app])
    launcher=destination/'Launch-Mac.command'
    launcher.write_text('#!/bin/sh\ncd -- "$(dirname -- "$0")" || exit 1\nexec "./FT2 External Engine.app/Contents/MacOS/FT2External" "$@"\n',encoding='utf-8');launcher.chmod(0o755)
    setup=destination/'Game-Setup-Mac.command'
    setup.write_text('#!/bin/sh\ncd -- "$(dirname -- "$0")" || exit 1\nexec open -n "./FT2 External Engine.app" --args -- --setup\n',encoding='utf-8');setup.chmod(0o755)
    result={'target':'macos-arm64','intel_included':False,'game_content_included':False,
            'minimum_macos':minimum,'native_deployment_flag':deployment_flag,
            'app':APP_NAME,'pack_sha256':hashlib.sha256(pack.read_bytes()).hexdigest(),
            'converter_files':converter_rows,'requires_private_legacy_conversion_cache':False,
            'bundled_converter':converter.relative_to(destination).as_posix(),'python_required_for_users':False,
            'converter_launcher':bridge.relative_to(destination).as_posix(),
            'signing':'local ad-hoc only; no Apple Developer ID or notarization claim','runtime_verified':False}
    (destination/'build_result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    archive=ROOT/'dist/FT2-External-macos-arm64.zip'
    if archive.exists():archive.unlink()
    run(['ditto','-c','-k','--sequesterRsrc','--keepParent',destination,archive],timeout=300)
    print(json.dumps({key:value for key,value in result.items()if key!='converter_files'}))


if __name__=='__main__':main()
