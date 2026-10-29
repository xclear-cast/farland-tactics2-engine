class_name FT2Numeric
extends "ft2_rules.gd"
# Original per-target numeric rules. No animations or asynchronous shared state.
var a: PackedByteArray
var t: PackedByteArray
var seeds: Array
var rec: Dictionary
var attack_origin: Vector2i
const INCAP = [1, 4, 5, 3, 8, 9]

func equipment(u: PackedByteArray) -> Array:
	return [u.decode_u16(0x14), u.decode_u16(0x16), u.decode_u16(0x18), u.decode_u16(0x1a)]

func effective(u: PackedByteArray, index: int) -> int:
	var value: int = u.decode_s16(0x2e + index * 2) + u.decode_s16(0x4c + index * 2)
	var slots: Array = [0, 2, 3] if index == 0 else [1, 2, 3] if index == 1 else [0, 1, 2, 3]
	var ids: Array = equipment(u)
	for k in slots: value += items.decode_s16(int(ids[k]) * 56 + 0x1a + index * 2)
	return value

func attributes(u: PackedByteArray) -> Array:
	var values: Array = []
	for j in range(3):
		var value: int = races.decode_s16(u.decode_u16(2) * 86 + 0x32 + 2 * j) + u.decode_s16(0x56 + 2 * j)
		for identity in equipment(u): value += items.decode_s16(int(identity) * 56 + 0x24 + 2 * j)
		values.append(value)
	return values

func chance(input_scale: int, is_status: bool = true, reverse: bool = false) -> bool:
	var first: PackedByteArray = t if reverse else a
	var second: PackedByteArray = a if reverse else t
	var threshold: int
	if is_status:
		var scale: int = maxi(1, s32(input_scale))
		if second.decode_u16(0x10) in INCAP: scale = s32(scale * 3)
		elif first.decode_u16(6) == second.decode_u16(6): scale = s32(scale * 2)
		elif first.decode_u16(6) != (second.decode_u16(6) ^ 3): scale = s32(scale + div0(scale, 2))
		var numerator: int = effective(first, 2) + effective(first, 4)
		var denominator: int = effective(second, 3) + effective(second, 4)
		threshold = maxi(1, div0(s32(numerator * scale), denominator if denominator != 0 else 1))
	else: threshold = chance_threshold(first, second, input_scale)
	return roll() < threshold

func roll() -> int:
	var step: Dictionary = rng_step(seeds, 100)
	seeds = step.seeds
	return int(step.value)

func put_state(value: int, counter: int = 100) -> void:
	put16(t, 0x10, value)
	t.encode_s32(0x68, counter)

func no_effect() -> void: rec.amount = 90006
func message() -> void: rec.amount = 90000
func done() -> Dictionary: return {"actor": a, "target": t, "result": rec, "seeds": seeds}

static func direction(x1: int, y1: int, x2: int, y2: int) -> int:
	var dx: int = x2 - x1
	var dy: int = y2 - y1
	return (0 if dy >= 0 else 3) if absi(dy) >= absi(dx) else (1 if dx >= 0 else 2)

