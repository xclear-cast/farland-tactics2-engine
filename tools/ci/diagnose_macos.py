"""Compare empty/native/full editor exits on the actual Mac runner."""
from pathlib import Path
import argparse
import json
import os
import platform
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[2]


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--godot',type=Path,required=True)
    args=parser.parse_args()
    output=ROOT/'private/macos-ci/diagnostics';output.mkdir(parents=True,exist_ok=True)
    library=ROOT/'game/native/bin/libft2synth.macos.arm64.dylib';library.parent.mkdir(parents=True,exist_ok=True)
    subprocess.run(['xcrun','clang','-arch','arm64','-dynamiclib','-O2','-fvisibility=hidden','-I',str(ROOT/'game/native'),str(ROOT/'game/native/ft2_synth.c'),'-framework','CoreGraphics','-o',str(library)],check=True,timeout=90)
    subprocess.run(['codesign','--force','--sign','-',str(library)],check=True,timeout=30)
    empty=output/'empty';empty.mkdir(exist_ok=True)
    (empty/'project.godot').write_text('config_version=5\n[application]\nconfig/name="FT2 Mac diagnostic"\n',encoding='utf-8')
    (empty/'quit.gd').write_text('extends SceneTree\nfunc _initialize():\n\tquit(0)\n',encoding='utf-8')
    native=output/'native';native.mkdir(exist_ok=True)
    shutil.copyfile(empty/'project.godot',native/'project.godot')
    shutil.copytree(ROOT/'game/native',native/'native',dirs_exist_ok=True,ignore=shutil.ignore_patterns('include','*.c'))
    (native/'quit.gd').write_text('extends SceneTree\nfunc _initialize():\n\tvar instance = ClassDB.instantiate("FT2NativeSynth")\n\tinstance = null\n\tquit(0)\n',encoding='utf-8')
    def cold_copy(name,source):
        target=output/name
        shutil.copytree(source,target,dirs_exist_ok=True,ignore=shutil.ignore_patterns('.godot'))
        return target
    native_default=cold_copy('native-default-cold',native)
    native_dummy=cold_copy('native-dummy-cold',native)
    native_delayed=cold_copy('native-delayed-cold',native)
    native_runtime=cold_copy('native-runtime',native)
    (native_runtime/'.godot').mkdir(exist_ok=True)
    (native_runtime/'.godot/extension_list.cfg').write_text('res://native/ft2_synth.gdextension\n',encoding='utf-8')
    no_extension=output/'full-no-extension'
    shutil.copytree(ROOT/'game',no_extension,dirs_exist_ok=True,ignore=shutil.ignore_patterns('.godot','native'))
    full_delayed=cold_copy('full-delayed-cold',ROOT/'game')
    cases=[('empty-editor-default',empty,True,False),('empty-runtime',empty,False,True),
           ('native-editor-default',native_default,True,False),('native-editor-dummy',native_dummy,True,True),
           ('native-runtime-dummy',native_runtime,False,True),('full-no-extension-editor-dummy',no_extension,True,True),
           ('full-editor-dummy',ROOT/'game',True,True),('native-editor-delayed',native_delayed,True,True),
           ('full-editor-delayed',full_delayed,True,True)]
    reports=[]
    for name,path,editor,dummy in cases:
        command=[str(args.godot),'--headless','--path',str(path)]
        if dummy:command+=['--audio-driver','Dummy']
        if name.endswith('-delayed'):command+=['--frame-delay','1000']
        command+=['--editor','--import','--quit']if editor else ['--script','res://quit.gd']
        try:
            result=subprocess.run(command,env=dict(os.environ,GODOT_SILENCE_ROOT_WARNING='1'),capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=75)
            text=result.stdout+result.stderr;code=result.returncode
        except subprocess.TimeoutExpired as error:
            text=str(error);code='timeout'
        (output/(name+'.log')).write_text(text,encoding='utf-8')
        record={'case':name,'returncode':code,'passed':code==0,'command':command}
        reports.append(record);print(json.dumps(record),flush=True)
    report={'platform':platform.platform(),'architecture':platform.machine(),'cases':reports,
            'scope':'Diagnostic comparison only; a failed case is recorded, not counted as a passing build.'}
    (output/'result.json').write_text(json.dumps(report,indent=2),encoding='utf-8')


if __name__=='__main__':main()
