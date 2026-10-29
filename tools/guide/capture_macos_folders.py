"""Capture real Finder windows on a temporary Mac runner, without TCC changes.

Only this project's downloaded archive, extracted app and self-authored folder
layout fixture are opened. Raw PNGs are never selected for artifact upload. A
32-byte base64 FINDER_GUIDE_CAPTURE_KEY encrypts successful captures with AES-GCM.
"""
from pathlib import Path,PurePosixPath
import argparse
import base64
import hashlib
import io
import json
import os
import platform
import posixpath
import shutil
import struct
import subprocess
import time
import zipfile

SWIFT=r'''
import Foundation
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String:Any]] ?? []
let windows = list.filter { ($0[kCGWindowOwnerName as String] as? String) == "Finder" && ($0[kCGWindowLayer as String] as? Int ?? -1) == 0 }
let result:[String:Any] = ["screen_capture_preflight":CGPreflightScreenCaptureAccess(), "display_width":CGDisplayPixelsWide(CGMainDisplayID()), "display_height":CGDisplayPixelsHigh(CGMainDisplayID()), "windows":windows]
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(data:data,encoding:.utf8)!)
'''


def run(arguments,timeout=20):
    result=subprocess.run([str(value)for value in arguments],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=timeout)
    if result.returncode:raise RuntimeError(f'Command failed ({result.returncode}): {Path(str(arguments[0])).name}: '+(result.stdout+result.stderr)[-3000:])
    return result.stdout


def apple_string(value):return '"'+str(value).replace('\\','\\\\').replace('"','\\"')+'"'


def safe_archive(archive):
    with zipfile.ZipFile(archive)as packed:
        for entry in packed.infolist():
            name=PurePosixPath(entry.filename)
            if name.is_absolute()or '..'in name.parts:raise ValueError('Unsafe input archive path')
            if entry.external_attr>>16&0o170000==0o120000:
                target=packed.read(entry).decode('utf-8')
                resolved=posixpath.normpath(str(name.parent/target))
                if target.startswith('/')or resolved=='..'or resolved.startswith('../'):raise ValueError('Input archive contains an escaping symlink')


def show_folder(folder,selected,bounds):
    select=f'select (item {apple_string(selected)} of target of guideWindow)'if selected else ''
    script=f'''tell application "Finder"
activate
open (POSIX file {apple_string(folder)} as alias)
set guideWindow to front Finder window
set target of guideWindow to (POSIX file {apple_string(folder)} as alias)
set current view of guideWindow to list view
set bounds of guideWindow to {{{','.join(str(v)for v in bounds)}}}
{select}
return (POSIX path of (target of guideWindow as alias)) & "|" & (name of guideWindow)
end tell'''
    return run(['osascript','-e',script],timeout=15).strip()


def encrypt_captures(raw,output,key):
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    stream=io.BytesIO()
    with zipfile.ZipFile(stream,'w',compression=zipfile.ZIP_DEFLATED)as packed:
        for path in sorted(raw.glob('*.png')):packed.write(path,path.name)
        packed.write(raw/'capture_manifest.json','capture_manifest.json')
    nonce=os.urandom(12)
    encrypted=b'FT2GUIDE1'+nonce+AESGCM(key).encrypt(nonce,stream.getvalue(),b'FT2 real Finder captures v1')
    (output/'finder-captures.aesgcm').write_bytes(encrypted)


def decrypt_capture(encrypted,key_file,output):
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    key=base64.b64decode(key_file.read_text(encoding='utf-8').strip(),validate=True)
    raw=encrypted.read_bytes()
    if len(key)!=32 or raw[:9]!=b'FT2GUIDE1':raise ValueError('Invalid capture key or file format')
    payload=AESGCM(key).decrypt(raw[9:21],raw[21:],b'FT2 real Finder captures v1')
    output.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(payload))as packed:
        for entry in packed.infolist():
            if len(PurePosixPath(entry.filename).parts)!=1:raise ValueError('Unexpected encrypted capture path')
            target=output/entry.filename
            if target.exists():raise ValueError('Refusing to overwrite an existing reviewed capture')
            target.write_bytes(packed.read(entry))
    print(json.dumps({'status':'decrypted','files':len(list(output.iterdir()))}))