func deal_damage(action: int, height_delta: int) -> void:
	var base: int
	if action == 0:
		base = maxi(1, effective(a, 0) - effective(t, 1))
		if t.decode_u16(0x10) == 3: put16(t, 0x10, 0)
		if a.decode_s32(0x64) == 0:
			if chance(3, false): rec.critical = 1
			if not (t.decode_u16(0x10) in INCAP) and chance(3, false, true):
				rec.critical = 0
				no_effect()
				put16(t, 6, direction(t.decode_s32(8), t.decode_s32(12), attack_origin.x, attack_origin.y))
				return
	else:
		var cursor: int = action * 64 + 0x18
		while magics.decode_s16(cursor) == 0: cursor += 2
		var power: int = absi(magics.decode_s16(cursor))
		base = maxi(1, (effective(a, 2) - effective(t, 3) if magics.decode_s16(action * 64 + 0x16) > 0 else effective(a, 0) - effective(t, 1)) + power)
	rec.damage_flag = 1
	var av: Array = attributes(a)
	var tv: Array = attributes(t)
	var selected: int = -1
	var best: int = -1
	for j in range(3):
		var total: int = int(av[j])
		var race: int = races.decode_s16(a.decode_u16(2) * 86 + 0x32 + 2 * j)
		var source: int = items.decode_s16(a.decode_u16(0x14) * 56 + 0x24 + 2 * j) if action == 0 else magics.decode_s16(action * 64 + 0x18 + 2 * j)
		if total != 0 and int(tv[j]) != 0 and (signi(total) == signi(race) or signi(total) == signi(source)):
			var difference: int = absi(total - int(tv[j]))
			if difference > best:
				best = difference
				selected = j
	if selected >= 0:
		var first: int = int(av[selected])
		var second: int = int(tv[selected])
		var percent: int = 100 - div0(absi(second) - absi(first) + 100, 4) if (first < 0) == (second < 0) else 100 + div0(absi(second - first), 2)
		base = maxi(1, div0(s32(base * percent), 100))
	if action == 0:
		if t.decode_u16(0x12) == 0 or t.decode_u16(0) == 8:
			var weapon_state: int = items.decode_u16(a.decode_u16(0x14) * 56 + 0x34)
			if weapon_state != 0 and chance(20, false):
				var allowed: bool = not (t.decode_u16(0x10) in INCAP)
				if weapon_state in [5, 8]: allowed = allowed or t.decode_u16(0x10) == 3
				if weapon_state == 4: allowed = allowed or t.decode_u16(0x10) in [3, 8]
				if weapon_state >= 2 and weapon_state <= 8 and allowed: rec.pending_state = weapon_state
		var attack_dir: int = direction(attack_origin.x, attack_origin.y, t.decode_s32(8), t.decode_s32(12))
		var facing: int = t.decode_u16(6)
		var facing_add: int = 25 if attack_dir == facing else 0 if attack_dir == (facing ^ 3) else 15
		var percent: int = (300 if a.decode_s32(0x64) != 0 else 100) + (80 if rec.critical != 0 else 0) + facing_add + 2 * height_delta
		base = maxi(1, div0(s32(base * percent), 100))
	rec.amount = mini(t.decode_s16(0x26), base)
	put16(t, 0x26, t.decode_s16(0x26) - int(rec.amount))
	if t.decode_s16(0x26) == 0: put16(t, 0x10, 1)

