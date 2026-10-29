class_name FT2Overview
extends Node
## F3 fullscreen mode6 and optional owned View window, original source protocol.
signal mode_requested(mode: int)
signal camera_requested(center: Vector2i)
signal command_forwarded(command: int)
signal overlay_changed(commands: Array)
signal cursor_changed(resource_id: int)
signal unsupported(details: Dictionary)

const Program = preload("ft2_overview_program.gd")
const Surface = preload("../render/ft2_indexed_surface.gd")
const DEST = Program.DEST
const SCRATCH = Program.SCRATCH
const CACHE = Program.CACHE
var data
var battle
var view
var active = false
var fullscreen = true
var windowed_preferred = false
var world_size = Vector2i(640,480)
var map_rect = Rect2i(0,0,640,480)
var mode = 1
var cursor_id = 102
var external_cursor_owner = false
var captured = false
var private_exists = false
var public_exists = false
var previous_visible = false
var satellite_enabled = false
var outer_rect = Rect2i(0,0,640,480)
var nonclient_extra = Vector2i.ZERO
var overlay: Array = []
var last_program: Array = []
var paint_count = 0
var cursor_provider: Callable
var creation_bounds_provider: Callable
var source_surfaces_provider: Callable
var persistence_enabled = true
var window_creation_enabled = true
var _window: Window
var _window_sprite: Sprite2D
var _window_texture: ImageTexture
var _resizing = false
var _dest
var _scratch
var _source_bank: Dictionary = {}
var _cursor_resources: Dictionary = {}
var _cursor_layer: CanvasLayer
var _cursor_sprite: Sprite2D
var _cursor_material: ShaderMaterial
var _config = ConfigFile.new()
var _config_path = "user://view.cfg"

func configure(source_data,model,battle_view) -> void:
	data = source_data
	battle = model
	view = battle_view
	_dest = Surface.new(640,480,0)
	_scratch = Surface.new(640,480,0)
	if persistence_enabled and _config.load(_config_path) == OK:
		var r = _config.get_value("View","WinRect",[0,0,640,480])
		outer_rect = Rect2i(int(r[0]),int(r[1]),int(r[2])-int(r[0]),int(r[3])-int(r[1]))
		satellite_enabled = bool(_config.get_value("Field","SatelliteView",false))
	_refresh_world()
	if battle != null and not battle.visual_requested.is_connected(_on_action): battle.visual_requested.connect(_on_action)
	if DisplayServer.get_name() != "headless" and not external_cursor_owner: _prepare_cursor()

func _refresh_world() -> void:
	if battle != null and battle.navigation != null: world_size = battle.navigation.canvas

func _cursor() -> Vector2i:
	if cursor_provider.is_valid(): return Vector2i(cursor_provider.call())
	return Vector2i(get_viewport().get_mouse_position()) if is_inside_tree() else Vector2i.ZERO

func enter(windowed: bool = false) -> bool:
	if battle != null and (battle.map_id < 0 or battle.substate != 0): return false
	_refresh_world()
	assert(world_size.x > 0 and world_size.y > 0)
	fullscreen = not windowed
	windowed_preferred = windowed
	if windowed:
		if public_exists:
			close(true)
			return false
		var made = _create_window()
		public_exists = made
		satellite_enabled = true
		_persist_setting()
		return made
	map_rect = Program.fit(world_size)
	active = true
	mode = 6
	mode_requested.emit(6)
	request_paint()
	#4327C0 requests same-position cursor refresh; coordinates come from polling.
	if DisplayServer.get_name() != "headless" and is_inside_tree(): Input.warp_mouse(Vector2(_cursor()))
	return true

func close(via_main: bool = true, reset_cursor: bool = false) -> void:
	if active:
		active = false
		mode = 1
		overlay.clear()
		overlay_changed.emit([])
		if reset_cursor: _set_cursor(102)
		mode_requested.emit(1)
		return
	if private_exists:
		_capture_window_rect()
		_persist_rect()
		private_exists = false
		previous_visible = false
		captured = false
		if is_instance_valid(_window):
			_window.hide()
			_window.queue_free()
		_window = null
		_window_sprite = null
	if via_main:
		public_exists = false
		satellite_enabled = false
		_persist_setting()
	# A window-manager close leaves public_exists/SatelliteView stale, like WM_DESTROY.

