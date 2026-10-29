extends SceneTree
const Setup = preload("res://scripts/content/ft2_content_setup.gd")
const Audio = preload("res://scripts/audio/ft2_audio.gd")
var checks := 0
var failures: Array[String] = []

class EmptyAudioData:
	extends RefCounted
	func read_json(_path: String) -> Dictionary: return {"WAV":[]}
	func resolve(path: String) -> String: return "user://nonexistent_audio_test/"+path

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var arguments := Setup._conversion_arguments("/tools/convert_installation.py",{"source_root":"/games/FT 2"},"/private/cache")
	check(arguments==PackedStringArray(["/tools/convert_installation.py","--source","/games/FT 2","--cache-parent","/private/cache"]),"minimal converter arguments")
	arguments = Setup._conversion_arguments("converter.py",{"source_root":"/game","font":" /font.ttf ","cdda_dir":"/audio","soundfont":"/music.sf2","legacy_port":"must-not-be-used"},"/cache")
	check(arguments.has("--font") and arguments.has("/font.ttf"),"optional font file")
	check(arguments.has("--cdda-dir") and arguments.has("/audio"),"optional CD audio folder")
	check(arguments.has("--soundfont") and arguments.has("/music.sf2"),"optional SoundFont file")
	check(not arguments.has("--legacy-port") and not arguments.has("must-not-be-used"),"no legacy workspace argument")
	var result = Setup._conversion_result("progress line\n{\"status\":\"ready\",\"content_root\":\"/cache/ready\",\"source_root\":\"/game\",\"warnings\":[\"No music\"]}\n")
	check(result is Dictionary and result.status=="ready" and result.warnings.size()==1,"last JSON result with warnings")
	check(Setup._conversion_result("not JSON")==null,"invalid converter output")
	var audio := Audio.new(); root.add_child(audio); audio.configure(EmptyAudioData.new())
	audio._configure_capabilities({})
	audio.apply_settings({"music_backend":2,"music":true,"effects":true})
	check(audio.backend==2 and audio.music_available and audio.music_enabled,"legacy cache audio behavior preserved")
	audio._configure_capabilities({"audio":{"cdda_tracks":0,"soundfont":false}})
	audio.apply_settings({"music_backend":2,"music":true,"effects":true})
	check(audio.backend==-1 and not audio.music_available and not audio.music_enabled,"missing BGM explicitly unavailable")
	check(audio.effects_enabled and not audio.availability_messages.is_empty(),"effects kept with BGM status message")
	audio.play_music(1)
	check(audio.failures.is_empty() and audio.requests[-1].kind=="music_unavailable","missing optional BGM does not load absent files")
	audio._configure_capabilities({"audio":{"cdda_tracks":0,"soundfont":true}})
	audio.apply_settings({"music_backend":2,"music":true})
	check(audio.backend==0 and audio.music_available and audio.music_enabled,"MIDI default when SoundFont supplied")
	check(audio._effective_backend(2,1)==0,"CD preference safely falls back to MIDI")
	audio._configure_capabilities({"audio":{"cdda_tracks":25,"soundfont":false}})
	audio.apply_settings({"music_backend":2,"music":true})
	check(audio.music_available and audio._effective_backend(2)==2,"CD capability preferred")
	check(audio._effective_backend(2,1)==-1,"missing specific CD track stays silent without error")
	check(audio._effective_backend(0)==2,"MIDI preference without SoundFont falls back to available CD")
	audio.stop_all();audio.dispose();audio.queue_free()
	await process_frame;await process_frame
	print("FT2_SETUP_AUDIO_TESTS ",JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
