class_name FT2MidiTransport
extends RefCounted
## Source stream protocol and sample timeline. Synthesizer/endpoint is an adapter.
const Sequence = preload("ft2_midi_sequence.gd")
var backend = 1
var file_loader: Callable
var sequence
var ready = 0
var handle = 0
var event_handle = 0
var window_handle = 0x515
var playing = 0
var paused = 0
var prepared = 0
var stop_state = 0
var completed = 0
var ring_index = 0
var eof_seen = 0
var headers: Array = []
var queued: Array = []
var channel_volumes: Array = []
var fade_scale = 1000
var fade_delta = 0
var aux_current = 65535
var aux_target = 65535
var current_index = -1
var normal_started = 0
var current_file = ""
var repeat = false
var epoch = 0
var api_feedback: Dictionary = {}
var callback_fill_feedback: Dictionary = {}
var auto_complete_stop = true
var timer_minimum_ms = 10 # Explicit host timer adapter, not a Win95 cadence assertion.
var audit = false
var trace: Array = []
var errors: Array = []
var posts: Array = []
var allocation_count = 0
var _out_events: Array = []
var _notices: Array = []
var _timer_period = 0
var _timer_next = 0
var _timer_active = false
var _now = 0
var _standard: Array = []
var _standard_index = 0
var _standard_last_tick = 0
var _mci_ended = false
var _header_position = 0
var _next: Dictionary = {}
var _due_frame = 0
var _frame_cursor = 0
var _time_floor = 0
var _time_remainder = 0
var _tempo = 500000
var _rate = 44100

func configure(loader: Callable,mode: int = 1) -> int:
	file_loader = loader
	backend = mode
	sequence = Sequence.new()
	channel_volumes.resize(16)
	channel_volumes.fill(100)
	return initialize()
func _record(name: String,values: Variant = null) -> void:
	trace.append({"name":name,"values":values})
	if not audit and trace.size() > 256: trace.pop_front()
func _api(name: String,values: Variant = null) -> int:
	_record(name,values)
	return int(api_feedback.get(name,0))
func initialize() -> int:
	ready = 0
	if backend == 1:
		if _api("midiStreamOpen",{"device_id":0,"callback":"431400","flags":0x30000}) != 0: handle = 0; return 1
		handle = 0x414
		if _api("CreateEventA",{"auto_reset":true}) != 0: event_handle = 0; return 1
		event_handle = 0x202
	elif backend == 0:
		#430970 WM_CREATE creates the window/aux profile; file device opens on400.
		handle = 0
	else: return _error("Transport supports source MIDI0/1 only")
	ready = 1
	return 0
func _error(text: String) -> int:
	errors.append(text)
	if errors.size() > 32: errors.pop_front()
	_notices.append({"kind":"error","message":text})
	return 1
func _allocate(bytes: int) -> bool:
	allocation_count += 1
	_record("allocate",bytes)
	return int(api_feedback.get("alloc_n",0)) != allocation_count
func _close_parser() -> void:
	_record("parser_cleanup")
	if sequence != null:
		sequence.tracks.clear()
		sequence.track_table_allocated = false
func _header() -> Dictionary:
	return {"allocated":false,"prepared":false,"bytes":PackedByteArray(),"records":[],"capacity":1024,"used":0}
