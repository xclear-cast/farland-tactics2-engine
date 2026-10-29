class_name FT2ExpansionEditor
extends Control
## Native forms for schema2 expansion authoring. Original resources are references.
signal closed
signal play_requested(folder: String)
signal source_connection_requested

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
var workspaces:Dictionary={}
var original_lists:Dictionary={}
var original_labels:Dictionary={}
var _search:Dictionary={}
var _original_search:Dictionary={}
var _original_selected:Dictionary={"characters":-1,"skills":-1}
var _record_title:Dictionary={}
var _record_summary:Dictionary={}
var _change_labels:Dictionary={}
var _portrait:TextureRect
var map_view
var story_view
var _heading:Label
var _connection:Label
var _dirty:=false
var _saved_signature:=""
var _history:Array=[]
var _history_cursor:=-1
var _history_restoring:=false
var _live_queued:=false
var _last_form:="characters"
var _pending_kind:=""
var _pending_edit:=false
var _chrome_ready:=false
var bridge
var _mcp_status:Label
var _mcp_client:OptionButton
var _mcp_config:TextEdit
var _mcp_tools:RichTextLabel
var _bridge_clock:=0.0
var external_preview_enabled:=true
var _preview_pid:=-1
var _preview_log:="user://editor_preview.log"
var _preview_error:=""
var _ui_scale_option:OptionButton
var _ui_scale_label:Label
var _effective_ui_scale:=1.0
var _scale_updating:=false
var _scale_suspended:=false
var _scale_window:Window
var _windowed_mode:=Window.MODE_WINDOWED
var _windowed_size:=Vector2i(1280,840)
var _windowed_position:=Vector2i.ZERO
const EditorBridge=preload("res://scripts/editor/ft2_editor_bridge.gd")
const MapView=preload("res://scripts/editor/ft2_editor_map_view.gd")
const StoryView=preload("res://scripts/editor/ft2_editor_story_view.gd")

func _ready() -> void:
	_build();_refresh_all();_reset_history()
	_scale_window=get_window()
	_scale_window.size_changed.connect(_apply_ui_scale)
	_apply_ui_scale()

func configure(source_data=null) -> void:
	if _built:_commit_pending()
	data=source_data;project.source_data=data
	if _built:
		_refresh_all()
		if _history.is_empty():_reset_history()
		_refresh_workbench()

func load_project(folder: String) -> Dictionary:
	var result: Dictionary=project.load_project(folder)
	if result.ok:
		for kind in selected:selected[kind]=0
		if _built:_refresh_all();_reset_history();_status("프로젝트를 열었습니다: "+folder)
	elif _built:_status(str(result.error),true)
	return result

func save_project(folder: String) -> Dictionary:
	if _built:_flush_active();_sync_header()
	var result: Dictionary=project.save_project(folder)
	if _built:
		if result.ok:project_path.text=str(result.folder);_saved_signature=_signature();_dirty=false;_status("저장했습니다: "+str(result.folder));_refresh_workbench()
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
	var node:=Button.new();node.text=text;node.pressed.connect(func():
		_commit_pending();action.call();_commit_pending();_checkpoint();_refresh_workbench())
	parent.add_child(node);buttons[key]=node;return node

func _entry(parent: Node,key: String,title: String,initial: String="") -> LineEdit:
	var input:=LineEdit.new();input.text=initial;input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_row(parent,title,input);fields[key]=input;return input

func _number(parent: Node,key: String,title: String,low: int=0,high: int=32767,value: int=0) -> SpinBox:
	var input:=SpinBox.new();input.min_value=low;input.max_value=high;input.step=1;input.value=value;input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_row(parent,title,input);fields[key]=input;return input

func _option(parent: Node,key: String,title: String) -> OptionButton:
	var input:=OptionButton.new();input.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_row(parent,title,input);fields[key]=input;return input

func _row(parent: Node,title: String,input: Control) -> void:
	var row:=HBoxContainer.new();row.size_flags_horizontal=Control.SIZE_EXPAND_FILL;var label:=Label.new();label.text=title;label.custom_minimum_size.x=85;row.add_child(label);row.add_child(input);parent.add_child(row)

func _text(parent: Node,text: String,size: int=16) -> Label:
	var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",size)
	if text.length()>48:
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.custom_minimum_size.x=180
	parent.add_child(label);return label

func _build() -> void:
	if _built:return
	_install_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background:=ColorRect.new();background.color=Color("171b22");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,10)
	add_child(margin)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",8);margin.add_child(box)
	var top:=HBoxContainer.new();box.add_child(top)
	_text(top,"FT2  /  확장팩 에디터",18)
	_heading=_text(top,"나의 첫 확장팩");_heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_heading.clip_text=true;_heading.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	_connection=_text(top,"정품 데이터 미연결",12)
	_button(top,"connect_original","원작 데이터 연결",_request_source_connection)
	_button(top,"open_original_folder","원작 폴더 열기",_open_original_folder)
	var toolbar:=HBoxContainer.new();toolbar.add_theme_constant_override("separation",5);box.add_child(toolbar)
	_button(toolbar,"new","새 프로젝트",_request_new).tooltip_text="새 확장팩 프로젝트"
	_button(toolbar,"open","열기",_request_open)
	_button(toolbar,"save","저장  Ctrl+S",_save_clicked)
	_button(toolbar,"save_as","다른 이름으로",func():_choose_folder("save"))
	toolbar.add_child(VSeparator.new())
	_button(toolbar,"undo","실행 취소",undo).tooltip_text="Ctrl+Z"
	_button(toolbar,"redo","다시 실행",redo).tooltip_text="Ctrl+Shift+Z / Ctrl+Y"
	toolbar.add_child(VSeparator.new())
	_button(toolbar,"validate","검사",func():validate_project())
	_button(toolbar,"export","내보내기",_choose_export)
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;toolbar.add_child(spacer)
	_button(toolbar,"ai_connect","AI로 만들기",func():tabs.current_tab=5).add_theme_color_override("font_color",Color("98c7ff"))
	var test:=_button(toolbar,"test_play","▶  저장하고 테스트",_test_clicked);test.add_theme_color_override("font_color",Color("9ce6c0"))
	_button(toolbar,"stop_play","테스트 중지",func():stop_preview())
	_button(toolbar,"close","닫기",_request_close)
	tabs=TabContainer.new();tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(tabs)
	_build_character(_section("characters","캐릭터 · 몬스터"))
	_build_skill(_section("skills","스킬"))
	_build_map(_section("maps","지도 · 배치"))
	_build_story(_section("stories","스토리"))
	_build_project_tab()
	_build_ai_tab()
	var footer:=HBoxContainer.new();box.add_child(footer)
	status=_text(footer,"목록에서 항목을 선택하세요. 원작 항목은 복제해서 편집합니다.",12);status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.x=200
	_ui_scale_option=OptionButton.new()
	for title in ["자동 확대","100%","125%","150%","175%","200%"]:_ui_scale_option.add_item(title)
	footer.add_child(_ui_scale_option);_ui_scale_option.item_selected.connect(func(_i):_apply_ui_scale())
	_ui_scale_label=_text(footer,"100%",12)
	_button(footer,"fullscreen","전체 화면  F11",_toggle_fullscreen)
	_built=true;_chrome_ready=true
	for key in fields:
		var control=fields[key]
		if key.begins_with("original_search_"):continue
		if control is LineEdit:
			control.text_changed.connect(_field_value_changed.bind(key));control.focus_exited.connect(_commit_pending)
		elif control is SpinBox:
			control.value_changed.connect(_field_value_changed.bind(key));control.get_line_edit().focus_exited.connect(_commit_pending)
		elif control is OptionButton:control.item_selected.connect(_field_value_changed.bind(key))
		elif control is CheckBox:control.toggled.connect(_field_value_changed.bind(key))
		elif control is TextEdit:control.text_changed.connect(_queue_live_edit.bind(key));control.focus_exited.connect(_commit_pending)
	tabs.tab_changed.connect(_workspace_changed)

