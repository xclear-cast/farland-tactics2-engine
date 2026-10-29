extends RefCounted
## Exact 13px Win95 USER checkbox/radio masks measured in the provided OS.
const CHECK_BASE = ["888888888888f", "800000000007f", "80fffffffff7f", "80fffffffff7f", "80fffffffff7f", "80fffffffff7f", "80fffffffff7f", "80fffffffff7f", "80fffffffff7f", "80fffffffff7f", "80fffffffff7f", "877777777777f", "fffffffffffff"]
const RADIO_BASE = ["7777788887777", "7778800008877", "77800ffff00f7", "7780ffffff7f7", "780ffffffff7f", "780ffffffff7f", "780ffffffff7f", "780ffffffff7f", "7780ffffff7f7", "77877ffff77f7", "777ff7777ff77", "77777ffff7777", "7777777777777"]
const CHECK_MARK = [[9,3],[8,4],[9,4],[3,5],[7,5],[8,5],[9,5],[3,6],[4,6],[6,6],[7,6],[8,6],[3,7],[4,7],[5,7],[6,7],[7,7],[4,8],[5,8],[6,8],[5,9]]
const RADIO_MARK = [[6,4],[7,4],[5,5],[6,5],[7,5],[8,5],[5,6],[6,6],[7,6],[8,6],[6,7],[7,7]]
static func glyph(out:Array[Dictionary],point:Vector2i,radio:bool,checked:bool,disabled:bool,pressed:bool)->void:
	var rows:Array=RADIO_BASE if radio else CHECK_BASE
	for y in 13:
		for x in 13:
			var color:int={"0":0,"8":248,"7":7,"f":255}[rows[y][x]]
			if (disabled or pressed) and color==255 and x>=2 and x<=10 and y>=2 and y<=(9 if radio else 10):color=7
			out.append({"op":"rect","rect":Rect2i(point+Vector2i(x,y),Vector2i.ONE),"filled":true,"color":color})
	if checked:
		for xy in (RADIO_MARK if radio else CHECK_MARK):out.append({"op":"rect","rect":Rect2i(point+Vector2i(xy[0],xy[1]),Vector2i.ONE),"filled":true,"color":248 if disabled else 0})

static func raised(out:Array[Dictionary],r:Rect2i)->void:
	out.append({"op":"rect","rect":r,"filled":true,"color":7})
	out.append({"op":"line","from":r.position,"to":Vector2i(r.end.x-2,r.position.y),"color":255})
	out.append({"op":"line","from":r.position,"to":Vector2i(r.position.x,r.end.y-2),"color":255})
	out.append({"op":"line","from":Vector2i(r.end.x-1,r.position.y),"to":r.end-Vector2i.ONE,"color":0})
	out.append({"op":"line","from":Vector2i(r.position.x,r.end.y-1),"to":r.end-Vector2i.ONE,"color":0})
	out.append({"op":"line","from":Vector2i(r.end.x-2,r.position.y+1),"to":r.end-Vector2i(2,2),"color":248})
	out.append({"op":"line","from":Vector2i(r.position.x+1,r.end.y-2),"to":r.end-Vector2i(2,2),"color":248})

static func button(out:Array[Dictionary],r:Rect2i,is_default:bool,pressed:bool)->void:
	if is_default:
		out.append({"op":"rect","rect":r,"filled":true,"color":0});r=Rect2i(r.position+Vector2i.ONE,r.size-Vector2i(2,2))
	if pressed:
		out.append({"op":"rect","rect":r,"filled":true,"color":7})
		out.append({"op":"rect","rect":r,"filled":false,"color":248})
	else:raised(out,r)