func release_for_display_change() -> void:
	#40D93C->406BC0(0): raw destruction, preserving SatelliteView and WinRect.
	# close() is an owner toggle that clears preference; close(false) intentionally
	# leaves the public handle stale. A display rebuild must clear both references.
	if private_exists or is_instance_valid(_window):
		_capture_window_rect()
		_persist_rect()
	private_exists=false;public_exists=false;previous_visible=false;captured=false
	active=false;mode=1 # No mode_requested signal: the caller owns VMmode and sourcegate.
	overlay.clear();overlay_changed.emit([])
	if is_instance_valid(_window_sprite):
		_window_sprite.texture=null
		_window_sprite.material=null
	_window_texture=null
	_window_sprite=null
	if is_instance_valid(_window):
		# Old deferred Window events must not affect a newly restored instance.
		for signal_name in ["close_requested","size_changed","window_input"]:
			for connection in _window.get_signal_connection_list(signal_name):
				_window.disconnect(signal_name,connection.callable)
		_window.hide()
		_window.queue_free()
	_window=null
	_source_bank.clear()

func restore_after_display_change(source_fullscreen:bool) -> bool:
	#40DB0B->406BC0(1): caller reaches this only after a successful displayreset
	# and mapresource reload. It is not F3/enter(), which toggles preferences.
	fullscreen=source_fullscreen
	windowed_preferred=not source_fullscreen
	if source_fullscreen or not satellite_enabled:return false
	if battle!=null and battle.map_id<0:return false
	_refresh_world()
	if not public_exists:public_exists=_create_window()
	return public_exists

func handle_command(command: int) -> bool:
	if active:
		input_message(0x111,command)
		return true
	if (command&65535) != 40030: return false
	if battle != null and (battle.map_id < 0 or battle.substate > 4): return false
	if battle != null and battle.substate != 0: return true
	enter(windowed_preferred)
	return true

func handle_input(event: InputEvent) -> bool:
	if not active:
		if event is InputEventMouseMotion and cursor_id in [148,149]: _set_cursor(102)
		return false
	if event is InputEventMouseMotion: return input_message(0x200) != 0
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT: return input_message(0x201) != 0
		if event.button_index == MOUSE_BUTTON_RIGHT: return input_message(0x204) != 0
	# No new ESC or mouse-up binding; F3 is normalized to command40030 by the host.
	return false

func input_message(message: int,wparam: int = 0) -> int:
	var result = Program.fullscreen_input(message,wparam,_cursor(),map_rect,world_size,mode)
	if result.cursor_id >= 0: _set_cursor(result.cursor_id)
	for call in result.camera: _camera(Vector2i(int(call[0]),int(call[1])))
	if int(result.mode) == 1 and mode != 1: close()
	return int(result["return"])

func window_message(message: int,cursor_client: Vector2i,client_size: Vector2i,wparam: int = 0) -> int:
	if message == 0x111:
		command_forwarded.emit(wparam)
		return 0
	if message in [5,0xf]:
		request_paint(client_size)
		return 0
	if message == 2:
		close(false)
		return 0x1234
	if message == 0x46: return 0
	if not message in [0x200,0x201,0x202,0xa2]: return 0x1234
	var result = Program.window_drag(message,captured,cursor_client,client_size,world_size)
	captured = bool(result.capture)
	for call in result.camera: _camera(Vector2i(int(call[0]),int(call[1])))
	if result.service and battle != null: battle.render_service_rng("overview_drag")
	return int(result["return"])

func _camera(center: Vector2i) -> void:
	camera_requested.emit(center)
	if view != null:
		view.camera = Vector2i(clampi(center.x-320,0,maxi(0,world_size.x-640)),clampi(center.y-240,0,maxi(0,world_size.y-480)))
		view._dirty = true

func show_previous_visibility(enable: bool) -> int:
	if fullscreen: return 0
	if private_exists:
		var old = int(previous_visible)
		previous_visible = enable
		if is_instance_valid(_window): _window.visible = enable
		return old
	if enable and satellite_enabled:
		public_exists = _create_window()
	return 0

func get_overlay() -> Array: return overlay
func is_open() -> bool: return active or private_exists

