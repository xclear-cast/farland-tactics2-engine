extends RefCounted
## Private, in-memory original references. Never resolve through mod layers.
## Public methods return only editable fields, each as a caller-owned deep copy.

const STATS := ["hp","mp","atk","def","int","mdef","agi"]
var _characters: Dictionary = {}
var _skills: Dictionary = {}
var _error := "정품 게임을 연결하면 원본값을 볼 수 있습니다."

func configure(data) -> void:
	_characters.clear();_skills.clear()
	_error="정품 게임을 연결하면 원본값을 볼 수 있습니다."
	if data==null:return
	var directory=str(data.get("repo_root"))
	if directory.is_empty():return
	var races: Array=_rows(directory,"race")
	var magics: Array=_rows(directory,"magic")
	for index in races.size():
		var row=races[index]
		if not row is Dictionary:continue
		var stats: Dictionary={}
		for stat in STATS:
			var pair: Dictionary=row.get("stats",{}).get(stat,{})
			if pair.has("initial"):stats[stat+".initial"]=int(pair.initial)
			if pair.has("growth")or pair.has("increment_per_level"):stats[stat+".growth"]=int(pair.get("growth",pair.get("increment_per_level")))
		var skills: Array=[]
		for value in row.get("default_skill_slots4",[]):
			if int(value)>0:skills.append(int(value))
		var sprite:=""
		# RACE has no sprite field. This is the engine's same-number APD family,
		# confirmed against files in the pristine cache, not an original table value.
		for variant in ["E","A","B","V"]:
			var candidate:="CHAR_%02d%s"%[index,variant]
			if FileAccess.file_exists(directory.path_join("data/port_ready/assets/apd/animations/"+candidate+".json")):
				sprite=candidate;break
		_characters[index]={"id":index,"name":str(row.name)if row.get("name")!=null else "","base_race":index,"sprite":sprite,"level":1,"stats":stats,"skills":skills}
	for index in magics.size():
		var row=magics[index]
		if not row is Dictionary:continue
		var power:=int(row.get("power",0))
		for value in row.get("power_channels_signed",[]):
			if absi(int(value))>absi(power):power=int(value)
		_skills[index]={"id":index,"name":str(row.name)if row.get("name")!=null else "","base_skill":index,"visual_skill":index,"mp":int(row.get("mp",0)),"power":power,
			"range_min":int(row.get("target_distance_min_raw",row.get("v2",0))),"range_max":int(row.get("target_distance_max_raw",row.get("flag",0)))}
	_error="" if not _characters.is_empty() and not _skills.is_empty() else "정품 캐시의 원본 직업·스킬 표를 읽을 수 없습니다."

func _rows(directory: String,table: String) -> Array:
	var path:=directory.path_join("data/port_ready/tables/"+table+".dat.json")
	if not FileAccess.file_exists(path):return []
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK or not parser.data is Dictionary:return []
	var rows=parser.data.get("records",[])
	return rows.duplicate(true) if rows is Array else []

func status() -> Dictionary:
	return {"available":not _characters.is_empty() and not _skills.is_empty(),"character_count":_characters.size(),"skill_count":_skills.size(),"error":_error,
		"level_source":"authoring_default_not_original","sprite_source":"derived_same_number_apd_family"}

func character(race_id: int) -> Dictionary:return _characters.get(race_id,{}).duplicate(true)
func skill(skill_id: int) -> Dictionary:return _skills.get(skill_id,{}).duplicate(true)

func catalog(kind: String,search: String="") -> Array:
	var source: Dictionary=_characters if kind in ["characters","character","race"] else _skills if kind in ["skills","skill","magic"] else {}
	var result: Array=[]
	var query:=search.to_lower().replace("골렘","고렘")
	for id in source:
		var row: Dictionary=source[id]
		if str(row.name).is_empty()or str(row.name)=="결번":continue
		if source==_skills and int(id)==0:continue
		if query.is_empty()or (str(id)+" "+str(row.name)).to_lower().replace("골렘","고렘").contains(query):result.append(row.duplicate(true))
	return result
