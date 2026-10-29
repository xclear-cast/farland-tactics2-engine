"""Fetch one official Godot archive and verify its official SHA-512 manifest."""
from pathlib import Path,PurePosixPath
import argparse
import hashlib
import json
import subprocess
import urllib.request
import zipfile

VERSION='4.7.2-stable'
NAME=f'Godot_v{VERSION}_macos.universal.zip'
BASE=f'https://github.com/godotengine/godot/releases/download/{VERSION}/'


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--destination',type=Path,required=True)
    args=parser.parse_args();destination=args.destination.resolve();destination.mkdir(parents=True,exist_ok=True)
    archive=destination/NAME
    urllib.request.urlretrieve(BASE+NAME,archive)
    request=urllib.request.Request(BASE+'SHA512-SUMS.txt',headers={'User-Agent':'FT2-macOS-build'})
    checksums=urllib.request.urlopen(request,timeout=60).read().decode('utf-8')
    expected=None
    for line in checksums.splitlines():
        fields=line.split()
        if len(fields)==2 and fields[1].lstrip('*./')==NAME:expected=fields[0].lower()
    with archive.open('rb')as stream:actual=hashlib.file_digest(stream,'sha512').hexdigest()
    if expected is None or expected!=actual:raise RuntimeError('Official Godot archive checksum did not match')
    with zipfile.ZipFile(archive)as packed:
        for entry in packed.infolist():
            path=PurePosixPath(entry.filename)
            if path.is_absolute()or '..'in path.parts:raise ValueError('Unsafe official archive path')
    subprocess.run(['ditto','-x','-k',str(archive),str(destination)],check=True,timeout=120)
    godot=destination/'Godot.app/Contents/MacOS/Godot'
    if not godot.is_file():raise FileNotFoundError(godot)
    godot.chmod(0o755)
    report={'version':VERSION,'source':BASE+NAME,'sha512':actual,'executable':str(godot)}
    (destination/'download_receipt.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(str(godot))


if __name__=='__main__':main()
