class_name FT2AI
extends RefCounted
const TERRAIN = [0,10,15,20,40,15,20,10]
const BLOCKED = [1,3,4,5,8,9]
var nav
var rules
var nearby_distance = 4

func _init(navigation = null, rule_set = null) -> void:
	nav = navigation
	rules = rule_set

static func word(value: int) -> int: return ((value+32768)&65535)-32768

func _template(skill: int) -> int:
	return FT2Content.active.extensions.numeric_skill(skill) if FT2Content.active!=null and FT2Content.active.extensions!=null else skill

func utility(actor_slot: int, skill: int, mode: int, side: int, center: Vector2i, minimum: int, maximum: int) -> int:
	skill=_template(skill)
	var a: PackedByteArray = nav.units[actor_slot]
	var score = 0
	for slot in nav.iterator(center,minimum,maximum):
		var b: PackedByteArray = nav.units[slot]
		var enemy = rules.hostile(a,b,actor_slot == slot)
		var state = b.decode_u16(16)
		var control = b.decode_u16(18)
		if (state == 1 or control == 7) and side != 2 and enemy != (side < 1): continue
		if skill in [13,45]:
			if not enemy and state != 0 and state >= 2 and state <= 8 and state != 6: score = {2:60,3:50,4:80,5:70,7:80,8:60}[state]
			if score > 0 and rules.xy(b) == center: score += 1
		elif skill in [32,40]:
			if not enemy and state != 1 and control != 7 and b.decode_s16(36) > b.decode_s16(38): score += rules.div0(rules.s32((b.decode_s16(36)-b.decode_s16(38))*100),b.decode_s16(36))
			if score > 0 and rules.xy(b) == center: score += 1
		elif skill == 41:
			if not enemy and (state == 1 or control == 7): score = 100
		elif skill in [55,81]:
			if a.decode_s16(36) > a.decode_s16(38) and state != 1 and control != 7 and enemy: score += a.decode_s16(36)-a.decode_s16(38)-rules.div0(b.decode_s16(52),10)
		elif enemy:
			score += 50 if mode == 6 else 30
			if rules.xy(b) == center: score += 1
			if state == {5:8,11:8,12:8,24:3,50:2,52:7,78:5}.get(skill,-1): score -= 20
		else: score -= 10 if mode == 6 else 20
		score = rules.s32(score)
	return score

