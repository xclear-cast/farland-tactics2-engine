class_name FT2ExpDialog
extends RefCounted
## 440730 Dialog162. Growth belongs to the caller after this dialog returns.
signal finished(accepted: bool, allocations: Array)
signal palette_scope_requested(begin: bool)
signal cursor_refresh_requested(point: Vector2i)
signal invalidated(controls: Array)
signal unsupported(details: Dictionary)
const BARS = [1104,1105,1106,1107,1111,1112,1113]
const VALUES = [1114,1115,1116,1117,1118,1119,1120]
const NAMES = [1122,1123,1124,1125,1126,1127,1128]
const PORTRAITS = [1121,1129,1130,1131,1132,1133,1134]
const FONT = {"family":"굴림","height":-12,"weight":400,"italic":false}
const WALL_REMAPS = [[90,16,208],[10,64,144],[74,16,16]]
var data
var _battle_ref: WeakRef
var _vm_ref: WeakRef
var battle:
	get: return _battle_ref.get_ref() if _battle_ref != null else null
var vm:
	get: return _vm_ref.get_ref() if _vm_ref != null else null
var active = false
var pool = 0
var scale = 0 #4620D0 survives dialog openings.
var count = 0
var experience: Array = []
var allocations: Array = []
var held = 0 # BAR control ID; lifetime differs from capture.
var captured = false
var focus = 0
var last_command = 0
var modal_guard = false
var invalidation_log: Array = []
var events: Array = []
var control_rects: Dictionary = {}
var dialog_origin = Vector2i.ZERO
var outer_rect = Rect2i()
var layout_provider: Callable
var pointer_provider: Callable
var _template: Dictionary = {}
var _captions: Dictionary = {}
var _pressed_button = 0
var _keyboard_button = 0
var _pointer = Vector2i.ZERO
var _elapsed = 0

func configure(source_data,model,scenario = null) -> void:
	data = source_data
	_battle_ref = weakref(model)
	_vm_ref = weakref(scenario) if scenario != null else null
	_template = data.read_json("data/port_ready/ui/FTO_O/dialog_162_lang1042.json")
	# Older JSON caption extraction is lossy; retained PE UTF16 is authoritative.
	var raw = FT2Content.bytes(data.resolve("data/port_ready/ui/FTO_O/dialog_162_lang1042.bin"))
	for control in _template.controls:
		var at = int(control.template_offset)+24
		if raw.decode_u16(at) == 65535: at += 4
		else:
			while raw.decode_u16(at) != 0: at += 2
			at += 2
		var end = at
		while raw.decode_u16(end) != 0: end += 2
		_captions[int(control.id)] = raw.slice(at,end).get_string_from_utf16()
	_layout()

static func muldiv(n: int,m: int,d: int) -> int:
	var a = n*m
	var q: int = (absi(a)+absi(d)/2)/absi(d)
	return -q if (a < 0) != (d < 0) else q

func _layout() -> void:
	# Actual Win95 MapDialogRect(4,8)=[7,12]; tmAveCharWidth6 is not DLU baseX.
	var size = Vector2i(muldiv(246,7,4),muldiv(195,12,8))
	outer_rect = Rect2i((Vector2i(640,480)-size-Vector2i(6,25))/2,size+Vector2i(6,25))
	dialog_origin = outer_rect.position+Vector2i(3,22)
	control_rects.clear()
	for control in _template.get("controls",[]):
		var r: Array = control.rect_dialog_units
		control_rects[int(control.id)] = Rect2i(dialog_origin+Vector2i(muldiv(int(r[0]),7,4),muldiv(int(r[1]),12,8)),Vector2i(muldiv(int(r[2]),7,4),muldiv(int(r[3]),12,8)))
	if layout_provider.is_valid():
		var supplied: Dictionary = layout_provider.call()
		dialog_origin = supplied.get("origin",dialog_origin)
		outer_rect = supplied.get("outer_rect",outer_rect)
		control_rects.merge(supplied.get("controls",{}),true)

