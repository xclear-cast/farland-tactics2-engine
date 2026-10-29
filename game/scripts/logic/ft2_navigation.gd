class_name FT2Navigation
extends RefCounted
const DIRS = [Vector2i(0,1),Vector2i(1,0),Vector2i(-1,0),Vector2i(0,-1)]
const BLOCKED = [1,3,4,5,8,9]
var rules
var units: Array = []
var cells: Dictionary = {}
var base = Vector2i.ZERO
var canvas = Vector2i(640,480)
var map_mode = 1
var actor_slot = -1
var origin = Vector2i.ZERO
var grid: Dictionary = {}

func _init(rule_set = null) -> void:
	rules = rule_set

func configure(source_units: Array, map_data: Dictionary, mode: int = 1) -> void:
	units = source_units
	map_mode = mode
	cells.clear()
	for c in map_data.get("cells",[]):
		cells[Vector2i(int(c.x),int(c.y))] = [int(c.H),int(c.flag2_raw),int(c.flag3_raw),int(c.L),int(c.part_count)]
	var bounds = map_data.get("header_map_bounds_ltrb",[0,0,10,10])
	base = Vector2i((int(bounds[1])-int(bounds[0]))*32,-(int(bounds[1])+int(bounds[0]))*16)
	canvas = Vector2i(maxi(640,(int(bounds[2])-int(bounds[3])-int(bounds[0])+int(bounds[1]))*32),maxi(480,(int(bounds[3])-int(bounds[1])-int(bounds[0])+int(bounds[2]))*16))

func cell(point: Vector2i) -> Variant: return cells.get(point)
func height(point: Vector2i) -> int: return int(cells.get(point,[0])[0])
func project(point: Vector2i) -> Vector2i: return Vector2i((point.x-point.y)*32+base.x,(point.x+point.y)*16+base.y-height(point)*8)
func inside(point: Vector2i) -> bool:
	var c = cell(point)
	if c == null or c[1] != 0: return false
	var p = project(point)
	return p.x >= 16 and p.y >= 8 and p.x < canvas.x-16 and p.y < canvas.y-8

func occupant(point: Vector2i) -> int:
	for i in range(units.size()):
		var u: PackedByteArray = units[i]
		if u.decode_u16(0) != 0 and (u.decode_u16(16) != 9 or u.decode_u16(0) == 8) and rules.xy(u) == point: return i
	return -1

func iterator(point: Vector2i, minimum: int, maximum: int) -> Array:
	var out: Array = []
	for i in range(units.size()):
		var u: PackedByteArray = units[i]
		if u.decode_u16(0) == 0 or (u.decode_u16(16) == 9 and u.decode_u16(0) != 8): continue
		var distance = manhattan(point,rules.xy(u))
		if distance >= minimum and distance <= maximum: out.append(i)
	return out

static func manhattan(a: Vector2i,b: Vector2i) -> int: return absi(a.x-b.x)+absi(a.y-b.y)
static func facing(a: Vector2i,b: Vector2i) -> int:
	var d = b-a
	return (1 if d.x >= 0 else 2) if absi(d.y) < absi(d.x) else (0 if d.y >= 0 else 3)

func floating(slot: int) -> bool:
	var u: PackedByteArray = units[slot]
	return map_mode == 1 and (rules.races.decode_u16(u.decode_u16(2)*86+62) != 99 or u.decode_u16(16) == 11 or rules.has_ability(u,11))

func limits(slot: int) -> Vector2i:
	if floating(slot): return Vector2i(99,99)
	var off = units[slot].decode_u16(2)*86
	return Vector2i(rules.races.decode_u16(off+58),rules.races.decode_u16(off+60))

func cost(slot: int,point: Vector2i) -> int:
	var c = cell(point)
	if c == null: return 99
	var u: PackedByteArray = units[slot]
	var terrain = 0 if c[2] != 0 else c[3]
	var other = occupant(point)
	if other >= 0 and units[other].decode_u16(18) != 7: terrain = 0
	var value = rules.races.decode_u16(u.decode_u16(2)*86+62+terrain*2)
	if terrain == 0 and rules.has_ability(u,11): value = rules.races.decode_u16(u.decode_u16(2)*86+64)
	if rules.has_ability(u,10): value -= 1
	return 99 if c[1] != 0 else value

