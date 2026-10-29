"""Build PRIVATE font masks from a user/system font, on Windows/macOS/Linux.

The generated masks use FreeType metrics, not Win95 GDI pixels. No Windows fonts
or captured glyphs are redistributed by this converter.
"""
from pathlib import Path
import hashlib
import json
import os
import struct


def dump(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,separators=(',',':')),encoding='utf-8')


def find_font(requested=None):
    if requested:
        path=Path(requested).expanduser().resolve()
        if not path.is_file():raise ValueError(f'Font not found: {path}')
        return path
    windows=Path(os.environ.get('WINDIR','C:/Windows'))/'Fonts'
    candidates=[windows/'malgun.ttf',windows/'gulim.ttc',
        Path('/System/Library/Fonts/AppleSDGothicNeo.ttc'),
        Path('/System/Library/Fonts/Supplemental/AppleGothic.ttf'),
        Path('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'),
        Path('/usr/share/fonts/truetype/nanum/NanumGothic.ttf')]
    for path in candidates:
        if path.is_file():return path
    raise ValueError('A Korean-capable font is required. Pass --font /path/to/font.ttf (or .ttc).')


def characters(output,engine_scripts=None):
    result=set(chr(n)for n in range(32,127))|{'\u3000'}
    def visit(value):
        if isinstance(value,str):result.update(c for c in value if ord(c)>=32 and ord(c)!=127)
        elif isinstance(value,list):
            for child in value:visit(child)
        elif isinstance(value,dict):
            for key,child in value.items():
                if not key.endswith(('_hex','_sha256')):visit(child)
    for path in (output/'data/port_ready').rglob('*.json'):
        visit(json.loads(path.read_text(encoding='utf-8')))
    # Cover all CP949 characters so runtime menus and player-entered names work
    # even when a character is absent from the original scenario text.
    codec=json.loads((output/'assets/cp949.json').read_text(encoding='utf-8'))
    result.update(chr(int(code))for code in codec['encode']if int(code)>=32)
    return sorted(result,key=ord)


