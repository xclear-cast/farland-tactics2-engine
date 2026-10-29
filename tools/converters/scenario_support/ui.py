"""PE dialog/menu resource decoders; no PE package dependency."""
import struct
CLASS = {128: 'BUTTON', 129: 'EDIT', 130: 'STATIC', 131: 'LISTBOX', 132: 'SCROLLBAR', 133: 'COMBOBOX'}

class Reader:

    def __init__(self, data):
        self.data = data
        self.pos = 0

    def unpack(self, fmt):
        values = struct.unpack_from('<' + fmt, self.data, self.pos)
        self.pos += struct.calcsize('<' + fmt)
        return values

    def word(self):
        return self.unpack('H')[0]

    def align(self, n):
        self.pos = (self.pos + n - 1) // n * n

    def string(self):
        parts = []
        while (ch := self.word()) != 0:
            parts.append(ch)
        return struct.pack('<' + 'H' * len(parts), *parts).decode('utf-16le')

    def field(self):
        value = self.word()
        if value == 0:
            return {'kind': 'none'}
        if value == 65535:
            return {'kind': 'ordinal', 'value': self.word()}
        self.pos -= 2
        return {'kind': 'string', 'value': self.string()}

def dialog(data):
    r = Reader(data)
    extended = data[2:4] == b'\xff\xff'
    if extended:
        version, signature, help_id, exstyle, style, count, x, y, w, h = r.unpack('HHIIIHhhhh')
    else:
        style, exstyle, count, x, y, w, h = r.unpack('IIHhhhh')
        version = 0
        help_id = 0
    out = {'extended': extended, 'version': version, 'style': hex(style), 'exstyle': hex(exstyle), 'help_id': help_id, 'control_count': count, 'rect_dialog_units': [x, y, w, h], 'menu': r.field(), 'class': r.field(), 'title': r.field(), 'controls': []}
    if style & 64:
        point = r.word()
        weight, italic, charset = r.unpack('HBB') if extended else (None, None, None)
        out['font'] = {'point_size': point, 'weight': weight, 'italic': italic, 'charset': charset, 'typeface': r.string()}
    for _ in range(count):
        r.align(4)
        start = r.pos
        if extended:
            help_id, exstyle, style, x, y, w, h, identity = r.unpack('IIIhhhhI')
        else:
            style, exstyle, x, y, w, h, identity = r.unpack('IIhhhhH')
            help_id = 0
        cls = r.field()
        title = r.field()
        extra_count = r.word()
        extra = r.data[r.pos:r.pos + max(0, extra_count - 2)]
        r.pos += max(0, extra_count - 2)
        out['controls'].append({'id': identity, 'template_offset': start, 'rect_dialog_units': [x, y, w, h], 'class': cls, 'class_name': CLASS.get(cls.get('value')) if cls['kind'] == 'ordinal' else cls.get('value'), 'title': title, 'style': hex(style), 'exstyle': hex(exstyle), 'help_id': help_id, 'creation_count': extra_count, 'creation_hex': extra.hex()})
    out['bytes_consumed'] = r.pos
    out['tail_hex'] = data[r.pos:].hex()
    assert len(data) - r.pos <= 3 and (not any(data[r.pos:])), out
    return out

def menu(data):
    r = Reader(data)
    version, offset = r.unpack('HH')
    r.pos = 4 + offset
    if version != 0:
        raise ValueError(f'MENUEX version{version} unsupported, raw preserved')

    def items():
        rows = []
        while True:
            flags = r.word()
            identity = None if flags & 16 else r.word()
            text = r.string()
            rows.append({'flags': hex(flags), 'id': identity, 'text': text, 'children': items() if flags & 16 else []})
            if flags & 128:
                break
        return rows
    out = {'version': version, 'items': items(), 'bytes_consumed': r.pos, 'tail_hex': data[r.pos:].hex()}
    assert not any(data[r.pos:])
    return out

def accelerator(data):
    rows = []
    for off in range(0, len(data), 8):
        flags, key, cmd, pad = struct.unpack_from('<4H', data, off)
        rows.append({'flags': hex(flags), 'key': key, 'command_id': cmd, 'virtual_key': bool(flags & 1), 'shift': bool(flags & 4), 'ctrl': bool(flags & 8), 'alt': bool(flags & 16), 'end': bool(flags & 128), 'padding': pad})
    return rows
