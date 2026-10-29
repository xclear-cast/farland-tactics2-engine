class_name FT2ExpansionEditor
extends Control
## Native forms for schema2 expansion authoring. Original resources are references.
signal closed
signal play_requested(folder: String)

const Project=preload("res://scripts/editor/ft2_expansion_project.gd")
var project=Project.new()
var data
var fields: Dictionary={}
var buttons: Dictionary={}
var lists: Dictionary={}
var forms: Dictionary={}
var selected: Dictionary={"characters":0,"skills":0,"maps":0,"stories":0,"nodes":0}
var tabs: TabContainer
var status: Label
var project_path: LineEdit
var map_grid: GridContainer
var map_cell_label: Label
var spawn_list: ItemList
var selected_cell:=Vector2i(2,2)
var _built:=false
var _refreshing:=false
var _play_after_save:=false

func _ready() -> void:
	_build();_refresh_all()

func configure(source_data=null) -> void:
	data=source_data;project.source_data=data
	if _built:_refresh_all()

func load_project(folder: String) -> Dictionary:
	var result: Dictionary=project.load_project(folder)
	if result.ok:
		for kind in selected:selected[kind]=0
		if _built:_refresh_all();_status("프로젝트를 열었습니다: "+folder)
	elif _built:_status(str(result.error),true)
	return result

func save_project(folder: String) -> Dictionary:
	if _built:_flush_active();_sync_header()
	var result: Dictionary=project.save_project(folder)
	if _built:
		if result.ok:project_path.text=str(result.folder);_status("저장했습니다: "+str(result.folder))
		else:_status(str(result.error),true)
	return result

func validate_project() -> Dictionary:
	if _built:_flush_active();_sync_header()
	var result: Dictionary=project.validate_project()
	if _built:_status("형식 검사 통과! ‘저장하고 테스트’로 실제 실행도 확인하세요." if result.ok else "\n".join(result.issues),not result.ok)
	return result

func export_project(zip_path: String) -> Dictionary:
	if _built:_flush_active();_sync_header()
	var result: Dictionary=project.export_project(zip_path)
	if _built:_status("ZIP으로 내보냈습니다. 원작 이미지·음악·캐시는 포함하지 않았습니다.\n"+str(result.zip)if result.ok else str(result.get("error","내보내기 실패"))+"\n"+"\n".join(result.get("issues",[])),not result.ok)
	return result

func _status(message: String, failed: bool=false) -> void:
	status.text=message;status.modulate=Color("ffb3a7")if failed else Color("9fe0c2")

func _button(parent: Node,key: String,text: String,action: Callable) -> Button:
	var node:=Button.new();node.text=text;node.pressed.connect(action);parent.add_child(node);buttons[key]=node;return node

func _entry(parent: Node,key: String,title: String,initial: String="") -> LineEdit:
	var input:=LineEdit.new();input.text=initial;input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_row(parent,title,input);fields[key]=input;return input

func _number(parent: Node,key: String,title: String,low: int=0,high: int=32767,value: int=0) -> SpinBox:
	var input:=SpinBox.new();input.min_value=low;input.max_value=high;input.step=1;input.value=value;input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_row(parent,title,input);fields[key]=input;return input

func _option(parent: Node,key: String,title: String) -> OptionButton:
	var input:=OptionButton.new();input.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_row(parent,title,input);fields[key]=input;return input

func _row(parent: Node,title: String,input: Control) -> void:
	var row:=HBoxContainer.new();row.size_flags_horizontal=Control.SIZE_EXPAND_FILL;var label:=Label.new();label.text=title;label.custom_minimum_size.x=150;row.add_child(label);row.add_child(input);parent.add_child(row)

func _text(parent: Node,text: String,size: int=16) -> Label:
	var label:=Label.new();label.text=text;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",size);parent.add_child(label);return label

