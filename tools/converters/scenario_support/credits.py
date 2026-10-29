"""STAFF.LST directive parser; data are always read from the selected installation."""
import re,copy,collections
from .core import *
BASE_EXE_SHA="7437429a63fd5773e152550a59161a1eeefdd3fa3da66cad1d46e232d8097f4c"
def convert_credits(source, output):
    GAME = source
    OUT = output
    exe = case_path(GAME, 'FTO_O.EXE').read_bytes()
    assert digest(exe) == BASE_EXE_SHA
    names = [cstring(exe, va_offset(exe, 4502048 + 16 * i), 'ascii')[0]['text'] for i in range(27)]
    direct = [{'index': i, 'name': name, 'handler_va': hex(u32_va(exe, 4364432 + i * 4))} for i, name in enumerate(names)]
    operations = ['spacesize=value', 'auto_mode=0', 'auto_mode=1', 'emit single space andreturn immediately', 'emit single space andreturn immediately', 'posx=value', 'posy=value', 'center=1', 'center=0', 'fontcolor=value', 'decocolor=value', 'linespace=value', 'fontsize=value', 'fontsize=16', 'fontsize=24', 'fontsize=32', 'fontflags|=2', 'fontflags&=~2', 'fontflags|=8', 'fontflags&=~8', 'fontflags|=32', 'fontflags&=~32', 'fontflags|=4', 'fontflags&=~4', 'fontflags|=16', 'fontflags&=~16', 'commit current text group after this line']
    for d, op in zip(direct, operations):
        d['operation'] = op
    for variant in ('DATA', 'VDAT'):
        try:
            path = case_path(GAME, variant + '/STAFF.LST')
        except FileNotFoundError:
            if variant == 'DATA':
                raise
            continue
        raw = path.read_bytes()
        text = raw.decode('cp949')
        state = {'fontsize': 24, 'fontflags': 36, 'fontcolor': 255, 'decocolor': 0, 'auto_mode': 0, 'posx': 0, 'posy': 0, 'center': 0, 'linespace': 8, 'spacesize': 8}
        lines = []
        render = []
        unknown = []
        group = 0
        truncated = raw.split(b'\x00')[0].split(b'\x1a')[0]
        source_lines = truncated.split(b'\n')
        if source_lines and source_lines[-1] == b'':
            source_lines.pop()
        for li, linebytes in enumerate(source_lines, 1):
            if linebytes.endswith(b'\r'):
                linebytes = linebytes[:-1]
            line = linebytes.decode('cp949')
            p = 0
            tokens = []
            emit = None
            commit = False
            if line and (not line.startswith('//')):
                while p < len(line) and line[p] == '/':
                    end = line.find('/', p + 1)
                    if end < 0:
                        unknown.append({'line': li, 'reason': 'unclosed directive', 'raw': line[p:]})
                        p = len(line)
                        break
                    token = line[p + 1:end]
                    upper = token.upper()
                    name = next((n for n in names if upper.startswith(n)), None)
                    number = re.search(':([0-9]+)', token)
                    value = int(number[1]) if number else None
                    tokens.append({'raw': token, 'name': name, 'number': value})
                    if name is None:
                        unknown.append({'line': li, 'raw': token, 'native_behavior': 'unknownkeyword consumed to nextslash; no action'})
                    elif name in ('SPACE', '[SPACE]'):
                        emit = ' '
                        p = len(line)
                        break
                    elif name in ('SPACESIZE', 'POSX', 'POSY', 'FONTCOL', 'DECOCOL', 'LINESPACE', 'SIZE'):
                        if value is None:
                            unknown.append({'line': li, 'raw': token, 'native_behavior': 'missing numeric value returnsfalse forline'})
                            p = len(line)
                            break
                        key = {'SPACESIZE': 'spacesize', 'POSX': 'posx', 'POSY': 'posy', 'FONTCOL': 'fontcolor', 'DECOCOL': 'decocolor', 'LINESPACE': 'linespace', 'SIZE': 'fontsize'}[name]
                        state[key] = value
                    elif name in ('SMALL', 'NORMAL', 'BIG'):
                        state['fontsize'] = {'SMALL': 16, 'NORMAL': 24, 'BIG': 32}[name]
                    elif name in ('AUTO', 'MANUAL'):
                        state['auto_mode'] = int(name == 'MANUAL')
                    elif name in ('CENTER', 'NOCENTER'):
                        state['center'] = int(name == 'CENTER')
                    elif name == 'CTRL':
                        commit = True
                    elif name in ('GOTIC', 'MINCHO'):
                        state['fontflags'] = state['fontflags'] | 2 if name == 'GOTIC' else state['fontflags'] & ~2
                    else:
                        flag = {'ITALIC': 8, 'NOITALIC': 8, 'DECO': 32, 'NODECO': 32, 'BOLD': 4, 'NOBOLD': 4, 'PITCH': 16, 'NOPITCH': 16}[name]
                        state['fontflags'] = state['fontflags'] & ~flag if name.startswith('NO') else state['fontflags'] | flag
                    p = end + 1
                if emit is None and p < len(line):
                    emit = line[p:]
            row = {'line': li, 'raw': line, 'raw_hex': linebytes.hex(), 'directives': tokens, 'emits': emit is not None, 'text': emit, 'group': group, 'style_after': copy.deepcopy(state), 'group_commit': commit}
            lines.append(row)
            if emit is not None:
                b = emit.encode('cp949')
                clip = b[:80]
                render.append({'line': li, 'group': group, 'text': emit, 'render_bytes_hex': clip.hex(), 'render_text_cp949': clip.decode('cp949', errors='replace'), 'clipped_to80bytes': len(b) > 80, 'style': copy.deepcopy(state), 'height_rule': 'if storedtext exactly singleASCIIspace then spacesize else native glyph measuredheight428EA0; linespace added between entries; final extra linespace subtracted', 'center_rule': 'when center!=0 calls428B20(lineID,trunc0((fontsize+2)*lineID/2)); exactpositioncalleecontractpending'})
            if commit:
                group += 1
        write_json(OUT / 'credits' / variant / 'STAFF.json', {'source_path': str(path), 'sha256': digest(raw), 'source_bytes': len(raw), 'runtime_binding': '4260F8 ->resource12 STAFF.LST ->429B60(resourceID4,path,145000ms)', 'parser': '4293A0 loadsfile/setsdefaults;40B690 line splitter;429580 directive loop;429900 prefix lookup;429940/429980 onlyinitialdecimaldigitsaftercolon', 'directive_table': direct, 'lines': lines, 'render_entries': render, 'unresolved_or_unknown_directives': unknown, 'scroll_contract': {'setup': '429B60:height=429250(resource4);429A00(resource4,startY480,deltaY=-480-height,duration145000);enable429340(4,1);4292E0(4);4291F0(4,0). Second coordinate is DELTA, not destination.', 'storage': '429A00:recordWORD22=startY,WORD24=deltaY,DWORD28=starttime0,DWORD2C=duration; signed16 truncation ofcoordinates.429B00->429AA0 enablesflag8 andsetsstarttime=timeGetTime().', 'update_evidence': '42B4F0..42B5A4', 'formula': 'Beforecompletion y=int16(startY)+trunc0(((now_ms-start_ms)/duration_ms)*int16(deltaY)); x87 fraction and442FA0 trunc0 helper. At signed(start_ms+duration)<=signed(now_ms), y=startY+deltaY then starttime0/flag8off.429A60 stores y asWORD andcalls429070 onlyifchanged.', 'final_y': '480+(-480-height)=-height, assumingheightfits signedWORD. Do not confuse delta -480-height with finalY.', 'rounding_evidence': '442FA0 savesx87controlword, OR0C00 towardzero,FISTP QWORD,restorescontrolword.'}, 'original_unchanged': digest(path.read_bytes()) == digest(raw)})
