class_name FT2Data
extends RefCounted

var repo_root: String
var data_root: String
var _json_cache: Dictionary = {}
var _tables: Dictionary = {}
var _raw_tables: Dictionary = {}
var _cp949: Dictionary = {}
var source_root: String
var prefer_user_saves := true
var placement_constructed: Array[Dictionary] = [] # Ordered successful41A7F0 calls, including repeated slots.

const U16_FIELDS := {0:"kind",2:"definition_id",4:"level",6:"direction",16:"state",18:"control",20:"weapon",22:"armor",24:"accessory1",26:"accessory2",28:"drop_item",30:"drop_money",32:"unknown20_raw",34:"unknown22_raw"}
const S16_FIELDS := {36:"hp_max",38:"hp",40:"mp_max",42:"mp",44:"experience",46:"atk",48:"def",50:"int",52:"mdef",54:"agi",56:"skill0",58:"skill1",60:"skill2",62:"skill3",64:"skill4",66:"skill5",68:"skill6",70:"skill7",72:"skill8",74:"skill9",76:"temp_atk",78:"temp_def",80:"temp_int",82:"temp_mdef",84:"temp_agi",86:"attribute0",88:"attribute1",90:"attribute2"}
const S32_FIELDS := {8:"x",12:"y",92:"move_marker",96:"action_marker",100:"prepared_mode",104:"status_counter"}
const U32_FIELDS := {108:"apd_resource_handle_raw",112:"visual_handle70_raw",116:"visual_handle74_raw",120:"visual_handle78_raw"}

func _init(_root: String = "") -> void:
	assert(FT2Content.active != null, "Configure external content before creating the game")
	repo_root = FT2Content.active.root
	data_root = repo_root.path_join("data/port_ready")
	source_root = FT2Content.active.source

func resolve(relative: String) -> String:
	return FT2Content.path_for(relative)

func read_json(relative: String) -> Variant:
	if not _json_cache.has(relative):
		var document = FT2Content.read_json(relative)
		if document == null:
			push_error("Missing external content: " + relative)
			return null
		_json_cache[relative] = document
	return _json_cache[relative]

func load_table(table: String) -> Array:
	var key := table.to_lower()
	if not _tables.has(key):
		var parsed: Dictionary = read_json("data/port_ready/tables/" + key + ".dat.json")
		_tables[key] = _decode_table(key, raw_table(key), parsed.get("records", []))
		if FT2Content.active.extensions!=null:
			for index in _tables[key].size():_tables[key][index]=FT2Content.active.extensions.display_record(key,index,_tables[key][index])
	return _tables[key]

func raw_table(table: String) -> PackedByteArray:
	var key = table.to_lower()
	if not _raw_tables.has(key):
		_raw_tables[key] = FT2Content.table_bytes(key)
	return _raw_tables[key].duplicate() # Callers own mutable rule/test copies; source stays immutable.

func _decode_table(table: String, raw: PackedByteArray, base: Array) -> Array:
	# Rules and UI share the same patched binary records. JSON is metadata only.
	var result: Array = []
	var stride := int(FT2Content.STRIDES[table])
	for index in range(raw.size()/stride):
		var record := raw.slice(index*stride,(index+1)*stride)
		var row: Dictionary = base[index].duplicate(true) if index < base.size() else {"id":index}
		if str(row.get("raw_record_hex","")) == record.hex_encode():
			result.append(row); continue
		row.id = index
		for field in FT2Content.TABLE_FIELDS[table]:
			if str(field).contains("."): continue
			var format: Array = FT2Content.TABLE_FIELDS[table][field]
			var offset := int(format[0])
			match str(format[1]):
				"s16": row[field] = record.decode_s16(offset)
				"u16": row[field] = record.decode_u16(offset)
				"cp949": row[field] = decode_cp949(record.slice(offset,offset+int(format[2])))
				"ascii":
					var text_bytes := record.slice(offset,offset+int(format[2]))
					var terminator := text_bytes.find(0)
					row[field] = text_bytes.slice(0,terminator if terminator >= 0 else text_bytes.size()).get_string_from_ascii()
		row.raw_record_hex = record.hex_encode()
		if table == "item":
			row.name_raw_hex = record.slice(0,20).hex_encode()
			row.icon = row.action_visual_selector_raw; row.effect_id = row.target_shape_raw
			row.tail_0x36_raw = row.equip_kind_mask
			row.attribute_channels_signed = [row.attribute0,row.attribute1,row.attribute2]
		elif table == "magic":
			row.index = index; row.legacy_id = index+1
			row.power_channels_signed = [record.decode_s16(24),record.decode_s16(26),record.decode_s16(28)]
			row.tail_0x2e_raw = row.sfx_index
		elif table == "race":
			row.stats = {}
			var names := ["hp","mp","atk","def","int","mdef","agi"]
			for stat in range(names.size()):
				var initial := record.decode_s16(22+stat*4)
				var growth := record.decode_s16(24+stat*4)
				row.stats[names[stat]] = {"initial":initial,"increment_per_level":growth,"base":initial,"growth":growth,"parameter_pair_raw":[initial,growth]}
			row.class_header_word_0x14_raw = row.experience_value
			row.attribute_channels_signed = [record.decode_s16(50),record.decode_s16(52),record.decode_s16(54)]
			row.shadow_size_selector = record.decode_u16(56)
			row.max_up_height = record.decode_u16(58); row.max_down_height = record.decode_u16(60)
			row.terrain_costs_signed = []
			for i in range(8): row.terrain_costs_signed.append(record.decode_s16(62+i*2))
			row.default_skill_slots4 = []
			for i in range(4): row.default_skill_slots4.append(record.decode_s16(78+i*2))
		result.append(row)
	return result