func _build() -> void:
	if _built:return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background:=ColorRect.new();background.color=Color("142131");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,12)
	add_child(margin);var box:=VBoxContainer.new();box.add_theme_constant_override("separation",7);margin.add_child(box)
	_text(box,"확장팩 제작기",24)
	_text(box,"새 이야기·맵·캐릭터·스킬을 폼으로 만듭니다. 원작 그래픽은 정품 데이터에서 참조합니다.")
	var toolbar:=HBoxContainer.new();box.add_child(toolbar)
	_button(toolbar,"new","새 프로젝트",_new_project)
	_button(toolbar,"open","열기",func():_choose_folder("open"))
	_button(toolbar,"save","저장",_save_clicked)
	_button(toolbar,"save_as","다른 폴더에 저장",func():_choose_folder("save"))
	_button(toolbar,"validate","검사",func():validate_project())
	_button(toolbar,"export","공유 ZIP 내보내기",_choose_export)
	_button(toolbar,"test_play","저장하고 테스트",_test_clicked)
	_button(toolbar,"close","닫기",func():closed.emit();queue_free())
	project_path=LineEdit.new();project_path.placeholder_text="프로젝트 폴더를 선택하거나 새 경로를 입력하세요.";box.add_child(project_path)
	var header:=GridContainer.new();header.columns=2;box.add_child(header)
	header.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_entry(header,"project.id","프로젝트 ID","my_expansion")
	_entry(header,"project.name","확장팩 이름")
	_entry(header,"project.version","버전","1.0")
	_entry(header,"project.entry","처음 시작할 스토리","intro")
	tabs=TabContainer.new();tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(tabs)
	var character:=_section("characters","캐릭터")
	_entry(character,"character.id","캐릭터 ID")
	_entry(character,"character.name","표시 이름")
	_option(character,"character.base_race","기반 직업")
	var sprites:=_option(character,"character.sprite","정품 APD 그래픽")
	_entry(character,"character.sprite_text","APD 이름 직접 입력","CHAR_00E")
	_number(character,"character.level","시작 레벨",1,99,1)
	_option(character,"character.skill_pick","추가할 스킬 선택")
	_button(character,"add_character_skill","선택한 스킬을 목록에 추가",_add_character_skill)
	_entry(character,"character.skills","스킬 ID (쉼표 구분)","spark")
	_text(character,"‘변경’을 켠 능력치만 덮어씁니다. 끈 항목은 기반 직업의 값을 그대로 사용합니다.")
	var stats:=GridContainer.new();stats.columns=2;character.add_child(stats)
	for pair in [["hp","HP"],["mp","MP"],["atk","공격"],["def","방어"],["int","지력"],["mdef","마법저항"],["agi","민첩"]]:
		for part in ["initial","growth"]:
			var key: String="character."+str(pair[0])+"."+part
			var minimum:=1 if pair[0]=="hp"and part=="initial"else 0 if pair[0]=="mp"and part=="initial"else -32768
			var input:=_number(stats,key,str(pair[1])+(" 기본"if part=="initial"else" 성장"),minimum,32767,0)
			var enabled:=CheckBox.new();enabled.text="변경";input.get_parent().add_child(enabled);fields[key+".enabled"]=enabled
			enabled.toggled.connect(func(on: bool):input.editable=on)
	_button(character,"apply_character","캐릭터 적용",func():_apply_character();_refresh_lists())
	var skill:=_section("skills","스킬")
	_entry(skill,"skill.id","스킬 ID")
	_entry(skill,"skill.name","새 스킬 이름")
	_option(skill,"skill.base_skill","기반 스킬")
	_option(skill,"skill.visual_skill","재사용할 연출")
	_number(skill,"skill.mp","MP 소비",0,32767,3)
	_number(skill,"skill.power","위력",1,32767,12)
	_number(skill,"skill.range_min","최소 거리",0,32,1)
	_number(skill,"skill.range_max","최대 거리",0,32,3)
	_text(skill,"새 능력치·이름을 등록하고 정품 스킬의 연출을 재사용합니다.")
	_button(skill,"apply_skill","스킬 적용",func():_apply_skill();_refresh_lists())
	var map:=_section("maps","맵·배치")
	_entry(map,"map.id","맵 ID")
	_entry(map,"map.name","맵 이름")
	_option(map,"map.base_map","타일을 참조할 원작 맵")
	_number(map,"map.width","가로 칸",1,16,8)
	_number(map,"map.height","세로 칸",1,16,8)
	_button(map,"apply_map","맵 크기·이름 적용",func():_apply_map();_refresh_lists();_refresh_map_grid())
	_text(map,"아래 칸을 클릭한 뒤 높이·지형을 적용하거나 캐릭터를 배치하세요. 좌표는 1부터 시작합니다.")
	var map_parts:=HBoxContainer.new();map.add_child(map_parts)
	var grid_side:=VBoxContainer.new();map_parts.add_child(grid_side)
	var edit_side:=VBoxContainer.new();edit_side.size_flags_horizontal=Control.SIZE_EXPAND_FILL;map_parts.add_child(edit_side)
	map_grid=GridContainer.new();map_grid.columns=8;grid_side.add_child(map_grid)
	map_cell_label=_text(grid_side,"선택한 칸: 2, 2")
	_number(edit_side,"map.cell_height","이 칸 높이",-64,64,0)
	var terrain:=_option(edit_side,"map.cell_terrain","이 칸 지형")
	for i in range(8):terrain.add_item("지형 %d"%i,i)
	terrain.select(1)
	_button(edit_side,"apply_cell","선택한 칸에 적용",_apply_cell)
	_option(edit_side,"spawn.character","배치할 캐릭터")
	var side:=_option(edit_side,"spawn.side","진영");side.add_item("아군",0);side.add_item("적군",1)
	_number(edit_side,"spawn.level","배치 레벨",1,99,1)
	_button(edit_side,"add_spawn","선택한 칸에 배치",_add_spawn)
	spawn_list=ItemList.new();spawn_list.custom_minimum_size.y=90;edit_side.add_child(spawn_list)
	_button(edit_side,"remove_spawn","선택한 배치 삭제",_remove_spawn)
	var story:=_section("stories","스토리")
	_entry(story,"story.id","스토리 ID")
	_entry(story,"story.start","시작 노드 ID")
	_button(story,"apply_story","스토리 정보 적용",func():_apply_story();_refresh_lists())
	var nodebar:=HBoxContainer.new();story.add_child(nodebar)
	_button(nodebar,"add_node","노드 추가",_new_node)
	_button(nodebar,"remove_node","선택 노드 삭제",_remove_node)
	var nodes:=ItemList.new();nodes.custom_minimum_size.y=130;nodes.item_selected.connect(_select_node);story.add_child(nodes);lists.nodes=nodes
	_entry(story,"node.id","노드 ID")
	var types:=_option(story,"node.type","종류")
	for pair in [["dialogue","대사"],["battle","전투"],["branch","조건 분기"],["set","변수 설정"],["end","끝"]]:types.add_item(pair[1]);types.set_item_metadata(types.item_count-1,pair[0])
	types.item_selected.connect(func(_index):_node_type_visibility())
	_entry(story,"node.speaker","화자 캐릭터 ID")
	var dialogue:=TextEdit.new();dialogue.custom_minimum_size.y=75;dialogue.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;_row(story,"직접 쓴 대사",dialogue);fields["node.text"]=dialogue
	_option(story,"node.map","전투 맵")
	_entry(story,"node.next","다음 노드")
	_entry(story,"node.on_defeat","패배하면 갈 노드")
	_entry(story,"node.variable","변수 이름")
	_entry(story,"node.value","설정할 값","1")
	_entry(story,"node.equals","비교할 값","1")
	_entry(story,"node.then","같으면 갈 노드")
	_entry(story,"node.else","다르면 갈 노드")
	_button(story,"apply_node","노드 적용",func():_apply_node();_refresh_nodes())
	status=_text(box,"새 프로젝트를 저장하고 ‘검사’를 눌러 확인하세요.",15);status.custom_minimum_size.y=48
	_built=true

