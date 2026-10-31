class_name FT2Interface
extends RefCounted
## Indexed Win95 UI controller. All glyphs are provided by the CPU native-font renderer.
signal load_requested(index: int)
signal save_requested(index: int)
signal new_game_requested
signal quit_requested
signal exit_confirmation_requested
signal settings_changed(settings: Dictionary)
signal fullscreen_requested
signal overview_requested
signal cursor_refresh_requested(point: Vector2i)
signal main_service_requested(now_ms:int)
signal message_presentation_requested(operation:String,request:Dictionary)
signal message_wait_requested(operation:String,request:Dictionary)
signal unit_window_requested(operation:String,request:Dictionary)
signal stage_selection_finished(result:int)
var data
var _battle_ref: WeakRef
var _vm_ref: WeakRef
var battle:
	get: return _battle_ref.get_ref()
var vm:
	get: return _vm_ref.get_ref()
var dialog := ""
var resource_id := 0
var payload: Dictionary = {}
var selection := 0
var scroll := 0
var quantity := 1
var settings := {"music":true,"effects":true,"music_volume":1.0,"effect_volume":1.0,"message_speed":1,"battle_animation":true,"forced_stage":0,"complete_flag":0}
var menu_rows: Array = []
var menu_position := Vector2i(160,120)
var _menu: Dictionary = {}
var _template: Dictionary = {}
var _control_rects: Dictionary = {}
var _list_rect := Rect2i()
var _elapsed := 0
var _list: Array = []
var _title := ""
var _modal_vm := false
var _unit_slot := 0
var _shop_items: Array = []
var _exp_allocations: Array = []
var _exp_mode := "balance"
var _hover_slot := -1
var _pointer_x := 0
var _hover_cell := Vector2i(-1,-1)
var forced_stage := false
var _body_text := ""
var _choice_default := 7
var _row_rects: Array[Rect2i] = []
var _menu_stack: Array[Dictionary] = []
var _startup := false
var stage_select=preload("res://scripts/ui/ft2_stage_select.gd").new()
var _stage_scrollbar:Dictionary={}
var _stage_scroll_capture:=""
var _stage_thumb_offset:=0
var _stage_search_prefix:=""
var input_clock_provider:Callable
var source_double_click_ms:=500 # Portable provided-profile fallback, USER SetDoubleClickTime(0).
var _listbox_input=preload("res://scripts/ui/ft2_listbox_input.gd").new()
var _stage_scroll_controller=preload("res://scripts/ui/ft2_scroll_controller.gd").new()
var experience
var unit_panel
var _units_tab := 0
var _unit_list_origin := ""
var _parents: Array[Dictionary] = []
var _settings_before: Dictionary = {}
var _dialog_outer:=Rect2i()
var _dialog_origin:=Vector2i.ZERO
var source_fullscreen:=true
var unit_window_create_provider:Callable
var _unit_window
var _is_unit_window_panel:=false
var _unit_window_owner:WeakRef
var unit_window_exists:bool:
	get:return _unit_window!=null and _unit_window.exists
var unit_window_visible:bool:
	get:return _unit_window!=null and _unit_window.visible
var unit_window_panel:
	get:return _unit_window.panel if _unit_window!=null else null
var persistence_enabled:=true
var _units_forced_modal:=false
var _overwrite_pending:=-1
var _quantity_text:="1"
var _quantity_replace:=true
var _quantity_caret:=1
var _caret_epoch:=0
var _quantity_total:=0
var _quantity_after:=0
var _dragging:=false
var _drag_pointer:=Vector2i.ZERO
var _drag_origin:=Vector2i.ZERO
var _focus_control:=1
var _pressed_control:=-1
var _captured_control:=-1
var _keyboard_control:=-1
var _message_presentation:Dictionary={}
var _message_wait:Dictionary={}
var _spin_pressed:=0
var _spin_capture:=0
var _default_button:=1
const SETTING_CONTROLS:={1009:"swap_mouse",1010:"skip_zoom",1011:"skip_palette",1012:"skip_effect",1015:"show_occluded",1014:"skip_ally",1013:"skip_enemy"}
var slot_header_provider:Callable
var preview_unit: Callable
var music_index_provider:Callable
var _bgm_preview_index:=-1
const STATE_NAMES := ["정상","기절","독","잠","석화","냉동","침묵","매료","마비","불가시","준민","부유"]
const UI_FONT := {"family":"굴림","height":-12,"weight":400,"italic":false}
const CUSTOM_FONT := {"family":"바탕","height":16,"weight":700,"italic":false}

func configure(store, combat, scenario,subscribe_source:bool=true) -> void:
	data = store; _battle_ref = weakref(combat); _vm_ref = weakref(scenario)
	_listbox_input.encode=Callable(data,"encode_cp949");_listbox_input.decode=Callable(data,"decode_cp949")
	_listbox_input.set_double_click_time(source_double_click_ms)
	if FT2Content.exists("user://settings.json"):
		var saved = JSON.parse_string(FT2Content.text("user://settings.json"))
		if saved is Dictionary: settings.merge(saved,true)
	_menu = data.read_json("data/port_ready/ui/FTO_O/menu_103_lang1042.json")
	if subscribe_source:
		vm.ui_requested.connect(_vm_request)
		vm.complete_flag_requested.connect(_complete_flag)
		vm.raw_globals["Main/CompleteFlag"]=int(settings.get("complete_flag",0))
		vm.save_requested.connect(_script_save)
		if battle.has_signal("confirmation_requested"): battle.confirmation_requested.connect(_confirm_magic)
		if battle.has_signal("modal_requested"): battle.modal_requested.connect(_battle_modal)
		_unit_window=preload("res://scripts/ui/ft2_unit_window.gd").new(self)
	experience = preload("res://scripts/experience/ft2_exp_dialog.gd").new()
	experience.configure(data,battle,vm)
	experience.finished.connect(_experience_finished)
	experience.cursor_refresh_requested.connect(_refresh_cursor)
	unit_panel = preload("res://scripts/ui/ft2_unit_panel.gd").new()
	unit_panel.configure(data,battle,vm)

func _script_save(index: int) -> void:
	if index < 0: open_save(true)
	else: save_requested.emit(index)

func _vm_request(request: Dictionary) -> void:
	payload = request.duplicate(true)
	_modal_vm = bool(vm.modal_wait)
	match str(request.kind):
		"shop": _shop_items = request.items; open_shop()
		"choice": _open("choice",int(request.get("resource",126)),str(request.text).trim_prefix("+").replace("_"," "))
		"message":
			_open("message",0,str(request.get("text","")));_begin_message_presentation()
		"experience":
			dialog = "experience"; resource_id = 162
			if not experience.open(int(request.pool)): vm.errors.append("Source EXP dialog precondition failed")
		"scene_growth":
			_elapsed = 0; _open("scene_growth",0,str(request.text));_begin_message_presentation()
		"town_menu":
			menu_rows.clear()
			for row in request.rows: menu_rows.append({"id":int(row.index),"text":str(row.caption),"town":true,"children":[]})
			menu_rows.append({"id":40028,"text":"불러오기(&L)","children":[]})
			menu_rows.append({"id":40029,"text":"저장하기(&S)","children":[]})
			dialog = "menu"; menu_position = Vector2i(350,180);selection=-1

func _confirm_magic(plan: Dictionary) -> void:
	payload = plan.duplicate(true)
	menu_rows = _menu.items[4 if not plan.get("ordered_targets",[]).is_empty() else 5].children.duplicate(true)
	dialog = "menu"; menu_position = Vector2i(240,220);selection=-1

func _battle_modal(request: Dictionary) -> void:
	payload = request.duplicate(true); _modal_vm = false
	_elapsed = 0
	var message := str(request.get("text",""))
	if request.get("kind","") == "round": message = "턴%d" % int(request.get("round",0))
	elif request.get("kind","") == "learned_skill": message = FT2Content.ui_text("skill_learned","%s: %s 습득") % [_unit_name(int(request.unit_slot)),str(data.load_table("magic")[int(request.skill_id)].name)]
	elif request.get("kind","") == "pickup_item": message = "%s(을)를 손에 넣었다." % str(data.load_table("item")[int(request.item_id)].name)
	elif request.get("kind","") == "pickup_capacity": message = FT2Content.ui_text("inventory_full","소지품 공간이 부족합니다.")
	elif request.get("kind","") == "pickup_gold": message = FT2Content.ui_text("currency_received","골드 %d 획득") % int(request.amount)
	elif request.get("kind","") == "pickup_found": message = "뭔가 찾았다!"
	elif request.get("kind","") == "levelup": message = FT2Content.ui_text("level_changed","%s: 레벨 %d") % [_unit_name(int(request.unit_slot)),int(request.level)]
	_open("battle_message",0,message)
	_begin_message_presentation()

func _open(kind: String, template_id: int, title: String = "") -> void:
	_listbox_input.destroy_control();_stage_search_prefix=""
	_stage_scroll_controller.cancel();_stage_scroll_capture=""
	dialog = kind; resource_id = template_id; selection = 0; scroll = 0; quantity = 1;_elapsed=0
	_list.clear()
	_quantity_text="1";_quantity_replace=false;_quantity_caret=0;_caret_epoch=0;_dragging=false;_pressed_control=-1;_captured_control=-1;_keyboard_control=-1;_spin_pressed=0;_spin_capture=0;_focus_control=1073 if kind=="buy_quantity" else (1086 if kind=="sell_quantity" else 1)
	_template = {}
	var path := "data/port_ready/ui/FTO_O/dialog_%d_lang1042.json" % template_id
	if FT2Content.exists(data.resolve(path)): _template = preload("res://scripts/ui/ft2_widgets.gd").dialog_template(data,template_id)
	_title = title if title != "" else str(_template.get("title",{}).get("value",""))
	_body_text = ""
	if kind in ["choice","end_turn","quit","overwrite","leave_shop"]:
		_choice_default = 6 if title.begins_with("*") else 7
		_body_text = title.trim_prefix("*")
		_title = str(_template.get("title",{}).get("value","확인"))
	_default_button=1
	for row in _template.get("controls",[]):
		if row.class_name=="BUTTON" and (str(row.style).hex_to_int()&15)==1:_default_button=int(row.id)
	if kind not in ["buy_quantity","sell_quantity"]:_focus_control=_default_button
	if kind in ["choice","end_turn","quit","overwrite","leave_shop"]:
		_focus_control=_choice_default;_default_button=_choice_default
	_control_rects.clear(); _list_rect = Rect2i()
	_row_rects.clear()
	if kind in ["buy_quantity","sell_quantity"]:_quantity_update_fields()
	if not _template.is_empty():
		var d: Array = _template.rect_dialog_units
		var size:Vector2i=preload("res://scripts/ui/ft2_widgets.gd").dlu_rect(d,Vector2i.ZERO,preload("res://scripts/ui/ft2_widgets.gd").dialog_base(template_id)).size
		_dialog_outer=Rect2i((Vector2i(640,480)-size-Vector2i(6,25))/2,size+Vector2i(6,25))
		var origin:=_dialog_outer.position+Vector2i(3,22); _dialog_origin=origin
		for row in _template.controls:
			var r: Array = row.rect_dialog_units
			var rect:Rect2i=preload("res://scripts/ui/ft2_widgets.gd").dlu_rect(r,origin,preload("res://scripts/ui/ft2_widgets.gd").dialog_base(template_id))
			_control_rects[int(row.id)] = rect
			_row_rects.append(rect)
			if row.class_name == "LISTBOX" and rect.size.y > _list_rect.size.y: _list_rect = rect
		if kind=="bgm":_control_rects[61536]=Rect2i(_dialog_outer.position+Vector2i(_dialog_outer.size.x-21,5),Vector2i(16,14))

func _message_commands()->Array[Dictionary]:
	var out:Array[Dictionary]=[]
	var count:int=data.encode_cp949(_title).size();var left:=int((74-count)*4)
	out.append_array(preload("res://scripts/ui/ft2_widgets.gd").game_panel(left,210,int((count+3)/2),1))
	_game_text(out,_title,Vector2i(left+18,228))
	return out

func _begin_message_presentation()->void:
	_message_wait={"text":_title,"kind":dialog,"source_mode":vm.mode,"source_format_null":bool(payload.get("source_format_null",false)),"duration_ms":int(payload.get("duration_ms",0)),"timer_id":100,"interval_ms":600}
	#430750(NULL) waits without invalidating, clearing or rendering either surface.
	if payload.get("source_format_null",false):message_wait_requested.emit("begin",_message_wait.duplicate(true));return
	_message_presentation={"commands":_message_commands(),"text":_title,"kind":dialog,"source_mode":vm.mode,"source_format_null":false}
	if not message_presentation_requested.get_connections().is_empty():message_presentation_requested.emit("begin",_message_presentation.duplicate(true))
	message_wait_requested.emit("begin",_message_wait.duplicate(true)) #430825 draw precedes43082F mode7/timer setup.

