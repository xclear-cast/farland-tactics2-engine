"""Convert FT2 scenario files and PE UI resources using only the selected game.

No Windows APIs, executable launch, cached game data or non-stdlib package is
required. The canonical Korean executable profile is currently supported.
"""
from pathlib import Path
import base64
import collections
import hashlib
import json
import struct

from .scenario_support.core import case_path, cstring, digest, label_table, pe_sections, u32_va, va_offset, write_json
from .scenario_support.bytecode import MAIN_ROWS, SYS_NAMES, SYS_SIG, decode_command
from .scenario_support.credits import convert_credits
from .scenario_support.ui import accelerator, dialog, menu
from .scenario_support.leaf_graphs import convert_leaf_graphs

SUPPORTED_EXE = '7437429a63fd5773e152550a59161a1eeefdd3fa3da66cad1d46e232d8097f4c'
TYPES = {1:'cursor',2:'bitmap',3:'icon',4:'menu',5:'dialog',6:'string_table',9:'accelerator',10:'rcdata',12:'group_cursor',14:'group_icon',16:'version'}


def normalize_event(path, variant):
    raw=path.read_bytes(); header=label_table(raw)
    starts=sorted({entry['target_file_offset'] for entry in header['labels']})
    labels=collections.defaultdict(list)
    for entry in header['labels']:labels[entry['target_file_offset']].append(entry['name'])
    commands={};blocks=[]
    for i,start in enumerate(starts):
        end=starts[i+1] if i+1<len(starts)else len(raw)
        offset=start;refs=[];unresolved=None
        while offset<end:
            try:
                command,next_offset=decode_command(raw,offset)
                if next_offset>end:raise ValueError('command crosses label boundary')
            except (ValueError,IndexError,struct.error)as error:
                unresolved={'offset':offset,'end_offset':end,'reason':str(error),'raw_hex':raw[offset:end].hex()};break
            commands[offset]=command;refs.append(offset);offset=next_offset
            if command['opcode']==0 and not 1<=command['system_id']<=57:
                unresolved={'offset':offset,'end_offset':end,'reason':'Unsupported system selector; remaining bytes preserved','raw_hex':raw[offset:end].hex()};break
        block={'offset':start,'end_offset':end,'labels':labels[start],'command_offsets':refs,'unresolved':unresolved}
        rebuilt=b''.join(bytes.fromhex(commands[q]['raw_hex'])for q in refs)
        if unresolved:rebuilt+=bytes.fromhex(unresolved['raw_hex'])
        if rebuilt!=raw[start:end]:raise ValueError('EVENT byte roundtrip mismatch')
        blocks.append(block)
    targets={entry['name'].lower():entry['target_file_offset']for entry in header['labels']}
    for command in commands.values():
        op=command['opcode'];args=command['operands'];flow={'fallthrough':command['end_offset']}
        if op in(32,39,40,46):
            target=args[-1]['text'];flow.update(label=target,target_offset=targets.get(target.lower()),kind='conditional_jump'if op in(39,40)else'single_slot_call'if op==46 else'jump')
            if op in(32,46):flow.pop('fallthrough')
        elif op==47:flow={'kind':'single_slot_return'}
        elif op==60:flow={'kind':'chain_event','event_number':args[0]['value'],'label':args[1]['text']}
        elif op in(36,54)or op is None or op>63:flow={'kind':'terminate_or_leave_script_game_mode'}
        command['control_flow']=flow
    return {'source_path':str(path),'variant':variant,'sha256':digest(raw),'bytes':len(raw),'header':header,'blocks':blocks,'commands':list(commands.values()),
            'status':'complete_structural_parse'if not any(block['unresolved']for block in blocks)else'partial_with_lossless_unresolved',
            'source_raw_base64':base64.b64encode(raw).decode('ascii')}


