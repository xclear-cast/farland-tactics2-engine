"""Synthetic format tests; no original game files required or embedded."""
from pathlib import Path
import hashlib
import io
import json
import struct
import sys
import tempfile
import unittest
import wave

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tables_audio import convert, finalize_save_bindings, _midi_payload, _convert_saves
from tables_audio_support.saves import decode_bytes,encode_bytes


class ConversionTests(unittest.TestCase):
    @staticmethod
    def _valid_save():
        raw=bytearray(6848)
        struct.pack_into('<I',raw,0,468)
        struct.pack_into('<I',raw,6668,180)
        return bytes(raw)

    @staticmethod
    def _source_hashes(source):
        return {p.relative_to(source).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                for p in source.rglob('*') if p.is_file()}

    def test_31_empty_slots_are_skipped_without_modifying_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            base=Path(temporary);source=base/'source';output=base/'cache'
            saves=source/'SAVE';saves.mkdir(parents=True)
            for slot in range(31):(saves/f'SAVE{slot:02d}.DAT').write_bytes(b'')
            before=self._source_hashes(source)
            report=_convert_saves(source,output)
            self.assertEqual(report['saves'],0)
            self.assertEqual(report['empty_saves_skipped'],31)
            self.assertEqual(set(report['empty_save_slots']),{f'SAVE{slot:02d}.DAT' for slot in range(31)})
            self.assertFalse(report['map_bindings_pending'])
            self.assertEqual(list((output/'data/port_ready/saves').glob('save[0-9]*.json')),[])
            bindings=finalize_save_bindings(output)
            self.assertEqual(bindings['save_bindings'],0)
            self.assertEqual(bindings['unresolved'],[])
            self.assertEqual(before,self._source_hashes(source))

    def test_native_empty_sentinels_and_mixed_save_indices(self):
        with tempfile.TemporaryDirectory() as temporary:
            base=Path(temporary);source=base/'source';output=base/'cache'
            saves=source/'sAvE';saves.mkdir(parents=True)
            # Match the native slot UI: fewer than four bytes, or first DWORD zero.
            empty=[b'',b'\x01',b'\x01\x02\x03',bytes(4),bytes(6848),bytes(4)+b'stale payload']
            for slot,raw in enumerate(empty):(saves/f'save{slot:02d}.dat').write_bytes(raw)
            for slot in (19,30):(saves/f'SAVE{slot:02d}.DAT').write_bytes(self._valid_save())
            (saves/'._SAVE19.DAT').write_bytes(b'Mac resource fork, not a save')
            (saves/'.DS_Store').write_bytes(b'Finder metadata')
            before=self._source_hashes(source)
            report=_convert_saves(source,output)
            self.assertEqual(report['saves'],2)
            self.assertEqual(report['empty_saves_skipped'],len(empty))
            destination=output/'data/port_ready/saves'
            self.assertEqual({p.name for p in destination.glob('save[0-9]*.json')},{'save19.json','save30.json'})
            for slot in (19,30):
                document=json.loads((destination/f'save{slot:02d}.json').read_text(encoding='utf-8'))
                self.assertEqual(encode_bytes(document),self._valid_save())
            scripts=output/'data/port_ready/scripts/normalized/DATA';scripts.mkdir(parents=True)
            (scripts/'EVENT00.json').write_text(json.dumps({'header':{'labels':[{'name':'Restart','target_file_offset':10}]},'commands':[{'offset':10,'opcode':10,'opcode_hex':'0A','name':'load_map','operands':[{'value':7}]}]}),encoding='utf-8')
            bindings=finalize_save_bindings(output)
            self.assertEqual(bindings['resolved_save_bindings'],2)
            self.assertEqual(bindings['unresolved'],[])
            index=json.loads((destination/'map_bindings.json').read_text(encoding='utf-8'))
            self.assertEqual({row['file'] for row in index['rows']},{'save19.dat','save30.dat'})
            self.assertEqual(before,self._source_hashes(source))

    def test_missing_save_directory_is_a_normal_new_installation(self):
        with tempfile.TemporaryDirectory() as temporary:
            base=Path(temporary);source=base/'source';source.mkdir();output=base/'cache'
            report=_convert_saves(source,output)
            self.assertEqual(report['saves'],0)
            self.assertEqual(report['empty_saves_skipped'],0)
            self.assertEqual(report['empty_save_slots'],[])
            self.assertFalse((source/'SAVE').exists())
            self.assertEqual(finalize_save_bindings(output)['unresolved'],[])

    def test_nonzero_header_truncation_is_not_misclassified_as_empty(self):
        for length in (4,467,6000,6847,6849):
            with self.subTest(length=length),tempfile.TemporaryDirectory() as temporary:
                base=Path(temporary);source=base/'source';output=base/'cache'
                saves=source/'SAVE';saves.mkdir(parents=True)
                raw=struct.pack('<I',468)+bytes(length-4)
                (saves/'SAVE12.DAT').write_bytes(raw)
                before=self._source_hashes(source)
                with self.assertRaisesRegex(ValueError,'Unsupported save length'):
                    _convert_saves(source,output)
                self.assertEqual(before,self._source_hashes(source))
        with tempfile.TemporaryDirectory() as temporary:
            base=Path(temporary);source=base/'source';output=base/'cache'
            saves=source/'SAVE';saves.mkdir(parents=True)
            raw=bytearray(self._valid_save());struct.pack_into('<I',raw,0,460)
            (saves/'SAVE12.DAT').write_bytes(raw)
            with self.assertRaisesRegex(ValueError,'Unsupported header size 460'):
                _convert_saves(source,output)

    def test_standalone_conversion_and_source_immutability(self):
        with tempfile.TemporaryDirectory() as temporary:
            base=Path(temporary);source=base/'source';output=base/'cache'
            for name in ('data','save','wave','midi'):(source/name).mkdir(parents=True,exist_ok=True)
            for name,stride in [('item',56),('magic',64),('race',86)]:
                raw=bytearray(stride*2);name_bytes='테스트'.encode('cp949');raw[stride:stride+len(name_bytes)]=name_bytes
                if name=='item':struct.pack_into('<h',raw,stride+20,30)
                if name=='magic':struct.pack_into('<h',raw,stride+22,6)
                (source/f'data/{name}.dat').write_bytes(raw)
            placement=bytearray(28);struct.pack_into('<hhhhii',placement,0,1,1,2,3,4,5)
            (source/'data/stage001.dat').write_bytes(placement)
            comments=bytearray(1024);struct.pack_into('<I',comments,4,1024);comments.extend('설명'.encode('cp949')+b'\0')
            (source/'data/itemcom.dat').write_bytes(comments)
            save=bytearray(6848);struct.pack_into('<I',save,0,468);struct.pack_into('<I',save,6668,180)
            (source/'save/save00.dat').write_bytes(save)
            pcm=io.BytesIO()
            with wave.open(pcm,'wb')as stream:stream.setnchannels(1);stream.setsampwidth(1);stream.setframerate(8000);stream.writeframes(bytes([128])*80)
            (source/'wave/sound.wav').write_bytes(pcm.getvalue())
            (source/'wave/._sound.wav').write_bytes(b'Mac resource fork, not WAV')
            (source/'wave/.DS_Store').write_bytes(b'Finder metadata')
            midi=b'MThd'+struct.pack('>IHHH',6,0,1,96)+b'MTrk'+struct.pack('>I',4)+b'\x00\xff\x2f\x00'
            (source/'midi/bgm00.mid').write_bytes(midi)
            (source/'midi/._bgm00.mid').write_bytes(b'Mac resource fork, not MIDI')
            before={p.relative_to(source).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()for p in source.rglob('*')if p.is_file()}
            report=convert(source,output)
            self.assertEqual(report['records'],{'item':2,'magic':2,'race':2})
            self.assertEqual((report['saves'],report['placements'],report['wav_files'],report['midi_directory_files']),(1,1,1,1))
            self.assertEqual(report['audio_errors'],[]);self.assertFalse(report['cdda_complete'])
            self.assertEqual((output/'fixtures/item.dat').read_bytes(),(source/'data/item.dat').read_bytes())
            codec=json.loads((output/'assets/cp949.json').read_text(encoding='utf-8'))
            self.assertEqual(codec['encode'][str(ord('테'))],list('테'.encode('cp949')))
            self.assertEqual(encode_bytes(decode_bytes(save)),save)
            scripts=output/'data/port_ready/scripts/normalized/DATA';scripts.mkdir(parents=True)
            (scripts/'EVENT00.json').write_text(json.dumps({'header':{'labels':[{'name':'Restart','target_file_offset':10}]},'commands':[{'offset':10,'opcode':10,'opcode_hex':'0A','name':'load_map','operands':[{'value':7}]}]}),encoding='utf-8')
            bindings=finalize_save_bindings(output)
            self.assertEqual(bindings['resolved_save_bindings'],1)
            document=json.loads((output/'data/port_ready/saves/map_bindings.json').read_text(encoding='utf-8'))
            self.assertEqual(document['rows'][0]['map_id'],7)
            after={p.relative_to(source).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()for p in source.rglob('*')if p.is_file()}
            self.assertEqual(before,after)

    def test_rejects_truncated_save_and_bad_midi(self):
        with self.assertRaises((ValueError,struct.error)):decode_bytes(b'\0'*20)
        with self.assertRaises(ValueError):_midi_payload(b'not MIDI')

    def test_riff_midi_payload(self):
        midi=b'MThd'+struct.pack('>IHHH',6,0,1,96)+b'MTrk'+struct.pack('>I',4)+b'\x00\xff\x2f\x00'
        body=b'RMIDdata'+struct.pack('<I',len(midi))+midi
        self.assertEqual(_midi_payload(b'RIFF'+struct.pack('<I',len(body))+body),midi)


if __name__=='__main__':unittest.main()