func close(result: int = 6) -> void:
	if dialog in ["stage_select","bgm"]:_listbox_input.destroy_control();_stage_search_prefix=""
	if dialog=="stage_select":
		stage_select_message(0x111,2 if result==7 else 1);return
	if _is_unit_window_panel and dialog=="units" and _parents.is_empty() and _unit_window_owner!=null:
		var owner=_unit_window_owner.get_ref()
		if owner!=null:owner.destroy_unit_window(true);return
	if not _message_presentation.is_empty() or not _message_wait.is_empty():
		var presentation:Dictionary=_message_presentation.duplicate(true);_message_presentation.clear()
		var wait_state:Dictionary=_message_wait.duplicate(true);_message_wait.clear()
		var was_vm:=_modal_vm;_modal_vm=false
		dialog="";resource_id=0;_list.clear();menu_rows.clear();_menu_stack.clear()
		if not _parents.is_empty():_restore_parent()
		if not wait_state.is_empty():message_wait_requested.emit("end",wait_state)
		if not presentation.is_empty() and not message_presentation_requested.get_connections().is_empty():message_presentation_requested.emit("end",presentation)
		if was_vm:vm.modal_result(result)
		return
	if dialog=="leave_shop":
		_restore_parent()
		if result==6:close(6)
		return
	if dialog=="overwrite" and result==6:
		var slot:=_overwrite_pending;_overwrite_pending=-1
		if not _parents.is_empty():_restore_parent()
		_parents.clear();dialog="";_modal_vm=false;save_requested.emit(slot);return
	if not _parents.is_empty():
		_restore_parent(); return
	var startup_cancel := _startup and result == 7
	if dialog=="bgm" and result==7 and (int(music_index_provider.call()) if music_index_provider.is_valid() else _bgm_preview_index)!=int(payload.get("old_music",-1)):vm.music_requested.emit(int(payload.get("old_music",-1)))
	if dialog=="settings" and result==7: settings=_settings_before.duplicate(true)
	_startup = false
	if dialog == "end_turn" and result == 6:
		dialog = ""; _menu_stack.clear(); battle.end_turn(); return
	var was_vm := _modal_vm; _modal_vm = false
	dialog = ""; resource_id = 0; _list.clear(); menu_rows.clear(); _menu_stack.clear()
	if was_vm: vm.modal_result(result)
	if startup_cancel: quit_requested.emit()

func advance(ms: int) -> void:
	if _unit_window!=null and _unit_window.exists and _unit_window.panel!=null:_unit_window.panel.advance(ms)
	_elapsed += ms
	if dialog=="units":unit_panel.advance_scroll()
	service_input_timers()
	if dialog=="bgm" and ms>0:main_service_requested.emit(_elapsed) #403F60 timer0/requested1ms; coalesced UI pump delivery.
	if dialog == "experience": experience.advance(ms); return
	if dialog == "battle_message" and int(payload.get("duration_ms",0)) > 0:
		if _elapsed >= int(payload.duration_ms): _dismiss_battle_modal()
	if dialog == "scene_growth" and _elapsed >= int(payload.get("duration_ms",4000)): close()

func blocks_outer_frame() -> bool:
	if _unit_window!=null and _unit_window.blocks_frame():return true
	if dialog=="units" and not source_fullscreen and not _units_forced_modal: return false
	return dialog != ""

func _dismiss_battle_modal() -> void:
	close()
	if battle.has_method("finish_modal"): battle.finish_modal()
	elif battle.has_method("dismiss_modal"): battle.dismiss_modal()
	elif battle.has_method("resume_modal"): battle.resume_modal()

func handle_input(event: InputEvent) -> bool:
	if dialog=="units":
		unit_panel.input_clock_provider=input_clock_provider;unit_panel.source_double_click_ms=source_double_click_ms
		if unit_panel.handle_scroll_input(event):return true
	if (dialog=="stage_select" or _uses_detail_scrollbar()) and _stage_scroll_capture!="":
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
			if _stage_scroll_capture=="thumb":
				# USER14:09EC..09F7 consumes the final release coordinates even
				# when no separate WM_MOUSEMOVE arrived at that position.
				_configure_stage_scroll_input()
				_apply_stage_scroll_commands(_stage_scroll_controller.move(Vector2i(event.position),_stage_scroll_geometry()))
			_apply_stage_scroll_commands(_stage_scroll_controller.release());return true
		if event is InputEventMouseMotion:
			_configure_stage_scroll_input()
			_apply_stage_scroll_commands(_stage_scroll_controller.move(Vector2i(event.position),_stage_scroll_geometry()))
			return true
	if event is InputEventKey and event.keycode == KEY_CTRL: vm.control_held = event.pressed
	if dialog == "experience": return experience.handle_input(event)
	if dialog!="" and event is InputEventKey and event.keycode==KEY_SPACE and (_button_at_focus() or _keyboard_control>=0):
		if event.pressed:
			if not event.echo and not _button_disabled(_focus_control):_keyboard_control=_focus_control;_pressed_control=_focus_control
			return true
		if _keyboard_control>=0:
			var captured:=_keyboard_control;_keyboard_control=-1;_pressed_control=-1
			if captured==_focus_control and not _button_disabled(captured):
				var activation:=InputEventMouseButton.new();activation.pressed=true;activation.button_index=MOUSE_BUTTON_LEFT;activation.position=_control_rects[captured].get_center();return _dialog_click(activation)
		return true
	if event is InputEventKey and event.pressed:
		if dialog != "": return _dialog_key(event)
		match event.keycode:
			KEY_F1: command(40028); return true
			KEY_F2: command(40010); return true
			KEY_F4: fullscreen_requested.emit(); return true
			KEY_F5: command(40029); return true
			KEY_F10: command(40009); return true
			KEY_F11: command(40012); return true
			KEY_F12: command(40004); return true
	if dialog != "":
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
			if not event.pressed and _captured_control>=0:
				var captured:=_captured_control;_captured_control=-1;_pressed_control=-1
				if _control_rects.has(captured) and _control_rects[captured].has_point(Vector2i(event.position)):
					var activation:InputEventMouseButton=event.duplicate();activation.pressed=true;return _dialog_click(activation)
				return true
			if not event.pressed and _spin_capture!=0:_spin_pressed=0;_spin_capture=0;return true
			if event.pressed:
				var target:=_button_at(Vector2i(event.position))
				if target>=0:
					if _button_disabled(target):return true
					_captured_control=target;_pressed_control=target
					if target!=61536:_set_focus_control(target)
					if dialog=="stage_select" and target in [1,2]:_default_button=target
					return true
		if _dragging and event is InputEventMouseButton and not event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			_dragging=false
			if dialog=="units":settings["unit_window_rect"]=[_dialog_outer.position.x,_dialog_outer.position.y,_dialog_outer.size.x,_dialog_outer.size.y];_persist_settings()
			return true
		if event is InputEventMouseMotion:
			if _captured_control>=0:
				_pressed_control=_captured_control if _control_rects[_captured_control].has_point(Vector2i(event.position)) else -1;return true
			if _spin_capture!=0:
				var spin:Rect2i=_control_rects[_focus_control];spin.position.x=spin.end.x-17;spin.size.x=17
				var side:=1 if event.position.y<spin.get_center().y else -1
				_spin_pressed=_spin_capture if spin.has_point(Vector2i(event.position)) and side==_spin_capture else 0;return true
			if _dragging:_move_dialog(_drag_origin+Vector2i(event.position)-_drag_pointer);return true
			if dialog == "menu":
				selection = _menu_hit(Vector2i(event.position),menu_rows,menu_position)
			return true
		if event is InputEventMouseButton and event.pressed:
			return _dialog_click(event)
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and vm.mode == 1:
		open_action_menu(Vector2i(event.position)); return true
	return vm.handle_input(event)

func _dialog_key(event: InputEventKey) -> bool:
	if dialog=="stage_select":return _stage_select_key(event)
	if dialog == "battle_message": _dismiss_battle_modal(); return true
	if dialog == "message": close(); return true
	if dialog == "scene_growth": close(); return true
	if dialog=="bgm" and _focus_control==1101 and _listbox_key(event):return true
	if dialog=="units" and unit_panel.handle_key(event):return true
	if event.keycode==KEY_TAB and dialog!="menu":
		var order:=_focus_order()
		if not order.is_empty():
			var index:=order.find(_focus_control);_set_focus_control(order[posmod(index+(-1 if event.shift_pressed else 1),order.size())])
			_quantity_replace=true
		return true
	if dialog=="settings":
		if event.alt_pressed and event.keycode<128:
			for row in _template.controls:
				var label:=str(row.get("title",{}).get("value",""));var at:=label.find("&")
				if at>=0 and label.substr(at+1,1).to_upper()==String.chr(event.keycode).to_upper():_focus_control=int(row.id);_toggle_setting(_focus_control);return true
		if event.keycode==KEY_SPACE and _focus_control in SETTING_CONTROLS.keys()+[1090,1091]:_toggle_setting(_focus_control);return true
		if event.keycode in [KEY_LEFT,KEY_UP,KEY_RIGHT,KEY_DOWN] and _focus_control in [1090,1091]:_focus_control=2181-_focus_control;_toggle_setting(_focus_control);return true
	if dialog in ["buy_quantity","sell_quantity"] and _focus_control in [1073,1086]:
		if event.ctrl_pressed and event.keycode==KEY_A:_quantity_replace=true;return true
		var digit:=-1
		if event.keycode>=KEY_0 and event.keycode<=KEY_9:digit=int(event.keycode-KEY_0)
		elif event.keycode>=KEY_KP_0 and event.keycode<=KEY_KP_9:digit=int(event.keycode-KEY_KP_0)
		if digit>=0:_quantity_insert(str(digit));return true
		if event.keycode in [KEY_BACKSPACE,KEY_DELETE]:
			if _quantity_replace:_quantity_text="";_quantity_caret=0
			elif event.keycode==KEY_BACKSPACE and _quantity_caret>0:_quantity_text=_quantity_text.erase(_quantity_caret-1,1);_quantity_caret-=1
			elif event.keycode==KEY_DELETE:_quantity_text=_quantity_text.erase(_quantity_caret,1)
			_quantity_replace=false;_quantity_reparse();return true
		if event.keycode in [KEY_UP,KEY_DOWN]:_quantity_step(1 if event.keycode==KEY_UP else -1);return true
		if event.keycode in [KEY_LEFT,KEY_RIGHT,KEY_HOME,KEY_END]:
			_quantity_caret=0 if event.keycode==KEY_HOME else (_quantity_text.length() if event.keycode==KEY_END else clampi(_quantity_caret+(-1 if event.keycode==KEY_LEFT else 1),0,_quantity_text.length()));_quantity_replace=false;return true
	if dialog in ["choice","end_turn","quit","overwrite","leave_shop"]:
		if event.keycode == KEY_Y:
			var quitting := dialog == "quit"; close(6)
			if quitting: quit_requested.emit()
			return true
		if event.keycode == KEY_N: close(7); return true
		if event.keycode in [KEY_LEFT,KEY_RIGHT,KEY_TAB]: _choice_default = 13-_choice_default;_focus_control=_choice_default;_default_button=_choice_default; return true
	if dialog == "menu" and battle.get("phase") == "confirm":
		if event.keycode == KEY_C: command(40024); return true
		if event.keycode == KEY_A: command(40025); return true
	if dialog == "menu" and event.keycode > 0 and event.keycode < 128:
		for i in menu_rows.size():
			var label := str(menu_rows[i].get("text",""))
			var marker := label.find("(&")
			if marker >= 0 and marker+2 < label.length() and String.chr(event.keycode).to_lower() == label.substr(marker+2,1).to_lower():
				selection = i; activate(); return true
	var previous_selection:=selection
	var visible_page:=int(_detail_list_geometry().page) if _uses_detail_scrollbar() else 12
	var page_step:=maxi(1,visible_page-1) if _uses_detail_scrollbar() else 10
	match event.keycode:
		KEY_ESCAPE:
			if dialog == "menu" and not _menu_stack.is_empty(): _pop_menu(); return true
			if dialog == "menu" and battle.get("phase") == "confirm": battle.confirm_action(false)
			close(7); return true
		KEY_UP: selection = _row_count()-1 if dialog=="menu" and selection<0 else maxi(0,selection-1); scroll = mini(scroll,selection)
		KEY_DOWN:
			selection = mini(maxi(0,_row_count()-1),selection+1)
			if selection >= scroll+visible_page: scroll = selection-visible_page+1
		KEY_LEFT:
			if dialog == "menu" and not _menu_stack.is_empty(): _pop_menu()
			else: quantity = maxi(1,quantity-1)
		KEY_RIGHT:
			if dialog == "menu": activate()
			else: quantity = mini(9999,quantity+1)
		KEY_HOME:selection=0;scroll=0
		KEY_END:selection=maxi(0,_row_count()-1);scroll=maxi(0,selection-visible_page+1)
		KEY_PAGEUP: selection = maxi(0,selection-page_step); scroll = maxi(0,scroll-page_step)
		KEY_PAGEDOWN: selection = mini(maxi(0,_row_count()-1),selection+page_step); scroll = mini(selection,scroll+page_step)
		KEY_ENTER,KEY_KP_ENTER,KEY_SPACE:
			if dialog=="menu" or dialog in ["choice","quit","end_turn","overwrite","leave_shop"]:activate()
			else:_activate_dialog_button()
		_:
			if dialog == "message": close()
	if dialog=="bgm" and selection!=previous_selection and event.keycode in [KEY_UP,KEY_DOWN,KEY_PAGEUP,KEY_PAGEDOWN,KEY_HOME,KEY_END]:_preview_music()
	return true

func _row_count() -> int:
	return menu_rows.size() if dialog == "menu" else _list.size()

