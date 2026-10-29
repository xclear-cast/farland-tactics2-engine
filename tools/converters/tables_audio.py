"""Standalone FT2 table/save/text/audio conversion from a user's installation.

Only Python's standard library is required. Importing this module does not read
any workspace or game files. All generated game content belongs in a PRIVATE
cache; neither this module nor its tests contain original game data.
"""
from __future__ import annotations

from collections import Counter
from pathlib import Path
import argparse
import hashlib
import json
import re
import struct

try:
    from .tables_audio_support.tables import decode_items, decode_magic, decode_race, decode_stage
    from .tables_audio_support.saves import decode_bytes, encode_bytes
    from .tables_audio_support.audio import szdd_decompress, wav_info, midi_info
except ImportError:  # Direct CLI invocation as well as package import.
    from tables_audio_support.tables import decode_items, decode_magic, decode_race, decode_stage
    from tables_audio_support.saves import decode_bytes, encode_bytes
    from tables_audio_support.audio import szdd_decompress, wav_info, midi_info


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def dump(path: Path, document) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document, ensure_ascii=False, indent=2)+'\n', encoding='utf-8', newline='\n')


def find(root: Path, relative: str, *, required: bool = True) -> Path | None:
    """Resolve an installation path without relying on filesystem case rules."""
    current = Path(root)
    for component in relative.replace('\\','/').split('/'):
        if not component or component in ('.','..'):
            raise ValueError(f'Unsafe installation path: {relative}')
        if not current.is_dir():
            if required: raise FileNotFoundError(relative)
            return None
        matches = [p for p in current.iterdir() if p.name.casefold()==component.casefold()]
        if len(matches)!=1:
            if not required and not matches:return None
            raise ValueError(f'Missing or ambiguous installation path: {relative}')
        current=matches[0]
        if current.is_symlink():raise ValueError(f'Symbolic links are unsupported: {relative}')
    return current


def files(directory: Path | None, suffix: str | None = None):
    if directory is None:return []
    result=[]
    for path in directory.rglob('*'):
        if path.name=='.DS_Store' or path.name.startswith('._'):continue
        if path.is_symlink():raise ValueError(f'Symbolic links are unsupported: {path.name}')
        if path.is_file() and (suffix is None or path.suffix.casefold()==suffix.casefold()):result.append(path)
    return sorted(result,key=lambda p:p.relative_to(directory).as_posix().casefold())


def _decoded(data: bytes) -> bytes:
    if not data.startswith(b'SZDD'):return data
    if len(data)<14:raise ValueError('Truncated SZDD header')
    size=struct.unpack_from('<I',data,10)[0]
    result=szdd_decompress(data)
    if len(result)!=size:raise ValueError('Truncated SZDD stream')
    return result


def _midi_payload(raw: bytes) -> bytes:
    data=_decoded(raw)
    if data.startswith(b'MThd'):return data
    if data[:4]==b'RIFF' and data[8:12]==b'RMID':
        pos=12
        while pos+8<=len(data):
            kind=data[pos:pos+4];size=struct.unpack_from('<I',data,pos+4)[0];start=pos+8
            if start+size>len(data):raise ValueError('Truncated RIFF MIDI chunk')
            if kind==b'data':
                payload=data[start:start+size]
                if not payload.startswith(b'MThd'):raise ValueError('RIFF data is not MIDI')
                return payload
            pos=start+size+(size&1)
    raise ValueError('Unsupported MIDI container; expected MThd or RIFF/RMID')


def _write_bytes(target: Path, data: bytes):
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_bytes(data)


