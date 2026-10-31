class_name FT2IndexedFont
extends RefCounted

var styles: Dictionary = {}
var masks: PackedByteArray
var observations: Dictionary = {}
var missing: Dictionary = {}
var _cache: Dictionary = {}
var _cache_order: Array[String] = []
var _cache_sizes: Dictionary = {}
var _cache_bytes = 0
var _extension_fonts: Array[Font] = []
var _extension_fonts_ready := false
const CACHE_LIMIT_BYTES = 8*1024*1024

func _remember(key: String, bitmap: Dictionary) -> void:
	# Typewriter prefixes otherwise retain an unbounded full bitmap for every prefix in the campaign.
	var charge = maxi(1,int(bitmap.width)*int(bitmap.height)*4)
	while not _cache_order.is_empty() and _cache_bytes+charge > CACHE_LIMIT_BYTES:
		var oldest: String = _cache_order.pop_front()
		_cache.erase(oldest)
		_cache_bytes -= int(_cache_sizes.get(oldest,0))
		_cache_sizes.erase(oldest)
	if charge > CACHE_LIMIT_BYTES: return
	_cache[key] = bitmap
	_cache_order.append(key)
	_cache_sizes[key] = charge
	_cache_bytes += charge

func _init() -> void:
	var document = FT2IndexedAssets.read_json("res://assets/indexed/fonts.json")
	if document.is_empty():
		return
	masks = FT2Content.bytes(str(document.mask_file))
	for style in document.styles:
		_normalize_style(style)
		styles[_key(style)] = style
	var otm = FT2IndexedAssets.read_json("res://assets/indexed/font_otm.json")
	for row in otm.get("rows", []):
		var id = int(row.style_id)
		if id < 0 or id >= document.styles.size():
			continue
		var key = _key(document.styles[id])
		for measure in row.get("measurements", []):
			if int(measure.get("success", 0)) != 0:
				observations[key + "|" + str(measure.text)] = measure.extent
		if styles.has(key):
			styles[key]["otm_ascent"] = int(row.get("otmAscent", styles[key].metrics.ascent))

func _normalize_style(style: Dictionary) -> void:
	if not style.has("metrics") or not style.has("glyphs"):
		return
	var raw_height := int(style.get("height", 16))
	var cell := maxi(1, absi(raw_height))
	if int(style.metrics.get("ascent", 0)) + int(style.metrics.get("descent", 0)) <= maxi(2, cell):
		return
	var descent := mini(2, maxi(0, cell - 1)) if raw_height < 0 else maxi(1, roundi(cell * 0.14))
	var ascent := maxi(1, cell - descent)
	var raw_ascent := int(style.metrics.get("ascent", ascent))
	var shift := maxi(0, raw_ascent - ascent)
	for code in style.glyphs:
		var glyph: Dictionary = style.glyphs[code]
		var rect: Array = glyph.get("rect", [0, 0, 0, 0])
		if rect.size() >= 4:
			var rows := int(rect[3])
			rect[1] = clampi(int(rect[1]) - shift, 0, maxi(0, cell - rows)) if rows > 0 else 0
		var adv: Array = glyph.get("advance", [0, cell])
		if adv.size() >= 2:
			adv[1] = cell
	style.metrics["height"] = cell
	style.metrics["ascent"] = ascent
	style.metrics["descent"] = descent
	style.metrics["internal_leading"] = 0

func _key(font: Dictionary) -> String:
	return "%s|%d|%d|%d" % [str(font.get("family", "바탕")), int(font.get("height", 16)), int(font.get("weight", 700)), int(font.get("italic", 0))]

func _style(font: Dictionary) -> Dictionary:
	var key = _key(font)
	if not styles.has(key):
		missing["font:" + key] = true
		return {}
	return styles[key]

func _extensions_active() -> bool:
	if FT2Content.active==null or FT2Content.active.extensions==null:return false
	var registry=FT2Content.active.extensions
	return not registry.characters.is_empty() or not registry.skills.is_empty() or not registry.stories.is_empty()