func _dialog_click(event: InputEventMouseButton) -> bool:
	if dialog == "battle_message" and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]: _dismiss_battle_modal(); return true
	if dialog == "scene_growth" and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]: close(); return true
	if event.button_index == MOUSE_BUTTON_RIGHT and dialog not in ["menu","message"]:return true
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if dialog=="stage_select":return true
		if dialog=="units" and unit_panel.scroll_at(Vector2i(event.position),-1):return true
		scroll = maxi(0,scroll-1); return true
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if dialog=="stage_select":return true
		if dialog=="units" and unit_panel.scroll_at(Vector2i(event.position),1):return true
		scroll = mini(maxi(0,_row_count()-1),scroll+1); return true
	if event.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]: return true
	var point := Vector2i(event.position)
	if dialog=="stage_select" and _control_rects.get(61536,Rect2i()).has_point(point):stage_select_message(0x10);return true
	if dialog=="bgm" and _control_rects.get(61536,Rect2i()).has_point(point):close(7);return true
	if dialog=="stage_select" or _uses_detail_scrollbar():
		var geometry:=_stage_scroll_geometry();var bar:Rect2i=geometry.rect;var thumb:Rect2i=geometry.thumb
		if bar.has_point(point):
			_configure_stage_scroll_input()
			_stage_thumb_offset=point.y-thumb.position.y
			_apply_stage_scroll_commands(_stage_scroll_controller.press(point,geometry,scroll))
			return true
	if event.button_index==MOUSE_BUTTON_LEFT and dialog not in ["menu","message","battle_message","scene_growth"] and Rect2i(_dialog_outer.position+Vector2i(3,3),Vector2i(_dialog_outer.size.x-6,18)).has_point(point):
		if dialog!="settings" or not source_fullscreen:_dragging=true;_drag_origin=_dialog_outer.position;_drag_pointer=point
		return true
	if dialog == "menu":
		selection = _menu_hit(point,menu_rows,menu_position)
		if selection >= 0: activate()
		else:
			var found := false
			for index in range(_menu_stack.size()-1,-1,-1):
				var previous: Dictionary = _menu_stack[index]
				var hit := _menu_hit(point,previous.rows,previous.pos)
				if hit >= 0:
					menu_rows = previous.rows; menu_position = previous.pos; selection = hit; _menu_stack.resize(index); found = true; activate(); break
			if not found: close(7)
		return true
	if dialog == "units":
		var tab_hit:=_unit_tab_at(point)
		if tab_hit>=0:
			_units_tab=tab_hit;_set_focus_control(1022);return true
		var hit: Dictionary = unit_panel.hit(point)
		if not hit.is_empty():
			if event.double_click or int(hit.control) == 1089: _unit_panel_action(hit)
			return true
	if _list_rect.has_point(point):
		if dialog=="stage_select" and not Rect2i(_list_rect.position+Vector2i(2,2),_list_rect.size-Vector2i(20,4)).has_point(point):return true
		var list_origin:Vector2i=_list_rect.position+Vector2i(0,2 if dialog=="stage_select"else 0)
		if _uses_detail_scrollbar():
			var content:Rect2i=_detail_list_geometry().content
			if not content.has_point(point):return true
			list_origin=content.position
		selection = mini(maxi(0,_list.size()-1),scroll+int((point.y-list_origin.y)/_list_height()))
		if dialog=="stage_select":
			_set_focus_control(1051);_default_button=1;stage_select.selection=selection;stage_select_message(0x111,1051|((2 if event.double_click else 1)<<16));return true
		if dialog=="bgm":_set_focus_control(1101);_preview_music()
		if event.double_click: activate()
		return true
	for id in _control_rects:
		if int(id)==65535:continue # STATIC/group frames do not intercept their child BUTTON hit tests.
		if _button_disabled(int(id)):continue
		if not _control_rects[id].has_point(point): continue
		if dialog=="bgm" and int(id)==61536:close(2);return true
		if dialog in ["buy_quantity","sell_quantity"] and int(id) in [1073,1086]:
			_focus_control=int(id)
			if point.x>=_control_rects[id].end.x-17:
				_spin_capture=1 if point.y<_control_rects[id].get_center().y else -1;_spin_pressed=_spin_capture;_quantity_step(_spin_capture)
			else:
				_quantity_replace=event.double_click;_quantity_caret=0
				var relative_x:int=point.x-int(_control_rects[id].position.x)-3
				var font:Dictionary=preload("res://scripts/ui/ft2_widgets.gd").dialog_font(resource_id)
				for index in _quantity_text.length():
					if relative_x>=(_raw_width(_quantity_text.substr(0,index),font)+_raw_width(_quantity_text.substr(0,index+1),font))/2:_quantity_caret=index+1
			return true
		if int(id)!=65535:_focus_control=int(id)
		match int(id):
			1,8001: activate()
			6:
				var quitting := dialog == "quit"; close(6)
				if quitting: quit_requested.emit()
			1109: _preview_experience("balance")
			1108: _preview_experience("equal")
			1078:_ask_leave_shop()
			2,7,1005,1064: close(7)
			8000: close(); new_game_requested.emit()
			1079: _push_parent(); _modal_vm=false; open_units(true)
			1004: _center_list_unit()
			_:
					if dialog == "settings": _toggle_setting(int(id))
		return true
	if dialog in ["message","experience"]: close()
	return true

func open_main_menu(pos: Vector2i) -> void:
	dialog = "menu"; menu_position = pos; selection = -1
	_menu_stack.clear()
	menu_rows = _menu.items[6 if vm.mode == 9 else 0].children.duplicate(true)

func open_action_menu(pos: Vector2i) -> void:
	if int(battle.substate) != 0: return
	if _hover_cell.x >= 0: battle.selected_slot = _hover_slot
	dialog = "menu"; menu_position = pos; selection = -1
	_menu_stack.clear()
	menu_rows = _menu.items[0].children.duplicate(true)
	var slot := int(battle.selected_slot)
	if slot >= 0 and slot < battle.units.size():
		var unit: Dictionary = data.decode_unit(battle.units[slot],slot)
		if int(unit.control) == 0 and int(unit.state) != 7:
			var flags: Dictionary = battle.menu_flags(slot)
			var dynamic: Array = []
			dynamic.append({"id":102,"text":"%s의 행동\t(HP:%d/%d)" % [_unit_name(slot),int(unit.hp),int(unit.hp_max)],"flags":0 if flags.get("action_move",false) else 1,"children":[]})
			var spells: Array = []
			var magic: Array = data.load_table("magic")
			for request in battle.available_magic(slot):
				var id := int(request.action_id)
				spells.append({"id":5000+id,"text":"%s(%s)\tMP:%d" % [str(magic[id].name),str(magic[id].get("effect_name","")),int(request.cost)],"flags":0 if request.enabled else 1,"children":[]})
			if not spells.is_empty(): dynamic.append({"id":null,"text":"%s의 마법/특기\t(MP:%d/%d)" % [_unit_name(slot),int(unit.mp),int(unit.mp_max)],"flags":0 if flags.get("magic_parent",false) else 1,"children":spells})
			var items: Array = []; var table: Array = data.load_table("item")
			for id in range(1,table.size()):
				var count: int = battle.rules.bag_count(battle.inventory,id)
				if count > 0 and int(table[id].get("effect_id",0)) != 0: items.append({"id":6000+id,"text":"%s\t%3d개" % [str(table[id].name),count],"flags":0,"children":[]})
			if not items.is_empty(): dynamic.append({"id":null,"text":"도구를 사용하다(&U)","flags":0 if flags.get("items_parent",false) else 1,"children":items})
			dynamic.append({"id":0,"text":"","flags":"0x800","children":[]})
			dynamic.append_array(menu_rows); menu_rows = dynamic
	menu_rows.append({"id":107,"text":"BGM 선택(&B)","flags":0,"children":[]})
	var metrics:=_menu_rects(menu_rows,menu_position)
	if not metrics.is_empty():
		var width:=_menu_width(menu_rows);var height:=metrics[-1].end.y-menu_position.y+3
		if menu_position.x+width>640:menu_position.x=maxi(0,menu_position.x-width)
		if menu_position.y+height>480:menu_position.y=maxi(0,480-height)

func command(id: int) -> void:
	if payload.get("gear_context",false) and (id in [40015,40016,40017,40018,40019] or id < 30):
		_gear_command(id); return
	if id in [40009,40010,40012,40028,40029,40030,40032,107] and (vm.mode not in [1,9] or (vm.mode == 1 and int(battle.substate) != 0)): return
	if id in [40028,40029] and forced_stage: return
	if id >= 5000 and id < 6000: close(); battle.choose_action(id-5000); return
	if id >= 6000 and id < 7000: close(); battle.choose_action(id-5000); return
	match id:
		40028: open_save(false)
		40029: open_save(true)
		40010: open_units()
		40012: open_settings()
		40004:
			if not exit_confirmation_requested.get_connections().is_empty():
				if dialog=="menu":close()
				exit_confirmation_requested.emit()
			else:_open("quit",126,"종료해도 좋습니까?") # Source449C70, WM_CLOSE40DDDB.
		40003: close(); fullscreen_requested.emit() # TrackPopupMenu ends before the source main command.
		40009: _modal_vm = false; _open("end_turn",126,"*턴을 종료해도 좋습니까?")
		40024: close(); battle.confirm_action(true)
		40025: close(7); battle.confirm_action(false)
		40032:
			_modal_vm=false;payload={}
			_open("message",0,vm.objective)
			_begin_message_presentation()
		40030: close(); overview_requested.emit()
		40035: vm.town.toggle_markers(); close()
		102:
			var slot := int(battle.selected_slot); close(); battle.select_unit(slot)
		107: open_bgm()
		-100:
			var slot := int(battle.selected_slot); close(); battle.select_unit(slot)
		-101: open_magic()
		-102: open_inventory()
		-103: open_equipment(battle.selected_slot)
		-104:
			_open("facing",0,"방향"); _list = [{"text":"남","id":0},{"text":"동","id":1},{"text":"서","id":2},{"text":"북","id":3}]
		-105: open_status(battle.selected_slot)

func open_save(saving: bool) -> void:
	_open("save" if saving else "load",143)
	_list.clear()
	var best:=-1;var first_empty:=false
	for i in (30 if saving else 32):
		var header:=_slot_header(i)
		var occupied:bool=not header.is_empty()
		var stamp:int=_timestamp(header.get("system_time_words",[]))
		var label:=FT2Content.ui_text("empty_save_slot","%2d: 빈 슬롯") % (i+1);var date:=""
		if occupied:
			var title:String=data.decode_cp949(str(header.title_cp949_raw_hex).hex_decode())
			label=FT2Content.ui_text("town_save_slot","%2d: %2d일 / 마을 / %s") % [i+1,int(header.stage),title] if int(header.round_index)<0 else FT2Content.ui_text("battle_save_slot","%2d: %2d일 / 턴 %-3d / %s") % [i+1,int(header.stage),mini(999,int(header.round_index)+1),title]
			var t:Array=header.system_time_words;date="%2d/%2d %2d:%02d" % [int(t[1]),int(t[3]),int(t[4]),int(t[5])]
		_list.append({"id":i,"text":label,"date":date,"header":header,"occupied":occupied,"stamp":stamp})
		if saving:
			if not occupied and not first_empty:selection=i;best=0;first_empty=true
			elif occupied and not first_empty and (best<0 or stamp<=best):selection=i;best=stamp
		elif occupied and stamp>best:selection=i;best=stamp
	scroll=maxi(0,selection-int(_list_rect.size.y/_list_height())+1)

func startup_load() -> void:
	# Original40D300 startup TITLE.BMP and408B30→41E6C0(-1), before EVENT00 begin.
	_modal_vm = false
	open_save(false)
	_startup = true

func open_stage_select()->void:
	#40D2C5 precedes graphics40D580/TITLE: do not set _startup or paint TITLE here.
	_modal_vm=false;_startup=false;_open("stage_select",124)
	if not stage_select.finished.is_connected(_stage_select_finished):stage_select.finished.connect(_stage_select_finished)
	stage_select.message(0x110);_focus_control=1051;_stage_scroll_capture="";_stage_search_prefix=""
	_control_rects[61536]=Rect2i(_dialog_outer.position+Vector2i(_dialog_outer.size.x-21,5),Vector2i(16,14))
	for text in stage_select.ROWS:_list.append({"text":text})

func stage_select_message(message_id:int,wparam:int=0)->int:
	if dialog!="stage_select":return 0
	return stage_select.message(message_id,wparam)

func _stage_select_finished(result:int)->void:
	_listbox_input.destroy_control();_stage_search_prefix=""
	cancel_control_capture();_dragging=false
	dialog="";resource_id=0;_list.clear();_template.clear();_control_rects.clear();_row_rects.clear()
	stage_selection_finished.emit(result)

func _stage_select_key(event:InputEventKey)->bool:
	if event.keycode==KEY_F4 and event.alt_pressed:stage_select_message(0x10);return true
	if event.keycode==KEY_ESCAPE:stage_select_message(0x111,2);return true
	if event.alt_pressed and event.keycode in [KEY_S,KEY_L]:stage_select_message(0x111,1 if event.keycode==KEY_S else 2);return true
	if event.keycode==KEY_TAB:
		var order:Array[int]=[1051,1,2];_set_focus_control(order[posmod(order.find(_focus_control)+(-1 if event.shift_pressed else 1),3)]);_default_button=_focus_control if _focus_control in [1,2]else 1;return true
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:stage_select_message(0x111,2 if _focus_control==2 else 1);return true
	if _focus_control!=1051:return true
	if _listbox_key(event):return true
	var previous:=selection;var page:=maxi(1,int((_list_rect.size.y-4)/_list_height()))
	match event.keycode:
		KEY_UP:selection=maxi(0,selection-1)
		KEY_DOWN:selection=mini(_list.size()-1,selection+1)
		KEY_HOME:selection=0
		KEY_END:selection=_list.size()-1
		KEY_PAGEUP:selection=maxi(0,selection-page+1)
		KEY_PAGEDOWN:selection=mini(_list.size()-1,selection+page-1)
	if selection!=previous:
		stage_select.selection=selection;stage_select_message(0x111,1051|(1<<16))
		scroll=clampi(scroll,maxi(0,selection-page+1),selection)
	return true

func _input_clock_now()->int:
	return int(input_clock_provider.call()) if input_clock_provider.is_valid() else Time.get_ticks_msec()