def _convert_tables(source: Path, output: Path) -> dict:
    destination=output/'data/port_ready/tables'
    counts={};records_total=0
    for name,stride,parser in (
        ('item',56,lambda p:list(decode_items(p,include_empty=True).values())),
        ('magic',64,lambda p:decode_magic(p,include_placeholders=True)),
        ('race',86,decode_race),
    ):
        path=find(source,f'DATA/{name.upper()}.DAT');raw=path.read_bytes()
        if len(raw)%stride:raise ValueError(f'{path.name} is not a multiple of {stride} bytes')
        rows=parser(path)
        if b''.join(bytes.fromhex(row['raw_record_hex'])for row in rows)!=raw:raise ValueError(f'{name} roundtrip failed')
        for row in rows:
            row['entry_role']='sentinel' if row['id']==0 and name!='race' else 'placeholder' if row.get('name') in (None,'','결번') else 'named'
        dump(destination/f'{name}.dat.json',{'source_file':f'DATA/{path.name}','sha256':sha(raw),
             'record_stride':stride,'record_count':len(rows),'index_semantics':'Array index equals original ID; placeholders retained.',
             'records':rows})
        _write_bytes(output/f'fixtures/{name}.dat',raw)
        counts[name]=len(rows);records_total+=len(rows)
    stages={}
    for path in files(find(source,'DATA'),'.dat'):
        if not re.fullmatch(r'STAGE\d+',path.stem,re.IGNORECASE):continue
        raw=path.read_bytes()
        if len(raw)%28:raise ValueError(f'Invalid placement stride: {path.name}')
        rows=decode_stage(path)
        if b''.join(bytes.fromhex(row['raw_record_hex'])for row in rows)!=raw:raise ValueError(f'Placement roundtrip failed: {path.name}')
        stages[path.stem.upper()]={'sha256':sha(raw),'record_count':len(rows),'records':rows}
    dump(destination/'stages.json',stages)
    return {'records':counts,'stages':len(stages),'placements':sum(row['record_count']for row in stages.values()),
            'all_table_bytes_roundtrip':True}


def _convert_saves(source: Path, output: Path) -> dict:
    destination=output/'data/port_ready/saves';count=0;empty_slots=[]
    for path in files(find(source,'SAVE',required=False),'.dat'):
        if not re.fullmatch(r'SAVE\d+',path.stem,re.IGNORECASE):continue
        raw=path.read_bytes()
        # The game's slot list treats a missing header or a zero header-size
        # DWORD as unregistered. Empty slots have no game state to decode.
        if len(raw)<4 or struct.unpack_from('<I',raw,0)[0]==0:
            empty_slots.append(path.name)
            continue
        if len(raw)!=6848:raise ValueError(f'Unsupported save length {len(raw)}: {path.name}')
        document=decode_bytes(raw)
        if encode_bytes(document)!=raw:raise ValueError(f'Save roundtrip failed: {path.name}')
        dump(destination/(path.stem.lower()+'.json'),document);count+=1
    # The scenario converter must run before final map bindings can be resolved.
    dump(destination/'map_bindings.json',{'method':'Pending bounded EVENT Restart evaluation',
         'rows':[],'resolved_count':0,'pending_scenario_conversion':count>0})
    return {'saves':count,'all_save_bytes_roundtrip':True,'map_bindings_pending':count>0,
            'empty_saves_skipped':len(empty_slots),'empty_save_slots':empty_slots,
            'save_roundtrip_scope':'Non-empty saves; empty slot files remain unchanged in the source installation.'}


