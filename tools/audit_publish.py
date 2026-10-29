"""Fail closed on the source publication boundary, without printing secret values.

Use --paths-file to stage the exact allowlisted sources, then --staged before a
commit/push. The audit checks data/secret exclusions; it is not a copyright or
open-source-licence clearance.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
ROOT_FILES={'.gitignore','README.md','requirements.txt','build-requirements.txt','LICENSING.md','THIRD_PARTY_NOTICES.md'}
GAME_FILES={'game/project.godot','game/pack_external.gd','game/write_notices.gd',
            'game/native/ft2_synth.c','game/native/ft2_synth.gdextension',
            'game/native/include/gdextension_interface.h','game/native/include/tsf.h'}
TOOL_FILES={'audit_publish.py','build_external.py','build_macos_arm64.py',
            'convert_installation.py','import_content.py','package_converter.py',
            'run_tests.py','update_font_charset.py','build_converter_binary.py','package_windows_release.py'}
SOURCE_SUFFIXES={'.gd','.gdshader','.gdshaderinc','.uid'}
FORBIDDEN_PARTS={'private','dist','.git','.venv','.godot','__pycache__','node_modules'}
DATA_SUFFIXES={'.dat','.bin','.idx','.pal','.bmp','.png','.jpg','.jpeg','.wav','.mid',
               '.sf2','.exe','.pck','.ttf','.ttc','.otf','.zip','.7z','.tar','.lzh',
               '.img','.pdb','.dll','.so','.dylib','.lib'}
SECRET_PATTERNS={
    'private_key':re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'),
    'github_token':re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})\b'),
    'openai_key':re.compile(r'\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{30,}\b'),
    'aws_access_key':re.compile(r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
}

def private_paths():
    values={str(ROOT),ROOT.as_posix(),str(ROOT.parent),ROOT.parent.as_posix(),str(Path.home()),Path.home().as_posix()}
    if ROOT.drive:
        for path in (ROOT,ROOT.parent,Path.home()):
            if path.drive:values.add('/mnt/'+path.drive[0].lower()+'/'+'/'.join(path.parts[1:]))
    return tuple(value for value in values if len(value)>8)


def allowed(relative):
    p=PurePosixPath(relative)
    if p.is_absolute()or any(part in ('','..',*FORBIDDEN_PARTS)for part in p.parts):return False
    if p.suffix.casefold()in DATA_SUFFIXES:return False
    if relative in ROOT_FILES or relative in GAME_FILES:return True
    if relative in {'game/pack_external.gd.uid','game/write_notices.gd.uid','game/native/ft2_synth.gdextension.uid'}:return True
    if relative.startswith('game/scripts/')and p.suffix in SOURCE_SUFFIXES:return True
    if relative.startswith('game/scenes/')and p.suffix=='.tscn':return True
    if relative.startswith('game/tests/')and p.suffix in {'.gd','.uid'}:return True
    if relative.startswith('tools/converters/'):
        return p.suffix=='.py' or p.name in {'README.md','requirements.txt','font_charset.json'}
    if p.parent==PurePosixPath('tools')and p.name in TOOL_FILES:return True
    if relative.startswith('tools/ci/')and p.suffix in {'.py','.sh'}:return True
    if relative=='tools/ci/macos_app_launcher.c':return True
    if relative.startswith('.github/workflows/')and p.suffix in {'.yml','.yaml'}:return True
    return relative=='mods/example_balance/mod.json'


def sha(data):return hashlib.sha256(data).hexdigest()


def inspect(relative,data):
    errors=[]
    if not allowed(relative):return [{'path':relative,'kind':'outside_publication_allowlist'}]
    try:text=data.decode('utf-8')
    except UnicodeDecodeError:return [{'path':relative,'kind':'unexpected_binary'}]
    if b'\0'in data:errors.append({'path':relative,'kind':'unexpected_nul_byte'})
    for name,pattern in SECRET_PATTERNS.items():
        if pattern.search(text):errors.append({'path':relative,'kind':name})
    for value in private_paths():
        if value in text:errors.append({'path':relative,'kind':'machine_specific_private_path'})
    if relative.endswith('.uid')and not re.fullmatch(r'uid://[a-z0-9]+\s*',text):
        errors.append({'path':relative,'kind':'invalid_godot_uid_file'})
    if relative=='tools/converters/font_charset.json':
        document=json.loads(text)
        if document.get('schema')!=1 or any(not isinstance(n,int)or not 0<=n<=0x10ffff for n in document.get('codepoints',[])):
            errors.append({'path':relative,'kind':'invalid_character_code_catalog'})
    return errors


def source_paths():
    paths={ROOT/name for name in ROOT_FILES|GAME_FILES}
    paths.update(ROOT/'tools'/name for name in TOOL_FILES)
    paths.update(ROOT/name for name in ('game/pack_external.gd.uid','game/write_notices.gd.uid','game/native/ft2_synth.gdextension.uid','mods/example_balance/mod.json'))
    for directory in ('game/scripts','game/scenes','game/tests','tools/converters','tools/ci','.github/workflows'):
        base=ROOT/directory
        if base.is_dir():paths.update(base.rglob('*'))
    for path in sorted(paths):
        relative=path.relative_to(ROOT).as_posix()
        if not allowed(relative):continue
        if path.is_symlink():raise ValueError('Publication symlink rejected: '+relative)
        if path.is_file():yield relative,path.read_bytes()


def staged_paths():
    modes={}
    for record in subprocess.check_output(['git','ls-files','--stage','-z'],cwd=ROOT).split(b'\0'):
        if record:
            metadata,name=record.split(b'\t',1)
            modes[name.decode('utf-8')]=metadata.split(b' ',1)[0]
    names=subprocess.check_output(['git','diff','--cached','--name-only','--diff-filter=ACMR','-z'],cwd=ROOT)
    for encoded in names.split(b'\0'):
        if not encoded:continue
        relative=encoded.decode('utf-8')
        if modes.get(relative)not in (b'100644',b'100755'):
            raise ValueError('Publication requires regular source files: '+relative)
        data=subprocess.check_output(['git','show',':'+relative],cwd=ROOT)
        yield relative,data


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged',action='store_true')
    parser.add_argument('--paths-file',type=Path,help='Write NUL-separated exact source paths for git add --pathspec-file-nul')
    parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    rows=[];errors=[]
    for relative,data in staged_paths()if args.staged else source_paths():
        errors.extend(inspect(relative,data));rows.append({'path':relative,'bytes':len(data),'sha256':sha(data)})
    if not rows:errors.append({'kind':'empty_source_selection'})
    report={'status':'passed_source_boundary'if not errors else'failed','mode':'staged'if args.staged else'allowlist',
            'file_count':len(rows),'bytes':sum(row['bytes']for row in rows),'files':rows,'errors':errors,
            'original_game_content_allowed':False,'machine_private_data_allowed':False,
            'project_wide_licensing_review':'pending; this audit does not grant redistribution rights'}
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    if args.paths_file and not errors:
        args.paths_file.parent.mkdir(parents=True,exist_ok=True)
        args.paths_file.write_bytes(b''.join(row['path'].encode('utf-8')+b'\0'for row in rows))
    print(json.dumps({key:value for key,value in report.items()if key!='files'},ensure_ascii=False))
    raise SystemExit(1 if errors else 0)


if __name__=='__main__':main()
