"""Read-only FM2 parser; no runtime data or workspace dependencies."""
from pathlib import Path
import hashlib, struct
from .compression import szdd_decompress


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def world_coords(w: int, h: int):
    """Exact valid region and serialized index order of EXE4031A0."""
    side = w + h - 1
    for x in range(side):
        for y in range(side):
            if w - 1 <= x + y <= 2 * h + w - 3 and abs(x - y) <= w - 1:
                yield x, y

def original_ordinal(x: int, y: int, w: int, h: int) -> int:
    """Literal arithmetic/control flow of4031A0; returns1-based or0."""
    if x + y < w - 1 or x + y > 2 * h + w - 3 or abs(x - y) > w - 1:
        return 0
    value = 1
    for t in range(x):
        value += min(2 * min(t, w + h - 2 - t) + 1, 2 * min(w, h) - 1)
    return value + (x + y - w + 1 if x < w else w - x + y - 1)

def parse_map(path: Path) -> dict:
    packed = path.read_bytes()
    raw = szdd_decompress(packed)
    if raw[:4] != b"FM2\0":
        raise ValueError(f"FM2 signature missing: {path}")
    w, h, sheet_count = struct.unpack_from("<3I", raw, 4)
    pointer_base = 0x40 + 16 * sheet_count
    first_cell = struct.unpack_from("<I", raw, pointer_base)[0]
    if (first_cell - pointer_base) % 4:
        raise ValueError("Unaligned cell pointer table")
    count = (first_cell - pointer_base) // 4
    assert count == w * h + (w - 1) * (h - 1)
    offsets = list(struct.unpack_from(f"<{count}I", raw, pointer_base)) + [len(raw)]
    assert offsets == sorted(offsets) and len(set(offsets)) == len(offsets)
    sheets = [raw[0x40 + 16*i:0x50 + 16*i].split(b"\0", 1)[0].decode("ascii") for i in range(sheet_count)]
    background = raw[0x10:0x20].split(b"\0", 1)[0].decode("ascii")
    header_words = list(struct.unpack_from("<8i", raw, 0x20))
    left, top, right, bottom = header_words[4:]
    base_xy = [32 * (top - left), -16 * (top + left)]
    coords = list(world_coords(w, h))
    assert len(coords) == count
    side = w + h - 1
    lookup = [0] * (side * side)
    cells = []
    for index, (x, y) in enumerate(coords):
        ordinal = original_ordinal(x, y, w, h)
        assert ordinal == index + 1
        lookup[y * side + x] = ordinal
        off, end = offsets[index:index+2]
        height, flag2, flag3, terrain, parts = struct.unpack_from("<h4B", raw, off)
        assert end - off == 6 + parts * 14
        layers = []
        for part in range(parts):
            p = off + 6 + part*14
            atlas, pass_flag, x0, y0, x1, y1, dx, dy = struct.unpack_from("<BB6h", raw, p)
            assert atlas < len(sheets)
            assert x1 > x0 and y1 > y0
            key = f"{sheets[atlas].upper()}:{x0},{y0},{x1},{y1}"
            layers.append({"part": part, "source_byte_offset": p,
                "atlas_index": atlas, "atlas_name": sheets[atlas], "render_pass_flag": pass_flag,
                "source_rect_xyxy": [x0, y0, x1, y1], "offset_xy": [dx, dy],
                "draw_xy_before_camera": [32*(x-y)+base_xy[0]+dx, 16*(x+y)+base_xy[1]-8*height+dy],
                "tile_id": hashlib.sha256(key.encode()).hexdigest()[:20]})
        cells.append({"index": index, "lookup_ordinal": ordinal, "x": x, "y": y,
            "source_byte_offset": off, "source_length": end-off,
            "H": height, "flag2_raw": flag2, "flag3_raw": flag3, "L": terrain,
            "part_count": parts, "parts": layers, "raw_hex": raw[off:end].hex(),
            "mouse_pick_field_gate": flag2 == 0 and flag3 == 0})
    return {"schema_version": 1, "source_path": str(path), "source_sha256": digest(packed),
        "packed_size": len(packed), "decoded_sha256": digest(raw), "decoded_size": len(raw),
        "source_map_id": int(path.stem[5:]), "signature": "FM2", "width": w, "height": h,
        "world_lookup_side": side, "cell_count": count, "cell_pointer_table_offset": pointer_base,
        "background_bitmap_name": background, "atlas_names": sheets,
        "header_0x20_eight_signed_dwords": header_words,
        "header_map_bounds_ltrb": [left, top, right, bottom], "base_offset_xy": base_xy,
        "world_lookup_y_major_1based_zero_invalid": lookup, "cells": cells,
        "static_layer_draw_cell_indices": [c["index"] for c in sorted(cells, key=lambda c: (c["x"]+c["y"], c["x"]))],
        "field_semantics": {"H": "signed16 cell+0, verified MapInfo/physical/projection",
            "L": "u8 cell+4, verified MapInfo; terrain behavior still requires movement rules",
            "part_count": "u8 cell+5; exactly6+14*count bytes for every source cell",
            "flags2_3": "Raw bytes; both zero required by4035E0 mouse cell picker. Not sufficient as a universal walkability rule.",
            "Surface": "NOT a cell/tile ID. MapInfo reads active DirectDraw surface counter44A280 via418BF0."},
        "decoded_bytes": raw}
