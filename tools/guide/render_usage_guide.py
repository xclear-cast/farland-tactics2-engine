"""Record a synthetic setup tutorial in an owned private WSL X display.

This script never opens the host GUI or reads an original game installation.
Run on Linux/WSL; the font is a user-supplied input and is never copied out.
"""
from pathlib import Path
import argparse
import json
import os
import socket
import subprocess
import time

ROOT=Path(__file__).resolve().parents[2]


def alive(number):
    for address in ('\0/tmp/.X11-unix/X'+str(number),'/tmp/.X11-unix/X'+str(number)):
        with socket.socket(socket.AF_UNIX)as client:
            try:client.connect(address);return True
            except OSError:pass
    return False


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',type=Path,required=True)
    parser.add_argument('--font',type=Path,required=True)
    parser.add_argument('--output',type=Path,default=ROOT/'private/usage_guide')
    args=parser.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    number=next(n for n in range(120,130)if not alive(n)and not Path(f'/tmp/.X{n}-lock').exists())
    log=(out/'xvfb.log').open('wb')
    server=subprocess.Popen(['Xvfb',':'+str(number),'-screen','0','1200x900x24','-nolisten','tcp','-ac'],stdout=log,stderr=subprocess.STDOUT)
    try:
        deadline=time.monotonic()+10
        while not alive(number)and time.monotonic()<deadline:
            if server.poll()is not None:raise RuntimeError('Owned tutorial Xvfb stopped')
            time.sleep(.05)
        if not alive(number):raise TimeoutError('Tutorial Xvfb not ready')
        env=dict(os.environ,DISPLAY=':'+str(number),GODOT_SILENCE_ROOT_WARNING='1',LIBGL_ALWAYS_SOFTWARE='1',LP_NUM_THREADS='2',SDL_VIDEODRIVER='x11')
        env.pop('WAYLAND_DISPLAY',None);env.pop('PULSE_SERVER',None)
        frames=out/'frames'
        command=[str(args.godot),'--path',str(ROOT/'game'),'--display-driver','x11','--audio-driver','Dummy','--resolution','960x720','--position','0,0',
                 '--script',str(ROOT/'tools/guide/render_usage_guide.gd'),'--',f'--font={args.font.resolve()}',f'--output={frames}']
        result=subprocess.run(command,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=60)
        output=result.stdout+result.stderr;(out/'godot.log').write_text(output,encoding='utf-8')
        errors=[line for line in output.splitlines()if line.startswith(('ERROR:','SCRIPT ERROR:'))]
        if result.returncode or errors:raise RuntimeError(output[-5000:])
        report={'passed':True,'frames':len(list(frames.glob('frame_*.png'))),'seconds':28,'fps':4,'display':':'+str(number),
                'host_windows_opened':False,'original_game_data_used':False,'instructional_example':True}
        (out/'render.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report))
    finally:
        if server.poll()is None:
            server.terminate()
            try:server.wait(timeout=5)
            except subprocess.TimeoutExpired:server.kill();server.wait(timeout=5)
        log.close()


if __name__=='__main__':main()
