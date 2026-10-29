class_name FT2IndexedSurface
extends RefCounted

var width: int
var height: int
var _pixels: PackedByteArray
var _image: Image
var _native_dirty = false
var _bytes_dirty = false
var reference_only = false # Deterministic regression harness; normal runtime uses native L8 copies.
var pixels: PackedByteArray:
	get:
		_ensure_bytes()
		return _pixels
	set(value):
		_pixels = value
		_native_dirty = true
		_bytes_dirty = false

func _init(w: int = 640, h: int = 480, color: int = 0) -> void:
	width = w
	height = h
	_pixels.resize(w * h)
	_pixels.fill(color & 255)
	_image = Image.create_from_data(w,h,false,Image.FORMAT_L8,_pixels)

func clear(color: int = 0) -> void:
	_pixels.resize(width*height)
	_pixels.fill(color & 255)
	_native_dirty = true
	_bytes_dirty = false

func _ensure_image() -> void:
	if _native_dirty:
		_image = Image.create_from_data(width,height,false,Image.FORMAT_L8,_pixels)
		_native_dirty = false

func _ensure_bytes() -> void:
	if _bytes_dirty:
		_pixels = _image.get_data()
		_bytes_dirty = false

func native_image() -> Image:
	_ensure_image()
	return _image

static func stretch_image(source: Image, rect: Rect2i, size: Vector2i) -> Image:
	# Exact floor(x*srcW/dstW), with native column/row copies instead of a GD pixel loop.
	var horizontal = Image.create(size.x,rect.size.y,false,Image.FORMAT_L8)
	for x in range(size.x):
		var sx = rect.position.x+int(x*rect.size.x/size.x)
		horizontal.blit_rect(source,Rect2i(sx,rect.position.y,1,rect.size.y),Vector2i(x,0))
	var output = Image.create(size.x,size.y,false,Image.FORMAT_L8)
	for y in range(size.y):
		var sy = int(y*rect.size.y/size.y)
		output.blit_rect(horizontal,Rect2i(0,sy,size.x,1),Vector2i(0,y))
	return output

func fill_rect(rect: Rect2i, color: int) -> void:
	var r = rect.intersection(Rect2i(0, 0, width, height))
	_ensure_image()
	var c = float(color&255)/255.0
	_image.fill_rect(r,Color(c,c,c,1.0))
	_bytes_dirty = true

func blit(source: Dictionary, source_rect: Rect2i, pos: Vector2i, key: int = -1, flip: int = 0, mask: int = 0, clip: Rect2i = Rect2i(0, 0, 640, 480), checker: bool = false, checker_world: Vector2i = Vector2i.ZERO) -> Rect2i:
	if source.is_empty() or source_rect.size.x <= 0 or source_rect.size.y <= 0:
		return Rect2i()
	var sw = int(source.width)
	var sh = int(source.height)
	var bytes: PackedByteArray = source.pixels
	var dest = Rect2i(pos, source_rect.size).intersection(Rect2i(0, 0, width, height)).intersection(clip)
	if dest.size.x <= 0 or dest.size.y <= 0:
		return Rect2i()
	if mask == 0 and not checker and not reference_only:
		return _native_blit(source,source_rect,pos,key,flip,dest)
	_ensure_bytes()
	# Dither phase begins at the clipped destination of THIS part, as original kernels.
	for y in range(dest.position.y, dest.end.y):
		var local_y = y - pos.y
		var sy = source_rect.position.y + (source_rect.size.y - 1 - local_y if flip & 2 else local_y)
		if sy < 0 or sy >= sh:
			continue
		var so = sy * sw
		var doffset = y * width
		for x in range(dest.position.x, dest.end.x):
			if mask & (1 << (((y - dest.position.y) & 3) * 4 + ((x - dest.position.x) & 3))):
				continue
			if checker and ((x + y + checker_world.x + checker_world.y) & 1) == 1:
				continue
			var local_x = x - pos.x
			var sx = source_rect.position.x + (source_rect.size.x - 1 - local_x if flip & 1 else local_x)
			if sx < 0 or sx >= sw:
				continue
			var value = int(bytes[so + sx])
			if value != key and (not checker or value != 0):
				_pixels[doffset + x] = value
	_native_dirty = true
	return dest

func _native_blit(source: Dictionary, source_rect: Rect2i, pos: Vector2i, key: int, flip: int, dest: Rect2i) -> Rect2i:
	_ensure_image()
	if not source.has("$image"):
		source["$image"] = Image.create_from_data(int(source.width),int(source.height),false,Image.FORMAT_L8,source.pixels)
	var image: Image = source["$image"]
	var mask_image: Image
	var sr = source_rect
	if flip != 0:
		# Crop before flipping, preserving part-local placement/clip phase.
		var cache_key = "$flip:"+str(source_rect)+":"+str(flip)
		if not source.has(cache_key):
			var cropped = image.get_region(source_rect)
			if flip & 1:
				cropped.flip_x()
			if flip & 2:
				cropped.flip_y()
			source[cache_key] = {"width":cropped.get_width(),"height":cropped.get_height(),"pixels":cropped.get_data(),"$image":cropped}
		return _native_blit(source[cache_key],Rect2i(Vector2i.ZERO,sr.size),pos,key,0,dest)
	var clipped_source = sr
	clipped_source.position += dest.position-pos
	clipped_source.size = dest.size
	if key >= 0 and key <= 255:
		var mask_key = "$key:"+str(key)
		if not source.has(mask_key):
			var alpha = PackedByteArray()
			var bytes: PackedByteArray = source.pixels
			alpha.resize(bytes.size()*2)
			for i in range(bytes.size()):
				alpha[2*i+1] = 0 if int(bytes[i]) == key else 255
			source[mask_key] = Image.create_from_data(int(source.width),int(source.height),false,Image.FORMAT_LA8,alpha)
		mask_image = source[mask_key]
		_image.blit_rect_mask(image,mask_image,clipped_source,dest.position)
	else:
		_image.blit_rect(image,clipped_source,dest.position)
	_bytes_dirty = true
	return dest

func line(a: Vector2i, b: Vector2i, color: int) -> void:
	_ensure_bytes()
	var x = a.x
	var y = a.y
	var dx = absi(b.x - a.x)
	var dy = -absi(b.y - a.y)
	var sx = 1 if a.x < b.x else -1
	var sy = 1 if a.y < b.y else -1
	var error = dx + dy
	while true:
		if x >= 0 and y >= 0 and x < width and y < height:
			_pixels[y * width + x] = color & 255
		if x == b.x and y == b.y:
			break
		var twice = 2 * error
		if twice >= dy:
			error += dy
			x += sx
		if twice <= dx:
			error += dx
			y += sy
	_native_dirty = true

func dictionary() -> Dictionary:
	return {"width":width,"height":height,"pixels":pixels}
