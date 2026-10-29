extends SceneTree
func _initialize() -> void:
	var failed: Array = []
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://engine_manifest.json"))
	for row in manifest.files:
		if not FileAccess.file_exists(str(row.path)) or FileAccess.get_sha256(str(row.path))!=str(row.sha256): failed.append(row.path)
	for path in ["res://assets","res://fixtures","res://runtime","res://private","res://data"]:
		if DirAccess.dir_exists_absolute(path): failed.append("Unexpected content directory: "+path)
	print("FT2_PACK_AUDIT ",JSON.stringify({"files":manifest.files.size(),"failures":failed,"passed":failed.is_empty()}))
	quit(0 if failed.is_empty() else 1)
