"""Source-data APD parser/compiler; extracted from the independently authored port tools."""
from pathlib import Path
import copy, hashlib, re, struct


TOKEN = re.compile(r'@[A-Za-z0-9_.#]+|[A-D](?:\((?:#)?\d+\))?|[HV]*[SPNM]|[HV]+|\d+|[-,\s]+|\([^)]*\)|.',re.DOTALL)

class ExactApd:
    """Header and all tables, including the previously omitted composition table."""
    def __init__(self,path):
        self.raw=Path(path).read_bytes()
        assert self.raw[:4] in [b'3DPA',b'2DPA']
        self.version=int(chr(self.raw[0]))
        self.n_sheets,self.n_parts,self.n_frames,self.n_labels=struct.unpack_from('<4H',self.raw,8)
        self.sheet_names=[self.raw[16+256*i:16+256*(i+1)].split(b'\0',1)[0].decode('latin1') for i in range(self.n_sheets)]
        base=16+256*self.n_sheets;self.parts=[]
        for i in range(self.n_parts):
            off=base+20*i;sheet,flags,x,y,w,h,ox,oy=struct.unpack_from('<BB4H2h',self.raw,off)
            self.parts.append({'index':i,'sheet':sheet,'source_render_byte':flags,'transparent_palette_index':flags,'x':x,'y':y,'w':w,'h':h,'ox':ox,'oy':oy,'raw_record_hex':self.raw[off:off+20].hex()})
        composite_base=base+self.n_parts*20;stride=520 if self.version>=3 else 72;self.composites=[]
        for i in range(self.n_frames):
            off=composite_base+i*stride;a,b,c,count=struct.unpack_from('<4H',self.raw,off)
            assert count<=(stride-8)//2
            parts=list(struct.unpack_from(f'<{count}H',self.raw,off+8));assert all(p<self.n_parts for p in parts)
            self.composites.append({'index':i,'source_offset':off,'source_length':stride,'header_words_raw':[a,b,c,count],
                'part_count':count,'part_indices_in_draw_order':parts,'raw_record_sha256':hashlib.sha256(self.raw[off:off+stride]).hexdigest()})
        label_base=composite_base+self.n_frames*stride;blob_base=label_base+self.n_labels*36;self.labels=[]
        assert blob_base<=len(self.raw)
        for i in range(self.n_labels):
            off=label_base+i*36;name_area=self.raw[off:off+32];name=name_area.split(b'\0',1)[0].decode('latin1');start,length=struct.unpack_from('<2H',self.raw,off+32)
            assert blob_base+start+length<=len(self.raw),(path,name,start,length)
            self.labels.append({'name':name,'aliases':[],'offset':start,'length':length,
                'name_area_hex':name_area.hex(),'script':self.raw[blob_base+start:blob_base+start+length].split(b'\0',1)[0].decode('latin1')})
        self.layout={'source_version':self.version,'sheet_count':self.n_sheets,'part_crop_count':self.n_parts,
            'composite_frame_count':self.n_frames,'label_count':self.n_labels,'part_table_offset':base,
            'composite_table_offset':composite_base,'composite_record_stride':stride,'label_table_offset':label_base,'script_blob_offset':blob_base,
            'label_name_rule':'Only first NUL-terminated CString is an actual label. Remaining32-byte name-area bytes are preserved raw, NOT fabricated aliases.'}