func _install_theme() -> void:
	var t:=Theme.new();t.default_font_size=14
	for path in ["C:/Windows/Fonts/malgun.ttf","/mnt/c/Windows/Fonts/malgun.ttf","/System/Library/Fonts/AppleSDGothicNeo.ttc","/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"]:
		if FileAccess.file_exists(path):
			var font:=FontFile.new();font.data=FileAccess.get_file_as_bytes(path);t.default_font=font;break
	for kind in ["Button","LineEdit","SpinBox","OptionButton","TextEdit","ItemList","TabContainer","PopupMenu"]:
		t.set_color("font_color",kind,Color("dce2eb"));t.set_color("font_disabled_color",kind,Color("768396"))
	for kind in ["Button","OptionButton"]:
		for pair in [["normal","2b323e"],["hover","374254"],["pressed","365477"],["disabled","242a34"]]:
			t.set_stylebox(pair[0],kind,_style(pair[1],"3b4658",5))
	for kind in ["LineEdit","TextEdit","ItemList"]:
		t.set_stylebox("normal",kind,_style("202630","354052",4));t.set_stylebox("focus",kind,_style("253144","5c9be8",4))
		t.set_color("font_selected_color",kind,Color.WHITE);t.set_color("selection_color",kind,Color("31557a"))
	t.set_stylebox("selected","ItemList",_style("28496b","4b83b9",3));t.set_stylebox("selected_focus","ItemList",_style("28496b","75b4ee",3))
	t.set_stylebox("panel","TabContainer",_style("1e242e","354052",5))
	t.set_stylebox("tab_selected","TabContainer",_style("2e415b","547da8",4))
	t.set_stylebox("tab_unselected","TabContainer",_style("212833","303b4b",4))
	t.set_color("font_color","Label",Color("cbd4e2"))
	t.set_constant("separation","VBoxContainer",7);t.set_constant("separation","HBoxContainer",7)
	theme=t

func _style(background:String,border:String,rounding:int=4)->StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=Color(background);style.border_color=Color(border);style.set_border_width_all(1);style.set_corner_radius_all(rounding)
	style.content_margin_left=8;style.content_margin_right=8;style.content_margin_top=5;style.content_margin_bottom=5
	return style

func _section(kind: String,title: String) -> VBoxContainer:
	var split:=HSplitContainer.new();split.name=title;split.split_offset=224;tabs.add_child(split)
	var sidebar:=VBoxContainer.new();sidebar.custom_minimum_size.x=210;split.add_child(sidebar)
	_text(sidebar,"내 확장팩",15)
	var search:=LineEdit.new();search.placeholder_text="이름 · ID 검색";sidebar.add_child(search);_search[kind]=search
	search.text_changed.connect(func(_value):_refresh_lists())
	var list:=ItemList.new();list.size_flags_vertical=Control.SIZE_EXPAND_FILL;sidebar.add_child(list);lists[kind]=list
	list.item_selected.connect(func(index):_select_record(kind,int(list.get_item_metadata(index))))
	var row:=HBoxContainer.new();sidebar.add_child(row)
	_button(row,"add_"+kind,"+ 새 항목",func():_new_record(kind))
	_button(row,"remove_"+kind,"삭제",func():_remove_record(kind))
	if kind in ["characters","skills"]:
		list.custom_minimum_size.y=110;list.size_flags_stretch_ratio=.45
		sidebar.add_child(HSeparator.new());_text(sidebar,"원작 데이터",15)
		var original_search:=LineEdit.new();original_search.placeholder_text="원작 이름 · ID 검색";sidebar.add_child(original_search);_original_search[kind]=original_search;fields["original_search_"+kind]=original_search
		original_search.text_changed.connect(func(_value):_refresh_original_catalog(kind))
		var originals:=ItemList.new();originals.size_flags_vertical=Control.SIZE_EXPAND_FILL;originals.size_flags_stretch_ratio=1.0;sidebar.add_child(originals);lists["original_"+kind]=originals
		originals.item_selected.connect(func(index):_original_selected[kind]=int(originals.get_item_metadata(index));_show_original_hint(kind))
		originals.item_activated.connect(func(_index):_import_original(kind))
		_button(sidebar,"import_original_"+kind,"원작에서 편집본 만들기",func():_import_original(kind))
	var details:=HSplitContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;details.split_offset=570;split.add_child(details)
	var center:=VBoxContainer.new();center.size_flags_horizontal=Control.SIZE_EXPAND_FILL;center.custom_minimum_size.x=330;details.add_child(center);workspaces[kind]=center
	_record_title[kind]=_text(center,title,20)
	_record_title[kind].clip_text=true;_record_title[kind].text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	_record_summary[kind]=_text(center,"항목을 선택해 편집하세요.",12)
	_record_summary[kind].clip_text=true
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size.x=300;scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.size_flags_stretch_ratio=.5;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;details.add_child(scroll)
	var form:=VBoxContainer.new();form.size_flags_horizontal=Control.SIZE_EXPAND_FILL;form.add_theme_constant_override("separation",8);scroll.add_child(form);forms[kind]=form
	_text(form,"속성",17)
	return form

