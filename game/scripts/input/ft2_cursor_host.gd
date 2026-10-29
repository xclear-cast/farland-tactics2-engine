extends Node
## Opt-in application-window adapter. No mouse-mode change, warp or Win32 hook.
signal descriptor_changed(request: Dictionary)
signal failed_descriptor(details: Dictionary)
const Controller = preload("res://scripts/input/ft2_cursor_controller.gd")
const XOR_SHADER = """shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture: hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D inverse_mask: repeat_disable, filter_nearest;
void fragment(){
 vec4 a=texture(TEXTURE,UV);
 float inv=texture(inverse_mask,UV).a;
 vec3 bg=texture(screen_texture,SCREEN_UV).rgb;
 COLOR=vec4(mix(a.rgb,vec3(1.0)-bg,inv),max(a.a,inv));
}
"""
var controller = Controller.new()
var application_enabled = false
var failures: Array = []
var _viewport: Viewport
var _configured = false
var _disposed = false
var _headless = true
var _pointer = Vector2.ZERO
var _pointer_supplied = false
var _inside = false
var _foreground = true
var _capture_depth = 0
var _descriptor: Dictionary = {}
var _applied_key = ""
var _hardware_apply_count = 0
var _descriptor_requests = 0
var _textures: Dictionary = {}
var _inverse_textures: Dictionary = {}
var _layer: CanvasLayer
var _backbuffer: BackBufferCopy
var _sprite: Sprite2D
var _material: ShaderMaterial
var _software_scale = Vector2.ONE

func configure(source_data, main_viewport: Viewport) -> void:
	if _disposed:return
	if _configured:
		_fail({"reason":"configure_called_twice"});return
	controller.configure(source_data)
	controller.cursor_requested.connect(_requested)
	_viewport=main_viewport
	_headless=DisplayServer.get_name()=="headless"
	_configured=true
	_descriptor=controller.descriptor(102)

func set_application_enabled(enabled: bool) -> void:
	if _disposed:return
	application_enabled=enabled
	_applied_key=""
	if enabled and _configured:_apply_descriptor()
	_update_visibility()

func set_pointer(point: Vector2) -> void:
	if _disposed:return
	_pointer=point;_pointer_supplied=true
	_update_geometry()

func request_resource(id: int) -> Dictionary:
	if _disposed:return {}
	if not _configured:_fail({"reason":"not_configured","id":id});return {}
	var request=controller.request_resource(id)
	if request.is_empty():_fail({"reason":"resource_descriptor_failed","id":id})
	return request

func request_system(id: int) -> Dictionary:
	if _disposed:return {}
	if not _configured:_fail({"reason":"not_configured","id":id});return {}
	var request=controller.request_system(id)
	if request.is_empty():_fail({"reason":"system_descriptor_failed","id":id})
	return request

func message_wait(operation: String, request: Dictionary, now: int) -> void:
	if _disposed:return
	if not _configured:_fail({"reason":"not_configured","operation":operation});return
	match operation:
		"begin":controller.begin_message_wait(now)
		"end":controller.end_message_wait()
		_:_fail({"reason":"unknown_message_wait_operation","operation":operation,"request":request})

func event_wait(operation: String, request: Dictionary, now: int) -> void:
	if _disposed:return
	if not _configured:_fail({"reason":"not_configured","operation":operation});return
	match operation:
		"begin":controller.begin_event_wait(now)
		"end":controller.end_event_wait(bool(request.get("input_wait_preserved",false)))
		_:_fail({"reason":"unknown_event_wait_operation","operation":operation,"request":request})

func advance(now: int, inside: bool, foreground: bool = true) -> Array:
	if _disposed:return []
	_inside=inside;_foreground=foreground
	if not _configured:return []
	# Never queries a Window/Viewport pointer in headless mode.
	if not _headless and not _pointer_supplied and is_instance_valid(_viewport):_pointer=_viewport.get_mouse_position()
	var requests=controller.advance(now,inside,foreground)
	_update_geometry();_update_visibility()
	return requests

func map_motion(substate: int, dragging: bool, control_held: bool) -> Dictionary:
	if _disposed:return {}
	if not _configured:return {}
	return controller.map_motion(substate,dragging,control_held)

func begin_capture(hide_cursor: bool = true) -> bool:
	if _disposed:return false
	# The caller must wait for frame_post_draw after this before viewport readback.
	# Hardware OS cursor pixels are never in that viewport image; only our GPU
	# cursor layer needs suppression for original-framebuffer comparisons.
	if hide_cursor:_capture_depth+=1;_update_visibility()
	return hide_cursor

func end_capture(suppressed: bool) -> void:
	if _disposed:return
	if suppressed:_capture_depth=maxi(0,_capture_depth-1);_update_visibility()

func composite_for_qa(background: Image,pointer: Vector2i) -> Image:
	if _descriptor.is_empty():return background.duplicate()
	return controller.composite_rgb(int(_descriptor.resource_id),background,pointer)

