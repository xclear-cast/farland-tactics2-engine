class_name FT2ExpansionProject
extends RefCounted
## Authoring-only model. Export descriptors, never copy the user's game/cache.

var descriptor: Dictionary = {}
var content: Dictionary = {}
var folder := ""
const Baseline=preload("res://scripts/editor/ft2_editor_baseline.gd")
var _baseline=Baseline.new()
var _source_data
var source_data:
	get:return _source_data
	set(value):
		_source_data=value
		_baseline.configure(value)
var issues: Array[String] = []

const KINDS := ["characters","skills","maps","stories"]
const NODE_TYPES := ["dialogue","battle","branch","set","end"]
const STAT_NAMES := ["hp","mp","atk","def","int","mdef","agi"]

func _init() -> void: new_project()

func baseline_status() -> Dictionary:return _baseline.status()
func original_character(race_id: int) -> Dictionary:return _baseline.character(race_id)
func original_skill(skill_id: int) -> Dictionary:return _baseline.skill(skill_id)
func original_catalog(kind: String,search: String="") -> Array:return _baseline.catalog(kind,search)

func character_defaults(record: Dictionary) -> Dictionary:
	var defaults:=original_character(int(record.get("base_race",-1)))
	if defaults.is_empty():return {}
	defaults.id=record.get("id",defaults.id)
	# Level is an instance setting, absent from the original RACE table.
	defaults.level=record.get("level",1)
	return defaults

func skill_defaults(record: Dictionary) -> Dictionary:
	var defaults:=original_skill(int(record.get("base_skill",-1)))
	if defaults.is_empty():return {}
	defaults.id=record.get("id",defaults.id)
	return defaults

func _baseline_kind(kind: String) -> String:
	return "characters" if kind in ["character","characters","race"] else "skills" if kind in ["skill","skills","magic"] else ""

func _baseline_record(kind: String,index: int) -> Dictionary:
	if kind.is_empty()or index<0 or index>=content.get(kind,[]).size():return {}
	return content[kind][index]

func reset_record(kind: String,index: int) -> Dictionary:
	kind=_baseline_kind(kind)
	var record:=_baseline_record(kind,index)
	if record.is_empty():return {"ok":false,"error":"초기화할 항목을 선택하세요."}
	var defaults:=character_defaults(record)if kind=="characters"else skill_defaults(record)
	if defaults.is_empty():return {"ok":false,"error":"정품 원본값이 없습니다. 먼저 게임을 연결하세요."}
	# A sparse override inherits numeric values from the referenced original row.
	if kind=="characters":defaults.stats={}
	update_record(kind,index,defaults)
	return {"ok":true,"record":defaults.duplicate(true)}

func reset_field(kind: String,index: int,key: String) -> Dictionary:
	kind=_baseline_kind(kind)
	var record:=_baseline_record(kind,index)
	if record.is_empty():return {"ok":false,"error":"초기화할 항목을 선택하세요."}
	var defaults:=character_defaults(record)if kind=="characters"else skill_defaults(record)
	if defaults.is_empty():return {"ok":false,"error":"정품 원본값이 없습니다. 먼저 게임을 연결하세요."}
	if key in ["id","base_race","base_skill","level"]:return {"ok":false,"error":"ID·원본 참조·레벨은 원본값 초기화 대상이 아닙니다."}
	var changed:=record.duplicate(true)
	if kind=="characters"and (key.begins_with("stats.")or key.split(".").size()==2):
		var stat:=key.trim_prefix("stats.")
		if not defaults.stats.has(stat):return {"ok":false,"error":"원본 능력치 필드가 없습니다."}
		var stats: Dictionary=changed.get("stats",{}).duplicate(true);stats.erase(stat);changed.stats=stats
	elif defaults.has(key):changed[key]={}if key=="stats"else defaults[key].duplicate(true)if defaults[key]is Dictionary or defaults[key]is Array else defaults[key]
	else:return {"ok":false,"error":"원본 필드가 없습니다: "+key}
	update_record(kind,index,changed)
	return {"ok":true,"record":changed.duplicate(true)}

