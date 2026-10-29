class_name FT2Content
extends RefCounted
## External data only. Mods are declarative files, never executable scripts.

static var active: FT2Content
var root := ""
var source := ""
var content_id := ""
var profile_id := ""
var capabilities: Dictionary = {}
var layers: Array[Dictionary] = []
var issues: Array[String] = []

const STRIDES := {"item":56,"magic":64,"race":86}
const REQUIRED := ["assets/indexed/manifest.json","assets/indexed/fonts.json","assets/indexed/font_masks.bin","assets/cp949.json","fixtures/item.dat","fixtures/magic.dat","fixtures/race.dat","data/port_ready/maps/index.json","data/port_ready/tables/stages.json","data/port_ready/scripts/spec/runtime_bindings.json"]
const TABLE_FIELDS := {
	"item": {"name":[0,"cp949",20],"price":[20,"u16"],"effect1":[22,"s16"],"effect2":[24,"s16"],"atk":[26,"s16"],"def":[28,"s16"],"int":[30,"s16"],"mdef":[32,"s16"],"agi":[34,"s16"],"attribute0":[36,"s16"],"attribute1":[38,"s16"],"attribute2":[40,"s16"],"target_distance_min_raw":[42,"u16"],"target_distance_max_raw":[44,"u16"],"category":[46,"u16"],"action_visual_selector_raw":[48,"u16"],"target_shape_raw":[50,"u16"],"state_code":[52,"u16"],"equip_kind_mask":[54,"u16"]},
	"magic": {"name":[0,"cp949",20],"req_level":[20,"s16"],"mp":[22,"s16"],"power":[24,"s16"],"v1":[26,"s16"],"power1":[26,"s16"],"power2":[28,"s16"],"v2":[30,"s16"],"flag":[32,"s16"],"target_distance_min_raw":[30,"s16"],"target_distance_max_raw":[32,"s16"],"apd_stem":[34,"ascii",12],"sfx_index":[46,"s16"],"target_mode_raw":[48,"s16"],"ai_dispatch_type_raw":[50,"s16"],"learn_kind_mask":[52,"u16"],"effect_name":[54,"cp949",10]},
	"race": {"name":[0,"cp949",20],"experience_value":[20,"s16"],"hp.initial":[22,"s16"],"hp.growth":[24,"s16"],"mp.initial":[26,"s16"],"mp.growth":[28,"s16"],"atk.initial":[30,"s16"],"atk.growth":[32,"s16"],"def.initial":[34,"s16"],"def.growth":[36,"s16"],"int.initial":[38,"s16"],"int.growth":[40,"s16"],"mdef.initial":[42,"s16"],"mdef.growth":[44,"s16"],"agi.initial":[46,"s16"],"agi.growth":[48,"s16"],"attribute0":[50,"s16"],"attribute1":[52,"s16"],"attribute2":[54,"s16"]}
}

static func canonical(path: String) -> String:
	var value := path.replace("\\","/")
	if value.begins_with("res://runtime/"): value = value.trim_prefix("res://runtime/")
	elif value.begins_with("res://assets/") or value.begins_with("res://fixtures/"): value = value.trim_prefix("res://")
	elif active != null and value.begins_with(active.root+"/"): value = value.trim_prefix(active.root+"/")
	elif active != null:
		for layer in active.layers:
			var prefix: String = layer.root+"/files/"
			if value.begins_with(prefix): value = value.trim_prefix(prefix); break
	if value.is_absolute_path() or value.contains(":") or value.begins_with("/"): return ""
	for part in value.split("/"):
		if part in ["",".",".."]: return ""
	return value

func _inside(base: String, key: String) -> String:
	if canonical(key) != key: return ""
	var current := base
	for part in key.split("/"):
		var directory := DirAccess.open(current)
		if directory != null and directory.is_link(part): return ""
		current = current.path_join(part)
	return current