func start_bytes(raw: PackedByteArray,looped: bool = false,name: String = "fixture.mid") -> int:
	if ready == 0: return 1
	if playing != 0:
		stop()
		if backend == 0 and playing != 0: return 1 #430B94 aborts replacement after failed stop.
	current_file = name
	repeat = looped
	queued.clear()
	_next.clear()
	_header_position = 0
	_frame_cursor = 0
	_time_floor = 0
	_time_remainder = 0
	_tempo = 500000
	_standard_index = 0
	_standard_last_tick = 0
	_mci_ended = false
	if handle == 0 and backend == 1:
		if _api("midiStreamOpen",{"device_id":0,"callback":"431400","flags":0x30000}) != 0: return 1
		handle = 0x414
	allocation_count = 0
	sequence = Sequence.new()
	sequence.repeat = repeat
	if backend == 1:
		headers = [_header(),_header()]
		for i in range(2):
			if not _allocate(1024): return 1
			headers[i].allocated = true
		sequence.memory_request = Callable(self,"_allocate")
	if api_feedback.get("open",0) or api_feedback.get("read",0) or api_feedback.get("short_read",0): return _error("Source file API failure")
	if sequence.load_bytes(raw,backend) != 0: return _error("MIDI load: "+sequence.error)
	channel_volumes.fill(100)
	if backend == 0:
		var doc = sequence.standard_events()
		if int(doc.code) != 0: return _error("Standard SMF decode")
		_standard = doc.events
		if _api("MCI_OPEN",{"type":"sequencer","element":name,"flags":0x2602}) != 0: return 1
		handle = 0x414
		if _api("MCI_SEEK_START",{"flags":0x102}) == 0x11f: return 1
		if _api("MCI_PLAY",name) == 0x11f: return 1 #430C4B: other error codes fall through.
		playing = 1
		epoch = _now
		return 0
	if _api("midiStreamProperty",{"size":8,"division":sequence.division,"property":0x80000001}) != 0:
		_close_parser()
		return 1
	completed = 0
	ring_index = 0
	for i in range(2):
		var result = sequence.fill(i == 0)
		if int(result.code) not in [0,-103]: _close_parser(); return 1
		headers[i].bytes = result.bytes
		headers[i].records = result.records
		headers[i].used = result.bytes.size()
		if prepared == 0:
			if _api("midiOutPrepareHeader",{"header":i,"size":64}) != 0: _close_parser(); return 1
			headers[i].prepared = true
		if _api("midiStreamOut",{"header":i,"size":64,"bytes":result.bytes.size()}) != 0: break # Source legacy fall-through.
		queued.append(i)
	prepared = 1
	ring_index = 0
	stop_state = 0
	if _api("midiStreamRestart") != 0: return 1
	playing = 1
	paused = 0
	epoch = _now
	return 0
func play(index: int) -> int:
	if index < 0:
		var result = stop()
		current_index = -1
		return result
	current_index = index
	normal_started = 0
	if not file_loader.is_valid(): return _error("No MIDI byte loader")
	var path = "midi/bgm%02d_GS.mid"%index
	var raw: PackedByteArray = file_loader.call(path)
	return start_bytes(raw,false,path)
func main_service() -> void:
	#401000 belongs to the source main service, never implicit inside pull().
	if ready == 0 or current_index < 0 or playing != 0 or normal_started != 0: return
	var path = "midi/bgm%02d.mid"%current_index
	var raw: PackedByteArray = file_loader.call(path) if file_loader.is_valid() else PackedByteArray()
	start_bytes(raw,not current_index in [0,3,21,24],path)
	normal_started = 1
func pause(value: int) -> void:
	if backend == 0: return #430970 has no402 case: do not invent MCI pause semantics.
	if handle == 0 or playing == 0 or paused == value: return
	_api("midiStreamPause" if value != 0 else "midiStreamRestart")
	paused = value # Raw wParam saved even on an API error; epoch unchanged.
func stop() -> int:
	if playing == 0: return 0
	if backend == 0:
		if _api("MCI_STOP") != 0: return 1
		if _api("MCI_CLOSE") != 0: return 1
		playing = 0 #430D40 changes this only after BOTH commands succeed.
		queued.clear()
		_next.clear()
		_out_events.append({"kind":"reset"})
		return 0
	playing = 0
	paused = 0
	if stop_state not in [200,300]: stop_state = 100
	if _api("midiStreamStop") != 0 or _api("midiOutReset") != 0: return 1
	_out_events.append({"kind":"reset"})
	_record("WaitForSingleObject",2000)
	var wait_result = int(api_feedback.get("wait_result",0))
	if api_feedback.has("wait_state"): stop_state = int(api_feedback.wait_state)
	elif auto_complete_stop: stop_state = 200
	if wait_result == 258: stop_state = 200
	if stop_state == 200: stop_state = 0
	_close_parser()
	for i in range(headers.size()):
		_api("midiOutUnprepareHeader",{"header":i,"size":64})
		headers[i].allocated = false
		headers[i].prepared = false
		headers[i].records = []
		headers[i].bytes = PackedByteArray()
	prepared = 0
	_api("midiStreamClose")
	handle = 0
	queued.clear()
	_next.clear()
	return 0
