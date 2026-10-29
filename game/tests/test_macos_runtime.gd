extends SceneTree
class SetupWithoutStartup extends "res://scripts/content/ft2_content_setup.gd":
	func _ready() -> void: pass

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var failures: Array = []
	if OS.get_name() != "macOS": failures.append("macOS runtime required")
	if Engine.get_architecture_name() != "arm64": failures.append("arm64 runtime required")
	if not ClassDB.class_exists("FT2NativeSynth"): failures.append("arm64 native module missing")
	else:
		var synth = ClassDB.instantiate("FT2NativeSynth")
		if not synth.has_method("sample_startup_modifiers"): failures.append("native startup method missing")
		var frames = synth.call("render_frames",4)
		if not frames is PackedVector2Array or frames.size()!=4: failures.append("native packed-vector ABI failed")
		else:
			for frame in frames:
				if frame != Vector2.ZERO: failures.append("empty synth must render silence")
		if bool(synth.call("load_bank",PackedByteArray([0,1,2]),44100)): failures.append("invalid synthetic bank accepted")
		synth.call("set_gain",0.5)
		synth.call("reset_voices")
		synth = null
	for path in ["res://assets","res://fixtures","res://runtime","res://private"]:
		if DirAccess.dir_exists_absolute(path): failures.append("Unexpected game content: "+path)
	var test_root := ProjectSettings.globalize_path("user://macos-converter-bridge-test")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--macos-ui-test-root="): test_root = argument.trim_prefix("--macos-ui-test-root=")
	var source := test_root.path_join("synthetic-source")
	DirAccess.make_dir_recursive_absolute(source)
	var original := FileAccess.open(source.path_join("FTO_O.EXE"),FileAccess.WRITE)
	original.store_string("MZ self-authored unsupported executable fixture"); original.close()
	var setup := SetupWithoutStartup.new()
	# An unavailable Python path proves that the UI must use its bundled converter.
	setup.configuration = {"source_root":source,"content_root":test_root.path_join("cache"),"python":"/no-user-python-installed"}
	root.add_child(setup);setup._build_ui()
	setup._import()
	var deadline := Time.get_ticks_msec()+60000
	while setup.worker != null and Time.get_ticks_msec()<deadline: await process_frame
	if setup.worker != null: failures.append("GUI converter process did not complete")
	var status := setup.status_label.text
	if not status.to_lower().contains("unsupported") or status.contains("찾을 수 없습니다"):
		failures.append("GUI did not reach bundled converter's unsupported-source response: "+status)
	setup.queue_free(); await process_frame
	print("FT2_MAC_NATIVE ",JSON.stringify({"passed":failures.is_empty(),"failures":failures,"engine":Engine.get_version_info(),"gui_converter_status":status}))
	quit(0 if failures.is_empty() else 1)
