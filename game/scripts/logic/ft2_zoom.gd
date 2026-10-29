class_name FT2Zoom
extends RefCounted
##402DE0/40883E. This is a draw-count controller, not an elapsed-time animation.
var enabled: int = 0 #449270 retains request DWORD, not a normalized BOOL.
var divisor = 8 #44E66C
var disabled = false #449260
var display_capable = true #46C978
func apply_settings(settings: Dictionary) -> void:
	disabled = bool(settings.get("skip_zoom",false))
func request(value: int = 1) -> void:
	if disabled:
		enabled = 0
		return
	divisor = 8
	enabled = value
func finish_results() -> void: enabled = 0 #406950 leaves divisor unchanged.
static func div0(a: int,b: int) -> int:
	assert(b != 0)
	var q: int = absi(a)/absi(b)
	return -q if (a < 0) != (b < 0) else q
func presentation(copy_mode: bool = false) -> Dictionary:
	if copy_mode: return {"op":"copy","source_rect":[0,0,640,480],"dest_rect":[0,0,640,480],"flags":0}
	if not enabled or not display_capable: return {"op":"present"}
	var x = div0(div0(640,divisor),2)
	var y = div0(div0(480,divisor),2)
	var out = {"op":"stretch","source_rect":[x,y,640-x,480-y],"dest_rect":[0,0,640,480],"flags":0x1000000}
	divisor = maxi(2,divisor-1)
	return out
static func sample(point: Vector2i,source_rect: Array) -> Vector2i:
	# Integer nearest sampling used by the indexed DirectDraw adapter.
	assert(point.x >= 0 and point.x < 640 and point.y >= 0 and point.y < 480)
	return Vector2i(int(source_rect[0])+div0(point.x*(int(source_rect[2])-int(source_rect[0])),640),int(source_rect[1])+div0(point.y*(int(source_rect[3])-int(source_rect[1])),480))
static func sample_image(image: Dictionary,source_rect: Array) -> Dictionary:
	# Deterministic CPU reference. A renderer may optimize while preserving these samples.
	var xlookup: Array = []
	for x in range(640): xlookup.append(sample(Vector2i(x,0),source_rect).x)
	var input: PackedByteArray = image.pixels
	var output = PackedByteArray()
	output.resize(640*480)
	for y in range(480):
		var sy = sample(Vector2i(0,y),source_rect).y
		for x in range(640): output[y*640+x] = input[sy*int(image.width)+int(xlookup[x])]
	return {"width":640,"height":480,"pixels":output}