def _convert_text(source: Path, output: Path) -> dict:
    destination=output/'data/port_ready/assets/text/canonical_DAT';rows=[]
    for path in files(find(source,'DATA')):
        if path.suffix.casefold()!='.txt' and not(path.suffix.casefold()=='.dat' and path.stem.upper().endswith('COM')):continue
        raw=path.read_bytes();target=destination/path.name.upper();_write_bytes(target,raw)
        row={'source':'DATA/'+path.name,'source_sha256':sha(raw),'raw_file':target.relative_to(output).as_posix(),'encoding':'CP949','profile':'canonical_DAT'}
        if path.suffix.casefold()=='.txt':
            decoded=raw.decode('cp949','strict');target.with_suffix('.utf8.txt').write_text(decoded,encoding='utf-8')
        else:
            if len(raw)<1024:raise ValueError(f'Comment table is shorter than its pointer table: {path.name}')
            pointers=list(struct.unpack_from('<256I',raw));entries=[]
            for index,offset in enumerate(pointers):
                if offset==0:continue
                if not 1024<=offset<=len(raw):raise ValueError(f'Invalid comment pointer {index} in {path.name}')
                end=raw.find(b'\0',offset);end=len(raw)if end<0 else end;text_bytes=raw[offset:end]
                try:decoded=text_bytes.decode('cp949','strict');error=None
                except UnicodeDecodeError as exc:decoded=None;error=str(exc)
                entries.append({'index':index,'absolute_byte_offset':offset,'raw_hex':text_bytes.hex(),'text':decoded,'CP949_decode_error':error})
            dump(Path(str(target)+'.json'),{'pointers_u32':pointers,'entries':entries})
            row['entry_count']=len(entries)
        rows.append(row)
    dump(output/'data/port_ready/assets/text/index.json',{'schema_version':1,'files':rows})
    return {'text_files':len(rows)}


def _codec(output: Path) -> dict:
    decode={};encode={}
    for code in range(0x10000):
        if 0xD800<=code<=0xDFFF:continue
        try:raw=chr(code).encode('cp949','strict')
        except UnicodeEncodeError:continue
        encode[str(code)]=list(raw)
        if len(raw)<=2:decode[str(int.from_bytes(raw,'big'))]=code
    # Decode aliases as well as Python's canonical encoder choices.
    for lead in range(128,256):
        for trail in range(256):
            try:text=bytes((lead,trail)).decode('cp949','strict')
            except UnicodeDecodeError:continue
            if len(text)==1:decode[str(lead*256+trail)]=ord(text)
    dump(output/'assets/cp949.json',{'decode':decode,'encode':encode})
    return {'cp949_encode_characters':len(encode),'cp949_decode_sequences':len(decode)}


