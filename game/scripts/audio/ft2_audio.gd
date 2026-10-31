class_name FT2Audio
extends Node
## Shipping backend2 uses the original extracted CD audio, BGM N -> CD N+2.
var data
var music: AudioStreamPlayer
var effects: Dictionary = {}
var current_index := -1
var music_enabled := true
var effects_enabled := true
var music_volume := 1.0
var effect_volume := 1.0
var requests: Array[Dictionary] = []
var failures: Array[String] = []
var _streams: Dictionary = {}
var _wave_paths: Dictionary = {}
var _source_sound_volumes: Dictionary = {} # DirectSound hundredths of dB, per source sound handle.
var backend := 2
var music_available := true
var availability_messages: Array[String] = []
var _audio_capabilities: Dictionary = {}
var _capabilities_declared := false
var _requested_backend := 2
var midi
var _midi_backend := -1

func configure(store) -> void:
	data = store
	for row in data.read_json("data/port_ready/assets/audio/index.json").WAV:
		_wave_paths[str(row.source).to_upper().trim_prefix("WAVE/").trim_suffix(".WAV")] = str(row.get("portable_file",""))
	music = AudioStreamPlayer.new(); add_child(music)
	music.finished.connect(_music_finished)
	if FT2Content.active != null:
		var capabilities = FT2Content.active.get("capabilities")
		if capabilities is Dictionary: _configure_capabilities(capabilities)

func _configure_capabilities(capabilities: Dictionary) -> void:
	_capabilities_declared = capabilities.get("audio") is Dictionary
	_audio_capabilities = capabilities.get("audio",{}).duplicate(true) if _capabilities_declared else {}
	availability_messages.clear()
	music_available = not _capabilities_declared or int(_audio_capabilities.get("cdda_tracks",0))>0 or bool(_audio_capabilities.get("soundfont",false))
	if _capabilities_declared and int(_audio_capabilities.get("cdda_tracks",0))==0:
		availability_messages.append("CD 배경음이 없어 MIDI 배경음을 사용합니다." if music_available else "배경음 자료가 없어 BGM을 사용하지 않습니다. 효과음은 사용할 수 있습니다.")
	_switch_backend(_effective_backend(_requested_backend))
	if not music_available: music_enabled = false

func _effective_backend(requested: int, index: int = -1) -> int:
	if not _capabilities_declared: return requested
	var has_cd := int(_audio_capabilities.get("cdda_tracks",0))>0
	var has_sf := bool(_audio_capabilities.get("soundfont",false))
	if requested == 2:
		if has_cd:
			if index < 0 or data == null: return 2
			var relative := "data/port_ready/analysis_completion/backend/cdda/BGM%02d_CDDA.wav" % index
			if FT2Content.exists(data.resolve(relative)): return 2
		return 0 if has_sf else -1
	if requested in [0,1] and has_sf: return requested
	return 2 if has_cd else -1

func _switch_backend(selected: int) -> void:
	if selected == backend: return
	backend = selected
	if midi != null:
		midi.dispose(); midi.queue_free(); midi = null; _midi_backend = -1
	if backend != 2 and music != null: music.stop()

func play_music(index: int) -> void:
	requests.append({"kind":"music","index":index,"track":index+2})
	if music == null: return
	current_index=-1 if index<0 else index #404100 stores selection even if backend play fails.
	if _capabilities_declared: _switch_backend(_effective_backend(_requested_backend,index))
	if backend < 0:
		music.stop()
		requests.append({"kind":"music_unavailable","index":index,"reason":"No CD audio or MIDI SoundFont provided"})
		return
	if backend != 2:
		music.stop()
		if not _ensure_midi():return
		if index<0:midi.play(-1);return
		if int(midi.play(index))!=0:failures.append_array(midi.failures)
		return
	if index < 0:
		music.stop(); current_index = -1; return
	if index > 24:
		music.stop();failures.append("CD track unavailable: %d" % (index+2)); return
		current_index = index
	var path := "data/port_ready/analysis_completion/backend/cdda/BGM%02d_CDDA.wav" % index
	music.stream = _wav(path)
	music.volume_linear = music_volume if music_enabled else 0.0
	if music.stream != null: music.play()

func _music_finished() -> void:
	# Original dispatcher restarts completed CD tracks except nonloop cues 0/3/21/24.
	if backend==2 and current_index >= 0 and not current_index in [0,3,21,24]: music.play()

func fade_music(timer_parameter: int,on: int) -> void:
	requests.append({"kind":"source431EE0","timer_parameter":timer_parameter,"direction":on,"backend":backend})
	# Original431EE0 branches only0/1; the shipping CDDA backend2 never sets fade delta.
	if backend == 2: return
	if _ensure_midi():midi.fade(timer_parameter,on)

func music_fade_busy() -> bool:
	return backend in [0,1] and midi != null and midi.fade_busy()

