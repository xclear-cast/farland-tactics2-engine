"""Fetch one official Windows Godot archive and verify its SHA-512 manifest."""
from pathlib import Path,PurePosixPath
import argparse
import hashlib
import json
import urllib.request
import zipfile

VERSION='4.7.2-stable'
NAME=f'Godot_v{VERSION}_win64.exe.zip'
CONSOLE_BINARY=f'Godot_v{VERSION}_win64_console.exe'
GUI_BINARY=f'Godot_v{VERSION}_win64.exe'
BASE=f'https://github.com/godotengine/godot/releases/download/{VERSION}/'


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--destination',type=Path,required=True)
    args=parser.parse_args();destination=args.destination.resolve();destination.mkdir(parents=True,exist_ok=True)
    archive=destination/NAME
    urllib.request.urlretrieve(BASE+NAME,archive)
    request=urllib.request.Request(BASE+'SHA512-SUMS.txt',headers={'User-Agent':'FT2-Windows-CI'})
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
        packed.extractall(destination)
    console=destination/CONSOLE_BINARY
    gui=destination/GUI_BINARY
    if not console.is_file()or not gui.is_file():raise FileNotFoundError(console)
    report={'version':VERSION,'source':BASE+NAME,'sha512':actual,'console_executable':str(console),'gui_executable':str(gui)}
    (destination/'download_receipt.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(str(console))


if __name__=='__main__':main()
