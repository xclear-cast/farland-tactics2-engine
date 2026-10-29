class_name FT2OverviewProgram
extends RefCounted
##401070/401AD0 typed operations; numeric IDs are symbols, not live pointers.
const DEST = 0x11100000
const SCRATCH = 0x11101000
const FRONT = 0x11102000
const WINDOW = 0x7001
const CACHE = 0x710000
static func s32(value: int) -> int:
	var v = value&0xffffffff
	return v-0x100000000 if v >= 0x80000000 else v
static func div0(a: int,b: int) -> int:
	assert(b != 0)
	var q: int = absi(a)/absi(b)
	return -q if (a < 0) != (b < 0) else q
static func ratio(a: int,b: int,c: int) -> int: return div0(s32(a*b),c)

static func constrain(input: Array,current: Array,extra: Array,world: Array,fullscreen: bool) -> Array:
	var p = input.duplicate()
	var l = int(current[0])
	var t = int(current[1])
	var r = int(current[2])
	var b = int(current[3])
	var ew = int(extra[0])
	var eh = int(extra[1])
	var ww = int(world[0])
	var wh = int(world[1])
	if not fullscreen and r-int(p[4]) == l and b-int(p[5]) == t: return p
	if int(p[5])-eh > 480: p[5] = eh+480
	p[4] = maxi(100,mini(ew+ratio(int(p[5])-eh,ww,wh),int(p[4])))
	if int(p[4])-ew > 640: p[4] = ew+640
	p[5] = eh+ratio(int(p[4])-ew,wh,ww)
	if int(p[2]) != l: p[2] = r-int(p[4])
	if int(p[3]) != t: p[3] = b-int(p[5])
	return p

static func fit(world: Vector2i) -> Rect2i:
	var p = constrain([0,0,0,0,640,480,0],[0,0,640,480],[0,0],[world.x,world.y],true)
	return Rect2i(div0(640-int(p[4]),2),div0(480-int(p[5]),2),int(p[4]),int(p[5]))

static func fullscreen_input(msg: int,wp: int,cursor: Vector2i,rect: Rect2i,world: Vector2i,mode: int = 6) -> Dictionary:
	var out = {"return":0,"mode":mode,"cursor_id":-1,"camera":[]}
	if msg == 0x111:
		out["return"] = 1
		if (wp&65535) == 40030: out.mode = 1
	elif msg == 0x200:
		out["return"] = 1
		out.cursor_id = 149 if rect.has_point(cursor) else 148
	elif msg == 0x201:
		out["return"] = 1
		if rect.has_point(cursor):
			out.camera = [[ratio(cursor.x-rect.position.x,world.x,rect.size.x),ratio(cursor.y-rect.position.y,world.y,rect.size.y),0,0]]
			out.cursor_id = 102
			out.mode = 1
	elif msg == 0x204:
		out["return"] = 1
		out.cursor_id = 102
		out.mode = 1
	return out

static func window_drag(msg: int,captured: bool,cursor: Vector2i,client: Vector2i,world: Vector2i) -> Dictionary:
	var result = {"return":0,"capture":captured,"camera":[],"service":false}
	if msg == 0x201: result.capture = true
	if msg == 0x201 or (msg == 0x200 and captured):
		result.camera = [[ratio(maxi(cursor.x,0),world.x,client.x),ratio(maxi(cursor.y,0),world.y,client.y),0,0]]
		result.service = true
	elif msg in [0x202,0xa2]: result.capture = false
	elif msg == 0x200: result["return"] = 0x1234 # DefWindowProc evidence adapter.
	return result

static func bitmap(out: Array,dest: int,x: int,y: int,source: int,rect: Variant = null) -> void:
	out.append({"op":"bitmap","dest":dest,"xy":[x,y],"source":source,"rect":rect})
static func blit(out: Array,dest: int,x: int,y: int,source: int,rect: Variant = null,flags: int = 1) -> void:
	out.append({"op":"surface_blit","dest":dest,"xy":[x,y],"source":source,"rect":rect,"flags":flags})
static func stretch(out: Array,dest_rect: Array,source: int,source_rect: Array,flags: int = 0x1000000) -> void:
	out.append({"op":"DDraw_Blt","dest":DEST,"dest_rect":dest_rect,"source":source,"source_rect":source_rect,"flags":flags})
static func fill(out: Array,rect: Variant,color: int,dest: int = DEST) -> void:
	out.append({"op":"fill","dest":dest,"rect":rect,"color":color})