func load_map(map_id: int) -> Dictionary:
	if FT2Content.active.extensions!=null:
		var definition: Dictionary=FT2Content.active.extensions.map_by_id(map_id)
		if not definition.is_empty():return preload("res://scripts/extensions/ft2_extension_maps.gd").normalized(self,definition,map_id)
	var index: Dictionary = read_json("data/port_ready/maps/index.json")
	for row in index.maps:
		if int(row.map_id) == map_id:
			return read_json(str(row.file))
	push_error("Unknown map: " + str(map_id))
	return {}

func load_apd(stem: String) -> Dictionary:
	var key := stem.get_file().get_basename().to_upper()
	if FT2Content.active.extensions!=null:key=FT2Content.active.extensions.sprite_alias(key)
	var parsed = read_json("data/port_ready/assets/apd/animations/" + key + ".json")
	return parsed if parsed is Dictionary else {}

func appearance_definition(definition: int) -> int:
	return FT2Content.active.extensions.appearance_definition(definition) if FT2Content.active.extensions!=null else definition

func sprite_stem(definition: int, variant: String) -> String:
	var stem:="CHAR_%02d%s"%[definition,variant]
	return FT2Content.active.extensions.sprite_alias(stem) if FT2Content.active.extensions!=null else stem

func skill_visual_id(action: int) -> int:
	return FT2Content.active.extensions.visual_skill(action) if FT2Content.active.extensions!=null else action

func skill_numeric_id(action: int) -> int:
	return FT2Content.active.extensions.numeric_skill(action) if FT2Content.active.extensions!=null else action

func load_save(index: int) -> Dictionary:
	var user_path := FT2Content.save_root().path_join("save%02d.dat" % index)
	if prefer_user_saves and FT2Content.exists(user_path):
		var sidecar: Dictionary = {}
		if FT2Content.exists(user_path + ".json"):
			sidecar = JSON.parse_string(FT2Content.text(user_path + ".json"))
		return decode_save(FT2Content.bytes(user_path), index, sidecar)
	var parsed: Dictionary = read_json("data/port_ready/saves/save%02d.json" % index)
	var binary_units: Array[PackedByteArray] = []
	for unit in parsed.units:
		binary_units.append(encode_unit(unit))
	var binding: Dictionary = {}
	var bindings: Dictionary = read_json("data/port_ready/saves/map_bindings.json")
	for row in bindings.rows:
		if str(row.file).to_lower() == "save%02d.dat" % index:
			binding = row
			break
	return {"header": parsed.header.duplicate(true), "units": binary_units,
		"map_id": int(binding.get("map_id", -1)), "control_mode": int(binding.get("control_mode", 1)),
		"source_index": index, "source_sha256": parsed.source_sha256,
		"header_raw":str(parsed.header_raw_hex).hex_decode(),
		"tail": str(parsed.tail_raw_hex).hex_decode(), "binding": binding}

func _codec() -> void:
	if _cp949.is_empty():
		_cp949 = JSON.parse_string(FT2Content.text("res://assets/cp949.json"))

func decode_cp949(bytes: PackedByteArray) -> String:
	_codec()
	var out := ""
	var offset := 0
	while offset < bytes.size():
		var value := int(bytes[offset])
		offset += 1
		if value == 0: break
		if value >= 128 and offset < bytes.size():
			var pair := str(value * 256 + bytes[offset])
			if _cp949.decode.has(pair):
				out += String.chr(int(_cp949.decode[pair]))
				offset += 1
				continue
		out += String.chr(int(_cp949.decode.get(str(value), 0xFFFD)))
	return out

