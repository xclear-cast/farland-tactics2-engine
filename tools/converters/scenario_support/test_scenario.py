"""Synthetic file-format tests; no original game content is embedded."""
from pathlib import Path
import struct
import tempfile
import unittest

from ..scenario import normalize_event, pe_resources, case_path
from .bytecode import decode_command
from .core import read_number


class ScenarioTests(unittest.TestCase):
    def test_signed_small_integer(self):
        value,end=read_number(b'\xff',0)
        self.assertEqual((value['value'],end),(-1,1))

    def test_extended_integer(self):
        value,end=read_number(b'\x80'+struct.pack('<i',-500),0)
        self.assertEqual((value['value'],end),(-500,5))

    def test_dialogue_without_variant_operand(self):
        command,end=decode_command(b'\xff\x04\0',0)
        self.assertEqual(end,3)
        self.assertEqual(len(command['operands']),1)

    def test_event_roundtrip(self):
        raw=b'begin\0'+struct.pack('<I',10)+b'\xff\x06Synthetic text\0\xff\x24'
        with tempfile.TemporaryDirectory()as folder:
            path=Path(folder)/'EVENT00.DAT';path.write_bytes(raw)
            document=normalize_event(path,'DATA')
            self.assertEqual(document['status'],'complete_structural_parse')
            self.assertEqual(document['commands'][0]['operands'][0]['text'],'Synthetic text')
            self.assertEqual(b''.join(bytes.fromhex(row['raw_hex'])for row in document['commands']),raw[10:])

    def test_unsafe_source_path(self):
        with self.assertRaises(ValueError):case_path(Path.cwd(),'../outside')

    def test_case_independent_source_names(self):
        with tempfile.TemporaryDirectory()as folder:
            root=Path(folder);(root/'data').mkdir();(root/'data/item.dat').write_bytes(b'synthetic')
            self.assertEqual(case_path(root,'DATA/ITEM.DAT').read_bytes(),b'synthetic')

    def test_truncated_event_is_preserved_as_partial(self):
        raw=b'begin\0'+struct.pack('<I',10)+b'\xff\x06unterminated'
        with tempfile.TemporaryDirectory()as folder:
            path=Path(folder)/'EVENT00.DAT';path.write_bytes(raw)
            document=normalize_event(path,'DATA')
            self.assertEqual(document['status'],'partial_with_lossless_unresolved')
            self.assertEqual(bytes.fromhex(document['blocks'][0]['unresolved']['raw_hex']),raw[10:])

    def test_truncated_executable(self):
        with self.assertRaises(struct.error):list(pe_resources(b'MZ'))


if __name__=='__main__':unittest.main()
