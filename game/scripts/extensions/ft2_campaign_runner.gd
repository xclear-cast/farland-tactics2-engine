class_name FT2CampaignRunner
extends CanvasLayer
## Declarative expansion campaign. Original EVENT files are not executed here.

signal finished(result: String)
signal state_changed
signal map_started(map_reference: String, map_id: int)
signal quit_requested

var registry
var data
var battle
var vm
var view
var ui
var active := false
var completed := false
var story_id := ""
var node_id := ""
var waiting := ""
var variables: Dictionary = {}
var map_reference := ""
var character_slots: Dictionary = {}
var errors: Array[String] = []
var trace: Array[Dictionary] = []
var _story: Dictionary = {}
var _nodes: Dictionary = {}
var _pending_outcome := ""
var _panel: PanelContainer
var _title: Label
var _text: Label
var _choices: VBoxContainer
var _continue: Button
var _font: Font

func configure(source_data, combat, scenario, battle_view, interface) -> void:
	data=source_data;battle=combat;vm=scenario;view=battle_view;ui=interface
	registry=FT2Content.active.extensions if FT2Content.active!=null else null
	layer=30

func entry_story() -> String:
	return str(registry.entry_story) if registry!=null else ""

func _build_ui() -> void:
	var container:=Control.new();container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);container.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(container)
	_panel=PanelContainer.new();_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left=12;_panel.offset_right=-12;_panel.offset_top=-190;_panel.offset_bottom=-12;container.add_child(_panel)
	var margin:=MarginContainer.new()
	for side in ["left","top","right","bottom"]:margin.add_theme_constant_override("margin_"+side,12)
	_panel.add_child(margin)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",8);margin.add_child(box)
	_title=Label.new();_title.add_theme_font_size_override("font_size",19);box.add_child(_title)
	_text=Label.new();_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_text.custom_minimum_size=Vector2(560,76);box.add_child(_text)
	_choices=VBoxContainer.new();box.add_child(_choices)
	_continue=Button.new();_continue.text="계속";_continue.pressed.connect(continue_dialogue);box.add_child(_continue)
	for path in ["C:/Windows/Fonts/malgun.ttf","/mnt/c/Windows/Fonts/malgun.ttf","/System/Library/Fonts/AppleSDGothicNeo.ttc","/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"]:
		if FileAccess.file_exists(path):
			var face:=FontFile.new();face.data=FileAccess.get_file_as_bytes(path);_font=face;break
	if _font==null:
		var face:=SystemFont.new();face.font_names=PackedStringArray(["Apple SD Gothic Neo","Malgun Gothic","Noto Sans CJK KR","Arial"]);_font=face
	_panel.add_theme_font_override("font",_font)
	_title.add_theme_font_override("font",_font);_text.add_theme_font_override("font",_font);_continue.add_theme_font_override("font",_font)
	_panel.hide()

func start(reference: String = "") -> bool:
	if registry==null:return false
	var requested:=reference if reference!="" else entry_story()
	if not _select_story(requested):return false
	if _panel==null:_build_ui()
	active=true;completed=false;variables.clear();map_reference="";character_slots.clear();errors.clear();trace.clear();_pending_outcome=""
	_prepare_vm()
	battle.money=200;battle.rng=[167,19960,5150];battle.round_index=0;battle.source_index=-1
	_empty_units()
	_enter(str(_story.get("start","")))
	return errors.is_empty()

func _select_story(reference: String) -> bool:
	if not registry.stories.has(reference):return false
	story_id=reference;_story=registry.stories[reference];_nodes.clear()
	for node in _story.get("nodes",[]):_nodes[str(node.id)]=node
	return not _nodes.is_empty()

