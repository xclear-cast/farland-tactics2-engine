class_name FT2PhysicalGeometry
extends RefCounted
static func f32(value: float) -> float:
	var bytes = PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0,value)
	return bytes.decode_float(0)
static func i32(value: int) -> int:
	return ((value+2147483648)&0xFFFFFFFF)-2147483648
static func half_away(value: float) -> int:
	var truncated = int(value)
	return truncated+(1 if value > 0.0 else -1) if absf(value-truncated) >= 0.5 else truncated
static func sampled_line(start: Vector2i, finish: Vector2i) -> Array:
	var x = f32(start.x)
	var y = f32(start.y)
	var dx = f32(i32(finish.x-start.x)*f32(0.02))
	var dy = f32(i32(finish.y-start.y)*f32(0.02))
	var out: Array = []
	for i in range(50):
		var point = Vector2i(half_away(x),half_away(y))
		if out.is_empty() or out[-1] != point: out.append(point)
		x = f32(x+dx)
		y = f32(y+dy)
	if not out.is_empty() and out[-1] == finish: out.pop_back()
	out.append(finish)
	return out
static func nearest(start: Vector2i, finish: Vector2i, sprite: Vector2i, project: Callable) -> Dictionary:
	if start == finish: return {"world":start,"residual":Vector2i.ZERO}
	var distance = INF
	var answer = {}
	for point in sampled_line(start,finish):
		var pixel: Vector2i = project.call(point)
		var delta = pixel-sprite
		var squared = i32(i32(delta.x*delta.x)+i32(delta.y*delta.y))
		var candidate = f32(sqrt(float(squared)))
		if answer.is_empty() or candidate < distance:
			distance = candidate
			answer = {"world":point,"residual":delta}
	return answer
static func focus(mode: int, pixel: Vector2i, motion: Vector2i, user: Vector2i, direction: int, a: Variant = null, b: Variant = null) -> Variant:
	var delta = motion+user
	if mode == 1: return pixel+delta
	if mode == 2: return Vector2i(pixel.x+delta.x,pixel.y+((-delta.x if direction in [0,3] else delta.x)>>1))
	if mode == 3 and a != null and b != null:
		var span = i32(b.x-a.x)
		if span == 0: return null
		var ratio = float(i32(pixel.x+delta.x-a.x))/span
		return Vector2i(i32(a.x+int(span*ratio)),i32(a.y+int(i32(b.y-a.y)*ratio)))
	return null
