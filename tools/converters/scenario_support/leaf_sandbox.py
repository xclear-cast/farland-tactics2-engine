"""Bounded, host-independent x86 cinematic conversion sandbox.

Only private Unicorn memory is modified. Every external API call is intercepted;
no original executable is launched, no guest OS exists, and no guest I/O runs.
The API/addresses below describe the supported compatibility ABI, not game data.
"""
from pathlib import Path
import struct
from .core import digest,pe_sections,case_path
from unicorn import Uc,UC_ARCH_X86,UC_MODE_32,UC_HOOK_CODE,UC_HOOK_MEM_WRITE
from unicorn.x86_const import *
EXE_SHA='7437429a63fd5773e152550a59161a1eeefdd3fa3da66cad1d46e232d8097f4c'
HEAP=0x10000000;STACK=0x20000000;STOP=0x30000000
MEM=0x11000000;RES=MEM;LAYERS=MEM+0x50000;QUEUES=MEM+0x51000;PALEFFECT=MEM+0x52000

def i32(value):return (value+0x80000000)%0x100000000-0x80000000

class Oracle:
 def __init__(self,source):
  self.source=Path(source);self.raw=case_path(self.source,'FTO_O.EXE').read_bytes()
  if digest(self.raw)!=EXE_SHA:raise ValueError('Unsupported executable profile')
  pe=struct.unpack_from('<I',self.raw,0x3c)[0];opt=pe+24
  image_base=struct.unpack_from('<I',self.raw,opt+28)[0]
  size=max(0x80000,(struct.unpack_from('<I',self.raw,opt+56)[0]+0xfff)&~0xfff)
  if image_base!=0x400000 or size>0x1000000:raise ValueError('Unexpected PE memory layout')
  self.uc=Uc(UC_ARCH_X86,UC_MODE_32)
  self.uc.mem_map(image_base,size)
  headers=struct.unpack_from('<I',self.raw,opt+60)[0]
  self.uc.mem_write(image_base,self.raw[:headers])
  for section in pe_sections(self.raw)[1]:
   self.uc.mem_write(section['va'],self.raw[section['raw_offset']:section['raw_offset']+section['raw_size']])
  self.uc.mem_map(HEAP,0x100000);self.uc.mem_map(STACK,0x100000);self.uc.mem_map(STOP,0x1000)
  for index,name in enumerate(('RACE.DAT','ITEM.DAT','MAGIC.DAT')):
   raw=case_path(self.source,'DATA/'+name).read_bytes();address=HEAP+index*0x10000
   self.uc.mem_write(address,raw);self.write32(0x44a3a0+index*4,address)
   if name=='ITEM.DAT':self.write32(0x462924,len(raw)//56)
   elif name=='MAGIC.DAT':self.write32(0x462928,len(raw)//64)
   else:self.write32(0x46292c,len(raw)//86)
 def read32(self,address):return struct.unpack('<I',self.uc.mem_read(address,4))[0]
 def write32(self,address,value):self.uc.mem_write(address,struct.pack('<I',value&0xffffffff))
 def call(self,address,*args):
  for register in (UC_X86_REG_EAX,UC_X86_REG_EBX,UC_X86_REG_ECX,UC_X86_REG_EDX,UC_X86_REG_ESI,UC_X86_REG_EDI,UC_X86_REG_EBP):self.uc.reg_write(register,0)
  sp=STACK+0xff000;self.uc.mem_write(sp-0x1000,b'\0'*0x2000)
  self.uc.mem_write(sp,struct.pack('<'+'I'*(len(args)+1),STOP,*(value&0xffffffff for value in args)))
  self.uc.reg_write(UC_X86_REG_ESP,sp);self.uc.reg_write(UC_X86_REG_EFLAGS,2)
  self.uc.emu_start(address,STOP,count=200000)
  if self.uc.reg_read(UC_X86_REG_EIP)!=STOP:raise RuntimeError('Instruction limit exceeded')
  return i32(self.uc.reg_read(UC_X86_REG_EAX))

API = {4328704: ('load_visual_cue', 2), 4329248: ('load_cue_reset_local_epoch', 1), 4326928: ('reset_layer_scene', 1), 4328960: ('release_cue_reset_scene', 1), 4355104: ('palette_fill_playable', 3), 4355184: ('palette_fill_range', 5), 4355280: ('palette_copy_bitmap', 3), 4355344: ('palette_fade_range', 4), 4355456: ('palette_fade_playable', 2), 4355568: ('palette_busy', 0), 4355584: ('palette_wait_pump', 0), 4356048: ('layer_crop', 8), 4356352: ('layer_transparent_index', 2), 4356416: ('layer_visible', 2), 4356512: ('layer_draw_order', 1), 4356640: ('layer_aux_offset', 3), 4356720: ('layer_fill_rect', 6), 4356928: ('layer_clear_drawable', 1), 4357072: ('layer_dither_busy', 1), 4357136: ('layer_dither_pattern', 7), 4357216: ('layer_dither_custom', 8), 4357376: ('layer_dither_start', 2), 4357472: ('layer_dither_set', 6), 4357584: ('layer_motion_busy', 1), 4357648: ('layer_motion', 8), 4357856: ('layer_motion_cycles', 9), 4358144: ('layer_motion_start', 2), 4358864: ('bitmap_queue_create', 4), 4359152: ('bitmap_queue_start', 2), 4359216: ('bitmap_queue_past_first', 1), 4359280: ('bitmap_queue_busy', 1), 4359376: ('bitmap_queue_append', 9), 4359552: ('bitmap_queue_from_list', 11), 4359712: ('bitmap_queue_from_sheet', 9), 4355808: ('palette_band_cycle', 6), 4355632: ('palette_band_busy', 1), 4355776: ('palette_band_stop', 1), 4372208: ('global_epoch_now_plus_offset', 1), 4372256: ('global_elapsed_le_threshold', 1), 4330112: ('local_elapsed_lt_threshold', 1), 4372368: ('wave_release_all', 0), 4372400: ('wave_load_slot', 2), 4372480: ('wave_slot_play_stop', 2), 4372544: ('midi_profile_start_reset_global_epoch', 2), 4372640: ('screen_clip_rect', 4), 4367232: ('render_present', 0), 4366336: ('callback_slots_clear', 0)}
API.update({4390192: ('format_resource_path', 2), 4365376: ('APD_resource_load_remap', 4), 4365728: ('APD_instance_create', 5), 4365920: ('APD_instance_play_label', 3), 4366016: ('APD_resource_palette_restore', 1), 4355008: ('palette_set_entry_RGB', 4), 4365152: ('credits_scroll_start', 3), 4366368: ('layer_callback_surface_create', 7)})
API.update({4365040: ('credits_scroll_busy', 0), 4365056: ('credits_scroll_enable', 0), 4365120: ('credits_group_destroy', 0), 4362880: ('text_group_children_busy', 1), 4366880: ('photo_move_palette_envelope', 10), 4231072: ('wave_play_path', 3)})

class SceneOracle(Oracle):

    def __init__(self, source):
        super().__init__(source)
        assert digest(self.raw) == EXE_SHA
        self.uc.mem_map(MEM, 2097152)
        self.now = 1000
        self.api_trace = []
        self.write32(4501864, RES)
        self.write32(4501860, LAYERS)
        self.write32(4501868, QUEUES)
        self.write32(4501900, PALEFFECT)
        self.write32(4642552, HEAP + 987136)
        self.uc.hook_add(UC_HOOK_CODE, self.clock, begin=HEAP + 987136, end=HEAP + 987136)
        for iat, addr, name, n in [(4642400, HEAP + 987152, 'SetRect', 5), (4642392, HEAP + 987168, 'CopyRect', 2), (4642372, HEAP + 987184, 'IntersectRect', 3), (4642192, HEAP + 987200, 'SetRectEmpty', 1), (4642396, HEAP + 987216, 'OffsetRect', 3)]:
            self.write32(iat, addr)
            self.uc.hook_add(UC_HOOK_CODE, self.rect_api, begin=addr, end=addr, user_data=(name, n))
        for i in range(10):
            p = LAYERS + 200 * i
            self.write_rect(p + 144, (0, 0, 640, 480))
            self.write_rect(p + 160, (0, 0, 640, 480))
            self.uc.mem_write(p + 180, struct.pack('<3H', 65535, i, 65535))
            self.uc.mem_write(p + 198, b'\x01')

    def finish(self, uc, result, stdcall_args=0):
        sp = uc.reg_read(UC_X86_REG_ESP)
        ret = self.read32(sp)
        uc.reg_write(UC_X86_REG_EAX, result & 4294967295)
        uc.reg_write(UC_X86_REG_ESP, sp + 4 + 4 * stdcall_args)
        uc.reg_write(UC_X86_REG_EIP, ret)

    def clock(self, uc, address, size, userdata):
        self.finish(uc, self.now)

    def rect(self, address):
        return list(struct.unpack('<4i', self.uc.mem_read(address, 16)))

    def write_rect(self, address, r):
        self.uc.mem_write(address, struct.pack('<4i', *r))

    def rect_api(self, uc, address, size, userdata):
        name, n = userdata
        sp = uc.reg_read(UC_X86_REG_ESP)
        a = list(struct.unpack('<' + 'I' * n, uc.mem_read(sp + 4, 4 * n)))
        result = 1
        if name == 'SetRect':
            self.write_rect(a[0], [i32(v) for v in a[1:]])
        elif name == 'CopyRect':
            self.write_rect(a[0], self.rect(a[1]))
        elif name == 'SetRectEmpty':
            self.write_rect(a[0], (0, 0, 0, 0))
        elif name == 'OffsetRect':
            self.write_rect(a[0], [i32(v + i32(a[1 + j % 2])) for j, v in enumerate(self.rect(a[0]))])
        else:
            x, y = (self.rect(a[1]), self.rect(a[2]))
            r = [max(x[0], y[0]), max(x[1], y[1]), min(x[2], y[2]), min(x[3], y[3])]
            result = int(r[0] < r[2] and r[1] < r[3])
            self.write_rect(a[0], r if result else (0, 0, 0, 0))
        self.finish(uc, result, n)

class ProgramOracle(SceneOracle):

    def __init__(self, source):
        super().__init__(source)
        self.commands = []
        self.answers = {}
        self.querytrace = []
        self.path_cursor = 0
        self._pending_api = None
        self.uc.hook_add(UC_HOOK_CODE, self.intercept_code)

    def intercept_code(self, uc, address, size, data):
        if address in API or address == self._pending_api:
            self._pending_api = None
            self.api(uc, address, size, data)
            return
        if 4328560 <= address < 4354144 and size == 5:
            code = bytes(uc.mem_read(address, 5))
            if code[0] == 232:
                target = address + 5 + struct.unpack_from('<i', code, 1)[0]
                if target >= 4354048 and target != 4468640:
                    self._pending_api = target

    def array(self, p, limit=256):
        out = []
        for i in range(limit):
            v = i32(self.read32(p + i * 4))
            if v == -1:
                return out
            out.append(v)
        return {'unterminated_up_to': out}

    def cstring(self, p):
        return bytes(self.uc.mem_read(p, 512)).split(b'\x00')[0].decode('cp949')

    def api(self, uc, address, size, data):
        sp = uc.reg_read(UC_X86_REG_ESP)
        ret = self.read32(sp)
        known = address in API
        name, n = API.get(address, ('ABI_UNRESOLVED', 12))
        args = list(struct.unpack('<' + 'i' * n, uc.mem_read(sp + 4, 4 * n))) if n else []
        r = {'call_va': hex(ret - 5), 'API': hex(address), 'operation': name, 'args': args, 'typed': known}
        if address == 4356512:
            r['draw_order'] = self.array(args[0])
        if address == 4359552:
            r['bitmap_ids'] = self.array(args[10])
        if address == 4357216 and args[7] > 0:
            r['masks'] = list(struct.unpack('<' + 'H' * min(args[7], 16), uc.mem_read(args[6], min(args[7], 16) * 2)))
        result_override = None
        if address == 4390192:
            fmt = self.cstring(self.read32(4503720 + 4 * args[0]))
            r['format_template'] = fmt
            if fmt.count('%s') == 1 and fmt.count('%') == 1:
                r['format_string_argument'] = self.cstring(args[1])
                path = fmt % r['format_string_argument']
                r['relative_path'] = path
                result_override = MEM + 1769472 + self.path_cursor * 512
                self.path_cursor += 1
                self.uc.mem_write(result_override, path.encode('cp949') + b'\x00')
            else:
                r['warning'] = 'Additional varargs format notnormalized; preserveCtemplateandactualcaller'
                r['typed'] = False
        if address in (4365376, 4365920):
            r['string_argument'] = self.cstring(args[1])
        if address == 4366368:
            r['bitmap_path'] = self.cstring(args[4])
            r['callbacks'] = {'initialize': hex(args[1]), 'update': hex(args[2]), 'draw': hex(args[3])}
        if not known:
            r['warning'] = 'ABI unknown;12rawstackDWORDs are evidence, not12formalarguments'
        self.commands.append(r)
        value = result_override if result_override is not None else self.answers.get(address, 0 if 'busy' in name or 'threshold' in name else 1)
        self.querytrace.append((address, args, value))
        self.finish(uc, value)

class GraphOracle(ProgramOracle):

    def __init__(self, source):
        super().__init__(source)
        self.choices = []
        self.predicates = []
        self.writes = []
        self.events = []
        self.uc.hook_add(UC_HOOK_MEM_WRITE, self.write_watch, begin=4500992, end=4501824)

    def write_watch(self, uc, access, address, size, value, data):
        r = {'address': hex(address), 'size': size, 'value': value & (1 << size * 8) - 1}
        self.writes.append(r)
        self.events.append({'write_scalar': r})

    def api(self, uc, address, size, data):
        if address in QUERY:
            n = API[address][1]
            sp = uc.reg_read(UC_X86_REG_ESP)
            a = list(struct.unpack('<' + 'i' * n, uc.mem_read(sp + 4, n * 4))) if n else []
            index = len(self.predicates)
            v = self.choices[index] if index < len(self.choices) else 0
            self.answers[address] = v
            self.predicates.append({'call_va': hex(self.read32(sp) - 5), 'operation': API[address][0], 'args': a, 'value': v})
        super().api(uc, address, size, data)
        r = self.commands[-1].copy()
        if address in QUERY:
            r['observed_predicate_value'] = self.predicates[-1]['value']
        self.events.append({'engine_call': r})

QUERY={address for address,(name,_) in API.items()if "busy" in name or "threshold" in name or name=="bitmap_queue_past_first"}