func changed_fields(kind: String,index: int) -> Array[String]:
	kind=_baseline_kind(kind)
	var record:=_baseline_record(kind,index)
	var changed: Array[String]=[]
	if record.is_empty():return changed
	var defaults:=character_defaults(record)if kind=="characters"else skill_defaults(record)
	if defaults.is_empty():return changed
	for key in defaults:
		if key in ["id","base_race","base_skill","level"]:continue
		if key=="stats":
			for stat in record.get("stats",{}):
				if not _same_value(record.stats[stat],defaults.stats.get(stat)):changed.append("stats."+str(stat))
		elif not _same_value(record.get(key,defaults[key]),defaults[key]):changed.append(str(key))
	return changed

func _same_value(left: Variant,right: Variant) -> bool:
	# JSON parses numbers as floats; 1 and 1.0 still represent the same default.
	if (left is int or left is float)and(right is int or right is float):return left==right
	if left is Array and right is Array:
		if left.size()!=right.size():return false
		for index in left.size():
			if not _same_value(left[index],right[index]):return false
		return true
	if left is Dictionary and right is Dictionary:
		if left.size()!=right.size():return false
		for key in left:
			if not right.has(key)or not _same_value(left[key],right[key]):return false
		return true
	return left==right

func new_project() -> void:
	descriptor={"schema":2,"id":"my_expansion","name":"나의 첫 확장팩","version":"1.0","content":"content.json","entry_story":"intro"}
	content={"schema":1,"characters":[
		{"id":"hero","name":"새 주인공","base_race":1,"sprite":"CHAR_00E","level":5,"stats":{"hp.initial":50,"atk.initial":40,"def.initial":8,"mp.initial":30},"skills":["spark"]},
		{"id":"enemy","name":"연습 상대","base_race":1,"sprite":"CHAR_00E","level":1,"stats":{"hp.initial":18,"atk.initial":8,"def.initial":3},"skills":[]}],
		"skills":[{"id":"spark","name":"나의 불꽃","base_skill":1,"visual_skill":1,"mp":3,"power":12,"range_min":1,"range_max":3}],
		"maps":[{"id":"field","name":"나의 연습장","base_map":40,"width":8,"height":8,"cells":[],"placements":[
			{"character":"hero","side":"ally","x":2,"y":2,"level":5},
			{"character":"enemy","side":"enemy","x":3,"y":2,"level":1}]}],
		"stories":[{"id":"intro","start":"hello","nodes":[
			{"id":"hello","type":"dialogue","speaker":"hero","text":"이곳에서 새로운 모험을 시작합니다.","next":"ready"},
			{"id":"ready","type":"set","variable":"ready","value":1,"next":"check"},
			{"id":"check","type":"branch","variable":"ready","equals":1,"then":"fight","else":"lost"},
			{"id":"fight","type":"battle","map":"field","next":"won","on_defeat":"lost"},
			{"id":"won","type":"dialogue","speaker":"hero","text":"첫 번째 연습을 마쳤습니다!","next":"ending"},
			{"id":"lost","type":"dialogue","speaker":"hero","text":"다시 준비해서 도전해 봅시다.","next":"ending"},
			{"id":"ending","type":"end"}]}]}
	folder="";issues.clear()

static func valid_id(value: String) -> bool:
	if value.is_empty() or value.length()>64: return false
	for index in value.length():
		var code:=value.unicode_at(index)
		if not(code>=48 and code<=57 or code>=65 and code<=90 or code>=97 and code<=122 or code in [45,95]): return false
	return true

func next_id(kind: String, prefix: String) -> String:
	var names := {}
	for row in content.get(kind,[]): names[str(row.get("id",""))]=true
	var number:=1
	while names.has(prefix+str(number)): number+=1
	return prefix+str(number)

func local_id(value: Variant) -> String:
	var text:=str(value)
	return text.trim_prefix(str(descriptor.get("id",""))+":")

func has_id(kind: String, value: Variant) -> bool:
	var key:=local_id(value)
	if key.contains(":"):
		var parts:=key.split(":")
		return parts.size()==2 and valid_id(parts[0]) and valid_id(parts[1]) # Dependency availability is checked by runtime registry.
	for row in content.get(kind,[]):
		if str(row.get("id",""))==key:return true
	return false

