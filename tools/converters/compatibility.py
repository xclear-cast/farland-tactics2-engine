"""Read the supported game's small compatibility tables from its PE32 file.

Only layout addresses, instruction grammar and API schemas are encoded here.
Town captions, animation labels, lookup coefficients and missile coordinates
are read from the user's executable and are never bundled as content literals.
"""
from __future__ import annotations
from pathlib import Path
import argparse
import hashlib
import json
import re
import struct

from .scenario_support.core import pe_sections, va_offset

SUPPORTED_EXE_SHA256 = '7437429a63fd5773e152550a59161a1eeefdd3fa3da66cad1d46e232d8097f4c'


class PE:
    def __init__(self, path: Path):
        self.raw = path.read_bytes()
        self.sha256 = hashlib.sha256(self.raw).hexdigest()
        if self.sha256 != SUPPORTED_EXE_SHA256:
            raise ValueError('Compatibility table addresses require the supported FTO_O.EXE edition')
        self.base, self.sections = pe_sections(self.raw)

    def read(self, address: int, count: int) -> bytes:
        offset = va_offset(self.raw,address)
        result = self.raw[offset:offset+count]
        if len(result) != count: raise ValueError('PE read exceeds file bounds')
        return result

    def u32(self, address: int) -> int:
        return struct.unpack('<I',self.read(address,4))[0]

    def text(self, address: int, encoding='cp949') -> str:
        offset = va_offset(self.raw,address)
        end = self.raw.find(b'\0',offset,offset+4096)
        if end < 0: raise ValueError('Unterminated PE string')
        return self.raw[offset:end].decode(encoding)


def _source_file(source: Path, relative: str) -> Path:
    current = source
    for part in relative.split('/'):
        matches = [p for p in current.iterdir() if p.name.casefold() == part.casefold()]
        if len(matches) != 1 or matches[0].is_symlink(): raise ValueError('Missing/ambiguous source: '+relative)
        current = matches[0]
    return current


def _dispatch(pe: PE, first: int, last: int, selector: int, handlers: int, default: int) -> dict:
    result = {}
    for skill in range(84):
        target = pe.u32(handlers+4*pe.read(selector+skill-first,1)[0]) if first<=skill<=last else default
        result[str(skill)] = hex(target)
    return {'id_range':[first,last], 'byte_table':hex(selector), 'jump_table':hex(handlers),
            'default':hex(default), 'skill_handlers':result}


def _phase_label(pe: PE, start: int, suffix: str, seen=None) -> str:
    """Read the label push in bounded supported-edition cast-selection blocks."""
    seen = set() if seen is None else seen
    if start in seen or len(seen)>8: raise ValueError('Cast label branch cycle')
    seen.add(start)
    code = pe.read(start,160)
    for index in range(len(code)-5):
        opcode = code[index]
        if opcode == 0x68:  # PUSH immediate32, whose operand may be a string VA.
            pointer = struct.unpack_from('<I',code,index+1)[0]
            try: value = pe.text(pointer,'ascii')
            except (ValueError,UnicodeError,struct.error): continue
            if re.fullmatch(r'cast\d+'+suffix,value): return value
        elif opcode == 0xe9:
            target = start+index+5+struct.unpack_from('<i',code,index+1)[0]
            if 0x432900<=target<0x437a00:
                return _phase_label(pe,target,suffix,seen)
        elif opcode == 0xeb:
            target = start+index+2+struct.unpack_from('<b',code,index+1)[0]
            if 0x432900<=target<0x437a00:
                return _phase_label(pe,target,suffix,seen)
    raise ValueError('Cast label not found in supported selection block')


def _missile_offsets(pe: PE) -> list:
    """Decode only MOV initializers in the bounded, call-free table block.

    This is data extraction, not execution of the game. Reject every instruction
    outside the three forms present in that specific supported PE block.
    """
    code = pe.read(0x433f27,0x4340f5-0x433f27)
    registers, stack = {}, {}
    cursor = 0
    while cursor < len(code):
        opcode = code[cursor]
        if 0xb8 <= opcode <= 0xbf:  # MOV register, immediate32.
            registers[opcode-0xb8] = struct.unpack_from('<i',code,cursor+1)[0]
            cursor += 5;continue
        if opcode not in (0xc7,0x89): raise ValueError('Unsupported missile initializer instruction')
        modrm = code[cursor+1]
        mode, register, rm = modrm>>6,(modrm>>3)&7,modrm&7
        if mode not in (1,2) or rm!=4 or code[cursor+2]!=0x24:
            raise ValueError('Unsupported missile initializer addressing')
        displacement_size = 1 if mode==1 else 4
        displacement = struct.unpack_from('<b' if mode==1 else '<i',code,cursor+3)[0]
        cursor += 3+displacement_size
        if opcode==0xc7:
            if register!=0: raise ValueError('Unsupported missile immediate store')
            value=struct.unpack_from('<i',code,cursor)[0];cursor+=4
        else:
            if register not in registers:raise ValueError('Uninitialized missile-table register')
            value=registers[register]
        stack[displacement]=value
    values = [stack[0x5c+4*i] for i in range(48)]
    return [[values[12*d+2*i:12*d+2*i+2] for i in range(6)] for d in range(4)]


