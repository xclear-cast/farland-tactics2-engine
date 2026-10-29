"""RIFF, MIDI and SZDD readers; no source paths or import-time I/O."""
import struct

SZDD_SIG = b"SZDD\x88\xf0'3"

def szdd_decompress(data: bytes) -> bytes:
    if not data.startswith(SZDD_SIG):
        return data
    out_len = struct.unpack_from('<I', data, 10)[0]
    src = memoryview(data)[14:]
    window = bytearray([32] * 4096)
    pos = 4096 - 16
    out = bytearray()
    i = 0
    while i < len(src):
        control = src[i]
        i += 1
        bit = 1
        while bit & 255:
            if control & bit:
                if i >= len(src):
                    break
                b = src[i]
                i += 1
                window[pos] = b
                pos = pos + 1 & 4095
                out.append(b)
            else:
                if i + 1 >= len(src):
                    break
                matchpos = src[i]
                matchlen = src[i + 1]
                i += 2
                matchpos |= (matchlen & 240) << 4
                matchlen = (matchlen & 15) + 3
                for _ in range(matchlen):
                    b = window[matchpos]
                    window[pos] = b
                    pos = pos + 1 & 4095
                    matchpos = matchpos + 1 & 4095
                    out.append(b)
            bit <<= 1
            if len(out) >= out_len:
                return bytes(out[:out_len])
    return bytes(out[:out_len])

def wav_info(data):
    assert data[:4] == b'RIFF' and data[8:12] == b'WAVE'
    chunks = []
    pos = 12
    fmt = None
    audio_bytes = 0
    while pos + 8 <= len(data):
        kind = data[pos:pos + 4].decode('latin1')
        size = struct.unpack_from('<I', data, pos + 4)[0]
        start = pos + 8
        assert start + size <= len(data), (kind, size, len(data))
        chunks.append({'id': kind, 'offset': start, 'bytes': size})
        if kind == 'fmt ':
            fmt = struct.unpack_from('<HHIIHH', data, start)
        if kind == 'data':
            audio_bytes += size
        pos = start + size + (size & 1)
    assert fmt
    tag, ch, rate, byte_rate, align, bits = fmt
    return {'format_tag': tag, 'channels': ch, 'sample_rate': rate, 'byte_rate': byte_rate, 'block_align': align, 'bits_per_sample': bits, 'audio_data_bytes': audio_bytes, 'pcm_frame_count': audio_bytes // align if tag == 1 else None, 'duration_s_from_byte_rate': audio_bytes / byte_rate if byte_rate else None, 'chunks': chunks, 'godot_native_pcm_wav_candidate': tag == 1 and bits in [8, 16]}

def vlq(b, pos):
    value = 0
    for _ in range(4):
        x = b[pos]
        pos += 1
        value = value << 7 | x & 127
        if not x & 128:
            return (value, pos)
    raise ValueError('MIDI VLQ exceeds4bytes')

def midi_info(b):
    assert b[:4] == b'MThd'
    size = struct.unpack_from('>I', b, 4)[0]
    fmt, ntracks, division = struct.unpack_from('>HHH', b, 8)
    pos = 8 + size
    tracks = []
    tempos = []
    for ti in range(ntracks):
        assert b[pos:pos + 4] == b'MTrk'
        length = struct.unpack_from('>I', b, pos + 4)[0]
        track = b[pos + 8:pos + 8 + length]
        assert len(track) == length
        pos += 8 + length
        p = 0
        tick = 0
        running = None
        events = []
        while p < len(track):
            delta, p = vlq(track, p)
            tick += delta
            status = track[p]
            if status < 128:
                assert running is not None
                status = running
            else:
                p += 1
                if status < 240:
                    running = status
            if status == 255:
                kind = track[p]
                p += 1
                n, p = vlq(track, p)
                payload = track[p:p + n]
                p += n
                e = {'tick': tick, 'type': 'meta', 'meta_type': kind, 'data_hex': payload.hex()}
                if kind in [1, 2, 3, 4, 5, 6, 7]:
                    e['text_ascii_preview'] = payload.decode('ascii', 'backslashreplace')
                if kind == 81 and n == 3:
                    tempos.append((tick, int.from_bytes(payload, 'big')))
            elif status in [240, 247]:
                n, p = vlq(track, p)
                payload = track[p:p + n]
                p += n
                e = {'tick': tick, 'type': 'sysex', 'status': status, 'data_hex': payload.hex()}
            else:
                assert status < 240
                kind = status >> 4
                n = 1 if kind in [12, 13] else 2
                payload = track[p:p + n]
                p += n
                e = {'tick': tick, 'type': 'channel', 'status': status, 'channel': status & 15, 'data': list(payload)}
            events.append(e)
        tracks.append({'index': ti, 'bytes': length, 'last_tick': tick, 'events': events})
    assert pos == len(b)
    last = max((t['last_tick'] for t in tracks), default=0)
    duration = None
    if not division & 32768:
        micros = 0
        prev = 0
        tempo = 500000
        for tick, new in sorted(set(tempos)):
            micros += (tick - prev) * tempo / division
            prev = tick
            tempo = new
        micros += (last - prev) * tempo / division
        duration = micros / 1000000.0
    return {'format': fmt, 'tracks': tracks, 'division_raw': division, 'ticks_per_quarter_note': division if not division & 32768 else None, 'last_tick': last, 'duration_s_from_tempo_map': duration, 'tempo_events': [list(x) for x in sorted(set(tempos))]}