def _convert_audio(source: Path, output: Path, cdda_source: Path | None) -> dict:
    destination=output/'data/port_ready/assets/audio';waves=[];midis=[];errors=[];used=set()
    wave_dir=find(source,'WAVE',required=False)
    for path in files(wave_dir,'.wav'):
        relative=path.relative_to(wave_dir);logical='WAVE/'+relative.as_posix();raw=path.read_bytes()
        data=_decoded(raw);target=destination/'wave'/relative.with_suffix('.wav')
        logical_target=target.relative_to(output).as_posix()
        if logical_target.casefold()in used:raise ValueError(f'Duplicate audio filename: {logical}')
        used.add(logical_target.casefold())
        row={'source':logical,'source_sha256':sha(raw),'bytes':len(raw),'portable_file':logical_target,'portable_sha256':sha(data)}
        # Preserve even malformed original resources; never invent a repaired sound.
        _write_bytes(target,data)
        try:
            if data[:4]!=b'RIFF' or data[8:12]!=b'WAVE':raise ValueError('Not RIFF/WAVE')
            row.update(wav_info(data))
            if not row['godot_native_pcm_wav_candidate']:raise ValueError('Only original PCM 8/16-bit WAV is supported')
        except Exception as exc:row['error']=str(exc);errors.append({'source':logical,'error':str(exc)})
        waves.append(row)
    midi_dir=find(source,'MIDI',required=False)
    for path in files(midi_dir):
        relative=path.relative_to(midi_dir);logical='MIDI/'+relative.as_posix();raw=path.read_bytes()
        row={'source':logical,'source_sha256':sha(raw),'bytes':len(raw),'variant':'GS'if '_GS.'in path.name.upper()else'GM_or_unspecified'}
        target=destination/'midi'/relative
        if path.suffix.casefold()=='.mid':
            try:
                data=_midi_payload(raw);parsed=midi_info(data);_write_bytes(target,data)
                events=destination/'midi_events'/relative.with_suffix('.json');dump(events,parsed)
                row.update(format=parsed['format'],track_count=len(parsed['tracks']),division=parsed['division_raw'],duration_s=parsed['duration_s_from_tempo_map'],events_json=events.relative_to(output).as_posix())
            except Exception as exc:row['error']=str(exc);errors.append({'source':logical,'error':str(exc)})
        else:
            _write_bytes(target,raw);row['status']='Opaque source file preserved; not interpreted as playable MIDI'
        row['portable_file']=target.relative_to(output).as_posix();midis.append(row)
    dump(destination/'index.json',{'schema_version':1,'wave_count':len(waves),'midi_directory_count':len(midis),'WAV':waves,'MIDI':midis,'errors':errors,
         'wav_format_counts':dict(Counter(str(row.get('format_tag'))for row in waves)),
         'policy':'Original payloads copied or decoded only from user installation; no generated substitute music.'})
    cdda=[]
    if cdda_source is not None:
        cdda_source=Path(cdda_source).resolve()
        if not cdda_source.is_dir():raise ValueError('CD audio directory does not exist')
        for index in range(25):
            path=find(cdda_source,f'BGM{index:02d}_CDDA.wav',required=False)
            if path is None:continue
            data=path.read_bytes()
            if data[:4]!=b'RIFF'or data[8:12]!=b'WAVE':raise ValueError(f'CD audio is not RIFF/WAVE: {path.name}')
            info=wav_info(data)
            if not info['godot_native_pcm_wav_candidate']:raise ValueError(f'CD audio is not PCM 8/16-bit: {path.name}')
            target=output/f'data/port_ready/analysis_completion/backend/cdda/BGM{index:02d}_CDDA.wav';_write_bytes(target,data)
            cdda.append({'index':index,'sha256':sha(data),'portable_file':target.relative_to(output).as_posix()})
    dump(destination/'availability.json',{'effects_available':any('error'not in row for row in waves),'effects_complete':not errors,
         'wav_playable_count':sum('error'not in row for row in waves),'midi_files_available':sum(path.suffix.casefold()=='.mid'for path in files(midi_dir)),
         'cdda_tracks':cdda,'cdda_complete':len(cdda)==25,'midi_requires_playback_backend_and_soundfont':True,
         'missing_cdda_policy':'No CD music is invented or silently copied from an unrelated cache.'})
    return {'wav_files':len(waves),'midi_directory_files':len(midis),'audio_errors':errors,'cdda_tracks':len(cdda),'cdda_complete':len(cdda)==25}


def resolve_save_restart(raw: bytes, output: Path) -> dict:
    """Bounded static evaluation of the save's EVENT Restart entry."""
    chapter=struct.unpack_from('<h',raw,4)[0];round_index=struct.unpack_from('<h',raw,0x26)[0]
    event=0 if round_index<0 else chapter;variables=list(struct.unpack_from('<100h',raw,0x28))
    tail=struct.unpack_from('<I',raw,0)[0]+6200
    mode=3 if struct.unpack_from('<I',raw,tail+0xB0)[0]else 2 if struct.unpack_from('<I',raw,tail+0xA8)[0]>=1 else 1
    document=json.loads((output/f'data/port_ready/scripts/normalized/DATA/EVENT{event:02d}.json').read_text(encoding='utf-8'))
    labels={row['name'].lower():row['target_file_offset']for row in document['header']['labels']}
    commands={row['offset']:row for row in document['commands']};pc=labels['restart'];equal=greater=None;trace=[];bitmap=None
    for _ in range(1000):
        command=commands[pc];opcode=command['opcode'];args=[operand.get('value',operand.get('text'))for operand in command.get('operands',[])];flow=command.get('control_flow',{})
        trace.append({'offset':pc,'opcode':command['opcode_hex'],'name':command['name'],'args':args})
        if opcode==0x0A:return {'map_id':args[0],'event_file':event,'restart_offset':labels['restart'],'map_load_offset':pc,'saved_round_index':round_index,'control_mode':mode,'trace':trace}
        if opcode==0x32:bitmap={'resource':f'BMP/{args[0]}.BMP','transition_ms_per_palette_step':args[1],'offset':pc}
        elif opcode==0x36 and bitmap is not None:return {'presentation':'town_bitmap','bitmap':bitmap,'exit_mode':9,'event_file':event,'restart_offset':labels['restart'],'saved_round_index':round_index,'control_mode':mode,'trace':trace}
        elif opcode in (0x02,0x03,0x09,0x23,0x33):pass
        elif opcode==0:
            if command['system_id']==52:variables[args[1]]=mode
            elif command['system_id']!=1:raise ValueError(f'Unsupported pre-map system {command["system_id"]}')
        elif opcode==0x29:variables[args[0]]=(args[1]+32768)%65536-32768
        elif opcode==0x2A:variables[args[0]]=(variables[args[0]]+args[1]+32768)%65536-32768
        elif opcode==0x2C:equal=args[1]==variables[args[0]];greater=args[1]>variables[args[0]]
        elif opcode==0x20:pc=flow['target_offset'];continue
        elif opcode in (0x27,0x28):
            flag=equal if opcode==0x27 else greater
            if flag is None:raise ValueError('Uninitialized restart comparison flag')
            if flag==((args[0]&0xFFFFFFFF)>=1):pc=flow['target_offset'];continue
        else:raise ValueError(f'Unsupported pre-map opcode {opcode:02x}')
        if 'fallthrough'not in flow:raise ValueError('No map before script termination')
        pc=flow['fallthrough']
    raise ValueError('Restart evaluation exceeded bounded instruction count')