func _prepare_vm() -> void:
	vm.busy=false;vm.input_wait=false;vm.modal_wait=false;vm.mode=0;vm.current_event=-1;vm.loaded_event=-1;vm.control_mode=1
	vm.actor_sprites.clear();vm.actor_busy.clear();vm.dialogue.clear();vm.dialogue_halves.clear();vm.bitmap="";vm._hook.clear()
	vm.town.hide();vm.scene.busy=false
	ui._startup=false
	ui.dialog="";ui.resource_id=0;ui._parents.clear();ui._menu_stack.clear()

func _empty_units() -> void:
	var units: Array=[]
	for i in range(50):
		var bytes:=PackedByteArray();bytes.resize(124);bytes.fill(0);units.append(bytes)
	battle.units=units;battle.inventory.fill(0);battle.map_id=-1;battle.map_data={}
	battle.navigation.configure(battle.units,{},1)

func stop() -> void:
	active=false;completed=false;waiting="";_pending_outcome=""
	if _panel!=null:_panel.hide()

func blocks_input() -> bool:
	return active and waiting!="battle"

func handle_input(event: InputEvent) -> bool:
	if not blocks_input():return false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE,KEY_ENTER,KEY_KP_ENTER]:
		if waiting=="dialogue":continue_dialogue()
		return true
	return event is InputEventMouse or event is InputEventKey

func _clear_choices() -> void:
	for child in _choices.get_children():_choices.remove_child(child);child.queue_free()

func _show(title: String, text: String, continue_visible: bool = true) -> void:
	_title.text=title;_text.text=text;_continue.visible=continue_visible;_clear_choices();_panel.offset_top=-190;_panel.show()

func _enter(next_id: String) -> void:
	var budget:=128
	while budget>0:
		budget-=1
		if not _nodes.has(next_id):_fail("스토리 노드를 찾을 수 없습니다: "+next_id);return
		node_id=next_id
		var node: Dictionary=_nodes[node_id]
		trace.append({"story":story_id,"node":node_id,"type":str(node.get("type",""))})
		match str(node.get("type","")):
			"dialogue":
				waiting="dialogue";vm.mode=0
				var speaker:=str(node.get("speaker",""))
				var character_id:=str(registry.resolve_id(speaker,str(_story.get("pack_id","")))) if speaker!="" else ""
				if registry.characters.has(character_id):speaker=str(registry.characters[character_id].get("name",speaker))
				_show(speaker if speaker!="" else str(_story.get("name","이야기")),str(node.get("text","")))
				state_changed.emit();return
			"set":
				variables[str(node.get("variable",""))]=node.get("value")
				next_id=str(node.get("next",""))
			"branch":
				var choices: Array=node.get("choices",[])
				if not choices.is_empty():
					waiting="choice";vm.mode=0;_show(str(_story.get("name","선택")),str(node.get("text","선택하세요.")),false)
					for i in range(choices.size()):
						var button:=Button.new();button.text=str(choices[i].get("text","선택 %d"%(i+1)));button.add_theme_font_override("font",_font);button.pressed.connect(choose.bind(i));_choices.add_child(button)
					_panel.offset_top=-mini(440,190+choices.size()*38)
					state_changed.emit();return
				next_id=str(node.get("then","") if variables.get(str(node.get("variable","")))==node.get("equals") else node.get("else",""))
			"battle":
				_start_battle(node);return
			"end":
				waiting="end";completed=true;vm.mode=0
				var result:=str(node.get("result","completed"))
				_show(str(_story.get("name","확장팩")),str(node.get("text","확장팩을 완료했습니다.")),false)
				var restart:=Button.new();restart.text="처음부터";restart.add_theme_font_override("font",_font);restart.pressed.connect(func():start(story_id));_choices.add_child(restart)
				var quit_button:=Button.new();quit_button.text="종료";quit_button.add_theme_font_override("font",_font);quit_button.pressed.connect(func():quit_requested.emit());_choices.add_child(quit_button)
				_panel.offset_top=-266
				finished.emit(result);state_changed.emit();return
			_:_fail("지원하지 않는 스토리 노드입니다: "+str(node.get("type","")));return
	_fail("대기 없는 스토리 순환이 너무 깁니다.")

