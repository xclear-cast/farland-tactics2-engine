class_name FT2Environment
extends RefCounted
##4072F0 and408350: source clock and draw passes remain separate.
var stage = -1
var frame = 0
var epoch = 0
var offsets: Array = [0,0,0,0,0,0,0,0,0,0,0]
var cooldown = 0
var random_x = 0
var cloud = Vector2i(384,320)
var rail = Vector2i(0,288)
var row_rotation = 0
var secondary_epoch = -1
var secondary_frame = 0
var rng: Array = [167,19960,5150]
var events: Array = []
var mode = 1
var sound_enabled = true
var _ambient_started = false
var shake_amplitude = 0

func configure(id: int) -> void:
	stage = id
	frame = 0
	epoch = 0
	offsets.fill(0)
	cooldown = 0
	cloud = Vector2i(384,320)
	rail = Vector2i(0,288)
	row_rotation = 0
	secondary_epoch = -1
	secondary_frame = 0
	_ambient_started = false

func random(modulus: int) -> int:
	var multipliers = [171,172,170]
	var divisors = [177,176,178]
	var subtract = [2,35,63]
	var periods = [30269,30307,30323]
	for i in range(3):
		var n = int(rng[i])
		n = int(multipliers[i])*(n % int(divisors[i]))-int(subtract[i])*int(n/int(divisors[i]))
		if n < 0:
			n += int(periods[i])
		rng[i] = n
	var value = int(rng[0])+int(rng[1])+int(rng[2])
	return value % modulus if modulus > 0 else value

func advance(now: int, width: int = 640) -> bool:
	var dt = (now-epoch)&0xFFFFFFFF
	events.clear()
	if stage == 21 and sound_enabled and not _ambient_started:
		_ambient_started = true
		events.append({"kind":"sound","stem":"spectate","loop":true})
		return false
	if stage == 53 and shake_amplitude != 0 and dt >= 10:
		epoch = now
		return true
	if stage == 16 and dt > 100:
		frame = (frame+1)%5
		return true
	if stage in [23,26,52,96] and dt >= (50 if stage == 96 else 100):
		epoch = now
		row_rotation = (row_rotation+1)%maxi(1,width)
		return true
	if stage in [33,42,48,57] and dt > 200:
		epoch = now
		frame = (frame+1)%6
		return true
	if stage in [35,36,37,78] and dt >= 50:
		for i in range(11):
			offsets[i] += 11-i
			var span = 640-i*32
			while offsets[i] > 0:
				offsets[i] -= span
		if cooldown > 0:
			cooldown -= 1
		if random(cooldown+1) == 0:
			random_x = random(640)
			cooldown = 10
			if mode == 1:
				events.append({"kind":"palette_flash","key":"map/st35c.bmp"})
		frame = int(offsets[0])&0xFFFFFFFF
		return true
	if stage == 54 and dt >= 50:
		epoch = now
		cloud += Vector2i(-2,1)
		if cloud.x < -640:
			cloud += Vector2i(1024,-512)
		rail += Vector2i(24,-12)
		if rail.x > 0:
			rail += Vector2i(-192,96)
		frame = (frame+1)%4
		return true
	if stage == 69 and dt >= 50:
		for i in range(3):
			offsets[i] += 3-i
			while offsets[i] > -480:
				offsets[i] -= 960
		frame = int(offsets[0])&0xFFFFFFFF
		return true
	if stage == 20:
		if secondary_epoch < 0:
			secondary_epoch = now
		if now-secondary_epoch >= 150:
			secondary_frame = (secondary_frame+1)%6
			secondary_epoch = now
			return true
	return false

func _bitmap(name: String, pos: Vector2i, source: Rect2i = Rect2i(), keyed: bool = true, dib: bool = false) -> Dictionary:
	var command = {"op":"bitmap","key":"map/"+name+".bmp","pos":pos,"remaps":[[10,112,32]],"transparent":249 if keyed else -1,"palette_install":[],"dib":dib}
	if source.size != Vector2i.ZERO:
		command["source"] = source
	return command

func commands(position: Vector2i) -> Array:
	var result: Array = []
	if stage == 16 and frame != 2:
		result.append(_bitmap("st16d" if frame == 0 else "st16e",position+Vector2i(1008,128)))
	elif stage == 52:
		result.append(_bitmap("st52c",position))
		result.append(_bitmap("st52d",position+Vector2i(400,0)))
	elif stage in [33,42,48,57]:
		var prefix = "st%02d" % stage
		var name = prefix+String.chr((102 if stage == 57 else 99)+frame)
		var start = Vector2i.ZERO if stage in [33,42] else Vector2i(position.x%340-340,position.y%170-170)
		for x in range(start.x,640,340):
			for y in range(start.y,480,170):
				result.append(_bitmap(name,Vector2i(x,y),Rect2i(),false))
	elif stage in [35,36,37,78]:
		result.append({"op":"rect","rect":Rect2i(0,0,640,480),"color":143,"filled":true})
		if cooldown > 0:
			var k = cooldown%10
			var source = Rect2i((k%5)*64,int(k/5)*192,64,192)
			for y in [160,352]:
				result.append(_bitmap("st35c",Vector2i(random_x,y),source,false,true))
		for i in range(10,-1,-1):
			var width = 640-i*32
			var top = (mini(i,5)+2*i)*16
			for x in range(int(offsets[i]),640,width):
				result.append(_bitmap("st35b",Vector2i(x,i*16),Rect2i(0,top,width,32 if i >= 5 else 48)))
	elif stage == 54:
		result.append(_bitmap("st54d",Vector2i.ZERO,Rect2i(cloud,Vector2i(640,480)),false,true))
		if cloud.x < 0:
			result.append(_bitmap("st54d",Vector2i.ZERO,Rect2i(cloud+Vector2i(1024,-512),Vector2i(640,480)),false,true))
		var p = rail
		while p.x < 640:
			result.append(_bitmap("st54c",p))
			p += Vector2i(192,-96)
		result.append(_bitmap("st54b",Vector2i(224,184),Rect2i((frame%2)*176,int(frame/2)*112,176,112)))
	elif stage == 69:
		for i in [2,1,0]:
			var x = int(offsets[i])+position.x
			var k = 0
			while x < 640:
				if x+480 >= 0:
					result.append(_bitmap("st69"+String.chr(99+2*i+k%2),Vector2i(x,400-i*64),Rect2i(0,0,480,112)))
				x += 480
				k += 1
	if stage == 20:
		result.append(_bitmap("st20b",Vector2i(0,384),Rect2i((secondary_frame%3)*192,int(secondary_frame/3)*96,192,96)))
	return result