func _group(parent:Node,title:String)->void:
	parent.add_child(HSeparator.new());_text(parent,title,14)

func _build_character(form:VBoxContainer)->void:
	_entry(form,"character.name","이름");_entry(form,"character.id","고유 ID")
	_option(form,"character.base_race","원작 기준")
	_number(form,"character.level","시작 레벨",1,99,1).tooltip_text="확장팩의 시작 레벨입니다. 원작 기준 직업표에는 시작 레벨이 없습니다."
	_group(form,"모습")
	_option(form,"character.sprite","스프라이트")
	_entry(form,"character.sprite_text","리소스 이름","CHAR_00E")
	_group(form,"보유 스킬")
	_option(form,"character.skill_pick","스킬 선택")
	_button(form,"add_character_skill","+ 선택한 스킬 추가",_add_character_skill)
	_entry(form,"character.skills","보유 스킬 ID","spark")
	_button(form,"apply_character","속성 적용",func():_apply_character();_refresh_lists();_refresh_workbench())
	var center:VBoxContainer=workspaces.characters
	var preview:=HBoxContainer.new();preview.custom_minimum_size.y=126;center.add_child(preview)
	_portrait=TextureRect.new();_portrait.custom_minimum_size=Vector2(126,126);_portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;_portrait.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;preview.add_child(_portrait)
	var summary:=VBoxContainer.new();summary.size_flags_horizontal=Control.SIZE_EXPAND_FILL;preview.add_child(summary)
	_text(summary,"능력치 편집",18);_text(summary,"원작 기준값을 옆에서 비교하며 수정합니다.",12)
	_change_labels.characters=_text(summary,"원본값 사용 중",13)
	_button(summary,"reset_character","원본값으로 전체 초기화",func():_reset_record("characters"))
	var grid:=GridContainer.new();grid.columns=5;grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",9);center.add_child(grid)
	for title in ["능력치","현재 기본값","원작","레벨당 성장","원작"]:_text(grid,title,12)
	for pair in [["hp","체력 HP"],["mp","마력 MP"],["atk","공격력"],["def","방어력"],["int","지력"],["mdef","마법 저항"],["agi","민첩"]]:
		_text(grid,pair[1],14)
		for part in ["initial","growth"]:
			var key:String=str(pair[0])+"."+part
			var cell:=HBoxContainer.new();grid.add_child(cell)
			var enabled:=CheckBox.new();enabled.tooltip_text="선택하면 확장팩 값으로 덮어씁니다. 끄면 원작값을 사용합니다.";cell.add_child(enabled);fields["character."+key+".enabled"]=enabled
			var value:=SpinBox.new();value.min_value=1 if key=="hp.initial"else 0 if key=="mp.initial"else -32768;value.max_value=32767;value.custom_minimum_size.x=90;cell.add_child(value);fields["character."+key]=value
			value.value_changed.connect(func(_v):
				if not _refreshing:enabled.button_pressed=true)
			_button(cell,"reset_character_"+key,"↶",func():_reset_field("characters","stats."+key)).tooltip_text="이 수치만 원작값으로 되돌리기"
			var original:=_text(grid,"—",13);original.modulate=Color("8898ac");original_labels["character."+key]=original
	_text(center,"체크된 수치만 확장팩에서 변경됩니다. 원본 데이터는 읽기 전용입니다.",12)

func _build_skill(form:VBoxContainer)->void:
	_entry(form,"skill.name","이름");_entry(form,"skill.id","고유 ID")
	_option(form,"skill.base_skill","원작 기준");_option(form,"skill.visual_skill","연출 기준")
	_text(form,"기반 스킬의 처리 방식과 정품 연출을 재사용합니다.",12)
	_button(form,"apply_skill","속성 적용",func():_apply_skill();_refresh_lists();_refresh_workbench())
	var center:VBoxContainer=workspaces.skills
	_group(center,"스킬 수치")
	_change_labels.skills=_text(center,"원본값 사용 중",13)
	_button(center,"reset_skill","원본값으로 전체 초기화",func():_reset_record("skills"))
	var grid:=GridContainer.new();grid.columns=4;grid.add_theme_constant_override("v_separation",14);center.add_child(grid)
	for title in ["속성","현재값","원작 기준값","초기화"]:_text(grid,title,12)
	for pair in [["mp","MP 소비"],["power","위력"],["range_min","최소 사거리"],["range_max","최대 사거리"]]:
		var key:String=pair[0];_text(grid,pair[1],15)
		var value:=SpinBox.new();value.min_value=-32768 if key=="power"else 0;value.max_value=32767;value.custom_minimum_size.x=125;grid.add_child(value);fields["skill."+key]=value
		var original:=_text(grid,"—",14);original.modulate=Color("8898ac");original_labels["skill."+key]=original
		_button(grid,"reset_skill_"+key,"↶ 원작값",func():_reset_field("skills",key))
	_text(center,"주황색 수치는 원작 기준값에서 변경된 값입니다.",12)