func zoc(slot: int,point: Vector2i) -> bool:
	if floating(slot): return false
	for delta in DIRS:
		var p = point+delta
		var other = occupant(p)
		if not inside(p) or other < 0: continue
		var u: PackedByteArray = units[other]
		if u.decode_u16(18) != 7 and absi(height(point)-height(p)) < 8 and not u.decode_u16(16) in BLOCKED and rules.hostile(units[slot],u,slot == other): return true
	return false

func movement_grid(slot: int, old_area_present: bool = false) -> Dictionary:
	actor_slot = slot
	origin = rules.xy(units[slot])
	grid.clear()
	grid[Vector2i.ZERO] = 30
	var u: PackedByteArray = units[slot]
	if not old_area_present and u.decode_u16(18) != 3 and u.decode_s32(92) == 0 and not u.decode_u16(16) in BLOCKED: _flood(origin)
	return grid.duplicate()

func _flood(point: Vector2i) -> void:
	var score = grid.get(point-origin,0)
	if score != 30 and zoc(actor_slot,point):
		grid[point-origin] = 1
		return
	var edge = limits(actor_slot)
	for delta in DIRS:
		var p = point+delta
		var offset = p-origin
		if not inside(p) or absi(offset.x) > 10 or absi(offset.y) > 10: continue
		if height(p)-height(point) > edge.x or height(point)-height(p) > edge.y: continue
		var value = score-cost(actor_slot,p)
		if grid.get(offset,0) >= value: continue
		value = maxi(1,value)
		grid[offset] = value&65535
		if value > 1: _flood(p)

func path_to(destination: Vector2i) -> Array:
	var point = destination
	var reverse: Array = []
	var previous = 4
	var edge = limits(actor_slot)
	while point != origin:
		var best = 4
		var score = grid.get(point-origin,0)
		for d in range(4):
			var p = point+DIRS[d]
			var offset = p-origin
			if cell(p) == null or absi(offset.x) > 10 or absi(offset.y) > 10: continue
			if height(point)-height(p) > edge.x or height(p)-height(point) > edge.y: continue
			var value = grid.get(offset,0)
			if value > score or (value == score and d == previous):
				best = d
				score = value
		if best == 4: return []
		reverse.append(best^3)
		point += DIRS[best]
		previous = best
		if reverse.size() > 30: return []
	reverse.reverse()
	return reverse

func selectable(point: Vector2i, mask: Dictionary = {}) -> bool:
	var c = cell(point)
	var offset = point-origin
	if c == null or c[1] != 0 or c[2] != 0 or absi(offset.x) > 10 or absi(offset.y) > 10: return false
	if mask.get(offset,0) in [1,2]: return true
	var other = occupant(point)
	return grid.get(offset,0) > 0 and (other < 0 or other == actor_slot or units[other].decode_u16(18) == 7 or units[other].decode_u16(0) == 8)

func selection_mask(slot: int,action: int) -> Dictionary:
	var out: Dictionary = {}
	var u: PackedByteArray = units[slot]
	var start = rules.xy(u)
	if action == 0:
		var off = u.decode_u16(20)*56
		var minimum = rules.items.decode_u16(off+42)
		var maximum = rules.items.decode_u16(off+44)
		var shape = rules.items.decode_u16(off+50)
		for other in iterator(start,minimum,maximum):
			if not rules.hostile(u,units[other],slot == other): continue
			var p = rules.xy(units[other])
			if shape != 3 and absi(height(start)-height(p)) > 4: return out
			if shape == 1 and start.x != p.x and start.y != p.y: continue
			out[p-start] = 1
		return out
	var item = action >= rules.magics.size()/64
	var table: PackedByteArray = rules.items if item else rules.magics
	var off = (action-1000)*56 if item else action*64
	var minimum = table.decode_u16(off+(42 if item else 30))
	var maximum = table.decode_u16(off+(44 if item else 32))
	var shape = 0 if item else table.decode_u16(off+50)
	var flag = 2 if item or table.decode_u16(off+48) == 1 else 1
	if item:
		for i in range(10):
			var p = rules.xy(units[i])
			if units[i].decode_u16(0) != 0 and manhattan(start,p) >= minimum and manhattan(start,p) <= maximum: out[p-start] = 2
	elif shape in [0,1,3]:
		for y in range(-10,11):
			for x in range(-10,11):
				var delta = Vector2i(x,y)
				var c = cell(start+delta)
				if c != null and c[1] == 0 and absi(x)+absi(y) >= minimum and absi(x)+absi(y) <= maximum: out[delta] = flag
	elif shape in [2,5]:
		for d in range(4):
			var p = start
			for n in range(1,maximum):
				var next = p+DIRS[d]
				if not inside(next): break
				if action == 60 and (cell(next)[2] != 0 or height(next) != height(p)): break
				if action == 62 and (cell(next)[2] != 0 or height(next) > height(p)): break
				p = next
				if n >= minimum: out[p-start] = flag
	return out

