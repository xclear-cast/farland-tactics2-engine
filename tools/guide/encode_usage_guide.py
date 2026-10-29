"""Encode the self-authored setup tutorial frames as MP4."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

ROOT=Path(__file__).resolve().parents[2]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg',default='ffmpeg')
    parser.add_argument('--frames',type=Path,default=ROOT/'private/usage_guide/frames')
    parser.add_argument('--output',type=Path,default=ROOT/'docs')
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    frames=sorted(args.frames.glob('frame_*.png'))
    if len(frames)!=112:raise ValueError('Expected the complete 112-frame instructional sequence')
    source=str(args.frames/'frame_%04d.png')
    common=[args.ffmpeg,'-y','-loglevel','error','-framerate','4','-i',source]
    subprocess.run([*common,'-vf','fps=12,format=yuv420p','-c:v','libx264','-preset','medium','-crf','20','-movflags','+faststart',str(args.output/'usage-guide.mp4')],check=True)
    rows=[]
    for name in ('usage-guide.mp4',):
        path=args.output/name
        rows.append({'path':'docs/'+name,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    report={'schema':1,'seconds':28,'resolution':[960,720],'instructional_example':True,'actual_setup_ui_used':True,
            'original_game_data_used':False,'original_game_screenshots_used':False,'private_paths_displayed':False,
            'font_binary_included':False,'conversion_timing':'Shortened illustration; real initial preparation may take several minutes',
            'chapters':['Unzip the whole package into a separate folder','Open the Windows or Mac start file',
                        'Choose the original game folder','Identify DATA/MAP/SPRITE/FTO_O.EXE in its parent folder',
                        'Click prepare and wait','Click connect and launch','Reopen setup when changing folders or mods'],
            'files':rows}
    (args.output/'usage-guide.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report))


if __name__=='__main__':main()