static func activate(cache_root: String, source_root: String, mods: Array = []) -> Dictionary:
	var candidate := FT2Content.new()
	candidate.root = ProjectSettings.globalize_path(cache_root).replace("\\","/").trim_suffix("/")
	candidate.source = ProjectSettings.globalize_path(source_root).replace("\\","/").trim_suffix("/")
	var metadata = _plain_json(candidate.root.path_join("content.json"))
	if not metadata is Dictionary or metadata.get("schema",0) != 1 or metadata.get("status","") != "ready":
		return {"ok":false,"error":"유효한 개인 콘텐츠 캐시(content.json)가 필요합니다."}
	var expected := {}
	for row in metadata.get("files",[]): expected[str(row.path)] = row
	for key in REQUIRED:
		var path := candidate._inside(candidate.root,str(key))
		if path == "" or not FileAccess.file_exists(path) or not expected.has(key):
			return {"ok":false,"error":"콘텐츠 캐시 누락: "+str(key)}
		if FileAccess.get_sha256(path) != str(expected[key].sha256):
			return {"ok":false,"error":"콘텐츠 캐시가 손상되었습니다: "+str(key)}
	for key in ["DATA/ITEM.DAT","DATA/MAGIC.DAT","DATA/RACE.DAT","FTO_O.EXE"]:
		var path := candidate.original_path(key)
		if path == "" or FileAccess.get_sha256(path) != str(metadata.get("source_files",{}).get(key,"missing")):
			return {"ok":false,"error":"선택한 정품 폴더와 캐시의 판본이 다릅니다: "+key}
	candidate.content_id = str(metadata.content_id)
	candidate.capabilities = metadata.get("capabilities",{})
	var identities: Array = [candidate.content_id]
	var ids := {}
	for mod_path in mods:
		var mod_root := ProjectSettings.globalize_path(str(mod_path)).replace("\\","/").trim_suffix("/")
		var mod = _plain_json(mod_root.path_join("mod.json"))
		if not mod is Dictionary or mod.get("schema",0) != 1 or str(mod.get("id","")).is_empty():
			return {"ok":false,"error":"유효하지 않은 mod.json: "+mod_root}
		if ids.has(str(mod.id)): return {"ok":false,"error":"중복 모드 ID: "+str(mod.id)}
		ids[str(mod.id)] = true
		for patch in mod.get("patches",[]):
			var target := str(patch.get("target",""))
			if canonical(target) != target or not target.ends_with(".json") or target in ["data/port_ready/tables/item.dat.json","data/port_ready/tables/magic.dat.json","data/port_ready/tables/race.dat.json"]:
				return {"ok":false,"error":"모드 JSON 경로 오류. 테이블은 table_edits를 사용하세요: "+target}
		for edit in mod.get("table_edits",[]):
			if not STRIDES.has(str(edit.get("table",""))): return {"ok":false,"error":"지원하지 않는 테이블입니다."}
		candidate.layers.append({"root":mod_root,"manifest":mod,"id":str(mod.id)})
		identities.append([mod.id,FileAccess.get_sha256(mod_root.path_join("mod.json")),candidate._file_identities(mod_root.path_join("files"))])
	candidate.profile_id = JSON.stringify(identities).sha256_text().substr(0,24)
	# Validate table edits before replacing the active mount.
	var previous = active
	active = candidate
	for table in STRIDES: table_bytes(str(table))
	for layer in candidate.layers:
		for patch in layer.manifest.get("patches",[]): read_json(str(patch.target))
	if not candidate.issues.is_empty():
		active = previous
		return {"ok":false,"error":"; ".join(candidate.issues)}
	return {"ok":true,"content_id":candidate.content_id,"profile_id":candidate.profile_id,"mods":ids.keys()}

func _file_identities(directory: String) -> Array:
	var result: Array = []
	var handle := DirAccess.open(directory)
	if handle == null: return result
	var names := Array(handle.get_files()) + Array(handle.get_directories())
	names.sort()
	for name in names:
		if handle.is_link(name): issues.append("모드 심볼릭 링크는 지원하지 않습니다: "+str(name)); continue
		var path := directory.path_join(str(name))
		if DirAccess.dir_exists_absolute(path): result.append([name,_file_identities(path)])
		else: result.append([name,FileAccess.get_sha256(path)])
	return result

func original_path(relative: String) -> String:
	if canonical(relative) != relative: return ""
	var current := source
	for part in relative.split("/"):
		var directory := DirAccess.open(current)
		if directory == null: return ""
		var match_name := ""
		for name in Array(directory.get_files())+Array(directory.get_directories()):
			if str(name).nocasecmp_to(part) == 0:
				if directory.is_link(str(name)): return ""
				if match_name != "": return ""
				match_name = str(name)
		if match_name == "": return ""
		current = current.path_join(match_name)
	return current

static func path_for(path: String) -> String:
	var key := canonical(path)
	if key == "": return path
	if active == null: return "user://missing-content/".path_join(key)
	for index in range(active.layers.size()-1,-1,-1):
		var layer: Dictionary = active.layers[index]
		var found := active._inside(str(layer.root).path_join("files"),key)
		if found != "" and FileAccess.file_exists(found): return found
	return active._inside(active.root,key)

static func exists(path: String) -> bool:
	var resolved := path_for(path)
	return resolved != "" and FileAccess.file_exists(resolved)

static func bytes(path: String) -> PackedByteArray:
	var resolved := path_for(path)
	return FileAccess.get_file_as_bytes(resolved) if resolved != "" and FileAccess.file_exists(resolved) else PackedByteArray()

