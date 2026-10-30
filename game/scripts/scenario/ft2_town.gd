class_name FT2Town
extends RefCounted
var _vm_ref: WeakRef
var vm:
	get: return _vm_ref.get_ref()
var data
var rows: Array = []
var enabled: Array[int] = []
var markers: Array[int] = []
var display_markers := 0
var mode2 := 0
var mode3 := 0
var extra_overlay := 0
var counter := 0
var pulse := 0
var hover := -1
var suppressed := false
var last_tick := 0
var cached_stems: Array[String] = []

func _init(owner, store) -> void:
	_vm_ref = weakref(owner); data = store
	rows = data.read_json("data/port_ready/analysis_completion/town/source_evidence.json").static_table.rows
	enabled.resize(20); enabled.fill(0); markers.resize(20); markers.fill(0)

func restore(tail: PackedByteArray) -> void:
	if tail.size() < 180: return
	display_markers = tail.decode_u32(4)
	for i in 20:
		markers[i] = tail.decode_u32(8+i*4); enabled[i] = tail.decode_u32(88+i*4)
	mode2 = tail.decode_u32(168); extra_overlay = tail.decode_u32(172); mode3 = tail.decode_u32(176)
	get_control_mode(0)

func snapshot() -> PackedByteArray:
	var bytes := PackedByteArray(); bytes.resize(180); bytes.fill(0)
	bytes.encode_u32(0,180)
	bytes.encode_u32(4,display_markers & 0xFFFFFFFF)
	for i in 20:
		bytes.encode_u32(8+i*4,markers[i]&0xFFFFFFFF); bytes.encode_u32(88+i*4,enabled[i]&0xFFFFFFFF)
	bytes.encode_u32(168,mode2&0xFFFFFFFF); bytes.encode_u32(172,extra_overlay&0xFFFFFFFF); bytes.encode_u32(176,mode3&0xFFFFFFFF)
	return bytes

func set_flag(index: int, value: int) -> void:
	if index >= 0 and index < 20: enabled[index] = value
	elif index == 20: mode2 = value
	elif index == 21: extra_overlay = value
	elif index == 22: mode3 = value

func get_control_mode(value: int) -> int:
	if value != 0:
		mode3 = int(value == 3); mode2 = int(value == 2)
	counter = 0; pulse = 0
	return 3 if mode3 != 0 else (2 if (mode2 & 0xFFFFFFFF) >= 1 else 1)

func enter() -> void:
	# Five caches are populated only when absent; setters do not invalidate them.
	if vm.current_event <= 0: return
	var count := 5 if mode2 != 0 and extra_overlay != 0 else 4
	var base := 20 if mode3 != 0 else (10 if (mode2 & 0xFFFFFFFF) >= 1 else 0)
	while cached_stems.size() < count:
		var slot := cached_stems.size()
		cached_stems.append("TOWN%02d" % (base+slot))
		#44247B remaps every cached bitmap;44248C copies only slot0 to BASE.
		#The caller's palette service owns realization, not each repeated draw.
		if slot == 0: vm.palette_requested.emit({"kind":"copy_bitmap_base","key":"BMP/"+cached_stems[0]+".BMP","remaps":[[10,112,32]],"start":32,"count":112})

func hide() -> void:
	#442370(0) calls41AB80 before releasing Town bitmaps. It does not419790/recreate A poses.
	vm.actor_sprites.clear();vm.actor_busy.clear();vm.actor_cache_generation+=1;vm.actor_cache_mode=-1;vm._emit_actor_state()
	cached_stems.clear()

func advance(tick: int) -> void:
	if not cached_stems.is_empty() and ((tick-last_tick)&0xFFFFFFFF) <= 50: return
	last_tick = tick; counter = (counter+1)%15; pulse = (pulse+1)%30
	if pulse == 2 or pulse == 4: pulse += 1
	enter()

func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var point := Vector2i(event.position)
		var selected := -1
		for row in rows:
			var index := int(row.index)
			var rect: Array = row.hit_rect
			var inside := point.x >= int(rect[0]) and point.y >= int(rect[1]) and point.x < int(rect[2]) and point.y < int(rect[3])
			if enabled[index] != 0 and inside:
				markers[index] = int(selected < 0)
				if selected < 0: selected = index
			else: markers[index] = enabled[index] & display_markers
		hover = selected
		return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			hover = -1; suppressed = true
			vm.ui_requested.emit({"kind":"town_menu","rows":available_places()})
			return true
		if event.button_index == MOUSE_BUTTON_LEFT:
			if suppressed: suppressed = false; return true
			if hover >= 0: select_place(hover)
			else: toggle_markers()
			return true
	return false

func toggle_markers() -> void:
	display_markers = int((display_markers & 0xFFFFFFFF) < 1)
	for i in rows.size(): markers[i] = enabled[i] & display_markers

func available_places() -> Array:
	var out: Array = []
	for row in rows:
		if enabled[int(row.index)] != 0: out.append(row)
	return out

func select_place(index: int) -> bool:
	if index < 0 or index >= rows.size(): return false
	for i in rows.size(): markers[i] = 0
	hide(); vm.mode = 1
	var label := str(rows[index].label)
	if vm.start(vm.current_event,label): return true
	return vm.start(0,label)

func commands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cached_stems.is_empty(): return out
	out.append({"op":"bitmap","key":"BMP/"+cached_stems[0]+".BMP","pos":Vector2i.ZERO,"town_remap":true,"transparent":-1})
	var n := int(counter/3)
	if cached_stems.size() > 1:
		out.append({"op":"bitmap","key":"BMP/"+cached_stems[1]+".BMP","pos":Vector2i(528,0),"source":Rect2i(int(n/3)*112,(n%3)*64,112,64),"town_remap":true,"transparent":0})
	if cached_stems.size() > 2:
		out.append({"op":"bitmap","key":"BMP/"+cached_stems[2]+".BMP","pos":Vector2i(352,320),"source":Rect2i(int(n/3)*288,(n%3)*160,288,160),"town_remap":true,"transparent":0})
	if cached_stems.size() > 4:
		var b := 0 if pulse >= 11 else 5-absi(pulse-5)
		out.append({"op":"bitmap","key":"BMP/"+cached_stems[4]+".BMP","pos":Vector2i(496,160),"source":Rect2i((b%3)*128,int(b/3)*128,128,128),"town_remap":true,"transparent":0})
	if cached_stems.size() > 3:
		for row in rows:
			if markers[int(row.index)] == 0: continue
			var r: Array = row.marker_rect
			out.append({"op":"bitmap","key":"BMP/"+cached_stems[3]+".BMP","pos":Vector2i(int(r[0]),int(r[1])),"source":Rect2i(int(r[0]),int(r[1]),int(r[2])-int(r[0]),int(r[3])-int(r[1])),"town_remap":true,"transparent":0})
	#4424C6 samples cached surface(0,8) AFTER42FEC0's index conversion.
	for command in out:
		command.erase("town_remap")
		command["remaps"] = [[10,112,32]]
		if int(command.get("transparent",-1)) >= 0: command["transparent_at"] = Vector2i(0,8)
	return out
