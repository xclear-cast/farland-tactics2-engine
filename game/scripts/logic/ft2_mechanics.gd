class_name FT2Mechanics
extends "ft2_numeric.gd"
## Binary124-byte units remain authoritative; no engine random generator.

static func copy_units(source: Array) -> Array:
	var out: Array = []
	for unit in source: out.append(unit.duplicate())
	return out

static func xy(unit: PackedByteArray) -> Vector2i:
	return Vector2i(unit.decode_s32(8), unit.decode_s32(12))

static func set_xy(unit: PackedByteArray, point: Vector2i) -> void:
	unit.encode_u32(8, point.x & 0xffffffff)
	unit.encode_u32(12, point.y & 0xffffffff)

static func hostile(first: PackedByteArray, second: PackedByteArray, same: bool = false) -> bool:
	var ca = first.decode_u16(18)
	var cb = second.decode_u16(18)
	if same or ca in [1,7] or cb in [1,7]: return false
	return ((ca != 0) != (cb != 0)) != (first.decode_u16(16) == 7)

func has_ability(unit: PackedByteArray, ability: int) -> bool:
	for identity in equipment(unit):
		if items.decode_u16(int(identity)*56+52) == ability: return true
	return false

func round_numeric(unit: PackedByteArray) -> PackedByteArray:
	var out = unit.duplicate()
	if out.decode_u16(0) == 0: return out
	out.encode_u32(92,0)
	out.encode_u32(96,0)
	put16(out,42,mini(out.decode_s16(40),out.decode_s16(42)+div0(out.decode_s16(40)+9,10)))
	for offset in [76,78,80,82,84]:
		var value = out.decode_s16(offset)
		put16(out,offset,value-signi(value))
	return out

func status_numeric(unit: PackedByteArray, input_rng: Array) -> Dictionary:
	var out = unit.duplicate()
	var random = input_rng.duplicate()
	var event: Dictionary = {}
	var state = out.decode_u16(16)
	if state == 2:
		var amount = mini(out.decode_s16(38),div0(out.decode_s16(36),10)+1)
		put16(out,38,out.decode_s16(38)-amount)
		if out.decode_s16(38) == 0: put16(out,16,1)
		event = {"amount":amount,"damage_flag":0}
	elif state in [3,5,6,7,8,11]:
		var decay = {3:15,5:10,6:15,7:10,8:10,11:20}[state]
		var remaining = maxi(0,out.decode_s32(104)-decay)
		out.encode_u32(104,remaining & 0xffffffff)
		var step = rng_step(random,100)
		random = step.seeds
		if step.value > remaining:
			put16(out,16,0)
			event = {"amount":90011 if state == 11 else 90007,"damage_flag":0}
	return {"unit":out,"seeds":random,"event":event}

func experience_sum(actor: PackedByteArray, source_units: Array, records: Array) -> int:
	if actor.is_empty() or actor.decode_u16(18) != 0: return 0
	var total = 0
	var support = 7
	for record in records:
		var slot = int(record.target_slot)
		var amount = int(record.get("amount",record.get("result",{}).get("amount",0)))
		if slot < 0 or amount == 0: continue
		var target: PackedByteArray = source_units[slot]
		var value: int
		if target.decode_u16(18) != 0 and amount < 90000:
			var base = races.decode_s16(target.decode_u16(2)*86+20)
			value = div0(s32(amount*base),target.decode_s16(36))
			if target.decode_s16(38) == 0: value = s32(value+base)
			if target.decode_u16(0) != 8: value = s32(value*2)
			var percent = maxi(10,20*(target.decode_u16(4)-actor.decode_u16(4)+5))
			value = maxi(1,div0(s32(value*percent),100))
			if slot < 10: value = 0
		else:
			value = maxi(1,support)
			support = maxi(1,div0(support,2))
		total = s32(total+value)
	return total

func exp_award_step(unit: PackedByteArray, remaining: int, pending: int) -> Dictionary:
	var out = unit.duplicate()
	var delta = maxi(1,div0(remaining,100))
	remaining = s32(remaining-delta)
	if remaining >= 0:
		put16(out,44,mini(9899,out.decode_s16(44)+delta))
		if out.decode_s16(44) >= s32((out.decode_u16(4)+pending)*100): pending = s32(pending+1)
	return {"unit":out,"remaining":remaining,"pending":pending}

func apply_pending_levels(unit: PackedByteArray, count: int, input_rng: Array) -> Dictionary:
	var out = unit.duplicate()
	var random = input_rng.duplicate()
	for ignored in range(maxi(0,count)):
		put16(out,4,out.decode_u16(4)+1)
		var grown = grow_record(out,true,random)
		out = grown.unit
		random = grown.seeds
	return {"unit":out,"seeds":random}

func buy_quantity_enabled(price: int, current_money: int, owned: int, quantity: int) -> bool:
	return quantity >= 1 and quantity <= 9999-owned and price*quantity <= current_money

func sell_quantity_enabled(owned: int, quantity: int) -> bool:
	return quantity >= 1 and quantity <= owned