func _build_map(form:VBoxContainer)->void:
	_entry(form,"map.name","맵 이름");_entry(form,"map.id","고유 ID");_option(form,"map.base_map","타일 기준 맵")
	_number(form,"map.width","가로 칸",1,64,8);_number(form,"map.height","세로 칸",1,64,8)
	_button(form,"apply_map","맵 속성 적용",func():_apply_map();_refresh_lists();_refresh_map_grid())
	_group(form,"선택한 칸 · 브러시")
	map_cell_label=_text(form,"X 2  /  Y 2",14)
	_number(form,"map.cell_height","높이",-64,64,0)
	var terrain:=_option(form,"map.cell_terrain","지형")
	for i in range(8):terrain.add_item("지형 %d"%i,i)
	terrain.select(1);_button(form,"apply_cell","선택한 칸에 적용",_apply_cell)
	_group(form,"캐릭터 배치")
	_option(form,"spawn.character","캐릭터")
	var side:=_option(form,"spawn.side","진영");side.add_item("아군",0);side.add_item("적군",1)
	_number(form,"spawn.level","레벨",1,99,1)
	_button(form,"add_spawn","선택한 칸에 배치",_add_spawn)
	spawn_list=ItemList.new();spawn_list.custom_minimum_size.y=130;form.add_child(spawn_list)
	_button(form,"remove_spawn","선택한 배치 삭제",_remove_spawn)
	var center:VBoxContainer=workspaces.maps
	var tools:=HBoxContainer.new();center.add_child(tools)
	for pair in [["select","선택"],["height","높이"],["terrain","지형"],["place","배치"]]:
		var tool:String=pair[0];_button(tools,"map_tool_"+tool,pair[1],func():_set_map_tool(tool))
	_button(tools,"map_zoom_out","−",func():map_view.zoom_out())
	_button(tools,"map_zoom_in","+",func():map_view.zoom_in())
	_button(tools,"map_fit","맞춤",func():map_view.zoom_to_fit())
	map_view=MapView.new();map_view.size_flags_vertical=Control.SIZE_EXPAND_FILL;map_view.custom_minimum_size.y=320;center.add_child(map_view)
	map_view.cell_selected.connect(_select_cell);map_view.cell_painted.connect(_paint_cell)
	var info:=_text(center,"휠: 확대 / 축소  ·  가운데 버튼: 화면 이동",12)
	map_view.view_info_changed.connect(func(message):info.text=message)
	map_grid=GridContainer.new();map_grid.visible=false;center.add_child(map_grid)

func _build_story(form:VBoxContainer)->void:
	_entry(form,"story.id","스토리 ID");_entry(form,"story.start","시작 노드")
	_button(form,"apply_story","스토리 속성 적용",func():_apply_story();_refresh_lists())
	_group(form,"선택한 노드")
	var nodes:=ItemList.new();nodes.custom_minimum_size.y=100;nodes.item_selected.connect(_select_node);form.add_child(nodes);lists.nodes=nodes
	_entry(form,"node.id","노드 ID")
	var types:=_option(form,"node.type","노드 종류")
	for pair in [["dialogue","대사"],["battle","전투"],["branch","조건 분기"],["set","변수 설정"],["end","이야기 종료"]]:types.add_item(pair[1]);types.set_item_metadata(types.item_count-1,pair[0])
	types.item_selected.connect(func(_index):_node_type_visibility())
	_entry(form,"node.speaker","화자 캐릭터")
	var dialogue:=TextEdit.new();dialogue.custom_minimum_size.y=105;dialogue.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;_row(form,"대사",dialogue);fields["node.text"]=dialogue
	_option(form,"node.map","전투 맵")
	for pair in [["next","다음 노드"],["on_defeat","패배 시 노드"],["variable","변수 이름"],["value","설정값"],["equals","비교값"],["then","같으면"],["else","다르면"]]:_entry(form,"node."+str(pair[0]),pair[1],"1"if pair[0]in ["value","equals"]else"")
	_button(form,"apply_node","노드 적용",func():_apply_node();_refresh_nodes())
	var center:VBoxContainer=workspaces.stories;var tools:=HBoxContainer.new();center.add_child(tools)
	_button(tools,"add_node","+ 노드",_new_node);_button(tools,"remove_node","노드 삭제",_remove_node)
	_button(tools,"story_fit","전체 보기",func():story_view.fit_view())
	story_view=StoryView.new();story_view.size_flags_vertical=Control.SIZE_EXPAND_FILL;story_view.custom_minimum_size.y=320;center.add_child(story_view);story_view.node_selected.connect(_select_node)
	_text(center,"노드를 클릭하면 오른쪽에서 내용을 편집합니다. 연결선은 이야기 진행 방향입니다.",12)

func _build_project_tab()->void:
	var outer:=VBoxContainer.new();outer.name="프로젝트 설정";tabs.add_child(outer)
	_text(outer,"프로젝트 설정",22)
	_text(outer,"배포할 확장팩의 이름과 시작할 이야기를 정합니다.",13)
	_entry(outer,"project.name","확장팩 이름")
	_entry(outer,"project.id","프로젝트 ID","my_expansion")
	_entry(outer,"project.version","버전","1.0")
	_entry(outer,"project.entry","시작 스토리","intro")
	_text(outer,"프로젝트 폴더",14)
	project_path=LineEdit.new();project_path.placeholder_text="저장할 폴더를 선택하세요.";outer.add_child(project_path)
	_button(outer,"project_choose_folder","저장 폴더 선택",func():_choose_folder("save"))

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
	return project.original_catalog("characters" if table=="race" else "skills")

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
	var baseline:Dictionary=project.original_character(fields["character.base_race"].get_selected_id())
	return int(baseline.get("stats",{}).get(key,0))

func _base_race_changed(_index: int) -> void:
	var guard:=_refreshing;_refreshing=true
	for stat in ["hp","mp","atk","def","int","mdef","agi"]:
		for part in ["initial","growth"]:
			var key:String="character."+stat+"."+part
			if not fields[key+".enabled"].button_pressed:fields[key].value=_base_stat(stat+"."+part)
	_refreshing=guard
	_refresh_workbench()

