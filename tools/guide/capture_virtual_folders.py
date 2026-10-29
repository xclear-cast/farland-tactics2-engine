"""Capture real file-manager windows in a dedicated Xvfb; no host desktop UI."""
from pathlib import Path
import json
import os
import shutil
import socket
import subprocess
import time
import zipfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'private/folder_guide/virtual'
DEMO=Path('/tmp/FT2-Guide')


def run(args,env):return subprocess.check_output([str(x)for x in args],env=env,text=True).strip()


def alive(number):
    for address in ('\0/tmp/.X11-unix/X'+str(number),'/tmp/.X11-unix/X'+str(number)):
        with socket.socket(socket.AF_UNIX)as client:
            try:client.connect(address);return True
            except OSError:pass
    return False


def main():
    OUT.mkdir(parents=True,exist_ok=True);DEMO.mkdir(exist_ok=True)
    base=DEMO/'MyGames';base.mkdir(exist_ok=True)
    archive=base/'FT2-Windows-x64.zip'
    if not archive.exists():shutil.copyfile(ROOT/'private/releases/FT2-Windows-x64.zip',archive)
    with zipfile.ZipFile(archive)as zipped:
        for info in zipped.infolist():
            target=(base/info.filename).resolve()
            if not target.is_relative_to(base.resolve()):raise ValueError('Unsafe release member')
        zipped.extractall(base)
    original=base/'FT2-Original';original.mkdir(exist_ok=True)
    for name in ('DATA','MAP','SPRITE'):(original/name).mkdir(exist_ok=True)
    (original/'FTO_O.EXE').write_text('Folder listing example, not original game data.',encoding='utf-8')
    config=OUT/'config';config.mkdir(exist_ok=True)
    (config/'gtk-3.0').mkdir(exist_ok=True)
    (config/'gtk-3.0/settings.ini').write_text('[Settings]\ngtk-font-name=Malgun Gothic 14\ngtk-icon-theme-name=Adwaita\n',encoding='utf-8')
    (config/'pcmanfm/default').mkdir(parents=True,exist_ok=True)
    (config/'pcmanfm/default/pcmanfm.conf').write_text('[ui]\nwin_width=1180\nwin_height=760\nview_mode=list\nshow_hidden=0\nsort=name;ascending;\n',encoding='utf-8')
    fonts=OUT/'fonts.conf'
    fonts.write_text('<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig><include>/etc/fonts/fonts.conf</include><dir>/mnt/c/Windows/Fonts</dir><cachedir>'+str(OUT/'font-cache')+'</cachedir><alias><family>sans-serif</family><prefer><family>Malgun Gothic</family></prefer></alias></fontconfig>',encoding='utf-8')
    number=next(n for n in range(126,136)if not alive(n)and not Path(f'/tmp/.X{n}-lock').exists())
    env=dict(os.environ,DISPLAY=':'+str(number),GDK_BACKEND='x11',GTK_USE_PORTAL='0',
             FONTCONFIG_FILE=str(fonts),XDG_CONFIG_HOME=str(config),XDG_DATA_HOME=str(OUT/'data'),XDG_CACHE_HOME=str(OUT/'cache'))
    for name in ('WAYLAND_DISPLAY','DBUS_SESSION_BUS_ADDRESS','PULSE_SERVER'):env.pop(name,None)
    xlog=(OUT/'xvfb.log').open('wb');flog=(OUT/'filemanager.log').open('wb')
    xvfb=subprocess.Popen(['Xvfb',env['DISPLAY'],'-screen','0','1280x850x24','-nolisten','tcp','-ac'],stdout=xlog,stderr=xlog)
    manager=None
    try:
        deadline=time.monotonic()+10
        while not alive(number)and time.monotonic()<deadline:
            if xvfb.poll()is not None:raise RuntimeError('Owned virtual display failed')
            time.sleep(.05)
        if not alive(number):raise RuntimeError('Owned virtual display not ready')
        manager=subprocess.Popen(['dbus-run-session','--','pcmanfm','--no-desktop','--new-win',str(base)],env=env,stdout=flog,stderr=flog)
        deadline=time.monotonic()+25;window=''
        while time.monotonic()<deadline:
            result=subprocess.run(['xdotool','search','--onlyvisible','--class','Pcmanfm'],env=env,capture_output=True,text=True)
            if result.returncode==0 and result.stdout.strip():window=result.stdout.strip().splitlines()[-1];break
            time.sleep(.1)
        if not window:raise RuntimeError('Virtual file manager window missing')
        run(['xdotool','windowmove',window,'0','0'],env);run(['xdotool','windowsize',window,'1180','760'],env)
        time.sleep(1)
        shots=[]
        for name,path in [('01-download',base),('02-extracted',base/'FT2-Windows-x64'),('03-original-folder',original)]:
            run(['xdotool','windowfocus',window],env)
            run(['xdotool','key','--window',window,'ctrl+l'],env)
            run(['xdotool','type','--window',window,'--clearmodifiers',str(path)],env)
            run(['xdotool','key','--window',window,'Return'],env)
            time.sleep(.9)
            destination=OUT/(name+'.png')
            subprocess.run(['import','-display',env['DISPLAY'],'-window',window,str(destination)],env=env,check=True,timeout=20)
            shots.append({'file':destination.name,'window_title':run(['xdotool','getwindowname',window],env)})
        report={'capture_kind':'actual-window-screenshots','environment':'Dedicated Linux/WSL Xvfb with PCManFM',
                'display':env['DISPLAY'],'host_desktop_used':False,'original_game_data_used':False,'fixture_folders_only':True,'captures':shots}
        (OUT/'capture_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps(report,ensure_ascii=False))
    finally:
        if manager is not None:
            manager.terminate()
            try:manager.wait(timeout=5)
            except subprocess.TimeoutExpired:manager.kill();manager.wait(timeout=5)
        xvfb.terminate()
        try:xvfb.wait(timeout=5)
        except subprocess.TimeoutExpired:xvfb.kill();xvfb.wait(timeout=5)
        xlog.close();flog.close()


if __name__=='__main__':main()