static func text(path: String) -> String:
	if canonical(path) != "" and path.ends_with(".json"):
		var document = read_json(path)
		return JSON.stringify(document) if document != null else ""
	var resolved := path_for(path)
	return FileAccess.get_file_as_string(resolved) if resolved != "" and FileAccess.file_exists(resolved) else ""

static func _plain_json(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

static func read_json(path: String) -> Variant:
	var key := canonical(path)
	if key == "": return _plain_json(path)
	if active == null: return null
	var document = _plain_json(active._inside(active.root,key))
	for layer in active.layers:
		var overlay := active._inside(str(layer.root).path_join("files"),key)
		if overlay != "" and FileAccess.file_exists(overlay): document = _plain_json(overlay)
		for patch in layer.manifest.get("patches",[]):
			if str(patch.target) == key:
				for operation in patch.get("operations",[]):
					if not active._patch(document,operation):
						active.issues.append("JSON 패치 실패: "+str(layer.id)+" / "+key)
						return null
	return document

func _patch(document: Variant, operation: Dictionary) -> bool:
	var pointer := str(operation.get("path",""))
	var op := str(operation.get("op",""))
	if not pointer.begins_with("/") or not op in ["set","remove","append"]: return false
	var parts := pointer.trim_prefix("/").split("/")
	var node = document
	for i in range(parts.size()):
		var key := str(parts[i]).replace("~1","/").replace("~0","~")
		var last := i == parts.size()-1
		if node is Dictionary:
			if last:
				if op == "set": node[key] = operation.get("value"); return true
				if op == "remove" and node.has(key): node.erase(key); return true
				if op == "append" and node.get(key) is Array: node[key].append(operation.get("value")); return true
				return false
			if not node.has(key): return false
			node = node[key]
		elif node is Array:
			if not key.is_valid_int(): return false
			var index := int(key)
			if index < 0 or index >= node.size(): return false
			if last:
				if op == "set": node[index] = operation.get("value"); return true
				if op == "remove": node.remove_at(index); return true
				if op == "append" and node[index] is Array: node[index].append(operation.get("value")); return true
				return false
			node = node[index]
		else: return false
	return false

static func table_bytes(table: String) -> PackedByteArray:
	if active == null or not STRIDES.has(table): return PackedByteArray()
	var key := "fixtures/"+table+".dat"
	var result := FileAccess.get_file_as_bytes(active.root.path_join(key))
	for layer in active.layers:
		var overlay := active._inside(str(layer.root).path_join("files"),key)
		if overlay != "" and FileAccess.file_exists(overlay): result = FileAccess.get_file_as_bytes(overlay)
		if result.size() % int(STRIDES[table]) != 0:
			active.issues.append("테이블 레코드 길이 오류: "+table); return PackedByteArray()
		for edit in layer.manifest.get("table_edits",[]):
			if str(edit.get("table","")) != table: continue
			var record := int(edit.get("record",-1))
			if record < 0 or record >= result.size()/int(STRIDES[table]):
				active.issues.append("테이블 ID 범위 오류: "+table); return PackedByteArray()
			for field in edit.get("fields",{}):
				if not TABLE_FIELDS[table].has(field):
					active.issues.append("지원하지 않는 테이블 필드: "+str(field)); return PackedByteArray()
				var format: Array = TABLE_FIELDS[table][field]
				var offset := record*int(STRIDES[table])+int(format[0])
				var value = edit.fields[field]
				if format[1] in ["u16","s16"]:
					var low := -32768 if format[1] == "s16" else 0
					var high := 32767 if format[1] == "s16" else 65535
					if not (value is int or value is float) or float(value) != int(value) or int(value)<low or int(value)>high:
						active.issues.append("테이블 숫자 범위 오류: "+str(field)); return PackedByteArray()
					result.encode_u16(offset,int(value)&65535)
				else:
					var encoded := active._encode(str(value),str(format[1]))
					if encoded.size() >= int(format[2]):
						active.issues.append("테이블 문자열 길이 오류: "+str(field)); return PackedByteArray()
					for i in range(int(format[2])): result[offset+i] = encoded[i] if i<encoded.size() else 0
	return result

func _encode(value: String, encoding: String) -> PackedByteArray:
	var result := PackedByteArray()
	var codec = _plain_json(root.path_join("assets/cp949.json"))
	for i in value.length():
		var code := value.unicode_at(i)
		if encoding == "ascii":
			if code >= 128: issues.append("ASCII 필드의 한글/유니코드 문자는 지원하지 않습니다."); return PackedByteArray()
			result.append(code)
		else:
			var key := str(code)
			if not codec.encode.has(key): issues.append("CP949로 표현할 수 없는 문자입니다."); return PackedByteArray()
			for byte in codec.encode[key]: result.append(int(byte))
	return result

static func save_root() -> String:
	return "user://profiles/"+(active.profile_id if active != null else "unconfigured")+"/saves"