func service_input_timers()->void:
	if dialog not in ["stage_select","bgm"] and not _uses_detail_scrollbar():return
	_listbox_input.set_double_click_time(source_double_click_ms)
	if _listbox_input.dispatch_due(_input_clock_now()):_stage_search_prefix=""
	if (dialog=="stage_select" or _uses_detail_scrollbar()) and _stage_scroll_controller.capture!="":
		_configure_stage_scroll_input()
		_apply_stage_scroll_commands(_stage_scroll_controller.advance(_stage_scroll_geometry()))

func _configure_stage_scroll_input()->void:
	# Forward the external clock itself; binding this RefCounted UI back into its
	# owned controller would create a strong-reference cycle.
	_stage_scroll_controller.configure(input_clock_provider,source_double_click_ms)

func _apply_stage_scroll_commands(commands:Array[Dictionary])->void:
	if dialog=="stage_select" or _uses_detail_scrollbar():
		var geometry:=_stage_scroll_geometry()
		# USER12:23BD..242A: fixed-height LISTBOX SB_PAGE uses visible rows minus1.
		var page_step:=maxi(1,int(geometry.page)-1)
		for command in commands:
			match int(command.code):
				0:scroll-=1
				1:scroll+=1
				2:scroll-=page_step
				3:scroll+=page_step
				4,5:scroll=int(command.position)
			scroll=clampi(scroll,0,int(geometry.max_top))
	_stage_scroll_capture=_stage_scroll_controller.capture

func stage_scroll_state()->Dictionary:return _stage_scroll_controller.snapshot()

func listbox_search_state()->Dictionary:return _listbox_input.snapshot()

func _set_focus_control(control:int)->void:
	if _focus_control in [1051,1101] and control!=_focus_control:
		_listbox_input.focus_lost();_stage_search_prefix=""
	_focus_control=control
	if dialog in ["choice","end_turn","quit","overwrite","leave_shop"] and control in [6,7]:_choice_default=control;_default_button=control

func handle_listbox_wm_char(text:String,control_down:bool=false)->bool:
	if not((dialog=="stage_select" and _focus_control==1051)or(dialog=="bgm" and _focus_control==1101)):return false
	_listbox_input.set_double_click_time(source_double_click_ms)
	var result:Dictionary=_listbox_input.wm_char(data.encode_cp949(text),_list,selection,_input_clock_now(),control_down)
	selection=int(result.selection);_stage_search_prefix=str(_listbox_input.snapshot().prefix)
	if result.notify:
		var page:=maxi(1,int((_list_rect.size.y-(4 if dialog=="stage_select"else 0))/_list_height()))
		scroll=clampi(scroll,maxi(0,selection-page+1),selection)
		if dialog=="stage_select":stage_select.selection=selection;stage_select_message(0x111,1051|(1<<16))
		else:_preview_music() # Source160 consumes LBN_SELCHANGE1, including unchanged successful matches.
	return true

func _listbox_key(event:InputEventKey)->bool:
	if event.alt_pressed or event.keycode in [KEY_TAB,KEY_ENTER,KEY_KP_ENTER,KEY_ESCAPE]:return false
	if event.keycode==KEY_BACKSPACE:return handle_listbox_wm_char(String.chr(8),event.ctrl_pressed)
	if event.unicode>0:return handle_listbox_wm_char(String.chr(event.unicode),event.ctrl_pressed)
	# Existing explicit key-only fixtures stand in for unmodified WM_CHAR; actual
	# events always prefer unicode (Shift+7 therefore searches '&', never '7').
	if not event.shift_pressed and not event.ctrl_pressed:
		if event.keycode>=KEY_0 and event.keycode<=KEY_9:return handle_listbox_wm_char(String.chr(event.keycode))
		if event.keycode>=KEY_KP_0 and event.keycode<=KEY_KP_9:return handle_listbox_wm_char(str(event.keycode-KEY_KP_0))
		if event.keycode==KEY_SPACE:return handle_listbox_wm_char(" ")
	return false

func open_units(force_modal: bool=false) -> void:
	if not source_fullscreen and not force_modal and not _is_unit_window_panel:
		toggle_unit_window();return
	_open("units",107)
	_units_forced_modal=force_modal if _is_unit_window_panel else (force_modal or vm.mode!=1)
	_units_tab = 0
	unit_panel.invalidate_magic()
	_list.clear()
	for i in mini(10,battle.units.size()):
		var unit: Dictionary = data.decode_unit(battle.units[i],i)
		if int(unit.kind) != 0 and int(unit.control) == 0 and int(unit.state) != 9:
			_list.append({"id":i,"text":"%s  LV%d  HP %d/%d  MP %d/%d" % [_unit_name(i),unit.level,unit.hp,unit.hp_max,unit.mp,unit.mp_max]})
	while _list.size()<5: _list.append({"id":-1,"text":""})
	_unit_slot = int(_list[0].id) if not _list.is_empty() else 0
	var saved:Array=settings.get("unit_window_rect",[])
	if saved.size()==4:_move_dialog(Vector2i(int(saved[0]),int(saved[1])))

func refresh_107()->bool:
	# Native dialog107 WM_USER400 updates existing child/owner-draw data, without INITDIALOG/tab recreation.
	if not _is_unit_window_panel and _unit_window!=null and _unit_window.exists:return _unit_window.refresh()
	if dialog!="units":return false
	if _units_tab in [0,1,3]:unit_panel.refresh_child([117,119,121,118][_units_tab])
	for row in _list:
		var slot:=int(row.get("id",-1))
		if slot<0 or slot>=battle.units.size():continue
		var unit:Dictionary=data.decode_unit(battle.units[slot],slot)
		row["text"]="%s  LV%d  HP %d/%d  MP %d/%d" % [_unit_name(slot),unit.level,unit.hp,unit.hp_max,unit.mp,unit.mp_max]
	return true

func service_unit_window_visibility(show:bool)->int:
	return _unit_window.service(show) if _unit_window!=null else 0

func toggle_unit_window()->bool:
	return _unit_window.toggle() if _unit_window!=null else false

func destroy_unit_window(persist_preference:bool=true)->bool:
	return _unit_window.destroy(persist_preference) if _unit_window!=null else false

func refresh_unit_window()->bool:
	return _unit_window.refresh() if _unit_window!=null else false

func cancel_unit_window_capture()->void:
	if _unit_window!=null:_unit_window.cancel_capture()

func set_unit_window_rect(rect:Rect2i)->void:
	if _unit_window!=null:_unit_window.set_rect(rect)

func unit_window_profile()->Dictionary:
	return _unit_window.profile() if _unit_window!=null else {}

func unit_window_blocks_primary_input()->bool:
	return _unit_window!=null and _unit_window.blocks_frame()

func handle_unit_window_input(event:InputEvent,screen_point:Vector2i=Vector2i(-2147483648,-2147483648))->bool:
	if _unit_window==null:return false
	if screen_point.x==-2147483648 and event is InputEventMouse:screen_point=_unit_window.outer_rect.position+Vector2i(event.position)
	return _unit_window.input(event,screen_point)
func _unit_name(slot: int) -> String:
	var unit: Dictionary = data.decode_unit(battle.units[slot],slot)
	if unit.has("extension_name"):return str(unit.extension_name)
	if int(unit.kind) != 8 and int(unit.kind) < 30: return str(vm._speaker_names.get(int(unit.kind),""))
	var race: Array = data.load_table("race")
	return str(race[int(unit.definition_id)].get("name","")) if int(unit.definition_id) < race.size() else ""

func open_status(slot: int) -> void:
	if slot < 0: return
	_unit_slot = slot
	var kind:int=battle.units[slot].decode_u16(0)
	var has_face:bool=kind<30 and kind not in [8,24] and unit_panel._faces.has("BMP/FACE%02dA.BMP" % kind)
	_open("status",145 if has_face else 144,"%s의 등록정보" % _unit_name(slot));_list.clear()

func open_magic() -> void:
	if battle.selected_slot < 0: return
	_open("magic",121,"마법")
	_list.clear()
	var table: Array = data.load_table("magic")
	for value in battle.available_magic(battle.selected_slot):
		var id := int(value.get("action_id",value.get("id",value.get("magic_id",0)))) if value is Dictionary else int(value)
		if id >= 0 and id < table.size(): _list.append({"id":id,"text":str(table[id].get("name","")),"source":value})

func open_inventory() -> void:
	_open("inventory",118,"물품")
	_list.clear()
	var table: Array = data.load_table("item")
	for i in 80:
		if battle.inventory.size() < i*4+4: break
		var id: int = battle.inventory.decode_u16(i*4); var count: int = battle.inventory.decode_u16(i*4+2)
		if id > 0 and id < table.size(): _list.append({"id":id,"bag_index":i,"count":count,"text":"%s × %d" % [str(table[id].name),count]})

func open_equipment(slot: int) -> void:
	if slot < 0: return
	_unit_slot = slot; _open("equipment",119,_unit_name(slot))
	_list.clear()
	var table: Array = data.load_table("item")
	var unit: PackedByteArray = battle.units[slot]
	for i in 8:
		var id := unit.decode_u16(20+i*2)
		if id > 0 and id < table.size(): _list.append({"id":id,"held_index":i,"text":str(table[id].name),"equipped":i < 4})

func open_shop() -> void:
	_open("shop",150)
	_list.clear()
	var table: Array = data.load_table("item")
	for value in _shop_items:
		var id := int(value)
		if id > 0 and id < table.size(): _list.append({"id":id,"text":"%s  %d" % [str(table[id].name),int(table[id].price)]})
	while _list.size()<10:_list.append({"id":0,"text":""})

func open_settings() -> void:
	_settings_before=settings.duplicate(true)
	_open("settings",109)
	_list.clear()

func open_bgm() -> void:
	_open("bgm",160)
	_list.clear()
	var captions: Array = data.read_json("data/port_ready/analysis_completion/ui/shared_helpers.json").contracts.source_arrays.music_labels
	for i in captions.size(): _list.append({"id":i,"text":str(captions[i])})
	payload={"old_music":int(music_index_provider.call()) if music_index_provider.is_valid() else -1}
	selection=int(payload.old_music);_bgm_preview_index=selection;scroll=maxi(0,selection-int(_list_rect.size.y/_list_height())+1)

func _toggle_setting(id: int) -> void:
	if id == 0: settings.music = not settings.music
	elif id == 1: settings.effects = not settings.effects
	elif id == 2: settings.battle_animation = not settings.battle_animation
	elif id == 1009: settings["swap_mouse"] = not settings.get("swap_mouse",false)
	elif id == 1010 and source_fullscreen: settings["skip_zoom"] = not settings.get("skip_zoom",false)
	elif id == 1011: settings["skip_palette"] = not settings.get("skip_palette",false)
	elif id == 1012: settings["skip_effect"] = not settings.get("skip_effect",false)
	elif id == 1015: settings["show_occluded"] = not settings.get("show_occluded",false)
	elif id == 1014: settings["skip_ally"] = not settings.get("skip_ally",false)
	elif id == 1013: settings["skip_enemy"] = not settings.get("skip_enemy",false)
	elif id == 1091: settings["music_backend"] = 2
	elif id == 1090: settings["music_backend"] = 0
	# Original109 stages the seven fields; Cancel preserves the incoming settings.

func activate() -> void:
	if dialog == "menu":
		if selection < 0 or selection >= menu_rows.size(): return
		var row: Dictionary = menu_rows[selection]
		var flags := int(row.get("flags",0)) if row.get("flags",0) is int or row.get("flags",0) is float else str(row.get("flags","0")).hex_to_int()
		if flags & 3: return
		if not row.get("children",[]).is_empty():
			var rects := _menu_rects(menu_rows,menu_position)
			var child_pos := Vector2i(menu_position.x+_menu_width(menu_rows)-3,rects[selection].position.y-3)
			_menu_stack.append({"rows":menu_rows,"pos":menu_position,"selection":selection})
			menu_rows = row.children; selection = 0
			if child_pos.x+_menu_width(menu_rows)>640: child_pos.x = maxi(0,menu_position.x-_menu_width(menu_rows)+3)
			menu_position = child_pos
		elif row.get("town",false): close(); vm.town.select_place(int(row.id))
		elif row.get("id") != null: command(int(row.id))
		return
	match dialog:
		"stage_select":stage_select_message(0x111,1)
		"message": close(6)
		"choice": close(_choice_default)
		"experience":
			experience.message(0x111,1)
		"quit":
			if _choice_default == 6: close(); quit_requested.emit()
			else: close(7)
		"end_turn": close(_choice_default)
		"overwrite","leave_shop": close(_choice_default)
		"battle_message": _dismiss_battle_modal()
		"save","load":
			if _list.is_empty(): return
			var index := int(_list[selection].id); var saving := dialog == "save"
			if not saving and not _list[selection].occupied:return
			if saving and _list[selection].occupied:
				_overwrite_pending=index;_push_parent();_modal_vm=false;_open("overwrite",126,"이미 데이터가 있습니다.\r\r덮어 써도 좋습니까?");return
			close()
			if saving: save_requested.emit(index)
			else: load_requested.emit(index)
		"units":
			_center_list_unit()
		"magic":
			if not _list.is_empty():
				var id := int(_list[selection].id); close(); battle.choose_action(id)
		"inventory":
			if not _list.is_empty():
				var id := int(_list[selection].id); close(); battle.choose_action(1000+id)
		"equipment":
			if not _list.is_empty() and int(_list[selection].held_index) >= 4:
				battle.equip_carried(_unit_slot,int(_list[selection].held_index)-4); open_equipment(_unit_slot)
		"shop": _begin_buy()
		"buy_quantity": _buy_quantity()
		"buy_receiver": _buy_receiver()
		"sell_quantity":
			if battle.sell_item(int(payload.item),quantity): close(6)
		"settings":
			settings_changed.emit(settings.duplicate(true))
			_persist_settings()
			close()
		"bgm":
			close()
		"facing":
			var direction := int(_list[selection].id); close(); battle.commit_facing(direction)