const SPIN_ROWS = [
	["8888888888888888f", "0000000000000007f", "7777777777777707f", "7ffffffffffff807f", "7f77777777777807f", "7f77777777777807f", "7f77777077777807f", "7f77770007777807f", "7f77777777777807f", "7888888888888807f", "0000000000000007f", "7777777777777777f", "7777777777777707f", "7ffffffffffff807f", "7f77777777777807f", "7f77770007777807f", "7f77777077777807f", "7f77777777777807f", "7f77777777777807f", "7888888888888807f", "0000000000000007f", "7777777777777777f", "fffffffffffffffff"],
	["8888888888888888f", "0000000000000007f", "88888888888888f7f", "80000000000007f7f", "80777777777777f7f", "80777777777777f7f", "80777777777777f7f", "80777777077777f7f", "80777770007777f7f", "87777777777777f7f", "fffffffffffffff7f", "7777777777777777f", "7777777777777707f", "7ffffffffffff807f", "7f77777777777807f", "7f77770007777807f", "7f77777077777807f", "7f77777777777807f", "7f77777777777807f", "7888888888888807f", "0000000000000007f", "7777777777777777f", "fffffffffffffffff"],
	["8888888888888888f", "0000000000000007f", "7777777777777707f", "7ffffffffffff807f", "7f77777777777807f", "7f77777777777807f", "7f77777077777807f", "7f77770007777807f", "7f77777777777807f", "7888888888888807f", "0000000000000007f", "7777777777777777f", "88888888888888f7f", "80000000000007f7f", "80777777777777f7f", "80777777777777f7f", "80777770007777f7f", "80777777077777f7f", "80777777777777f7f", "87777777777777f7f", "fffffffffffffff7f", "7777777777777777f", "fffffffffffffffff"],
]
static func spin(out:Array[Dictionary],point:Vector2i,pressed:int)->void:
	var rows:Array=SPIN_ROWS[1 if pressed>0 else (2 if pressed<0 else 0)]
	for y in 23:
		for x in 17:out.append({"op":"rect","rect":Rect2i(point+Vector2i(x,y),Vector2i.ONE),"filled":true,"color":{"0":0,"8":248,"7":7,"f":255}[rows[y][x]]})

static func edit(out:Array[Dictionary],r:Rect2i)->void:
	out.append({"op":"rect","rect":r,"filled":true,"color":255})
	for depth in 2:
		var box:=Rect2i(r.position+Vector2i(depth,depth),r.size-Vector2i(depth*2,depth*2))
		out.append({"op":"line","from":box.position,"to":Vector2i(box.end.x-1,box.position.y),"color":248 if depth==0 else 0})
		out.append({"op":"line","from":box.position,"to":Vector2i(box.position.x,box.end.y-1),"color":248 if depth==0 else 0})
		out.append({"op":"line","from":Vector2i(box.end.x-1,box.position.y),"to":box.end-Vector2i.ONE,"color":255 if depth==0 else 7})
		out.append({"op":"line","from":Vector2i(box.position.x,box.end.y-1),"to":box.end-Vector2i.ONE,"color":255 if depth==0 else 7})

## The same native inset measured on124 is used by stock and owner-drawn LISTBOX.
## WS_VSCROLL hides when all rows fit (these resources omit LBS_DISABLENOSCROLL).
static func listbox_geometry(r:Rect2i,row_height:int,count:int,top:int,vertical_scroll:bool=true)->Dictionary:
	var inner:=Rect2i(r.position+Vector2i(2,2),r.size-Vector2i(4,4))
	var page:=maxi(1,int(inner.size.y/maxi(1,row_height)))
	var paint_rows:=maxi(1,int((inner.size.y+maxi(1,row_height)-1)/maxi(1,row_height)))
	var has_scroll:=vertical_scroll and count>page
	var content:=Rect2i(inner.position,inner.size-Vector2i(16 if has_scroll else 0,0))
	var bar:=Rect2i(inner.end-Vector2i(16,inner.size.y),Vector2i(16,inner.size.y)) if has_scroll else Rect2i()
	return {"outer":r,"inner":inner,"content":content,"page":page,"paint_rows":paint_rows,"max_top":maxi(0,count-page),"top":clampi(top,0,maxi(0,count-page)),"scrollbar":bar}

static func listbox_frame(out:Array[Dictionary],r:Rect2i,row_height:int,count:int,top:int,vertical_scroll:bool=true)->Dictionary:
	var geometry:=listbox_geometry(r,row_height,count,top,vertical_scroll)
	edit(out,r)
	if geometry.scrollbar.size.x>0:
		geometry["scroll_geometry"]=preload("res://scripts/ui/ft2_stage_widgets.gd").scrollbar(out,geometry.scrollbar,int(geometry.top),int(geometry.page),count)
	return geometry
