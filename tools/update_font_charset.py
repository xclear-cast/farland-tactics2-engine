"""Record UI character codepoints only, never font pixels or game content."""
from pathlib import Path
import json


def update(root):
    root=Path(root)
    characters=set(range(32,127))
    for path in (root/'game/scripts').rglob('*.gd'):
        characters.update(ord(c)for c in path.read_text(encoding='utf-8')if c.isprintable())
    target=root/'tools/converters/font_charset.json'
    document={'schema':1,'source':'Engine UI source character repertoire; no game data or font glyphs',
              'codepoints':sorted(characters)}
    target.write_text(json.dumps(document,separators=(',',':')),encoding='utf-8',newline='\n')
    return len(characters)


if __name__=='__main__':print({'engine_ui_characters':update(Path(__file__).resolve().parents[1])})
