class_name FT2Widgets
extends RefCounted
static func muldiv(value: int,multiplier: int,divisor: int) -> int:
	var product:=value*multiplier
	var quotient:int=(absi(product)+absi(divisor)/2)/absi(divisor)
	return -quotient if (product<0)!=(divisor<0) else quotient

static func dlu_rect(r: Array,origin: Vector2i=Vector2i.ZERO,base:Vector2i=Vector2i(7,12)) -> Rect2i:
	return Rect2i(origin+Vector2i(muldiv(int(r[0]),base.x,4),muldiv(int(r[1]),base.y,8)),Vector2i(muldiv(int(r[2]),base.x,4),muldiv(int(r[3]),base.y,8)))
## Measured WM_GETFONT/MapDialogRect on provided Win95, 96DPI.
static func dialog_base(resource:int)->Vector2i:
	if resource in [107,160]:return Vector2i(9,16)
	if resource in [117,124,144,145,151,152,153]:return Vector2i(8,15)
	if resource in [118,119,121,150]:return Vector2i(8,13)
	return Vector2i(7,12)
static func dialog_font(resource:int)->Dictionary:
	return {"family":"굴림","height":-dialog_base(resource).y,"weight":400,"italic":false}

static func wrap_lines(text:String,width:int,measure:Callable)->Array[String]:
	# Keep an ASCII word (including CD-ROM) together when it fits a line.
	# CJK characters remain individual break opportunities; oversized words split.
	var tokens:Array[String]=[];var word:=""
	for character in text:
		var code:=character.unicode_at(0)
		if code>32 and code<127:word+=character
		else:
			if not word.is_empty():tokens.append(word);word=""
			tokens.append(character)
	if not word.is_empty():tokens.append(word)
	var lines:Array[String]=[];var line:=""
	for token in tokens:
		if not line.is_empty() and int(measure.call(line+token))>width:
			while line.ends_with(" ") or line.ends_with("\t"):line=line.left(line.length()-1)
			lines.append(line);line=""
			if token==" " or token=="\t":continue
		if int(measure.call(token))>width:
			for character in token:
				if not line.is_empty() and int(measure.call(line+character))>width:lines.append(line);line=""
				line+=character
		else:line+=token
	lines.append(line)
	return lines
static func dialog_template(data,resource: int) -> Dictionary:
	var base := "data/port_ready/ui/FTO_O/dialog_%d_lang1042" % resource
	var parsed = data.read_json(base+".json")
	if not parsed is Dictionary: return {}
	var out: Dictionary = parsed.duplicate(true)
	var raw := FT2Content.bytes(data.resolve(base+".bin"))
	if raw.is_empty(): return out
	for control in out.get("controls",[]):
		var at := int(control.template_offset)+(24 if out.get("extended",false) else 18)
		if at+2 > raw.size(): continue
		if raw.decode_u16(at) == 65535: at += 4
		else:
			while at+2 <= raw.size() and raw.decode_u16(at) != 0: at += 2
			at += 2
		if at+2 > raw.size() or raw.decode_u16(at) == 65535: continue
		var end := at
		while end+2 <= raw.size() and raw.decode_u16(end) != 0: end += 2
		control.title = {"kind":"string","value":raw.slice(at,end).get_string_from_utf16()}
	return out
## Original403960: source SYSTEM.APD border and center cells on a16px grid.
static func game_panel(x: int,y: int,width: int,height: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in height+2:
		for column in width+2:
			var frame := 18
			if row == 0: frame = 2 if column == 0 else (6 if column == width+1 else 5)
			elif row == height+1: frame = 4 if column == 0 else (8 if column == width+1 else 9)
			elif column == 0: frame = 3
			elif column == width+1: frame = 7
			out.append({"op":"apd","stem":"SYSTEM","label":"","frame":frame,"pos":Vector2i(x+2+column*16,y+2+row*16),"mirror":false,"policy":"system"})
	return out
