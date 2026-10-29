extends Node
## The source118 -> DialogBox153 boundary. No subscriptions, clocks or model writes.
signal presentation_changed
const View = preload("../render/ft2_battle_view.gd")
var data
var main_view
var parent_window: Window
var panel
var window: Window
var painter
var active := false
var desktop_rect_override := Rect2i() # Explicit headless geometry fixture only.
var logical_rect := Rect2i()
var screen_rect := Rect2i()
var failures: Array = []
var last_cancel_result = null
var _commands: Array = []
var _colors := PackedByteArray()
var _disposed := false
var _releasing := false
var _owner_focus_state: Dictionary={}

func configure(store, renderer, source107: Window) -> void:
	data=store;main_view=renderer;parent_window=source107

func accepts(interface) -> bool:
	return interface!=null and interface.dialog=="sell_quantity" and interface.resource_id==153 and not interface._parents.is_empty() and interface._parents[-1].dialog=="units"

func synchronize(interface, all_commands: Array) -> Array:
	if _disposed:return all_commands
	if not accepts(interface):
		if active:
			_release(true)
			all_commands=interface.commands() # Repaint restored default/focus in this same presentation.
		if interface!=null and interface.dialog=="units":
			_owner_focus_state={"focus_control":interface._focus_control,"default_button":interface._default_button}
		return all_commands
	panel=interface;logical_rect=panel._dialog_outer
	var parent_commands: Array=panel._parents[-1].draw
	var own: Array=translate(all_commands.slice(parent_commands.size()),-logical_rect.position)
	if not active:
		active=true;last_cancel_result=null;_create()
	if own!=_commands or main_view.palette.current!=_colors:
		_commands=own.duplicate(true);_colors=main_view.palette.current.duplicate()
		painter.palette.install(_colors)
		painter.service_script_commands([{"op":"clear_rect","surface":"main","rect":Rect2i(0,0,640,480),"color":7},{"op":"paint_main","commands":own},{"op":"present","mode":"main"}])
		if not painter.font.missing.is_empty():failures.append({"fonts":painter.font.missing.duplicate()})
		if not painter.assets.missing.is_empty():failures.append({"assets":painter.assets.missing.duplicate()})
	return parent_commands

func _create() -> void:
	var desktop:=desktop_rect_override
	if DisplayServer.get_name()!="headless":
		var screen:=parent_window.current_screen
		desktop=Rect2i(DisplayServer.screen_get_position(screen),DisplayServer.screen_get_size(screen))
	if desktop.has_area():screen_rect=Rect2i(desktop.position+(desktop.size-logical_rect.size)/2,logical_rect.size)
	else:screen_rect=Rect2i(Vector2i.ZERO,logical_rect.size) # Position unavailable in a headless run.
	painter=View.new()
	if DisplayServer.get_name()=="headless":add_child(painter);painter.configure(data);return
	window=Window.new();window.name="Unit153";window.title="수량"
	window.visible=false;window.force_native=true;window.borderless=true;window.unfocusable=false
	window.transient=true;window.exclusive=true;window.unresizable=true
	window.initial_position=Window.WINDOW_INITIAL_POSITION_ABSOLUTE
	window.size=screen_rect.size;window.position=screen_rect.position
	parent_window.add_child(window);window.add_child(painter);painter.configure(data)
	window.window_input.connect(deliver_input);window.close_requested.connect(cancel)
	window.show();window.grab_focus()
	_focus_after_mapping.call_deferred(window.get_instance_id())
	if window.get_window_id()==DisplayServer.INVALID_WINDOW_ID:failures.append({"modal153_creation_failed":true})

func _focus_after_mapping(instance_id: int) -> void:
	# Native mapping is asynchronous. Do not defer this activation onto a later/reopened dialog.
	await get_tree().process_frame
	if _disposed or not active or not is_instance_valid(window) or window.get_instance_id()!=instance_id:return
	window.grab_focus()

func deliver_input(event: InputEvent) -> void:
	if not active or panel==null:return
	var translated: InputEvent=event.duplicate()
	if translated is InputEventMouse:translated.position+=Vector2(logical_rect.position)
	panel.handle_input(translated)
	if translated is InputEventKey and translated.pressed and translated.keycode==KEY_ESCAPE and panel.dialog=="units":last_cancel_result=0
	presentation_changed.emit()

func cancel() -> void:
	# Native default WM_CLOSE -> WM_COMMAND IDCANCEL2 -> EndDialog(0).
	if not active or panel==null:return
	last_cancel_result=0;panel.close(0);presentation_changed.emit()

func focus_modal() -> void:
	if is_instance_valid(window):window.grab_focus()

static func translate(commands: Array, delta: Vector2i) -> Array:
	var result: Array=[]
	for source in commands:
		var command: Dictionary=source.duplicate(true)
		for key in ["pos","from","to","origin"]:
			if command.has(key):command[key]=Vector2i(command[key])+delta
		for key in ["rect","clip"]:
			if command.has(key):
				var rectangle: Rect2i=command[key];rectangle.position+=delta;command[key]=rectangle
		result.append(command)
	return result

func image() -> Image:
	if not is_instance_valid(painter):return null
	return painter.snapshot_image().get_region(Rect2i(Vector2i.ZERO,logical_rect.size))

func snapshot() -> Dictionary:
	return {"active":active,"resource":153,"source_owner_resource":107,"source_modal_return":last_cancel_result,"logical_rect":logical_rect,"screen_rect":screen_rect,"headless_position_fixture":desktop_rect_override.has_area(),"native_window":is_instance_valid(window),"exclusive":active,"focus_control":int(panel._focus_control) if panel!=null and active else -1,"failures":failures.duplicate(true),"scope":"Separate153 painter; headless verifies CPU/state only. OS modal placement/focus must be tested in parent-owned private display."}

func _release(restore_focus: bool) -> void:
	if _releasing:return
	_releasing=true
	# hide()/focus changes can synchronously emit released keys and repaint callbacks.
	# Detach all owned state before any of these native or renderer side effects.
	var retired_panel=panel
	var retired_window: Window=window
	var retired_painter=painter
	window=null;painter=null;panel=null;active=false;_commands.clear();_colors=PackedByteArray()
	if restore_focus and retired_panel!=null and retired_panel.dialog=="units" and not _owner_focus_state.is_empty():
		retired_panel._focus_control=int(_owner_focus_state.focus_control)
		retired_panel._default_button=int(_owner_focus_state.default_button)
		retired_panel.cancel_control_capture()
	if is_instance_valid(retired_painter):
		retired_painter.dispose()
		if not retired_painter.is_queued_for_deletion():retired_painter.queue_free()
	if is_instance_valid(retired_window):
		retired_window.hide()
		if is_instance_valid(retired_window) and not retired_window.is_queued_for_deletion():retired_window.queue_free()
	if restore_focus and is_instance_valid(parent_window):parent_window.grab_focus()
	_releasing=false

func dispose() -> void:
	if _disposed:return
	_disposed=true;_release(false);parent_window=null;main_view=null;data=null