func encode_cp949(value: String) -> PackedByteArray:
	_codec()
	var out := PackedByteArray()
	for i in value.length():
		var key := str(value.unicode_at(i))
		for byte in _cp949.encode.get(key, [63]):
			out.append(int(byte))
	return out

func source_bytes(relative: String) -> PackedByteArray:
	var path := source_root
	for component in relative.replace("\\", "/").split("/", false):
		var direct := path.path_join(component)
		if FT2Content.exists(direct) or DirAccess.dir_exists_absolute(direct):
			path = direct
			continue
		var dir := DirAccess.open(path)
		if dir == null: return PackedByteArray()
		var found := false
		for name in Array(dir.get_directories()) + Array(dir.get_files()):
			if str(name).nocasecmp_to(component) == 0:
				path = path.path_join(str(name)); found = true; break
		if not found: return PackedByteArray()
	return FT2Content.bytes(path)

func load_placement(number: int, combat = null) -> Array:
	placement_constructed.clear()
	var document: Dictionary = read_json("data/port_ready/tables/stages.json")
	var records: Array = document.get("STAGE%03d" % number, {}).get("records", [])
	var units: Array = []
	if combat != null:
		units = combat.snapshot_units()
	else:
		for i in range(50):
			var empty := PackedByteArray(); empty.resize(124); empty.fill(0); units.append(empty)
	for i in range(10,50):
		if units[i].decode_u16(0) != 0:
			var empty := PackedByteArray(); empty.resize(124); empty.fill(0); units[i] = empty
	for row in records:
		var unit := encode_unit({"kind":row.kind_word,"definition_id":row.definition_id,
			"level":row.level,"direction":row.direction_word,"x":row.x,"y":row.y,
			"state":row.state,"control":row.control,"weapon":row.weapon,"armor":row.armor,
			"drop_item":row.drop_item,"drop_money":row.drop_money})
		if combat != null:
			var result: Dictionary = combat.rules.construct(units, unit, combat.rng)
			units = result.units; combat.rng = result.seeds
			if int(result.slot) < 0: break
			placement_constructed.append({"slot":int(result.slot),"unit":units[int(result.slot)].duplicate()})
		else:
			# Raw placement decoding is diagnostic; gameplay must supply its shared RNG/controller.
			for slot in range(0 if int(row.control) == 0 else 10, 10 if int(row.control) == 0 else 50):
				if units[slot].decode_u16(0) == 0: units[slot] = unit; break
	return units

func decode_save(bytes: PackedByteArray, index: int, binding: Dictionary = {}) -> Dictionary:
	if bytes.size() != 468 + 6200 + 180:
		push_error("Invalid original save length: %d" % bytes.size()); return {}
	var header := {"stage":bytes.decode_u16(4),"round_index":bytes.decode_s16(38),
		"title_cp949_raw_hex":bytes.slice(6,38).hex_encode(),
		"bgm":bytes.decode_u16(106),"money":bytes.decode_s32(108),
		"battle_objective_cp949_raw_hex":bytes.slice(436,468).hex_encode(),
		"event_variables_independent":[],"system_time_words":[],"inventory":[]}
	for i in range(25): header.event_variables_independent.append(bytes.decode_s16(40 + i*2))
	for i in range(8): header.system_time_words.append(bytes.decode_u16(90+i*2))
	for i in range(80): header.inventory.append({"id":bytes.decode_s16(112+i*4),"quantity":bytes.decode_s16(114+i*4)})
	var units: Array = []
	for i in range(50): units.append(bytes.slice(468+i*124,468+(i+1)*124))
	return {"header":header,"header_raw":bytes.slice(0,468),"units":units,
		"tail":bytes.slice(6668,6848),"source_index":index,"source_sha256":"user-save",
		"map_id":int(binding.get("map_id",-1)),"control_mode":int(binding.get("control_mode",1)),"binding":binding}

func encode_save(save: Dictionary) -> PackedByteArray:
	var bytes: PackedByteArray = save.get("header_raw", PackedByteArray()).duplicate()
	if bytes.size() != 468: bytes.resize(468); bytes.fill(0); bytes.encode_u32(0,468)
	var header: Dictionary = save.header
	bytes.encode_u16(4, int(header.get("stage",0)) & 65535)
	bytes.encode_u16(38,int(header.get("round_index",0)) & 65535)
	bytes.encode_u16(106,int(header.get("bgm",0)) & 65535)
	bytes.encode_u32(108,int(header.get("money",0)) & 0xFFFFFFFF)
	for field in [{"key":"title_cp949_raw_hex","offset":6},{"key":"battle_objective_cp949_raw_hex","offset":436}]:
		if header.has(field.key):
			var raw := str(header[field.key]).hex_decode()
			for i in range(32): bytes[int(field.offset)+i] = raw[i] if i < raw.size() else 0
	for i in range(mini(25,header.get("event_variables_independent",[]).size())):
		bytes.encode_u16(40+i*2,int(header.event_variables_independent[i]) & 65535)
	for i in range(mini(8,header.get("system_time_words",[]).size())):
		bytes.encode_u16(90+i*2,int(header.system_time_words[i]) & 65535)
	for i in range(mini(80,header.get("inventory",[]).size())):
		bytes.encode_u16(112+i*4,int(header.inventory[i].id)&65535)
		bytes.encode_u16(114+i*4,int(header.inventory[i].quantity)&65535)
	for unit in save.units: bytes.append_array(unit)
	bytes.append_array(save.tail)
	return bytes

