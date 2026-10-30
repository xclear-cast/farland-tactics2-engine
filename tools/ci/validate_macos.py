"""Validate the Mac app with self-authored fixtures; never requires game data."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import platform
import plistlib
import re
import struct
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from run_tests import fixtures
from prepare_extension_fixtures import prepare as extension_fixtures


def version_tuple(value):
    parts=str(value).split('.')
    if not 1<=len(parts)<=3 or not all(part.isdigit()for part in parts):
        raise ValueError('Invalid macOS version: '+str(value))
    return tuple([int(part)for part in parts]+[0]*(3-len(parts)))


def packed_version(value):
    return ((value>>16)&0xffff,(value>>8)&0xff,value&0xff)


def version_text(value):return '.'.join(str(part)for part in value)


def macho_minimum_versions(path):
    """Read declared macOS deployment floors without executing native code.

    Supports thin 32/64-bit Mach-O and both FAT table sizes/endian orders. The
    application architecture is separately required to be arm64 by lipo.
    """
    path=Path(path);total=path.stat().st_size
    thin={b'\xcf\xfa\xed\xfe':('<',32),b'\xfe\xed\xfa\xcf':('>',32),
          b'\xce\xfa\xed\xfe':('<',28),b'\xfe\xed\xfa\xce':('>',28)}
    fat={b'\xca\xfe\xba\xbe':('>',20),b'\xbe\xba\xfe\xca':('<',20),
         b'\xca\xfe\xba\xbf':('>',32),b'\xbf\xba\xfe\xca':('<',32)}
    records=[]
    with path.open('rb')as stream:
        def parse_slice(offset,size):
            if offset<0 or size<28 or offset+size>total:raise ValueError('Mach-O slice is out of bounds')
            stream.seek(offset);header=stream.read(32)
            if header[:4]not in thin:raise ValueError('Unsupported Mach-O slice magic')
            endian,header_size=thin[header[:4]]
            if len(header)<header_size:raise ValueError('Truncated Mach-O header')
            cpu=struct.unpack_from(endian+'i',header,4)[0]
            command_count,command_bytes=struct.unpack_from(endian+'II',header,16)
            if command_count>65535 or command_bytes>size-header_size or command_count>command_bytes//8:
                raise ValueError('Invalid Mach-O load-command table')
            stream.seek(offset+header_size);commands=stream.read(command_bytes)
            position=0;found=[]
            for _ in range(command_count):
                if position+8>len(commands):raise ValueError('Truncated Mach-O load command')
                command,length=struct.unpack_from(endian+'II',commands,position)
                if length<8 or position+length>len(commands):raise ValueError('Mach-O command length is out of bounds')
                command&=0x7fffffff
                if command==0x32: # LC_BUILD_VERSION
                    if length<24:raise ValueError('Truncated LC_BUILD_VERSION')
                    target,minimum,sdk=struct.unpack_from(endian+'III',commands,position+8)
                    if target!=1:raise ValueError('Non-macOS LC_BUILD_VERSION platform: '+str(target))
                    found.append(('LC_BUILD_VERSION',minimum,sdk))
                elif command==0x24: # LC_VERSION_MIN_MACOSX
                    if length<16:raise ValueError('Truncated LC_VERSION_MIN_MACOSX')
                    minimum,sdk=struct.unpack_from(endian+'II',commands,position+8)
                    found.append(('LC_VERSION_MIN_MACOSX',minimum,sdk))
                position+=length
            if position!=len(commands):raise ValueError('Mach-O load-command size mismatch')
            if not found:raise ValueError('Mach-O has no declared minimum macOS version')
            for command,minimum,sdk in found:
                if minimum==0:raise ValueError('Mach-O minimum macOS version is unspecified')
                records.append({'cpu_type':cpu,'slice_offset':offset,'command':command,
                                'minimum_macos':version_text(packed_version(minimum)),
                                'sdk':version_text(packed_version(sdk))})
        magic=stream.read(4)
        if magic in thin:parse_slice(0,total)
        elif magic in fat:
            endian,entry_size=fat[magic]
            raw=stream.read(4)
            if len(raw)!=4:raise ValueError('Truncated FAT header')
            count=struct.unpack(endian+'I',raw)[0]
            if count<1 or count>64 or 8+count*entry_size>total:raise ValueError('Invalid FAT architecture table')
            table=stream.read(count*entry_size)
            for index in range(count):
                start=index*entry_size
                if entry_size==20:offset,size=struct.unpack_from(endian+'II',table,start+8)
                else:offset,size=struct.unpack_from(endian+'QQ',table,start+8)
                parse_slice(offset,size)
        else:raise ValueError('Not a Mach-O file')
    return records


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--gui',action='store_true')
    args=parser.parse_args()
    if platform.system()!='Darwin'or platform.machine()!='arm64':raise RuntimeError('Actual Apple Silicon runner required')
    destination=ROOT/'dist/FT2-External-macos-arm64'
    media=[p.relative_to(destination).as_posix()for p in destination.rglob('*')
           if p.is_file()and p.suffix.lower()in ('.gif','.mp4','.webm','.mov','.avi','.mkv')]
    if media:raise RuntimeError('Text-only release contains instructional media: '+str(media))
    app=destination/'FT2 External Engine.app'
    launcher=app/'Contents/MacOS/FT2External'
    runtime=app/'Contents/MacOS/GodotRuntime'
    resources=app/'Contents/Resources'
    output=ROOT/'private/macos-ci';output.mkdir(parents=True,exist_ok=True)
    app_metadata=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    advertised_minimum=str(app_metadata['LSMinimumSystemVersion'])
    minimum_limit=version_tuple(advertised_minimum)
    records=[]
    def run(name,command,expected=0,timeout=90,extra_env=None):
        result=subprocess.run([str(x)for x in command],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=timeout,
                              env=dict(os.environ,GODOT_SILENCE_ROOT_WARNING='1',**(extra_env or {})))
        text=result.stdout+result.stderr
        (output/(name+'.log')).write_text(text,encoding='utf-8')
        diagnostics=[line for line in text.splitlines()if line.startswith(('ERROR:','SCRIPT ERROR:'))]
        if result.returncode!=expected or diagnostics:raise RuntimeError(f'{name} failed:\n{text[-7000:]}')
        records.append({'test':name,'exit_code':result.returncode,'passed':True})
        return text
    run('signature',['codesign','--verify','--deep','--strict',app])
    macho_magic={b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca',b'\xca\xfe\xba\xbf',b'\xbf\xba\xfe\xca',
                 b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xce\xfa\xed\xfe',b'\xfe\xed\xfa\xce'}
    native_count=0
    minimum_records=[];minimum_errors=[]
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
        relative=binary.relative_to(app).as_posix()
        try:
            commands=macho_minimum_versions(binary)
            minimum_records.append({'path':relative,'commands':commands})
            for command in commands:
                if version_tuple(command['minimum_macos'])>minimum_limit:
                    minimum_errors.append({'path':relative,'minimum_macos':command['minimum_macos'],
                                           'advertised_minimum_macos':advertised_minimum})
        except ValueError as error:minimum_errors.append({'path':relative,'error':str(error)})
    deployment_report={'passed':not minimum_errors,'advertised_minimum_macos':advertised_minimum,
                       'native_files_checked':len(minimum_records),'files':minimum_records,'errors':minimum_errors}
    (output/'minimum_versions.json').write_text(json.dumps(deployment_report,indent=2),encoding='utf-8')
    if minimum_errors:raise RuntimeError('Native minimum macOS versions exceed the application target or are invalid: '+json.dumps(minimum_errors))
    records.append({'test':'all-native-minimum-macos-versions','passed':True,'minimum_macos':advertised_minimum,'files':len(minimum_records)})
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
    for name,argument in [('portrait_palette','palette'),('actor_job_direction','direction'),('actor_sprite_reset','sprite'),('story_palette_snapshot','story-palette'),('story_shadow','shadow'),('cinematic_layer_keys','layer-keys'),('story_unit_visibility','unit-visibility'),('script_sprite_palette','script-palette'),('save_tail_header','save-tail'),('cinematic_reset_lifetime','scene-reset'),('story_palette_wait','palette-wait'),('scene_dispatch','scene-dispatch'),('story_cleanup','cleanup'),('system_palette_acquisition','system-palette'),('story_shadow_handles','shadow-handles'),('story_appearance_refresh','appearance'),('actor_palette_acquisition','actor-palette'),('script_whiten_palette','whiten'),('cache_rebuild_mode','cache-rebuild'),('exp_palette_scope','exp-palette'),('selection_camera','selection-camera'),('actor_job_start_failure','job-start'),('placement_appearance','placement'),('action_camera_and_mask','action-camera'),('actor_job_wait','job-wait'),('source_game_mode','game-mode'),('next_party_presentation','next-party')]:
        regression_output=output/name;regression_output.mkdir(parents=True,exist_ok=True)
        run(name,[launcher,'--headless','--audio-driver','Dummy','--script',ROOT/f'game/tests/test_{name}.gd','--',f'--{argument}-output={regression_output}'])
        regression_report=json.loads((regression_output/'result.json').read_text(encoding='utf-8'))
        if not regression_report.get('passed'):raise RuntimeError(name+' synthetic runtime regression did not pass')
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
    baseline_output=output/'editor-baseline';baseline_output.mkdir(parents=True,exist_ok=True)
    run('editor-original-baseline-synthetic',[launcher,'--headless','--audio-driver','Dummy','--script',ROOT/'game/tests/test_editor_baseline.gd','--',f'--baseline-output={baseline_output}'])
    baseline_report=json.loads((baseline_output/'result.json').read_text(encoding='utf-8'))
    if not baseline_report.get('passed')or baseline_report.get('real_cache_checked')is not False or baseline_report.get('original_data_embedded')is not False:
        raise RuntimeError('Content-free editor baseline regression did not pass')
    scaling_output=output/'editor-scaling';scaling_output.mkdir(parents=True,exist_ok=True)
    run('editor-display-scaling',[launcher,'--headless','--audio-driver','Dummy','--script',ROOT/'game/tests/test_editor_scaling.gd','--',f'--scaling-output={scaling_output}'])
    scaling_report=json.loads((scaling_output/'result.json').read_text(encoding='utf-8'))
    if not scaling_report.get('passed')or scaling_report.get('original_data_used')is not False:
        raise RuntimeError('Content-free editor display scaling did not pass')
    clients_output=output/'editor-clients';clients_output.mkdir(parents=True,exist_ok=True)
    run('godot-ai-client-registry',[launcher,'--headless','--audio-driver','Dummy','--script',ROOT/'game/tests/test_editor_clients.gd','--',f'--clients-output={clients_output}'])
    run('all-client-setting-formats',[sys.executable,ROOT/'tools/ci/validate_editor_clients.py','--directory',clients_output])
    clients_report=json.loads((clients_output/'parsed-settings.json').read_text(encoding='utf-8'))
    if not clients_report.get('passed')or clients_report.get('clients')!=26 or not clients_report.get('deepseek_harness_verified'):
        raise RuntimeError('The complete 26-client registry did not validate')
    run('no-original-data',[launcher,'--headless','--audio-driver','Dummy','--','--check-content',f'--engine-config={output/"absent-connection.json"}'],expected=2)
    if args.gui:
        run('first-setup-window',[launcher,'--audio-driver','Dummy','--quit-after','5','--','--setup',f'--engine-config={output/"gui-connection.json"}'],timeout=45)
        cancel_output=output/'editor-source-cancel';cancel_output.mkdir(parents=True,exist_ok=True)
        run('original-folder-escape-return',[launcher,'--audio-driver','Dummy','--script',ROOT/'game/tests/test_editor_source_link.gd','--',
            f'--source-link-output={cancel_output}',f'--source-link-connection={cancel_output/"connection.json"}','--source-link-embedded-esc'],timeout=45)
        cancel_report=json.loads((cancel_output/'result.json').read_text(encoding='utf-8'))
        if not cancel_report.get('passed')or not cancel_report.get('synthetic_only'):
            raise RuntimeError('Original-folder Escape did not restore the editor')
    run('graphics-parser-fixtures',[sys.executable,'-m','unittest','tools.converters.test_graphics'])
    run('scenario-parser-fixtures',[sys.executable,'-m','unittest','tools.converters.scenario_support.test_scenario'])
    run('table-audio-save-parser-fixtures',[sys.executable,ROOT/'tools/converters/tables_audio_support/test_conversion.py'])
    mcp_suite=run('editor-mcp-protocol-and-live-bridge',
                  [sys.executable,'-m','unittest','discover','-s','tools/tests','-p','test_editor_mcp.py','-v'],
                  extra_env={'FT2_BRIDGE_GODOT':str(runtime)})
    if (not re.search(r'(?m)^Ran 4 tests in [0-9.]+s\s*$',mcp_suite)
            or 'OK'not in mcp_suite.splitlines()
            or re.search(r'\bskipped\b',mcp_suite,re.IGNORECASE)):
        raise RuntimeError('MCP protocol/live TCP suite must execute all four tests without skips')
    records.append({'test':'editor-mcp-live-tcp-suite-executed','passed':True,'tests':4})
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
    messages=[{'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'ft2-package-validation','version':'1'}}},
              {'jsonrpc':'2.0','method':'notifications/initialized'},
              {'jsonrpc':'2.0','id':2,'method':'tools/list'}]
    frozen_mcp=subprocess.run([str(converter),'--editor-mcp'],input=''.join(json.dumps(row)+'\n'for row in messages),
                              capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=30)
    (output/'frozen-editor-mcp.log').write_text(frozen_mcp.stdout+frozen_mcp.stderr,encoding='utf-8')
    replies=[json.loads(line)for line in frozen_mcp.stdout.splitlines()]
    if frozen_mcp.returncode or len(replies)!=2 or len(replies[-1].get('result',{}).get('tools',[]))!=14:
        raise RuntimeError('Bundled MCP stdio server did not negotiate its 14 tools')
    records.append({'test':'frozen-editor-mcp-stdio','passed':True,'tools':14})
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
            'minimum_macos':advertised_minimum,'native_minimum_versions_verified':True,
            'native_minimum_version_files':len(minimum_records),
            'synthetic_engine_checks':report['checks'],
            'synthetic_extension_checks':extension_report['checks'],'editor_control_checks':editor_report['checks'],
            'editor_baseline_synthetic_checks':baseline_report['checks'],
            'editor_scaling_checks':scaling_report['checks'],
            'editor_mcp_client_profiles':26,'editor_mcp_client_setting_checks':clients_report['checks'],
            'editor_mcp_tools':14,'editor_mcp_stdio_verified':True,
            'editor_mcp_live_tcp_tests':4,
            'editor_source_cancel_checks':cancel_report['checks']if args.gui else 0,
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
