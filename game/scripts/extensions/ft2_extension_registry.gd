class_name FT2ExtensionRegistry
extends RefCounted
## Declarative v2 definitions. Compiled rows live in RAM, never in the source cache.
var issues: Array[String] = []
var characters: Dictionary = {}
var skills: Dictionary = {}
var maps: Dictionary = {}
var stories: Dictionary = {}
var entry_story := ""
var base_race_count := 0
var base_skill_count := 0
var _race_rows: Array[PackedByteArray] = []
var _skill_rows: Array[PackedByteArray] = []
var _races_by_number: Dictionary = {}
var _skills_by_number: Dictionary = {}
var _maps_by_number: Dictionary = {}
var _compiled_characters: Dictionary = {}
var _base_magic: PackedByteArray
var _apds: Dictionary = {}
const STATS := ["hp","mp","atk","def","int","mdef","agi"]

func _identifier(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length()>64:return false
	for index in value.length():
		var character: String=value.substr(index,1)
		if not ((character>="a" and character<="z") or (character>="A" and character<="Z") or (character>="0" and character<="9") or character in ["_","-","."]):return false
	return true

func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and float(value)==int(value) and int(value)>=low and int(value)<=high

func resolve_id(value: Variant, pack_id: String = "") -> Variant:
	if value is int or value is float:return int(value)
	var text:=str(value)
	return text if text.contains(":") else pack_id+":"+text

func character(value: Variant) -> Dictionary:return characters.get(str(value),{})
func skill(value: Variant) -> Dictionary:return skills.get(str(value),{})
func character_race_id(value: Variant) -> int:return int(_compiled_characters.get(str(value),{}).get("numeric_id",-1))
func skill_action_id(value: Variant) -> int:return int(skills.get(str(value),{}).get("numeric_id",-1))
func map_id(value: Variant) -> int:return int(maps.get(str(value),{}).get("numeric_id",-1))
func map_by_id(value: int) -> Dictionary:return _maps_by_number.get(value,{})
func character_by_race(value: int) -> Dictionary:return _races_by_number.get(value,{})
func skill_by_action(value: int) -> Dictionary:return _skills_by_number.get(value,{})
func visual_skill(value: int) -> int:return int(_skills_by_number.get(value,{}).get("visual_skill",value))
func numeric_skill(value: int) -> int:return int(_skills_by_number.get(value,{}).get("base_skill",value))
func appearance_definition(value: int) -> int:return int(_races_by_number.get(value,{}).get("appearance_definition",value))

func load_layers(owner, base_races: PackedByteArray, base_magics: PackedByteArray, manifest: Dictionary) -> void:
	base_race_count=base_races.size()/86;base_skill_count=base_magics.size()/64
	_base_magic=base_magics.duplicate();_apds=manifest.get("apds",{})
	for layer in owner.layers:
		if int(layer.manifest.get("schema",1))!=2:continue
		var pack:=str(layer.id)
		if not _identifier(pack):issues.append("Invalid extension pack ID: "+pack);continue
		var relative:=str(layer.manifest.get("content","content.json"))
		var path: String=owner._inside(str(layer.root),relative)
		var document = JSON.parse_string(FileAccess.get_file_as_string(path)) if path!="" and FileAccess.file_exists(path) else null
		if not document is Dictionary or document.get("schema",0)!=1:
			issues.append("Invalid extension content.json: "+pack);continue
		for group in ["characters","skills","maps","stories"]:
			var definitions=document.get(group,[])
			if not definitions is Array:issues.append("Extension definitions must be arrays: "+group);continue
			for raw in definitions:
				if not raw is Dictionary or not _identifier(raw.get("id")):issues.append("Invalid extension definition ID: "+group);continue
				var global_id:=pack+":"+str(raw.id)
				var target: Dictionary=characters if group=="characters" else skills if group=="skills" else maps if group=="maps" else stories
				if target.has(global_id):issues.append("Duplicate extension ID: "+global_id);continue
				var descriptor: Dictionary=raw.duplicate(true)
				descriptor.pack_id=pack;descriptor.global_id=global_id
				target[global_id]=descriptor
		if layer.manifest.has("entry_story"):entry_story=str(resolve_id(layer.manifest.entry_story,pack))
	var skill_keys:=skills.keys();skill_keys.sort()
	if base_skill_count+skill_keys.size()>1000:issues.append("Too many skills: action IDs 1000+ are reserved for items");return
	for index in skill_keys.size():
		var descriptor: Dictionary=skills[skill_keys[index]]
		descriptor.numeric_id=base_skill_count+index
		if not _integer(descriptor.get("base_skill",1),1,base_skill_count-1) or not _integer(descriptor.get("visual_skill",descriptor.get("base_skill",1)),1,base_skill_count-1):
			issues.append("Invalid base/visual skill: "+str(descriptor.global_id));continue
		descriptor.base_skill=int(descriptor.get("base_skill",1));descriptor.visual_skill=int(descriptor.get("visual_skill",descriptor.base_skill))
		var bad_fields:=false
		for field in ["mp","power","range_min","range_max"]:
			if descriptor.has(field) and not _integer(descriptor[field],0 if field!="power" else -32768,32767):issues.append("Invalid skill field: "+str(descriptor.global_id)+"/"+field);bad_fields=true
		if bad_fields:continue
		if int(descriptor.get("range_min",0))>int(descriptor.get("range_max",32767)):issues.append("Skill minimum range exceeds maximum: "+str(descriptor.global_id))
		var row:=base_magics.slice(descriptor.base_skill*64,(descriptor.base_skill+1)*64)
		var visual:=base_magics.slice(descriptor.visual_skill*64,(descriptor.visual_skill+1)*64)
		if descriptor.has("power") and int(descriptor.power)==0 and (row.decode_s16(24)!=0 or row.decode_s16(26)!=0 or row.decode_s16(28)!=0):issues.append("Damage skill power must be nonzero: "+str(descriptor.global_id))
		for offset in range(34,48):row[offset]=visual[offset]
		if descriptor.has("power"):
			var channel:=0
			for index2 in range(1,3):
				if absi(row.decode_s16(24+index2*2))>absi(row.decode_s16(24+channel*2)):channel=index2
			for index2 in 3:row.encode_u16(24+index2*2,int(descriptor.power)&65535 if index2==channel else 0)
		for pair in [["mp",22],["range_min",30],["range_max",32]]:
			if descriptor.has(pair[0]):row.encode_u16(int(pair[1]),int(descriptor[pair[0]])&65535)
		row.encode_u16(52,0) # Explicit character skill lists; never alter original global learning masks.
		_skill_rows.append(row);_skills_by_number[int(descriptor.numeric_id)]=descriptor
	var map_keys:=maps.keys();map_keys.sort()
	for index in map_keys.size():
		var descriptor: Dictionary=maps[map_keys[index]];descriptor.numeric_id=10000+index
		if not _integer(descriptor.get("base_map",-1),0,9999) or not manifest.get("maps",{}).has(str(int(descriptor.get("base_map",-1)))):issues.append("Unavailable original base map: "+str(descriptor.global_id))
		_maps_by_number[int(descriptor.numeric_id)]=descriptor
	for key in characters:_compiled_characters[key]=characters[key]
	for key in maps:
		var definition: Dictionary=maps[key]
		if not definition.get("placements",[]) is Array:issues.append("Map placements must be an array: "+str(key));definition.placements=[];continue
		for index in definition.get("placements",[]).size():
			var placement=definition.placements[index]
			if not placement is Dictionary:issues.append("Invalid map placement: "+str(key));continue
			if not placement.has("character") and placement.has("sprite"):
				var internal:=str(key)+"/@placement"+str(index)
				_compiled_characters[internal]={"id":internal,"global_id":internal,"pack_id":definition.pack_id,"name":str(placement.get("name","")),"base_race":placement.get("race",1),"sprite":placement.sprite,"skills":placement.get("skills",[]),"stats":{}}
	var character_keys:=_compiled_characters.keys();character_keys.sort()
	if base_race_count+character_keys.size()>65535:issues.append("Too many character definitions");return
	for index in character_keys.size():
		var descriptor: Dictionary=_compiled_characters[character_keys[index]]
		descriptor.numeric_id=base_race_count+index
		if not _integer(descriptor.get("base_race",1),0,base_race_count-1):issues.append("Invalid base race: "+str(descriptor.global_id));continue
		descriptor.base_race=int(descriptor.get("base_race",1))
		if not _integer(descriptor.get("level",1),1,99):issues.append("Character level must be 1..99: "+str(descriptor.global_id))
		if str(descriptor.get("name","")).length()>128:issues.append("Character name exceeds 128 characters")
		var stem:=str(descriptor.get("sprite","CHAR_%02dA"%descriptor.base_race)).get_file().get_basename().to_upper()
		if not _apds.has(stem) or not stem.begins_with("CHAR_") or not stem.substr(5,stem.length()-6).is_valid_int():
			issues.append("Character sprite must reference an available original CHAR APD family: "+stem)
		descriptor.sprite=stem;descriptor.appearance_definition=int(stem.substr(5,stem.length()-6)) if stem.length()>6 else descriptor.base_race
		var row:=base_races.slice(descriptor.base_race*86,(descriptor.base_race+1)*86)
		var stats=descriptor.get("stats",{})
		if not stats is Dictionary:issues.append("Character stats must be an object");stats={}
		for field in stats:
			var parts:=str(field).split(".")
			if parts.size()!=2 or not parts[0] in STATS or not parts[1] in ["initial","growth"] or not _integer(stats[field],-32768,32767):
				issues.append("Invalid character stat: "+str(field));continue
			row.encode_u16(22+4*STATS.find(parts[0])+(2 if parts[1]=="growth" else 0),int(stats[field])&65535)
		if row.decode_s16(22)<=0 or row.decode_s16(26)<0:issues.append("Character requires positive HP and nonnegative MP: "+str(descriptor.global_id))
		var declared=descriptor.get("skills",[])
		if not declared is Array or declared.size()>10:issues.append("Character supports at most 10 skills: "+str(descriptor.global_id));declared=[]
		descriptor.skill_ids=[]
		for value in declared:
			if (value is int or value is float) and not _integer(value,1,base_skill_count-1):issues.append("Invalid original skill reference: "+str(value));continue
			var reference=resolve_id(value,str(descriptor.pack_id))
			var identity:=int(reference) if reference is int else skill_action_id(reference)
			if identity<=0 or identity>=base_skill_count+skills.size() or (reference is int and identity>=base_skill_count):issues.append("Unregistered character skill: "+str(value))
			else:descriptor.skill_ids.append(identity)
		_race_rows.append(row);_races_by_number[int(descriptor.numeric_id)]=descriptor
	for key in maps:
		var definition: Dictionary=maps[key]
		for placement in definition.get("placements",[]):
			if not placement is Dictionary:continue
			if placement.has("character"):
				var reference:=str(resolve_id(placement.character,str(definition.pack_id)))
				if not characters.has(reference):issues.append("Unregistered map character: "+reference)
	for key in stories:
		var nodes=stories[key].get("nodes",[])
		if not nodes is Array:issues.append("Story nodes must be an array: "+str(key));stories[key].nodes=[];continue
		for node in nodes:
			if node is Dictionary and str(node.get("type",""))=="battle":
				var reference:=str(resolve_id(node.get("map",""),str(stories[key].pack_id)))
				if not maps.has(reference):issues.append("Unregistered story map: "+reference)
	if entry_story!="" and not stories.has(entry_story):issues.append("Unregistered entry story: "+entry_story)
	_validate_structure()

func _validate_structure() -> void:
	for key in maps:
		var definition: Dictionary=maps[key]
		if not _integer(definition.get("width",8),1,64) or not _integer(definition.get("height",8),1,64):issues.append("Map dimensions must be 1..64: "+str(key));continue
		var width:=int(definition.get("width",8));var height:=int(definition.get("height",8))
		var cells=definition.get("cells",[])
		if not cells is Array:issues.append("Map cells must be an array: "+str(key));continue
		var seen: Dictionary={}
		for cell in cells:
			if not cell is Dictionary:issues.append("Invalid map cell: "+str(key));continue
			if not _integer(cell.get("x"),1,width) or not _integer(cell.get("y"),1,height) or not _integer(cell.get("height",0),-32768,32767) or not _integer(cell.get("terrain",1),0,7):issues.append("Invalid map cell coordinates/height/terrain: "+str(key));continue
			var point:=Vector2i(int(cell.x),int(cell.y))
			if seen.has(point):issues.append("Duplicate map cell: "+str(key))
			seen[point]=true
		var ally_count:=0;var npc_count:=0
		for placement in definition.get("placements",[]):
			if not placement is Dictionary:continue
			if not _integer(placement.get("x",1),1,width) or not _integer(placement.get("y",1),1,height) or not _integer(placement.get("level",1),1,99):issues.append("Invalid map placement coordinates/level: "+str(key))
			var side:=str(placement.get("side","ally"))
			if side=="ally":ally_count+=1
			elif side in ["enemy","neutral"]:npc_count+=1
			else:issues.append("Invalid map placement side: "+str(key))
			if not placement.has("character") and not _integer(placement.get("race",1),0,base_race_count-1):issues.append("Invalid original placement race")
		if ally_count>10 or npc_count>40:issues.append("Map supports at most 10 allies and 40 NPC/enemy slots")
	for key in stories:
		var definition: Dictionary=stories[key]
		var nodes=definition.get("nodes",[])
		if not nodes is Array:continue
		var ids: Dictionary={}
		for node in nodes:
			if not node is Dictionary or not _identifier(node.get("id")):issues.append("Invalid story node ID: "+str(key));continue
			if ids.has(str(node.id)):issues.append("Duplicate story node ID: "+str(key))
			ids[str(node.id)]=true
		if not ids.has(str(definition.get("start",""))):issues.append("Story start node is missing: "+str(key))
		for node in nodes:
			if not node is Dictionary:continue
			var type:=str(node.get("type",""))
			if not type in ["dialogue","battle","branch","set","end"]:issues.append("Unknown story node type: "+type);continue
			var links: Array=[]
			if type=="branch":
				var choices=node.get("choices",[])
				if not choices is Array:issues.append("Branch choices must be an array");continue
				if not choices.is_empty():
					for choice in choices:
						if not choice is Dictionary or not choice.get("set",{}) is Dictionary:issues.append("Invalid branch choice");continue
						links.append(str(choice.get("next","")))
				else:links.append(str(node.get("then","")));links.append(str(node.get("else","")))
			elif type!="end":links.append(str(node.get("next","")))
			if type=="battle" and node.has("on_defeat"):links.append(str(node.on_defeat))
			if type=="dialogue" and str(node.get("speaker","")).contains(":"):
				if not characters.has(str(node.speaker)):issues.append("Unknown namespaced dialogue speaker")
			for link in links:
				if not ids.has(link):issues.append("Story link target missing: "+str(key)+"/"+link)

func append_table_rows(table: String, raw: PackedByteArray) -> PackedByteArray:
	var result:=raw.duplicate()
	for row in (_race_rows if table=="race" else _skill_rows if table=="magic" else []):result.append_array(row)
	return result

func display_record(table: String, index: int, row: Dictionary) -> Dictionary:
	var definition: Dictionary=character_by_race(index) if table=="race" else skill_by_action(index) if table=="magic" else {}
	if not definition.is_empty():
		row["extension_id"]=definition.global_id
		if str(definition.get("name",""))!="":row.name=str(definition.name)
		if table=="magic" and definition.has("power"):row.power=int(definition.power)
	return row

func sprite_alias(stem: String) -> String:
	var value:=stem.get_file().get_basename().to_upper()
	if not value.begins_with("CHAR_") or value.length()<7:return stem
	var digits:=value.substr(5,value.length()-6)
	if not digits.is_valid_int():return stem
	var definition:=character_by_race(int(digits))
	if definition.is_empty():return stem
	var requested:="CHAR_%02d%s"%[int(definition.appearance_definition),value.right(1)]
	return requested if _apds.has(requested) else str(definition.sprite)

func numeric_table(action: int, current: PackedByteArray) -> PackedByteArray:
	var descriptor:=skill_by_action(action)
	if descriptor.is_empty():return current
	var base:=int(descriptor.base_skill)
	var result:=current.duplicate()
	var row:=current.slice(action*64,(action+1)*64)
	# MP cost is independent of the inherited physical/magical damage category.
	var original_mp:=_base_magic.decode_s16(base*64+22)
	row.encode_u16(22,((-1 if original_mp<=0 else 1)*maxi(1,absi(row.decode_s16(22))))&65535)
	for index in 64:result[base*64+index]=row[index]
	return result

func spawn_placements(definition: Dictionary, battle) -> Dictionary:
	var units: Array=[];var slots: Dictionary={};var instances: Dictionary={};var random: Array=battle.rng.duplicate();var errors: Array[String]=[]
	for index in 50:
		var empty:=PackedByteArray();empty.resize(124);empty.fill(0);units.append(empty)
	var placements=definition.get("placements",[])
	for index in placements.size():
		var placement: Dictionary=placements[index]
		var reference:=str(resolve_id(placement.get("character",""),str(definition.pack_id))) if placement.has("character") else str(definition.global_id)+"/@placement"+str(index)
		var character_definition: Dictionary=_compiled_characters.get(reference,{})
		var race:=int(character_definition.get("numeric_id",placement.get("race",1)))
		var side:=str(placement.get("side","ally"))
		if side not in ["ally","enemy","neutral"]:errors.append("Invalid placement side");continue
		if race<0 or race>=battle.rules.races.size()/86:errors.append("Invalid placement race");continue
		var skills_list: Array=character_definition.get("skill_ids",[])
		var level_value=placement.get("level",character_definition.get("level",1))
		if not _integer(level_value,1,99):errors.append("Placement level must be 1..99");continue
		if not _integer(placement.get("x",1),1,int(definition.get("width",8))) or not _integer(placement.get("y",1),1,int(definition.get("height",8))):errors.append("Placement is outside map bounds");continue
		# Keep every custom kind distinct while selecting learning-mask bit31,
		# outside the original 16-bit hero masks. Level-ups preserve own skills.
		var descriptor: Dictionary={"kind":32768+index*32,"definition_id":race,"level":int(level_value),
			"direction":int(placement.get("direction",0)),"x":int(placement.get("x",1)),"y":int(placement.get("y",1)),"state":0,"control":0 if side=="ally" else 2 if side=="enemy" else 1,
			"weapon":int(placement.get("weapon",0)),"armor":int(placement.get("armor",0))}
		var raw: PackedByteArray=battle.data.encode_unit(descriptor)
		var built: Dictionary=battle.rules.construct(units,raw,random)
		if int(built.slot)<0:errors.append("No free placement slot");continue
		units=built.units;random=built.seeds
		var slot:=int(built.slot)
		units[slot].encode_u32(92,0);units[slot].encode_u32(96,0)
		if not character_definition.is_empty():
			for skill_index in 10:units[slot].encode_u16(56+skill_index*2,int(skills_list[skill_index]) if skill_index<skills_list.size() else 0)
			if not slots.has(reference):slots[reference]=slot
			if not instances.has(reference):instances[reference]=[]
			instances[reference].append(slot)
	return {"units":units,"character_slots":slots,"character_instances":instances,"rng":random,"issues":errors}
