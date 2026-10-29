"""Self-authored binary fixtures for the standalone graphics converter."""
from pathlib import Path
import json
import struct
import tempfile
import unittest

from .graphics import bitmap, convert
from .graphics_support.compression import szdd_decompress


def bmp_fixture():
    pixels = bytes((1,2,0,0))
    palette = b''.join(bytes((n,n,n,0)) for n in range(256))
    offset = 14+40+len(palette)
    file_header = b'BM'+struct.pack('<IHHI',offset+len(pixels),0,0,offset)
    info = struct.pack('<IiiHHIIiiII',40,2,1,1,8,0,len(pixels),0,0,256,0)
    return file_header+info+palette+pixels


def apd_fixture():
    header = b'3DPA'+bytes(4)+struct.pack('<4H',1,1,1,1)
    sheet = b'Sample.bmp'.ljust(256,b'\0')
    part = struct.pack('<BB4H2h',0,0,0,0,2,1,0,0)+bytes(6)
    frame = (struct.pack('<4H',0,0,0,1)+struct.pack('<H',0)).ljust(520,b'\0')
    script = b'S50 P0 N3 M0,0\0'
    label = b'idle'.ljust(32,b'\0')+struct.pack('<2H',0,len(script))
    return header+sheet+part+frame+label+script


def map_fixture():
    header = bytearray(64)
    header[:4] = b'FM2\0'
    struct.pack_into('<3I',header,4,1,1,0)
    struct.pack_into('<8i',header,32,0,0,0,0,0,0,1,1)
    return bytes(header)+struct.pack('<I',68)+struct.pack('<h4B',1,0,0,2,0)


class GraphicsTests(unittest.TestCase):
    def test_indexed_bitmap(self):
        width,height,pixels,palette=bitmap(bmp_fixture())
        self.assertEqual((width,height,pixels),(2,1,b'\x01\x02'))
        self.assertEqual(len(palette),768)
        self.assertEqual(palette[3:6],b'\x01\x01\x01')

    def test_szdd_literals(self):
        raw=b'hello'
        packed=b'SZDD\x88\xf0\x27\x33'+b'A\0'+struct.pack('<I',len(raw))+b'\x1f'+raw
        self.assertEqual(szdd_decompress(packed),raw)
        self.assertEqual(szdd_decompress(raw),raw)

    def test_invalid_bitmap(self):
        with self.assertRaises(ValueError):bitmap(b'BM')
        damaged=bytearray(bmp_fixture());struct.pack_into('<I',damaged,10,999999)
        with self.assertRaises(ValueError):bitmap(damaged)

    def test_end_to_end(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);source=root/'source';output=root/'output'
            for folder in ('BMP','MAP','SPRITE'):(source/folder).mkdir(parents=True)
            (source/'SPRITE/SAMPLE.BMP').write_bytes(bmp_fixture())
            (source/'SPRITE/SAMPLE.APD').write_bytes(apd_fixture())
            (source/'MAP/STAGE00.MAP').write_bytes(map_fixture())
            before={p.relative_to(source):p.read_bytes()for p in source.rglob('*')if p.is_file()}
            result=convert(source,output)
            self.assertEqual((result['images'],result['apds'],result['maps'],result['cells']),(1,1,1,1))
            self.assertFalse(result['legacy_cache_used'])
            self.assertEqual(result['original_missing_sheets'],[])
            manifest=json.loads((output/'assets/indexed/manifest.json').read_text())
            self.assertEqual(manifest['images']['sprite/sample.bmp']['width'],2)
            apd=json.loads((output/'assets/indexed/apd/SAMPLE.json').read_text())
            self.assertEqual(len(apd['animations']['idle']['groups'][0]['steps']),3)
            self.assertEqual(apd['animations']['idle']['duration'],150)
            map_data=json.loads((output/'assets/indexed/maps/STAGE00.json').read_text())
            self.assertEqual(map_data['cells'][0][:6],[0,0,1,0,0,2])
            self.assertEqual(len((output/'assets/indexed/maps/STAGE00.idx').read_bytes()),640*480)
            self.assertEqual(before,{p.relative_to(source):p.read_bytes()for p in source.rglob('*')if p.is_file()})

    def test_output_cannot_modify_installation(self):
        with tempfile.TemporaryDirectory() as temporary:
            source=Path(temporary)
            with self.assertRaises(ValueError):convert(source,source/'cache')


if __name__=='__main__':unittest.main()
