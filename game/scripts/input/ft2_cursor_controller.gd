extends RefCounted
## Window-cursor state/bitmaps only. No Input/DisplayServer/mouse-warp side effects.
signal cursor_requested(request: Dictionary)
const RESOURCE_IDS = [102,105,132,141,148,149,161]
const SYSTEM_PATHS = {32512:"res://assets/cursors/system_cursor_32512.bin",32513:"res://assets/cursors/system_cursor_32513.bin",32514:"res://assets/cursors/system_cursor_32514.bin",32515:"res://assets/cursors/system_cursor_32515.bin"}
const WAIT_FRAMES = [132,141]
var data
var resource_id = 102
var message_index = 0 #44B9C8, persists across430750 openings.
var event_index = 0 #44C380, independent EVENT input-wait cursor.
var message_wait = false
var event_wait = false
var event_input_wait = false #462158 latch; may survive a deadline timer stop.
var _message_epoch = 0
var _event_epoch = 0
var _resources: Dictionary = {}
var failures: Array = []
var trace: Array = []
var trace_enabled = false

func configure(source_data) -> void: data = source_data

func resource(id: int) -> Dictionary:
	if _resources.has(id): return _resources[id]
	if id in [0,32641]:
		# Native Win95 LoadCursor(NULL,32641)==NULL; its SetCursor(NULL) hides.
		# The empty Image is a window-local Godot carrier, not an invented bitmap.
		var and_bits=PackedByteArray();and_bits.resize(1024);and_bits.fill(1)
		var zeros=PackedByteArray();zeros.resize(4096);var xor_bits=PackedByteArray();xor_bits.resize(1024)
		var hidden={"resource_id":id,"child_id":-1,"hotspot":Vector2i.ZERO,"size":Vector2i(32,32),"rgba":zeros,"inverse_rgba":zeros.duplicate(),"and_bits":and_bits,"xor_bits":xor_bits,"counts":{"black":0,"white":0,"transparent":1024,"invert":0},"needs_screen_xor":false,"native_null":true}
		_resources[id]=hidden;return hidden
	var child = -1
	var raw=PackedByteArray()
	if SYSTEM_PATHS.has(id):raw=FT2Content.bytes(str(SYSTEM_PATHS[id]))
	else:
		var path = data.resolve("data/port_ready/ui/FTO_O/group_cursor_%d_lang1042.bin" % id)
		if not FT2Content.exists(path): failures.append({"missing_group":id}); return {}
		var group = FT2Content.bytes(path)
		if group.size()!=20 or group.decode_u16(2)!=2 or group.decode_u16(4)!=1: failures.append({"invalid_group":id}); return {}
		child = group.decode_u16(18)
		raw=FT2Content.bytes(data.resolve("data/port_ready/ui/FTO_O/cursor_%d_lang1042.bin" % child))
	if raw.size()<52 or raw.decode_u32(4)!=40 or raw.decode_u16(18)!=1 or raw.decode_u32(20)!=0: failures.append({"unsupported_cursor":id}); return {}
	var width = raw.decode_s32(8)
	var height: int = absi(raw.decode_s32(12))/2
	var pitch: int = ((width+31)/32)*4
	var start = 4+int(raw.decode_u32(4))+8
	if width!=32 or height!=32 or raw.size()!=start+pitch*height*2: failures.append({"invalid_dimensions":id}); return {}
	var and_bits = PackedByteArray();var xor_bits = PackedByteArray();var rgba = PackedByteArray();var inverse = PackedByteArray()
	and_bits.resize(width*height);xor_bits.resize(width*height);rgba.resize(width*height*4);inverse.resize(width*height*4)
	var counts = {"black":0,"white":0,"transparent":0,"invert":0}
	for y in range(height):
		var row = height-1-y
		for x in range(width):
			var bit = 7-x%8;var offset = row*pitch+x/8;var index = y*width+x
			var xor_bit = (raw[start+offset]>>bit)&1
			var and_bit = (raw[start+height*pitch+offset]>>bit)&1
			and_bits[index]=and_bit;xor_bits[index]=xor_bit
			if and_bit == 0:
				for channel in range(3): rgba[index*4+channel]=raw[44+xor_bit*4+2-channel]
				rgba[index*4+3]=255
				counts["black" if xor_bit==0 else "white"] += 1
			elif xor_bit == 1:
				for channel in range(4):inverse[index*4+channel]=255
				counts.invert += 1
			else: counts.transparent += 1
	var result = {"resource_id":id,"child_id":child,"hotspot":Vector2i(raw.decode_u16(0),raw.decode_u16(2)),"size":Vector2i(width,height),"rgba":rgba,"inverse_rgba":inverse,"and_bits":and_bits,"xor_bits":xor_bits,"counts":counts,"needs_screen_xor":int(counts.invert)>0}
	_resources[id]=result
	return result