func _create_window() -> bool:
	if private_exists: return true
	if not window_creation_enabled: return false
	var current = creation_bounds_provider.call() if creation_bounds_provider.is_valid() else [outer_rect.position.x,outer_rect.position.y,outer_rect.end.x,outer_rect.end.y]
	var constrained = Program.constrain([0,0,outer_rect.position.x,outer_rect.position.y,outer_rect.size.x,outer_rect.size.y,0],current,[nonclient_extra.x,nonclient_extra.y],[world_size.x,world_size.y],false)
	outer_rect = Rect2i(int(constrained[2]),int(constrained[3]),int(constrained[4]),int(constrained[5]))
	private_exists = true
	previous_visible = true
	if DisplayServer.get_name() == "headless" or not is_inside_tree(): return true
	_window = Window.new()
	_window.visible = false # Configure native ownership before mapping the window.
	_window.title = "전체맵"
	_window.name = "View"
	_window.unresizable = false
	_window.transient = true
	_window.force_native = true
	_window.min_size = Vector2i(1,1)
	_window.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
	_window.position = outer_rect.position
	_window.size = outer_rect.size-nonclient_extra
	add_child(_window)
	_window_sprite = Sprite2D.new()
	_window_sprite.centered = false
	_window_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_window_sprite.material = view._material if view != null else null
	_window.add_child(_window_sprite)
	_window.close_requested.connect(func():close(false))
	_window.size_changed.connect(_window_resized)
	_window.window_input.connect(_window_input)
	_window.show()
	if _window.has_method("get_size_with_decorations"):
		nonclient_extra = Vector2i(_window.call("get_size_with_decorations"))-_window.size
	_capture_window_rect()
	request_paint(_window.size)
	return true

func _capture_window_rect() -> void:
	if not is_instance_valid(_window): return
	var position = _window.position
	if _window.has_method("get_position_with_decorations"): position = Vector2i(_window.call("get_position_with_decorations"))
	outer_rect = Rect2i(position,_window.size+nonclient_extra)

func _window_resized() -> void:
	if _resizing or not is_instance_valid(_window): return
	_resizing = true
	var input = [0,0,_window.position.x,_window.position.y,_window.size.x+nonclient_extra.x,_window.size.y+nonclient_extra.y,0]
	var current = [outer_rect.position.x,outer_rect.position.y,outer_rect.end.x,outer_rect.end.y]
	var p = Program.constrain(input,current,[nonclient_extra.x,nonclient_extra.y],[world_size.x,world_size.y],false)
	_window.position = Vector2i(int(p[2]),int(p[3]))
	_window.size = Vector2i(int(p[4])-nonclient_extra.x,int(p[5])-nonclient_extra.y)
	_capture_window_rect()
	_resizing = false
	request_paint(_window.size)

func _window_input(event: InputEvent) -> void:
	if not is_instance_valid(_window): return
	var point = Vector2i(_window.get_mouse_position())
	if event is InputEventMouseMotion: window_message(0x200,point,_window.size)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT: window_message(0x201 if event.pressed else 0x202,point,_window.size)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F3: command_forwarded.emit(40030)

func _on_action(_plan: Dictionary) -> void:
	if private_exists and previous_visible: call_deferred("request_paint") # Main105 invalidation, not per-frame repaint.

func _persist_setting() -> void:
	if not persistence_enabled: return
	_config.set_value("Field","SatelliteView",satellite_enabled)
	_config.save(_config_path)
func _persist_rect() -> void:
	if not persistence_enabled: return
	_config.set_value("View","WinRect",[outer_rect.position.x,outer_rect.position.y,outer_rect.end.x,outer_rect.end.y])
	_config.save(_config_path)

func _image(key: String) -> Dictionary:
	if view == null or key == "" or key.to_lower().ends_with("/empty"): return {}
	return view.assets.image(key,[[10,112,32]])

func _runtime_sources() -> Dictionary:
	_source_bank.clear()
	var mid = battle.map_id if battle != null else -1
	var background = _image(str(view.map.get("background",""))) if view != null else {}
	if not background.is_empty() and mid in [23,26,52,96] and view.environment != null:
		background = _rotate_rows(background,int(view.environment.row_rotation))
	var sources = {"A":0,"D":0,"layers":[0,0,0,0,0,0],"width":640,"height":480}
	if not background.is_empty():
		_source_bank[1] = background
		sources.A = 1
		sources.width = int(background.width)
		sources.height = int(background.height)
	var keys: Array = []
	if mid in [35,36,37]: keys = ["map/st35b.bmp"]
	elif mid in [42,57]:
		var frame = int(view.environment.frame)%6 if view != null else 0
		keys = ["map/st%02d%s.bmp"%[mid,String.chr((102 if mid == 57 else 99)+frame)]]
	elif mid == 52: keys = ["map/st52c.bmp","map/st52d.bmp"]
	elif mid == 54:
		keys = ["map/st54c.bmp"]
		var cloud = _image("map/st54d.bmp")
		if not cloud.is_empty():
			_source_bank[2] = cloud
			sources.D = 2
	elif mid == 69:
		for code in range(99,105): keys.append("map/st69%s.bmp"%String.chr(code))
	for i in range(keys.size()):
		var image = _image(str(keys[i]))
		if not image.is_empty():
			_source_bank[100+i] = image
			sources.layers[i] = 100+i
	if source_surfaces_provider.is_valid():
		var supplied: Dictionary = source_surfaces_provider.call()
		_source_bank.merge(supplied.get("bank",{}),true)
		sources.merge(supplied.get("sources",{}),true)
		if supplied.has("scratch"): _scratch.pixels = supplied.scratch.pixels.duplicate()
	return sources