func continue_dialogue() -> void:
	if not active or waiting!="dialogue":return
	_enter(str(_nodes[node_id].get("next","")))

func choose(index: int) -> void:
	if not active or waiting!="choice":return
	var choices: Array=_nodes[node_id].get("choices",[])
	if index<0 or index>=choices.size():return
	var selected: Dictionary=choices[index]
	var assignments: Dictionary=selected.get("set",{})
	for key in assignments:variables[str(key)]=assignments[key]
	_enter(str(selected.get("next","")))

func _start_battle(node: Dictionary, restoring: bool = false) -> void:
	map_reference=str(registry.resolve_id(node.get("map",""),str(_story.get("pack_id",""))))
	if not registry.maps.has(map_reference):_fail("확장 맵을 찾을 수 없습니다: "+map_reference);return
	var definition: Dictionary=registry.maps[map_reference]
	var numeric_id:=int(registry.map_id(map_reference))
	var normalized: Dictionary=data.load_map(numeric_id)
	if normalized.is_empty():_fail("확장 맵을 구성하지 못했습니다: "+map_reference);return
	if not restoring:
		var spawned: Dictionary=registry.spawn_placements(definition,battle)
		if not spawned.get("issues",[]).is_empty():_fail("배치 구성 실패: "+str(spawned.issues));return
		battle.units=spawned.units;character_slots=spawned.get("character_slots",{});battle.rng=spawned.get("rng",battle.rng)
		for unit in battle.units:unit.encode_u32(92,0);unit.encode_u32(96,0)
		battle.round_index=0
	battle.map_id=numeric_id;battle.map_data=normalized;battle.source_index=-1;battle.event_id=-1
	battle.selected_slot=-1;battle.substate=0;battle.pending_plan.clear();battle._preview.clear();battle.highlights.clear()
	battle._hook_groups.clear();battle._waiting_hook=false;battle._modal_waiting=false;battle._pickup_active=false
	battle._pickup_stage="";battle._pickup_candidate=-1;battle._growth_active=false;battle._growth_notices.clear();battle._hook_response_pending=false;battle.post_state=-1
	battle._return_phase="player";battle.navigation.configure(battle.units,normalized,1);battle._set_phase("player")
	vm.mode=1;vm.busy=false;vm.current_event=-1;vm.control_mode=1;vm.stage_title=str(definition.get("name",map_reference));vm.objective=str(node.get("objective","모든 적을 쓰러뜨리세요."))
	waiting="battle";_panel.hide();battle.changed.emit();view.set_map(numeric_id);view.sync_actor_visuals()
	for i in range(10):
		if battle.units[i].decode_u16(0)!=0:view.center_on_unit(i);break
	map_started.emit(map_reference,numeric_id);state_changed.emit()

func on_battle_hook(request: Dictionary) -> void:
	if not active:return
	var label:=str(request.get("label","")).to_upper()
	if str(request.get("kind",""))=="terminal" and label in ["COMPLETE","GAMEOVER"]:
		_pending_outcome="victory" if label=="COMPLETE" else "defeat"
		vm.mode=0
	battle.resume_hook(false)

func advance(_milliseconds: int) -> void:
	if not active or waiting!="battle":return
	if _pending_outcome!="":
		var result:=_pending_outcome;_pending_outcome="";_resolve_battle(result);return
	if battle.phase not in ["player","enemy","status"]:return
	var allies:=0;var enemies:=0
	for unit in battle.units:
		if unit.decode_u16(0)==0 or unit.decode_s16(38)<=0 or unit.decode_u16(16) in [1,9]:continue
		if unit.decode_u16(18)==0:allies+=1
		elif not unit.decode_u16(18) in [1,7]:enemies+=1
	if allies==0:_resolve_battle("defeat")
	elif enemies==0:_resolve_battle("victory")