func _begin_buy() -> void:
	if _list.is_empty() or int(_list[selection].id)<=0: return
	var id := int(_list[selection].id)
	var row: Dictionary = data.load_table("item")[id]
	if int(row.price) > int(battle.money): return
	_push_parent(); _modal_vm=false
	payload = {"item":id,"price":int(row.price)}
	if int(row.category) == 3:
		_open("buy_quantity",151); return
	_open("buy_receiver",152)
	_list.clear()
	for i in battle.units.size():
		var bytes: PackedByteArray = battle.units[i]
		if bytes.decode_u16(0) == 0: break
		var free := false
		for offset in [28,30,32,34]:
			if bytes.decode_u16(offset) == 0: free = true
		_list.append({"id":i,"text":_unit_name(i),"enabled":free and bytes.decode_u16(16) != 9})
	while _list.size()<10: _list.append({"id":-1,"text":"","enabled":false})

func _buy_quantity() -> void:
	var count := 0
	for i in 80:
		if battle.inventory.decode_u16(i*4) == int(payload.item): count = battle.inventory.decode_u16(i*4+2); break
	if quantity < 1 or quantity > 9999-count or int(payload.price)*quantity > int(battle.money): return
	battle.grant_item(-1,int(payload.item),quantity); battle.add_money(-int(payload.price)*quantity)
	close()

func _preview_experience(distribution: String) -> void:
	_exp_mode = distribution
	var experience: Array = []
	for bytes in battle.units:
		if bytes.decode_u16(0) == 0: break
		experience.append(bytes.decode_s16(44))
	_exp_allocations = battle.rules.equal_distribution(experience,int(payload.get("pool",0))) if distribution == "equal" else battle.rules.balanced_distribution(experience,int(payload.get("pool",0)))
	_list.clear()
	for i in _exp_allocations.size(): _list.append({"id":i,"text":"%s  %d(+%d)" % [_unit_name(i),int(experience[i]),int(_exp_allocations[i])]})

func _buy_receiver() -> void:
	if _list.is_empty() or not _list[selection].enabled: return
	battle.grant_item(int(_list[selection].id),int(payload.item),1); battle.add_money(-int(payload.price)); close()

func startup_title_commands() -> Array[Dictionary]:
	# Source40D30A..40D3A6. Pure data: caller owns when MAIN is presented.
	return [{"op":"bitmap","key":"BMP/TITLE.BMP","pos":Vector2i.ZERO,"source":Rect2i(0,0,640,480),"remaps":[[122,32,208],[10,112,32]],"palette_install":[[208,32],[32,112]],"transparent":-1}]

func commands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _parents.is_empty(): out.append_array(_parents[-1].draw)
	if dialog == "experience": return experience.commands()
	if _startup: out.append_array(startup_title_commands())
	if dialog == "battle_message" and payload.get("source_format_null",false): return out
	if dialog in ["battle_message","message","scene_growth"]:
		if _message_presentation.is_empty() or message_presentation_requested.get_connections().is_empty():out.append_array(_message_commands())
		return out
	if dialog == "":
		if vm.mode == 1: return _hover_commands()
		return out
	if dialog == "menu":
		for previous in _menu_stack: _draw_menu(out,previous.rows,previous.pos,int(previous.selection))
		_draw_menu(out,menu_rows,menu_position,selection)
		return out
	var rect := Rect2i(112,80,416,320)
	if not _template.is_empty():
		rect=_dialog_outer
	_panel(out,rect)
	out.append({"op":"rect","rect":Rect2i(rect.position+Vector2i(3,3),Vector2i(rect.size.x-6,18)),"color":4,"filled":true})
	_text(out,_title,rect.position+Vector2i(5,6),255,UI_FONT)
	if dialog in ["stage_select","bgm"]:preload("res://scripts/ui/ft2_stage_widgets.gd").mask(out,_control_rects[61536].position,preload("res://scripts/ui/ft2_stage_widgets.gd").CLOSE)
	if dialog=="status":
		unit_panel.measure=vm.measure_text; unit_panel.preview_unit=preview_unit
		_unit_panel_button_state()
		out.append_array(unit_panel.commands(resource_id,_unit_slot,_dialog_origin));return out
	var control_index := 0
	for row in _template.get("controls",[]):
		var r: Rect2i = _row_rects[control_index]; control_index += 1
		var caption := str(row.get("title",{}).get("value",""))
		if int(row.id) == 1058 and _body_text != "": caption = _body_text
		if dialog in ["buy_quantity","sell_quantity"]:
			var total:=_quantity_total
			if int(row.id)==1076:caption=str(battle.money)
			elif int(row.id)==1077:caption=str(total) if total<=999999 else "많이"
			elif int(row.id)==1087:caption=str(_quantity_after)
			elif int(row.id)==1088:caption=str(total)
			elif int(row.id)==1098 and payload.has("item"):caption=FT2Content.ui_text("item_count","%s: %d개 보유") % [str(data.load_table("item")[int(payload.item)].name),battle.rules.bag_count(battle.inventory,int(payload.item))]
		if dialog=="shop" and int(row.id)==1080:caption=str(battle.money)
		if dialog in ["save","load"] and int(row.id)==1062:caption="세이브할 장소를 지정해 주십시오" if dialog=="save" else "로드할 데이터를 지정해 주십시오"
		if row.class_name == "BUTTON":
			if dialog=="save" and int(row.id)==8000:continue
			var disabled:bool=_button_disabled(int(row.id))
			var style:=str(row.style).hex_to_int()&15
			if style==11 and int(row.id)==1059 and resource_id in [126,163]:
				#430080 draws the full64x72 WHAT image, even though control1059
				#has a56px client width. The original owner-draw has no button edge.
				out.append({"op":"palette_current_entry","index":15,"rgb":[192,192,192]})
				out.append({"op":"rect","rect":Rect2i(r.position,Vector2i(64,72)),"color":15,"filled":true})
				out.append({"op":"bitmap","key":"BMP/WHAT.BMP","pos":r.position,"source":Rect2i(0,0,64,72),"remaps":[[10,64,144]],"palette_install":[[144,64]],"transparent":7})
			elif style in [3,9]:
				var checked:=bool(settings.get(SETTING_CONTROLS.get(int(row.id),""),false)) if style==3 else int(settings.get("music_backend",2))==(0 if int(row.id)==1090 else 2)
				if int(row.id)==1010 and not source_fullscreen:checked=true
				_draw_check(out,r,caption,style==9,checked,disabled,int(row.id)==_focus_control,int(row.id)==_pressed_control)
			elif style==7:
				var edge:=Rect2i(r.position+Vector2i(0,7 if dialog=="stage_select"else 6),r.size-Vector2i(1,8 if dialog=="stage_select"else 7))
				out.append({"op":"rect","rect":Rect2i(edge.position+Vector2i.ONE,edge.size),"filled":false,"color":255})
				out.append({"op":"rect","rect":edge,"filled":false,"color":248})
				for corner in [Vector2i(edge.end.x,edge.position.y),Vector2i(edge.position.x,edge.end.y)]:out.append({"op":"rect","rect":Rect2i(corner,Vector2i.ONE),"filled":true,"color":255})
				var label_width:=_raw_width(caption,preload("res://scripts/ui/ft2_widgets.gd").dialog_font(resource_id));out.append({"op":"rect","rect":Rect2i(r.position+Vector2i(7,0),Vector2i(label_width+4,12)),"filled":true,"color":7});_text(out,caption,r.position+Vector2i(9,0),0)
			else:
				var is_default:bool=int(row.id)==_default_button if dialog in ["stage_select","choice","end_turn","quit","overwrite","leave_shop"] else style==1
				_draw_button(out,r,caption,is_default,disabled,int(row.id)==_focus_control,int(row.id)==_pressed_control)
		elif row.class_name == "STATIC" and caption != "" and not (dialog=="shop" and int(row.id)==1077):
			_draw_static(out,caption,r,str(row.style).hex_to_int())
		elif row.class_name=="EDIT" and dialog in ["buy_quantity","sell_quantity"]:
			var edit:=Rect2i(r.position,r.size-Vector2i(15,0))
			preload("res://scripts/ui/ft2_native_widgets.gd").edit(out,edit)
			var text_point:=r.position+Vector2i(3,3)
			var selected:bool=_focus_control==int(row.id) and _quantity_replace
			if selected:out.append({"op":"rect","rect":Rect2i(text_point,Vector2i(_raw_width(_quantity_text,preload("res://scripts/ui/ft2_widgets.gd").dialog_font(resource_id)),15)),"filled":true,"color":4,"clip":edit})
			_text(out,_quantity_text,text_point,255 if selected else 0);out[-1]["clip"]=Rect2i(edit.position+Vector2i(2,2),edit.size-Vector2i(4,4))
			preload("res://scripts/ui/ft2_native_widgets.gd").spin(out,Vector2i(r.end.x-17,r.position.y),_spin_pressed)
			if _focus_control==int(row.id) and not _quantity_replace and ((_elapsed-_caret_epoch)%1000)<500:
				var caret:=r.position+Vector2i(3+_raw_width(_quantity_text.substr(0,_quantity_caret),preload("res://scripts/ui/ft2_widgets.gd").dialog_font(resource_id)),3)
				out.append({"op":"caret_rect","rect":Rect2i(caret,Vector2i(2,15))})
	if dialog=="shop":_shop_detail_commands(out);return out
	if dialog=="buy_receiver":_receiver_detail_commands(out);return out
	if dialog=="bgm":_bgm_detail_commands(out);return out
	if _list_rect.size == Vector2i.ZERO and not _list.is_empty(): _list_rect = Rect2i(rect.position+Vector2i(12,36),Vector2i(rect.size.x-24,rect.size.y-64))
	if dialog=="stage_select":
		_draw_stage_list(out);return out
	var height:=_list_height()
	var list_content:=_list_rect
	if dialog in ["load","save","units"]:
		var geometry:=preload("res://scripts/ui/ft2_native_widgets.gd").listbox_frame(out,_list_rect,height,_list.size(),scroll)
		list_content=geometry.content
	var list_rows := maxi(1,int((list_content.size.y+height-1)/height))
	var list_font:Dictionary=preload("res://scripts/ui/ft2_widgets.gd").dialog_font(resource_id) if dialog in ["load","save"] else CUSTOM_FONT
	var list_font_height:=absi(int(list_font.get("height",height)))
	for i in mini(list_rows,maxi(0,_list.size()-scroll)):
		var index := scroll+i
		var pos := list_content.position+Vector2i(0,i*height)
		var row_begin:=out.size()
		if dialog in ["load","save"]:
			var selected:=index==selection
			var text_y:=pos.y+int((height-mini(height,list_font_height))/2)
			if selected:out.append({"op":"rect","rect":Rect2i(pos,Vector2i(list_content.size.x,height)),"color":4,"filled":true,"clip":list_content})
			var text_color:int=255 if selected else 0
			var label:=str(_list[index].text)
			var label_clip:=Rect2i(pos+Vector2i(2,0),Vector2i(maxi(0,mini(350,list_content.size.x-2)),height))
			var date_clip:=Rect2i(pos+Vector2i(352,0),Vector2i(maxi(0,list_content.end.x-(pos.x+352)),height))
			var date_text:=str(_list[index].date)
			var date_width:=_raw_width(date_text,list_font) if not date_text.is_empty() else 0
			var date_x:=maxi(date_clip.position.x,date_clip.end.x-8-date_width)
			out.append({"op":"text","raw_text":label,"text":label.replace("_"," ").replace("*",","),"pos":Vector2i(pos.x+2,text_y),"font":list_font,"color":text_color,"decor":{"raw_gdi":true},"clip":label_clip})
			if not date_text.is_empty():out.append({"op":"text","text":date_text,"pos":Vector2i(date_x,text_y),"font":list_font,"color":text_color,"decor":{"raw_gdi":true},"clip":date_clip})
		elif dialog=="units":
			_draw_unit_row(out,int(_list[index].id),pos,index==selection)
		else:
			if index==selection:out.append({"op":"rect","rect":Rect2i(pos,Vector2i(_list_rect.size.x,height)),"color":4,"filled":true})
			_text(out,str(_list[index].get("text","")),pos+Vector2i(2,2),255 if index==selection else 0)
		for command_index in range(row_begin,out.size()):
			if not out[command_index].has("clip"):out[command_index]["clip"]=list_content
	if dialog == "units":
		_control_rects.erase(1089)
		if selection >= 0 and selection < _list.size() and int(_list[selection].id)>=0: _unit_slot=int(_list[selection].id)
		var tab: Rect2i = _control_rects.get(1022,Rect2i())
		if tab.size.x>0:
			_draw_unit_tabs(out)
			if _unit_slot>=0:
				unit_panel.measure=vm.measure_text; unit_panel.preview_unit=preview_unit
				_unit_panel_button_state()
				out.append_array(unit_panel.commands([117,119,121,118][_units_tab],_unit_slot,tab.position+_child_offset([117,119,121,118][_units_tab])))
				if unit_panel.controls.has(1089):_control_rects[1089]=unit_panel.controls[1089]
	return out

