extends SceneTree
func _initialize() -> void:
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
	print("FT2_MAC_NATIVE ",JSON.stringify({"passed":failures.is_empty(),"failures":failures,"engine":Engine.get_version_info()}))
	quit(0 if failures.is_empty() else 1)