static func _rotate_rows(image: Dictionary,offset: int) -> Dictionary:
	var w = int(image.width)
	var h = int(image.height)
	var n = offset%w
	if n == 0: return image
	var bytes: PackedByteArray = image.pixels
	var rotated = bytes.duplicate()
	for y in range(h):
		for x in range(w): rotated[y*w+x] = bytes[y*w+(x+n)%w]
	var out = image.duplicate()
	out.pixels = rotated
	out.erase("$image")
	return out

func request_paint(client_size: Vector2i = Vector2i.ZERO) -> void:
	if view == null or battle == null: return
	if not active and not private_exists: return
	_refresh_world()
	var target = map_rect.size if active else client_size
	if not active and target == Vector2i.ZERO: target = _window.size if is_instance_valid(_window) else outer_rect.size-nonclient_extra
	if target.x <= 0 or target.y <= 0: return
	var sources = _runtime_sources()
	if battle.map_id in [26,69] and int(sources.A) == 0:
		unsupported.emit({"kind":"original_required_background_missing","map":battle.map_id})
		return
	last_program = Program.build(battle.map_id,active,world_size,target,sources,battle.units,Callable(battle.navigation,"project"))
	_execute(last_program)
	paint_count += 1
	if active:
		overlay = [{"op":"indexed_image","image":_dest.dictionary(),"pos":Vector2i.ZERO,"key":-1}]
		overlay_changed.emit(overlay)
	elif is_instance_valid(_window_sprite):
		var bytes: PackedByteArray = _dest.pixels
		var crop = PackedByteArray()
		crop.resize(target.x*target.y)
		for y in range(target.y):
			for x in range(target.x): crop[y*target.x+x] = bytes[y*640+x]
		var image = Image.create_from_data(target.x,target.y,false,Image.FORMAT_L8,crop)
		_window_texture = ImageTexture.create_from_image(image)
		_window_sprite.texture = _window_texture

func _source(id: int,rect: Variant) -> Dictionary:
	if id == SCRATCH: return {"image":_scratch.dictionary(),"rect":rect}
	if id == DEST: return {"image":_dest.dictionary(),"rect":rect}
	if id >= CACHE and id < CACHE+64:
		var index = id-CACHE
		var r: Array = rect.duplicate()
		var dx = Program.div0(index,5)*640
		var dy = (index%5)*480
		for i in [0,2]: r[i] += dx
		for i in [1,3]: r[i] += dy
		return {"image":view._baked,"rect":r,"key":0}
	var image: Dictionary = _source_bank.get(id,{})
	return {"image":image,"rect":rect if rect != null else [0,0,int(image.get("width",0)),int(image.get("height",0))],"key":int(image.get("map_key",0))}

func _execute(program: Array) -> void:
	for op in program:
		if op.get("dest",DEST) == Program.FRONT: continue # Godot window presents the indexed texture.
		var dest = _scratch if int(op.get("dest",DEST)) == SCRATCH else _dest
		if op.op == "fill":
			var r = Rect2i(0,0,640,480) if op.rect == null else _rect(op.rect)
			dest.fill_rect(r,int(op.color))
		elif op.op in ["bitmap","surface_blit"]:
			var source = _source(int(op.source),op.rect)
			if source.image.is_empty(): continue
			var key = int(source.get("key",0)) if op.op == "surface_blit" and int(op.flags) != 0 else -1
			dest.blit(source.image,_rect(source.rect),Vector2i(int(op.xy[0]),int(op.xy[1])),key)
		elif op.op == "DDraw_Blt":
			var source = _source(int(op.source),op.source_rect)
			if source.image.is_empty(): continue
			_stretch(dest,source.image,_rect(source.rect),_rect(op.dest_rect),int(source.get("key",0)) if (int(op.flags)&0x8000) != 0 else -1)

