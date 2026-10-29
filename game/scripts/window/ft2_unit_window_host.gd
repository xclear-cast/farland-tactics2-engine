extends Node
## OS-window adapter for source modeless107. Source lifecycle remains in FT2Interface.
signal forwarded_input(event: InputEvent)
const View = preload("../render/ft2_battle_view.gd")
const Modal153 = preload("ft2_unit_modal_host.gd")
const Popup119 = preload("ft2_unit_popup_host.gd")
var data
var ui
var main_view
var _window: Window
var _painter
var _last_commands: Array = []
var _last_palette = PackedByteArray()
var _disposed = false
var failures: Array = []
var paint_count = 0
var _modal153
var _popup119

func configure(store, interface, renderer) -> void:
	data = store; ui = interface; main_view = renderer
	ui.unit_window_create_provider = Callable(self,"create_window")
	ui.unit_window_requested.connect(_request)

func create_window(_panel, profile: Dictionary) -> bool:
	if _disposed: return false
	if is_instance_valid(_painter): return true
	if DisplayServer.get_name() == "headless":
		_painter = View.new(); add_child(_painter); _painter.configure(data)
		return true # Logical/CPU adapter only; no OS-window evidence in headless.
	_window = Window.new()
	_window.visible = false; _window.unfocusable = true
	_window.name = "Unit107"; _window.title = "유닛 일람"
	_window.force_native = true; _window.borderless = true
	_window.transient = true; _window.unresizable = true
	_window.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
	_window.size = Vector2i(profile.outer_size)
	_window.position = Rect2i(profile.outer_rect).position
	if profile.get("default_relative_to_main",false): _window.position += get_window().position
	add_child(_window)
	_painter = View.new(); _window.add_child(_painter); _painter.configure(data)
	_window.window_input.connect(_input_window)
	_window.close_requested.connect(func(): ui.destroy_unit_window(true))
	_window.focus_exited.connect(func():
		ui.cancel_unit_window_capture()
	)
	show_without_activation()
	if _window.get_window_id() == DisplayServer.INVALID_WINDOW_ID:
		failures.append({"native_window_creation_failed":true}); _release_window(); return false
	return true

func show_without_activation() -> void:
	if not is_instance_valid(_window): return
	# SHOWNA8 must not grab focus. Re-enable future user activation after mapping.
	_window.unfocusable = true; _window.show()
	_window.set_deferred("unfocusable",false)

func _request(operation: String, profile: Dictionary) -> void:
	if _disposed: return
	match operation:
		"create":
			if is_instance_valid(_window): ui.set_unit_window_rect(Rect2i(_window.position,_window.size))
			paint(true)
		"refresh": paint(true)
		"show":
			if profile.visible: show_without_activation(); paint(true)
			elif is_instance_valid(_window): _window.hide()
		"move":
			if is_instance_valid(_window): _window.position = Rect2i(profile.outer_rect).position
		"destroy": _release_window()

func _input_window(event: InputEvent) -> void:
	if ui.dialog != "": return # A primary dialog owns this thread's input pump.
	if is_instance_valid(_modal153) and _modal153.active:
		_modal153.focus_modal();return # Actual DialogBox disables the top-level107 owner.
	var position = _source107_rect().position
	if event is InputEventMouse: position += Vector2i(event.position)
	if is_instance_valid(_popup119) and _popup119.active:
		_popup119.deliver_owner_input(event,position);return
	if not ui.handle_unit_window_input(event,position):
		forwarded_input.emit(event)
		if ui.dialog != "": get_window().grab_focus() # User initiated a main-window accelerator.
	paint(false)

func advance_presentation() -> void:
	# Ordinary107 repaints on its source refresh/input events, not every battle tick.
	if ui.unit_window_visible and ui.unit_window_panel != null and ui.unit_window_panel.dialog != "units": paint(false)

func paint(force: bool = false) -> void:
	if not is_instance_valid(_painter) or not ui.unit_window_exists or ui.unit_window_panel == null: return
	var commands: Array = ui.unit_window_panel.commands()
	if not is_instance_valid(_modal153):
		_modal153=Modal153.new();add_child(_modal153);_modal153.configure(data,main_view,_window)
		_modal153.presentation_changed.connect(func():paint(false))
	commands=_modal153.synchronize(ui.unit_window_panel,commands)
	if not is_instance_valid(_popup119):
		_popup119=Popup119.new();add_child(_popup119);_popup119.configure(data,main_view,Callable(self,"_source107_rect"))
		_popup119.presentation_changed.connect(func():paint(false))
	commands=_popup119.synchronize(ui.unit_window_panel,commands)
	var colors: PackedByteArray = main_view.palette.current
	if not force and commands == _last_commands and colors == _last_palette: return
	_last_commands = commands.duplicate(true); _last_palette = colors.duplicate()
	_painter.palette.install(colors)
	_painter.service_script_commands([
		{"op":"clear_rect","surface":"main","rect":Rect2i(0,0,640,480),"color":7},
		{"op":"paint_main","commands":commands}, {"op":"present","mode":"main"}])
	paint_count += 1
	if not _painter.assets.missing.is_empty(): failures.append({"missing":_painter.assets.missing.duplicate()})
	if not _painter.font.missing.is_empty(): failures.append({"fonts":_painter.font.missing.duplicate()})

func snapshot() -> Dictionary:
	return {"profile":ui.unit_window_profile(),"native_window":is_instance_valid(_window),"paint_count":paint_count,"failures":failures.duplicate(true),"nested153":_modal153.snapshot() if is_instance_valid(_modal153) else {},"popup119":_popup119.snapshot() if is_instance_valid(_popup119) else {},"scope":"Separate borderless source107 rendering/input; headless represents only CPU/lifecycle state."}

func _source107_rect()->Rect2i:
	return Rect2i(_window.position,_window.size) if is_instance_valid(_window) else Rect2i(ui.unit_window_profile().outer_rect)

func popup_image()->Image:
	return _popup119.image() if is_instance_valid(_popup119) else null

func modal_image() -> Image:
	return _modal153.image() if is_instance_valid(_modal153) else null

func image() -> Image:
	if not is_instance_valid(_painter): return null
	var full: Image = _painter.snapshot_image()
	var size: Vector2i = ui.unit_window_profile().outer_size
	return full.get_region(Rect2i(Vector2i.ZERO,size))

func _release_window() -> void:
	if is_instance_valid(_popup119):_popup119.dispose();_popup119.queue_free()
	_popup119=null
	if is_instance_valid(_modal153):_modal153.dispose();_modal153.queue_free()
	_modal153=null
	if is_instance_valid(_painter): _painter.dispose(); _painter.queue_free()
	_painter = null
	if is_instance_valid(_window): _window.hide(); _window.queue_free()
	_window = null; _last_commands.clear(); _last_palette = PackedByteArray()

func dispose() -> void:
	if _disposed: return
	if ui != null:
		ui.destroy_unit_window(false)
		ui.unit_window_create_provider = Callable()
		if ui.unit_window_requested.is_connected(_request): ui.unit_window_requested.disconnect(_request)
	_release_window(); _disposed = true
