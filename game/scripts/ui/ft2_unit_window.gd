extends RefCounted
## Source404210/4042B0/41DD50 lifetime for the separate windowed107 instance.
## Host window creation and input delivery belong to main; headless tests use logical state.
var _owner:WeakRef
var panel
var exists:=false
var visible:=false
var outer_rect:=Rect2i(17,24,605,431)
var refresh_count:=0
var creation_enabled:=true
var dragging:=false
var _drag_start:=Vector2i.ZERO
var _drag_pointer:=Vector2i.ZERO

func _init(owner)->void:_owner=weakref(owner)
func owner():return _owner.get_ref()

func profile()->Dictionary:
	return {"resource":107,"modal":false,"exists":exists,"visible":visible,"outer_rect":outer_rect,"outer_size":Vector2i(605,431),"client_size":Vector2i(599,406),"nonclient_extra":Vector2i(6,25),"painted_nonclient":true,"activate":false}

func _notify(operation:String,extra:Dictionary={})->void:
	var request:=profile();request.merge(extra,true);owner().unit_window_requested.emit(operation,request)

func _preference(value:bool)->void:
	owner().settings["unit_view"]=value;owner()._persist_settings()

func create()->bool:
	if exists:return true
	var ui=owner()
	if ui.battle.units.is_empty() or ui.battle.units[0].decode_u16(0)==0:return false #404210 entry guard.
	if not creation_enabled:_preference(false);return false
	panel=ui.get_script().new();panel._is_unit_window_panel=true;panel._unit_window_owner=weakref(ui)
	panel.configure(ui.data,ui.battle,ui.vm,false);panel.settings=ui.settings;panel.source_fullscreen=false;panel.persistence_enabled=false
	panel.preview_unit=ui.preview_unit;panel.open_units()
	var saved:Array=ui.settings.get("unit_window_rect",[])
	if saved.size()==4:outer_rect.position=Vector2i(int(saved[0]),int(saved[1]))
	else:outer_rect.position=panel._dialog_outer.position
	outer_rect.size=panel._dialog_outer.size
	panel._move_dialog(Vector2i.ZERO) # Separate Window content uses local source107 coordinates.
	var creation_profile:=profile();creation_profile.merge({"exists":true,"visible":true,"default_relative_to_main":saved.size()!=4},true)
	var made:bool=bool(ui.unit_window_create_provider.call(panel,creation_profile)) if ui.unit_window_create_provider.is_valid() else true
	if not made:panel=null;_preference(false);return false
	exists=true;visible=true;_preference(true);_notify("create",{"default_relative_to_main":saved.size()!=4})
	return true

func service(show:bool)->int:
	if owner().source_fullscreen:return 0 #41DD50 returns before HWND/config access.
	if exists:
		var previous:=visible
		refresh();visible=show;_notify("show",{"show_command":8 if show else 0})
		return int(previous) #ShowWindow's previous visibility, not requested state.
	if show and bool(owner().settings.get("unit_view",false)):create()
	return 0

func toggle()->bool:
	if exists:destroy(true);return false
	return create()

func destroy(persist_preference:bool=true)->bool:
	if not exists:return false
	if panel!=null:panel.cancel_control_capture();panel._unit_window_owner=null
	exists=false;visible=false;dragging=false;panel=null
	if persist_preference:_preference(false)
	_notify("destroy",{"persist_preference":persist_preference})
	return true

func refresh()->bool:
	if not exists or panel==null:return false
	refresh_count+=1;panel.settings=owner().settings
	var result:bool=panel.refresh_107()
	_notify("refresh",{"message":1024,"tab":panel._units_tab})
	return result

func cancel_capture()->void:
	dragging=false
	if panel!=null:panel.cancel_control_capture()

func set_rect(rect:Rect2i)->void:
	#41DB11 SWP_NOSIZE restores left/top only; WM_MOVE persists actual screen LTRB.
	outer_rect=Rect2i(rect.position,outer_rect.size)
	owner().settings["unit_window_rect"]=[outer_rect.position.x,outer_rect.position.y,outer_rect.end.x,outer_rect.end.y]
	owner()._persist_settings();_notify("move")

func blocks_frame()->bool:
	return exists and visible and panel!=null and (dragging or panel.dialog!="units")

func input(event:InputEvent,screen_point:Vector2i)->bool:
	if not exists or not visible or panel==null:return false
	if event is InputEventKey:
		# Global accelerators belong to the main HWND, not the modeless Dialog's key filter.
		if panel.dialog=="units" and (event.keycode in [KEY_F1,KEY_F2,KEY_F3,KEY_F4,KEY_F5,KEY_F10,KEY_F11,KEY_F12,KEY_PAUSE] or (event.ctrl_pressed and event.keycode in [KEY_I,KEY_Z])):return false
		if event.keycode==KEY_ESCAPE and panel.dialog=="units":return true #IDCANCEL2 is not107's close1005.
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if not event.pressed and dragging:dragging=false;return true
		if event.pressed and Rect2i(3,3,outer_rect.size.x-6,18).has_point(Vector2i(event.position)):
			dragging=true;_drag_start=outer_rect.position;_drag_pointer=screen_point;return true
	if event is InputEventMouseMotion and dragging:
		set_rect(Rect2i(_drag_start+screen_point-_drag_pointer,outer_rect.size));return true
	return panel.handle_input(event)