func save_game(index: int, combat, scenario, bgm: int = -1) -> Error:
	var saved: Dictionary
	if combat.source_index >= 0:
		saved = load_save(combat.source_index)
	else:
		saved = {"header":{},"header_raw":PackedByteArray(),"tail":PackedByteArray()}
	var state: Dictionary = scenario.snapshot_state()
	var header: Dictionary = saved.header
	header.stage = int(state.current_event); header.round_index = int(combat.round_index)
	header.event_variables_independent = state.variables.slice(0,25)
	header.title_cp949_raw_hex = encode_cp949(str(state.stage_title)).slice(0,31).hex_encode()
	header.battle_objective_cp949_raw_hex = encode_cp949(str(state.objective)).slice(0,31).hex_encode()
	header.money = int(combat.money); header.bgm = bgm
	header.inventory = []
	for i in range(80): header.inventory.append({"id":combat.inventory.decode_s16(i*4),"quantity":combat.inventory.decode_s16(i*4+2)})
	saved.units = combat.snapshot_units(); saved.tail = state.town_tail
	var stamp := Time.get_datetime_dict_from_system()
	header.system_time_words = [stamp.year,stamp.month,stamp.weekday,stamp.day,stamp.hour,stamp.minute,stamp.second,0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FT2Content.save_root()))
	var path := FT2Content.save_root().path_join("save%02d.dat" % index)
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_buffer(encode_save(saved)); file.close()
	var meta := FileAccess.open(path+".json",FileAccess.WRITE)
	if meta == null: return FileAccess.get_open_error()
	meta.store_string(JSON.stringify({"map_id":combat.map_id,"control_mode":state.control_mode}))
	return OK

static func source_s32(value: int) -> int:
	var bits := value & 0xFFFFFFFF
	return bits - 0x100000000 if bits >= 0x80000000 else bits

func source_cosine(radius: int, degrees: int) -> int:
	var table: Array = read_json("data/port_ready/effects/spec/fixed_trig_contract.json").quarter_wave_u16
	var angle := posmod(source_s32(degrees) + 90,360)-90
	if angle == 0: return source_s32(radius)
	if angle == 180: return source_s32(-radius)
	if angle <= 90: return source_s32(int(table[90-absi(angle)])*source_s32(radius)) >> 16
	return source_s32(-(source_s32(int(table[90-absi(angle-180)])*source_s32(radius)) >> 16))

func decode_unit(bytes: PackedByteArray, slot: int = -1) -> Dictionary:
	var out := {"slot":slot}
	for offset in U16_FIELDS:
		out[U16_FIELDS[offset]] = bytes.decode_u16(offset)
	for offset in S16_FIELDS:
		out[S16_FIELDS[offset]] = bytes.decode_s16(offset)
	for offset in S32_FIELDS:
		out[S32_FIELDS[offset]] = bytes.decode_s32(offset)
	for offset in U32_FIELDS:
		out[U32_FIELDS[offset]] = bytes.decode_u32(offset)
	if FT2Content.active.extensions!=null:
		var custom: Dictionary=FT2Content.active.extensions.character_by_race(int(out.definition_id))
		if not custom.is_empty():
			out["extension_id"]=custom.global_id
			if str(custom.get("name",""))!="":out["extension_name"]=str(custom.name)
	return out

func encode_unit(unit: Dictionary) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(124)
	out.fill(0)
	for offset in U16_FIELDS:
		out.encode_u16(offset, int(unit.get(U16_FIELDS[offset], 0)) & 0xFFFF)
	for offset in S16_FIELDS:
		out.encode_u16(offset, int(unit.get(S16_FIELDS[offset], 0)) & 0xFFFF)
	for offset in S32_FIELDS:
		out.encode_u32(offset, int(unit.get(S32_FIELDS[offset], 0)) & 0xFFFFFFFF)
	for offset in U32_FIELDS:
		out.encode_u32(offset, int(unit.get(U32_FIELDS[offset], 0)) & 0xFFFFFFFF)
	return out
