class_name FT2ExtensionMaps
extends RefCounted
## Build a new 1-based board from local original tile references, never files.

static func _template_score(cell: Dictionary) -> int:
	var score := int(cell.get("part_count",0))*100+absi(int(cell.get("H",0)))*20
	for part in cell.get("parts",[]):
		var rect: Array = part.get("source_rect_xyxy",[0,0,0,0])
		score += maxi(0,int(rect[3])-int(rect[1]))
	return score

static func normalized(data, definition: Dictionary, numeric_id: int) -> Dictionary:
	var width := int(definition.get("width",8))
	var height := int(definition.get("height",8))
	if width<1 or height<1 or width>64 or height>64: return {}
	var base_id := int(definition.get("base_map",40))
	if base_id==numeric_id: return {}
	var base: Dictionary = data.load_map(base_id)
	if base.is_empty(): return {}
	var templates: Dictionary = {}
	var fallback: Dictionary = {}
	for original in base.get("cells",[]):
		var cell: Dictionary = original
		if int(cell.get("flag2_raw",0))!=0 or int(cell.get("flag3_raw",0))!=0 or cell.get("parts",[]).is_empty(): continue
		var terrain := int(cell.get("L",1))
		if fallback.is_empty() or _template_score(cell)<_template_score(fallback): fallback=cell
		if not templates.has(terrain) or _template_score(cell)<_template_score(templates[terrain]): templates[terrain]=cell
	if fallback.is_empty(): return {}
	var changes: Dictionary = {}
	for row in definition.get("cells",[]): changes[Vector2i(int(row.x),int(row.y))]=row
	var bounds := [-height-1,0,width+height+2,height+1]
	var base_xy := [(int(bounds[1])-int(bounds[0]))*32,-(int(bounds[1])+int(bounds[0]))*16]
	var side := maxi(width,height)+1
	var lookup: Array = [];lookup.resize(side*side);lookup.fill(0)
	var cells: Array = []
	for y in range(1,height+1):
		for x in range(1,width+1):
			var change: Dictionary = changes.get(Vector2i(x,y),{})
			var terrain := int(change.get("terrain",1))
			var template: Dictionary = templates.get(terrain,templates.get(1,fallback))
			var parts: Array = []
			for original_part in template.get("parts",[]):
				parts.append({"atlas_index":int(original_part.atlas_index),"render_pass_flag":int(original_part.render_pass_flag),
					"source_rect_xyxy":original_part.source_rect_xyxy.duplicate(),"offset_xy":original_part.offset_xy.duplicate()})
			var ordinal := cells.size()
			cells.append({"index":ordinal,"lookup_ordinal":y*side+x,"x":x,"y":y,"H":int(change.get("height",0)),
				"L":terrain,"flag2_raw":0,"flag3_raw":0,"part_count":parts.size(),"parts":parts})
			lookup[y*side+x]=ordinal+1
	var order: Array = []
	for index in range(cells.size()): order.append(index)
	order.sort_custom(func(a,b):
		var ca: Dictionary=cells[int(a)];var cb: Dictionary=cells[int(b)]
		return int(ca.x)+int(ca.y)<int(cb.x)+int(cb.y) if int(ca.x)+int(ca.y)!=int(cb.x)+int(cb.y) else int(ca.x)<int(cb.x))
	var header: Array = base.get("header_0x20_eight_signed_dwords",[0,0,0,0,0,0,0,0]).duplicate()
	if header.size()<8: header.resize(8)
	for i in range(4): header[i+4]=bounds[i]
	return {"schema_version":1,"source_type":"extension-grid","source_map_id":numeric_id,"extension_id":str(definition.get("global_id",definition.get("id",""))),
		"base_map":base_id,"width":width,"height":height,"world_lookup_side":side,"cell_count":cells.size(),
		"background_bitmap_name":str(base.get("background_bitmap_name","")),"atlas_names":base.get("atlas_names",[]).duplicate(),
		"header_0x20_eight_signed_dwords":header,"header_map_bounds_ltrb":bounds,"base_offset_xy":base_xy,
		"world_lookup_y_major_1based_zero_invalid":lookup,"cells":cells,"static_layer_draw_cell_indices":order}

static func indexed(data, definition: Dictionary, numeric_id: int) -> Dictionary:
	var source := normalized(data,definition,numeric_id)
	if source.is_empty(): return {}
	var cells: Array = []
	for cell in source.cells:
		var parts: Array = []
		for part in cell.parts:
			parts.append([part.atlas_index,part.render_pass_flag,part.source_rect_xyxy[0],part.source_rect_xyxy[1],
				part.source_rect_xyxy[2],part.source_rect_xyxy[3],part.offset_xy[0],part.offset_xy[1]])
		cells.append([cell.x,cell.y,cell.H,cell.flag2_raw,cell.flag3_raw,cell.L,parts])
	var atlases: Array = []
	for name in source.atlas_names: atlases.append(("map/"+str(name)).to_lower())
	var result := {"id":numeric_id,"extension_id":source.extension_id,"width":source.width,"height":source.height,
		"side":source.world_lookup_side,"base":source.base_offset_xy,"bounds":source.header_map_bounds_ltrb,
		"header":source.header_0x20_eight_signed_dwords,"background":("map/"+str(source.background_bitmap_name)).to_lower(),
		"atlases":atlases,"static_order":source.static_layer_draw_cell_indices,"cells":cells}
	var bounds: Array = source.header_map_bounds_ltrb
	var width := maxi(640,(int(bounds[2])-int(bounds[3])-int(bounds[0])+int(bounds[1]))*32)
	var height := maxi(480,(int(bounds[3])-int(bounds[1])-int(bounds[0])+int(bounds[2]))*16)
	var surface := FT2IndexedSurface.new(width,height,0)
	var assets := FT2IndexedAssets.new()
	for ordinal in result.static_order:
		var cell: Array = cells[int(ordinal)]
		var anchor := Vector2i((int(cell[0])-int(cell[1]))*32+int(result.base[0]),(int(cell[0])+int(cell[1]))*16+int(result.base[1])-int(cell[2])*8)
		for part in cell[6]:
			var index := int(part[0])
			if index<0 or index>=atlases.size(): continue
			var image := assets.image(str(atlases[index]),[[10,112,32]])
			if image.is_empty(): continue
			var rect := Rect2i(int(part[2]),int(part[3]),int(part[4])-int(part[2]),int(part[5])-int(part[3]))
			surface.blit(image,rect,anchor+Vector2i(int(part[6]),int(part[7])),int(image.map_key),0,0,Rect2i(0,0,width,height))
	# A new authored board has explicit visible cells, independent of the base
	# map's background. These procedural edges contain no original asset data.
	if bool(definition.get("show_grid",true)):
		for cell in cells:
			var center:=Vector2i((int(cell[0])-int(cell[1]))*32+int(result.base[0]),(int(cell[0])+int(cell[1]))*16+int(result.base[1])-int(cell[2])*8)
			var corners: Array=[center+Vector2i(-32,0),center+Vector2i(0,-16),center+Vector2i(32,0),center+Vector2i(0,16)]
			for edge in range(4):surface.line(corners[edge],corners[(edge+1)%4],254)
	result.baked={"width":width,"height":height,"pixels":surface.pixels,"transparent":0}
	return result
