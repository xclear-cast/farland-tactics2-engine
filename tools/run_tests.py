"""Synthetic mount/mod tests plus optional real content tests; headless only."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from import_content import REQUIRED, verify


def dump(path, data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def fixtures(directory):
    source, cache = directory/'source', directory/'cache'
    source.mkdir(parents=True,exist_ok=True)
    (source/'DATA').mkdir(exist_ok=True)
    source_files={}
    for name,stride in [('item',56),('magic',64),('race',86)]:
        raw=bytearray(stride*2)
        raw[stride:stride+4]=b'Test'
        if name=='item':struct.pack_into('<H',raw,stride+20,30)
        if name=='magic':struct.pack_into('<h',raw,stride+22,6)
        path=source/f'DATA/{name.upper()}.DAT';path.write_bytes(raw)
        source_files[path.relative_to(source).as_posix()]=sha(path)
        target=cache/f'fixtures/{name}.dat';target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(raw)
        records=[{'id':i,'name':'Test' if i else '', 'raw_record_hex':raw[i*stride:(i+1)*stride].hex()} for i in range(2)]
        records[1]['price' if name=='item' else 'mp']=30 if name=='item' else 6
        dump(cache/f'data/port_ready/tables/{name}.dat.json',{'records':records})
    (source/'FTO_O.EXE').write_bytes(b'MZ synthetic fixture, not an original executable')
    source_files['FTO_O.EXE']=sha(source/'FTO_O.EXE')
    for key in REQUIRED:
        path=cache/key
        if path.exists():continue
        if key=='assets/cp949.json':dump(path,{'encode':{str(i):[i] for i in range(128)},'decode':{str(i):i for i in range(128)}})
        elif path.suffix=='.json':dump(path,{})
        else:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'synthetic font data')
    (cache/'custom').mkdir(exist_ok=True)
    (cache/'custom/hello.txt').write_text('base',encoding='utf-8')
    dump(cache/'custom/document.json',{'value':1,'list':[1],'remove_me':True})
    rows=[{'path':p.relative_to(cache).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)} for p in cache.rglob('*')if p.is_file()and p.name!='content.json']
    dump(cache/'content.json',{'schema':1,'status':'ready','content_id':'synthetic-v1','required':list(REQUIRED),'files':rows,'source_files':source_files})
    mods={
        'low':{'table_edits':[{'table':'item','record':1,'fields':{'price':10,'name':'Custom'}},{'table':'magic','record':1,'fields':{'mp':3}}],
               'patches':[{'target':'custom/document.json','operations':[{'op':'set','path':'/value','value':2},{'op':'append','path':'/list','value':2},{'op':'remove','path':'/remove_me'}]}]},
        'high':{'table_edits':[{'table':'item','record':1,'fields':{'price':7}}]},
        'bad_path':{'patches':[{'target':'../escape.json','operations':[]}]},
        'bad_value':{'table_edits':[{'table':'item','record':1,'fields':{'price':-1}}]},
        'bad_patch':{'patches':[{'target':'custom/document.json','operations':[{'op':'set','path':'/absent/child','value':1}]}]},
        'bad_field':{'table_edits':[{'table':'item','record':1,'fields':{'missing_field':1}}]},
        'bad_record':{'table_edits':[{'table':'item','record':999,'fields':{'price':1}}]},
    }
    for key,value in mods.items():dump(directory/key/'mod.json',{'schema':1,'id':key,**value})
    for key in ('low','high'):
        folder=directory/key/'files/custom';folder.mkdir(parents=True,exist_ok=True)
        (folder/'hello.txt').write_text(key,encoding='utf-8')
    (directory/'low/files/custom/new.txt').write_text('new',encoding='utf-8')
    dump(directory/'high/files/custom/document.json',{'value':9,'list':[],'remove_me':True})
    verify(cache)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--real-cache',type=Path)
    parser.add_argument('--real-source',type=Path)
    parser.add_argument('--pack',type=Path)
    parser.add_argument('--godot',type=Path)
    parser.add_argument('--verbose',action='store_true')
    args=parser.parse_args()
    for name in ('pack','godot','real_cache','real_source'):
        value=getattr(args,name)
        if value is not None:setattr(args,name,value.resolve())
    directory=ROOT/'private/tests'/(("windows" if os.name=='nt' else "linux")+('-pack' if args.pack else '-source'))
    fixtures(directory)
    godot=str(args.godot) if args.godot else '/opt/ft2-godot/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64'
    command=[godot,'--headless','--audio-driver','Dummy','--path',str(args.pack.parent if args.pack else ROOT/'game')]
    if args.pack:command+=['--main-pack',str(args.pack)]
    if args.verbose:command+=['--verbose']
    command+=['--script',str(ROOT/'game/tests/test_content.gd'),'--',f'--fixtures={directory}']
    if args.real_cache:command += [f'--real-cache={args.real_cache}',f'--real-source={args.real_source}']
    result=subprocess.run(command,env=dict(os.environ,GODOT_SILENCE_ROOT_WARNING='1'),capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=60)
    output=result.stdout+result.stderr
    (directory/('pack.log' if args.pack else 'source.log')).write_text(output,encoding='utf-8')
    errors=[line for line in output.splitlines()if line.startswith(('ERROR:','SCRIPT ERROR:'))]
    print(output[-8000:])
    if result.returncode or errors:raise SystemExit(1)
    report=json.loads((directory/'godot_result.json').read_text(encoding='utf-8'))
    if not report['passed']:raise SystemExit(1)


if __name__=='__main__':main()