static func _rect(r: Array) -> Rect2i: return Rect2i(int(r[0]),int(r[1]),int(r[2])-int(r[0]),int(r[3])-int(r[1]))
static func _stretch(dest,source: Dictionary,sr: Rect2i,dr: Rect2i,key: int = -1) -> void:
	if dr.size.x <= 0 or dr.size.y <= 0 or sr.size.x <= 0 or sr.size.y <= 0: return
	var clipped = dr.intersection(Rect2i(0,0,dest.width,dest.height))
	var src: PackedByteArray = source.pixels
	var out: PackedByteArray = dest.pixels
	var sw = int(source.width)
	var sh = int(source.height)
	for y in range(clipped.position.y,clipped.end.y):
		var sy = sr.position.y+Program.ratio(y-dr.position.y,sr.size.y,dr.size.y)
		if sy < 0 or sy >= sh: continue
		for x in range(clipped.position.x,clipped.end.x):
			var sx = sr.position.x+Program.ratio(x-dr.position.x,sr.size.x,dr.size.x)
			if sx < 0 or sx >= sw: continue
			var value = int(src[sy*sw+sx])
			if value != key: out[y*dest.width+x] = value
	dest.pixels = out

func _prepare_cursor() -> void:
	_cursor_layer = CanvasLayer.new()
	_cursor_layer.layer = 1000
	add_child(_cursor_layer)
	_cursor_sprite = Sprite2D.new()
	_cursor_sprite.centered = false
	_cursor_sprite.visible = false
	_cursor_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cursor_layer.add_child(_cursor_sprite)
	var shader = Shader.new()
	shader.code = "shader_type canvas_item; render_mode unshaded; uniform sampler2D screen_texture:hint_screen_texture,filter_nearest; uniform sampler2D inverse_mask:filter_nearest; void fragment(){vec4 a=texture(TEXTURE,UV);float inv=texture(inverse_mask,UV).a;vec3 screen=texture(screen_texture,SCREEN_UV).rgb;COLOR=vec4(mix(a.rgb,vec3(1.0)-screen,inv),max(a.a,inv));}"
	_cursor_material = ShaderMaterial.new()
	_cursor_material.shader = shader
	_cursor_sprite.material = _cursor_material

func _set_cursor(id: int) -> void:
	cursor_id = id
	cursor_changed.emit(id)
	if external_cursor_owner: return
	if DisplayServer.get_name() == "headless" or _cursor_sprite == null: return
	var cursor = _decode_cursor(id)
	if cursor.is_empty(): return
	if active and id in [148,149]:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_cursor_sprite.texture = cursor.texture
		_cursor_material.set_shader_parameter("inverse_mask",cursor.inverse)
		_cursor_sprite.position = _cursor()-cursor.hotspot
		_cursor_sprite.visible = true
	else:
		_cursor_sprite.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Input.set_custom_mouse_cursor(cursor.texture,Input.CURSOR_ARROW,Vector2(cursor.hotspot))

func _decode_cursor(id: int) -> Dictionary:
	if _cursor_resources.has(id): return _cursor_resources[id]
	var group_path = data.resolve("data/port_ready/ui/FTO_O/group_cursor_%d_lang1042.bin"%id)
	if not FT2Content.exists(group_path): return {}
	var group = FT2Content.bytes(group_path)
	var image_id = group.decode_u16(18)
	var raw = FT2Content.bytes(data.resolve("data/port_ready/ui/FTO_O/cursor_%d_lang1042.bin"%image_id))
	var width = raw.decode_s32(8)
	var height = absi(raw.decode_s32(12))/2
	var bpp = raw.decode_u16(18)
	assert(bpp == 1,"Authored overview cursors102/148/149 are monochrome")
	var pitch: int = ((width+31)/32)*4
	var start = 4+raw.decode_u32(4)+8
	var bytes = PackedByteArray()
	var inverse = PackedByteArray()
	bytes.resize(width*height*4)
	inverse.resize(width*height*4)
	bytes.fill(0)
	inverse.fill(0)
	for y in range(height):
		var row = height-1-y
		for x in range(width):
			var bit = 7-x%8
			var xor_bit = (raw[start+row*pitch+x/8]>>bit)&1
			var and_bit = (raw[start+height*pitch+row*pitch+x/8]>>bit)&1
			var offset = (y*width+x)*4
			if and_bit == 0:
				for c in range(3): bytes[offset+c] = raw[44+xor_bit*4+2-c]
				bytes[offset+3] = 255
			elif xor_bit == 1:
				for c in range(4): inverse[offset+c] = 255
	var result = {"texture":ImageTexture.create_from_image(Image.create_from_data(width,height,false,Image.FORMAT_RGBA8,bytes)),"inverse":ImageTexture.create_from_image(Image.create_from_data(width,height,false,Image.FORMAT_RGBA8,inverse)),"hotspot":Vector2i(raw.decode_u16(0),raw.decode_u16(2)),"rgba":bytes,"inverse_rgba":inverse,"size":Vector2i(width,height)}
	_cursor_resources[id] = result
	return result
