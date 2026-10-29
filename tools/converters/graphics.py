"""Convert user-owned FT2 graphics directly from the installed source files.

No legacy cache or generated workspace data is read. Pixel indices, palettes,
APD group compilation, FM2 cells and baked map surfaces retain their source
representation. Pillow is used only for indexed map compositing.
"""
from __future__ import annotations

from collections import Counter
from pathlib import Path
import argparse
import hashlib
import json
import struct

from PIL import Image

from .graphics_support.apd import ExactApd, compile_source, resolve_references
from .graphics_support.compression import szdd_decompress
from .graphics_support.maps import parse_map


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def dump(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')


def directory(source: Path, name: str) -> Path:
    matches = [p for p in source.iterdir() if p.is_dir() and p.name.casefold() == name.casefold()]
    if len(matches) != 1:
        raise ValueError(f'Missing or ambiguous source directory: {name}')
    if matches[0].is_symlink():
        raise ValueError(f'Source directory links are unsupported: {name}')
    return matches[0]


def bitmap(raw: bytes) -> tuple[int, int, bytes, bytes]:
    """Return top-down 8-bit indices and exactly 256 RGB palette entries."""
    data = szdd_decompress(raw)
    if len(data) < 54 or data[:2] != b'BM':
        raise ValueError('Missing BMP signature/header')
    offset = struct.unpack_from('<I', data, 10)[0]
    hs, width, height, planes, bpp, compression = struct.unpack_from('<IiiHHI', data, 14)
    if hs < 40 or planes != 1 or bpp != 8 or compression != 0 or width <= 0 or height == 0:
        raise ValueError(f'Unsupported indexed BMP format: {(hs,width,height,planes,bpp,compression)}')
    if width * abs(height) > 128 * 1024 * 1024:
        raise ValueError('Unreasonable bitmap dimensions')
    entries = struct.unpack_from('<I', data, 46)[0] or 256
    if entries > 256 or 14 + hs + 4 * entries > len(data):
        raise ValueError('Invalid palette bounds')
    palette = bytearray(256 * 3)
    for index in range(entries):
        blue, green, red, _ = struct.unpack_from('<4B', data, 14 + hs + 4 * index)
        palette[index * 3:index * 3 + 3] = bytes((red, green, blue))
    stride = (width + 3) & ~3
    if offset < 14 + hs + 4 * entries or offset + stride * abs(height) > len(data):
        raise ValueError('Invalid bitmap pixel bounds')
    rows = range(height - 1, -1, -1) if height > 0 else range(abs(height))
    pixels = b''.join(data[offset + y * stride:offset + y * stride + width] for y in rows)
    return width, abs(height), pixels, bytes(palette)


def _apd_document(path: Path, sheet_files: dict[str, Path], image_rows: dict) -> dict:
    apd = ExactApd(path)
    sheets = []
    for name in apd.sheet_names:
        lookup = name.strip().rstrip('.').casefold()
        source = sheet_files.get(lookup)
        row = image_rows.get('sprite/' + lookup)
        sheets.append({'declared_name':source.name if source is not None else name,
                       'source_declared_name':name, 'resolved':source is not None and row is not None,
                       'size':[row['width'],row['height']] if row else [],
                       'source_sha256':row['source_sha256'] if row else None})
    parts = []
    for index, original in enumerate(apd.parts):
        valid = original['sheet'] < len(sheets) and sheets[original['sheet']]['resolved']
        if valid:
            width, height = sheets[original['sheet']]['size']
            valid = (0 <= original['x'] < original['x'] + original['w'] <= width and
                     0 <= original['y'] < original['y'] + original['h'] <= height)
        parts.append({**original, 'index':index, 'sheet_resolved_and_rect_valid':bool(valid),
                      'godot_unflipped_draw_offset_xy':[original['ox'], original['oy']],
                      'anchor_mirror_H_draw_offset_xy':[-original['ox'] - original['w'], original['oy']],
                      'anchor_mirror_V_draw_offset_xy':[original['ox'], -original['oy'] - original['h']]})
    frames = []
    for frame in apd.composites:
        used = [parts[i] for i in frame['part_indices_in_draw_order']]
        bounds = [min((p['ox'] for p in used), default=0), min((p['oy'] for p in used), default=0),
                  max((p['ox']+p['w'] for p in used), default=0), max((p['oy']+p['h'] for p in used), default=0)]
        frames.append({**frame, 'bounds_relative_anchor_xyxy':bounds,
                       'complete_source_pixels':all(p['sheet_resolved_and_rect_valid'] for p in used)})
    animations = {}
    for label in apd.labels:
        entry = compile_source(label['script'])
        entry.update(label_source_offset=label['offset'], label_source_length=label['length'],
                     label_name_area_raw_hex=label['name_area_hex'], aliases=label['aliases'])
        animations[label['name']] = entry
    resolve_references(animations)
    invalid = [{'label':label, 'ordinal':step['ordinal'], 'frame':step['image_frame']}
               for label, entry in animations.items() for group in entry['compiled_groups']
               for step in group['steps'] if not 0 <= step['image_frame'] < apd.n_frames]
    unhandled = [{'label':label, 'tokens':entry['unhandled_tokens']}
                 for label, entry in animations.items() if entry['unhandled_tokens']]
    return {'schema_version':1, 'source':str(path), 'source_sha256':sha(apd.raw),
            'source_layout':apd.layout, 'sheets':sheets, 'part_crops':parts, 'frames':frames,
            'animations':animations, 'invalid_step_frames':invalid, 'unhandled_script_tokens':unhandled,
            'complete_sheet_pixels':all(sheet['resolved'] for sheet in sheets)}


def _compact_apd(document: dict, stem: str) -> dict:
    animations = {}
    for label, entry in document['animations'].items():
        groups = []
        for group in entry['compiled_groups']:
            groups.append({'move':group.get('move_total_xy',[0,0]),
                           'velocity':group.get('compiled_sequence_velocity_per_ms',[0,0]),
                           'duration':group.get('duration_ms',0),
                           'steps':[[step['image_frame'], step['duration_ms'], step.get('draw_flags',0),
                                     step.get('sound_event_id',-1), step.get('sound_event_indirect',0),
                                     step.get('action_marker',0)] for step in group['steps']]})
        animations[label] = {'groups':groups, 'duration':entry['compiled_schedule_ms']}
    return {'name':stem, 'source_sha256':document['source_sha256'],
            'sheets':[('sprite/'+sheet['declared_name']).lower() for sheet in document['sheets']],
            'parts':[[part['sheet'],part['x'],part['y'],part['w'],part['h'],part['ox'],part['oy'],part['transparent_palette_index']]
                     for part in document['part_crops']],
            'frames':[{'parts':frame['part_indices_in_draw_order'], 'pivot':frame['header_words_raw'][2],
                       'bounds':frame['bounds_relative_anchor_xyxy']} for frame in document['frames']],
            'animations':animations}


def _compact_map(document: dict) -> dict:
    return {'id':document['source_map_id'], 'width':document['width'], 'height':document['height'],
            'side':document['world_lookup_side'], 'base':document['base_offset_xy'],
            'bounds':document['header_map_bounds_ltrb'], 'header':document['header_0x20_eight_signed_dwords'],
            'background':('map/'+document['background_bitmap_name']).lower(),
            'atlases':[('map/'+name).lower() for name in document['atlas_names']],
            'static_order':document['static_layer_draw_cell_indices'],
            'cells':[[cell['x'],cell['y'],cell['H'],cell['flag2_raw'],cell['flag3_raw'],cell['L'],
                      [[part['atlas_index'],part['render_pass_flag'],*part['source_rect_xyxy'],*part['offset_xy']]
                       for part in cell['parts']]] for cell in document['cells']]}


def _bake(compact: dict, image_rows: dict, indexed: Path, memo: dict) -> bytes:
    left, top, right, bottom = compact['bounds']
    width = max(640, (right-bottom-left+top)*32)
    height = max(480, (bottom-top-left+right)*16)
    if width * height > 128 * 1024 * 1024:
        raise ValueError('Unreasonable map surface dimensions')
    canvas = Image.new('L',(width,height),0)
    for ordinal in compact['static_order']:
        cell = compact['cells'][ordinal]
        x,y,h = cell[:3]
        anchor = ((x-y)*32+compact['base'][0], (x+y)*16+compact['base'][1]-h*8)
        for part in cell[6]:
            key = compact['atlases'][part[0]]
            if key not in image_rows:
                raise ValueError(f'Missing map atlas: {key}')
            if key not in memo:
                row = image_rows[key]
                data = (indexed/'images'/Path(row['indices']).name).read_bytes()
                remap = list(range(256))
                for number in range(10,122): remap[number] = number+22
                image = Image.frombytes('L',(row['width'],row['height']),data).point(remap)
                first = image.getpixel((0,0))
                memo[key] = (image,249 if 10 <= first < 246 else first)
            image, transparent = memo[key]
            tile = image.crop(tuple(part[2:6]))
            mask = tile.point([0 if value == transparent else 255 for value in range(256)])
            canvas.paste(tile,(anchor[0]+part[6],anchor[1]+part[7]),mask)
    compact['baked'] = {'width':width,'height':height,'indices':'','transparent':0}
    return canvas.tobytes()


def convert(source: Path, output: Path) -> dict:
    source, output = Path(source).resolve(), Path(output).resolve()
    if output == source or output.is_relative_to(source):
        raise ValueError('Conversion output must be outside the installation')
    indexed = output/'assets/indexed'
    images, apds, maps, unsupported, missing_sheets = {}, {}, {}, [], []
    bitmaps = []
    folders = {name:directory(source,name) for name in ('BMP','MAP','SPRITE')}
    for folder, path in folders.items():
        for original in sorted(path.iterdir()):
            if not original.is_file() or original.suffix.casefold() != '.bmp': continue
            if original.is_symlink(): raise ValueError(f'Unsupported source link: {original}')
            raw = original.read_bytes()
            key = (folder+'/'+original.name).lower()
            try: width,height,pixels,palette = bitmap(raw)
            except (ValueError,struct.error,IndexError) as error:
                unsupported.append({'source':key,'error':str(error)}); continue
            name = key.replace('/','__')
            pixel_file, palette_file = indexed/'images'/(name+'.idx'), indexed/'images'/(name+'.pal')
            pixel_file.parent.mkdir(parents=True,exist_ok=True)
            pixel_file.write_bytes(pixels);palette_file.write_bytes(palette)
            images[key] = {'width':width,'height':height,'indices':'res://assets/indexed/images/'+pixel_file.name,
                           'palette':'res://assets/indexed/images/'+palette_file.name,'source_sha256':sha(raw),
                           'indices_sha256':sha(pixels),'palette_sha256':sha(palette)}
            if folder == 'BMP':
                bitmaps.append({'source':folder+'/'+original.name,'source_sha256':sha(raw),
                                'decoded_bitmap_sha256':sha(szdd_decompress(raw)), 'size':[width,height],
                                'mode':'P','indexed_indices':images[key]['indices'],'indexed_palette':images[key]['palette']})
    sheet_files = {p.name.casefold():p for p in folders['SPRITE'].iterdir() if p.is_file()}
    for path in sorted(folders['SPRITE'].iterdir()):
        if path.suffix.casefold() != '.apd' or not path.is_file(): continue
        if path.is_symlink(): raise ValueError(f'Unsupported source link: {path}')
        document = _apd_document(path,sheet_files,images)
        for sheet in document['sheets']:
            if not sheet['resolved']:missing_sheets.append({'apd':path.name,'declared_sheet':sheet['declared_name']})
        stem = path.stem.upper()
        dump(output/'data/port_ready/assets/apd/animations'/(stem+'.json'),document)
        compact = _compact_apd(document,stem)
        dump(indexed/'apd'/(stem+'.json'),compact)
        apds[stem] = 'res://assets/indexed/apd/'+stem+'.json'
    map_rows, tile_memo = [], {}
    for path in sorted(folders['MAP'].iterdir()):
        if path.suffix.casefold() != '.map' or not path.stem.upper().startswith('STAGE'): continue
        if path.is_symlink(): raise ValueError(f'Unsupported source link: {path}')
        document = parse_map(path)
        document.pop('decoded_bytes')
        stem = f"STAGE{document['source_map_id']:02d}"
        relative = 'data/port_ready/maps/maps/'+stem+'.json'
        dump(output/relative,document)
        compact = _compact_map(document)
        pixels = _bake(compact,images,indexed,tile_memo)
        cache = indexed/'maps'/(stem+'.idx');cache.parent.mkdir(parents=True,exist_ok=True);cache.write_bytes(pixels)
        compact['baked'].update(indices='res://assets/indexed/maps/'+cache.name,sha256=sha(pixels))
        dump(indexed/'maps'/(stem+'.json'),compact)
        maps[str(document['source_map_id'])] = 'res://assets/indexed/maps/'+stem+'.json'
        map_rows.append({'map_id':document['source_map_id'],'file':relative,'source_sha256':document['source_sha256'],
                         'width':document['width'],'height':document['height'],'world_side':document['world_lookup_side'],
                         'cells':document['cell_count'],'visual_parts':sum(c['part_count'] for c in document['cells']),
                         'H_histogram':dict(Counter(c['H'] for c in document['cells'])),
                         'L_histogram':dict(Counter(c['L'] for c in document['cells']))})
    dump(indexed/'manifest.json',{'schema':1,'source':'User-provided original indexed BMP/APD/FM2 files',
                                  'images':images,'apds':apds,'maps':maps,
                                  'fonts':'res://assets/indexed/fonts.json' if (indexed/'fonts.json').is_file() else '',
                                  'unsupported':unsupported,'source_unchanged':True})
    dump(output/'data/port_ready/assets/bitmaps/index.json',{'schema_version':1,'count':len(bitmaps),'files':bitmaps})
    dump(output/'data/port_ready/maps/index.json',{'schema_version':1,'source_root':str(source),'maps':map_rows,
                                                'summary':{'map_count':len(map_rows),'cell_count':sum(row['cells']for row in map_rows)}})
    report = {'images':len(images),'apds':len(apds),'maps':len(maps),'cells':sum(row['cells']for row in map_rows),
              'unsupported':unsupported,'original_missing_sheets':missing_sheets,'legacy_cache_used':False,'source_modified':False}
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    options = parser.parse_args()
    print(json.dumps(convert(options.source,options.output),ensure_ascii=False))
