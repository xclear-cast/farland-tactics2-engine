"""Create self-authored v2 fixtures; no original game or converted cache input."""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from run_tests import fixtures,dump


def prepare(output):
    output=Path(output).resolve()
    fixtures(output)
    for table,stride in (('race',86),('magic',64)):
        target=output/f'cache/fixtures/{table}.dat'
        raw=bytearray(target.read_bytes());offset=stride
        if table=='race':
            for index,value in enumerate((100,20,10,5,10,5,10)):struct.pack_into('<h',raw,offset+22+4*index,value)
            for index in range(8):struct.pack_into('<H',raw,offset+62+2*index,4 if index else 99)
            struct.pack_into('<HH',raw,offset+58,4,4)
        else:
            for position,value in ((20,1),(22,6),(24,5),(30,1),(32,3),(48,0),(50,1),(52,65535)):struct.pack_into('<H',raw,offset+position,value)
        target.write_bytes(raw);(output/f'source/DATA/{table.upper()}.DAT').write_bytes(raw)
        path=output/f'cache/data/port_ready/tables/{table}.dat.json'
        document=json.loads(path.read_text(encoding='utf-8'));document['records'][1]['raw_record_hex']=bytes(raw[offset:offset+stride]).hex();dump(path,document)
    dump(output/'cache/assets/indexed/manifest.json',{'apds':{'CHAR_00A':'unused','CHAR_00B':'unused','CHAR_00E':'unused'},'maps':{}})
    manifest_path=output/'cache/content.json';manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    manifest['source_files']={p.relative_to(output/'source').as_posix():hashlib.sha256(p.read_bytes()).hexdigest()for p in (output/'source').rglob('*')if p.is_file()}
    manifest['files']=[{'path':p.relative_to(output/'cache').as_posix(),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}for p in (output/'cache').rglob('*')if p.is_file()and p.name!='content.json'];dump(manifest_path,manifest)
    dump(output/'extension/mod.json',{'schema':2,'id':'definition_test','content':'content.json'})
    dump(output/'extension/content.json',{'schema':1,'characters':[
        {'id':'hero','name':'힣 매우 긴 새로운 영웅 이름','base_race':1,'sprite':'CHAR_00E','skills':['spark'],'stats':{'hp.initial':120,'mp.initial':30,'int.initial':30}},
        {'id':'foe','name':'시험 상대','base_race':1,'sprite':'CHAR_00E','skills':['spark'],'stats':{'hp.initial':100,'mp.initial':30}}],
        'skills':[{'id':'spark','name':'힣 새로운 번개','base_skill':1,'visual_skill':1,'mp':3,'power':12,'range_min':1,'range_max':3}],
        'maps':[],'stories':[]})
    return output


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,required=True)
    print(json.dumps({'fixtures':str(prepare(parser.parse_args().output)),'original_data_used':False}))