func collect_targets(slot: int,clicked: Vector2i,action: int) -> Dictionary:
	var u: PackedByteArray = units[slot]
	var start = rules.xy(u)
	var direction = u.decode_u16(6) if clicked == start else facing(start,clicked)
	rules.put16(u,6,direction)
	units[slot] = u
	var records: Array = []
	var marked: Dictionary = {}
	var center = clicked
	if action >= rules.magics.size()/64:
		records.append({"target_slot":occupant(clicked),"origin":Vector2i.ZERO})
	elif action == 0:
		var off = u.decode_u16(20)*56
		var shape = rules.items.decode_u16(off+50)
		var minimum = rules.items.decode_u16(off+42)
		var maximum = rules.items.decode_u16(off+44)
		if shape in [0,3]: records.append({"target_slot":occupant(clicked),"origin":start})
		elif shape == 1:
			for n in range(1,maximum+1):
				var p = start+DIRS[direction]*n
				if n < minimum: continue
				var other = occupant(p)
				if absi(height(start)-height(p)) > 4 or (other >= 0 and (units[other].decode_u16(16) == 1 or units[other].decode_u16(18) == 7)): other = -1
				records.append({"target_slot":other,"origin":start})
		elif shape == 2:
			for d in [[2,0,1],[3,1,0],[0,2,3],[1,3,2]][direction]:
				var p = start+DIRS[d]
				var other = occupant(p)
				if absi(height(start)-height(p)) > 4 or (other >= 0 and (units[other].decode_u16(16) == 1 or units[other].decode_u16(18) == 7)): other = -1
				records.append({"target_slot":other,"origin":start})
	else:
		var off = action*64
		var shape = rules.magics.decode_u16(off+50)
		var side = rules.magics.decode_u16(off+48)
		var minimum = rules.magics.decode_u16(off+30)
		var maximum = rules.magics.decode_u16(off+32)
		if shape == 2:
			var p = start
			for n in range(1,maximum+1):
				var next = p+DIRS[direction]
				if not inside(next): break
				if n == 1: center = next
				if action == 60 and (cell(next)[2] != 0 or height(next) != height(p)): break
				if action == 62 and height(next) > height(start): break
				if action == 77 and (cell(next)[2] != 0 or height(next) > height(p)): break
				p = next
				if n < minimum: continue
				marked[p-start] = 1
				var other = occupant(p)
				if other >= 0 and (units[other].decode_u16(16) == 1 or units[other].decode_u16(18) == 7 or (side != 2 and rules.hostile(u,units[other],slot == other) != (side == 0))): other = -1
				records.append({"target_slot":other,"origin":start})
				if action == 62 and other >= 0:
					if height(start)-height(p) <= 4: break
					records[-1].target_slot = -1
			if action == 62 and not records.any(func(r):return r.target_slot >= 0): records.clear()
		else:
			var low = 0
			var high = 0
			if shape in [3,5]:
				center = start
				low = minimum
				high = maximum
			elif shape == 1:
				var delta = u.decode_u16(4)-rules.magics.decode_u16(off+20)
				high = 0 if delta < 10 else 1 if delta < 20 else 2
			elif shape == 4: high = 9999
			if shape != 4:
				for y in range(-10,11):
					for x in range(-10,11):
						var d = Vector2i(x,y)
						var distance = absi(x)+absi(y)
						if distance <= high and (shape != 5 or ((x == 0 if direction in [0,3] else y == 0) and distance >= low)): marked[d] = 1
			for other in range(units.size()):
				var target: PackedByteArray = units[other]
				if target.decode_u16(0) == 0 or target.decode_u16(18) == 7: continue
				if side != 2 and rules.hostile(u,target,slot == other) != (side == 0): continue
				var p = rules.xy(target)
				var distance = manhattan(center,p)
				if distance < low or distance > high: continue
				if shape == 5 and ((center.x != p.x and center.y != p.y) or not facing(center,p) in [direction,direction^3]): continue
				if action in [41,64]:
					if target.decode_u16(16) != 1: continue
				elif target.decode_u16(16) == 1: continue
				records.append({"target_slot":other,"origin":Vector2i.ZERO})
		if action in [55,81]: records.append({"target_slot":slot,"origin":start})
	return {"records":records,"mask":marked,"center":center,"direction":direction}
