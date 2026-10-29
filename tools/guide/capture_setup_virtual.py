"""Capture the real setup scene and file chooser in an owned virtual display."""
from pathlib import Path
import os
import subprocess
import time
from capture_virtual_folders import alive

ROOT=Path(__file__).resolve().parents[2]


def main():
    out=ROOT/'private/folder_guide/virtual';out.mkdir(parents=True,exist_ok=True)
    number=next(n for n in range(126,136)if not alive(n)and not Path(f'/tmp/.X{n}-lock').exists())
    log=(out/'app-xvfb.log').open('wb')
    server=subprocess.Popen(['Xvfb',':'+str(number),'-screen','0','1100x850x24','-nolisten','tcp','-ac'],stdout=log,stderr=log)
    try:
        deadline=time.monotonic()+10
        while not alive(number)and time.monotonic()<deadline:
            if server.poll()is not None:raise RuntimeError('Owned virtual display stopped')
            time.sleep(.05)
        if not alive(number):raise RuntimeError('Owned virtual display not ready')
        env=dict(os.environ,DISPLAY=':'+str(number),GODOT_SILENCE_ROOT_WARNING='1',LIBGL_ALWAYS_SOFTWARE='1',LP_NUM_THREADS='2',
                 SDL_VIDEODRIVER='x11',FONTCONFIG_FILE=str(out/'fonts.conf'),XDG_CONFIG_HOME=str(out/'config'),XDG_DATA_HOME=str(out/'data'))
        for name in ('WAYLAND_DISPLAY','PULSE_SERVER'):env.pop(name,None)
        dist=ROOT/'dist/FT2-External-Engine'
        command=[str(dist/'FT2-External-linux.x86_64'),'--display-driver','x11','--audio-driver','Dummy','--path',str(dist),
                 '--main-pack',str(dist/'FT2-External.pck'),'--script',str(ROOT/'tools/guide/capture_setup_windows.gd'),'--','--setup',
                 f'--engine-config={out/"tutorial_connection.json"}',f'--capture-output={out}',
                 '--fixture-folder=/tmp/FT2-Guide/MyGames/FT2-Original']
        result=subprocess.run(command,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=50)
        text=result.stdout+result.stderr;(out/'app-capture.log').write_text(text,encoding='utf-8')
        if result.returncode or any(line.startswith(('ERROR:','SCRIPT ERROR:'))for line in text.splitlines()):raise RuntimeError(text[-5000:])
        print((out/'setup_capture.json').read_text(encoding='utf-8'))
    finally:
        server.terminate()
        try:server.wait(timeout=5)
        except subprocess.TimeoutExpired:server.kill();server.wait(timeout=5)
        log.close()


if __name__=='__main__':main()