def convert(output,*,font=None,full_charset=False):
    from PIL import Image,ImageDraw,ImageFont
    output=Path(output)
    font_path=find_font(font)
    chars=characters(output)
    if not full_charset:
        # All actual converted text plus ASCII. The optional full charset is
        # useful for custom content; the default keeps initial setup quick.
        codec_path=output/'assets/cp949.json'
        chars_set=set(chr(n)for n in range(32,127))|{'\u3000'}
        def collect(value):
            if isinstance(value,str):chars_set.update(c for c in value if ord(c)>=32 and ord(c)!=127)
            elif isinstance(value,list):
                for child in value:collect(child)
            elif isinstance(value,dict):
                for key,child in value.items():
                    if not key.endswith(('_hex','_sha256')):collect(child)
        for path in (output/'data/port_ready').rglob('*.json'):
            collect(json.loads(path.read_text(encoding='utf-8')))
        # Menus authored by the engine are independent of the game data.
        collect('게임 데이터 연결 정품 설치 폴더 개인 콘텐츠 캐시 생성 모드 선택 확인 취소 저장 불러오기 종료 설정 음악 효과음 경험치 레벨 공격 방어 지력 민첩 마법 저항력 이동 대기 장비 물품 사용 상태 수량 돈 가격 구입 판매 목표 아군 적군 전체화면 창모드 예 아니오')
        catalog=Path(__file__).with_name('font_charset.json')
        if catalog.is_file():
            chars_set.update(chr(int(code))for code in json.loads(catalog.read_text(encoding='utf-8'))['codepoints'])
        chars=sorted(chars_set,key=ord)
    presets=[('바탕',n,700,0)for n in (1,8,10,12,14,16,20,23,24,26,28,32,45,48,60)]
    presets += [('바탕',n,700,1)for n in (16,32,35,37,45,48,57,60)]
    presets += [('굴림',n,400,0)for n in (-12,-13,-15,-16)]
    packed=bytearray();styles=[]
    for family,height,weight,italic in presets:
        size=max(1,round(abs(height)*.82))if height>0 else abs(height)
        face=ImageFont.truetype(str(font_path),size=size,layout_engine=ImageFont.Layout.BASIC)
        ascent,descent=face.getmetrics();cell=max(1,abs(height)if height>0 else ascent+descent)
        glyphs={}
        for character in chars:
            mask,offset=face.getmask2(character,mode='1',stroke_width=0)
            width,rows=mask.size
            data=bytes(1 if value else 0 for value in mask)
            if italic and width and rows:
                image=Image.frombytes('L',(width,rows),bytes(255*x for x in data))
                extra=max(1,rows//5)
                image=image.transform((width+extra,rows),Image.Transform.AFFINE,(1,.2,-extra,0,1,0),resample=Image.Resampling.NEAREST)
                width,rows=image.size;data=bytes(1 if value else 0 for value in image.tobytes())
            start=len(packed);packed.extend(data)
            advance=max(0,round(face.getlength(character)))
            glyphs[str(ord(character))]={'offset':start,'rect':[offset[0],offset[1],width,rows],
                                        'advance':[advance,cell],'pen':advance}
        metrics={'height':cell,'ascent':ascent,'descent':descent,'overhang':0,
                 'internal_leading':max(0,cell-ascent-descent),'external_leading':0,
                 'average_width':max(1,round(face.getlength('n'))),'max_width':max(1,round(face.getlength('한')))}
        styles.append({'family':family,'height':height,'weight':weight,'italic':italic,'metrics':metrics,'glyphs':glyphs})
    target=output/'assets/indexed';target.mkdir(parents=True,exist_ok=True)
    (target/'font_masks.bin').write_bytes(packed)
    dump(target/'fonts.json',{'mask_file':'res://assets/indexed/font_masks.bin','styles':styles,
         'font_sha256':hashlib.sha256(font_path.read_bytes()).hexdigest(),'fidelity':'portable-user-font;not-Win95-GDI-pixel-equivalence'})
    dump(target/'font_otm.json',{'rows':[],'backend':'portable-freetype'})
    manifest_path=target/'manifest.json'
    if manifest_path.exists():
        manifest=json.loads(manifest_path.read_text(encoding='utf-8'));manifest['fonts']='res://assets/indexed/fonts.json';dump(manifest_path,manifest)
    cursor_results=[]
    for identifier in (32512,32513,32514,32515):
        image=Image.new('RGBA',(32,32),(0,0,0,0));draw=ImageDraw.Draw(image)
        if identifier==32512:
            draw.polygon([(2,1),(2,25),(8,19),(13,29),(17,27),(12,17),(22,17)],fill='white',outline='black');hotspot=(2,1)
        elif identifier==32513:
            draw.line((16,3,16,28),fill='black',width=3);draw.line((11,3,21,3),fill='black',width=2);draw.line((11,28,21,28),fill='black',width=2);hotspot=(16,16)
        elif identifier==32514:
            draw.ellipse((4,4,27,27),fill='white',outline='black',width=2);draw.line((16,8,16,16,23,20),fill='black',width=2);hotspot=(16,16)
        else:
            draw.line((3,16,28,16),fill='black',width=2);draw.line((16,3,16,28),fill='black',width=2);hotspot=(16,16)
        xor=bytearray(128);and_mask=bytearray([255]*128)
        for y in range(32):
            for x in range(32):
                r,g,b,a=image.getpixel((x,y));index=(31-y)*4+x//8;bit=1<<(7-x%8)
                if a:and_mask[index]&=255^bit
                if a and r+g+b>=384:xor[index]|=bit
        raw=struct.pack('<HHIiiHHIIiiII',*hotspot,40,32,64,1,1,0,256,0,0,2,0)
        raw+=bytes((0,0,0,0,255,255,255,0))+xor+and_mask
        path=output/f'assets/cursors/system_cursor_{identifier}.bin';path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw);cursor_results.append(identifier)
    return {'font_backend':'portable-user-font','font_file':str(font_path),'styles':len(styles),
            'characters':len(chars),'mask_bytes':len(packed),'Win95_pixel_equivalence':False,
            'system_cursors':'independently drawn portable shapes','cursor_ids':cursor_results}