func play_sound(stem: String, loop: bool = false) -> void:
	var key := _key(stem)
	requests.append({"kind":"wave","stem":key,"loop":loop})
	if not effects_enabled: return # Source disabled DirectSound has no handle, load, playback or busy status.
	if key == "": return
	var player: AudioStreamPlayer = effects.get(key)
	if player == null:
		player = AudioStreamPlayer.new(); add_child(player); effects[key] = player
	var stream := _wav(str(_wave_paths.get(key,"data/port_ready/assets/audio/wave/"+key+".wav")))
	if stream == null: return
	var local: AudioStreamWAV = stream.duplicate()
	if loop:
		local.loop_mode = AudioStreamWAV.LOOP_FORWARD
		local.loop_begin = 0
		var channels := 2 if local.stereo else 1
		var width := 2 if local.format == AudioStreamWAV.FORMAT_16_BITS else 1
		local.loop_end = int(local.data.size()/(channels*width))
	else: local.loop_mode = AudioStreamWAV.LOOP_DISABLED
	player.stop(); player.stream = local
	player.volume_linear = effect_volume * float(_source_sound_volumes.get(key,1.0)) if effects_enabled else 0.0
	player.play()

func stop_sound(stem: String) -> void:
	var key := _key(stem)
	if key.is_empty():
		# Empty script WAVE cues release looping ambience while one-shot effects finish.
		for player in effects.values():
			if player != null and player.playing and player.stream is AudioStreamWAV and player.stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
				player.stop()
		return
	if effects.has(key): effects[key].stop()

func is_sound_playing(stem: String) -> bool:
	var player: AudioStreamPlayer = effects.get(_key(stem))
	return player != null and player.playing

static func _key(stem: String) -> String:
	return stem.replace("\\","/").trim_prefix("*").to_upper().trim_prefix("WAVE/").trim_suffix(".WAV")

func _wav(relative: String) -> AudioStreamWAV:
	if _streams.has(relative): return _streams[relative]
	var path: String = data.resolve(relative)
	if not FT2Content.exists(path):
		failures.append("Missing original audio: "+relative); return null
	var stream := AudioStreamWAV.load_from_file(path)
	if stream == null: failures.append("Original WAV decoder rejected: "+relative)
	else: _streams[relative] = stream
	return stream

func apply_settings(settings: Dictionary) -> void:
	var previous_backend:=backend
	_requested_backend = int(settings.get("music_backend",_requested_backend if _capabilities_declared else backend))
	_switch_backend(_effective_backend(_requested_backend,current_index))
	music_enabled = bool(settings.get("music",music_enabled)) and music_available; effects_enabled = bool(settings.get("effects",effects_enabled))
	music_volume = clampf(float(settings.get("music_volume",music_volume)),0,1)
	effect_volume = clampf(float(settings.get("effect_volume",effect_volume)),0,1)
	if music != null: music.volume_linear = music_volume if music_enabled else 0.0
	if midi!=null:midi.set_volume(music_volume if music_enabled else 0.0)
	if backend!=previous_backend and current_index>=0:play_music(current_index)
	for key in effects:
		var player:AudioStreamPlayer=effects[key]
		if not effects_enabled: player.stop()
		player.volume_linear = effect_volume * float(_source_sound_volumes.get(key,1.0)) if effects_enabled else 0.0

func stop_all() -> void:
	if midi!=null:midi.stop()
	if music != null: music.stop()
	for player in effects.values(): player.stop()

func dispose() -> void:
	# Detach owned playback before children exit; repeated cleanup is harmless.
	# Normal decoded-PCM caching, playback and source busy/stop rules stay intact.
	for player in effects.values():
		if is_instance_valid(player): player.stream = null
	if is_instance_valid(music): music.stream = null

func _exit_tree() -> void:
	dispose()

func _ensure_midi()->bool:
	if backend not in [0,1]:return false
	if midi!=null and _midi_backend==backend:return bool(midi._ready_output)
	midi=preload("res://scripts/midi_output/ft2_midi_output.gd").new();add_child(midi);_midi_backend=backend
	if not midi.configure(data,backend):failures.append_array(midi.failures);return false
	midi.set_volume(music_volume if music_enabled else 0.0)
	return true
func source_main_service(now_ms:int)->void:
	if midi!=null:midi.source_main_service(now_ms)

func consume_source_sound(command:Dictionary)->void:
	var operation:=str(command.get("op",""))
	var key:=_key(str(command.get("stem","")))
	match operation:
		"sound_volume":
			_source_sound_volumes[key]=pow(10.0,float(command.get("value",0))/2000.0)
			if effects.has(key):effects[key].volume_linear=effect_volume*float(_source_sound_volumes[key]) if effects_enabled else 0.0
		"sound_play":play_sound(key,int(command.get("value",0))!=0)
		"sound_release":
			stop_sound(key);_source_sound_volumes.erase(key)
		"sound_load","sound_path","resource_path":pass # Source assets resolve lazily through the exact WAV index at play.