func decision(actor_slot: int) -> Dictionary:
	var units: Array = nav.units
	var a: PackedByteArray = units[actor_slot]
	var origin = rules.xy(a)
	var mode = a.decode_u16(18)
	if mode == 0: mode = 4
	if mode != 6 and (a.decode_s32(96) != 0 or a.decode_u16(16) in BLOCKED): mode = 5
	nav.movement_grid(actor_slot)
	var scores: Dictionary = {}
	var aggregate: Array = []
	var weapon = a.decode_u16(20)*56
	var minimum = rules.items.decode_u16(weapon+42)
	var maximum = rules.items.decode_u16(weapon+44)
	var weapon_shape = rules.items.decode_u16(weapon+50)
	for dy in range(-10,11):
		for dx in range(-10,11):
			var offset = Vector2i(dx,dy)
			var point = origin+offset
			var r = [0,0,0,0,0,0,0]
			scores[offset] = r
			var c = nav.cell(point)
			var occupant = nav.occupant(point)
			if not nav.selectable(point) or (occupant >= 0 and occupant != actor_slot):
				r[0] = -9999
				continue
			if a.decode_s32(92) != 0 or a.decode_u16(16) in BLOCKED:
				if dx != 0 or dy != 0: continue
			var nearby = nav.iterator(point,1,nearby_distance)
			var active: Array = []
			for slot in nearby:
				if rules.hostile(a,units[slot],actor_slot == slot) and not units[slot].decode_u16(16) in BLOCKED: active.append(slot)
			if dx == 0 and dy == 0 and mode in [2,5]:
				r[0] = 10
				if mode == 5:
					for slot in nearby:
						if rules.hostile(units[slot],a,slot == actor_slot) and not units[slot].decode_u16(16) in BLOCKED: r[0] = 0
			r[0] = word(r[0]+rules.div0(TERRAIN[c[3]],5 if mode == 5 else 10))
			var n = 0 if mode == 6 else active.size()
			for j in range(n): r[0] = word(r[0]-rules.div0(3*j,2))
			if mode == 5 or n == 0:
				var nearest = 999
				for slot in range(units.size()):
					var b: PackedByteArray = units[slot]
					if slot != actor_slot and b.decode_u16(0) != 0 and not b.decode_u16(16) in [1,9] and b.decode_u16(18) != 7 and rules.hostile(a,b): nearest = mini(nearest,nav.manhattan(point,rules.xy(b)))
				if mode == 6: nearest *= 2
				r[0] = word(r[0]+(nearest if mode == 5 else nearby_distance-nearest))
			if a.decode_s32(96) == 0 and not a.decode_u16(16) in BLOCKED:
				for slot in nav.iterator(point,minimum,maximum):
					var b: PackedByteArray = units[slot]
					if not rules.hostile(a,b,slot == actor_slot) or b.decode_u16(16) == 1 or b.decode_u16(18) == 7: continue
					var bxy = rules.xy(b)
					if weapon_shape != 3 and absi(nav.height(point)-nav.height(bxy)) > 4: continue
					if weapon_shape == 1 and point.x != bxy.x and point.y != bxy.y: continue
					var weight = 5 if mode == 5 else 40 if mode == 6 else 20
					if mode == 2 and offset == Vector2i.ZERO:
						weight += 10
						r[0] = 0
					var direction = nav.facing(point,bxy)
					var bonus = 8 if direction == b.decode_u16(6) else 0 if (direction^3) == b.decode_u16(6) else 4
					if b.decode_u16(16) == 7: weight = 5
					if mode == 5: bonus = rules.div0(bonus,4)
					if a.decode_u16(18) == 0 and ((bxy.x == point.x and origin.x == point.x) or (bxy.y == point.y and origin.y == point.y)) and absi(dx)+absi(dy) >= 3: bonus += 40
					var value = weight+bonus
					var index = -1
					for k in range(aggregate.size()):
						if aggregate[k][3] == slot:
							index = k
							break
					if index < 0:
						index = aggregate.size()
						aggregate.append([0,0,0,slot])
					if aggregate[index][2] < value: aggregate[index] = [point.x,point.y,value,slot]
					if r[1] < value:
						r[1] = word(value)
						r[4] = index+1
			for skill_slot in range(10):
				var skill = a.decode_u16(56+2*skill_slot)
				var template:=_template(skill)
				if skill == 0 or a.decode_s32(96) != 0 or a.decode_u16(16) in [1,3,4,5,6,8,9]: continue
				var off = skill*64
				var shape = rules.magics.decode_u16(off+50)
				var side = rules.magics.decode_u16(off+48)
				var low = rules.magics.decode_u16(off+30)
				var high = rules.magics.decode_u16(off+32)
				if absi(rules.magics.decode_s16(off+22)) > a.decode_s16(42) or template == 31 or shape > 4: continue
				if shape == 2:
					if template == 62: continue
					var buckets = [0,0,0,0,0]
					var targets: Dictionary = {}
					for slot in nav.iterator(point,low,high):
						var b: PackedByteArray = units[slot]
						var enemy = rules.hostile(a,b,slot == actor_slot)
						if b.decode_u16(16) == 1 or b.decode_u16(18) == 7 or slot == actor_slot or (side != 2 and enemy != (side < 1)): continue
						var bxy = rules.xy(b)
						if point.x != bxy.x and point.y != bxy.y: continue
						var direction = nav.facing(point,bxy)
						if enemy:
							if template == 77:
								var p = point
								var valid = true
								for ignored in range(nav.manhattan(point,bxy)):
									var next = p+nav.DIRS[direction]
									if not nav.inside(next) or nav.height(next) > nav.height(p):
										valid = false
										break
									p = next
								if not valid: continue
							buckets[direction] += 40 if mode == 6 else 20
							if b.decode_u16(16) == {72:5,73:2,74:8,75:4}.get(template,-1): buckets[direction] -= 20
						else: buckets[direction] -= 40
						targets[direction] = bxy
					var best = 4
					for d in range(4):
						if buckets[d] > buckets[best]: best = d
					if best != 4 and r[2] < buckets[best]:
						r[2] = word(buckets[best])
						r[3] = skill
						r[5] = targets[best].x
						r[6] = targets[best].y
					continue
				var centers: Array = []
				if shape in [0,1]:
					var radius = 0 if shape == 0 else maxi(0,mini(2,rules.div0(a.decode_u16(4)-rules.magics.decode_u16(off+20),10)))
					for y in range(point.y-high,point.y+high+1):
						for x in range(point.x-high,point.x+high+1):
							var center = Vector2i(x,y)
							var distance = nav.manhattan(point,center)
							if distance >= low and distance <= high: centers.append([center,0,radius])
				elif shape == 3: centers.append([point,low,high])
				else: centers.append([point,0,9999])
				for entry in centers:
					var center: Vector2i = entry[0]
					var center_cell = nav.cell(center)
					if center_cell == null or center_cell[1] != 0: continue
					var value = utility(actor_slot,skill,mode,side,center,entry[1],entry[2])
					if value > 0 and offset == Vector2i.ZERO: value += 5
					value -= skill_slot*10
					if r[2] < value:
						r[2] = word(value)
						r[3] = skill
						r[5] = center.x
						r[6] = center.y
	for row in aggregate:
		var offset = Vector2i(row[0],row[1])-origin
		if scores[offset][1] < row[2]: scores[offset][1] = word(row[2])
	var best = -9999
	var distance = 999
	var chosen = origin
	for dy in range(-10,11):
		for dx in range(-10,11):
			var offset = Vector2i(dx,dy)
			var r: Array = scores[offset]
			r[0] = word(r[0]+maxi(r[1],r[2]))
			var d = absi(dx)+absi(dy)
			if r[0] != -9999 and (r[0] > best or (r[0] == best and d < distance)):
				best = r[0]
				distance = d
				chosen = origin+offset
	var record: Array = scores[chosen-origin]
	var action = record[3] if record[3] != 0 and record[2] > record[1] else 0
	var target = Vector2i(record[5],record[6]) if action != 0 else origin
	if action == 0 and record[4] > 0: target = rules.xy(units[aggregate[record[4]-1][3]])
	return {"position":chosen,"scores":scores,"aggregate":aggregate,"action_id":action,"target":target,"physical_index":record[4],"has_action":action != 0 or record[4] > 0}