func _resolve_battle(result: String) -> void:
	if waiting!="battle":return
	variables["last_battle"]=result
	trace.append({"story":story_id,"node":node_id,"battle_result":result})
	var node: Dictionary=_nodes[node_id]
	var next_id:=str(node.get("next","") if result=="victory" else node.get("on_defeat",node.get("next","")))
	vm.mode=0;_enter(next_id)

func _fail(message: String) -> void:
	active=true;waiting="error";vm.mode=0;errors.append(message);_show("확장팩 오류",message,false);state_changed.emit()

func snapshot_state() -> Dictionary:
	var units:=PackedByteArray()
	for unit in battle.units:units.append_array(unit)
	return {"schema":2,"kind":"ft2-expansion-save","profile_id":FT2Content.active.profile_id,
		"story":story_id,"node":node_id,"waiting":waiting,"completed":completed,"variables":variables.duplicate(true),
		"map":map_reference,"character_slots":character_slots.duplicate(true),"units_hex":units.hex_encode(),
		"inventory_hex":battle.inventory.hex_encode(),"money":battle.money,"round_index":battle.round_index,"rng":battle.rng.duplicate()}

func slot_path(index: int) -> String:
	return FT2Content.save_root().path_join("extension%02d.json"%index)

func has_slot(index: int) -> bool:
	return FileAccess.file_exists(slot_path(index))

func save_slot(index: int) -> Error:
	if not active:return ERR_UNAVAILABLE
	if waiting=="battle" and (battle.phase!="player" or battle.substate!=0):return ERR_BUSY
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FT2Content.save_root()))
	var state:=snapshot_state();state["saved_at"]=Time.get_datetime_dict_from_system()
	var file:=FileAccess.open(slot_path(index),FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_string(JSON.stringify(state,"\t"));file.close();return OK

func load_slot(index: int) -> bool:
	if not has_slot(index):return false
	var state=JSON.parse_string(FileAccess.get_file_as_string(slot_path(index)))
	if not state is Dictionary or state.get("schema",0)!=2 or state.get("profile_id","")!=FT2Content.active.profile_id:return false
	if not _select_story(str(state.get("story","")))or not _nodes.has(str(state.get("node",""))):return false
	if _panel==null:_build_ui()
	var raw:=str(state.get("units_hex","")).hex_decode();var inventory:=str(state.get("inventory_hex","")).hex_decode()
	if raw.size()!=6200 or inventory.size()!=320:return false
	active=true;completed=bool(state.get("completed",false));variables=state.get("variables",{}).duplicate(true);character_slots=state.get("character_slots",{}).duplicate(true)
	errors.clear();trace.clear();_pending_outcome="";_prepare_vm()
	var units: Array=[]
	for slot in range(50):units.append(raw.slice(slot*124,(slot+1)*124))
	battle.units=units;battle.inventory=inventory;battle.money=int(state.get("money",0));battle.round_index=int(state.get("round_index",0));battle.rng=state.get("rng",[167,19960,5150]).duplicate()
	node_id=str(state.node)
	if str(state.get("waiting",""))=="battle":_start_battle(_nodes[node_id],true)
	else:_enter(node_id)
	return errors.is_empty()

func slot_header(index: int) -> Dictionary:
	if not has_slot(index):return {}
	var state=JSON.parse_string(FileAccess.get_file_as_string(slot_path(index)))
	if not state is Dictionary or state.get("schema",0)!=2:return {}
	var stamp: Dictionary=state.get("saved_at",{})
	var title:=str(state.get("story","Expansion"))+" / "+str(state.get("node",""))
	return {"stage":1,"round_index":int(state.get("round_index",0)),"title_cp949_raw_hex":data.encode_cp949(title).hex_encode(),
		"system_time_words":[int(stamp.get("year",0)),int(stamp.get("month",0)),int(stamp.get("weekday",0)),int(stamp.get("day",0)),int(stamp.get("hour",0)),int(stamp.get("minute",0)),int(stamp.get("second",0)),0]}
