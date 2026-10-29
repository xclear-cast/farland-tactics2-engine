class_name FT2MidiSequence
extends RefCounted
##41EF40/41F350/41F6F0/41FB40. No native process or saved event output is consulted.
var backend = 1
var format = 0
var division = 0
var tracks: Array = []
var raw = PackedByteArray()
var parsed_events: Array = []
var record_parsed_events = false # Development audit only; looping music stays bounded.
var parsed_event_count = 0
var flags = 0 #EOF1, sticky decode error2, pending pack event4.
var last_tick = 0
var tempo_us = 0
var window_ticks = 0
var tempo_scale = 100
var inject_tempo = 0
var repeat = false
var pending: Dictionary = {}
var fault = ""
var error = ""
var memory_request: Callable
var track_table_allocated = false

static func u32(value: int) -> int: return value&0xffffffff
static func be16(bytes: PackedByteArray,at: int) -> int: return (int(bytes[at])<<8)|int(bytes[at+1])
static func be32(bytes: PackedByteArray,at: int) -> int: return (int(bytes[at])<<24)|(int(bytes[at+1])<<16)|(int(bytes[at+2])<<8)|int(bytes[at+3])
func load_bytes(bytes: PackedByteArray,mode: int = 1) -> int:
	backend = mode
	raw = bytes
	tracks.clear()
	parsed_events.clear()
	parsed_event_count = 0
	flags = 0
	last_tick = 0
	pending.clear()
	error = ""
	fault = ""
	track_table_allocated = false
	if raw.size() < 14 or raw.slice(0,4).get_string_from_ascii() != "MThd": return _load_error("MThd")
	var length = be32(raw,4)
	if length < 6 or length+8 > raw.size(): return _load_error("short_header")
	format = be16(raw,8)
	var count = be16(raw,10)
	division = be16(raw,12)
	if memory_request.is_valid() and not memory_request.call(count*40): return _load_error("track_table_alloc")
	track_table_allocated = true
	var at = 8+length
	for index in range(count):
		if at+8 > raw.size() or raw.slice(at,at+4).get_string_from_ascii() != "MTrk": return _load_error("MTrk")
		var size = be32(raw,at+4)
		at += 8
		# Initial buffer uses exact41F260; later41FA80 accepts any positive short read.
		if (backend == 0 and size > raw.size()-at) or mini(size,1024) > raw.size()-at: return _load_error("short_track")
		if memory_request.is_valid() and not memory_request.call(1024): return _load_error("track_buffer_alloc")
		var track = {"index":index,"start":at,"length":size,"pos":at,"end":at+size,"next_tick":0,"running":0,"finished":size == 0}
		tracks.append(track)
		if size > 0:
			var value = _vlq(track)
			if not value.ok: return _load_error("initial_delta")
			track.next_tick = value.value
		at += size
	return 0
func _load_error(reason: String) -> int:
	error = reason
	track_table_allocated = false
	tracks.clear()
	return 1
func _byte(track: Dictionary) -> int:
	if int(track.pos) >= int(track.end) or int(track.pos) >= raw.size(): return -1
	var value = int(raw[int(track.pos)])
	track.pos = int(track.pos)+1
	return value
func _vlq(track: Dictionary) -> Dictionary:
	var value = 0
	while true:
		var byte = _byte(track)
		if byte < 0: return {"ok":false,"value":0}
		value = u32((value<<7)|(byte&127))
		if (byte&128) == 0: return {"ok":true,"value":value}
	return {"ok":false,"value":0}
func rewind_tracks() -> bool:
	for track in tracks:
		track.pos = track.start
		track.running = 0
		track.finished = int(track.length) == 0
		if not track.finished:
			var value = _vlq(track)
			if not value.ok: return false
			track.next_tick = value.value
	last_tick = 0
	flags = 0
	pending.clear()
	return true