def capture(archive,output):
    if platform.system()!='Darwin'or platform.machine()!='arm64':raise RuntimeError('This capture task requires the temporary Apple Silicon runner')
    output.mkdir(parents=True,exist_ok=True)
    workspace=output/'runner-only';workspace.mkdir(exist_ok=True)
    raw=workspace/'raw';raw.mkdir(exist_ok=True)
    report={'status':'preparing','actual_native_capture':True,'tcc_settings_changed':False,
            'explicit_permission_request_api_called':False,'permission_bypassed':False,
            'original_game_data_used':False,'raw_images_uploaded':False,'captures':[]}
    try:
        safe_archive(archive)
        downloads=workspace/'01-Download';downloads.mkdir(exist_ok=True)
        copied=downloads/'FT2-External-macos-arm64.zip';shutil.copyfile(archive,copied)
        unpacked=workspace/'02-Unpacked';unpacked.mkdir(exist_ok=True)
        run(['ditto','-x','-k',copied,unpacked],timeout=90)
        apps=list(unpacked.rglob('FT2 External Engine.app'))
        if len(apps)!=1:raise RuntimeError('Expected exactly one real app from the successful build artifact')
        app_folder=apps[0].parent
        example=workspace/'03-Example-game-folder';example.mkdir(exist_ok=True)
        for name in ('DATA','MAP','SPRITE'):(example/name).mkdir(exist_ok=True)
        (example/'FTO_O.EXE').write_bytes(b'')
        source=workspace/'finder_windows.swift';source.write_text(SWIFT,encoding='utf-8')
        helper=workspace/'finder_windows'
        run(['xcrun','swiftc',source,'-o',helper],timeout=90)
        environment=json.loads(run([helper]))
        report['screen_capture_preflight']=environment['screen_capture_preflight']
        width,height=int(environment['display_width']),int(environment['display_height'])
        if width<640 or height<480:raise RuntimeError('No usable graphical desktop is available on this runner')
        bounds=[40,40,min(width-30,1080),min(height-30,740)]
        for name,folder,selection in [('01-downloaded-zip',downloads,copied.name),('02-extracted-app',app_folder,apps[0].name),('03-game-folder-example',example,'FTO_O.EXE')]:
            finder_state=show_folder(folder,selection,bounds)
            time.sleep(1)
            state=json.loads(run([helper]))
            windows=[]
            for window in state['windows']:
                frame=window.get('kCGWindowBounds',{})
                if int(frame.get('Width',0))<300 or int(frame.get('Height',0))<200:continue
                distance=abs(float(frame.get('X',0))-bounds[0])+abs(float(frame.get('Y',0))-bounds[1])
                distance+=abs(float(frame.get('Width',0))-(bounds[2]-bounds[0]))+abs(float(frame.get('Height',0))-(bounds[3]-bounds[1]))
                windows.append((distance,window))
            if not windows:raise RuntimeError('Finder window IDs were unavailable; Screen Recording/Automation permission may be blocked')
            distance,window=min(windows,key=lambda row:row[0])
            if distance>100:raise RuntimeError('Could not identify the specific temporary Finder window safely')
            target=raw/(name+'.png')
            run(['screencapture','-x','-o','-l',str(window['kCGWindowNumber']),target],timeout=15)
            data=target.read_bytes()
            if data[:8]!=b'\x89PNG\r\n\x1a\n':raise RuntimeError('macOS did not produce a native PNG screenshot')
            image_width,image_height=struct.unpack('>II',data[16:24])
            if image_width<300 or image_height<200:raise RuntimeError('Native Finder capture is unexpectedly small')
            report['captures'].append({'name':target.name,'sha256':hashlib.sha256(data).hexdigest(),
                'width':image_width,'height':image_height,'finder_state':finder_state,'window_id':window['kCGWindowNumber'],
                'window_bounds':window['kCGWindowBounds'],'selected_item':selection,'example_only':name=='03-game-folder-example'})
        report['status']='captured-before-encryption'
        (raw/'capture_manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        encoded=os.environ.get('FINDER_GUIDE_CAPTURE_KEY','').strip()
        if not encoded:
            report['status']='captured-local-only-no-key';report['error']='No encryption key provided; raw screenshots remain runner-local and are not uploaded'
        else:
            key=base64.b64decode(encoded,validate=True)
            if len(key)!=32:raise ValueError('Capture encryption key must be 32 bytes')
            encrypt_captures(raw,output,key)
            report['status']='captured-encrypted';report['encrypted_artifact']='finder-captures.aesgcm'
    except (RuntimeError,ValueError,OSError,zipfile.BadZipFile,subprocess.TimeoutExpired)as error:
        report['status']='blocked';report['error']=str(error)
    (output/'capture_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps({'status':report['status'],'captured_windows':len(report['captures']),'error':report.get('error')}))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--decrypt',type=Path)
    parser.add_argument('--key-file',type=Path)
    args=parser.parse_args()
    if args.decrypt:
        if not args.key_file:parser.error('--key-file is required for local decryption')
        decrypt_capture(args.decrypt,args.key_file,args.output)
    else:
        if not args.archive:parser.error('--archive is required on the temporary runner')
        capture(args.archive.resolve(),args.output.resolve())


if __name__=='__main__':main()
