"""PRIVATE original-data smoke test. Never uploads files or writes screenshots.

This helper is opt-in and requires explicit original/cache/executable paths. Do
not place original data, converted caches, or this helper's private reports in a
public repository/artifact. Mac gameplay verification is performed on the user's
Mac unless the user separately authorizes a different destination.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess

ROOT=Path(__file__).resolve().parents[2]


def digest(path):
    with path.open('rb')as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def snapshot(root):
    result={}
    for path in sorted(root.rglob('*')):
        if path.name=='.DS_Store'or path.name.startswith('._'):continue
        if path.is_symlink():raise ValueError('Original-installation links are unsupported')
        if path.is_file():result[path.relative_to(root).as_posix()]=digest(path)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',type=Path,required=True)
    parser.add_argument('--pack',type=Path,required=True)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--cache',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--mod',type=Path,default=ROOT/'mods/example_balance')
    parser.add_argument('--gui',action='store_true')
    args=parser.parse_args()
    for key in ('godot','pack','source','cache','output','mod'):setattr(args,key,getattr(args,key).expanduser().resolve())
    if args.output.is_relative_to(args.source)or args.output.is_relative_to(args.cache):
        parser.error('Private output must be outside original installation/cache')
    args.output.mkdir(parents=True,exist_ok=True)
    before=snapshot(args.source)
    report=args.output/'engine_result.json'
    command=[str(args.godot),'--audio-driver','Dummy','--path',str(args.pack.parent),'--main-pack',str(args.pack),
             '--script',str(ROOT/'game/tests/test_real_installation.gd')]
    if not args.gui:command.insert(1,'--headless')
    command+=['--',f'--real-source={args.source}',f'--real-cache={args.cache}',f'--real-report={report}',f'--real-mod={args.mod}']
    completed=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=900,
                             env=dict(os.environ,GODOT_SILENCE_ROOT_WARNING='1'))
    log=completed.stdout+completed.stderr
    (args.output/'engine.log').write_text(log,encoding='utf-8')
    after=snapshot(args.source)
    changed=[name for name in sorted(set(before)|set(after))if before.get(name)!=after.get(name)]
    diagnostics=[line for line in log.splitlines()if line.startswith(('ERROR:','SCRIPT ERROR:'))]
    engine=json.loads(report.read_text(encoding='utf-8'))if report.is_file()else {'passed':False,'failures':['Engine report missing']}
    result={'passed':completed.returncode==0 and not diagnostics and not changed and bool(engine.get('passed')),
            'source_file_count':len(before),'source_files_changed':changed,'engine_exit_code':completed.returncode,
            'engine_diagnostics':diagnostics,'engine':engine,'network_upload_performed':False,'screenshots_written':False}
    (args.output/'validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'passed':result['passed'],'source_file_count':len(before),'source_files_changed':len(changed),
                      'engine_failures':engine.get('failures',[]),'private_report':str(args.output/'validation.json')},ensure_ascii=False))
    if not result['passed']:raise SystemExit(1)


if __name__=='__main__':main()
