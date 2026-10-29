extends RefCounted
## Native callback40CC60, string pointers449A08..449A48, PEinitial449A4C=1.
signal finished(result:int)
const ROWS:Array[String]=["01:일을 주십시오!","02:아빠는 걱정꾼","03:나 시집가요","04:사랑하는 카트린느","05:생각을 노래로","06:역습! 카트린느","07:광산의 마수","08:빛을 찾아서...","09:영예는 누구의 손에?","10:남자는 강하고 늠름하게!","11:당신은 누구??","12:먼 훗날의 약속","13:최후의 휴일","14:해상의 결전","15:암흑가","16:단 하나의 진실","17:시간을 관리하는 자"]
var selection:=0
var stage_value:=1
var ended:=false
var result:=0

func message(message_id:int,wparam:int=0)->int:
	match message_id:
		0x110:selection=0;ended=false;return 1
		0x10:_end(-1);return 0
		0x111:
			var control:=wparam&65535;var notification:=(wparam>>16)&65535
			if control==1:_end(stage_value)
			elif control==2:_end(0)
			elif control==1051 and notification in [1,2] and selection>=0 and selection<ROWS.size():
				var text:=ROWS[selection]
				stage_value=10*(text.unicode_at(0)-48)+text.unicode_at(1)-48
				if notification==2:message(0x111,1) #46D688 is SendMessageA: synchronous nested IDOK.
			return 1
	return 0

func _end(value:int)->void:
	result=value;ended=true;finished.emit(value)