func callback_done(_header_identity: int = 0) -> void:
	if stop_state == 200: return
	completed += 1
	if stop_state in [100,300]:
		if completed >= 2:
			if stop_state == 300: posts.append({"message":0x401})
			stop_state = 200
			_record("SetEvent")
		return
	if playing == 0 or completed == 0: return
	var result: Dictionary
	if callback_fill_feedback.is_empty(): result = sequence.fill(false)
	else: result = callback_fill_feedback
	var code = int(result.code)
	_record("fill",{"first":0,"header":ring_index,"code":code})
	if code == -103:
		eof_seen = 1
		stop_state = 300
		return
	if code != 0:
		_close_parser()
		return
	if ring_index >= headers.size(): headers = [_header(),_header()]
	headers[ring_index].records = result.get("records",[])
	headers[ring_index].bytes = result.get("bytes",PackedByteArray())
	headers[ring_index].used = headers[ring_index].bytes.size()
	if _api("midiStreamOut",{"header":ring_index,"size":64}) != 0:
		_close_parser()
		return
	queued.append(ring_index)
	ring_index = (ring_index+1)%2
	completed -= 1
func position_callback(word: int) -> void:
	if (word&0xf0) != 0xb0 or ((word>>8)&255) != 7: return
	var channel = word&15
	channel_volumes[channel] = (word>>16)&127
	posts.append({"message":0x465,"channel":channel})
func pump_messages() -> Array:
	while not posts.is_empty():
		var post: Dictionary = posts.pop_front()
		if int(post.message) == 0x401: stop()
		elif int(post.message) == 0x3b9 and int(post.get("reason",0)) == 1 and playing != 0:
			if _api("MCI_SEEK_START",{"flags":0x100}) == 0x11f: continue
			if not repeat: stop()
			elif _api("MCI_PLAY",{"notify":true}) != 0x11f:
				_standard_index = 0
				_standard_last_tick = 0
				_time_floor = _frame_cursor
				_time_remainder = 0
				_mci_ended = false
				epoch = _now
		elif int(post.message) == 0x465 and playing != 0:
			var channel = int(post.channel)
			_send_short(0xb0|channel|(7<<8)|(int((int(channel_volumes[channel])*fade_scale)/1000)<<16))
	return take_events()
func _send_short(word: int) -> void:
	if _api("midiOutShortMsg",word) == 0 and handle != 0:
		_out_events.append({"kind":"short","word":word&0xffffff})
func fade(timer_parameter: int,direction: int) -> void:
	if ready == 0 or window_handle == 0: return #431EE0 tests HWND/ready, not stream handle.
	if fade_delta != 0: _api("KillTimer"); _timer_active = false
	if timer_parameter == 0:
		fade_delta = 0
		if backend == 1:
			fade_scale = 1000 if direction != 0 else 0
			_volume_all()
		else:
			aux_current = aux_target if direction != 0 else 0
			_aux_output()
		return
	if backend == 1: fade_delta = 50 if direction != 0 else -50
	else: fade_delta = Sequence.u32(0) # Assigned below with signed truncation.
	if backend == 0: fade_delta = _div0(aux_target-aux_current+31,32) if direction != 0 else _div0(-31-aux_current,32)
	_timer_period = int(Sequence.u32(timer_parameter)/50)
	_timer_next = Sequence.u32(_now+maxi(timer_minimum_ms,_timer_period))
	_timer_active = true
	_api("SetTimer",{"id":0,"requested_period":_timer_period})
static func _div0(a: int,b: int) -> int:
	var q: int = absi(a)/absi(b)
	return -q if (a < 0) != (b < 0) else q
func fade_tick() -> void:
	if backend == 1:
		fade_scale = clampi(fade_scale+fade_delta,0,1000)
		_volume_all()
		if fade_scale == 0 or fade_scale == 1000: fade_delta = 0
	else:
		aux_current = clampi(aux_current+fade_delta,0,aux_target)
		_aux_output()
		if aux_current == 0 or aux_current == aux_target: fade_delta = 0
	if fade_delta == 0:
		_timer_active = false
		_api("KillTimer")
func _volume_all() -> void:
	for channel in range(16): _send_short(0xb0|channel|(7<<8)|(int((int(channel_volumes[channel])*fade_scale)/1000)<<16))
func _aux_output() -> void:
	if _api("auxSetVolume",((aux_current&65535)<<16)|(aux_current&65535)) == 0:
		_out_events.append({"kind":"gain","value":float(aux_current)/65535.0})
func fade_busy() -> bool: return fade_delta != 0
func take_events() -> Array:
	var result = _out_events
	_out_events = []
	return result
