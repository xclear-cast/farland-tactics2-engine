class_name FT2ScrollController
extends RefCounted
## USER14:08CC/051C/07A0 input/timer contract. The receiver owns scroll position.
## Emits Win32 SB_* codes; no UI/model/SceneTree/Input mutation.
var clock_provider:Callable
var source_double_click_ms:=500
var capture:="" #Compatible with existing UI "scroll"/"thumb" capture strings.
var part:=""
var inside:=false
var pointer:=Vector2i.ZERO
var _due:=-1
var _period:=0
var _grab_offset:=0
var _original_position:=0
var _position:=0

func configure(provider:Callable=Callable(),double_click_ms:int=500)->void:
	#Configuration updates do not discard an active capture or restart its timer.
	clock_provider=provider
	var value:=double_click_ms&0xFFFF
	source_double_click_ms=mini(5000,500 if value==0 else value)

func _now()->int:return int(clock_provider.call()) if clock_provider.is_valid() else Time.get_ticks_msec()
func initial_delay_ms()->int:return int((source_double_click_ms*4)/5)
func repeat_delay_ms()->int:return initial_delay_ms()>>3
func _registered_delay(value:int)->int:return maxi(1,value) #USER3:6120 zero interval becomes1.

static func _region(name:String,g:Dictionary)->Rect2i:
	var rect:Rect2i=g.rect
	var track:Rect2i=g.track
	var thumb:Rect2i=g.thumb
	match name:
		"line_up":return Rect2i(rect.position,Vector2i(rect.size.x,maxi(0,track.position.y-rect.position.y)))
		"line_down":return Rect2i(Vector2i(rect.position.x,track.end.y),Vector2i(rect.size.x,maxi(0,rect.end.y-track.end.y)))
		"page_up":return Rect2i(track.position,Vector2i(track.size.x,maxi(0,thumb.position.y-track.position.y)))
		"page_down":return Rect2i(Vector2i(track.position.x,thumb.end.y),Vector2i(track.size.x,maxi(0,track.end.y-thumb.end.y)))
		"thumb":return thumb
	return Rect2i()

static func hit_part(point:Vector2i,g:Dictionary)->String:
	if g.is_empty() or not Rect2i(g.rect).has_point(point):return ""
	for name in ["line_up","line_down","thumb","page_up","page_down"]:
		if _region(name,g).has_point(point):return name
	return ""

func _step(reason:String)->Dictionary:
	return {"code":{"line_up":0,"line_down":1,"page_up":2,"page_down":3}[part],"reason":reason}

func press(point:Vector2i,g:Dictionary,current_position:int=0)->Array[Dictionary]:
	var out:Array[Dictionary]=[]
	if capture!="":return out
	part=hit_part(point,g)
	if part=="":return out
	pointer=point;inside=true;_original_position=current_position;_position=current_position
	if part=="thumb":
		capture="thumb";_grab_offset=point.y-Rect2i(g.thumb).position.y
		out.append({"code":5,"position":current_position,"reason":"thumb_begin"}) #14:0CFE.
	else:
		capture="scroll";_period=_registered_delay(initial_delay_ms());_due=_now()+_period
		out.append(_step("down"))
	return out

func move(point:Vector2i,g:Dictionary)->Array[Dictionary]:
	var out:Array[Dictionary]=[]
	if capture=="":return out
	pointer=point
	if capture=="thumb":
		var track:Rect2i=g.track
		var thumb:Rect2i=g.thumb
		var travel:=track.size.y-thumb.size.y
		if travel<=0:return out
		var pixel:=clampi(point.y-_grab_offset-track.position.y,0,travel)
		var maximum:=maxi(0,int(g.get("max_top",0)))
		var value:=int((pixel*maximum+int(travel/2))/travel) #Positive MulDiv nearest.
		#14:0C74..0CAF inflates the whole vertical bar by2barwidth and
		#2SM_CYVTHUMB;9AD uses the originalthumb pixel outside this rectangle.
		var rect:Rect2i=g.rect
		var pad_y:=2*int(g.get("source_nominal_thumb_px",16)) #Observed providedWin95 profile.
		var drag_bounds:Rect2i=g.get("drag_bounds",rect.grow_individual(2*rect.size.x,pad_y,2*rect.size.x,pad_y))
		if not drag_bounds.has_point(point):value=_original_position
		if value!=_position:
			_position=value;out.append({"code":5,"position":value,"reason":"thumb_track"})
		return out
	var previous:=inside
	inside=_region(part,g).has_point(point)
	#08CC mouseMove inside->inside does nothing; outside->inside arms repeat
	#interval and sends one scroll immediately. No initial-delay restart.
	if inside and not previous:
		_period=_registered_delay(repeat_delay_ms());_due=_now()+_period;out.append(_step("reenter"))
	return out

func advance(g:Dictionary)->Array[Dictionary]:
	var out:Array[Dictionary]=[]
	if capture!="scroll" or _due<0:return out
	var now:=_now()
	if now<_due:return out
	inside=_region(part,g).has_point(pointer)
	if inside:
		out.append(_step("timer"));_period=_registered_delay(repeat_delay_ms())
	#051C registers a new interval from this delivery; never burst-catch up
	#missed deadlines. Outside suppresses scroll; reentry is serviced by move.
	_due=now+_period
	return out

func release(cancelled:bool=false)->Array[Dictionary]:
	var out:Array[Dictionary]=[]
	if capture=="":return out
	if capture=="thumb":out.append({"code":4,"position":_original_position if cancelled else _position,"reason":"cancel" if cancelled else "thumb_position"})
	out.append({"code":8,"reason":"cancel" if cancelled else "end_scroll"})
	capture="";part="";inside=false;_due=-1;_period=0
	return out

func cancel()->Array[Dictionary]:return release(true)
func pressed_part()->String:return part if inside and capture!="" else ""
func snapshot()->Dictionary:
	return {"capture":capture,"part":part,"inside":inside,"pointer":pointer,"deadline":_due,"period":_period,"position":_position,"original_position":_original_position,
		"source_double_click_ms":source_double_click_ms,"initial_delay_ms":initial_delay_ms(),"repeat_delay_ms":repeat_delay_ms()}
func dispose()->void:
	release(true);clock_provider=Callable()
