"""Convert a user's FT2 installation into a private, external engine cache.

Windows x64 and Apple Silicon macOS use the same Python converter. No existing
Godot port, Windows VM, captured game data, or original-game OS process is used.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import sys
import uuid

sys.path.insert(0,str(Path(__file__).resolve().parent))
from import_content import REQUIRED, sha, verify

FORMAT='standalone-installation-v1'


def dump(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8',newline='\n')


def source_files(source):
    rows={}
    for path in sorted(source.rglob('*')):
        if path.name=='.DS_Store' or path.name.startswith('._'):continue
        if path.is_symlink() or (hasattr(path,'is_junction') and path.is_junction()):
            raise ValueError(f'Installation links are unsupported: {path.name}')
        if path.is_file():rows[path.relative_to(source).as_posix()]=sha(path)
    if not rows:raise ValueError('Installation folder is empty')
    return rows


def pipeline_identity():
    if getattr(sys,'frozen',False):
        stamp=Path(getattr(sys,'_MEIPASS',Path(__file__).resolve().parent))/'converter_build.json'
        document=json.loads(stamp.read_text(encoding='utf-8'))
        value=str(document.get('pipeline_sha256',''))
        if len(value)!=64 or any(character not in '0123456789abcdef'for character in value):
            raise ValueError('Bundled converter build identity is invalid')
        return value
    root=Path(__file__).resolve().parent
    files=[Path(__file__),root/'import_content.py',root/'converters/font_charset.json',*sorted((root/'converters').rglob('*.py'))]
    return hashlib.sha256(json.dumps([(p.relative_to(root).as_posix(),sha(p))for p in files if not p.name.startswith('test_')],sort_keys=True).encode()).hexdigest()


def convert(source,cache_parent,*,font=None,cdda_dir=None,soundfont=None,full_font_charset=False):
    from converters import graphics,scenario,tables_audio,compatibility,fonts
    source,cache_parent=Path(source).expanduser().resolve(),Path(cache_parent).expanduser().resolve()
    if not source.is_dir():raise ValueError('Select the installed game folder containing DATA, MAP and SPRITE')
    if cache_parent==source or cache_parent.is_relative_to(source):raise ValueError('Private cache must be outside the original installation')
    exe=scenario.case_path(source,'FTO_O.EXE')
    if sha(exe)!=scenario.SUPPORTED_EXE:raise ValueError('This executable edition is unsupported; no guessed offsets will be used')
    font=fonts.find_font(font)
    if cdda_dir:
        cdda_dir=Path(cdda_dir).expanduser().resolve()
        if cache_parent==cdda_dir or cache_parent.is_relative_to(cdda_dir):raise ValueError('Cache must be outside the supplied CD audio folder')
    if soundfont:
        soundfont=Path(soundfont).expanduser().resolve()
        header=soundfont.read_bytes()[:12]if soundfont.is_file()else b''
        if header[:4]!=b'RIFF' or header[8:12]!=b'sfbk':raise ValueError('Select a valid SoundFont .sf2 file')
    before=source_files(source)
    option_files={str(font):sha(font)}
    extra_inputs={font:sha(font)}
    if soundfont:option_files[str(soundfont)]=sha(soundfont)
    if soundfont:extra_inputs[soundfont]=sha(soundfont)
    if cdda_dir:
        for path in sorted(cdda_dir.rglob('*')):
            if path.name=='.DS_Store' or path.name.startswith('._'):continue
            if path.is_symlink():raise ValueError('CD audio links are unsupported')
            if path.is_file():
                option_files[path.relative_to(cdda_dir).as_posix()]=sha(path)
                extra_inputs[path]=sha(path)
    identity={'source_files':before,'font_sha256':sha(font),'extra_files':option_files,'format':FORMAT,
              'pipeline_sha256':pipeline_identity(),'full_font_charset':full_font_charset}
    key=hashlib.sha256(json.dumps(identity,sort_keys=True).encode()).hexdigest()[:24]
    cache_parent.mkdir(parents=True,exist_ok=True)
    target=cache_parent/key
    if target.exists():
        verify(target)
        document=json.loads((target/'content.json').read_text(encoding='utf-8'))
        return {'status':'ready','reused':True,'content_root':str(target),'source_root':str(source),
                'adapter':FORMAT,'capabilities':document.get('capabilities',{}),'warnings':document.get('warnings',[])}
    stage=cache_parent/('.convert-'+uuid.uuid4().hex)
    stage.mkdir()
    dump(stage/'conversion_state.json',{'status':'preparing','format':FORMAT})
    def progress(text):print(text,file=sys.stderr,flush=True)
    reports={}
    progress('[1/6] Tables, saves, text and audio')
    reports['tables_audio']=tables_audio.convert(source,stage,cdda_source=cdda_dir)
    progress('[2/6] Indexed images, sprites and maps')
    reports['graphics']=graphics.convert(source,stage)
    if reports['graphics'].get('unsupported'):raise ValueError('Unsupported image files: '+str(reports['graphics']['unsupported'][:3]))
    progress('[3/6] Events, UI resources and cinematic controllers')
    reports['scenario']=scenario.convert(source,stage,include_leaf_graphs=True)
    partial=[row for row in reports['scenario']['events']if row.get('status')!='complete_structural_parse']
    unsupported=[row for row in partial if not(str(row.get('file','')).upper()=='EVENT98.DAT' and row.get('status')=='partial_with_lossless_unresolved')]
    if unsupported:raise ValueError('Event conversion is incomplete: '+str(unsupported[:3]))
    for index in range(18):
        if not(stage/f'data/port_ready/scripts/normalized/DATA/EVENT{index:02d}.json').is_file():
            raise ValueError(f'Campaign EVENT{index:02d} missing')
    reports['save_bindings']=tables_audio.finalize_save_bindings(stage)
    if reports['save_bindings'].get('unresolved'):raise ValueError('Unresolved original save locations')
    progress('[4/6] Executable resource and compatibility tables')
    reports['compatibility']=compatibility.convert(source,stage)
    if soundfont:
        out=stage/'assets/audio/TimGM6mb.sf2';out.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(soundfont,out)
    progress('[5/6] Portable Korean font masks and cursors')
    reports['fonts']=fonts.convert(stage,font=font,full_charset=full_font_charset)
    audio=reports['tables_audio']
    capabilities={'audio':{'cdda_tracks':int(audio.get('cdda_tracks',0)),'soundfont':soundfont is not None},
                  'fonts':{'backend':'portable-user-font','Win95_pixel_equivalence':False},
                  'converter_platform_targets':['windows-x64','macos-arm64','linux-x64']}
    warnings=['Portable font rendering differs from Win95 GDI. User/system font data remain private.']
    if partial:warnings.append('Original development EVENT98 contains unsupported system99 commands; lossless data were preserved. Campaign EVENT00..17 are fully parsed.')
    if capabilities['audio']['cdda_tracks']==0:
        warnings.append('No CD music supplied; MIDI music will be used.'if soundfont else 'No CD music or SoundFont supplied. Background music is unavailable; original sound effects remain enabled.')
    if audio.get('audio_errors'):warnings.append('The original installation contains '+str(len(audio['audio_errors']))+' malformed audio entries; their bytes were preserved and reported.')
    if reports['graphics'].get('original_missing_sheets'):warnings.append('The original installation itself is missing '+str(len(reports['graphics']['original_missing_sheets']))+' declared sprite sheets; no substitute art was invented.')
    progress('[6/6] Integrity and engine-readiness checks')
    if source_files(source)!=before:raise RuntimeError('The original installation changed during conversion; cache not activated')
    if any(not path.is_file() or sha(path)!=expected for path,expected in extra_inputs.items()):
        raise RuntimeError('A supplied font or music input changed during conversion; cache not activated')
    for logical in REQUIRED:
        if not(stage/logical).is_file():raise ValueError('Required engine input missing: '+logical)
    if len(list((stage/'data/port_ready/scripts/cinematics/contracts/leaf_graphs').glob('profile*.json')))!=36:
        raise ValueError('Required cinematic controllers missing')
    for name in ('ITEM','MAGIC','RACE'):
        before['DATA/'+name+'.DAT']=sha(scenario.case_path(source,'DATA/'+name+'.DAT'))
    before['FTO_O.EXE']=sha(exe)
    dump(stage/'conversion_report.json',{'format':FORMAT,'source_modified':False,'legacy_workspace_used':False,
          'reports':reports,'warnings':warnings,'capabilities':capabilities})
    (stage/'conversion_state.json').unlink()
    rows=[{'path':path.relative_to(stage).as_posix(),'bytes':path.stat().st_size,'sha256':sha(path)}
          for path in sorted(stage.rglob('*'))if path.is_file()]
    document={'schema':1,'status':'ready','content_id':key,'adapter':FORMAT,'redistributable':False,
              'source_root':str(source),'source_files':before,'required':list(REQUIRED),'files':rows,
              'bytes':sum(row['bytes']for row in rows),'warnings':warnings,'capabilities':capabilities,
              'pipeline_sha256':identity['pipeline_sha256']}
    dump(stage/'content.json',document)
    verify(stage)
    os.replace(stage,target)
    return {'status':'ready','reused':False,'content_root':str(target),'source_root':str(source),
            'adapter':FORMAT,'files':len(rows),'bytes':document['bytes'],'warnings':warnings,'capabilities':capabilities}


def main():
    if hasattr(sys.stdout,'reconfigure'):sys.stdout.reconfigure(encoding='utf-8')
    if hasattr(sys.stderr,'reconfigure'):sys.stderr.reconfigure(encoding='utf-8')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--cache-parent',type=Path,required=True)
    parser.add_argument('--font',type=Path)
    parser.add_argument('--cdda-dir',type=Path)
    parser.add_argument('--soundfont',type=Path)
    parser.add_argument('--full-font-charset',action='store_true')
    args=parser.parse_args()
    try:
        result=convert(args.source,args.cache_parent,font=args.font,cdda_dir=args.cdda_dir,
                       soundfont=args.soundfont,full_font_charset=args.full_font_charset)
        print(json.dumps(result,ensure_ascii=False))
    except Exception as error:
        message=str(error)
        if isinstance(error,ModuleNotFoundError):message+='; install dependencies with: python -m pip install -r requirements.txt'
        print(json.dumps({'status':'error','error':message},ensure_ascii=False))
        raise SystemExit(1)


if __name__=='__main__':main()