func open(amount: int) -> bool:
	assert(battle != null)
	_layout()
	pool = battle.rules.s32(amount)
	active = false
	held = 0
	captured = false
	focus = 0 # WM_INITDIALOG itself does not SetFocus; dialog manager is external.
	count = 0
	experience.clear()
	allocations.clear()
	_elapsed = 0
	_pressed_button = 0
	_keyboard_button = 0
	events.clear()
	invalidation_log.clear()
	for unit in battle.units:
		if unit.decode_u16(0) == 0: break
		count += 1
		experience.append(unit.decode_s16(44))
		scale = maxi(scale,battle.rules.s32(unit.decode_s16(44)+pool))
	if count > 7:
		unsupported.emit({"kind":"source_dialog162_seven_control_rows_exceeded","count":count})
		return false
	if count == 0 and pool > 0:
		unsupported.emit({"kind":"source_positive_pool_zero_party_division","pool":pool})
		return false
	palette_scope_requested.emit(true)
	active = true
	message(0x111,1109) # Source synchronous default balance reentry.
	return true

func _invalidate(ids: Array) -> void:
	invalidation_log.append_array(ids)
	invalidated.emit(ids)

func remaining_pool() -> int:
	var total = 0
	for value in allocations: total = battle.rules.s32(total+int(value))
	return battle.rules.s32(pool-total)

func message(msg: int,wparam: int = 0,lparam: int = 0) -> int:
	if msg == 0x111:
		last_command = wparam&65535
		if last_command in [1108,1109]:
			allocations = battle.rules.equal_distribution(experience,pool) if last_command == 1108 else battle.rules.balanced_distribution(experience,pool)
			_invalidate([0])
			return 1
		if last_command == 1:
			for i in range(count): battle.rules.put16(battle.units[i],44,battle.units[i].decode_u16(44)+(int(allocations[i])&65535))
			active = false
			palette_scope_requested.emit(false)
			battle.changed.emit()
			finished.emit(true,allocations.duplicate())
			return 1
		if ((wparam>>16)&65535) == 6 and last_command in BARS:
			held = last_command
			captured = true
			events.append("capture")
			cursor_refresh_requested.emit(_cursor())
			events.append("same_position_cursor")
		return 0
	if msg == 0x200:
		if (wparam&1) == 0 or held == 0:
			held = 0
			return 1
		var row = BARS.find(held)
		if row < 0 or row >= count: return 1
		var r: Rect2i = control_rects[held]
		var point = dialog_origin+Vector2i(lparam&65535,(lparam>>16)&65535)-r.position
		var width = r.size.x
		if width <= 0:
			unsupported.emit({"kind":"source_drag_zero_width_division","control":held})
			return 1
		var desired = battle.rules.div0(battle.rules.s32(clampi(point.x,0,width)*scale),width)
		desired = maxi(experience[row],mini(desired,battle.rules.s32(experience[row]+pool)))-experience[row]
		if count == 1 and desired != allocations[0]:
			unsupported.emit({"kind":"source_single_party_drag_nontermination","desired":desired,"allocated":allocations[0]})
			return 1
		allocations = battle.rules.drag_distribution(experience,allocations,pool,row,point.x,width,scale)
		_invalidate(BARS.slice(0,count))
		return 1
	if msg == 0x202:
		captured = false
		events.append("release_capture")
		focus = 1109
		events.append("focus_balance")
		return 1
	if msg == 2: return 1
	if msg == 0xa1: return int(modal_guard)
	return 0 # Cancel/close/down/timer have no callback termination or commit.

func _cursor() -> Vector2i: return Vector2i(pointer_provider.call()) if pointer_provider.is_valid() else _pointer