func _refresh_lists() -> void:
	for kind in Project.KINDS:
		var list:ItemList=lists[kind];list.clear()
		var query:=str(_search[kind].text).strip_edges().to_lower() if _search.has(kind) else ""
		for index in project.content[kind].size():
			var row:Dictionary=project.content[kind][index]
			var name:=str(row.get("name",row.get("id","")))
			if not query.is_empty() and not (name+" "+str(row.get("id",""))).to_lower().contains(query):continue
			var changed:=project.changed_fields(kind,index).size() if kind in ["characters","skills"] else 0
			list.add_item(("● " if changed>0 else "")+name+"  ·  "+str(row.get("id","")))
			list.set_item_metadata(list.item_count-1,index)
			if index==int(selected[kind]):list.select(list.item_count-1)
	_fill_project_option("spawn.character","characters")
	_fill_project_option("node.map","maps")
	_fill_character_skills()
	for kind in ["characters","skills"]:_refresh_original_catalog(kind)

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
	if _pending_edit and not _refreshing:_commit_pending()
	var guard:=_refreshing;_refreshing=true
	selected[kind]=index
	var row:=_selected_record(kind)
	if row.is_empty():_refreshing=guard;_refresh_workbench();return
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
				fields[key+".enabled"].button_pressed=enabled;fields[key].editable=true
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
	_refreshing=guard;_refresh_workbench()

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
	if is_instance_valid(map_view):map_view.configure(data);map_view.set_map(_selected_record("maps"),project.content.characters);map_view.selected_cell=selected_cell
	for child in map_grid.get_children():map_grid.remove_child(child);child.queue_free()
	var map:=_selected_record("maps")
	if map.is_empty():return
	map_grid.columns=int(map.width)
	if int(map.width)*int(map.height)>256:return
	for y in range(1,int(map.height)+1):
		for x in range(1,int(map.width)+1):
			var point:=Vector2i(x,y);var cell:=_cell_at(map,point);var node:=Button.new()
			node.text=str(int(cell.height));node.custom_minimum_size=Vector2(28,28);node.tooltip_text="(%d, %d) 높이 %d / 지형 %d"%[x,y,int(cell.height),int(cell.terrain)]
			var style:=StyleBoxFlat.new();style.bg_color=Color.from_hsv(float(int(cell.terrain))/8.0,.3,.40)
			style.border_color=Color("ffd06b")if point==selected_cell else Color("536476")
			style.set_border_width_all(3 if point==selected_cell else 1);node.add_theme_stylebox_override("normal",style)
			node.pressed.connect(func():_select_cell(point));map_grid.add_child(node)

func _select_cell(point: Vector2i) -> void:
	selected_cell=point;map_cell_label.text="X %d  /  Y %d"%[point.x,point.y]
	if map_view==null or map_view.tool_mode=="select":
		var guard:=_refreshing;_refreshing=true
		var cell:=_cell_at(_selected_record("maps"),point)
		fields["map.cell_height"].value=int(cell.height);_select_number(fields["map.cell_terrain"],int(cell.terrain))
		_refreshing=guard
	_refresh_map_grid()

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
	if is_instance_valid(story_view):story_view.set_story(_selected_record("stories"))
	var list: ItemList=lists.nodes;list.clear()
	for node in _selected_record("stories").get("nodes",[]):list.add_item(str(node.id)+" · "+str(node.type))
	if list.item_count>0:
		selected.nodes=clampi(int(selected.nodes),0,list.item_count-1);list.select(int(selected.nodes));_select_node(int(selected.nodes))

func _select_node(index: int) -> void:
	var guard:=_refreshing;_refreshing=true
	selected.nodes=index;var nodes: Array=_selected_record("stories").get("nodes",[])
	if index<0 or index>=nodes.size():_refreshing=guard;return
	var node: Dictionary=nodes[index]
	fields["node.id"].text=str(node.id);_select_metadata(fields["node.type"],str(node.type))
	for key in ["speaker","next","on_defeat","variable","then","else"]:fields["node."+key].text=str(node.get(key,""))
	fields["node.text"].text=str(node.get("text",""));_select_metadata(fields["node.map"],str(node.get("map","")))
	fields["node.value"].text=JSON.stringify(node.get("value",1));fields["node.equals"].text=JSON.stringify(node.get("equals",1));_node_type_visibility()
	if is_instance_valid(story_view):story_view.selected_node=index;story_view.queue_redraw()
	_refreshing=guard

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
	if tabs.current_tab<4 and _selected_record(Project.KINDS[tabs.current_tab]).is_empty():return
	match tabs.current_tab:
		0:_apply_character()
		1:_apply_skill()
		2:_apply_map()
		3:_apply_node();_apply_story()

func _new_project() -> void:
	project.new_project();project.source_data=data
	for key in selected:selected[key]=0
	_refresh_all();_reset_history();_status("새 프로젝트를 만들었습니다. 기본 예제를 폼에서 바꿔 보세요.")

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
	if external_preview_enabled:
		launch_preview()
	else:play_requested.emit(str(saved.folder))

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

func _refresh_original_catalog(kind:String)->void:
	if not lists.has("original_"+kind):return
	var list:ItemList=lists["original_"+kind];var previous:int=int(_original_selected[kind]);list.clear()
	var query:=str(_original_search[kind].text).strip_edges().to_lower().replace("골렘","고렘")
	for row in project.original_catalog(kind):
		if not (str(row.id)+" "+str(row.name)).to_lower().replace("골렘","고렘").contains(query):continue
		list.add_item("%03d  %s"%[int(row.id),str(row.name)]);list.set_item_metadata(list.item_count-1,int(row.id))
		if int(row.id)==previous:list.select(list.item_count-1)
	buttons["import_original_"+kind].disabled=list.item_count==0
	if previous<0 and list.item_count>0:_original_selected[kind]=int(list.get_item_metadata(0));list.select(0)

func _show_original_hint(kind:String)->void:
	var id:int=int(_original_selected[kind]);var row:Dictionary=project.original_character(id) if kind=="characters" else project.original_skill(id)
	_status("원작 %s 선택 · ‘원작에서 편집본 만들기’ 또는 두 번 클릭으로 추가하세요."%str(row.get("name","")))

func _import_original(kind:String)->void:
	var id:int=int(_original_selected[kind]);var row:Dictionary=project.original_character(id) if kind=="characters" else project.original_skill(id)
	if row.is_empty():_status("정품 게임을 연결하면 원작 데이터를 선택할 수 있습니다.",true);return
	row.id=project.next_id(kind,"character"if kind=="characters"else"skill")
	project.update_record(kind,-1,row);selected[kind]=project.content[kind].size()-1
	_refresh_lists();_select_record(kind,int(selected[kind]));_checkpoint()
	_status("원작 기준을 보관한 편집본을 추가했습니다. 수치를 바꿔도 원본값은 유지됩니다.")

func _reset_record(kind:String)->void:
	var result:Dictionary=project.reset_record(kind,int(selected[kind]))
	if not result.ok:_status(str(result.get("error","정품 데이터가 필요합니다.")),true);return
	_select_record(kind,int(selected[kind]));_refresh_lists();_checkpoint();_status("선택한 항목을 원작 기준값으로 초기화했습니다.")

func _reset_field(kind:String,key:String)->void:
	var result:Dictionary=project.reset_field(kind,int(selected[kind]),key)
	if not result.ok:_status(str(result.get("error","원본값을 읽을 수 없습니다.")),true);return
	_select_record(kind,int(selected[kind]));_refresh_lists();_checkpoint();_status("선택한 수치를 원작값으로 초기화했습니다.")