func _draw_static(out:Array[Dictionary],raw:String,r:Rect2i,style:int)->void:
	if r.size.x<=0 or r.size.y<=0:return
	var font:Dictionary=preload("res://scripts/ui/ft2_widgets.gd").dialog_font(resource_id)
	var alignment:=style&31
	var no_prefix:bool=(style&0x80)!=0
	var y:=r.position.y
	for paragraph in raw.replace("\r\n","\n").replace("\r","\n").split("\n"):
		var display:="";var underline:=-1;var i:=0
		while i<paragraph.length():
			if not no_prefix and paragraph.substr(i,1)=="&" and i+1<paragraph.length():
				if paragraph.substr(i+1,1)=="&":display+="&";i+=2;continue
				underline=display.length();i+=1
			display+=paragraph.substr(i,1);i+=1
		var lines:Array[String]=[display];var line_start:=0
		if alignment!=12:lines=preload("res://scripts/ui/ft2_widgets.gd").wrap_lines(display,r.size.x,func(value):return _raw_width(value,font))
		for text in lines:
			var width:=_raw_width(text,font)
			var x:=r.position.x+(r.size.x-width if alignment==2 else ((r.size.x-width)/2 if alignment==1 else 0))
			if not text.is_empty():_text(out,text,Vector2i(x,y),0,font);out[-1]["clip"]=r
			if underline>=line_start and underline<line_start+text.length():
				var index:=underline-line_start;var before:=_raw_width(text.substr(0,index),font)
				var letter:=_raw_width(text.substr(index,1),font)
				out.append({"op":"line","from":Vector2i(x+before,y-int(font.height)-2),"to":Vector2i(x+before+letter-1,y-int(font.height)-2),"color":0,"clip":r})
			line_start+=text.length();y+=-int(font.height)

func _caption(value: String) -> String:
	return value.replace("&","").replace("\t","  ")

func _button_at(point:Vector2i)->int:
	if dialog=="units" and _units_tab==1 and _control_rects.get(1089,Rect2i()).has_point(point):return 1089
	if dialog in ["stage_select","bgm"] and _control_rects.get(61536,Rect2i()).has_point(point):return 61536
	for row in _template.get("controls",[]):
		var id:=int(row.id)
		if dialog=="save" and id==8000:continue
		if row.class_name=="BUTTON" and (str(row.style).hex_to_int()&15) in [0,1,3,9] and _control_rects.has(id) and _control_rects[id].has_point(point):return id
	return -1

func _draw_stage_list(out:Array[Dictionary])->void:
	preload("res://scripts/ui/ft2_native_widgets.gd").edit(out,_list_rect)
	var inner:=Rect2i(_list_rect.position+Vector2i(2,2),_list_rect.size-Vector2i(4,4))
	var content:=Rect2i(inner.position,inner.size-Vector2i(16,0));var page:=int(inner.size.y/15)
	for i in mini(page,_list.size()-scroll):
		var index:=scroll+i;var row:=Rect2i(content.position+Vector2i(0,i*15),Vector2i(content.size.x,15))
		if index==selection:out.append({"op":"rect","rect":row,"filled":true,"color":4})
		_text(out,str(_list[index].text),row.position+Vector2i(2,0),255 if index==selection else 0);out[-1]["clip"]=content
		if index==selection and _focus_control==1051:
			for y in row.size.y:
				for x in row.size.x:
					if (x==0 or y==0 or x==row.size.x-1 or y==row.size.y-1) and ((x+y+row.position.x+row.position.y-_dialog_outer.position.x-_dialog_outer.position.y)&1)==1:out.append({"op":"rect","rect":Rect2i(row.position+Vector2i(x,y),Vector2i.ONE),"filled":true,"color":251})
	_stage_scrollbar=preload("res://scripts/ui/ft2_stage_widgets.gd").scrollbar(out,Rect2i(inner.end-Vector2i(16,inner.size.y),Vector2i(16,inner.size.y)),scroll,page,_list.size())

func _stage_scroll_geometry()->Dictionary:
	if _uses_detail_scrollbar():
		var geometry:=_detail_list_geometry()
		if geometry.scrollbar.size.y<=0:return {"rect":Rect2i(),"thumb":Rect2i(),"page":geometry.page,"max_top":geometry.max_top,"top":geometry.top}
		return preload("res://scripts/ui/ft2_stage_widgets.gd").scroll_geometry(geometry.scrollbar,scroll,int(geometry.page),_list.size())
	var inner:=Rect2i(_list_rect.position+Vector2i(2,2),_list_rect.size-Vector2i(4,4))
	return preload("res://scripts/ui/ft2_stage_widgets.gd").scroll_geometry(Rect2i(inner.end-Vector2i(16,inner.size.y),Vector2i(16,inner.size.y)),scroll,int(inner.size.y/15),_list.size())

func _button_disabled(id:int)->bool:
	if dialog=="shop" and id==8001:
		if selection<0 or selection>=_list.size() or int(_list[selection].id)<=0:return true
		return int(data.load_table("item")[int(_list[selection].id)].price)>int(battle.money)
	if dialog=="buy_receiver" and id==1:return selection<0 or selection>=_list.size() or not bool(_list[selection].get("enabled",false))
	return (dialog=="save" and id==8000) or (dialog=="units" and id==1004 and (vm.mode!=1 or (_units_forced_modal and not source_fullscreen))) or (dialog=="settings" and id==1010 and not source_fullscreen) or (id==1 and dialog in ["buy_quantity","sell_quantity"] and not _quantity_valid()) or (id==1 and dialog=="load" and not _list[selection].occupied)

func _button_at_focus()->bool:
	if dialog=="units" and _units_tab==1 and _focus_control==1089:return true
	for row in _template.get("controls",[]):
		if int(row.id)==_focus_control:return row.class_name=="BUTTON" and (str(row.style).hex_to_int()&15) in [0,1,3,9]
	return false

func cancel_control_capture(lost_focus:bool=false)->void:
	if unit_panel!=null:unit_panel.cancel_capture()
	if experience!=null and experience.active:experience.cancel_control_capture()
	# Native WM_CANCELMODE releases BUTTON/spin capture without BN_CLICKED.
	_captured_control=-1;_keyboard_control=-1;_pressed_control=-1;_spin_capture=0;_spin_pressed=0
	_apply_stage_scroll_commands(_stage_scroll_controller.cancel())
	if lost_focus and dialog in ["stage_select","bgm"]:
		# USER12:05F0 WM_KILLFOCUS is distinct from WM_CANCELMODE. The real
		# Window focus-exited bridge clears the stock search prefix and timer.
		_listbox_input.focus_lost();_stage_search_prefix=""

func _panel(out: Array[Dictionary],rect: Rect2i) -> void:
	out.append({"op":"rect","rect":rect,"color":7,"filled":true})
	preload("res://scripts/ui/ft2_native_widgets.gd").raised(out,Rect2i(rect.position+Vector2i.ONE,rect.size-Vector2i.ONE))
	for point in [Vector2i(rect.end.x-2,rect.position.y+1),Vector2i(rect.position.x+1,rect.end.y-2)]:out.append({"op":"rect","rect":Rect2i(point,Vector2i.ONE),"filled":true,"color":248})
	out.append({"op":"line","from":rect.end-Vector2i.ONE,"to":Vector2i(rect.end.x-1,rect.position.y),"color":0})
	out.append({"op":"line","from":rect.end-Vector2i.ONE,"to":Vector2i(rect.position.x,rect.end.y-1),"color":0})

func _text(out: Array[Dictionary],text: String,pos: Vector2i,color: int,font:Dictionary={}) -> void:
	if font.is_empty():font=preload("res://scripts/ui/ft2_widgets.gd").dialog_font(resource_id) if dialog!="menu" else UI_FONT
	out.append({"op":"text","text":text,"raw_text":text,"pos":pos,"font":font,"color":color,"decor":{"raw_gdi":true}})

func _menu_width(rows: Array) -> int:
	var left := 0; var right := 0
	for row in rows:
		var pieces: PackedStringArray = str(row.get("text","")).split("\t")
		left = maxi(left,_ui_width(_caption(pieces[0])))
		if pieces.size()>1: right = maxi(right,_ui_width(_caption(pieces[1])))
	return maxi(47,left+right+(56 if right>0 else 49)) #Win95 native119 recipient/sale popup width = longest caption+49.

func _ui_width(text: String) -> int:
	if vm.measure_text.is_valid(): return int(vm.measure_text.call(text,UI_FONT).width)
	return data.encode_cp949(text).size()*6

func _menu_rects(rows: Array,pos: Vector2i) -> Array[Rect2i]:
	var width := _menu_width(rows)
	var y := pos.y+3
	var rects: Array[Rect2i] = []
	for row in rows:
		var height := 9 if str(row.get("text","")) == "" else 18
		rects.append(Rect2i(pos.x+3,y,width-6,height)); y += height
	return rects

func _menu_hit(point: Vector2i,rows: Array,pos: Vector2i) -> int:
	var rects := _menu_rects(rows,pos)
	for i in rects.size():
		if rects[i].has_point(point): return i
	return -1

func _draw_menu(out: Array[Dictionary],rows: Array,pos: Vector2i,current: int) -> void:
	var rects := _menu_rects(rows,pos)
	if rects.is_empty(): return
	_menu_panel(out,Rect2i(pos,Vector2i(_menu_width(rows),rects[-1].end.y-pos.y+3)))
	var max_left:=0
	for row in rows:max_left=maxi(max_left,_ui_width(_caption(str(row.get("text","")).split("\t")[0])))
	for i in rows.size():
		var row: Dictionary = rows[i]; var rect := rects[i]
		if str(row.get("text","")) == "":
			out.append({"op":"line","from":rect.position+Vector2i(0,3),"to":Vector2i(rect.end.x-1,rect.position.y+3),"color":248})
			out.append({"op":"line","from":rect.position+Vector2i(0,4),"to":Vector2i(rect.end.x-1,rect.position.y+4),"color":255});continue
		var flags := int(row.get("flags",0)) if row.get("flags",0) is int or row.get("flags",0) is float else str(row.get("flags","0")).hex_to_int()
		var disabled := (flags&3) != 0
		if i == current: out.append({"op":"rect","rect":rect,"color":4,"filled":true})
		var color := 248 if disabled else (255 if i == current else 0)
		var pieces: PackedStringArray = str(row.get("text","")).split("\t")
		var label:=_caption(pieces[0]);var point:=rect.position+Vector2i(21,3)
		_text(out,label,point,color)
		var prefix:=pieces[0].find("&")
		if prefix>=0 and prefix+1<pieces[0].length():
			var before:=pieces[0].substr(0,prefix).replace("&","");var letter:=pieces[0].substr(prefix+1,1)
			var x:=point.x+_ui_width(before)
			out.append({"op":"line","from":Vector2i(x,point.y+11),"to":Vector2i(x+_ui_width(letter)-1,point.y+11),"color":color})
		if pieces.size()>1:
			var right := _caption(pieces[1]); _text(out,right,Vector2i(pos.x+33+max_left,rect.position.y+3),color)
		if not row.get("children",[]).is_empty():
			var x := rect.end.x-10; var y := rect.position.y+7
			for column in 4: out.append({"op":"line","from":Vector2i(x+column,y-3+column),"to":Vector2i(x+column,y+3-column),"color":color})

func _menu_panel(out:Array[Dictionary],rect:Rect2i)->void:
	out.append({"op":"rect","rect":rect,"color":7,"filled":true})
	var inner:=Rect2i(rect.position+Vector2i.ONE,rect.size-Vector2i(2,2))
	out.append({"op":"line","from":inner.position,"to":Vector2i(inner.end.x-1,inner.position.y),"color":255})
	out.append({"op":"line","from":inner.position,"to":Vector2i(inner.position.x,inner.end.y-1),"color":255})
	out.append({"op":"line","from":Vector2i(inner.end.x-1,inner.position.y),"to":inner.end-Vector2i.ONE,"color":248})
	out.append({"op":"line","from":Vector2i(inner.position.x,inner.end.y-1),"to":inner.end-Vector2i.ONE,"color":248})
	out.append({"op":"line","from":Vector2i(rect.end.x-1,rect.position.y),"to":rect.end-Vector2i.ONE,"color":0})
	out.append({"op":"line","from":Vector2i(rect.position.x,rect.end.y-1),"to":rect.end-Vector2i.ONE,"color":0})

func _pop_menu() -> void:
	var previous: Dictionary = _menu_stack.pop_back()
	menu_rows = previous.rows; menu_position = previous.pos; selection = int(previous.selection)

func _experience_finished(_accepted: bool,_allocations: Array) -> void:
	dialog = ""; resource_id = 0; _modal_vm = false
	vm.begin_scene_growth()

func _refresh_cursor(point: Vector2i) -> void:
	cursor_refresh_requested.emit(point)

func _list_height() -> int:
	if dialog=="stage_select":return 15
	return 80 if dialog=="units" else (20 if dialog in ["load","save","shop","buy_receiver","magic","inventory","equipment"] else 16)

func _quantity_limit() -> int:
	var owned:int=battle.rules.bag_count(battle.inventory,int(payload.get("item",0)))
	return 9999-owned if dialog=="buy_quantity" else owned

func _quantity_valid() -> bool:
	if dialog=="buy_quantity":return battle.rules.buy_quantity_enabled(int(payload.get("price",0)),int(battle.money),battle.rules.bag_count(battle.inventory,int(payload.get("item",0))),quantity)
	return battle.rules.sell_quantity_enabled(battle.rules.bag_count(battle.inventory,int(payload.get("item",0))),quantity)

