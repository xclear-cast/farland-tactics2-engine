class_name FT2IndexedAssets
extends RefCounted

var manifest: Dictionary = {}
var missing: Dictionary = {}
var _images: Dictionary = {}
var _apds: Dictionary = {}
var _maps: Dictionary = {}

func _init() -> void:
	manifest = read_json("res://assets/indexed/manifest.json")

static func read_json(path: String) -> Dictionary:
	var parsed = FT2Content.read_json(path)
	return parsed if parsed is Dictionary else {}

func image(key: String, remaps: Array = []) -> Dictionary:
	key = key.replace("\\", "/").to_lower()
	#41AC40 loads WALL through41ADB0 before any143/107/bar/icon consumer.
	#Keep this resource preprocessing shared; the source SYSTEM-last lifecycle
	#owns the hardware palette, so WALL draws must not install their own palette.
	if key == "bmp/wall.bmp" and remaps.is_empty():
		remaps = [[90,16,208],[10,64,144],[74,16,16]]
	var cache_key = key + JSON.stringify(remaps)
	if _images.has(cache_key):
		return _images[cache_key]
	if not manifest.get("images", {}).has(key):
		missing[key] = true
		return {}
	var row: Dictionary = manifest.images[key]
	var bytes = FT2Content.bytes(str(row.indices))
	var pal = FT2Content.bytes(str(row.palette))
	for remap in remaps:
		var start = int(remap[0])
		var count = int(remap[1])
		var dest = int(remap[2])
		var colors = pal.slice(start * 3, (start + count) * 3)
		for c in range(count * 3):
			pal[dest * 3 + c] = colors[c]
		for p in range(bytes.size()):
			if bytes[p] >= start and bytes[p] < start + count:
				bytes[p] = bytes[p] - start + dest
	var first = int(bytes[0]) if not bytes.is_empty() else 0
	var result = {"key":key,"signature":cache_key,"width":int(row.width),"height":int(row.height),"pixels":bytes,"palette":pal,"map_key":249 if first >= 10 and first < 246 else first}
	_images[cache_key] = result
	return result

func apd(stem: String) -> Dictionary:
	stem = stem.get_file().get_basename().to_upper()
	if FT2Content.active!=null and FT2Content.active.extensions!=null:stem=FT2Content.active.extensions.sprite_alias(stem)
	if not _apds.has(stem):
		var path = str(manifest.get("apds", {}).get(stem, ""))
		_apds[stem] = read_json(path) if path != "" else {}
		if _apds[stem].is_empty():
			missing["APD/" + stem] = true
	return _apds[stem]

static func is_apd_z_sheet(key: String) -> bool:
	#42CA50 inspects the filename's final letter before its extension. Z sheets
	#bypass the caller's normal palette callback and use42CAF0's16-color band.
	return key.replace("\\","/").get_file().get_basename().to_lower().ends_with("z")

func apd_image(key: String, remaps: Array = []) -> Dictionary:
	return image(key,[[10,16,208]] if is_apd_z_sheet(key) else remaps)

static func apd_palette_band(key: String, first: int, count: int) -> Vector2i:
	return Vector2i(208,16) if is_apd_z_sheet(key) else Vector2i(first,count)

func map_data(id: int) -> Dictionary:
	if FT2Content.active!=null and FT2Content.active.extensions!=null:
		var definition: Dictionary=FT2Content.active.extensions.map_by_id(id)
		if not definition.is_empty():return preload("res://scripts/extensions/ft2_extension_maps.gd").indexed(FT2Data.new(),definition,id)
	if not _maps.has(id):
		_maps[id] = read_json(str(manifest.get("maps", {}).get(str(id), "")))
	return _maps[id]
