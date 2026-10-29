"""Lossless 50-unit SAVE codec; no source paths or import-time I/O."""
import struct,hashlib

HEADER_SIZE = 468

UNIT_SIZE = 124

CAPACITY = 50

U16_FIELDS = {0: 'kind', 2: 'definition_id', 4: 'level', 6: 'direction', 16: 'state', 18: 'control', 20: 'weapon', 22: 'armor', 24: 'accessory1', 26: 'accessory2', 28: 'drop_item', 30: 'drop_money', 32: 'unknown20_raw', 34: 'unknown22_raw'}

S16_FIELDS = {36: 'hp_max', 38: 'hp', 40: 'mp_max', 42: 'mp', 44: 'experience', 46: 'atk', 48: 'def', 50: 'int', 52: 'mdef', 54: 'agi', **{56 + 2 * k: f'skill{k}' for k in range(10)}, **{76 + 2 * k: f'temp_{s}' for k, s in enumerate(['atk', 'def', 'int', 'mdef', 'agi'])}, **{86 + 2 * k: f'attribute{k}' for k in range(3)}}

S32_FIELDS = {8: 'x', 12: 'y', 92: 'move_marker', 96: 'action_marker', 100: 'prepared_mode', 104: 'status_counter'}

U32_FIELDS = {108: 'apd_resource_handle_raw', 112: 'visual_handle70_raw', 116: 'visual_handle74_raw', 120: 'visual_handle78_raw'}

FIELDS = [(off, fmt, name) for fmt, fields in [('H', U16_FIELDS), ('h', S16_FIELDS), ('i', S32_FIELDS), ('I', U32_FIELDS)] for off, name in fields.items()]

def decode_bytes(data):
    header_size = struct.unpack_from('<I', data, 0)[0]
    if header_size != HEADER_SIZE:
        raise ValueError(f'Unsupported header size {header_size}; preserve file without reinterpreting.')
    tail_start = header_size + CAPACITY * UNIT_SIZE
    if len(data) < tail_start + 4:
        raise ValueError('Truncated unit/tail chunks')
    header = data[:header_size]
    units = []
    for slot in range(CAPACITY):
        raw = data[header_size + slot * UNIT_SIZE:header_size + (slot + 1) * UNIT_SIZE]
        unit = {name: struct.unpack_from('<' + fmt, raw, off)[0] for off, fmt, name in FIELDS}
        unit['slot'] = slot
        units.append(unit)
        unit['context_alias_views'] = {'carried_equipment4': [unit['drop_item'], unit['drop_money'], unit['unknown20_raw'], unit['unknown22_raw']], 'provenance': '4199D0 grants category0/1/2 equipment to Unit+1C..22. Enemy KO4140E9 interprets first2as item/money drops. This is a read-only alias view; encoder writes each WORD once.'}
    return {'schema_version': 1, 'source_sha256': hashlib.sha256(data).hexdigest(), 'header_raw_hex': header.hex(), 'header': {'size': header_size, 'stage': struct.unpack_from('<H', header, 4)[0], 'title_cp949_raw_hex': header[6:38].hex(), 'round_index': struct.unpack_from('<h', header, 38)[0], 'turn_unsigned_alias_view': struct.unpack_from('<H', header, 38)[0], 'restart_policy': 'round_index<0 selects EVENT00 Restart (town); otherwise stage is the EVENT/chapter ID, not the map ID.', 'event_variables_independent': list(struct.unpack_from('<25h', header, 40)), 'system_time_words': list(struct.unpack_from('<8H', header, 90)), 'bgm': struct.unpack_from('<H', header, 106)[0], 'money': struct.unpack_from('<i', header, 108)[0], 'inventory': [{'id': struct.unpack_from('<h', header, 112 + k * 4)[0], 'quantity': struct.unpack_from('<h', header, 114 + k * 4)[0]} for k in range(80)], 'inventory_following_dword_raw': struct.unpack_from('<I', header, 432)[0], 'battle_objective_cp949_raw_hex': header[436:468].hex()}, 'header_variable100_alias_view': list(struct.unpack_from('<100h', header, 40)), 'units': units, 'tail_raw_hex': data[tail_start:].hex(), 'tail_size_field': struct.unpack_from('<I', data, tail_start)[0], 'runtime_handle_policy': 'Preserve bytes for archival roundtrip. Recreate visual actors/handles from native loader contract; raw Windows addresses are not Godot resources.'}

def encode_bytes(doc):
    header = bytearray.fromhex(doc['header_raw_hex'])
    h = doc['header']
    struct.pack_into('<IH', header, 0, h['size'], h['stage'])
    header[6:38] = bytes.fromhex(h['title_cp949_raw_hex'])
    if 'round_index' in h:
        struct.pack_into('<h', header, 38, h['round_index'])
    else:
        struct.pack_into('<H', header, 38, h['turn'])
    struct.pack_into('<25h', header, 40, *h['event_variables_independent'])
    struct.pack_into('<8H', header, 90, *h['system_time_words'])
    struct.pack_into('<Hi', header, 106, h['bgm'], h['money'])
    for k, row in enumerate(h['inventory']):
        struct.pack_into('<2h', header, 112 + k * 4, row['id'], row['quantity'])
    struct.pack_into('<I', header, 432, h['inventory_following_dword_raw'])
    header[436:468] = bytes.fromhex(h['battle_objective_cp949_raw_hex'])
    units = bytearray(CAPACITY * UNIT_SIZE)
    if len(doc['units']) != CAPACITY or len(h['inventory']) != 80:
        raise ValueError('Fixed capacity mismatch')
    for slot, unit in enumerate(doc['units']):
        if unit['slot'] != slot:
            raise ValueError('Slot sequence mismatch')
        for off, fmt, name in FIELDS:
            struct.pack_into('<' + fmt, units, slot * UNIT_SIZE + off, unit[name])
    return bytes(header) + bytes(units) + bytes.fromhex(doc['tail_raw_hex'])