func service(now_ms: int,main: bool = true,timers: bool = true,posted: bool = true) -> Dictionary:
	_now = now_ms&0xffffffff
	var events: Array = []
	if posted: events.append_array(pump_messages())
	if timers and _timer_active and int((_now-_timer_next)&0xffffffff) < 0x80000000:
		fade_tick() # WM_TIMER coalesces; no invented catch-up loop.
		_timer_next = Sequence.u32(_now+maxi(timer_minimum_ms,_timer_period))
	if main: main_service()
	events.append_array(take_events())
	return {"events":events,"playing":playing,"paused":paused,"fade_busy":fade_busy()}

func _schedule(delta: int) -> bool:
	var div = int(sequence.division)
	var numerator: int
	var denominator: int
	if (div&0x8000) != 0:
		var fps = 256-((div>>8)&255)
		var ticks = div&255
		if fps not in [24,25,29,30] or ticks == 0: _error("Invalid raw SMPTE timediv adapter"); return false
		denominator = (30000 if fps == 29 else fps)*ticks
		numerator = delta*(1001 if fps == 29 else 1)
	else:
		if div == 0: _error("Zero timediv"); return false
		denominator = div*1000000
		numerator = delta*_tempo
	# Split before multiplication: full uint32 tick/24-bit tempo range fits signed64.
	_time_floor += int(numerator/denominator)*_rate
	var remainder = (numerator%denominator)*_rate+_time_remainder
	_time_floor += int(remainder/denominator)
	_time_remainder = remainder%denominator
	_due_frame = _time_floor+int(_time_remainder != 0) # First sample boundary not before event.
	return true
func _next_event() -> bool:
	if backend == 0:
		if _mci_ended: return false
		while _standard_index < _standard.size():
			var event: Dictionary = _standard[_standard_index]
			_standard_index += 1
			_next = event
			var delta = int(event.tick)-_standard_last_tick
			_standard_last_tick = int(event.tick)
			return _schedule(delta)
		_mci_ended = true
		posts.append({"message":0x3b9,"reason":1}) # MCI_NOTIFY_SUCCESSFUL window feedback.
		_notices.append({"kind":"completed","file":current_file})
		return false
	while not queued.is_empty():
		var index = int(queued[0])
		var header: Dictionary = headers[index]
		if _header_position < header.records.size():
			_next = header.records[_header_position]
			_header_position += 1
			return _schedule(int(_next.delta))
		queued.pop_front()
		_header_position = 0
		callback_done(index) # FIFO driver adapter; callback selects global ring index.
	return false
func _dispatch(event: Dictionary) -> Array:
	if backend == 0:
		if event.kind == "tempo": _tempo = int(event.tempo); return []
		if event.kind == "short": return [{"kind":"short","word":int(event.word)}]
		if event.kind == "sysex": return [{"kind":"sysex","bytes":event.bytes}]
		return []
	var word = int(event.word)
	if (word&0xff000000) == 0x1000000:
		_tempo = word&0xffffff
		return []
	if (word&0x40000000) != 0: position_callback(word)
	return [{"kind":"short","word":word&0xffffff}]
func pull(frames: int,mix_rate: int = 44100) -> Dictionary:
	assert(frames >= 0 and mix_rate > 0)
	_rate = mix_rate
	var segments: Array = []
	var left = frames
	var events = take_events()
	var guard = 0
	while true:
		guard += 1
		if guard > 100000:
			_error("Source zero-duration repeat or empty-stream progress boundary")
			playing = 0
			segments.append({"frames":left,"events":events+[{"kind":"reset"}]})
			break
		if playing == 0 or (backend == 1 and paused != 0):
			segments.append({"frames":left,"events":events})
			break
		if _next.is_empty() and not _next_event():
			events.append_array(take_events())
			segments.append({"frames":left,"events":events})
			_frame_cursor += left
			break
		if _due_frame <= _frame_cursor:
			events.append_array(_dispatch(_next))
			_next = {}
			continue
		var count = mini(left,_due_frame-_frame_cursor)
		segments.append({"frames":count,"events":events})
		events = []
		_frame_cursor += count
		left -= count
		if left == 0: break
	var notices = _notices
	_notices = []
	return {"segments":segments,"notifications":notices,"playing":playing,"paused":paused,"frame_cursor":_frame_cursor}