func _refresh_workbench()->void:
	if not _chrome_ready:return
	_heading.text="  ·  "+str(project.descriptor.get("name","새 프로젝트"))+("  ● 수정됨"if _dirty else "")
	_connection.text="정품 기준값 연결됨" if not project.original_catalog("characters").is_empty() else "정품 미연결 · 원본값 확인 불가"
	_connection.modulate=Color("92c7ae") if data!=null else Color("c5a46c")
	if buttons.has("open_original_folder"):buttons.open_original_folder.disabled=data==null
	for kind in Project.KINDS:
		var record:=_selected_record(kind)
		_record_title[kind].text=str(record.get("name",record.get("id","항목 없음")))
		_record_summary[kind].text="%s  /  %s"%[str(project.descriptor.get("name","")),str(record.get("id","선택된 항목 없음"))]
	for kind in ["characters","skills"]:
		var record:=_selected_record(kind)
		var defaults:Dictionary=project.character_defaults(record) if kind=="characters"else project.skill_defaults(record)
		var available:=not defaults.is_empty()
		buttons["reset_character"if kind=="characters"else"reset_skill"].disabled=not available
		var changed:=0
		for key in original_labels:
			var prefix:="character."if kind=="characters"else"skill."
			if not str(key).begins_with(prefix):continue
			var field:=str(key).trim_prefix(prefix)
			var original=defaults.get("stats",{}).get(field) if kind=="characters"else defaults.get(field)
			original_labels[key].text=str(original)if original!=null else"—"
			var edited:bool=original!=null and int(fields[key].value)!=int(original)
			if kind=="characters":edited=edited and fields[str(key)+".enabled"].button_pressed
			if edited:changed+=1
			fields[key].get_line_edit().add_theme_color_override("font_color",Color("ffc978")if edited else Color("dce2eb"))
			fields[key].tooltip_text="원작: "+str(original)if original!=null else"정품 데이터를 연결하면 원본값을 표시합니다."
		_change_labels[kind].text=("원본과 다른 수치 %d개"%changed)if available else"정품 데이터 연결 후 원본 비교 · 초기화 가능"
	if is_instance_valid(map_view):
		map_view.configure(data)
		if _portrait!=null and data!=null:_portrait.texture=map_view.character_texture(str(fields["character.sprite_text"].text))
	if is_instance_valid(story_view):story_view.set_story(_selected_record("stories"))
	if buttons.has("undo"):buttons.undo.disabled=_history_cursor<=0;buttons.redo.disabled=_history_cursor>=_history.size()-1

func _field_value_changed(_value,key:String)->void:
	_queue_live_edit(key)
	if fields.get(key)is OptionButton and not _refreshing:_commit_pending.call_deferred()
func _queue_live_edit(key:String="")->void:
	if _refreshing or not _chrome_ready or _history_restoring:return
	var prefix:=key.get_slice(".",0)
	var kind:String={"character":"characters","skill":"skills","map":"maps","node":"stories","story":"stories","project":"project"}.get(prefix,"")
	if kind.is_empty()or key.begins_with("spawn."):return
	_pending_kind=kind;_pending_edit=true;_dirty=true;_refresh_workbench()

func _commit_pending()->void:
	if not _pending_edit or _refreshing or not _built:return
	var kind:=_pending_kind;_pending_edit=false;_pending_kind=""
	_flush_kind(kind);_checkpoint();_refresh_workbench()

func _flush_kind(kind:String)->void:
	if kind in Project.KINDS and _selected_record(kind).is_empty():return
	match kind:
		"characters":_apply_character()
		"skills":_apply_skill()
		"maps":_apply_map()
		"stories":_apply_node();_apply_story()
		"project":_sync_header()

func _workspace_changed(index:int)->void:
	_commit_pending()
	_last_form=Project.KINDS[index] if index<4 else"project"
	_refresh_workbench()

func _signature()->String:return JSON.stringify([project.descriptor,project.content]).sha256_text()
func _reset_history()->void:
	_history.clear();_history_cursor=-1;_saved_signature=_signature();_dirty=false;_pending_edit=false;_checkpoint()
func _checkpoint()->void:
	if not _built or _history_restoring:return
	var signature:=_signature()
	if _history_cursor>=0 and _history[_history_cursor].signature==signature:return
	while _history.size()>_history_cursor+1:_history.pop_back()
	_history.append({"signature":signature,"descriptor":project.descriptor.duplicate(true),"content":project.content.duplicate(true),"selected":selected.duplicate()})
	if _history.size()>100:_history.pop_front()
	_history_cursor=_history.size()-1;_dirty=signature!=_saved_signature
func undo()->void:
	if _history_cursor>0:_restore_history(_history_cursor-1)
func redo()->void:
	if _history_cursor+1<_history.size():_restore_history(_history_cursor+1)
func _restore_history(index:int)->void:
	_history_restoring=true;_pending_edit=false;_history_cursor=index
	var state:Dictionary=_history[index]
	project.descriptor=state.descriptor.duplicate(true);project.content=state.content.duplicate(true);selected=state.selected.duplicate()
	_refresh_all();_dirty=_signature()!=_saved_signature;_history_restoring=false;_refresh_workbench();_status("실행 취소"if index<_history.size()-1 else"다시 실행")

func _set_map_tool(mode:String)->void:
	map_view.tool_mode=mode
	for tool in ["select","height","terrain","place"]:buttons["map_tool_"+tool].modulate=Color("8fc4ff")if tool==mode else Color.WHITE
	_status("지도 도구: "+{"select":"선택","height":"높이 브러시","terrain":"지형 브러시","place":"캐릭터 배치"}.get(mode,mode))
func _paint_cell(point:Vector2i)->void:
	selected_cell=point
	if map_view.tool_mode=="place":_add_spawn()
	elif map_view.tool_mode in ["height","terrain"]:
		var map:=_selected_record("maps");var cell:=_cell_at(map,point).duplicate()
		if map_view.tool_mode=="height":cell.height=int(fields["map.cell_height"].value)
		else:cell.terrain=fields["map.cell_terrain"].get_selected_id()
		var found:=false
		for i in map.cells.size():
			if int(map.cells[i].x)==point.x and int(map.cells[i].y)==point.y:map.cells[i]=cell;found=true;break
		if not found:map.cells.append(cell)
	_refresh_map_grid();_refresh_spawns();_checkpoint()