func hardware_image(id: int) -> Image:
	var cursor = resource(id)
	# An inverse cursor cannot be encoded as ordinary RGBA. Never make it black.
	if cursor.is_empty() or cursor.needs_screen_xor:return null
	return Image.create_from_data(cursor.size.x,cursor.size.y,false,Image.FORMAT_RGBA8,cursor.rgba)

func descriptor(id: int) -> Dictionary:
	var cursor = resource(id)
	if cursor.is_empty():return {}
	return {"kind":"hidden" if cursor.get("native_null",false) else "system_resource" if SYSTEM_PATHS.has(id) else "resource","resource_id":id,"hotspot":cursor.hotspot,"size":cursor.size,"path":"software_xor" if cursor.needs_screen_xor else "hardware_transparent" if cursor.get("native_null",false) else "hardware_rgba","inverse_pixels":cursor.counts.invert,"native_null":cursor.get("native_null",false)}

func request_system(id: int) -> Dictionary:
	if id not in [0,32641] and not SYSTEM_PATHS.has(id):failures.append({"uncaptured_system_cursor":id});return {}
	return request_resource(id)

func request_resource(id: int) -> Dictionary:
	var request = descriptor(id)
	if request.is_empty():return {}
	resource_id=id
	if trace_enabled:
		trace.append(request.duplicate())
		if trace.size()>2000:trace.pop_front()
	cursor_requested.emit(request)
	return request

func map_motion(substate: int,dragging: bool,control_held: bool) -> Dictionary:
	if substate not in [0,1,2,3,4]:return {}
	return request_resource(105 if substate in [0,1,3] and (dragging or control_held) else 102)

func begin_message_wait(now: int) -> void:
	message_wait=true;_message_epoch=now
	#430750 installs timer100/600ms, but does not reset44B9C8 or set a cursor.

func end_message_wait() -> Dictionary:
	message_wait=false
	return request_resource(102) #4308ED always restores resource102.

func begin_event_wait(now: int) -> Dictionary:
	event_wait=true;event_input_wait=true;_event_epoch=now
	return request_resource(132) #43EEBD, immediate initial frame;44C380 is not reset.

func end_event_wait(input_wait_preserved: bool = false) -> Dictionary:
	event_wait=false;event_input_wait=input_wait_preserved
	return request_system(32641)

func timer_event(timer_id: int,inside_client: bool,foreground_main: bool = true) -> Dictionary:
	if timer_id==100:
		var cursor = {}
		if inside_client:cursor=request_resource(int(WAIT_FRAMES[message_index]));message_index+=1
		if message_index>=2:message_index=0
		return cursor
	if timer_id==400:
		if not event_input_wait or not foreground_main:return {}
		var cursor = {}
		if inside_client:cursor=request_resource(int(WAIT_FRAMES[event_index]));event_index+=1
		if event_index>=2:event_index=0
		return cursor
	return {}

func advance(now: int,inside_client: bool,foreground_main: bool = true) -> Array:
	# One delivered timer event per update. No claim of native wall-clock cadence.
	var requests: Array=[]
	if message_wait and ((now-_message_epoch)&0xFFFFFFFF)>=600:
		_message_epoch=now;var request=timer_event(100,inside_client)
		if not request.is_empty():requests.append(request)
	if event_wait and ((now-_event_epoch)&0xFFFFFFFF)>=600:
		_event_epoch=now;var request=timer_event(400,inside_client,foreground_main)
		if not request.is_empty():requests.append(request)
	return requests

func composite_rgb(id: int,background: Image,pointer: Vector2i) -> Image:
	# Separate cursor QA/software reference: never changes game/framebuffer bytes.
	var cursor=resource(id);var out=background.duplicate();out.convert(Image.FORMAT_RGB8)
	if cursor.is_empty():return out
	var bytes=out.get_data();var origin=pointer-Vector2i(cursor.hotspot)
	for y in range(cursor.size.y):
		for x in range(cursor.size.x):
			var destination=origin+Vector2i(x,y)
			if destination.x<0 or destination.y<0 or destination.x>=out.get_width() or destination.y>=out.get_height():continue
			var index=y*cursor.size.x+x;var offset=(destination.y*out.get_width()+destination.x)*3
			for channel in range(3):bytes[offset+channel]=(bytes[offset+channel] if cursor.and_bits[index]!=0 else 0)^(255 if cursor.xor_bits[index]!=0 else 0)
	return Image.create_from_data(out.get_width(),out.get_height(),false,Image.FORMAT_RGB8,bytes)

func snapshot() -> Dictionary:
	return {"resource_id":resource_id,"message_index":message_index,"event_index":event_index,"message_wait":message_wait,"event_wait":event_wait,"event_input_wait":event_input_wait,"failures":failures.duplicate(true),"scope":"Window cursor only; no game RNG, unit state, framebuffer or host mouse mutation"}