func _slot_header(index: int) -> Dictionary:
	if slot_header_provider.is_valid():return slot_header_provider.call(index)
	var raw:=PackedByteArray()
	var user_path:=FT2Content.save_root().path_join("save%02d.dat" % index)
	if data.prefer_user_saves and FT2Content.exists(user_path):raw=FT2Content.bytes(user_path)
	else:
		var path:="data/port_ready/saves/save%02d.json" % index
		if FT2Content.exists(data.resolve(path)):
			var source:Dictionary=data.read_json(path);raw=str(source.header_raw_hex).hex_decode()
	if raw.size()<4:return {}
	var size:=mini(mini(int(raw.decode_u32(0)),468),raw.size())
	var header:=PackedByteArray();header.resize(468);header.fill(0)
	for i in size:header[i]=raw[i]
	if header.decode_u32(0)==0:return {}
	var times:Array=[]
	for i in 8:times.append(header.decode_u16(90+i*2))
	return {"stage":header.decode_s16(4),"round_index":header.decode_s16(38),"title_cp949_raw_hex":header.slice(6,38).hex_encode(),"system_time_words":times}

static func _timestamp(words: Array) -> int:
	if words.size()<8:return 0
	var stamp:=int(words[0])
	for i in [1,3,4,5,6]:stamp=stamp*100+int(words[i])
	return stamp*1000+int(words[7])

func _center_list_unit() -> void:
	if selection<0 or selection>=_list.size() or int(_list[selection].id)<0: return
	if vm.mode != 1: return
	vm.camera_requested.emit({"kind":"actor","slot":int(_list[selection].id)})
	if source_fullscreen:close() #41DC62: modeless windowed107 stays open after camera movement.

func _unit_panel_action(hit: Dictionary) -> void:
	var id:=int(hit.control)
	if id in [1032,1034,1035,1036,1037] and hit.has("item"):
		if int(hit.item.get("id",0))<=0: return
		_push_parent(); _modal_vm=false
		payload={"gear_context":true,"slot":_unit_slot,"held_index":int(hit.item.get("held_index",4)),"item":int(hit.item.get("id",0))}
		_open_gear_menu()
	elif id==1023 and hit.has("item") and int(hit.item.get("id",0))>0:
		_push_parent(); _modal_vm=false
		payload={"item":int(hit.item.id),"bag_index":int(hit.item.bag_index),"price":int(data.load_table("item")[int(hit.item.id)].price)}
		_open("sell_quantity",153)
	elif id==1089:
		var entries:Array=unit_panel.lists.get(1023,[]); var index:=int(unit_panel.selected.get(1023,0))
		if index<entries.size(): _unit_panel_action({"control":1023,"item":entries[index]})

func _push_parent() -> void:
	var painted := commands().duplicate(true)
	_parents.append({"dialog":dialog,"resource":resource_id,"payload":payload.duplicate(true),"selection":selection,"scroll":scroll,"quantity":quantity,"template":_template,"control_rects":_control_rects.duplicate(),"row_rects":_row_rects.duplicate(),"list_rect":_list_rect,"list":_list.duplicate(true),"title":_title,"body":_body_text,"modal_vm":_modal_vm,"slot":_unit_slot,"tab":_units_tab,"draw":painted,"outer":_dialog_outer,"origin":_dialog_origin,"choice_default":_choice_default})

	_parents[-1]["focus_control"]=_focus_control;_parents[-1]["default_button"]=_default_button

func _restore_parent() -> void:
	var p: Dictionary = _parents.pop_back()
	dialog=str(p.dialog); resource_id=int(p.resource); payload=p.payload; selection=int(p.selection); scroll=int(p.scroll); quantity=int(p.quantity)
	_template=p.template; _control_rects=p.control_rects; _row_rects.assign(p.row_rects); _list_rect=p.list_rect; _list=p.list
	_title=str(p.title); _body_text=str(p.body); _modal_vm=bool(p.modal_vm); _unit_slot=int(p.slot); _units_tab=int(p.tab); _menu_stack.clear()
	_dialog_outer=p.outer;_dialog_origin=p.origin;_choice_default=int(p.choice_default)
	_focus_control=int(p.get("focus_control",1));_default_button=int(p.get("default_button",1))
	_pressed_control=-1;_captured_control=-1;_keyboard_control=-1

func _open_gear_menu() -> void:
	var slot := int(payload.slot); var held := int(payload.held_index)
	var unit: PackedByteArray = battle.units[slot]
	var id := int(payload.item); var row: Dictionary = data.load_table("item")[id]
	var hole := -1
	for index in 4:
		if unit.decode_u16(28+index*2)==0: hole=index; break
	dialog="menu"; menu_position=Vector2i(320,200); selection=-1; menu_rows=[]
	if held>=4:
		var enabled: bool = battle.rules.can_equip(id,unit.decode_u16(0))
		menu_rows.append({"id":40016,"text":"장비하다(&E)" if enabled else "이것은 장비할 수 없습니다","flags":0 if enabled else 1,"children":[]})
	else: menu_rows.append({"id":40015,"text":"벗는다(&R)" if hole>=0 else "소유품이 꽉차서 가질수 없다","flags":0 if hole>=0 else 1,"children":[]})
	menu_rows.append({"id":40017,"text":"%d에 판다(&S)" % (int(row.price)>>1),"flags":0,"children":[]})
	for other in mini(10,battle.units.size()):
		if other==slot: continue
		var receiver: PackedByteArray = battle.units[other]
		var kind:=receiver.decode_u16(0)
		if kind==0: continue
		if vm.mode==1 and absi(receiver.decode_s32(8)-unit.decode_s32(8))+absi(receiver.decode_s32(12)-unit.decode_s32(12))>4: continue
		var free:=false
		for index in 4:
			if receiver.decode_u16(28+index*2)==0: free=true; break
		menu_rows.append({"id":kind,"text":"%s에게 넘긴다" % _unit_name(other) if free else "%s(은)는 소유품이 꽉찼다" % _unit_name(other),"flags":0 if free else 1,"children":[]})

func _gear_command(command_id: int) -> void:
	var slot:=int(payload.slot); var offset:=20+int(payload.held_index)*2
	var unit:PackedByteArray=battle.units[slot]; var id:=unit.decode_u16(offset)
	match command_id:
		40015:
			for i in 4:
				if unit.decode_u16(28+i*2)==0: unit.encode_u16(28+i*2,id); unit.encode_u16(offset,0); battle.units[slot]=unit; break
		40016: battle.equip_carried(slot,int(payload.held_index)-4)
		40017: menu_rows=_menu.items[2].children.duplicate(true); selection=0; return
		40018:
			battle.add_money((int(data.load_table("item")[id].price)&65535)>>1); unit.encode_u16(offset,0); battle.units[slot]=unit
		40019: close(7); return
		_:
			if command_id<8 or command_id in [11,23]:
				for other in battle.units.size():
					var receiver:PackedByteArray=battle.units[other]
					if receiver.decode_u16(0)!=command_id or command_id==0: continue
					for i in 4:
						if receiver.decode_u16(28+i*2)==0:
							receiver.encode_u16(28+i*2,id); unit.encode_u16(offset,0); battle.units[other]=receiver; battle.units[slot]=unit; break
					break
	battle.refresh_context(); close()

func hover_cell(cell: Vector2i,pointer_x: int = 0) -> void:
	_pointer_x = pointer_x; _hover_slot = -1; _hover_cell = cell
	for slot in battle.units.size():
		var bytes: PackedByteArray = battle.units[slot]
		if bytes.decode_u16(0) != 0 and bytes.decode_u16(16) != 9 and Vector2i(bytes.decode_s32(8),bytes.decode_s32(12)) == cell:
			_hover_slot = slot; break

func _game_text(out: Array[Dictionary],raw: String,pos: Vector2i,color:int=30,style:int=1) -> Dictionary:
	out.append({"op":"text","text":raw.replace("_"," ").replace("*",","),"raw_text":raw,"pos":pos,"font":CUSTOM_FONT,"color":color,"decor":{"style":style}})
	return vm._measure(raw,16,false)

func _hover_commands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _hover_slot < 0 or _hover_slot >= battle.units.size(): return out
	var bytes: PackedByteArray = battle.units[_hover_slot]
	if bytes.decode_u16(0) == 0: return out
	var left := 0 if _pointer_x > 320 else 348
	out.append_array(preload("res://scripts/ui/ft2_widgets.gd").game_panel(left,376,16,4))
	if preview_unit.is_valid():
		var miniature: Dictionary = preview_unit.call(_hover_slot,Vector2i(left+48,456))
		if not miniature.is_empty(): out.append(miniature)
	var name := _unit_name(_hover_slot)
	# Original %-14s pads ANSIbytes, not Unicode scalars.
	var count: int = data.encode_cp949(name).size()
	var padded := name+" ".repeat(maxi(0,14-count))
	_game_text(out,padded,Vector2i(left+88,400))
	var status := int(bytes.decode_u16(16))
	if status < STATE_NAMES.size(): _game_text(out,STATE_NAMES[status],Vector2i(left+232,400))
	var hp := _game_text(out,"HP",Vector2i(left+88,420))
	var hp_x := left+88+int(hp.width)+33
	# 419E48..419FB4 clamps each raw signed WORD to130; it does not make a percentage.
	var max_hp := mini(130,bytes.decode_s16(36)); var current_hp := mini(130,bytes.decode_s16(38))
	if max_hp > 0: out.append({"op":"bitmap","key":"BMP/WALL.BMP","pos":Vector2i(hp_x,422),"source":Rect2i(0,192,max_hp,16),"transparent":-1})
	if current_hp > 0: out.append({"op":"bitmap","key":"BMP/WALL.BMP","pos":Vector2i(hp_x,422),"source":Rect2i(0,176,current_hp,16),"transparent":-1})
	var mp := _game_text(out,"MP",Vector2i(left+83,440))
	var mp_x := left+83+int(mp.width)+33
	var max_mp := mini(130,bytes.decode_s16(40)); var current_mp := mini(130,bytes.decode_s16(42))
	if max_mp > 0: out.append({"op":"bitmap","key":"BMP/WALL.BMP","pos":Vector2i(mp_x,442),"source":Rect2i(160,176,max_mp,16),"transparent":-1})
	if current_mp > 0: out.append({"op":"bitmap","key":"BMP/WALL.BMP","pos":Vector2i(mp_x,442),"source":Rect2i(160,160,current_mp,16),"transparent":-1})
	return out

func _focus_order()->Array[int]:
	var result:Array[int]=[]
	for row in _template.get("controls",[]):
		var id:=int(row.id)
		if (str(row.style).hex_to_int()&0x10000)==0 or (id==1010 and dialog=="settings" and not source_fullscreen):continue
		if row.class_name=="BUTTON" and _button_disabled(id):continue
		result.append(id)
	if dialog=="units" and _units_tab==1 and _control_rects.has(1089):result.append(1089)
	return result
func _quantity_reparse()->void:
	_caret_epoch=_elapsed
	quantity=int(_quantity_text) if _quantity_text.is_valid_int() and int(_quantity_text)<=0xFFFFFFFF else 0
	_quantity_update_fields()
func _quantity_insert(text:String)->void:
	if _quantity_replace:_quantity_text=text;_quantity_caret=text.length()
	else:_quantity_text=_quantity_text.insert(_quantity_caret,text);_quantity_caret+=text.length()
	_quantity_replace=false;_quantity_reparse()
func _quantity_step(delta:int)->void:
	quantity=clampi(quantity+delta,1,maxi(1,_quantity_limit()));_quantity_text=str(quantity);_quantity_caret=0;_quantity_replace=false;_caret_epoch=_elapsed;_quantity_update_fields()
func _raw_width(text:String,font:Dictionary)->int:
	return int(vm.measure_text.call(text,font).width) if vm.measure_text.is_valid() else text.length()*6
func _focus_rect(out:Array[Dictionary],rect:Rect2i)->void:
	for x in range(rect.position.x,rect.end.x):
		for y in [rect.position.y,rect.end.y-1]:
			if ((x+y-_dialog_outer.position.x-_dialog_outer.position.y)&1)==0:out.append({"op":"rect","rect":Rect2i(x,y,1,1),"filled":true,"color":0})
	for y in range(rect.position.y+1,rect.end.y-1):
		for x in [rect.position.x,rect.end.x-1]:
			if ((x+y-_dialog_outer.position.x-_dialog_outer.position.y)&1)==0:out.append({"op":"rect","rect":Rect2i(x,y,1,1),"filled":true,"color":0})

func _caption_text(out:Array[Dictionary],caption:String,point:Vector2i,color:int,font:Dictionary={})->void:
	if font.is_empty():font=preload("res://scripts/ui/ft2_widgets.gd").dialog_font(resource_id)
	var label:=_caption(caption);_text(out,label,point,color,font)
	var prefix:=caption.find("&")
	if prefix>=0 and prefix+1<caption.length():
		var x:=point.x+_raw_width(caption.substr(0,prefix),font)
		var width:=_raw_width(caption.substr(prefix+1,1),font)
		var ascent:int=int(vm.measure_text.call(label,font).get("ascent",-int(font.height)-2)) if vm.measure_text.is_valid() else -int(font.height)-2
		out.append({"op":"line","from":Vector2i(x,point.y+ascent+1),"to":Vector2i(x+width-1,point.y+ascent+1),"color":color})
func _draw_check(out:Array[Dictionary],rect:Rect2i,caption:String,radio:bool,checked:bool,disabled:bool,focused:bool,pressed:bool=false)->void:
	var box:=Rect2i(rect.position+Vector2i(0,(rect.size.y-13)/2),Vector2i(13,13))
	preload("res://scripts/ui/ft2_native_widgets.gd").glyph(out,box.position,radio,checked,disabled,pressed)
	var point:=rect.position+Vector2i(18,(rect.size.y-12)/2)
	if disabled:_caption_text(out,caption,point+Vector2i.ONE,255)
	_caption_text(out,caption,point,248 if disabled else 0)
	if focused:_focus_rect(out,Rect2i(point-Vector2i.ONE,Vector2i(_raw_width(_caption(caption),UI_FONT)+2,14)))

