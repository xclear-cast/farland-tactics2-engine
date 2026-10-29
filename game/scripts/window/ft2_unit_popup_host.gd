extends Node
## Source119 TrackPopupMenu: a separate no-activate surface, not game state.
signal presentation_changed
const View=preload("../render/ft2_battle_view.gd")
const Coordinates=preload("ft2_unit_modal_host.gd")
var data
var main_view
var panel
var window: Window
var painter
var active:=false
var pointer_provider:=Callable() # Explicit headless/validation snapshot; production reads OS once per menu.
var desktop_rect_override:=Rect2i() # Headless only; never changes the actual desktop.
var source107_rect_provider:=Callable()
var logical_rect:=Rect2i()
var screen_rect:=Rect2i()
var pointer_anchor:=Vector2i.ZERO
var desktop_rect:=Rect2i()
var placement_available:=false
var generation:=0
var last_cancel_reason:=""
var failures:Array=[]
var _rows:Array=[]
var _commands:Array=[]
var _colors:=PackedByteArray()
var _owner_focus_state:Dictionary={}
var _disposed:=false
var _releasing:=false
var _synchronizing:=false
var _placement_failure_recorded:=false

func configure(store,renderer,owner_rect:Callable)->void:
	data=store;main_view=renderer;source107_rect_provider=owner_rect

func accepts(interface)->bool:
	return interface!=null and interface.dialog=="menu" and bool(interface.payload.get("gear_context",false)) and not interface._parents.is_empty() and interface._parents[-1].dialog=="units"

func synchronize(interface,all_commands:Array)->Array:
	if _disposed:return all_commands
	if _synchronizing:
		return interface._parents[-1].draw if accepts(interface) else all_commands
	_synchronizing=true
	var owner_commands:Array=all_commands
	if not accepts(interface):
		if active:
			_release(true)
			owner_commands=interface.commands()
		if interface!=null and interface.dialog=="units":
			_owner_focus_state={"focus_control":interface._focus_control,"default_button":interface._default_button}
	else:
		panel=interface
		owner_commands=panel._parents[-1].draw
		var changed:bool=not active or panel.menu_rows!=_rows
		if changed:
			_rows=panel.menu_rows.duplicate(true);generation+=1;last_cancel_reason=""
			_place_at_pointer()
		else:
			# A programmatic owner move must not move a non-owned native menu.
			if placement_available:
				logical_rect.position=screen_rect.position-_owner_rect().position
				panel.menu_position=logical_rect.position
		active=true
		if not is_instance_valid(painter):_create()
		if is_instance_valid(painter):
			all_commands=panel.commands()
			var own:Array=Coordinates.translate(all_commands.slice(owner_commands.size()),-logical_rect.position)
			if own!=_commands or main_view.palette.current!=_colors:
				_commands=own.duplicate(true);_colors=main_view.palette.current.duplicate()
				painter.palette.install(_colors)
				painter.service_script_commands([{"op":"clear_rect","surface":"main","rect":Rect2i(0,0,640,480),"color":7},{"op":"paint_main","commands":own},{"op":"present","mode":"main"}])
				if not painter.font.missing.is_empty():failures.append({"fonts":painter.font.missing.duplicate()})
				if not painter.assets.missing.is_empty():failures.append({"assets":painter.assets.missing.duplicate()})
			if changed and is_instance_valid(window):
				window.size=screen_rect.size;window.position=screen_rect.position
	_synchronizing=false
	return owner_commands

func _owner_rect()->Rect2i:
	return Rect2i(source107_rect_provider.call()) if source107_rect_provider.is_valid() else Rect2i()

static func fitted_rect(anchor:Vector2i,size:Vector2i,desktop:Rect2i)->Rect2i:
	# Observed Win95 flags2: flip left at the original X, clamp Y to full desktop bottom.
	var point:=anchor
	if point.x+size.x>desktop.end.x:point.x=anchor.x-size.x
	point.x=maxi(desktop.position.x,point.x)
	point.y=clampi(point.y,desktop.position.y,maxi(desktop.position.y,desktop.end.y-size.y))
	return Rect2i(point,size)

