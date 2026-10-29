"""Validate the Mac app with self-authored fixtures; never requires game data."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import platform
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from run_tests import fixtures
from prepare_extension_fixtures import prepare as extension_fixtures


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--gui',action='store_true')
    args=parser.parse_args()
    if platform.system()!='Darwin'or platform.machine()!='arm64':raise RuntimeError('Actual Apple Silicon runner required')
    destination=ROOT/'dist/FT2-External-macos-arm64'
    app=destination/'FT2 External Engine.app'
    launcher=app/'Contents/MacOS/FT2External'
    runtime=app/'Contents/MacOS/GodotRuntime'
    resources=app/'Contents/Resources'
    output=ROOT/'private/macos-ci';output.mkdir(parents=True,exist_ok=True)
    records=[]
    def run(name,command,expected=0,timeout=90):
        result=subprocess.run([str(x)for x in command],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=timeout,
                              env=dict(os.environ,GODOT_SILENCE_ROOT_WARNING='1'))
        text=result.stdout+result.stderr
        (output/(name+'.log')).write_text(text,encoding='utf-8')
        diagnostics=[line for line in text.splitlines()if line.startswith(('ERROR:','SCRIPT ERROR:'))]
        if result.returncode!=expected or diagnostics:raise RuntimeError(f'{name} failed:\n{text[-7000:]}')
        records.append({'test':name,'exit_code':result.returncode,'passed':True})
        return text
    run('signature',['codesign','--verify','--deep','--strict',app])
    macho_magic={b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca',b'\xca\xfe\xba\xbf',b'\xbf\xba\xfe\xca',
                 b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf'}
    native_count=0
    frameworks=sorted((path for path in app.rglob('*.framework')if path.is_dir()and not path.is_symlink()),key=lambda path:len(path.parts),reverse=True)
    for index,framework in enumerate(frameworks,1):
        # Apple TN2206 / Code Signing Guide require bundle-context verification
        # for a framework; its main executable alone has no resource envelope.
        run(f'framework-signature-{index}',['codesign','--verify','--deep','--strict',framework])
    for binary in sorted(app.rglob('*')):
        if not binary.is_file()or binary.is_symlink():continue
        with binary.open('rb')as stream:header=stream.read(4)
        if header not in macho_magic:continue
        native_count+=1
        enclosing=[framework for framework in frameworks if binary.is_relative_to(framework)]
        if not enclosing:run(f'nested-signature-{native_count}',['codesign','--verify','--strict',binary])
        if run(f'nested-architecture-{native_count}',['lipo','-archs',binary]).strip()!='arm64':
            raise RuntimeError('Non-arm64 code in application: '+str(binary.relative_to(app)))
    for binary in (launcher,runtime,resources/'native/bin/libft2synth.macos.arm64.dylib'):
        result=run('architecture-'+binary.name,['lipo','-archs',binary])
        if result.strip()!='arm64':raise RuntimeError('Only arm64 executables may be included')
    run('native-module',[launcher,'--headless','--audio-driver','Dummy','--script',ROOT/'game/tests/test_macos_runtime.gd','--',f'--macos-ui-test-root={output/"gui-converter-test"}'])
    run('pack-content-audit',[launcher,'--headless','--audio-driver','Dummy','--script',ROOT/'game/tests/audit_pack.gd'])
    synthetic=output/'synthetic';fixtures(synthetic)
    run('synthetic-mods',[launcher,'--headless','--audio-driver','Dummy','--script',ROOT/'game/tests/test_content.gd','--',f'--fixtures={synthetic}'])
    report=json.loads((synthetic/'godot_result.json').read_text(encoding='utf-8'))
    if not report['passed']:raise RuntimeError('Synthetic data/mod integration did not pass')
    run('setup-audio-contracts',[launcher,'--headless','--audio-driver','Dummy','--script',ROOT/'game/tests/test_setup_audio.gd'])
    # These definitions and the editor's test project are entirely self-authored.
    # Do not add a real installation path/cache or call the local-game validator.
    extension_synthetic=extension_fixtures(output/'extension-synthetic')
    run('extension-definitions',[launcher,'--headless','--audio-driver','Dummy','--script',ROOT/'game/tests/test_extension_definitions.gd','--',f'--fixtures={extension_synthetic}'])
    extension_report=json.loads((extension_synthetic/'extension_result.json').read_text(encoding='utf-8'))
    if not extension_report.get('passed')or not extension_report.get('synthetic_only'):
        raise RuntimeError('Synthetic v2 definitions did not pass')
    editor_output=output/'editor';editor_output.mkdir(parents=True,exist_ok=True)
    run('extension-editor-controls',[launcher,'--headless','--audio-driver','Dummy','--script',ROOT/'game/tests/test_extension_editor.gd','--',f'--editor-output={editor_output}'])
    editor_report=json.loads((editor_output/'result.json').read_text(encoding='utf-8'))
    if not editor_report.get('passed')or editor_report.get('source_game_data_used')is not False:
        raise RuntimeError('Content-free editor controls did not pass')
    run('no-original-data',[launcher,'--headless','--audio-driver','Dummy','--','--check-content',f'--engine-config={output/"absent-connection.json"}'],expected=2)
    if args.gui:
        run('first-setup-window',[launcher,'--audio-driver','Dummy','--quit-after','5','--','--setup',f'--engine-config={output/"gui-connection.json"}'],timeout=45)
    run('graphics-parser-fixtures',[sys.executable,'-m','unittest','tools.converters.test_graphics'])
    run('scenario-parser-fixtures',[sys.executable,'-m','unittest','tools.converters.scenario_support.test_scenario'])
    run('distributed-converter-help',[sys.executable,'-I',resources/'tools/convert_installation.py','--help'])
    converter=app/'Contents/MacOS/tools/ft2-convert/ft2-convert'
    architecture=run('converter-architecture',['lipo','-archs',converter])
    if architecture.strip()!='arm64':raise RuntimeError('Bundled converter contains an unsupported architecture')
    payload=resources/'converter/ft2-convert/ft2-convert'
    if run('converter-payload-architecture',['lipo','-archs',payload]).strip()!='arm64':
        raise RuntimeError('Converter payload contains an unsupported architecture')
    run('bundled-converter-help',[converter,'--help'])
    frozen_result=run('bundled-converter-native-self-test',[converter,'--self-test'])
    if json.loads(frozen_result.strip().splitlines()[-1]).get('status')!='self-test-passed':
        raise RuntimeError('Frozen converter native dependencies were not verified')
    # Exercise the same ARM-native libraries required for actual conversion.
    from unicorn import Uc,UC_ARCH_X86,UC_MODE_32
    from unicorn.x86_const import UC_X86_REG_EAX
    emulator=Uc(UC_ARCH_X86,UC_MODE_32);emulator.mem_map(0x1000,0x1000)
    emulator.mem_write(0x1000,b'\xb8\x2a\x00\x00\x00\x40\x90')
    emulator.emu_start(0x1000,0x1007)
    if emulator.reg_read(UC_X86_REG_EAX)!=43:raise RuntimeError('ARM-native Unicorn x86 conversion backend failed')
    records.append({'test':'arm-native-unicorn-self-authored-code','passed':True})
    from converters.fonts import convert as convert_fonts,find_font
    font_result=convert_fonts(synthetic/'cache',font=find_font())
    font_metadata=json.loads((synthetic/'cache/assets/indexed/fonts.json').read_text(encoding='utf-8'))
    if not all('215'in style['glyphs']for style in font_metadata['styles']):raise RuntimeError('Engine UI multiplication glyph missing')
    records.append({'test':'arm-native-Pillow-system-font-conversion','passed':True,'styles':font_result['styles']})
    result={'passed':True,'platform':platform.platform(),'architecture':platform.machine(),
            'signed_arm64_native_files':native_count,
            'strict_framework_bundles':len(frameworks),
            'synthetic_engine_checks':report['checks'],
            'synthetic_extension_checks':extension_report['checks'],'editor_control_checks':editor_report['checks'],
            'tests':records,'game_data_used':False,
            'gui_first_setup_verified':args.gui,'real_gameplay_verified':False,
            'scope':'Native arm64 build, app startup/setup, content-free package, synthetic loader/v2 definitions/editor/parser/font/emulator validation. No original game or complete campaign validation.'}
    (output/'validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    build=json.loads((destination/'build_result.json').read_text(encoding='utf-8'))
    build.update(runtime_verified=True,validation_scope=result['scope'],real_gameplay_verified=False)
    (destination/'build_result.json').write_text(json.dumps(build,indent=2),encoding='utf-8')
    archive=ROOT/'dist/FT2-External-macos-arm64.zip'
    if archive.exists():archive.unlink()
    subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(destination),str(archive)],check=True,timeout=300)
    result['archive_sha256']=hashlib.sha256(archive.read_bytes()).hexdigest()
    (output/'validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result))


if __name__=='__main__':main()