func _request_new()->void:_confirm_discard(_new_project)
func _request_open()->void:_confirm_discard(func():_choose_folder("open"))
func _request_close()->void:_confirm_discard(func():closed.emit();queue_free())
func _confirm_discard(action:Callable)->void:
	if not _dirty:action.call();return
	var dialog:=ConfirmationDialog.new();dialog.title="저장하지 않은 변경";dialog.dialog_text="저장하지 않은 변경을 버리고 계속할까요?";dialog.ok_button_text="변경 버리고 계속";dialog.cancel_button_text="돌아가기";add_child(dialog)
	dialog.confirmed.connect(func():action.call();dialog.queue_free());dialog.canceled.connect(dialog.queue_free);dialog.popup_centered()

func _unhandled_key_input(event:InputEvent)->void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_F11:_toggle_fullscreen();get_viewport().set_input_as_handled();return
	if not (event.ctrl_pressed or event.meta_pressed):return
	match event.keycode:
		KEY_S:_commit_pending();_save_clicked()
		KEY_Z:_commit_pending();redo()if event.shift_pressed else undo()
		KEY_Y:_commit_pending();redo()
		KEY_N:_request_new()
		KEY_O:_request_open()
		KEY_F:
			if tabs.current_tab<4:_search[Project.KINDS[tabs.current_tab]].grab_focus()
		KEY_ENTER:_commit_pending();_test_clicked()
		_:return
	get_viewport().set_input_as_handled()

func _build_ai_tab()->void:
	var page:=VBoxContainer.new();page.name="AI 연결";page.add_theme_constant_override("separation",12);tabs.add_child(page)
	_text(page,"AI와 함께 확장팩 만들기",23)
	_text(page,"추천 작업 방식: AI 도구 연결 → 원하는 변경을 말로 요청 → 결과 확인 → 테스트 → 저장",14)
	_text(page,"Claude Code · OpenCode · Codex · Cursor 등 MCP를 지원하는 도구를 사용할 수 있습니다.",13)
	var bar:=HBoxContainer.new();page.add_child(bar)
	_mcp_client=OptionButton.new()
	for title in ["Claude Code / Claude Desktop","OpenCode V1","OpenCode V2","Codex","Cursor / Cline / Windsurf","일반 MCP 클라이언트"]:_mcp_client.add_item(title)
	bar.add_child(_mcp_client);_mcp_client.item_selected.connect(func(_i):_refresh_mcp_config())
	_button(bar,"mcp_start","AI 연결 시작",_start_mcp)
	_button(bar,"mcp_copy","연결 설정 복사",_copy_mcp_config)
	_button(bar,"mcp_stop","연결 종료",_stop_mcp)
	_mcp_status=_text(page,"AI 연결 꺼짐 · 연결할 도구를 고르고 ‘AI 연결 시작’을 누르세요.",13)
	var split:=HSplitContainer.new();split.size_flags_vertical=Control.SIZE_EXPAND_FILL;split.split_offset=650;page.add_child(split)
	var left:=VBoxContainer.new();left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;split.add_child(left)
	_text(left,"선택한 AI 도구의 연결 설정",16)
	_mcp_config=TextEdit.new();_mcp_config.editable=false;_mcp_config.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;_mcp_config.size_flags_vertical=Control.SIZE_EXPAND_FILL;left.add_child(_mcp_config)
	_text(left,"설정을 AI 도구에 추가한 뒤 에디터를 켜 둔 상태로 요청하세요.",12)
	var right:=VBoxContainer.new();right.custom_minimum_size.x=350;split.add_child(right)
	_text(right,"MCP로 할 수 있는 작업",16)
	_mcp_tools=RichTextLabel.new();_mcp_tools.size_flags_vertical=Control.SIZE_EXPAND_FILL;right.add_child(_mcp_tools)
	_mcp_tools.text="MCP 작업 도구 14개\n\nft2_read_project · 프로젝트 조회\nft2_list_originals · 원작 검색\nft2_get_record · 항목 조회\nft2_create_record · 새 항목 만들기\nft2_update_record · 항목 수정\nft2_reset_field · 수치 하나 초기화\nft2_reset_record · 원본으로 전체 초기화\nft2_validate · 검사\nft2_save · 저장\nft2_open · 프로젝트 열기\nft2_export · 공유 ZIP 내보내기\nft2_play · 별도 창 테스트\nft2_get_debug_output · 테스트 로그\nft2_stop_play · 테스트 중지"
	_refresh_mcp_config()

func _start_mcp()->void:
	_commit_pending()
	if bridge==null:bridge=EditorBridge.new()
	var result:Dictionary=bridge.start(self)
	if not result.ok:_status(str(result.get("error","AI 연결을 시작할 수 없습니다.")),true)
	_refresh_mcp_config();_update_mcp_status()
func _stop_mcp()->void:
	if bridge!=null:bridge.stop()
	_update_mcp_status()
func _update_mcp_status()->void:
	if _mcp_status==null:return
	var state:Dictionary=bridge.status()if bridge!=null else {"running":false}
	_mcp_status.text="AI 연결 대기 중 · 요청 %d회 · 최근 작업: %s"%[int(state.get("requests",0)),str(state.get("last_tool","없음"))]if state.running else"AI 연결 꺼짐 · ‘AI 연결 시작’을 누르세요."
	buttons.mcp_stop.disabled=not state.running

func _mcp_launch()->Dictionary:
	var suffix:=".exe"if OS.get_name()=="Windows"else""
	var executable:=OS.get_executable_path().get_base_dir().path_join("tools/ft2-convert/ft2-convert"+suffix)
	var connection:=ProjectSettings.globalize_path("user://editor_mcp_connection.json")
	if bridge!=null:connection=str(bridge.status().connection_file)
	if FileAccess.file_exists(executable):return {"command":executable,"args":["--editor-mcp","--connection",connection]}
	var script:=ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("tools/editor_mcp.py")
	return {"command":"python"if OS.get_name()=="Windows"else"python3","args":[script,"--connection",connection]}
func _refresh_mcp_config()->void:
	if _mcp_config==null:return
	var launch:=_mcp_launch();var command:Array=[launch.command];command.append_array(launch.args)
	var config:Dictionary
	match _mcp_client.selected:
		1:config={"$schema":"https://opencode.ai/config.json","mcp":{"ft2":{"type":"local","command":command,"enabled":true}}}
		2:config={"$schema":"https://opencode.ai/config.json","mcp":{"servers":{"ft2":{"type":"local","command":command,"protocol":"legacy"}}}}
		3:
			_mcp_config.text="[mcp_servers.ft2]\ncommand = "+JSON.stringify(launch.command)+"\nargs = "+JSON.stringify(launch.args)+"\n";return
		_:config={"mcpServers":{"ft2":launch}}
	_mcp_config.text=JSON.stringify(config,"\t")