func update_record(kind: String, index: int, record: Dictionary) -> void:
	if not kind in KINDS:return
	var rows: Array=content[kind]
	if index>=0 and index<rows.size():
		var old:=str(rows[index].get("id",""));rows[index]=record.duplicate(true)
		if old!=str(record.get("id","")):_rename_references(kind,old,str(record.get("id","")))
	else:rows.append(record.duplicate(true))

func remove_record(kind: String,index: int) -> void:
	if kind in KINDS and index>=0 and index<content[kind].size():content[kind].remove_at(index)

func _replace_reference(value: Variant, old: String, replacement: String) -> Variant:
	if value is String:
		if value==old:return replacement
		if value==str(descriptor.id)+":"+old:return str(descriptor.id)+":"+replacement
	return value

func _rename_references(kind: String,old: String,replacement: String) -> void:
	if kind=="skills":
		for character in content.characters:
			for i in range(character.get("skills",[]).size()):character.skills[i]=_replace_reference(character.skills[i],old,replacement)
	if kind=="characters":
		for map in content.maps:
			for spawn in map.get("placements",[]):
				if spawn.has("character"):spawn.character=_replace_reference(spawn.character,old,replacement)
	for story in content.stories:
		for node in story.get("nodes",[]):
			if kind=="characters" and node.has("speaker"):node.speaker=_replace_reference(node.speaker,old,replacement)
			if kind=="maps" and node.has("map"):node.map=_replace_reference(node.map,old,replacement)
	if kind=="stories":descriptor.entry_story=_replace_reference(descriptor.get("entry_story",""),old,replacement)

func rename_node(story: Dictionary,old: String,replacement: String) -> void:
	if str(story.get("start",""))==old:story.start=replacement
	for node in story.get("nodes",[]):
		for key in ["next","on_defeat","then","else"]:
			if str(node.get(key,""))==old:node[key]=replacement
		for choice in node.get("choices",[]):
			if str(choice.get("next",""))==old:choice.next=replacement

func _issue(message: String) -> void:issues.append(message)

func _integer(value: Variant,minimum: int,maximum: int) -> bool:
	return (value is int or value is float) and float(value)==int(value) and int(value)>=minimum and int(value)<=maximum

func _keys(record: Dictionary,allowed: Array,label: String) -> void:
	for key in record:
		if not str(key)in allowed:_issue(label+"지원하지 않는 필드: "+str(key))

func _original_count(table: String) -> int:
	var count:=int(_baseline.status().get("character_count"if table=="race"else"skill_count",0))
	if count>0:return count
	return 74 if table=="race" else 84

