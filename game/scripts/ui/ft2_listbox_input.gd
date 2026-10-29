extends RefCounted
## Win95 USER12:3DAE/0741, stock string LISTBOX124/160 only.
const SYSTEM_TIMER_ID:=-4
var encode:Callable
var decode:Callable
var double_click_ms:=500
var storage:=PackedByteArray([0])
var length:=0 # Source WORD0F52, distinct from the NUL-terminated storage.
var timer_active:=false
var due_ms:=0
var timer_dispatches:=0

func set_double_click_time(value:int)->void:
	var word:=value&65535
	double_click_ms=500 if word==0 else mini(word,5000) # USER3:6C80..6CA5.

func interval_ms()->int:return (double_click_ms<<2)&65535

func destroy_control()->void:
	storage=PackedByteArray([0]);length=0;timer_active=false;due_ms=0

func focus_lost()->void:
	# USER12:05F0 clears/kills only when logical prefix length is nonzero.
	if length>0:length=0;timer_active=false;due_ms=0

func dispatch_due(now_ms:int)->bool:
	# Delivery adapter for WM_SYSTIMER118/FFFC, never an inline WM_CHAR test.
	if not timer_active or now_ms<due_ms:return false
	length=0;timer_active=false;due_ms=0;timer_dispatches+=1
	return true

func _put(index:int,value:int)->void:
	if storage.size()<=index:storage.resize(index+1)
	storage[index]=value

func _cstring()->PackedByteArray:
	var end:=storage.find(0)
	return storage.slice(0,end if end>=0 else storage.size())

func _bytes(text:String)->PackedByteArray:
	return encode.call(text) if encode.is_valid() else text.to_utf8_buffer()

func _fold(bytes:PackedByteArray)->PackedByteArray:
	var out:=bytes.duplicate();var i:=0
	while i<out.size():
		if out[i]>=0x81 and out[i]<=0xfe and i+1<out.size():i+=2;continue
		if out[i]>=65 and out[i]<=90:out[i]+=32
		i+=1
	return out

func _find(rows:Array,needle:PackedByteArray,start:int)->int:
	if needle.is_empty() or rows.is_empty():return -1
	var folded:=_fold(needle)
	for step in rows.size():
		var index:=posmod(start+1+step,rows.size())
		var text:String=str(rows[index].get("text","")) if rows[index] is Dictionary else str(rows[index])
		var candidate:=_fold(_bytes(text))
		if candidate.size()>=folded.size() and candidate.slice(0,folded.size())==folded:return index
	return -1

func _arm(now_ms:int)->void:timer_active=true;due_ms=now_ms+interval_ms()

func _last_character_size()->int:
	var cursor:=0;var previous:=0
	while cursor<length:
		previous=cursor
		cursor+=2 if storage[cursor]>=0x81 and storage[cursor]<=0xfe else 1
	return 2 if storage[previous]>=0x81 and storage[previous]<=0xfe else 1

func wm_char(bytes:PackedByteArray,rows:Array,current:int,now_ms:int,control_down:bool=false)->Dictionary:
	var result:={"handled":true,"matched":false,"notify":false,"selection":current}
	if rows.is_empty() or bytes.is_empty():return result
	var input:=bytes.duplicate()
	if input.size()==1 and input[0]==27:
		length=0;_put(0,0);return result # Escape does not itself kill the timer.
	if input.size()==1 and input[0]==8:
		if length==0:return result
		var old_length:=length;length-=1;_put(old_length,0) # Intentional source old-index NUL.
		_arm(now_ms)
	else:
		if control_down and input.size()==1 and input[0]<32:input[0]+=64
		if length==0x100:result["capacity_rejected"]=true;return result
		for byte in input:_put(length,byte);length=(length+1)&65535
		_put(length,0);_arm(now_ms)
	var found:=_find(rows,_cstring(),-1)
	if found<0 and length>0:
		# Source CharPrev/DBCS branch: remove the last input from the logical count,
		# retaining its bytes until the next append overwrites them.
		var count:=_last_character_size()
		if length<count:return result
		length-=count
		if length==count and storage.slice(0,count)==storage.slice(count,count*2):
			_put(count,0);found=_find(rows,_cstring(),current)
	if found>=0:
		result.selection=found;result.matched=true;result.notify=true # Fake key401 also notifies unchanged matches.
	return result

func snapshot()->Dictionary:
	var prefix:=storage.slice(0,length)
	return {"prefix_hex":prefix.hex_encode(),"prefix":decode.call(prefix) if decode.is_valid() else prefix.get_string_from_utf8(),"length_bytes":length,"cstring_hex":_cstring().hex_encode(),"storage_hex":storage.hex_encode(),"timer_active":timer_active,"due_ms":due_ms,"interval_ms":interval_ms(),"timer_id":SYSTEM_TIMER_ID,"timer_dispatches":timer_dispatches}