func handle_input(event: InputEvent) -> bool:
	if not active: return false
	if event is InputEventMouseMotion:
		_pointer = Vector2i(event.position)
		var point = _pointer-dialog_origin
		message(0x200,1 if (event.button_mask&MOUSE_BUTTON_MASK_LEFT) != 0 else 0,(point.x&65535)|((point.y&65535)<<16))
		return true
	if event is InputEventMouseButton:
		_pointer = Vector2i(event.position)
		if event.button_index != MOUSE_BUTTON_LEFT: return true
		if event.pressed:
			_pressed_button = 0
			for id in BARS.slice(0,count):
				if control_rects[id].has_point(_pointer):
					message(0x111,id|(6<<16)) # Child BS_OWNERDRAW|BS_NOTIFY BN_HILITE.
					return true
			for id in [1109,1108,1]:
				if control_rects[id].has_point(_pointer):
					_pressed_button = id
					if focus!=id:_keyboard_button=0
					focus = id
		else:
			if captured: message(0x202)
			if _pressed_button != 0 and control_rects[_pressed_button].has_point(_pointer): message(0x111,_pressed_button)
			_pressed_button = 0
		return true
	if event is InputEventKey and event.keycode==KEY_SPACE:
		# Native USER BUTTON Space retains the button on keydown and sends
		# BN_CLICKED only on keyup while the same button still owns focus.
		if event.pressed:
			if not event.echo:_keyboard_button=_stock_button_focus()
		else:
			var held_button:int=_keyboard_button
			_keyboard_button=0
			if held_button!=0 and held_button==_stock_button_focus():message(0x111,held_button)
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE: message(0x111,2)
		elif event.keycode in [KEY_ENTER,KEY_KP_ENTER]: message(0x111,focus if focus in [1,1108,1109] else 1109)
		elif event.alt_pressed and event.keycode == KEY_B: message(0x111,1109)
		elif event.alt_pressed and event.keycode == KEY_E: message(0x111,1108)
		elif event.keycode == KEY_TAB:
			var order = [1109,1108,1]
			_keyboard_button=0 # Native BUTTON WM_KILLFOCUS cancels held Space.
			focus = order[posmod(order.find(focus)+(-1 if event.shift_pressed else 1),3)]
		return true
	return true

func cancel_control_capture()->void:
	_pressed_button=0
	_keyboard_button=0

func _stock_button_focus()->int:
	return focus if focus in [1109,1108,1] else (1109 if focus==0 else 0)

func advance(ms: int) -> void:
	_elapsed += ms # WM_TIMER does not synthesize held movement or mutate budgets.

func draw_item(control: int,item_action: int = 1) -> Dictionary:
	var result = {"return":1,"fills":[],"portrait":[],"text":"","value_id":0}
	if item_action != 1: return result
	var row = BARS.find(control)
	if row >= 0:
		if scale == 0:
			unsupported.emit({"kind":"source_draw_zero_scale_division","control":control})
			return result
		var size: Vector2i = control_rects[control].size
		var base = int(experience[row])
		var allocated = int(allocations[row])
		for pair in [[size.x,7],[battle.rules.div0(battle.rules.s32(battle.rules.s32(base+pool)*size.x),scale),255],[battle.rules.div0(battle.rules.s32(battle.rules.s32(base+allocated)*size.x),scale),249],[battle.rules.div0(battle.rules.s32(base*size.x),scale),250]]:
			result.fills.append({"rect":[0,0,pair[0],size.y],"color":pair[1]})
		result.text = "%5d(+%d)"%[battle.rules.s32(base+allocated),allocated] if allocated > 0 else "%5d"%base
		result.value_id = VALUES[row]
		return result
	row = PORTRAITS.find(control)
	if row >= 0:
		result.portrait = [40*row,256,40*row+40,288]
		return result
	result["return"] = 0
	return result

func _rect(out: Array[Dictionary],r: Rect2i,color: int) -> void: out.append({"op":"rect","rect":r,"color":color,"filled":true})
func _text(out: Array[Dictionary],value: String,point: Vector2i,color: int = 0,clip: Rect2i = Rect2i(0,0,640,480)) -> void: out.append({"op":"text","text":value,"raw_text":value,"pos":point,"font":FONT,"color":color,"decor":{"raw_gdi":true},"clip":clip})
func _panel(out: Array[Dictionary],r: Rect2i) -> void:
	# Same measured classic dialog border as Interface._panel, not a button bevel.
	_rect(out,r,7)
	preload("res://scripts/ui/ft2_native_widgets.gd").raised(out,Rect2i(r.position+Vector2i.ONE,r.size-Vector2i.ONE))
	for point in [Vector2i(r.end.x-2,r.position.y+1),Vector2i(r.position.x+1,r.end.y-2)]:_rect(out,Rect2i(point,Vector2i.ONE),248)
	out.append({"op":"line","from":r.end-Vector2i.ONE,"to":Vector2i(r.end.x-1,r.position.y),"color":0})
	out.append({"op":"line","from":r.end-Vector2i.ONE,"to":Vector2i(r.position.x,r.end.y-1),"color":0})