func _decode(track: Dictionary) -> Dictionary:
	var status = _byte(track)
	if status < 0: return {}
	if status < 128:
		track.pos = int(track.pos)-1
		status = int(track.running)
		if status == 0: return {}
	elif status < 0xf0: track.running = status
	var event = {"tick":int(track.next_tick),"status":status,"data1_or_meta_type":0,"data2":0,"length":0,"track":int(track.index)}
	if status < 0xf0:
		var count = 1 if (status&0xf0) in [0xc0,0xd0] else 2
		var a = _byte(track)
		var b = _byte(track) if count == 2 else 0
		if a < 0 or b < 0: return {}
		event.data1_or_meta_type = a
		event.data2 = b
		event.length = count+1
	elif status in [0xf0,0xf7,0xff]:
		if status == 0xff:
			event.data1_or_meta_type = _byte(track)
			if int(event.data1_or_meta_type) < 0: return {}
		var length = _vlq(track)
		if not length.ok or int(length.value) > int(track.end)-int(track.pos) or int(length.value) > raw.size()-int(track.pos): return {}
		event.length = int(length.value)
		if int(length.value) > 0 and memory_request.is_valid() and not memory_request.call(int(length.value)): return {}
		event.payload_hex = raw.slice(int(track.pos),int(track.pos)+int(length.value)).hex_encode()
		track.pos = int(track.pos)+int(length.value)
		if status == 0xff and int(event.data1_or_meta_type) == 0x2f:
			track.finished = true
			return event
	else: return {}
	# Native reads following delta BEFORE returning the current event.
	var next = _vlq(track)
	if not next.ok: return {}
	track.next_tick = u32(int(track.next_tick)+int(next.value))
	return event
func next_event() -> Dictionary:
	var selected = -1
	var minimum = 0xffffffff
	for i in range(tracks.size()):
		var track: Dictionary = tracks[i]
		if not track.finished and int(track.next_tick) < minimum:
			selected = i
			minimum = int(track.next_tick)
	if selected < 0: return {"end":true}
	var event = _decode(tracks[selected])
	if event.is_empty():
		flags |= 2
		error = "event_decode"
		return {"error":true}
	parsed_event_count += 1
	if record_parsed_events: parsed_events.append(event.duplicate())
	return event

func pack_event(event: Dictionary,header: Dictionary) -> int:
	var used = int(header.used)
	if used == 0: header.base = last_tick
	if u32(last_tick-int(header.base)) > window_ticks:
		if int(header.allow) != 0:
			header.allow = 0
			return -104
		header.allow = 1
	var delta = u32(int(event.tick)-last_tick)
	last_tick = int(event.tick)
	var pointer = int(header.offset)+used
	if inject_tempo != 0:
		inject_tempo = 0
		if u32(int(header.capacity)-used) < 12: return -104
		if tempo_us != 0:
			if tempo_scale == 0: fault = "source_zero_scale_DIV"; return -106
			_emit(header,pointer,0,0x1000000|int(u32(tempo_us*100)/tempo_scale))
			pointer += 192 # Dormant original pointer/used mismatch, not repaired.
			used += 12
			header.used = used
	var status = int(event.status)
	var kind = int(event.data1_or_meta_type)
	if status < 0xf0:
		if u32(int(header.capacity)-used) < 12: return -104
		var word = status|(kind<<8)|(int(event.data2)<<16)
		if (status&0xf0) == 0xb0 and kind == 7: word |= 0x40000000
		_emit(header,pointer,delta,word)
	elif status in [0xf0,0xf7]: return 0
	elif kind != 0x51: return -105
	else:
		if u32(int(header.capacity)-used) < 12: return -104
		var payload = str(event.get("payload_hex","")).hex_decode()
		if payload.size() < 3: fault = "source_short_tempo_payload"; return -106
		var tempo = (int(payload[0])<<16)|(int(payload[1])<<8)|int(payload[2])
		if tempo == 0 or tempo_scale == 0:
			fault = "source_zero_tempo_DIV" if tempo == 0 else "source_zero_scale_DIV"
			return -106
		tempo_us = tempo
		_emit(header,pointer,delta,0x1000000|int(u32(tempo*100)/tempo_scale))
		window_ticks = int(u32(division*60000)/tempo)
	header.used = used+12
	return 0
func _emit(header: Dictionary,at: int,delta: int,word: int) -> void:
	var buffer: PackedByteArray = header.buffer
	if buffer.size() < at+12: buffer.resize(at+12)
	buffer.encode_u32(at,u32(delta))
	buffer.encode_u32(at+4,0)
	buffer.encode_u32(at+8,u32(word))
	header.buffer = buffer
