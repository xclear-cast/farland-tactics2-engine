extends RefCounted
## Native Win95 resource124 close/scroll masks, startup124/ST124.BIN.
const CLOSE=["fffffffffffffff0","f777777777777780","f777777777777780","f777007777007780","f777700770077780","f777770000777780","f777777007777780","f777770000777780","f777700770077780","f777007777007780","f777777777777780","f777777777777780","f888888888888880","0000000000000000"]
const UP=["7777777777777770","7fffffffffffff80","7f77777777777780","7f77777777777780","7f77777777777780","7f77777777777780","7f77777077777780","7f77770007777780","7f77700000777780","7f77000000077780","7f77777777777780","7f77777777777780","7f77777777777780","7f77777777777780","7888888888888880","0000000000000000"]
const DOWN=["7777777777777770","7fffffffffffff80","7f77777777777780","7f77777777777780","7f77777777777780","7f77777777777780","7f77000000077780","7f77700000777780","7f77770007777780","7f77777077777780","7f77777777777780","7f77777777777780","7f77777777777780","7f77777777777780","7888888888888880","0000000000000000"]
static func mask(out:Array[Dictionary],point:Vector2i,rows:Array)->void:
	for y in rows.size():
		for x in rows[y].length():out.append({"op":"rect","rect":Rect2i(point+Vector2i(x,y),Vector2i.ONE),"filled":true,"color":{"0":0,"8":248,"7":7,"f":255}[rows[y][x]]})
static func scrollbar(out:Array[Dictionary],rect:Rect2i,top:int,page:int,count:int)->Dictionary:
	var geometry:=scroll_geometry(rect,top,page,count);var track:Rect2i=geometry.track
	for y in track.size.y:
		for x in track.size.x:out.append({"op":"rect","rect":Rect2i(track.position+Vector2i(x,y),Vector2i.ONE),"filled":true,"color":255 if ((x+y)&1)==1 else 7})
	mask(out,rect.position,UP);mask(out,rect.end-Vector2i(16,16),DOWN)
	var thumb:Rect2i=geometry.thumb;var thumb_height:=thumb.size.y
	var lines:Array=[]
	for y in thumb_height:
		lines.append("7777777777777770"if y==0 else("0000000000000000"if y==thumb_height-1 else("7888888888888880"if y==thumb_height-2 else("7fffffffffffff80"if y==1 else"7f77777777777780"))))
	mask(out,thumb.position,lines)
	return geometry
static func scroll_geometry(rect:Rect2i,top:int,page:int,count:int)->Dictionary:
	var track:=Rect2i(rect.position+Vector2i(0,16),rect.size-Vector2i(0,32))
	var thumb_height:=FT2Widgets.muldiv(track.size.y,page,count)
	var thumb:=Rect2i(track.position+Vector2i(0,FT2Widgets.muldiv(track.size.y-thumb_height,top,maxi(1,count-page))),Vector2i(16,thumb_height))
	return {"rect":rect,"track":track,"thumb":thumb,"page":page,"max_top":maxi(0,count-page)}
