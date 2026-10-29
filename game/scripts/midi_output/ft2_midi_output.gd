class_name FT2MidiOutput
extends Node
## Explicit GM endpoint adapter. Source0/1 event/timing algorithms are separate.
const Transport = preload("res://scripts/midi/ft2_midi_transport.gd")
var data
var transport
var synth
var player: AudioStreamPlayer
var generator: AudioStreamGenerator
var playback: AudioStreamGeneratorPlayback
var backend := 1
var rate := 44100
var adapter_headroom := 0.25 # Named GM endpoint calibration, not an original Win95 volume measurement.
var failures: Array[String] = []
var unhandled_sysex := 0
var rendered_frames := 0
var _ready_output := false
var _wall_ms := 0
var _disposed := false

func configure(store,source_backend: int = 1) -> bool:
	data = store; backend = source_backend
	_wall_ms = Time.get_ticks_msec()
	process_priority = -100 # Native posted messages/timers precede the next source outer frame.
	if not ClassDB.class_exists("FT2NativeSynth"):
		failures.append("Optional GM synth native adapter is unavailable on this platform")
		return false
	synth = ClassDB.instantiate("FT2NativeSynth")
	if not synth.call("load_bank",FT2Content.bytes("res://assets/audio/TimGM6mb.sf2"),rate):
		failures.append("Optional GM soundfont load failed"); synth = null; return false
	synth.call("set_gain",adapter_headroom)
	transport = Transport.new()
	if int(transport.configure(_load_file,backend)) != 0:
		failures.append("Source MIDI transport initialization failed"); return false
	player = AudioStreamPlayer.new(); add_child(player)
	_ready_output = true
	return true

func _load_file(path: String) -> PackedByteArray:
	var name := path.replace("\\","/").get_file().to_upper()
	var source: String = data.resolve("data/port_ready/assets/audio/midi/"+name)
	return FT2Content.bytes(source) if FT2Content.exists(source) else PackedByteArray()

func play(index: int) -> int:
	if not _ready_output: return 1
	transport.service(Time.get_ticks_msec(),false,false,false)
	player.stop(); playback = null
	var error := int(transport.play(index))
	_dispatch_all(transport.take_events())
	if error == 0 and index >= 0: _start_playback()
	if error != 0: failures.append_array(transport.errors)
	return error

func _start_playback() -> void:
	# A fresh playback is the portable flush boundary; active.clear_buffer() is invalid.
	player.stop()
	generator = AudioStreamGenerator.new(); generator.mix_rate = rate; generator.buffer_length = 0.12
	player.stream = generator; player.play()
	playback = player.get_stream_playback()

func stop() -> void:
	if transport != null:
		transport.stop(); _dispatch_all(transport.take_events())
	if player != null: player.stop()
	playback = null
	if synth != null: synth.call("reset_voices")

func fade(timer_parameter: int,direction: int) -> void:
	if transport == null: return
	transport.fade(timer_parameter,direction)
	_dispatch_all(transport.take_events())

func fade_busy() -> bool:
	return transport != null and transport.fade_busy()

func source_main_service(now_ms: int) -> void:
	if transport == null: return
	var result: Dictionary = transport.service(Time.get_ticks_msec(),true,false,false)
	_dispatch_all(result.events)

func _process(delta: float) -> void:
	_wall_ms = Time.get_ticks_msec()
	if not _ready_output: return
	var posted: Dictionary = transport.service(_wall_ms,false,true,true)
	_dispatch_all(posted.events)
	if playback == null:
		if int(transport.playing) == 0: return
		_start_playback()
	var frames := playback.get_frames_available()
	if frames <= 0: return
	var result: Dictionary = transport.pull(frames,rate)
	for segment in result.segments:
		_dispatch_all(segment.events)
		if int(segment.frames) > 0:
			var samples: PackedVector2Array = synth.call("render_frames",int(segment.frames))
			playback.push_buffer(samples)
			rendered_frames += samples.size()

func _dispatch_all(events: Array) -> void:
	if synth == null: return
	for event in events:
		match str(event.kind):
			"short": synth.call("dispatch_short",int(event.word))
			"sysex":
				if not synth.call("dispatch_sysex",event.bytes): unhandled_sysex += 1
			"reset": synth.call("reset_voices")
			"gain": synth.call("set_gain",adapter_headroom*float(event.value))

func set_volume(linear: float) -> void:
	if player != null: player.volume_linear = clampf(linear,0.0,1.0)

func dispose() -> void:
	if _disposed: return
	_disposed = true
	set_process(false)
	stop()
	if transport != null:
		transport.file_loader = Callable()
		if transport.sequence != null: transport.sequence.memory_request = Callable()
	transport = null
	synth = null
	playback = null
	if player != null:
		player.stop(); player.stream = null
	generator = null
	data = null

func _exit_tree() -> void:
	dispose()