def finalize_save_bindings(output: Path) -> dict:
    output=Path(output).resolve();rows=[]
    for path in sorted((output/'data/port_ready/saves').glob('save*.json')):
        if not re.fullmatch(r'save\d+',path.stem,re.IGNORECASE):continue
        document=json.loads(path.read_text(encoding='utf-8'));raw=encode_bytes(document)
        row={'file':path.stem.lower()+'.dat','sha256':sha(raw),'header_event_id':struct.unpack_from('<h',raw,4)[0]}
        try:row.update(resolve_save_restart(raw,output),status='resolved_script_restart')
        except (ValueError,KeyError,IndexError,FileNotFoundError,struct.error)as exc:row.update(status='unresolved',error=str(exc))
        rows.append(row)
    report={'method':'Bounded static EVENT Restart evaluation using the user save and decoded event instructions.',
            'rows':rows,'resolved_count':sum(row['status']=='resolved_script_restart'for row in rows),'pending_scenario_conversion':False}
    dump(output/'data/port_ready/saves/map_bindings.json',report)
    return {'save_bindings':len(rows),'resolved_save_bindings':report['resolved_count'],'unresolved':[row for row in rows if row['status']=='unresolved']}


def convert(source: Path, output: Path, *, cdda_source: Path | None = None) -> dict:
    source=Path(source).resolve();output=Path(output).resolve()
    if not source.is_dir():raise ValueError('Installation directory does not exist')
    if output==source or output.is_relative_to(source) or source.is_relative_to(output):raise ValueError('Output must be separate from installation')
    if cdda_source is not None:
        cdda_source=Path(cdda_source).resolve()
        if output==cdda_source or output.is_relative_to(cdda_source)or cdda_source.is_relative_to(output):
            raise ValueError('Output must be separate from user CD audio input')
    output.mkdir(parents=True,exist_ok=True)
    report={'module':'tables_audio','dependencies':['Python standard library'],
            **_convert_tables(source,output),**_convert_saves(source,output),**_convert_text(source,output),
            **_codec(output),**_convert_audio(source,output,cdda_source)}
    return report


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--cdda-dir',type=Path);parser.add_argument('--finalize-bindings',action='store_true')
    options=parser.parse_args()
    report=convert(options.source,options.output,cdda_source=options.cdda_dir)
    if options.finalize_bindings:report.update(finalize_save_bindings(options.output))
    print(json.dumps(report,ensure_ascii=False))