func _copy_mcp_config()->void:
	_refresh_mcp_config();DisplayServer.clipboard_set(_mcp_config.text);_status("연결 설정을 복사했습니다. 선택한 AI 도구의 MCP 설정에 추가하세요.")

func launch_preview()->Dictionary:
	if data==null:return {"ok":false,"error":"정품 게임 데이터를 먼저 연결하세요."}
	if project_path.text.strip_edges().is_empty():return {"ok":false,"error":"프로젝트를 먼저 저장하세요."}
	var saved:=save_project(project_path.text.strip_edges())
	if not saved.ok:return saved
	var validation:=validate_project()
	if not validation.ok:return {"ok":false,"error":"확장팩 검사를 통과해야 테스트할 수 있습니다.","issues":validation.issues}
	stop_preview()
	var executable:=OS.get_executable_path();var folder:=executable.get_base_dir()
	var pack:=folder.path_join("FT2-External.pck")
	if not FileAccess.file_exists(pack):pack=folder.path_join("../Resources/FT2-External.pck").simplify_path()
	var arguments:=PackedStringArray()
	if FileAccess.file_exists(pack):arguments.append_array(["--path",pack.get_base_dir(),"--main-pack",pack])
	else:arguments.append_array(["--path",ProjectSettings.globalize_path("res://")])
	if DisplayServer.get_name()=="headless":arguments.append_array(["--headless","--audio-driver","Dummy"])
	arguments.append_array(["--log-file",ProjectSettings.globalize_path(_preview_log),"--","--engine-config="+ProjectSettings.globalize_path("user://editor_preview_connection.json"),"--source-root="+str(data.source_root),"--content-root="+str(data.repo_root),"--mod="+str(saved.folder)])
	var log_file:=FileAccess.open(_preview_log,FileAccess.WRITE)
	if log_file!=null:log_file.close()
	_preview_pid=OS.create_process(executable,arguments,false)
	_preview_error=""if _preview_pid>0 else"테스트 실행 창을 열 수 없습니다."
	_status("별도 창에서 테스트를 시작했습니다. 에디터와 AI 연결은 계속 사용할 수 있습니다."if _preview_pid>0 else _preview_error,_preview_pid<=0)
	return {"ok":_preview_pid>0,"pid":_preview_pid,"status":"running"if _preview_pid>0 else"failed"}
func stop_preview()->Dictionary:
	if _preview_pid>0 and OS.is_process_running(_preview_pid):OS.kill(_preview_pid)
	_preview_pid=-1
	return {"ok":true,"running":false}
func preview_status()->Dictionary:
	var running:=_preview_pid>0 and OS.is_process_running(_preview_pid)
	var tail:=""
	if FileAccess.file_exists(_preview_log):
		var text:=FileAccess.get_file_as_string(_preview_log);tail=text.right(12000)
		if data!=null:
			for pair in [[str(data.source_root),"<정품 폴더>"],[str(data.repo_root),"<개인 캐시>"]]:
				for form in [pair[0],str(pair[0]).replace("\\","/"),JSON.stringify(pair[0]).trim_prefix('"').trim_suffix('"')]:tail=tail.replace(form,pair[1])
	return {"ok":true,"running":running,"pid":_preview_pid if running else -1,"log_tail":tail,"has_errors":tail.contains("ERROR:"),"error":_preview_error}
func _process(delta:float)->void:
	if bridge!=null:bridge.poll()
	_bridge_clock+=delta
	if _bridge_clock>=.5:
		_bridge_clock=0;_update_mcp_status()
		if buttons.has("stop_play"):buttons.stop_play.disabled=not (_preview_pid>0 and OS.is_process_running(_preview_pid))
func _exit_tree()->void:
	prepare_close()
	if bridge!=null:bridge.stop()
	stop_preview()

func ui_scale_percent()->float:return _effective_ui_scale*100.0

func _apply_ui_scale()->void:
	if _scale_suspended or _scale_updating or not is_inside_tree():return
	var window:=get_window()
	if window.size.x<=0 or window.size.y<=0:return
	_scale_updating=true
	var physical:=Vector2(window.size)
	var desired:=minf(physical.x/1280.0,physical.y/840.0)
	if _ui_scale_option!=null and _ui_scale_option.selected>0:desired=[1.0,1.25,1.5,1.75,2.0][_ui_scale_option.selected-1]
	var limit:=minf(physical.x/1280.0,physical.y/720.0)
	_effective_ui_scale=clampf(desired,.5,maxf(.5,limit))
	var logical:=Vector2i(ceili(physical.x/_effective_ui_scale),ceili(physical.y/_effective_ui_scale))
	window.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_factor=1.0
	if window.content_scale_size!=logical:window.content_scale_size=logical
	if _ui_scale_label!=null:_ui_scale_label.text="%d%%"%roundi(ui_scale_percent())+(" · 화면 맞춤"if _effective_ui_scale<desired-.01 else "")
	_scale_updating=false

func _toggle_fullscreen()->void:
	var window:=get_window()
	if window.mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN]:
		window.mode=_windowed_mode
		if _windowed_mode==Window.MODE_WINDOWED:window.size=_windowed_size;window.position=_windowed_position
	else:
		_windowed_mode=window.mode;_windowed_size=window.size;_windowed_position=window.position
		window.mode=Window.MODE_FULLSCREEN
	_apply_ui_scale.call_deferred()

func prepare_close()->void:
	_scale_suspended=true
	if is_instance_valid(_scale_window)and _scale_window.size_changed.is_connected(_apply_ui_scale):_scale_window.size_changed.disconnect(_apply_ui_scale)

func _request_source_connection()->void:
	_commit_pending()
	_stop_mcp()
	source_connection_requested.emit()

func _open_original_folder()->void:
	if data!=null and DirAccess.dir_exists_absolute(str(data.source_root)):
		OS.shell_open(str(data.source_root))
	else:_status("원작 데이터 연결을 눌러 정품 폴더를 먼저 선택하세요.",true)
