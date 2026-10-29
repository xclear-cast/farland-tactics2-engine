"""Create the beginner Windows ZIP from an audited engine/converter build."""
from pathlib import Path
import argparse
import hashlib
import json
import zipfile

ROOT=Path(__file__).resolve().parents[1]
TOP={'FT2-External.exe','FT2-External.pck','Launch-Windows.cmd','Game-Setup-Windows.cmd',
     'README.md','LICENSING.md','THIRD_PARTY_NOTICES.md','GODOT_LICENSES.txt',
     'TINYSOUNDFONT_LICENSE.txt','engine_manifest.json','requirements.txt','COPYING-converter','CONVERTER_LICENSE.json','EXAMPLES_LICENSE'}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=ROOT/'dist/FT2-External-Engine')
    parser.add_argument('--output',type=Path,default=ROOT/'private/releases/FT2-Windows-x64.zip')
    args=parser.parse_args()
    source=args.source.resolve();output=args.output.resolve()
    required=['FT2-External.exe','FT2-External.pck','Launch-Windows.cmd','Game-Setup-Windows.cmd',
              'tools/ft2-convert/ft2-convert.exe','tools/ft2-convert/converter_build_result.json',
              'native/bin/ft2synth.dll']
    for name in required:
        if not(source/name).is_file():raise ValueError('Missing Windows release file: '+name)
    marker=json.loads((source/'tools/ft2-convert/converter_build_result.json').read_text(encoding='utf-8'))
    if marker.get('original_game_data_included')is not False or marker.get('requires_python_installation')is not False:
        raise ValueError('Converter is not a standalone, original-data-free build')
    files=[]
    for path in sorted(source.rglob('*')):
        if not path.is_file():continue
        relative=path.relative_to(source)
        name=relative.as_posix()
        if relative.suffix.lower()in ('.gif','.mp4','.webm','.mov','.avi','.mkv'):
            raise ValueError('Instructional media is excluded from the text-only release: '+name)
        if path.is_symlink():raise ValueError('Release symlink rejected: '+name)
        if any(part in ('private','__pycache__','.venv','.git')for part in relative.parts):raise ValueError('Private files in release input: '+name)
        if name in TOP or name.startswith(('tools/','mods/','docs/')) or name=='native/bin/ft2synth.dll':files.append((path,name))
    output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6)as archive:
        for path,name in files:archive.write(path,'FT2-Windows-x64/'+name)
    with output.open('rb')as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
    result={'status':'packaged','zip':output.name,'bytes':output.stat().st_size,'sha256':digest,
            'files':len(files),'original_game_content_included':False,'requires_python_installation':False,
            'launch':'FT2-Windows-x64/Launch-Windows.cmd','setup':'FT2-Windows-x64/Game-Setup-Windows.cmd'}
    output.with_suffix('.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result))


if __name__=='__main__':main()