def convert(source: Path, output: Path) -> dict:
    source, output = Path(source).resolve(),Path(output).resolve()
    if output == source or output.is_relative_to(source):raise ValueError('Output must be outside installation')
    pe = PE(_source_file(source,'FTO_O.EXE'))
    def write(relative, data):
        target = output/relative;target.parent.mkdir(parents=True,exist_ok=True)
        target.write_text(json.dumps({'schema_version':1,'source_sha256':pe.sha256,**data},ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    specifications = [
        ('initializer',0,83,0x4346cc,0x434664,0x432ba0),
        ('cast_label_selection',14,65,0x437654,0x437628,0x434949),
        ('cast_started_effect',3,83,0x4376ec,0x437688,0x434ef9),
        ('per_child_update',3,80,0x43779c,0x437740,0x43631d),
        ('child_delay_elapsed_activation',1,81,0x437870,0x437800,0x4362bd),
        ('global_frame_update',12,83,0x437900,0x4378c4,0x4365bf)]
    tables={name:_dispatch(pe,*specification) for name,*specification in specifications}
    write('data/port_ready/effects/source_index.json',{'dispatch_tables':tables})
    write('data/port_ready/effects/spec/fixed_trig_contract.json',
          {'quarter_wave_u16':list(struct.unpack('<91H',pe.read(0x44b908,182)))})
    town = []
    for index in range(32):
        address=0x44c738+index*40
        values=list(struct.unpack('<8i2I',pe.read(address,40)))
        if values[3]==0:break
        town.append({'index':index,'address':hex(address),'hit_rect':values[:4],'marker_rect':values[4:8],
                     'label_pointer':hex(values[8]),'label':pe.text(values[8]),
                     'caption_pointer':hex(values[9]),'caption':pe.text(values[9])})
    else:raise ValueError('Town table sentinel missing')
    write('data/port_ready/analysis_completion/town/source_evidence.json',{'static_table':{'rows':town}})
    write('data/port_ready/analysis_completion/ui/shared_helpers.json',
          {'contracts':{'source_arrays':{'music_labels':[pe.text(pe.u32(0x449290+4*i)) for i in range(25)]}}})
    magic = _source_file(source,'DATA/MAGIC.DAT').read_bytes()
    if len(magic)!=84*64:raise ValueError('Unsupported MAGIC table length')
    prepare = _dispatch(pe,14,64,0x434630,0x43460c,0x432a30)['skill_handlers']
    hold = tables['cast_label_selection']['skill_handlers']
    cast_rows, names = [], {}
    for index in range(84):
        mask=struct.unpack_from('<H',magic,index*64+52)[0]
        first,last=int(prepare[str(index)],16),int(hold[str(index)],16)
        if mask:
            for address,suffix in ((first,'a'),(last,'b')):
                names.setdefault((address,suffix),_phase_label(pe,address,suffix))
        cast_rows.append({'skill_id':index,'magic_plus34_raw':mask,'replace_caster_APD':bool(mask),
                          'prepare_label_unprefixed':names.get((first,'a')) if mask else None,
                          'hold_label_unprefixed':names.get((last,'b')) if mask else None,
                          'prepare_branch':hex(first),'hold_branch':hex(last),
                          'hold_animation_flags':'directionMirror|1' if index==78 else 'directionMirror|3',
                          'direction_mirror_override_definitions':[23,73]})
    write('data/port_ready/effects/spec/common_cast_lifecycle.json',{'per_skill_cast_labels':cast_rows})
    offsets = _missile_offsets(pe)
    write('data/port_ready/effects/spec/missile78_contract.json',{'offsets_by_direction':offsets})
    return {'contracts':6,'dispatch_tables':len(tables),'cast_rows':len(cast_rows),'town_rows':len(town),
            'music_labels':25,'missile_direction_tables':len(offsets),'legacy_cache_used':False,'source_modified':False}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();print(json.dumps(convert(args.source,args.output),ensure_ascii=False))