func _section(kind: String,title: String) -> VBoxContainer:
	var root_box:=HBoxContainer.new();root_box.name=title;tabs.add_child(root_box)
	var sidebar:=VBoxContainer.new();sidebar.custom_minimum_size.x=210;root_box.add_child(sidebar)
	var row:=HBoxContainer.new();sidebar.add_child(row)
	_button(row,"add_"+kind,"추가",func():_new_record(kind))
	_button(row,"remove_"+kind,"삭제",func():_remove_record(kind))
	var list:=ItemList.new();list.size_flags_vertical=Control.SIZE_EXPAND_FILL;sidebar.add_child(list);lists[kind]=list
	list.item_selected.connect(func(index):_select_record(kind,index))
	var scroll:=ScrollContainer.new();scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;root_box.add_child(scroll)
	var form:=VBoxContainer.new();form.size_flags_horizontal=Control.SIZE_EXPAND_FILL;form.add_theme_constant_override("separation",6);scroll.add_child(form);forms[kind]=form
	return form

func _sync_header() -> void:
	project.descriptor.id=fields["project.id"].text.strip_edges()
	project.descriptor.name=fields["project.name"].text.strip_edges()
	project.descriptor.version=fields["project.version"].text.strip_edges()
	project.descriptor.entry_story=fields["project.entry"].text.strip_edges()