func _button_text_metrics(text:String)->Dictionary:
	if vm != null and vm.measure_text.is_valid():return vm.measure_text.call(text,FONT)
	return {"width":data.encode_cp949(text).size()*6,"ascent":10}

func _button_commands(out:Array[Dictionary],id:int,is_default:bool,focused:bool,pressed:bool)->void:
	# Interface._draw_button/_caption_text are anchored to the provided Win95
	# WM_PAINT golden windows. Use that same geometry, underline and XOR focus.
	var r:Rect2i=control_rects[id]
	preload("res://scripts/ui/ft2_native_widgets.gd").button(out,r,is_default,pressed)
	var caption:=str(_captions.get(id,""))
	var label:=caption.replace("&","")
	var metrics:=_button_text_metrics(label)
	var size:=Vector2i(int(metrics.width),-int(FONT.height))
	var point:=r.position+(r.size-size)/2+(Vector2i.ONE if pressed else Vector2i.ZERO)
	_rect(out,Rect2i(point,size),7)
	_text(out,label,point)
	var prefix:=caption.find("&")
	if prefix>=0 and prefix+1<caption.length():
		var x:=point.x+int(_button_text_metrics(caption.substr(0,prefix)).width)
		var width:=int(_button_text_metrics(caption.substr(prefix+1,1)).width)
		var y:=point.y+int(metrics.get("ascent",10))+1
		out.append({"op":"line","from":Vector2i(x,y),"to":Vector2i(x+width-1,y),"color":0})
	if focused:
		var inset:=4 if is_default else 3
		out.append({"op":"focus_rect","rect":Rect2i(r.position+Vector2i(inset,inset),r.size-Vector2i(inset*2,inset*2)),"origin":outer_rect.position})

func commands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not active: return out
	_panel(out,outer_rect)
	_rect(out,Rect2i(outer_rect.position+Vector2i(3,3),Vector2i(outer_rect.size.x-6,18)),4)
	_text(out,"경험치 배분",outer_rect.position+Vector2i(5,6),255)
	# Resource162:1109 is BS_DEFPUSHBUTTON and the first tab stop. The native
	# callback returnsTRUE from WM_INITDIALOG; USER supplies this initial focus.
	# Keep callback focus0 intact while reproducing the dialog manager's paint.
	var paint_focus:int=_stock_button_focus()
	var paint_default:int=paint_focus if paint_focus in [1109,1108,1] else 1109
	for id in [1109,1108,1]:
		var r: Rect2i = control_rects[id]
		var pressed:bool=(_pressed_button==id and r.has_point(_pointer)) or (_keyboard_button==id and id==paint_focus)
		_button_commands(out,id,id==paint_default,id==paint_focus,pressed)
	_text(out,"경험치  %d"%pool,control_rects[1110].position,0,control_rects[1110])
	for row in range(count):
		var r: Rect2i = control_rects[BARS[row]]
		var drawing = draw_item(BARS[row])
		for fill in drawing.fills:
			var source: Array = fill.rect
			var box = Rect2i(r.position,Vector2i(int(source[2]),int(source[3]))).intersection(r)
			if box.size.x > 0 and box.size.y > 0: _rect(out,box,int(fill.color))
		_text(out,drawing.text,control_rects[VALUES[row]].position,0,control_rects[VALUES[row]])
		_text(out,str(_captions.get(NAMES[row],"")),control_rects[NAMES[row]].position,0,control_rects[NAMES[row]])
		#41AD38 sets the surface color key to5. Callback argument1 is KEYSRC flag.
		out.append({"op":"bitmap","key":"BMP/WALL.BMP","pos":control_rects[PORTRAITS[row]].position,"source":Rect2i(40*row,256,40,32),"transparent":5,"remaps":WALL_REMAPS,"palette_install":[[144,64],[16,16]]})
	return out
