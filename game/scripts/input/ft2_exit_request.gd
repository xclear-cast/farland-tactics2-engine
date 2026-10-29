extends RefCounted
## Main WM_CLOSE40DDDB:430020 confirmation; only result6 requests destruction.
signal accepted
signal cancelled
const Interface=preload("res://scripts/ui/ft2_interface.gd")
const PROMPT="종료해도 좋습니까?" #449C70, original CP949 bytes.
var active:=false
var dialog_ui
var requests:=0

func configure(store,battle,vm)->void:
	# This is a nested confirmation, not another subscriber to battle/VM signals.
	dialog_ui=Interface.new();dialog_ui.data=store
	dialog_ui._battle_ref=weakref(battle);dialog_ui._vm_ref=weakref(vm)
	dialog_ui.persistence_enabled=false
	dialog_ui.quit_requested.connect(_accept)

func request()->void:
	if active:return
	requests+=1;active=true
	dialog_ui._open("quit",126,PROMPT)

func handle_input(event:InputEvent)->void:
	if not active:return
	dialog_ui.handle_input(event)
	if active and dialog_ui.dialog=="":
		active=false;cancelled.emit()

func _accept()->void:
	if not active:return
	active=false;accepted.emit()

func commands()->Array[Dictionary]:
	return dialog_ui.commands() if active else []

func dispose()->void:
	active=false
	if dialog_ui!=null:
		if dialog_ui.quit_requested.is_connected(_accept):dialog_ui.quit_requested.disconnect(_accept)
		dialog_ui=null