func _refresh_all() -> void:
	_refreshing=true
	for key in ["id","name","version"]:fields["project."+key].text=str(project.descriptor.get(key,""))
	fields["project.entry"].text=str(project.descriptor.get("entry_story",""));project_path.text=project.folder
	_fill_original_options();_refresh_lists();_refreshing=false
	for kind in Project.KINDS:_select_record(kind,clampi(int(selected[kind]),0,maxi(0,project.content[kind].size()-1)))

func _original_rows(table: String) -> Array:
	if data==null:return []
	var document=data.read_json("data/port_ready/tables/"+table+".dat.json")
	return document.get("records",[])if document is Dictionary else []

func _fill_original_options() -> void:
	for pair in [["character.base_race","race",74],["skill.base_skill","magic",84],["skill.visual_skill","magic",84]]:
		var option: OptionButton=fields[pair[0]];option.clear();var rows:=_original_rows(str(pair[1]))
		if rows.is_empty():
			for i in range(int(pair[2])):
				if pair[1]=="magic" and i==0:continue
				option.add_item("정품 ID %d (게임 연결 후 이름 표시)"%i,i)
		else:
			for row in rows:
				var id:=int(row.get("id",0));var name:=str(row.get("name",""))
				if row.get("name")==null or str(row.get("entry_role",""))=="placeholder"or name.is_empty() or name=="결번" or pair[1]=="magic" and id==0:continue
				option.add_item("%d · %s"%[id,name],id)
	var races: OptionButton=fields["character.base_race"]
	if not races.item_selected.is_connected(_base_race_changed):races.item_selected.connect(_base_race_changed)
	var sprites: OptionButton=fields["character.sprite"];sprites.clear()
	var stems: Array=[]
	if data!=null:
		var manifest=FT2Content.read_json("res://assets/indexed/manifest.json")
		if manifest is Dictionary:stems=manifest.get("apds",{}).keys();stems.sort()
	if stems.is_empty():stems=["CHAR_00E"]
	for stem in stems:sprites.add_item(str(stem));sprites.set_item_metadata(sprites.item_count-1,str(stem))
	if not sprites.item_selected.is_connected(_sprite_selected):sprites.item_selected.connect(_sprite_selected)
	var maps: OptionButton=fields["map.base_map"];maps.clear()
	if data!=null:
		var index=data.read_json("data/port_ready/maps/index.json")
		if index is Dictionary:
			for row in index.get("maps",[]):maps.add_item("원작 맵 %d"%int(row.map_id),int(row.map_id))
	if maps.item_count==0:maps.add_item("원작 맵 40",40)

func _sprite_selected(index: int) -> void:
	fields["character.sprite_text"].text=str(fields["character.sprite"].get_item_metadata(index))

func _base_stat(key: String) -> int:
	var id: int=fields["character.base_race"].get_selected_id();var rows:=_original_rows("race")
	if id>=0 and id<rows.size():
		var parts:=key.split(".");var stat: Dictionary=rows[id].get("stats",{}).get(parts[0],{})
		return int(stat.get("initial"if parts[1]=="initial"else"increment_per_level",0))
	return 0

func _base_race_changed(_index: int) -> void:
	for stat in ["hp","mp","atk","def","int","mdef","agi"]:
		for part in ["initial","growth"]:
			var key: String="character."+stat+"."+part
			if not fields[key+".enabled"].button_pressed:fields[key].value=_base_stat(stat+"."+part)

func _refresh_lists() -> void:
	for kind in Project.KINDS:
		var list: ItemList=lists[kind];list.clear()
		for row in project.content[kind]:list.add_item(str(row.get("id",""))+" · "+str(row.get("name",row.get("start",""))))
		if int(selected[kind])>=0 and int(selected[kind])<list.item_count:list.select(int(selected[kind]))
	_fill_project_option("spawn.character","characters")
	_fill_project_option("node.map","maps")
	_fill_character_skills()