static func build(mid: int,fullscreen: bool,world: Vector2i,target: Vector2i,sources: Dictionary,units: Array = [],projection: Callable = Callable(),client_origin: Vector2i = Vector2i(14,43)) -> Array:
	var tw = target.x
	var th = target.y
	var ww = world.x
	var wh = world.y
	var A = int(sources.get("A",0))
	var layers: Array = sources.get("layers",[0,0,0,0,0,0])
	var B = int(layers[0])
	var C = int(layers[1])
	var D = int(sources.get("D",0))
	var bw = int(sources.get("width",640))
	var bh = int(sources.get("height",480))
	var center = Vector2i(div0(640-tw,2),div0(480-th,2)) if fullscreen else Vector2i.ZERO
	var out: Array = []
	if fullscreen: fill(out,null,0)
	var ratioh = ratio(th,640,tw)
	if mid == 26:
		if fullscreen: bitmap(out,DEST,0,center.y+th-bh,A)
		else:
			if A != 0: bitmap(out,SCRATCH,0,ratioh-bh,A)
			stretch(out,[0,0,tw,th],SCRATCH,[0,0,640,ratioh])
	elif mid in [35,36,37]:
		fill(out,null,143,SCRATCH)
		if B != 0:
			for k in range(11):
				var n = 10-k
				var width = 320+32*k
				var height = 32 if n >= 5 else 48
				var sy = 16*(20-2*k+mini(n,5))
				for x in range(0,640,width): blit(out,SCRATCH,x,160-16*k,B,[0,sy,width,sy+height])
		stretch(out,[0,0,tw,th],SCRATCH,[0,0,640,ratioh])
	elif mid in [42,57]:
		if B != 0:
			for y in range(0,th,170):
				for x in range(0,tw,340): blit(out,DEST,x,y,B,null,0)
	elif mid == 52:
		if A != 0: bitmap(out,SCRATCH,0,0,A)
		if B != 0: blit(out,SCRATCH,0,0,B)
		if C != 0: blit(out,SCRATCH,400,0,C)
		stretch(out,[0,0,tw,th],SCRATCH,[0,0,640,ratioh])
	elif mid == 54:
		if D != 0 and B != 0:
			bitmap(out,SCRATCH,0,0,D,[384,320,1024,800])
			for k in range(4): blit(out,SCRATCH,192*k,288-96*k,B)
			stretch(out,[0,0,tw,th],SCRATCH,[0,0,640,480])
	elif mid == 69:
		var crop = ((bw-640)&0xffffffff)>>1
		bitmap(out,SCRATCH,0,0,A,[crop,0,crop+640,bh])
		stretch(out,[0,0,tw,ratio(tw,bh,640)],SCRATCH,[0,0,640,bh])
		for i in [2,1,0]:
			var height = 112 if i > 0 else 80
			var dw = ratio(480,tw,720)
			var dh = ratio(height,tw,720)
			var y = th+i*ratio(dh,4,-7)-ratio(tw,80,720)
			if int(layers[2*i]) != 0: stretch(out,[0,y,dw,y+dh],int(layers[2*i]),[0,0,480,height],0x1008000)
			if int(layers[2*i+1]) != 0: stretch(out,[dw,y,tw,y+dh],int(layers[2*i+1]),[0,0,ratio(tw-dw,480,dw),height],0x1008000)
	for y in range(0,wh,480):
		for x in range(0,ww,640):
			var w = mini(640,ww-x)
			var h = mini(480,wh-y)
			var tx = ratio(x,tw,ww)+center.x
			var ty = ratio(y,th,wh)+center.y
			var rect = [tx,ty,mini(640,tx+ratio(w,tw,ww)+1),mini(480,ty+ratio(h,th,wh)+1)]
			if A != 0 and not mid in [26,52,54,69]:
				bitmap(out,SCRATCH,0,0,A,[x,y,x+w,y+h])
				stretch(out,rect,SCRATCH,[0,0,w,h])
			stretch(out,rect,CACHE+div0(x,640)*5+div0(y,480),[0,0,w,h],0x1008000)
	for slot in range(units.size()):
		var unit: PackedByteArray = units[slot]
		var kind = unit.decode_u16(0)
		var state = unit.decode_u16(16)
		var control = unit.decode_u16(18)
		if kind == 0 or state == 9 or (control == 7 and kind != 8): continue
		var world_point = Vector2i(unit.decode_s32(8),unit.decode_s32(12))
		var p: Vector2i = projection.call(world_point) if projection.is_valid() else Vector2i((world_point.x-world_point.y)*32+div0(ww,2),(world_point.x+world_point.y)*16)
		var px = ratio(p.x,tw,ww)+center.x
		var py = ratio(p.y,th,wh)+center.y
		var color = 26 if control == 7 else 24 if slot < 10 else 20
		fill(out,[px-1,py,px+5,py+4],0)
		fill(out,[px,py-1,px+4,py+5],0)
		fill(out,[px,py,px+4,py+4],color)
	if fullscreen: out.append({"op":"0x4189a0","args":[]})
	else:
		out.append({"op":"0x418ba0","args":[WINDOW]})
		blit(out,FRONT,client_origin.x,client_origin.y,DEST,[0,0,tw,th],0)
	return out