func validate_project() -> Dictionary:
	issues.clear()
	if int(descriptor.get("schema",0))!=2:_issue("mod.json의 확장팩 형식은 schema 2여야 합니다.")
	_keys(descriptor,["schema","id","name","version","content","entry_story","files","patches","table_edits"],"프로젝트: ")
	if not valid_id(str(descriptor.get("id",""))):_issue("프로젝트 ID는 영문·숫자·밑줄·하이픈으로 작성하세요.")
	if str(descriptor.get("name","")).strip_edges().is_empty():_issue("확장팩 이름을 입력하세요.")
	if str(descriptor.get("version","")).strip_edges().is_empty():_issue("버전을 입력하세요.")
	if str(descriptor.get("content",""))!="content.json":_issue("이 제작기는 content.json 정의 파일을 사용합니다.")
	if int(content.get("schema",0))!=1:_issue("content.json 형식은 schema 1이어야 합니다.")
	_keys(content,["schema","characters","skills","maps","stories"],"확장 정의: ")
	for field in ["files","patches","table_edits"]:
		if descriptor.has(field):
			var value=descriptor[field]
			if not(value is Array or value is Dictionary):_issue("기존 레이어 형식 오류: "+field)
			elif not value.is_empty():_issue("이 제작기는 확장 정의를 내보냅니다. 기존 "+field+" 레이어는 별도 프로젝트로 보관하세요.")
	for kind in KINDS:
		if not content.get(kind) is Array:_issue("목록 형식 오류: "+kind);continue
		var used: Dictionary={}
		for row in content[kind]:
			if not row is Dictionary:_issue("항목 형식 오류: "+kind);continue
			var id:=str(row.get("id",""))
			if not valid_id(id):_issue("올바르지 않은 ID: "+kind+" / "+id)
			elif used.has(id):_issue("중복 ID: "+kind+" / "+id)
			used[id]=true
	if not issues.is_empty():return {"ok":false,"issues":issues.duplicate()}
	for row in content.characters:
		var label: String="캐릭터 "+str(row.id)+": "
		_keys(row,["id","name","base_race","sprite","level","stats","skills"],label)
		if str(row.get("name","")).strip_edges().is_empty():_issue(label+"이름이 없습니다.")
		if str(row.get("name","")).length()>128:_issue(label+"이름은 128자 이내로 입력하세요.")
		if not _integer(row.get("base_race",-1),0,_original_count("race")-1):_issue(label+"존재하는 원작 기반 직업 ID를 선택하세요.")
		if str(row.get("sprite","")).is_empty() or str(row.sprite).contains("/") or str(row.sprite).contains("\\") or str(row.sprite).contains(":"):_issue(label+"APD 이름만 입력하세요. 파일 경로는 사용할 수 없습니다.")
		if not _integer(row.get("level",0),1,99):_issue(label+"레벨은 1~99 정수여야 합니다.")
		if not row.get("stats",{}) is Dictionary:_issue(label+"능력치 형식 오류")
		else:
			for key in row.get("stats",{}):
				var parts:=str(key).split(".")
				if parts.size()!=2 or not parts[0]in STAT_NAMES or not parts[1]in ["initial","growth"]:_issue(label+"능력치 필드 오류: "+str(key))
				elif not _integer(row.stats[key],-32768,32767):_issue(label+"능력치는 -32768~32767 정수입니다.")
				elif str(key)=="hp.initial"and int(row.stats[key])<1:_issue(label+"HP 기본값은 1 이상이어야 합니다.")
				elif str(key)=="mp.initial"and int(row.stats[key])<0:_issue(label+"MP 기본값은 0 이상이어야 합니다.")
		if not row.get("skills",[]) is Array:_issue(label+"스킬 목록 형식 오류")
		else:
			if row.get("skills",[]).size()>10:_issue(label+"스킬은 최대 10개입니다.")
			for skill in row.get("skills",[]):
				if skill is String and not has_id("skills",skill):_issue(label+"존재하지 않는 스킬: "+str(skill))
				elif not skill is String and not _integer(skill,1,_original_count("magic")-1):_issue(label+"원작 스킬 ID 범위 오류")
	for row in content.skills:
		var label: String="스킬 "+str(row.id)+": "
		_keys(row,["id","name","base_skill","visual_skill","mp","power","range_min","range_max"],label)
		if str(row.get("name","")).strip_edges().is_empty():_issue(label+"이름이 없습니다.")
		if not _integer(row.get("base_skill",0),1,_original_count("magic")-1)or not _integer(row.get("visual_skill",0),1,_original_count("magic")-1):_issue(label+"존재하는 원작 기반/연출 스킬을 선택하세요.")
		if str(row.get("name","")).length()>128:_issue(label+"이름은 128자 이내로 입력하세요.")
		if not _integer(row.get("mp",-1),0,32767):_issue(label+"MP 소비는 0~32767 정수입니다.")
		if not _integer(row.get("power",0),-32768,32767):_issue(label+"위력은 -32768~32767 정수입니다.")
		elif int(row.get("power",0))==0:
			var original:=original_skill(int(row.get("base_skill",-1)))
			if original.is_empty()or int(original.get("power",0))!=0:_issue(label+"공격 스킬 위력은 0일 수 없습니다.")
		if int(row.get("range_min",0))<0 or int(row.get("range_max",0))<int(row.get("range_min",0)):_issue(label+"최대 거리는 최소 거리 이상이어야 합니다.")
	for row in content.maps:
		var label: String="맵 "+str(row.id)+": "
		_keys(row,["id","name","base_map","width","height","cells","placements"],label)
		var width:=int(row.get("width",0));var height:=int(row.get("height",0))
		if not _integer(row.get("width",0),1,64)or not _integer(row.get("height",0),1,64):_issue(label+"맵 크기는 각 1~64칸입니다.")
		if int(row.get("base_map",-1))<0:_issue(label+"원작 타일을 참조할 기반 맵을 선택하세요.")
		if not row.get("cells",[]) is Array or not row.get("placements",[]) is Array:_issue(label+"격자/배치 형식 오류");continue
		var cell_keys: Dictionary={};var occupied: Dictionary={};var ally_count:=0;var enemy_count:=0
		for cell in row.get("cells",[]):
			if not cell is Dictionary:_issue(label+"칸 형식 오류");continue
			_keys(cell,["x","y","height","terrain"],label)
			var x:=int(cell.get("x",0));var y:=int(cell.get("y",0));var key: String="%d,%d"%[x,y]
			if not _integer(cell.get("x",0),1,width)or not _integer(cell.get("y",0),1,height):_issue(label+"칸 좌표 범위 오류: "+key)
			if cell_keys.has(key):_issue(label+"중복 칸: "+key)
			cell_keys[key]=true
			if not _integer(cell.get("terrain",1),0,7):_issue(label+"지형은 0~7입니다.")
			if not _integer(cell.get("height",0),-32768,32767):_issue(label+"높이는 -32768~32767 정수입니다.")
		for spawn in row.get("placements",[]):
			if not spawn is Dictionary:_issue(label+"배치 형식 오류");continue
			_keys(spawn,["character","race","sprite","side","x","y","level"],label)
			var x:=int(spawn.get("x",0));var y:=int(spawn.get("y",0));var key: String="%d,%d"%[x,y]
			if not _integer(spawn.get("x",0),1,width)or not _integer(spawn.get("y",0),1,height):_issue(label+"배치 좌표 범위 오류: "+key)
			if not _integer(spawn.get("level",1),1,99):_issue(label+"배치 레벨은 1~99 정수입니다.")
			if occupied.has(key):_issue(label+"같은 칸에 두 캐릭터가 배치되어 있습니다: "+key)
			occupied[key]=true
			if spawn.has("character") and not has_id("characters",spawn.character):_issue(label+"없는 캐릭터: "+str(spawn.character))
			elif not spawn.has("character") and not spawn.has("race"):_issue(label+"배치할 캐릭터를 선택하세요.")
			var side:=str(spawn.get("side",""))
			if side=="ally":ally_count+=1
			elif side=="enemy":enemy_count+=1
			else:_issue(label+"진영은 ally 또는 enemy입니다.")
		if ally_count>10 or enemy_count>40:_issue(label+"한 전투는 아군 10명·적군 40명까지 지원합니다.")
	for story in content.stories:_validate_story(story)
	if not str(descriptor.get("entry_story","")).is_empty() and not has_id("stories",descriptor.entry_story):_issue("시작 스토리를 찾을 수 없습니다.")
	return {"ok":issues.is_empty(),"issues":issues.duplicate()}