func _fill_character_skills() -> void:
	var option: OptionButton=fields["character.skill_pick"];option.clear()
	for row in project.content.skills:
		option.add_item("내 스킬 · "+str(row.get("name",row.id))+" ("+str(row.id)+")")
		option.set_item_metadata(option.item_count-1,str(row.id))
	var rows:=_original_rows("magic")
	for row in rows:
		var id:=int(row.get("id",0));var name:=str(row.get("name",""))
		if id<1 or row.get("name")==null or str(row.get("entry_role",""))=="placeholder"or name.is_empty()or name=="결번":continue
		option.add_item("원작 스킬 · %d %s"%[id,name]);option.set_item_metadata(option.item_count-1,id)
	if option.item_count>0:option.select(0)

func _add_character_skill() -> void:
	var option: OptionButton=fields["character.skill_pick"]
	if option.selected<0:_status("스킬 탭에서 새 스킬을 먼저 만드세요.",true);return
	var reference:=str(option.get_item_metadata(option.selected));var parts: Array[String]=[]
	for raw in fields["character.skills"].text.split(",",false):
		if not str(raw).strip_edges().is_empty():parts.append(str(raw).strip_edges())
	if not reference in parts:parts.append(reference)
	fields["character.skills"].text=",".join(parts);_status("스킬 목록에 추가했습니다. ‘캐릭터 적용’을 눌러 반영하세요.")

func _fill_project_option(key: String,kind: String) -> void:
	var option: OptionButton=fields[key];var previous:=str(option.get_item_metadata(option.selected))if option.selected>=0 else "";option.clear()
	for row in project.content[kind]:
		option.add_item(str(row.get("name",row.id))+" ("+str(row.id)+")");option.set_item_metadata(option.item_count-1,str(row.id))
	_select_metadata(option,previous)

func _select_number(option: OptionButton,id: int) -> void:
	for i in option.item_count:
		if option.get_item_id(i)==id:option.select(i);return
	if id>=0:
		option.add_item("확인 필요 · ID %d"%id,id);option.select(option.item_count-1)
	elif option.item_count>0:option.select(0)

func _select_metadata(option: OptionButton,value: String) -> void:
	for i in option.item_count:
		if str(option.get_item_metadata(i))==value:option.select(i);return
	if not value.is_empty():
		option.add_item("확인 필요 · "+value);option.set_item_metadata(option.item_count-1,value);option.select(option.item_count-1)
	elif option.item_count>0:option.select(0)

func _metadata(key: String) -> String:
	var option: OptionButton=fields[key]
	return str(option.get_item_metadata(option.selected))if option.selected>=0 else ""

func _selected_record(kind: String) -> Dictionary:
	var index:=int(selected[kind]);var rows: Array=project.content[kind]
	return rows[index]if index>=0 and index<rows.size()else {}

func _select_record(kind: String,index: int) -> void:
	selected[kind]=index
	var row:=_selected_record(kind)
	if row.is_empty():return
	if kind=="characters":
		for key in ["id","name"]:fields["character."+key].text=str(row.get(key,""))
		_select_number(fields["character.base_race"],int(row.get("base_race",1)))
		_select_metadata(fields["character.sprite"],str(row.get("sprite","CHAR_00E")))
		fields["character.sprite_text"].text=str(row.get("sprite","CHAR_00E"));fields["character.level"].value=int(row.get("level",1))
		var references: Array[String]=[]
		for value in row.get("skills",[]):references.append(str(value))
		fields["character.skills"].text=",".join(references)
		for stat in ["hp","mp","atk","def","int","mdef","agi"]:
			for part in ["initial","growth"]:
				var key: String="character."+stat+"."+part
				var enabled: bool=row.get("stats",{}).has(stat+"."+part)
				fields[key+".enabled"].button_pressed=enabled;fields[key].editable=enabled
				fields[key].value=int(row.get("stats",{}).get(stat+"."+part,_base_stat(stat+"."+part)))
	elif kind=="skills":
		for key in ["id","name"]:fields["skill."+key].text=str(row.get(key,""))
		for key in ["base_skill","visual_skill"]:_select_number(fields["skill."+key],int(row.get(key,1)))
		for key in ["mp","power","range_min","range_max"]:fields["skill."+key].value=int(row.get(key,0))
	elif kind=="maps":
		for key in ["id","name"]:fields["map."+key].text=str(row.get(key,""))
		_select_number(fields["map.base_map"],int(row.get("base_map",40)))
		for key in ["width","height"]:fields["map."+key].value=int(row.get(key,8))
		selected_cell=Vector2i(2,2);_refresh_map_grid();_refresh_spawns();_select_cell(selected_cell)
	elif kind=="stories":
		for key in ["id","start"]:fields["story."+key].text=str(row.get(key,""))
		selected.nodes=0;_refresh_nodes()

