"""Pure binary primitives; no workspace lookup or import-time file access."""
from pathlib import Path
import hashlib,json,struct

def case_path(root, relative):
    """Resolve source names on case-sensitive hosts; reject traversal and links."""
    path = Path(root)
    for part in str(relative).replace('\\', '/').split('/'):
        if part in ('', '.', '..'):
            raise ValueError('Unsafe source path')
        matches = [child for child in path.iterdir() if child.name.casefold() == part.casefold()]
        if len(matches) != 1:
            raise FileNotFoundError(relative)
        path = matches[0]
        if path.is_symlink():
            raise ValueError('Source symlinks are unsupported')
    return path
def digest(b):
    return hashlib.sha256(b).hexdigest()

def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def pe_sections(b):
    pe = struct.unpack_from('<I', b, 60)[0]
    n = struct.unpack_from('<H', b, pe + 6)[0]
    size = struct.unpack_from('<H', b, pe + 20)[0]
    opt = pe + 24
    image = struct.unpack_from('<I', b, opt + 28)[0]
    rows = []
    for i in range(n):
        s = opt + size + 40 * i
        name = b[s:s + 8].rstrip(b'\x00').decode('ascii')
        virtual_size, rva, raw_size, raw_off = struct.unpack_from('<4I', b, s + 8)
        rows.append({'name': name, 'va': image + rva, 'virtual_size': virtual_size, 'raw_size': raw_size, 'raw_offset': raw_off})
    return (image, rows)

def va_offset(b, va):
    _, rows = pe_sections(b)
    for s in rows:
        if s['va'] <= va < s['va'] + max(s['virtual_size'], s['raw_size']):
            return s['raw_offset'] + va - s['va']
    raise ValueError(hex(va))

def u32_va(b, va):
    return struct.unpack_from('<I', b, va_offset(b, va))[0]

def cstring(b, p, encoding='cp949'):
    end = b.index(0, p)
    raw = b[p:end]
    try:
        text = raw.decode(encoding)
        valid = True
    except UnicodeDecodeError:
        text = raw.decode(encoding, errors='replace')
        valid = False
    return ({'text': text, 'raw_hex': raw.hex(), 'offset': p, 'bytes': len(raw) + 1, 'decoding_valid': valid}, end + 1)

def read_number(b, p):
    """0x43F170: marker80 + LE int32, otherwise sign-extended int8."""
    start = p
    if b[p] == 128:
        value = struct.unpack_from('<i', b, p + 1)[0]
        p += 5
        kind = 'extended_signed32'
    else:
        value = struct.unpack_from('<b', b, p)[0]
        p += 1
        kind = 'signed8'
    return ({'value': value, 'encoding': kind, 'offset': start, 'raw_hex': b[start:p].hex()}, p)

def label_table(b):
    p = 0
    labels = []
    while p < len(b) and b[p] != 255:
        label, end = cstring(b, p, 'ascii')
        target = struct.unpack_from('<I', b, end)[0]
        if not 0 <= target < len(b):
            raise ValueError('Label target out of file')
        labels.append({'name': label['text'], 'name_raw_hex': label['raw_hex'], 'entry_offset': p, 'target_file_offset': target, 'target_first_bytes_hex': b[target:target + 8].hex()})
        p = end + 4
    if p >= len(b):
        raise ValueError('No FF sentinel after label records')
    return {'table_bytes': p, 'sentinel_offset': p, 'sentinel_is_also_first_opcode_marker': min((x['target_file_offset'] for x in labels)) == p, 'labels': labels}
