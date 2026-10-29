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
from tables_audio import convert, finalize_save_bindings, _midi_payload
from tables_audio_support.saves import decode_bytes,encode_bytes


class ConversionTests(unittest.TestCase):
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
            midi=b'MThd'+struct.pack('>IHHH',6,0,1,96)+b'MTrk'+struct.pack('>I',4)+b'\x00\xff\x2f\x00'
            (source/'midi/bgm00.mid').write_bytes(midi)
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