func equipment_receiver_enabled(unit: PackedByteArray) -> bool:
	if unit.decode_u16(16) == 9: return false
	for offset in [28,30,32,34]:
		if unit.decode_u16(offset) == 0: return true
	return false

static func gear_sell_credit(price: int) -> int: return (price&65535)>>1

func finish_states_and_drops(source: Array, records: Array) -> Array:
	var out = copy_units(source)
	for record in records:
		var slot = int(record.target_slot)
		if slot < 0: continue
		var unit: PackedByteArray = out[slot]
		if unit.decode_u16(16) == 1 and unit.decode_u16(18) != 0:
			var identity = unit.decode_u16(28)
			var gold = unit.decode_u16(30)
			if identity != 0 or gold != 0:
				put16(unit,2,8 if identity != 0 else 9)
				put16(unit,16,0)
				put16(unit,18,7)
			elif unit.decode_u16(0) == 8 or unit.decode_u16(0) > 30:
				unit.fill(0)
		else:
			var pending = int(record.get("pending_state",record.get("result",{}).get("pending_state",0)))
			if pending != 0 and unit.decode_u16(16) != 1: put16(unit,16,pending)
		out[slot] = unit
	return out

func equal_distribution(experience: Array, pool: int) -> Array:
	var out: Array = []
	if experience.is_empty(): return out
	var q = div0(pool,experience.size())
	var left = pool-q*experience.size()
	for index in range(experience.size()):
		out.append(q+int(left>0))
		left -= int(left>0)
	return out

func balanced_distribution(experience: Array, pool: int) -> Array:
	var out: Array = []
	out.resize(experience.size())
	out.fill(0)
	if experience.is_empty():
		assert(pool <= 0,"Original positive-pool / zero-party balance division failure")
		return out
	var order: Array = range(experience.size())
	var left = pool
	for i in range(order.size()-1):
		for j in range(i,order.size()):
			if experience[order[j]] < experience[order[i]]:
				var previous = order[i]
				order[i] = order[j]
				order[j] = previous
	for count in range(1,order.size()):
		if left <= 0: break
		var amount = mini(experience[order[count]]-experience[order[count-1]],div0(left,count))
		left -= count*amount
		for i in range(count): out[order[i]] += amount
		if left < count:
			for i in range(count):
				if left <= 0: break
				out[order[i]] += 1
				left -= 1
	if left > 0:
		var q = div0(left,order.size())
		left -= q*order.size()
		for i in order: out[i] += q
		for i in order:
			if left <= 0: break
			out[i] += 1
			left -= 1
	return out

func drag_distribution(experience: Array, allocations: Array, pool: int, selected: int, x: int, width: int, scale: int) -> Array:
	assert(width > 0)
	var desired = div0(s32(clampi(x,0,width)*scale),width)
	desired = maxi(experience[selected],mini(desired,s32(experience[selected]+pool)))-experience[selected]
	var out = allocations.duplicate()
	assert(out.size() != 1 or out[0] == desired, "Original changing single-party drag never terminates")
	var index = 0
	while out[selected] != desired:
		if index != selected:
			if desired > out[selected] and out[index] > 0:
				out[index] -= 1
				out[selected] += 1
			elif desired < out[selected]:
				out[index] += 1
				out[selected] -= 1
		index = (index+1)%out.size()
	return out

func money_after(current: int, delta: int) -> int:
	return clampi(s32(current+delta),0,999999)

func bag_count(bag: PackedByteArray, item: int) -> int:
	for k in range(80):
		if bag.decode_s16(k*4) == item: return bag.decode_s16(k*4+2)
	return 0

func grant(unit: PackedByteArray, bag: PackedByteArray, item: int, quantity: int) -> Dictionary:
	var out = unit.duplicate()
	var inventory = bag.duplicate()
	if items.decode_s16(item*56+46) in [0,1,2]:
		if out.is_empty(): return {"unit":out,"bag":inventory,"accepted":false}
		for offset in [28,30,32,34]:
			if out.decode_u16(offset) == 0:
				put16(out,offset,item)
				return {"unit":out,"bag":inventory,"accepted":true}
		return {"unit":out,"bag":inventory,"accepted":false}
	var slot = -1
	for k in range(80):
		if inventory.decode_s16(k*4) == item:
			slot = k
			break
	if slot < 0:
		for k in range(80):
			if inventory.decode_s16(k*4) == 0:
				slot = k
				break
	if slot < 0 or s32(inventory.decode_s16(slot*4+2)+quantity) > 9999: return {"unit":out,"bag":inventory,"accepted":false}
	put16(inventory,slot*4,item)
	put16(inventory,slot*4+2,inventory.decode_s16(slot*4+2)+quantity)
	return {"unit":out,"bag":inventory,"accepted":true}

func consume(bag: PackedByteArray, item: int, quantity: int) -> PackedByteArray:
	var out = bag.duplicate()
	if items.decode_s16(item*56+46) in [0,1,2]: return out
	for k in range(80):
		if out.decode_s16(k*4) != item: continue
		if s32(out.decode_s16(k*4+2)+quantity) > 9999: return out
		put16(out,k*4+2,out.decode_s16(k*4+2)-quantity)
		if out.decode_s16(k*4+2) <= 0:
			put16(out,k*4,0)
			put16(out,k*4+2,0)
		break
	return out