func _new_record(kind: String) -> void:
	var record: Dictionary
	match kind:
		"characters":record={"id":project.next_id(kind,"character"),"name":"새 캐릭터","base_race":1,"sprite":"CHAR_00E","level":1,"stats":{},"skills":[]}
		"skills":record={"id":project.next_id(kind,"skill"),"name":"새 스킬","base_skill":1,"visual_skill":1,"mp":3,"power":12,"range_min":1,"range_max":3}
		"maps":record={"id":project.next_id(kind,"map"),"name":"새 맵","base_map":40,"width":8,"height":8,"cells":[],"placements":[]}
		"stories":record={"id":project.next_id(kind,"story"),"start":"begin","nodes":[{"id":"begin","type":"end"}]}
	project.update_record(kind,-1,record);selected[kind]=project.content[kind].size()-1;_refresh_lists();_select_record(kind,int(selected[kind]));_status("새 항목을 추가했습니다. 폼에서 수정한 뒤 적용하세요.")

func _remove_record(kind: String) -> void:
	project.remove_record(kind,int(selected[kind]));selected[kind]=0;_refresh_lists();_select_record(kind,0);_status("항목을 삭제했습니다. 연결된 참조가 있다면 검사에서 확인하세요.")

func _apply_character() -> void:
	var row: Dictionary={"id":fields["character.id"].text.strip_edges(),"name":fields["character.name"].text.strip_edges(),
		"base_race":fields["character.base_race"].get_selected_id(),"sprite":fields["character.sprite_text"].text.strip_edges(),"level":int(fields["character.level"].value),"stats":{},"skills":[]}
	for stat in ["hp","mp","atk","def","int","mdef","agi"]:
		for part in ["initial","growth"]:
			var key: String=stat+"."+part;var value:=int(fields["character."+key].value)
			if fields["character."+key+".enabled"].button_pressed:row.stats[key]=value
	for value in fields["character.skills"].text.split(",",false):
		var text:=str(value).strip_edges()
		if not text.is_empty():row.skills.append(int(text)if text.is_valid_int()else text)
	project.update_record("characters",int(selected.characters),row);_status("캐릭터를 적용했습니다.")

func _apply_skill() -> void:
	var row: Dictionary={"id":fields["skill.id"].text.strip_edges(),"name":fields["skill.name"].text.strip_edges()}
	for key in ["base_skill","visual_skill"]:row[key]=fields["skill."+key].get_selected_id()
	for key in ["mp","power","range_min","range_max"]:row[key]=int(fields["skill."+key].value)
	project.update_record("skills",int(selected.skills),row);_status("스킬을 적용했습니다.")

func _apply_map() -> void:
	var row:=_selected_record("maps").duplicate(true)
	if row.is_empty():row={"cells":[],"placements":[]}
	for key in ["id","name"]:row[key]=fields["map."+key].text.strip_edges()
	row.base_map=fields["map.base_map"].get_selected_id()
	for key in ["width","height"]:row[key]=int(fields["map."+key].value)
	project.update_record("maps",int(selected.maps),row);_status("맵 정보를 적용했습니다.")

func _cell_at(map: Dictionary,point: Vector2i) -> Dictionary:
	for cell in map.get("cells",[]):
		if int(cell.x)==point.x and int(cell.y)==point.y:return cell
	return {"x":point.x,"y":point.y,"height":0,"terrain":1}

func _refresh_map_grid() -> void:
	for child in map_grid.get_children():map_grid.remove_child(child);child.queue_free()
	var map:=_selected_record("maps")
	if map.is_empty():return
	map_grid.columns=int(map.width)
	for y in range(1,int(map.height)+1):
		for x in range(1,int(map.width)+1):
			var point:=Vector2i(x,y);var cell:=_cell_at(map,point);var node:=Button.new()
			node.text=str(int(cell.height));node.custom_minimum_size=Vector2(28,28);node.tooltip_text="(%d, %d) 높이 %d / 지형 %d"%[x,y,int(cell.height),int(cell.terrain)]
			var style:=StyleBoxFlat.new();style.bg_color=Color.from_hsv(float(int(cell.terrain))/8.0,.3,.40)
			style.border_color=Color("ffd06b")if point==selected_cell else Color("536476")
			style.set_border_width_all(3 if point==selected_cell else 1);node.add_theme_stylebox_override("normal",style)
			node.pressed.connect(func():_select_cell(point));map_grid.add_child(node)

