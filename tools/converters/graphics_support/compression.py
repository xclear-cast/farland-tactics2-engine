"""SZDD decompression for user-provided game data."""
import struct


SZDD_SIG = b"SZDD\x88\xf0\x27\x33"

def szdd_decompress(data: bytes) -> bytes:
    if not data.startswith(SZDD_SIG):
        return data
    out_len = struct.unpack_from("<I", data, 10)[0]
    src = memoryview(data)[14:]
    window = bytearray([0x20] * 4096)
    pos = 4096 - 16
    out = bytearray()
    i = 0
    while i < len(src):
        control = src[i]
        i += 1
        bit = 1
        while bit & 0xFF:
            if control & bit:
                if i >= len(src):
                    break
                b = src[i]
                i += 1
                window[pos] = b
                pos = (pos + 1) & 0xFFF
                out.append(b)
            else:
                if i + 1 >= len(src):
                    break
                matchpos = src[i]
                matchlen = src[i + 1]
                i += 2
                matchpos |= (matchlen & 0xF0) << 4
                matchlen = (matchlen & 0x0F) + 3
                for _ in range(matchlen):
                    b = window[matchpos]
                    window[pos] = b
                    pos = (pos + 1) & 0xFFF
                    matchpos = (matchpos + 1) & 0xFFF
                    out.append(b)
            bit <<= 1
            if len(out) >= out_len:
                return bytes(out[:out_len])
    return bytes(out[:out_len])