func can_equip(item: int, kind: int) -> bool:
	var mask = items.decode_u16(item*56+54)
	return mask == 0 or (kind == 23 and (mask&128)!=0) or (kind == 11 and (mask&256)!=0) or (mask & (1<<((kind-1)&31)))!=0

func equip_carried(unit: PackedByteArray, index: int) -> PackedByteArray:
	var out = unit.duplicate()
	var identity = out.decode_u16(28+index*2)
	var category = items.decode_u16(identity*56+46)
	var offset = 20 if category == 0 else 22 if category == 1 else 24 if out.decode_u16(24) == 0 else 26
	var old = out.decode_u16(offset)
	put16(out,offset,identity)
	put16(out,28+index*2,old)
	return out

func item_icon(identity: int) -> int:
	var category = items.decode_u16(identity*56+46)
	if category == 0:
		for k in range(8):
			if (items.decode_u16(identity*56+54)&(1<<k)) != 0: return k
		return 8
	return 9 if category == 1 else items.decode_u16(identity*56+50)+9

func construct(source: Array, descriptor: PackedByteArray, input_rng: Array) -> Dictionary:
	var out = copy_units(source)
	var random = input_rng.duplicate()
	var control = descriptor.decode_u16(18)
	var kind = descriptor.decode_u16(0)
	var slot = -1
	var reuse = false
	if control == 0:
		for i in range(10):
			if out[i].decode_u16(0) == kind:
				slot = i
				reuse = true
				break
	if slot < 0:
		for i in range(0 if control == 0 else 10,10 if control == 0 else 50):
			if out[i].decode_u16(0) == 0:
				slot = i
				break
	if slot < 0: return {"units":out,"slot":-1,"seeds":random}
	var unit: PackedByteArray = out[slot].duplicate() if reuse else descriptor.duplicate()
	if reuse:
		set_xy(unit,xy(descriptor))
		put16(unit,6,descriptor.decode_u16(6))
		put16(unit,16,descriptor.decode_u16(16))
	else:
		var definition = unit.decode_u16(2)
		if definition < races.size()/86 and control != 7:
			var offsets = [36,40,46,48,50,52,54]
			for k in range(7): put16(unit,offsets[k],races.decode_s16(definition*86+22+4*k))
			put16(unit,38,unit.decode_u16(36))
			put16(unit,42,unit.decode_u16(40))
			for ignored in range(maxi(0,descriptor.decode_u16(4)-1)):
				var grown = grow_record(unit,control != 0,random)
				unit = grown.unit
				random = grown.seeds
			if unit.decode_u16(16) == 1: put16(unit,38,0)
			elif unit.decode_u16(16) != 0: unit.encode_u32(104,100)
			put16(unit,44,(unit.decode_u16(4)-1)*100)
			if unit.decode_u16(0) >= 8:
				for k in range(8): unit[56+k] = races[definition*86+78+k]
		for k in range(112,124): unit[k] = 0
	unit.encode_u32(92,1)
	unit.encode_u32(96,1)
	out[slot] = unit
	return {"units":out,"slot":slot,"seeds":random}

func summon82(source: Array, caster: int, input_rng: Array, navigation) -> Dictionary:
	var out = copy_units(source)
	var random = input_rng.duplicate()
	var spawned: Array = []
	var attempts: Array = []
	var center = xy(out[caster])
	var direction = out[caster].decode_u16(6)
	for template in range(50):
		var unit: PackedByteArray = out[template]
		if unit.decode_u16(16) != 9 or unit.decode_u16(18) in [0,7]: continue
		var count = 0
		while true:
			count += 1
			if count > 10000: return {"units":out,"seeds":random,"spawned":spawned,"attempts":attempts,"error":"Original82 has unbounded rejection when no legal cell exists"}
			var rx = rng_step(random,17)
			var ry = rng_step(rx.seeds,17)
			random = ry.seeds
			var point = center+Vector2i(rx.value-8,ry.value-8)
			if count < 20: continue
			var c = navigation.cell(point)
			if c == null or c[1] != 0 or c[2] != 0: continue
			var occupied = false
			for other in out:
				if other.decode_u16(0) != 0 and (other.decode_u16(0) == 8 or other.decode_u16(16) != 9) and xy(other) == point: occupied = true
			if occupied: continue
			var descriptor = unit.duplicate()
			put16(descriptor,16,0)
			put16(descriptor,6,direction)
			set_xy(descriptor,point)
			var built = construct(out,descriptor,random)
			out = built.units
			random = built.seeds
			if built.slot < 0: return {"units":out,"seeds":random,"spawned":spawned,"attempts":attempts,"error":"Original82 does not check NULL constructor: no free NPC slot"}
			spawned.append(built.slot)
			attempts.append({"template_slot":template,"spawned_slot":built.slot,"xy":point,"random_candidate_pairs":count})
			break
	return {"units":out,"seeds":random,"spawned":spawned,"attempts":attempts,"error":""}
