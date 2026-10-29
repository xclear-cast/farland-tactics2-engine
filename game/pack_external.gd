extends SceneTree
## Explicit engine allowlist. No assets, fixtures, runtime or user cache paths.
var paths: Array[String] = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2: printerr("Expected OUTPUT.pck MANIFEST.json"); quit(2); return
	_collect("res://scripts")
	_collect("res://scenes")
	paths.append("res://project.godot")
	paths.append("res://native/ft2_synth.gdextension")
	for filename in ["ft2synth.dll","libft2synth.so","libft2synth.macos.arm64.dylib"]:
		var library: String = "res://native/bin/"+str(filename)
		if FileAccess.file_exists(library): paths.append(library)
	for filename in ["global_script_class_cache.cfg","extension_list.cfg"]:
		var path: String = "res://.godot/"+str(filename)
		if FileAccess.file_exists(path): paths.append(path)
	paths.sort()
	var packer := PCKPacker.new()
	var error := packer.pck_start(args[0])
	if error != OK: printerr(error); quit(3); return
	var rows: Array = []
	for path in paths:
		if path.begins_with("res://assets/") or path.begins_with("res://fixtures/") or path.begins_with("res://runtime/"):
			printerr("Content in engine package: "+path); quit(4); return
		error = packer.add_file(path,path)
		if error != OK: printerr("Missing engine dependency: "+path); quit(5); return
		rows.append({"path":path,"sha256":FileAccess.get_sha256(path),"bytes":FileAccess.get_file_as_bytes(path).size()})
	error = packer.flush()
	if error != OK: printerr(error); quit(6); return
	var file := FileAccess.open(args[1],FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema":1,"kind":"external-content-migration-candidate","game_content_included":false,"files":rows},"\t"));file.close()
	print("FT2_PACK ",JSON.stringify({"files":paths.size(),"game_content_included":false})); quit(0)

func _collect(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	for name in directory.get_directories():
		if not name.begins_with("."): _collect(path.path_join(name))
	for name in directory.get_files():
		if name.ends_with(".gd") or name.ends_with(".gdshader") or name.ends_with(".gdshaderinc") or name.ends_with(".tscn"):
			paths.append(path.path_join(name))
