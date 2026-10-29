"""Turn actual, private window captures into a red-box tutorial slideshow.

Inputs are never changed. Cropping and privacy masks happen only in the video
filter graph. Output defaults to private/; promotion into docs is a separate step.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

ROOT=Path(__file__).resolve().parents[2]


def sha(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def quoted_path(path):
    value=Path(path).resolve().as_posix().replace(':',r'\:')
    if "'"in value:raise ValueError('Use a render work directory/font path without apostrophes')
    return "'"+value+"'"


def run(command,log):
    result=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
    log.write_text(result.stdout+result.stderr,encoding='utf-8')
    if result.returncode:raise RuntimeError('Video encoding failed; inspect '+str(log))


def image_size(ffprobe,path):
    raw=subprocess.check_output([ffprobe,'-v','error','-select_streams','v:0','-show_entries','stream=width,height','-of','json',str(path)],text=True,encoding='utf-8')
    record=json.loads(raw)['streams'][0];return int(record['width']),int(record['height'])


def rectangle(values,width,height,offset=(0,0)):
    if len(values)!=4:raise ValueError('Rectangle must contain x,y,width,height')
    x,y,w,h=map(int,values);x-=offset[0];y-=offset[1]
    if w<=0 or h<=0:raise ValueError('Rectangle has no area')
    right,bottom=min(width,x+w),min(height,y+h);x,y=max(0,x),max(0,y)
    return (x,y,right-x,bottom-y)if right>x and bottom>y else None


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest',type=Path,required=True)
    parser.add_argument('--font',type=Path,required=True)
    parser.add_argument('--ffmpeg',default='ffmpeg')
    parser.add_argument('--ffprobe',default='ffprobe')
    parser.add_argument('--output',type=Path,default=ROOT/'private/folder_guide/rendered')
    parser.add_argument('--prefix',default='folder-guide-windows')
    args=parser.parse_args()
    manifest_path=args.manifest.resolve();manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    if manifest.get('capture_kind')!='actual-window-screenshots':raise ValueError('This renderer accepts actual screenshot manifests only')
    capture_root=Path(manifest['capture_root'])
    if not capture_root.is_absolute():capture_root=manifest_path.parent/capture_root
    capture_root=capture_root.resolve();out=args.output.resolve()
    if out==capture_root or out.is_relative_to(capture_root):raise ValueError('Render output must be outside the original capture folder')
    out.mkdir(parents=True,exist_ok=True)
    width,height=map(int,manifest.get('canvas',[1280,800]));caption_height=int(manifest.get('caption_height',72))
    if width%2 or height%2 or caption_height<48:raise ValueError('Use even canvas dimensions and at least48px caption height')
    if not args.font.is_file():raise ValueError('Korean font input is missing')
    if not manifest.get('frames'):raise ValueError('No actual screenshots supplied')
    segment_paths=[];provenance=[];seconds=0.0
    for index,frame in enumerate(manifest['frames'],1):
        source=(capture_root/frame['file']).resolve()
        if not source.is_relative_to(capture_root)or source.is_symlink()or not source.is_file():raise ValueError('Unsafe or missing capture')
        if source.suffix.lower()not in ('.png','.jpg','.jpeg'):raise ValueError('Expected an original PNG/JPEG screenshot')
        original_sha=sha(source);sw,sh=image_size(args.ffprobe,source)
        crop=tuple(map(int,frame.get('crop',[0,0,sw,sh])))
        if len(crop)!=4 or crop[0]<0 or crop[1]<0 or crop[2]<=0 or crop[3]<=0 or crop[0]+crop[2]>sw or crop[1]+crop[3]>sh:
            raise ValueError('Crop is outside the original screenshot')
        cw,ch=crop[2:];filters=[f'crop={cw}:{ch}:{crop[0]}:{crop[1]}']
        for masked in frame.get('masks',[]):
            box=rectangle(masked, cw,ch,crop[:2])
            if box:filters.append('drawbox=x=%d:y=%d:w=%d:h=%d:color=0xeeeeee:t=fill'%box)
        boxes=[]
        for requested in frame.get('boxes',[]):
            box=rectangle(requested,cw,ch,crop[:2])
            if box:
                filters.append('drawbox=x=%d:y=%d:w=%d:h=%d:color=red:t=5'%box);boxes.append(list(requested))
        available=height-caption_height
        filters += [f'scale={width}:{available}:force_original_aspect_ratio=decrease',
                    f'pad={width}:{height}:(ow-iw)/2:0:color=0x202020',
                    f'drawbox=x=0:y={available}:w={width}:h={caption_height}:color=0x101010:t=fill']
        caption=str(frame.get('caption','')).replace('\n',' ').strip()
        if not caption:raise ValueError('Each step needs one short Korean caption')
        text=out/f'caption_{index:02d}.txt';text.write_text(f'{index}. {caption}',encoding='utf-8')
        font_size=int(manifest.get('caption_font_size',28))
        filters.append(f'drawtext=fontfile={quoted_path(args.font)}:textfile={quoted_path(text)}:expansion=none:fontcolor=white:fontsize={font_size}:x=24:y={available}+(h-{available}-text_h)/2')
        graph=out/f'filter_{index:02d}.txt';graph.write_text(','.join(filters),encoding='utf-8')
        duration=float(frame.get('seconds',3.5))
        if duration<1 or duration>20:raise ValueError('Use readable1–20second screenshot durations')
        segment=out/f'segment_{index:02d}.mp4'
        run([args.ffmpeg,'-y','-loglevel','error','-loop','1','-framerate','10','-i',str(source),'-t',str(duration),
             '-filter_script:v',str(graph),'-an','-map_metadata','-1','-c:v','libx264','-preset','medium','-crf','18','-pix_fmt','yuv420p',str(segment)],out/f'encode_{index:02d}.log')
        preview=out/f'preview_{index:02d}.png'
        run([args.ffmpeg,'-y','-loglevel','error','-i',str(segment),'-frames:v','1',str(preview)],out/f'preview_{index:02d}.log')
        if sha(source)!=original_sha:raise RuntimeError('Original capture changed during rendering')
        segment_paths.append(segment);seconds+=duration
        provenance.append({'step':index,'capture_name':source.name,'source_sha256':original_sha,'source_dimensions':[sw,sh],
                           'crop':list(crop),'masks':frame.get('masks',[]),'red_boxes':boxes,'seconds':duration,'caption':caption})
    listing=out/'segments.txt'
    listing.write_text(''.join("file '"+path.as_posix()+"'\n"for path in segment_paths),encoding='utf-8')
    mp4=out/(args.prefix+'.mp4');gif=out/(args.prefix+'.gif')
    run([args.ffmpeg,'-y','-loglevel','error','-f','concat','-safe','0','-i',str(listing),'-map_metadata','-1','-c','copy','-movflags','+faststart',str(mp4)],out/'concat.log')
    run([args.ffmpeg,'-y','-loglevel','error','-i',str(mp4),'-vf',
         'fps=3,split[s0][s1];[s0]palettegen=max_colors=192:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=4',
         '-map_metadata','-1','-loop','0',str(gif)],out/'gif.log')
    report={'schema':1,'capture_kind':'actual-window-screenshots','seconds':seconds,'canvas':[width,height],
            'source_captures_modified':False,'screenshots_cropped_and_privacy_masked':True,
            'game_art_or_game_data_shown':False,'privacy_reviewed':bool(manifest.get('privacy_reviewed',False)),'steps':provenance,
            'files':[{'name':p.name,'bytes':p.stat().st_size,'sha256':sha(p)}for p in (gif,mp4)]}
    (out/(args.prefix+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({key:value for key,value in report.items()if key!='steps'},ensure_ascii=False))


if __name__=='__main__':main()