func _select_cell(point: Vector2i) -> void:
	selected_cell=point;map_cell_label.text="선택한 칸: %d, %d"%[point.x,point.y]
	var cell:=_cell_at(_selected_record("maps"),point)
	fields["map.cell_height"].value=int(cell.height);_select_number(fields["map.cell_terrain"],int(cell.terrain));_refresh_map_grid()

func _apply_cell() -> void:
	_apply_map();var map:=_selected_record("maps")
	if selected_cell.x>int(map.width)or selected_cell.y>int(map.height):_status("맵 안쪽의 칸을 먼저 선택하세요.",true);return
	var cell: Dictionary={"x":selected_cell.x,"y":selected_cell.y,"height":int(fields["map.cell_height"].value),"terrain":fields["map.cell_terrain"].get_selected_id()}
	var replaced:=false
	for index in map.cells.size():
		if int(map.cells[index].x)==selected_cell.x and int(map.cells[index].y)==selected_cell.y:map.cells[index]=cell;replaced=true
	if not replaced:map.cells.append(cell)
	_refresh_map_grid();_status("선택한 칸의 높이와 지형을 바꿨습니다.")

func _add_spawn() -> void:
	_apply_map();var map:=_selected_record("maps");var id:=_metadata("spawn.character")
	if id.is_empty():_status("배치할 캐릭터를 먼저 만드세요.",true);return
	map.placements.append({"character":id,"side":"ally"if fields["spawn.side"].selected==0 else"enemy","x":selected_cell.x,"y":selected_cell.y,"level":int(fields["spawn.level"].value)})
	_refresh_spawns();_status("캐릭터를 선택한 칸에 배치했습니다.")

func _refresh_spawns() -> void:
	spawn_list.clear()
	for row in _selected_record("maps").get("placements",[]):spawn_list.add_item("%s · %s · (%d, %d)"%[str(row.get("character",row.get("race","?"))),"아군"if row.get("side")=="ally"else"적군",int(row.x),int(row.y)])

func _remove_spawn() -> void:
	var selection:=spawn_list.get_selected_items()
	if not selection.is_empty():_selected_record("maps").placements.remove_at(int(selection[0]));_refresh_spawns()

func _apply_story() -> void:
	var row:=_selected_record("stories").duplicate(true)
	if row.is_empty():row={"nodes":[]}
	row.id=fields["story.id"].text.strip_edges();row.start=fields["story.start"].text.strip_edges()
	project.update_record("stories",int(selected.stories),row)

func _refresh_nodes() -> void:
	var list: ItemList=lists.nodes;list.clear()
	for node in _selected_record("stories").get("nodes",[]):list.add_item(str(node.id)+" · "+str(node.type))
	if list.item_count>0:
		selected.nodes=clampi(int(selected.nodes),0,list.item_count-1);list.select(int(selected.nodes));_select_node(int(selected.nodes))

func _select_node(index: int) -> void:
	selected.nodes=index;var nodes: Array=_selected_record("stories").get("nodes",[])
	if index<0 or index>=nodes.size():return
	var node: Dictionary=nodes[index]
	fields["node.id"].text=str(node.id);_select_metadata(fields["node.type"],str(node.type))
	for key in ["speaker","next","on_defeat","variable","then","else"]:fields["node."+key].text=str(node.get(key,""))
	fields["node.text"].text=str(node.get("text",""));_select_metadata(fields["node.map"],str(node.get("map","")))
	fields["node.value"].text=JSON.stringify(node.get("value",1));fields["node.equals"].text=JSON.stringify(node.get("equals",1));_node_type_visibility()

func _node_type_visibility() -> void:
	var type:=_metadata("node.type")
	var visible_keys: Array=[]
	match type:
		"dialogue":visible_keys=["speaker","text","next"]
		"battle":visible_keys=["map","next","on_defeat"]
		"branch":visible_keys=["variable","equals","then","else"]
		"set":visible_keys=["variable","value","next"]
	for key in ["speaker","text","map","next","on_defeat","variable","value","equals","then","else"]:fields["node."+key].get_parent().visible=key in visible_keys