func fill(first: bool = false,capacity: int = 1024) -> Dictionary:
	var header = {"offset":0,"capacity":capacity,"used":0,"base":0,"allow":0,"buffer":PackedByteArray()}
	header.buffer.resize(maxi(2048,capacity))
	var code = 0
	if first:
		flags = 0
		pending.clear()
	if (flags&2) != 0: code = -102
	elif (flags&1) != 0:
		if repeat:
			if not rewind_tracks(): code = -101
		else: code = -103
	if code == 0:
		while true:
			var event: Dictionary
			if (flags&4) != 0:
				event = pending
				flags &= ~4
			else:
				event = next_event()
				if event.get("end",false): flags |= 1; break
				if event.get("error",false): code = -101; break
				if int(event.status) == 0xff and int(event.data1_or_meta_type) == 0x2f: continue
			var result = pack_event(event,header)
			if result == -104:
				pending = event
				flags |= 4
				break
			if result == -106: code = result; break
	var bytes: PackedByteArray = header.buffer.slice(0,int(header.used))
	var records: Array = []
	for at in range(0,bytes.size(),12): records.append({"delta":bytes.decode_u32(at),"stream_id":bytes.decode_u32(at+4),"word":bytes.decode_u32(at+8)})
	return {"code":code,"bytes":bytes,"records":records,"header":header}

func standard_events() -> Dictionary:
	# Independent backend0/MCI SMF adapter, not the custom decoder/packer timeline.
	var output: Array = []
	if not format in [0,1,2]: return {"code":1,"events":[]}
	for source in tracks:
		var track = {"pos":int(source.start),"end":int(source.end)}
		var tick = 0
		var running = 0
		var ordinal = 0
		while int(track.pos) < int(track.end):
			var delta = _standard_vlq(track)
			if not delta.ok: return {"code":1,"events":output}
			tick += int(delta.value)
			var status = _byte(track)
			if status < 0: return {"code":1,"events":output}
			if status < 128:
				track.pos = int(track.pos)-1
				status = running
				if running == 0: return {"code":1,"events":output}
			elif status < 0xf0: running = status
			var event = {"tick":tick,"track":int(source.index),"ordinal":ordinal}
			ordinal += 1
			if status < 0xf0:
				var a = _byte(track)
				var b = _byte(track) if not (status&0xf0) in [0xc0,0xd0] else 0
				if a < 0 or b < 0 or a > 127 or b > 127: return {"code":1,"events":output}
				event.kind = "short"
				event.word = status|(a<<8)|(b<<16)
			else:
				if not status in [0xf0,0xf7,0xff]: return {"code":1,"events":output}
				var meta = _byte(track) if status == 0xff else 0
				var length = _standard_vlq(track)
				if meta < 0 or not length.ok or int(length.value) > int(track.end)-int(track.pos): return {"code":1,"events":output}
				var payload = raw.slice(int(track.pos),int(track.pos)+int(length.value))
				track.pos = int(track.pos)+int(length.value)
				if status in [0xf0,0xf7]:
					running = 0
					event.kind = "sysex"
					event.bytes = PackedByteArray([0xf0])+payload if status == 0xf0 else payload
				elif meta == 0x51:
					if payload.size() != 3: return {"code":1,"events":output}
					event.kind = "tempo"
					event.tempo = (int(payload[0])<<16)|(int(payload[1])<<8)|int(payload[2])
				elif meta == 0x2f:
					event.kind = "track_end"
					output.append(event)
					break
				else: continue
			output.append(event)
	output.sort_custom(func(a,b): return a.tick < b.tick if a.tick != b.tick else a.track < b.track if a.track != b.track else a.ordinal < b.ordinal)
	return {"code":0,"events":output}
func _standard_vlq(track: Dictionary) -> Dictionary:
	var value = 0
	for i in range(4):
		var byte = _byte(track)
		if byte < 0: return {"ok":false,"value":0}
		value = (value<<7)|(byte&127)
		if (byte&128) == 0: return {"ok":true,"value":value}
	return {"ok":false,"value":0}