func _validate_story(story: Dictionary) -> void:
	var label: String="스토리 "+str(story.id)+": "
	_keys(story,["id","start","nodes"],label)
	if not story.has("nodes")or not story.get("nodes") is Array:_issue(label+"노드 목록 형식 오류");return
	var ids: Dictionary={}
	for node in story.nodes:
		if not node is Dictionary:_issue(label+"노드 형식 오류");continue
		var id:=str(node.get("id",""))
		if not valid_id(id) or ids.has(id):_issue(label+"노드 ID 오류/중복: "+id)
		ids[id]=true
	if not ids.has(str(story.get("start",""))):_issue(label+"시작 노드가 없습니다.")
	for node in story.nodes:
		if not node is Dictionary:continue
		_keys(node,["id","type","speaker","text","next","map","on_defeat","variable","value","equals","then","else","choices"],label)
		var type:=str(node.get("type",""))
		if not type in NODE_TYPES:_issue(label+"지원하지 않는 노드: "+type);continue
		if type=="dialogue" and str(node.get("text","")).strip_edges().is_empty():_issue(label+str(node.id)+" 대사를 입력하세요.")
		if type=="battle" and not has_id("maps",node.get("map","")):_issue(label+"없는 전투 맵: "+str(node.get("map","")))
		var choices=node.get("choices",[])
		if not choices is Array:_issue(label+"선택지 목록 형식 오류");choices=[]
		if (type=="set" or type=="branch"and choices.is_empty()) and str(node.get("variable","")).is_empty():_issue(label+"변수 이름을 입력하세요.")
		var links: Array=[]
		if type in ["dialogue","set"]:links.append(node.get("next",""))
		elif type=="battle":links.append(node.get("next",""));links.append(node.get("on_defeat",""))
		elif type=="branch":
			if not choices.is_empty():
				for choice in choices:
					if choice is Dictionary:links.append(choice.get("next",""))
					else:_issue(label+"선택지 형식 오류")
			else:links.append(node.get("then",""));links.append(node.get("else",""))
		for target in links:
			if not str(target).is_empty() and not ids.has(str(target)):_issue(label+"연결할 노드를 찾을 수 없습니다: "+str(target))