func snapshot() -> Dictionary:
	return {"descriptor":_descriptor.duplicate(true),"headless":_headless,"application_enabled":application_enabled,"disposed":_disposed,"hardware_apply_count":_hardware_apply_count,"descriptor_requests":_descriptor_requests,"render_nodes_created":is_instance_valid(_layer),"owned_texture_count":_textures.size()+_inverse_textures.size(),"logical_software_visible":_software_visible(),"pointer":_pointer,"software_scale":_software_scale,"capture_suppression_depth":_capture_depth,"failures":failures.duplicate(true),"controller":controller.snapshot(),"scope":"OS cursor and separate GPU cursor layer; never writes game indexed framebuffer. Headless makes no Input/window calls. Capture excludes GPU cursor only when explicitly suppressed before draw."}

func _requested(request: Dictionary) -> void:
	_descriptor=request.duplicate(true);_descriptor_requests+=1
	descriptor_changed.emit(_descriptor.duplicate(true))
	_apply_descriptor()

func _fail(details: Dictionary) -> void:
	failures.append(details)
	failed_descriptor.emit(details)

func _software_visible() -> bool:
	return not _disposed and application_enabled and _inside and _capture_depth==0 and _descriptor.get("path","")=="software_xor"

func _texture(id: int) -> Texture2D:
	if _textures.has(id):return _textures[id]
	var image=controller.hardware_image(id)
	if image==null:_fail({"reason":"cursor_not_hardware_representable","id":id});return null
	var texture=ImageTexture.create_from_image(image)
	_textures[id]=texture
	return texture

func _apply_descriptor() -> void:
	if _headless or not application_enabled or not _configured or _descriptor.is_empty():return
	var path=str(_descriptor.get("path",""));var id=int(_descriptor.resource_id)
	var image_id=0 if path=="software_xor" else id
	if path not in ["hardware_rgba","hardware_transparent","software_xor"]:_fail({"reason":"unsupported_cursor_path","descriptor":_descriptor});return
	var texture=_texture(image_id)
	if texture==null:return # Never use Input(null), which would invent a default cursor.
	var hotspot=Vector2.ZERO if path=="software_xor" else Vector2(_descriptor.hotspot)
	var key=str(image_id)+":"+str(hotspot)
	if key!=_applied_key:
		Input.set_custom_mouse_cursor(texture,Input.CURSOR_ARROW,hotspot)
		_hardware_apply_count+=1;_applied_key=key
	if path=="software_xor":
		if not _prepare_layer():return
		var cursor=controller.resource(id)
		if not _textures.has(id):_textures[id]=ImageTexture.create_from_image(Image.create_from_data(cursor.size.x,cursor.size.y,false,Image.FORMAT_RGBA8,cursor.rgba))
		if not _inverse_textures.has(id):_inverse_textures[id]=ImageTexture.create_from_image(Image.create_from_data(cursor.size.x,cursor.size.y,false,Image.FORMAT_RGBA8,cursor.inverse_rgba))
		_sprite.texture=_textures[id]
		_material.set_shader_parameter("inverse_mask",_inverse_textures[id])
	_update_geometry();_update_visibility()

func _prepare_layer() -> bool:
	if is_instance_valid(_layer):return true
	if not is_instance_valid(_viewport):_fail({"reason":"software_cursor_requires_viewport"});return false
	_layer=CanvasLayer.new();_layer.name="FT2CursorLayer";_layer.layer=10000
	_viewport.add_child(_layer)
	_backbuffer=BackBufferCopy.new();_backbuffer.copy_mode=BackBufferCopy.COPY_MODE_VIEWPORT;_layer.add_child(_backbuffer)
	_sprite=Sprite2D.new();_sprite.centered=false;_sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_material=ShaderMaterial.new();var shader=Shader.new();shader.code=XOR_SHADER;_material.shader=shader;_sprite.material=_material
	_layer.add_child(_sprite)
	return true

func _update_geometry() -> void:
	if _headless or not is_instance_valid(_sprite):return
	var screen=_viewport.get_screen_transform()
	var scale=Vector2(screen.x.length(),screen.y.length())
	if scale.x<=0 or scale.y<=0:_fail({"reason":"invalid_cursor_screen_scale","scale":scale});_sprite.visible=false;return
	_software_scale=Vector2.ONE/scale
	_sprite.scale=_software_scale
	_sprite.position=_pointer-Vector2(_descriptor.get("hotspot",Vector2i.ZERO))*_software_scale

func _update_visibility() -> void:
	if _headless:return
	var visible=_software_visible()
	if is_instance_valid(_sprite):_sprite.visible=visible
	if is_instance_valid(_backbuffer):_backbuffer.visible=visible

func dispose() -> void:
	# Main owns Input's custom-cursor reference. Release only our own resources;
	# the caller must clear/transfer Input's reference before application exit.
	if _disposed:return
	_disposed=true;application_enabled=false;_configured=false
	if controller.cursor_requested.is_connected(_requested):controller.cursor_requested.disconnect(_requested)
	if is_instance_valid(_sprite):
		_sprite.visible=false;_sprite.texture=null;_sprite.material=null
	if _material!=null:
		_material.set_shader_parameter("inverse_mask",null)
		_material.shader=null
	if is_instance_valid(_backbuffer):
		_backbuffer.visible=false;_backbuffer.copy_mode=BackBufferCopy.COPY_MODE_DISABLED
	if is_instance_valid(_layer):_layer.queue_free()
	_sprite=null;_material=null;_backbuffer=null;_layer=null;_viewport=null
	_textures.clear();_inverse_textures.clear();_applied_key="";_capture_depth=0

func _exit_tree() -> void:dispose()