def dispatch_and_bindings(exe, output):
    main=[]
    for opcode,(name,signature,address,operation)in enumerate(MAIN_ROWS):
        actual=u32_va(exe,0x43f044+opcode*4)
        if actual!=int(address,16):raise ValueError(f'Unexpected main dispatch handler {opcode}')
        main.append({'opcode':opcode,'opcode_hex':f'{opcode:02x}','handler_va':hex(actual),'name':name,'signature':signature,'operation':operation})
    system=[{'system_id':i+1,'handler_va':hex(u32_va(exe,0x44064c+i*4)),'name':name,'signature':signature}for i,(name,signature)in enumerate(zip(SYS_NAMES,SYS_SIG))]
    write_json(output/'spec/main_dispatch.json',{'source_exe_sha256':digest(exe),'table_va':'0x43F044','entries':main})
    write_json(output/'spec/system_dispatch.json',{'source_exe_sha256':digest(exe),'table_va':'0x44064C','entries':system})
    names=[]
    for index in range(30):
        address=u32_va(exe,0x449ed0+index*4)
        try:
            text,_=cstring(exe,va_offset(exe,address));names.append({'speaker_id':index,'name_va':hex(address),**text})
        except ValueError:names.append({'speaker_id':index,'name_va':hex(address),'status':'not_cstring_pointer'})
    visual=[{'index':index,'state_selector_word':struct.unpack_from('<h',exe,va_offset(exe,0x44ae28)+index*4)[0],
             'second_parameter_word':struct.unpack_from('<h',exe,va_offset(exe,0x44ae28)+index*4+2)[0]}for index in range(48)]
    write_json(output/'spec/runtime_bindings.json',{'source_exe_sha256':digest(exe),'speaker_name_table':names,'visual_sequence_selector':{'entries':visual},
        'time_contract':{'unit':'milliseconds'},'adapter':'canonical-profile-read-only-data-extraction'})