func _safe_output(path: String) -> bool:
	var absolute:=ProjectSettings.globalize_path(path).replace("\\","/").simplify_path().trim_suffix("/")
	if absolute.is_empty() or not absolute.is_absolute_path():return false
	var candidates: Array=[]
	if source_data!=null:
		for key in ["source_root","repo_root"]:
			var value=source_data.get(key)
			if value is String and not value.is_empty():candidates.append(value)
	if FT2Content.active!=null:candidates.append(FT2Content.active.source);candidates.append(FT2Content.active.root)
	for value in candidates:
		var protected:=ProjectSettings.globalize_path(str(value)).replace("\\","/").simplify_path().trim_suffix("/")
		if protected.is_empty():continue
		if absolute.nocasecmp_to(protected)==0 or absolute.to_lower().begins_with(protected.to_lower()+"/"):return false
	var ancestor:=absolute
	while not ancestor.is_empty():
		var parent:=ancestor.get_base_dir()
		var parent_dir:=DirAccess.open(parent)
		if parent_dir!=null and parent_dir.is_link(ancestor.get_file()):return false
		var directory:=DirAccess.open(ancestor)
		if directory!=null:
			for name in directory.get_files():
				if name.nocasecmp_to("FTO_O.EXE")==0:return false
		if parent==ancestor:break
		ancestor=parent
	return true

func save_project(path: String) -> Dictionary:
	if not _safe_output(path):return {"ok":false,"error":"원작과 캐시 밖의 새 프로젝트 폴더를 선택하세요."}
	var absolute:=ProjectSettings.globalize_path(path).simplify_path()
	var error:=DirAccess.make_dir_recursive_absolute(absolute)
	if error!=OK:return {"ok":false,"error":"프로젝트 폴더를 만들 수 없습니다."}
	var names: Array[String]=["mod.json","content.json"]
	for pair in [["mod.json",descriptor],["content.json",content]]:
		var target:=absolute.path_join(str(pair[0]));var temporary:=target+".writing"
		var directory:=DirAccess.open(absolute)
		if directory.is_link(str(pair[0])) or directory.is_link(str(pair[0])+".writing"):return {"ok":false,"error":"링크가 아닌 실제 프로젝트 파일에 저장하세요."}
		var file:=FileAccess.open(temporary,FileAccess.WRITE)
		if file==null:return {"ok":false,"error":"프로젝트 파일을 저장할 수 없습니다: "+str(pair[0])}
		file.store_string(JSON.stringify(pair[1],"\t"));file.close()
	var backups: Array[String]=[]
	var committed: Array[String]=[]
	for name in names:
		var target:=absolute.path_join(name)
		if FileAccess.file_exists(target):
			var previous:=target+".previous"
			if FileAccess.file_exists(previous)and DirAccess.remove_absolute(previous)!=OK:
				_restore_files(absolute,backups,committed);return {"ok":false,"error":"이전 백업 파일을 갱신할 수 없습니다."}
			if DirAccess.rename_absolute(target,previous)!=OK:
				_restore_files(absolute,backups,committed);return {"ok":false,"error":"기존 프로젝트 파일을 보존할 수 없습니다."}
			backups.append(name)
	for name in names:
		if DirAccess.rename_absolute(absolute.path_join(name+".writing"),absolute.path_join(name))!=OK:
			_restore_files(absolute,backups,committed);return {"ok":false,"error":"프로젝트 저장을 완료하지 못해 이전 파일을 복원했습니다."}
		committed.append(name)
	folder=absolute
	return {"ok":true,"folder":absolute}