func _draw_button(out:Array[Dictionary],rect:Rect2i,caption:String,is_default:bool,disabled:bool,focused:bool,pressed:bool=false)->void:
	preload("res://scripts/ui/ft2_native_widgets.gd").button(out,rect,is_default,pressed)
	var font:Dictionary=preload("res://scripts/ui/ft2_widgets.gd").dialog_font(resource_id)
	var size:=Vector2i(_raw_width(_caption(caption),font),-int(font.height))
	var point:=rect.position+(rect.size-size)/2+(Vector2i.ONE if pressed else Vector2i.ZERO)
	var inset:=4 if is_default else 3
	out.append({"op":"rect","rect":Rect2i(point,size),"filled":true,"color":7})
	if disabled:_caption_text(out,caption,point+Vector2i.ONE,255,font)
	_caption_text(out,caption,point,248 if disabled else 0,font)
	if focused:out.append({"op":"focus_rect","rect":Rect2i(rect.position+Vector2i(inset,inset),rect.size-Vector2i(inset*2,inset*2)),"origin":_dialog_outer.position+(Vector2i(1,0)if dialog=="stage_select"else Vector2i.ZERO)})

func _child_offset(resource:int)->Vector2i:
	var template:Dictionary=preload("res://scripts/ui/ft2_widgets.gd").dialog_template(data,resource)
	return preload("res://scripts/ui/ft2_widgets.gd").dlu_rect(template.rect_dialog_units,Vector2i.ZERO,preload("res://scripts/ui/ft2_widgets.gd").dialog_base(resource)).position
func _draw_unit_row(out:Array[Dictionary],slot:int,pos:Vector2i,selected:bool)->void:
	var first:=out.size()
	# Original41D2C2 uses the same 80px WALL band for every roster row.
	out.append({"op":"bitmap","key":"BMP/WALL.BMP","pos":pos,"source":Rect2i(0,80 if selected else 0,_list_rect.size.x,80),"transparent":-1})
	if slot>=0:
		var bytes:PackedByteArray=battle.units[slot]
		if preview_unit.is_valid():
			var miniature:Dictionary=preview_unit.call(slot,pos+Vector2i(32,68),true)
			if not miniature.is_empty():out.append(miniature)
		var name:=_unit_name(slot);var padded:=name+" ".repeat(maxi(0,14-data.encode_cp949(name).size()))
		_game_text(out,padded,pos+Vector2i(64,10),16,0)
		var state:=bytes.decode_u16(16)
		if state<STATE_NAMES.size():_game_text(out,STATE_NAMES[state],pos+Vector2i(208,10),16,0)
		for i in 2:
			var label:="HP" if i==0 else "MP";var textpos:=pos+Vector2i(64 if i==0 else 59,30+i*20)
			var measured:=_game_text(out,label,textpos,16,0);var bar:=textpos+Vector2i(int(measured.width),2)
			out.append({"op":"bitmap","key":"BMP/WALL.BMP","pos":bar,"source":Rect2i(160 if selected else 0,192 if selected else 160,154,16),"transparent":5})
			for current in 2:
				var value:=mini(150,bytes.decode_s16(36+i*4+current*2))
				if value>0:out.append({"op":"bitmap","key":"BMP/WALL.BMP","pos":bar+Vector2i(2,0),"source":Rect2i(160 if i else 0,(176 if current==0 else 160) if i else (192 if current==0 else 176),value,16),"transparent":5})
	for i in range(first,out.size()):out[i]["clip"]=_list_rect

func _move_dialog(position:Vector2i)->void:
	var delta:=position-_dialog_outer.position;_dialog_outer.position=position;_dialog_origin+=delta
	for id in _control_rects:_control_rects[id].position+=delta
	for i in _row_rects.size():_row_rects[i].position+=delta
	_list_rect.position+=delta
func _persist_settings()->void:
	if not persistence_enabled:return
	var file:=FileAccess.open("user://settings.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(settings))

func _preview_music()->void:
	if selection>=0 and selection<_list.size():_bgm_preview_index=int(_list[selection].id);vm.music_requested.emit(_bgm_preview_index)

func _activate_dialog_button()->void:
	var id:=_default_button
	for row in _template.get("controls",[]):
		if int(row.id)==_focus_control and row.class_name=="BUTTON" and (str(row.style).hex_to_int()&15) in [0,1]:id=_focus_control
	match id:
		1078:_ask_leave_shop()
		2,7,1005,1064:close(7)
		1004:_center_list_unit()
		1079:_push_parent();_modal_vm=false;open_units(true)
		8000:close();new_game_requested.emit()
		_:activate()

func _ask_leave_shop()->void:
	_push_parent();_modal_vm=false;_open("leave_shop",126,"가게를 나갑니까?")

func _quantity_update_fields()->void:
	if quantity<1 or quantity>_quantity_limit():return #Source EN_CHANGE leaves prior totals for invalid bounds.
	_quantity_total=int(payload.get("price",0))*quantity
	_quantity_after=mini(999999,int(battle.money)+_quantity_total)

func _complete_flag(value:int)->void:
	settings["complete_flag"]=value;_persist_settings()

## Normal dialogs150/152/160 have separate list controls and native owner-draw
## paths. They must not collapse into the generic plain-text list renderer.
func _detail_list_geometry()->Dictionary:
	var control:=1082 if dialog=="shop" else (1099 if dialog=="buy_receiver" else (1101 if dialog=="bgm" else 1060))
	var r:Rect2i=_control_rects.get(control,_list_rect)
	return preload("res://scripts/ui/ft2_native_widgets.gd").listbox_geometry(r,_list_height(),_list.size(),scroll)

func _uses_detail_scrollbar()->bool:
	return dialog in ["shop","buy_receiver","bgm","load","save","units"]

func _unit_panel_button_state()->void:
	unit_panel.focus_control=_focus_control;unit_panel.pressed_control=_pressed_control
	unit_panel.default_button=_default_button;unit_panel.focus_origin=_dialog_outer.position

func _detail_owner_row(out:Array[Dictionary],row:Rect2i,index:int,current:bool)->void:
	#441112/44112E,4417C2/4417DC: four WALL rows, selected rows+80.
	var source_y:=(index%4)*20+(80 if current else 0)
	for column in range(0,row.size.x,320):
		out.append({"op":"bitmap","key":"BMP/WALL.BMP","pos":row.position+Vector2i(column,0),"source":Rect2i(0,source_y,mini(320,row.size.x-column),20),"transparent":-1,"clip":row})

func _detail_game_text(out:Array[Dictionary],raw:String,point:Vector2i,clip:Rect2i,color:int=16)->void:
	out.append({"op":"text","raw_text":raw,"text":raw.replace("_"," ").replace("*",","),"pos":point,"font":CUSTOM_FONT,"color":color,"decor":{"style":0},"clip":clip})

func _detail_static_lines(out:Array[Dictionary],raw:String,rect:Rect2i,wrap:bool)->void:
	var font:Dictionary=preload("res://scripts/ui/ft2_widgets.gd").dialog_font(resource_id)
	var y:=rect.position.y
	for paragraph in raw.replace("\r\n","\n").replace("\r","\n").split("\n"):
		var lines:Array[String]=[paragraph]
		if wrap:lines=preload("res://scripts/ui/ft2_widgets.gd").wrap_lines(paragraph,rect.size.x,func(value):return _raw_width(value,font))
		for line in lines:
			if not line.is_empty():_text(out,line,Vector2i(rect.position.x,y),0,font);out[-1]["clip"]=rect
			y+=-int(font.height)

func _shop_detail_commands(out:Array[Dictionary])->void:
	var widgets=preload("res://scripts/ui/ft2_native_widgets.gd")
	#441201..441224: header is an independent1081 owner-draw LISTBOX.
	var header:Dictionary=widgets.listbox_frame(out,_control_rects[1081],20,1,0,false)
	var header_row:=Rect2i(header.content.position,Vector2i(header.content.size.x,20))
	_detail_owner_row(out,header_row,0,false)
	_detail_game_text(out,"명칭"+" ".repeat(34)+"가격",header_row.position+Vector2i(40,2),header_row)
	var geometry:Dictionary=widgets.listbox_frame(out,_control_rects[1082],20,_list.size(),scroll)
	var content:Rect2i=geometry.content
	var first:=int(geometry.top)
	var table:Array=data.load_table("item")
	for i in mini(int(geometry.paint_rows),_list.size()-first):
		var index:=first+i
		var row:=Rect2i(content.position+Vector2i(0,i*20),Vector2i(content.size.x,20)).intersection(content)
		_detail_owner_row(out,row,index,index==selection)
		var id:=int(_list[index].id)
		if id<=0 or id>=table.size():continue
		#441233..44128B: icon is WALL[14+icon/20][icon%20], keysourcing1.
		var icon:int=battle.rules.item_icon(id)
		out.append({"op":"bitmap","key":"BMP/WALL.BMP","pos":row.position+Vector2i(12,2),"source":Rect2i((icon%20)*16,(14+int(icon/20))*16,16,16),"transparent":5,"clip":row})
		_detail_game_text(out,str(table[id].name),row.position+Vector2i(40,1),row)
		_detail_game_text(out,"%6d"%int(table[id].price),row.position+Vector2i(264,1),row)
	var selected_id:=int(_list[selection].id) if selection>=0 and selection<_list.size() else 0
	_detail_static_lines(out,unit_panel.description("ITEM",selected_id),_control_rects[1077],true)

func _receiver_detail_commands(out:Array[Dictionary])->void:
	var geometry:Dictionary=preload("res://scripts/ui/ft2_native_widgets.gd").listbox_frame(out,_control_rects[1099],20,_list.size(),scroll)
	var content:Rect2i=geometry.content
	var first:=int(geometry.top)
	for i in mini(int(geometry.paint_rows),_list.size()-first):
		var index:=first+i
		var row:=Rect2i(content.position+Vector2i(0,i*20),Vector2i(content.size.x,20)).intersection(content)
		_detail_owner_row(out,row,index,index==selection)
		if int(_list[index].id)>=0:
			_detail_game_text(out,str(_list[index].text),row.position+Vector2i(8,1),row,16 if bool(_list[index].enabled) else 25)
	#4417FA..44193A: all worn four and carried four names, each followed byCRLF.
	var gear_text:=""
	var slot:=int(_list[selection].id) if selection>=0 and selection<_list.size() else -1
	var items:Array=data.load_table("item")
	if slot>=0 and slot<battle.units.size():
		var raw:PackedByteArray=battle.units[slot]
		for offset in range(20,36,2):
			var id:=raw.decode_u16(offset)
			if id>0 and id<items.size():gear_text+=str(items[id].name)+"\r\n"
	_detail_static_lines(out,gear_text,_control_rects[1100],false)

func _bgm_detail_commands(out:Array[Dictionary])->void:
	var geometry:Dictionary=preload("res://scripts/ui/ft2_native_widgets.gd").listbox_frame(out,_control_rects[1101],16,_list.size(),scroll)
	var content:Rect2i=geometry.content
	var first:=int(geometry.top)
	for i in mini(int(geometry.paint_rows),_list.size()-first):
		var index:=first+i
		var row:=Rect2i(content.position+Vector2i(0,i*16),Vector2i(content.size.x,16)).intersection(content)
		if index==selection:out.append({"op":"rect","rect":row,"filled":true,"color":4})
		_text(out,str(_list[index].text),row.position+Vector2i(2,0),255 if index==selection else 0);out[-1]["clip"]=content
		if index==selection and _focus_control==1101:out.append({"op":"focus_rect","rect":row,"origin":_dialog_outer.position})







func _unit_tab_rect(index:int)->Rect2i:
	#Measured originalCOMCTL TCS_BUTTONS TCM_GETITEMRECT,96DPI/Gulim-16.
	var tab:Rect2i=_control_rects.get(1022,Rect2i())
	return Rect2i(tab.position+Vector2i(2+index*63,0),Vector2i(60,24))

func _unit_tab_at(point:Vector2i)->int:
	for i in 4:
		if _unit_tab_rect(i).has_point(point):return i
	return -1

func _draw_unit_tabs(out:Array[Dictionary])->void:
	var labels:=["능력","장비","마법","도구"]
	for i in 4:
		var r:=_unit_tab_rect(i);var selected:bool=i==_units_tab
		if selected:
			#Native107 WM_PRINT selected mask, not ordinaryBS_PUSHBUTTON depressededge.
			out.append({"op":"rect","rect":r,"filled":true,"color":7})
			out.append({"op":"line","from":r.position,"to":Vector2i(r.end.x-2,r.position.y),"color":0})
			out.append({"op":"line","from":r.position,"to":Vector2i(r.position.x,r.end.y-2),"color":0})
			out.append({"op":"line","from":r.position+Vector2i.ONE,"to":Vector2i(r.end.x-3,r.position.y+1),"color":248})
			out.append({"op":"line","from":r.position+Vector2i.ONE,"to":Vector2i(r.position.x+1,r.end.y-3),"color":248})
			out.append({"op":"line","from":Vector2i(r.end.x-1,r.position.y),"to":r.end-Vector2i.ONE,"color":255})
			out.append({"op":"line","from":Vector2i(r.position.x,r.end.y-1),"to":r.end-Vector2i.ONE,"color":255})
		else:preload("res://scripts/ui/ft2_native_widgets.gd").raised(out,r)
		#All16native labelmasks matchtheprovidedfont exactlyat(6,3), pressed+1/+1.
		_text(out,labels[i],r.position+Vector2i(7,4) if selected else r.position+Vector2i(6,3),0,preload("res://scripts/ui/ft2_widgets.gd").dialog_font(107))
		if selected and _focus_control==1022:
			out.append({"op":"focus_rect","rect":Rect2i(r.position+Vector2i(2,2),r.size-Vector2i(4,4)),"origin":_control_rects[1022].position+Vector2i(1,0)})