func apply_numeric(actor: PackedByteArray, target: PackedByteArray, action: int, input_seeds: Array, target_slot: int = 17, same_unit: bool = false, first_result: int = 0, map_mode: int = 0, height_delta: int = 0, origin: Array = [], initial_critical: int = 0) -> Dictionary:
	a = actor.duplicate()
	t = a if same_unit else target.duplicate()
	attack_origin = Vector2i(a.decode_s32(8), a.decode_s32(12)) if origin.is_empty() else Vector2i(int(origin[0]), int(origin[1]))
	seeds = input_seeds.duplicate()
	rec = {"damage_flag": 0, "critical": initial_critical, "amount": 0, "pending_state": 0}
	if action >= 1000:
		var identity: int = action - 1000
		var offset: int = identity * 56
		if target_slot >= 10: return done()
		if (t.decode_u16(0x10) == 1 or t.decode_u16(0x12) == 7) and items.decode_u16(offset + 0x34) != 1:
			no_effect()
			return done()
		var hp: int = items.decode_s16(offset + 0x16)
		var mp: int = items.decode_s16(offset + 0x18)
		if hp > 0:
			rec.amount = -mini(hp, t.decode_s16(0x24) - t.decode_s16(0x26))
			put16(t, 0x26, t.decode_s16(0x26) - int(rec.amount))
		if mp > 0:
			var amount: int = -mini(mp, t.decode_s16(0x28) - t.decode_s16(0x2a))
			put16(t, 0x2a, t.decode_s16(0x2a) - amount)
			if hp == 0: rec.amount = amount
		if identity == 6:
			rec.amount = 90006 + int(t.decode_u16(0x10) != 0)
			put16(t, 0x10, 0)
		elif identity in [7, 8, 9]:
			if t.decode_u16(0x10) in ([1, 3] if identity == 7 else [1, 5]):
				rec.amount = 90007
				put16(t, 0x10, 0)
			else: no_effect()
		elif identity >= 155 and identity <= 160:
			var word_offset: int = [0x24, 0x28, 0x2e, 0x30, 0x32, 0x34][identity - 155]
			put16(t, word_offset, mini(999, t.decode_s16(word_offset) + 5))
			rec.amount = [90008, 90009, 90001, 90002, 90003, 90004][identity - 155]
		elif identity == 163: put16(t, 0x10, 0)
		else:
			var cure: int = items.decode_u16(offset + 0x34)
			if cure != 0:
				if t.decode_u16(0x10) == cure:
					if rec.amount == 0: rec.amount = 90007
					put16(t, 0x10, 0)
				else: no_effect()
		return done()
	var st: int = t.decode_u16(0x10)
	var control: int = t.decode_u16(0x12)
	if action in [2, 10]:
		if st == (5 if action == 2 else 2):
			rec.amount = 90007
			put16(t, 0x10, 0)
		else: no_effect()
		return done()
	if action in [3, 21, 33, 44]:
		var settings: Array = {3: [0, 4, 90001], 21: [4, 2, 90005], 33: [1, 2, 90002], 44: [3, 2, 90004]}[action]
		var index: int = settings[0]
		var base: int = t.decode_s16(0x2e + 2 * index)
		put16(t, 0x4c + 2 * index, mini(div0(base, int(settings[1])), div0(base, 10) + 1 + t.decode_s16(0x4c + 2 * index)))
		rec.amount = settings[2]
		return done()
	if action in [13, 45]:
		if not (st in [0, 1]) and control != 7:
			put16(t, 0x10, 0)
			rec.amount = 90007
		else: no_effect()
		return done()
	if action == 25:
		t.encode_s32(0x60, 0)
		t.encode_s32(0x5c, 0)
		message()
		return done()
	if action in [14, 54, 63]:
		t.encode_s32(0x64, 1)
		message()
		return done()
	if action == 82:
		message()
		return done()
	if action == 47:
		rec.amount = t.decode_s16(0x26) - t.decode_s16(0x24)
		put16(t, 0x26, t.decode_s16(0x24))
		put16(t, 0x10, 0)
		return done()
	if action == 35:
		var equipped: bool = false
		for identity in equipment(t): equipped = equipped or items.decode_u16(int(identity) * 56 + 0x34) == 11
		if st == 0 and (map_mode != 1 or (races.decode_s16(t.decode_u16(2) * 86 + 0x3e) == 99 and not equipped)):
			put_state(11, (a.decode_u16(4) + 4) * 5)
			rec.amount = 90010
		else: no_effect()
		return done()
	if action in [22, 32, 40]:
		if st != 1 and control != 7:
			rec.amount = -mini(effective(a, 2), t.decode_s16(0x24) - t.decode_s16(0x26))
			put16(t, 0x26, t.decode_s16(0x26) - int(rec.amount))
		return done()
	if action in [41, 64]:
		if action == 64:
			put16(a, 0x26, 0)
			put16(a, 0x10, 1)
		if action == 64 or st == 1 or control == 7:
			rec.amount = -mini(div0(effective(a, 2), 2), t.decode_s16(0x24))
			put16(t, 0x26, t.decode_s16(0x26) - int(rec.amount))
			put16(t, 0x10, 0)
		return done()
	if action in [55, 81] and same_unit:
		rec.amount = -mini(t.decode_s16(0x24) - t.decode_s16(0x26), first_result)
		put16(t, 0x26, t.decode_s16(0x26) - int(rec.amount))
		return done()
	if action in [1, 9, 71] and st == 5: put16(t, 0x10, 0)
	var av: Array = attributes(a)
	var tv: Array = attributes(t)
	if action == 31:
		if not (st in INCAP) and chance(int(tv[1]) - int(av[1]) + 60):
			put16(t, 6, a.decode_u16(6))
			message()
		else: no_effect()
		return done()
	if action in [23, 24, 28]:
		var ok: bool = (control == 0 or t.decode_u16(0) == 8) and not (st in INCAP)
		if action == 28:
			if ok:
				put_state(6)
				message()
			else: no_effect()
		elif ok and chance(int(av[1]) - int(tv[1]) + (40 if action == 23 else 30)):
			put_state(6 if action == 23 else 3)
			message()
		else: no_effect()
		return done()
	var can_status: bool = control == 0 or t.decode_u16(0) == 8
	if action in [5, 51, 26, 74, 79] and can_status and not (st in [1, 4, 5, 8, 9]):
		var channel: int = 0 if action in [5, 51] else 1
		if chance(int(av[channel]) - int(tv[channel]) + 30): put_state(8)
	elif action in [11, 12, 19, 72] and can_status and not (st in [1, 4, 5, 9]):
		if chance(int(tv[0]) - int(av[0]) + 30): put_state(5)
	elif action in [34, 73] and can_status and not (st in INCAP):
		if chance(int(tv[1]) - int(av[1]) + 40): put_state(2)
	elif action == 52 and can_status and not (st in INCAP):
		if chance(int(tv[2]) - int(av[2]) + 50): put_state(7)
	elif action == 53 and can_status and not (st in INCAP):
		if chance(int(tv[2]) - int(av[2]) + 30):
			t.encode_s32(0x68, 100)
			var value: int = roll()
			for pair in [[50, 3], [40, 6], [30, 2], [20, 8], [10, 7], [5, 5], [1, 4]]:
				if value < int(pair[0]): put16(t, 0x10, int(pair[1]))
	elif action in [50, 75] and can_status and (control == 0 or t.decode_u16(2) != 50) and not (st in [1, 4, 5, 9]):
		if chance(int(tv[2]) - int(av[2]) + 20): put_state(4)
	deal_damage(action, height_delta)
	return done()