func _restore_files(directory: String,backups: Array[String],committed: Array[String]) -> void:
	for name in committed:
		var target:=directory.path_join(name)
		if FileAccess.file_exists(target):DirAccess.remove_absolute(target)
	for name in backups:
		var target:=directory.path_join(name)
		if not FileAccess.file_exists(target):DirAccess.rename_absolute(target+".previous",target)

func load_project(path: String) -> Dictionary:
	var absolute:=ProjectSettings.globalize_path(path).simplify_path()
	var documents: Array=[]
	for name in ["mod.json","content.json"]:
		var target:=absolute.path_join(name)
		if not FileAccess.file_exists(target):return {"ok":false,"error":"프로젝트 파일이 없습니다: "+name}
		if FileAccess.get_file_as_bytes(target).size()>8*1024*1024:return {"ok":false,"error":"프로젝트 정의가 너무 큽니다."}
		var parser:=JSON.new()
		if parser.parse(FileAccess.get_file_as_string(target))!=OK or not parser.data is Dictionary:return {"ok":false,"error":"JSON 형식이 올바르지 않습니다: "+name}
		documents.append(parser.data)
	if int(documents[0].get("schema",0))!=2 or int(documents[1].get("schema",0))!=1:return {"ok":false,"error":"확장팩 제작기 v2 형식의 프로젝트를 선택하세요."}
	if str(documents[0].get("content",""))!="content.json":return {"ok":false,"error":"프로젝트 content 파일은 content.json이어야 합니다."}
	descriptor=documents[0];content=documents[1];folder=absolute
	for kind in KINDS:
		if not content.has(kind):content[kind]=[]
	return {"ok":true,"folder":absolute}

func export_project(zip_path: String) -> Dictionary:
	var result:=validate_project()
	if not result.ok:return {"ok":false,"error":"검사를 통과한 뒤 내보낼 수 있습니다.","issues":result.issues}
	if not _safe_output(zip_path.get_base_dir()):return {"ok":false,"error":"원작 또는 캐시 폴더 밖으로 내보내세요."}
	var absolute:=ProjectSettings.globalize_path(zip_path).simplify_path()
	if not absolute.to_lower().ends_with(".zip"):return {"ok":false,"error":"ZIP 확장자로 내보내세요."}
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var directory:=DirAccess.open(absolute.get_base_dir())
	if directory==null or directory.is_link(absolute.get_file()):return {"ok":false,"error":"링크가 아닌 새 ZIP 파일을 선택하세요."}
	var pack:=ZIPPacker.new();var error:=pack.open(absolute)
	if error!=OK:return {"ok":false,"error":"ZIP 파일을 만들 수 없습니다."}
	var prefix:=str(descriptor.id)+"/"
	for pair in [["mod.json",descriptor],["content.json",content]]:
		error=pack.start_file(prefix+str(pair[0]))
		if error==OK:error=pack.write_file(JSON.stringify(pair[1],"\t").to_utf8_buffer())
		if error==OK:error=pack.close_file()
		if error!=OK:pack.close();return {"ok":false,"error":"ZIP에 프로젝트 정의를 기록하지 못했습니다."}
	pack.close()
	return {"ok":true,"zip":absolute,"files":[prefix+"mod.json",prefix+"content.json"],"original_assets_included":false}
