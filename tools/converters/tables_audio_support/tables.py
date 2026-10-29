"""Fixed-stride table parsers; no source paths or import-time I/O."""
from pathlib import Path
import struct

def i16(b: bytes, off: int) -> int:
    return struct.unpack_from('<h', b, off)[0]

def cstr(b: bytes, off: int, size: int, enc: str) -> str:
    return b[off:off + size].split(b'\x00')[0].decode(enc, 'replace').strip()

def decode_magic(path: str | Path, stride: int=64, include_placeholders: bool=False) -> list[dict]:
    b = Path(path).read_bytes()
    out = []
    for i in range(len(b) // stride):
        r = i * stride
        name = cstr(b, r + 0, 20, 'cp949')
        if (not name or name == '결번') and (not include_placeholders):
            continue
        out.append({'id': i, 'index': i, 'legacy_id': i + 1, 'name': name, 'apd_stem': cstr(b, r + 34, 12, 'ascii'), 'effect_name': cstr(b, r + 54, 10, 'cp949'), 'req_level': i16(b, r + 20), 'mp': i16(b, r + 22), 'power': i16(b, r + 24), 'power_channels_signed': [i16(b, r + off) for off in (24, 26, 28)], 'power_channel_offsets': ['0x18', '0x1A', '0x1C'], 'v1': i16(b, r + 26), 'v2': i16(b, r + 30), 'flag': i16(b, r + 32), 'target_mode_raw': i16(b, r + 48), 'ai_dispatch_type_raw': i16(b, r + 50), 'learn_kind_mask': struct.unpack_from('<H', b, r + 52)[0], 'tail_0x2e_raw': i16(b, r + 46), 'sfx_index': i16(b, r + 46), 'raw_record_hex': b[r:r + stride].hex()})
    return out

STRIDE = 56

STAT_KEYS = ('atk', 'def', 'int', 'mdef', 'agi')

STAT_OFFSETS = (26, 28, 30, 32, 34)

def decode_items(path: Path, include_empty: bool=False) -> dict[int, dict]:
    b = path.read_bytes()
    out = {}
    for i in range(len(b) // STRIDE):
        r = i * STRIDE
        name = b[r:r + 20].split(b'\x00')[0].decode('cp949', 'replace').strip()
        if (not name or name == '없음') and (not include_empty):
            continue
        rec = {'id': i, 'name': name, 'price': i16(b, r + 20), 'effect1': i16(b, r + 22), 'effect2': i16(b, r + 24), 'element': i16(b, r + 36), 'extra': i16(b, r + 40), 'attribute_channels_signed': [i16(b, r + off) for off in (36, 38, 40)], 'attribute_channel_offsets': ['0x24', '0x26', '0x28'], 'category': i16(b, r + 46), 'icon': i16(b, r + 48), 'effect_id': i16(b, r + 50), 'name_raw_hex': b[r:r + 20].hex(), 'raw_record_hex': b[r:r + STRIDE].hex(), 'action_visual_selector_raw': i16(b, r + 48), 'target_shape_raw': i16(b, r + 50), 'state_code': i16(b, r + 52), 'tail_0x36_raw': i16(b, r + 54), 'equip_kind_mask': struct.unpack_from('<H', b, r + 54)[0], 'target_distance_min_raw': i16(b, r + 42), 'target_distance_max_raw': i16(b, r + 44)}
        for key, off in zip(STAT_KEYS, STAT_OFFSETS):
            rec[key] = i16(b, r + off)
        out[i] = rec
    return out

RACE_STRIDE = 86

STAT_NAMES = ('hp', 'mp', 'atk', 'def', 'int', 'mdef', 'agi')

def decode_race(path: Path) -> list[dict]:
    b = path.read_bytes()
    out = []
    for i in range(len(b) // RACE_STRIDE):
        r = i * RACE_STRIDE
        name = b[r:r + 20].split(b'\x00')[0].decode('cp949', 'replace').strip()
        pairs = {}
        vals = struct.unpack_from('<' + 'h' * ((RACE_STRIDE - 24) // 2), b, r + 24)
        for k, stat in enumerate(STAT_NAMES):
            initial, increment = struct.unpack_from('<2h', b, r + 22 + 4 * k)
            pairs[stat] = {'initial': initial, 'increment_per_level': increment, 'base': initial, 'growth': increment, 'parameter_pair_raw': [initial, increment], 'initial_offset': hex(22 + 4 * k), 'increment_offset': hex(24 + 4 * k)}
        out.append({'id': i, 'name': name or None, 'stats': pairs, 'class_header_word_0x14_raw': struct.unpack_from('<h', b, r + 20)[0], 'experience_value': struct.unpack_from('<h', b, r + 20)[0], 'experience_value_provenance': '41456C:damage*RACE+14/targetMaxHP, KO additional base, kind and level scaling in414548..624', 'stat_layout_provenance': 'C init41A8C8..909 and growth41A4D0..71E;7pairs at+16(initial),+18(increment). Older+18 pair decode shifted2bytes.', 'attribute_channels_signed': list(vals[13:16]), 'attribute_channel_offsets': ['0x32', '0x34', '0x36'], 'tail_from_0x38_raw': list(vals[16:]), 'terrain_costs_signed': list(struct.unpack_from('<8h', b, r + 62)), 'shadow_size_selector': struct.unpack_from('<H', b, r + 56)[0], 'max_up_height': struct.unpack_from('<H', b, r + 58)[0], 'max_down_height': struct.unpack_from('<H', b, r + 60)[0], 'default_skill_slots4': list(struct.unpack_from('<4h', b, r + 78)), 'raw_record_hex': b[r:r + RACE_STRIDE].hex(), 'last_four_words_skill_candidates': list(vals[-4:]), 'tail': list(vals[14:])})
    return out

def decode_stage(path: Path) -> list[dict]:
    b = path.read_bytes()
    rows = []
    for k in range(len(b) // 28):
        v = struct.unpack_from('<14h', b, k * 28)
        rows.append({'id': v[0], 'kind_word': v[0], 'race': v[1], 'definition_id': v[1], 'level': v[2], 'flag': v[3], 'direction_word': v[3], 'x': struct.unpack_from('<i', b, k * 28 + 8)[0], 'y': struct.unpack_from('<i', b, k * 28 + 12)[0], 'p12': v[12], 'p13': v[13], 'state': v[8], 'control': v[9], 'weapon': v[10], 'armor': v[11], 'drop_item': v[12], 'drop_money': v[13], 'loader_mapping_provenance': '41AACD..41AAE2 copies raw+18DWORD to unit+1CDWORD, clears unit+18DWORD; no STAGE accessory slots.', 'raw_record_hex': b[k * 28:(k + 1) * 28].hex(), 'raw': list(v)})
    return rows