def compile_source(script: str) -> dict:
    tokens = [{'text':m.group(),'offset':m.start()} for m in TOKEN.finditer(script)]
    groups=[];steps=[];ms=200;target=0;mode=None;mcoords=[];range_next=False
    modifier={'marker':0,'event_id':-1,'indirect':0};global_flip=0;local_flip=0;move_flip=0
    references=[];unknown=[]
    def flush(move=(0,0)):
        nonlocal steps,target
        if not steps and groups:
            steps=copy.deepcopy(groups[-1]['steps'])
        raw_count=len(steps);wanted=target or raw_count
        if wanted and not steps:
            raise ValueError('Positive N without any source/previous steps')
        if wanted>4096:raise ValueError('Unreasonable N')
        expanded=[copy.deepcopy(steps[i%raw_count]) for i in range(wanted)] if raw_count else []
        duration=sum(x['duration_ms'] for x in expanded)
        velocity=[struct.unpack('<f',struct.pack('<f',value/duration))[0] if duration else 0 for value in move]
        groups.append({'source_step_count':raw_count,'N_target':target or None,'compiled_step_count':wanted,
            'move_total_xy':list(move),'compiled_sequence_velocity_per_ms':velocity,
            'compiled_velocity_float32_le_hex':[struct.pack('<f',v).hex() for v in velocity],
            'duration_ms':duration,'steps':expanded})
        steps=[];target=0
    def append(frame,mark,offset):
        steps.append({'image_frame':frame,'duration_ms':ms,'draw_flags':global_flip^local_flip,
            'sound_event_id':mark['event_id'],'sound_event_indirect':mark['indirect'],
            'action_marker':mark['marker'],'source_offset':offset})
    for token in tokens:
        t=token['text']
        if t.startswith('@'):
            if steps:flush()
            references.append({'label':t[1:],'source_offset':token['offset'],'group_insertion_index':len(groups)})
            groups.append({'reference_label':t[1:]})
            continue
        if re.fullmatch(r'[HV]*[SPNM]',t):
            mode=t[-1];flip=(1 if 'H' in t[:-1] else 0)|(2 if 'V' in t[:-1] else 0)
            if mode=='P':global_flip=flip
            if mode=='M':mcoords=[];move_flip=flip
            continue
        if re.fullmatch(r'[HV]+',t):
            local_flip=(1 if 'H' in t else 0)|(2 if 'V' in t else 0);continue
        if re.fullmatch(r'[A-D](?:\((?:#)?\d+\))?',t):
            modifier={'marker':ord(t[0])-ord('A')+1,'event_id':-1,'indirect':0}
            if '(' in t:
                value=t[t.index('(')+1:-1];modifier['indirect']=int(value.startswith('#'));modifier['event_id']=int(value.lstrip('#'))
            continue
        if re.fullmatch(r'\((?:#)?\d+\)',t):
            value=t[1:-1];modifier['indirect']=int(value.startswith('#'));modifier['event_id']=int(value.lstrip('#'));continue
        if t.isdigit():
            value=int(t)
            if mode=='S':ms=value
            elif mode=='N':target=value
            elif mode=='P':
                if range_next and steps:
                    last=steps[-1]['image_frame'];direction=1 if value>=last else -1
                    for frame in range(last+direction,value+direction,direction):
                        append(frame,modifier if frame==value else {'marker':0,'event_id':-1,'indirect':0},token['offset'])
                else:append(value,modifier,token['offset'])
            elif mode=='M':
                if range_next:value=-value
                axis=len(mcoords)
                if move_flip & (1<<axis):value=-value
                mcoords.append(value)
                if len(mcoords)==2:flush(tuple(mcoords));mcoords=[]
            else:unknown.append(token)
            range_next=False;modifier={'marker':0,'event_id':-1,'indirect':0};local_flip=0
            continue
        if set(t)<=set('-, \t\r\n'):
            if '-' in t:range_next=True
            continue
        unknown.append(token)
    if steps or target:flush()
    return {'source':script,'tokens':tokens,'groups':groups,'references':references,'unhandled_tokens':unknown,
        'compiler_contract':'40EC40/40F150/40F360/40F4E0/40F8C0; structural execution steps, not observed game action duration'}

def resolve_references(entries:dict):
    def expand(name,stack):
        if name in stack:raise ValueError('APD reference cycle: '+str(stack+[name]))
        entry=entries[name];result=[]
        for g in entry['groups']:
            if 'reference_label' in g:
                ref=g['reference_label']
                if ref not in entries:raise ValueError('Missing label reference '+ref)
                result+=copy.deepcopy(expand(ref,stack+[name]))
            else:result.append(copy.deepcopy(g))
        return result
    for name,e in entries.items():
        e['compiled_groups']=expand(name,[])
        ordinal=0
        for group in e['compiled_groups']:
            for step in group['steps']:step['ordinal']=ordinal;ordinal+=1
        e['compiled_step_count']=ordinal
        e['compiled_schedule_ms']=sum(g['duration_ms'] for g in e['compiled_groups'])
        e['native_observed_action_duration_s']=None