func _place_at_pointer()->void:
	var row_rects:Array=panel._menu_rects(panel.menu_rows,Vector2i.ZERO)
	var size:=Vector2i(panel._menu_width(panel.menu_rows),row_rects[-1].end.y+3) if not row_rects.is_empty() else Vector2i.ZERO
	logical_rect=Rect2i(panel.menu_position,size);screen_rect=Rect2i(Vector2i.ZERO,size)
	placement_available=false
	var pointer_known:=false
	if pointer_provider.is_valid():
		pointer_anchor=Vector2i(pointer_provider.call());pointer_known=true
	elif DisplayServer.get_name()!="headless":
		pointer_anchor=DisplayServer.mouse_get_position();pointer_known=true
	desktop_rect=desktop_rect_override if DisplayServer.get_name()=="headless" else Rect2i()
	if DisplayServer.get_name()!="headless" and pointer_known:
		for screen in DisplayServer.get_screen_count():
			var candidate:=Rect2i(DisplayServer.screen_get_position(screen),DisplayServer.screen_get_size(screen))
			if candidate.has_point(pointer_anchor):desktop_rect=candidate;break
	if pointer_known and desktop_rect.has_area() and size.x>0 and size.y>0:
		screen_rect=fitted_rect(pointer_anchor,size,desktop_rect)
		logical_rect.position=screen_rect.position-_owner_rect().position
		panel.menu_position=logical_rect.position;placement_available=true
	elif DisplayServer.get_name()!="headless" and not _placement_failure_recorded:
		failures.append({"popup_pointer_or_desktop_unavailable":true});_placement_failure_recorded=true

func _create()->void:
	if DisplayServer.get_name()!="headless" and not placement_available:return
	painter=View.new()
	if DisplayServer.get_name()=="headless":add_child(painter);painter.configure(data);return
	window=Window.new();window.name="Unit119Popup";window.title="장비 메뉴"
	window.visible=false;window.force_native=true;window.borderless=true;window.unresizable=true
	window.popup_window=true;window.unfocusable=true;window.transient=false;window.exclusive=false
	window.initial_position=Window.WINDOW_INITIAL_POSITION_ABSOLUTE
	window.size=screen_rect.size;window.position=screen_rect.position
	add_child(window);window.add_child(painter);painter.configure(data)
	window.window_input.connect(deliver_input);window.close_requested.connect(cancel)
	# popup() forces transient ownership and usable-area fitting. Source has neither.
	window.show() # No focus request; owner/thread keyboard focus must be retained.
	if window.get_window_id()==DisplayServer.INVALID_WINDOW_ID:failures.append({"popup119_creation_failed":true})

func deliver_input(event:InputEvent)->void:
	if not active or panel==null or _releasing or _synchronizing:return
	var translated:InputEvent=event.duplicate()
	if translated is InputEventMouse:translated.position+=Vector2(logical_rect.position)
	panel.handle_input(translated)
	if translated is InputEventKey and translated.pressed and translated.keycode==KEY_ESCAPE:last_cancel_reason="escape"
	presentation_changed.emit()

func deliver_owner_input(event:InputEvent,screen_point:Vector2i)->void:
	if not active or panel==null or _releasing or _synchronizing:return
	var translated:InputEvent=event.duplicate()
	if translated is InputEventMouse:translated.position=Vector2(screen_point-_owner_rect().position)
	if translated is InputEventMouseButton and translated.pressed and not screen_rect.has_point(screen_point):last_cancel_reason="outside_click"
	panel.handle_input(translated);presentation_changed.emit()

func cancel()->void:
	if not active or panel==null or _releasing or _synchronizing:return
	last_cancel_reason="native_close_or_outside";panel.close(7);presentation_changed.emit()

func image()->Image:
	if not is_instance_valid(painter):return null
	return painter.snapshot_image().get_region(Rect2i(Vector2i.ZERO,logical_rect.size))

func snapshot()->Dictionary:
	return {"active":active,"kind":"source119_gear_or_sale_popup","generation":generation,"logical_rect":logical_rect,"screen_rect":screen_rect,"pointer_anchor":pointer_anchor,"desktop_rect":desktop_rect,"placement_available":placement_available,"native_window":is_instance_valid(window),"requested_native_owner":0,"requested_no_activate":true,"requested_exclusive":false,"source119_callback_owner":"current119HWND","source_track_flags":2,"last_cancel_reason":last_cancel_reason,"failures":failures.duplicate(true),"scope":"Headless proves placement/own CPU/input mapping only. Actual native owner/no-activation/focus/outside-click require the separately guarded private GUI QA."}

func _release(restore_owner_state:bool)->void:
	if _releasing:return
	_releasing=true
	var retired_panel=panel;var retired_window:Window=window;var retired_painter=painter
	window=null;painter=null;panel=null;active=false;_rows.clear();_commands.clear();_colors=PackedByteArray()
	if restore_owner_state and retired_panel!=null and retired_panel.dialog=="units" and not _owner_focus_state.is_empty():
		retired_panel._focus_control=int(_owner_focus_state.focus_control);retired_panel._default_button=int(_owner_focus_state.default_button);retired_panel.cancel_control_capture()
	if is_instance_valid(retired_painter):
		retired_painter.dispose()
		if not retired_painter.is_queued_for_deletion():retired_painter.queue_free()
	if is_instance_valid(retired_window):
		retired_window.hide()
		if is_instance_valid(retired_window) and not retired_window.is_queued_for_deletion():retired_window.queue_free()
	# Closing a no-activate menu must not activate another window either.
	_releasing=false

func dispose()->void:
	if _disposed:return
	_disposed=true;_release(false);main_view=null;data=null;source107_rect_provider=Callable()
