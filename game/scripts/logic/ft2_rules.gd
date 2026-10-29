class_name FT2Rules
extends RefCounted

var items: PackedByteArray
var races: PackedByteArray
var magics: PackedByteArray

func _init(data = null) -> void:
	if data != null:
		items = data.raw_table("item")
		races = data.raw_table("race")
		magics = data.raw_table("magic")
	else:
		var root = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
		items = FT2Content.bytes(root.path_join("data/port_ready/python_runtime/tables/item.dat"))
		races = FT2Content.bytes(root.path_join("data/port_ready/python_runtime/tables/race.dat"))
		magics = FT2Content.bytes(root.path_join("data/port_ready/python_runtime/tables/magic.dat"))

static func s32(value: int) -> int:
	var wrapped: int = value & 0xffffffff
	return wrapped - 0x100000000 if wrapped >= 0x80000000 else wrapped

static func div0(a: int, b: int) -> int:
	var quotient: int = absi(a) / absi(b)
	return -quotient if (a < 0) != (b < 0) else quotient

static func rem0(a: int, b: int) -> int:
	return a - div0(a, b) * b

static func rng_step(seeds: Array, modulus: int) -> Dictionary:
	var x: int = s32(int(seeds[0]))
	var y: int = s32(int(seeds[1]))
	var z: int = s32(int(seeds[2]))
	x = s32(171 * rem0(x, 177) - 2 * div0(x, 177))
	y = s32(172 * rem0(y, 176) - 35 * div0(y, 176))
	z = s32(170 * rem0(z, 178) - 63 * div0(z, 178))
	if x < 0: x = s32(x + 30269)
	if y < 0: y = s32(y + 30307)
	if z < 0: z = s32(z + 30323)
	var total: int = s32(s32(x + y) + z)
	return {"seeds": [x, y, z], "value": rem0(total, modulus) if modulus > 0 else total}

func effective_agi(unit: PackedByteArray) -> int:
	var value: int = unit.decode_s16(0x36) + unit.decode_s16(0x54)
	for offset in [0x14, 0x16, 0x18, 0x1a]:
		value += items.decode_s16(unit.decode_u16(offset) * 56 + 0x22)
	return value

func chance_threshold(a: PackedByteArray, b: PackedByteArray, input_scale: int) -> int:
	var scale: int = maxi(1, s32(input_scale))
	var adir: int = a.decode_u16(6)
	var bdir: int = b.decode_u16(6)
	if b.decode_u16(0x10) in [1, 4, 5, 3, 8, 9]: scale = s32(scale * 3)
	elif adir == bdir: scale = s32(scale * 2)
	elif adir != (bdir ^ 3): scale = s32(scale + div0(scale, 2))
	var denominator: int = effective_agi(b)
	if denominator == 0: denominator = 1
	return maxi(1, div0(s32(effective_agi(a) * scale), denominator))

static func put16(data: PackedByteArray, offset: int, value: int) -> void:
	data.encode_u16(offset, value & 0xffff)

func grow_record(unit: PackedByteArray, randomize: bool, input_seeds: Array) -> Dictionary:
	var result: PackedByteArray = unit.duplicate()
	var seeds: Array = input_seeds.duplicate()
	var race: int = unit.decode_u16(2) * 86
	var offsets: Array = [0x24, 0x28, 0x2e, 0x30, 0x32, 0x34, 0x36]
	for index in range(7):
		var offset: int = offsets[index]
		var increment: int = races.decode_s16(race + 0x18 + index * 4)
		var jitter: int = 0
		if randomize:
			var rolled: Dictionary = rng_step(seeds, 3)
			seeds = rolled.seeds
			jitter = rolled.value - 1
		var current: int = result.decode_s16(offset)
		if current + increment + jitter > 999: put16(result, offset, 999)
		else:
			jitter = 0
			if randomize:
				var rolled: Dictionary = rng_step(seeds, 3)
				seeds = rolled.seeds
				jitter = rolled.value - 1
			put16(result, offset, current + increment + jitter)
	if result.decode_u16(0x10) != 1:
		put16(result, 0x26, result.decode_u16(0x24))
		put16(result, 0x2a, result.decode_u16(0x28))
	if result.decode_u16(0x12) == 0:
		var mask: int = 1 << ((result.decode_u16(0) - 1) & 31)
		var cursor: int = 0
		for identity in range(magics.size() / 64):
			var base: int = identity * 64
			var required: int = magics.decode_u16(base + 0x14)
			if (magics.decode_u16(base + 0x34) & mask) != 0 and required != 0 and result.decode_u16(4) >= required:
				put16(result, 0x38 + cursor * 2, identity)
				cursor += 1
	return {"unit": result, "seeds": seeds}