def convert_vsllst(source, output, variant):
    path=case_path(source,f'{variant}/VSLLST.DAT');raw=path.read_bytes()
    if len(raw)%30:raise ValueError('VSLLST record length mismatch')
    rows=[]
    for index in range(len(raw)//30):
        record=raw[index*30:(index+1)*30]
        selector,cue,resource_id=struct.unpack_from('<3H',record)
        name=record[6:22].split(b'\0')[0].decode('ascii')
        state,a0,a1,a2=struct.unpack_from('<4H',record,22)
        try:bitmap=str(case_path(source,'BMP/'+name+'.BMP'))
        except FileNotFoundError:bitmap=None
        rows.append({'index':index,'offset':index*30,'raw_hex':record.hex(),'sequence_selector':selector,'cue_index':cue,'resource_id':resource_id,
                     'bitmap_stem':name,'initial_runtime_load_state':state,'load4271F0_arg2':a0,'load4271F0_arg3':a1,'load4271F0_arg4':a2,'bitmap_path':bitmap})
    if b''.join(bytes.fromhex(row['raw_hex'])for row in rows)!=raw:raise ValueError('VSLLST byte roundtrip mismatch')
    write_json(output/'cinematics'/variant/'VSLLST.json',{'source_path':str(path),'sha256':digest(raw),'bytes':len(raw),'record_bytes':30,'record_count':len(rows),'records':rows,'roundtrip':'PASS'})
    return len(rows)


def pe_resources(raw):
    pe=struct.unpack_from('<I',raw,0x3c)[0]
    if raw[pe:pe+4]!=b'PE\0\0':raise ValueError('Not a PE executable')
    opt=pe+24
    if struct.unpack_from('<H',raw,opt)[0]!=0x10b:raise ValueError('Only PE32 resources supported')
    image,sections=pe_sections(raw)
    rva,size=struct.unpack_from('<II',raw,opt+96+2*8)
    base=va_offset(raw,image+rva)
    def name(value):
        if not value&0x80000000:return value
        position=base+(value&0x7fffffff);length=struct.unpack_from('<H',raw,position)[0]
        return raw[position+2:position+2+length*2].decode('utf-16le')
    def directory(position,trail):
        if len(trail)>3:raise ValueError('Resource tree too deep')
        absolute=base+position
        named,numbered=struct.unpack_from('<HH',raw,absolute+12)
        for index in range(named+numbered):
            identity,child=struct.unpack_from('<II',raw,absolute+16+index*8)
            current=trail+[name(identity)]
            if child&0x80000000:yield from directory(child&0x7fffffff,current)
            else:
                if len(current)!=3:raise ValueError('Unsupported resource level')
                data_rva,length,code_page,_=struct.unpack_from('<4I',raw,base+child)
                offset=va_offset(raw,image+data_rva);blob=raw[offset:offset+length]
                if len(blob)!=length:raise ValueError('Truncated resource payload')
                yield current,data_rva,code_page,blob
    yield from directory(0,[])


def convert_ui(exe_path, output):
    raw=exe_path.read_bytes();target=output/'FTO_O';target.mkdir(parents=True,exist_ok=True)
    entries=[];errors=[];counts=collections.Counter()
    for (kind,identity,language),rva,code_page,blob in pe_resources(raw):
        typename=TYPES.get(kind,f'type{kind}')
        # Named resources are untrusted path components.
        if not str(identity).replace('_','').isalnum():raise ValueError('Unsafe PE resource name')
        stem=f'{typename}_{identity}_lang{language}';filename=stem+'.bin'
        (target/filename).write_bytes(blob)
        row={'type_id':kind,'type':typename,'id':identity,'language_id':language,'code_page':code_page,'rva':hex(rva),'bytes':len(blob),'sha256':digest(blob),'raw_file':filename}
        try:
            if kind==5:row['decoded']=dialog(blob)
            elif kind==4:row['decoded']=menu(blob)
            elif kind==9:row['decoded']=accelerator(blob)
            if 'decoded'in row:write_json(target/(stem+'.json'),row['decoded'])
        except (ValueError,IndexError,struct.error)as error:
            row['decode_error']=str(error);errors.append({'file':filename,'error':str(error)})
        entries.append(row);counts[typename]+=1
    write_json(target/'index.json',{'exe':str(exe_path),'sha256':digest(raw),'counts':dict(counts),'decode_errors':errors,'resources':entries})
    if errors:raise ValueError('UI decoding errors: '+str(errors))
    return len(entries)


def convert(source: Path, output: Path, *, include_leaf_graphs: bool = False) -> dict:
    source,output=Path(source).resolve(),Path(output).resolve()
    if output.is_relative_to(source):raise ValueError('Output must be outside the source installation')
    exe_path=case_path(source,'FTO_O.EXE');exe=exe_path.read_bytes()
    if digest(exe)!=SUPPORTED_EXE:raise ValueError('Unsupported executable profile; no guessed offsets will be used')
    scripts=output/'data/port_ready/scripts';files=[];vsllst={}
    dispatch_and_bindings(exe,scripts)
    for variant in ('DATA','VDAT'):
        try:folder=case_path(source,variant)
        except FileNotFoundError:continue
        for path in sorted(folder.iterdir()):
            if not(path.is_file()and path.name.upper().startswith('EVENT')and path.suffix.upper()=='.DAT'):continue
            document=normalize_event(path,variant)
            write_json(scripts/'normalized'/variant/(path.stem.upper()+'.json'),document)
            files.append({'variant':variant,'file':path.name,'commands':len(document['commands']),'status':document['status']})
        try:vsllst[variant]=convert_vsllst(source,scripts,variant)
        except FileNotFoundError:pass
    convert_credits(source,scripts)
    resource_count=convert_ui(exe_path,output/'data/port_ready/ui')
    leaf_report=convert_leaf_graphs(source,output)if include_leaf_graphs else None
    return {'converter':'scenario-v1','event_files':len(files),'commands':sum(row['commands']for row in files),'events':files,
            'vsllst_records':vsllst,'ui_resources':resource_count,'exe_unchanged':digest(exe_path.read_bytes())==digest(exe),
            'cinematic_leaf_graphs_generated':include_leaf_graphs,
            'leaf_graphs':leaf_report,
            'remaining':[]if include_leaf_graphs else['Run convert_leaf_graphs or include_leaf_graphs=True for cinematic controllers; no cache fallback was used']}