func _prepare_extension_fonts() -> void:
	if _extension_fonts_ready:return
	_extension_fonts_ready=true
	# The original, verified private font is preferred. No font pixels are shipped.
	var root:=FT2Content.active.root
	var metadata=JSON.parse_string(FileAccess.get_file_as_string(root.path_join("conversion_report.json"))) if FileAccess.file_exists(root.path_join("conversion_report.json")) else null
	var base=JSON.parse_string(FileAccess.get_file_as_string(root.path_join("assets/indexed/fonts.json")))
	var path:=str(metadata.get("reports",{}).get("fonts",{}).get("font_file","")) if metadata is Dictionary else ""
	if OS.get_name()=="Linux" and path.length()>2 and path.substr(1,1)==":":path="/mnt/"+path.left(1).to_lower()+path.substr(2).replace("\\","/")
	if path!="" and FileAccess.file_exists(path) and base is Dictionary and FileAccess.get_sha256(path)==str(base.get("font_sha256","")):
		var file:=FontFile.new();file.data=FileAccess.get_file_as_bytes(path)
		_extension_fonts.append(file)
	var system:=SystemFont.new()
	system.font_names=PackedStringArray(["Malgun Gothic","Apple SD Gothic Neo","Noto Sans CJK KR","Noto Sans","Arial"])
	system.allow_system_fallback=true
	_extension_fonts.append(system)

func _supplement(style: Dictionary, font: Dictionary, code: int) -> bool:
	var key:=str(code)
	if style.glyphs.has(key):return true
	if not _extensions_active():return false
	_prepare_extension_fonts()
	var height:=int(font.get("height",16))
	var size:=maxi(1,roundi(absi(height)*0.82)) if height>0 else maxi(1,absi(height))
	var server:=TextServerManager.get_primary_interface()
	for face in _extension_fonts:
		for rid in face.get_rids():
			if not server.font_has_char(rid,code):continue
			server.font_set_oversampling(rid,1.0)
			var glyph:=server.font_get_glyph_index(rid,size,code,0)
			server.font_render_glyph(rid,Vector2i(size,0),glyph)
			var texture_index:=server.font_get_glyph_texture_idx(rid,Vector2i(size,0),glyph)
			var advance:=maxi(0,roundi(server.font_get_glyph_advance(rid,size,glyph).x))
			if texture_index<0:
				if code in [32,12288]:style.glyphs[key]={"offset":masks.size(),"rect":[0,0,0,0],"advance":[advance,int(style.metrics.height)],"pen":advance};return true
				continue
			var image:=server.font_get_texture_image(rid,Vector2i(size,0),texture_index)
			if image==null:continue
			var uv: Rect2=server.font_get_glyph_uv_rect(rid,Vector2i(size,0),glyph)
			var offset: Vector2=server.font_get_glyph_offset(rid,Vector2i(size,0),glyph)
			var width:=roundi(uv.size.x);var rows:=roundi(uv.size.y);var start:=masks.size()
			for y in rows:
				for x in width:
					var pixel:=image.get_pixel(roundi(uv.position.x)+x,roundi(uv.position.y)+y)
					var alpha: float=pixel.r if image.get_format() in [Image.FORMAT_L8,Image.FORMAT_R8] else pixel.a
					masks.append(1 if alpha>=0.25 else 0)
			var gy:=clampi(int(style.metrics.ascent)+roundi(offset.y),0,maxi(0,int(style.metrics.height)-rows)) if rows>0 else 0
			style.glyphs[key]={"offset":start,"rect":[roundi(offset.x),gy,width,rows],"advance":[advance,int(style.metrics.height)],"pen":advance,"extension_system_font":true}
			return true
	return false

func measure(raw_text: String, font: Dictionary) -> Dictionary:
	var style = _style(font)
	if style.is_empty():
		return {"width":0,"height":0,"extent":Vector2i.ZERO,"size":Vector2i.ZERO,"ascent":0,"overhang":0,"observed":false,"missing":true}
	var overhang = int(style.metrics.overhang)
	var width = 0
	var height = int(style.metrics.height)
	var observed = observations.has(_key(font) + "|" + raw_text)
	if observed:
		var e = observations[_key(font) + "|" + raw_text]
		width = int(e[0])
		height = int(e[1])
	else:
		for i in range(raw_text.length()):
			var cp = str(raw_text.unicode_at(i))
			if not style.glyphs.has(cp):_supplement(style,font,raw_text.unicode_at(i))
			if style.glyphs.has(cp):
				width += int(style.glyphs[cp].pen)
			elif observations.has(_key(font) + "|" + raw_text.substr(i, 1)):
				width += int(observations[_key(font) + "|" + raw_text.substr(i, 1)][0]) - overhang
			else:
				missing["measure:" + _key(font) + ":" + cp] = true
		if raw_text.length() > 0:
			width += overhang
	return {"width":width,"height":height,"extent":Vector2i(width,height),"size":Vector2i(width+33,height+3),"ascent":int(style.get("otm_ascent", style.metrics.ascent)),"overhang":overhang,"observed":observed,"missing":false}