func _new_node() -> void:
	_apply_story();var story:=_selected_record("stories");var used: Dictionary={}
	for node in story.nodes:used[str(node.id)]=true
	var number:=1
	while used.has("node"+str(number)):number+=1
	story.nodes.append({"id":"node"+str(number),"type":"dialogue","speaker":"hero","text":"새로운 대사를 입력하세요.","next":""})
	selected.nodes=story.nodes.size()-1;_refresh_nodes();_status("새 노드를 추가했습니다.")

func _remove_node() -> void:
	var nodes: Array=_selected_record("stories").get("nodes",[])
	if int(selected.nodes)>=0 and int(selected.nodes)<nodes.size():nodes.remove_at(int(selected.nodes));selected.nodes=0;_refresh_nodes()

func _value(text: String) -> Variant:
	var parser:=JSON.new()
	if parser.parse(text)==OK:return parser.data
	return text

func _apply_node() -> void:
	_apply_story();var story:=_selected_record("stories");var index:=int(selected.nodes)
	if index<0 or index>=story.nodes.size():return
	var old:=str(story.nodes[index].id);var type:=_metadata("node.type")
	var node: Dictionary={"id":fields["node.id"].text.strip_edges(),"type":type}
	match type:
		"dialogue":
			node.speaker=fields["node.speaker"].text.strip_edges();node.text=fields["node.text"].text;node.next=fields["node.next"].text.strip_edges()
		"battle":
			node.map=_metadata("node.map");node.next=fields["node.next"].text.strip_edges();node.on_defeat=fields["node.on_defeat"].text.strip_edges()
		"branch":
			node.variable=fields["node.variable"].text.strip_edges();node.equals=_value(fields["node.equals"].text);node["then"]=fields["node.then"].text.strip_edges();node["else"]=fields["node.else"].text.strip_edges()
		"set":
			node.variable=fields["node.variable"].text.strip_edges();node.value=_value(fields["node.value"].text);node.next=fields["node.next"].text.strip_edges()
	story.nodes[index]=node
	if old!=str(node.id):project.rename_node(story,old,str(node.id));fields["story.start"].text=str(story.start)
	_status("스토리 노드를 적용했습니다.")

func _flush_active() -> void:
	if not _built:return
	match tabs.current_tab:
		0:_apply_character()
		1:_apply_skill()
		2:_apply_map()
		3:_apply_node();_apply_story()

func _new_project() -> void:
	project.new_project();project.source_data=data
	for key in selected:selected[key]=0
	_refresh_all();_status("새 프로젝트를 만들었습니다. 기본 예제를 폼에서 바꿔 보세요.")

func _save_clicked() -> void:
	if project_path.text.strip_edges().is_empty():_choose_folder("save")
	else:save_project(project_path.text.strip_edges())

func _test_clicked() -> void:
	if project_path.text.strip_edges().is_empty():_play_after_save=true;_choose_folder("save");return
	var saved:=save_project(project_path.text.strip_edges())
	if not saved.ok:return
	var checked:=validate_project()
	if not checked.ok:return
	if data==null:_status("프로젝트는 저장했습니다. 정품 게임 데이터를 연결한 뒤 테스트할 수 있습니다.",true);return
	play_requested.emit(str(saved.folder))

func _choose_folder(action: String) -> void:
	var dialog:=FileDialog.new();dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=FileDialog.FILE_MODE_OPEN_DIR
	dialog.title="확장팩 프로젝트 폴더 열기"if action=="open"else"확장팩을 저장할 새 폴더 선택"
	add_child(dialog);dialog.current_dir=project.folder if not project.folder.is_empty()else OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	dialog.dir_selected.connect(func(path):
		if action=="open":load_project(path)
		else:
			var result:=save_project(path)
			if result.ok and _play_after_save:_play_after_save=false;_test_clicked()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered_ratio(.85)

func _choose_export() -> void:
	var result:=validate_project()
	if not result.ok:return
	var dialog:=FileDialog.new();dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE
	dialog.title="공유할 확장팩 ZIP 저장";dialog.filters=PackedStringArray(["*.zip ; Expansion ZIP"]);dialog.current_file=str(project.descriptor.id)+".zip"
	add_child(dialog);dialog.file_selected.connect(func(path):export_project(path if path.to_lower().ends_with(".zip")else path+".zip");dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered_ratio(.8)