func rasterize(raw_text: String, font: Dictionary, color: int = 30, decor: Dictionary = {}, visible_override: String = "") -> Dictionary:
	if decor.get("raw_gdi",false):
		return rasterize_gdi(visible_override if visible_override != "" else raw_text,font,color,int(decor.get("background",254)))
	var cache_key = raw_text + "|" + _key(font) + "|" + str(color) + JSON.stringify(decor) + visible_override
	if _cache.has(cache_key):
		return _cache[cache_key]
	var metrics = measure(raw_text, font)
	if metrics.get("missing", false):
		return {}
	var style = _style(font)
	var w = int(metrics.width) + 33
	var h = int(metrics.height) + 3
	var background = int(decor.get("background", 254))
	var background_byte = background & 255
	var mode8 = bool(decor.get("mode8", false))
	var kind = int(decor.get("style", 1))
	var shadow = int(decor.get("shadow", 248 if kind == 2 and not mode8 else 16)) & 255
	var top = PackedByteArray()
	top.resize(w * h)
	top.fill(background_byte)
	var ink = PackedByteArray()
	ink.resize(w * h)
	ink.fill(background_byte)
	var visible_text = visible_override if visible_override != "" else raw_text.replace("_", " ").replace("*", ",")
	var pen = 0
	for i in range(visible_text.length()):
		var cp = str(visible_text.unicode_at(i))
		if not style.glyphs.has(cp):
			missing["glyph:" + _key(font) + ":" + cp] = true
			continue
		var glyph = style.glyphs[cp]
		var rect = glyph.rect
		for y in range(int(rect[3])):
			for x in range(int(rect[2])):
				var dest_x = pen + int(rect[0]) + x
				var dest_y = int(rect[1]) + y
				if dest_x >= 0 and dest_x < w and dest_y >= 0 and dest_y < h and masks[int(glyph.offset) + y * int(rect[2]) + x] != 0:
					ink[dest_y * w + dest_x] = 255
		pen += int(glyph.pen)
	var outline = kind == 1 if mode8 else kind == 1 or kind == 3
	if outline:
		for offset in [Vector2i(2,2),Vector2i(1,2),Vector2i(2,1),Vector2i(3,2),Vector2i(2,3)]:
			_copy_mask(top, ink, w, h, offset, background_byte)
		var copy = top.duplicate()
		for y in range(h - 1):
			for x in range(w - 1):
				if copy[(y + 1) * w + x + 1] != background_byte:
					top[y * w + x] = copy[(y + 1) * w + x + 1]
	elif not mode8 and kind == 2:
		top = ink.duplicate()
	for i in range(w * h):
		if int(top[i]) != background:
			top[i] = shadow
		if int(ink[i]) != background:
			ink[i] = color & 255
	_copy_mask(top, ink, w, h, Vector2i.ONE, background if background >= 0 and background <= 255 else -1)
	var result = {"width":w,"height":h,"pixels":top,"transparent":background if background >= 0 and background <= 255 else -1,"metrics":metrics}
	_remember(cache_key,result)
	return result

func rasterize_gdi(raw_text: String, font: Dictionary, color: int = 0, transparent: int = 254) -> Dictionary:
	var key = "raw_gdi|"+raw_text+"|"+_key(font)+"|"+str(color)+"|"+str(transparent)
	if _cache.has(key): return _cache[key]
	var metrics = measure(raw_text,font)
	if metrics.get("missing",false) or int(metrics.width) <= 0: return {}
	var style = _style(font)
	var w = int(metrics.width)
	var h = int(metrics.height)
	var pixels = PackedByteArray()
	pixels.resize(w*h)
	pixels.fill(transparent&255)
	var pen = 0
	for i in range(raw_text.length()):
		var cp = str(raw_text.unicode_at(i))
		if not style.glyphs.has(cp):
			missing["glyph:"+_key(font)+":"+cp] = true
			continue
		var glyph: Dictionary = style.glyphs[cp]
		var rect = glyph.rect
		for y in range(int(rect[3])):
			var dy = int(rect[1])+y
			if dy < 0 or dy >= h: continue
			for x in range(int(rect[2])):
				var dx = pen+int(rect[0])+x
				if dx >= 0 and dx < w and masks[int(glyph.offset)+y*int(rect[2])+x] != 0:
					pixels[dy*w+dx] = color&255
		pen += int(glyph.pen)
	var result = {"width":w,"height":h,"pixels":pixels,"transparent":transparent,"metrics":metrics}
	_remember(key,result)
	return result

func _copy_mask(dest: PackedByteArray, source: PackedByteArray, w: int, h: int, offset: Vector2i, key: int) -> void:
	for y in range(h):
		for x in range(w):
			var dx = x + offset.x
			var dy = y + offset.y
			if dx >= 0 and dx < w and dy >= 0 and dy < h and int(source[y*w+x]) != key:
				dest[dy*w+dx] = source[y*w+x]
