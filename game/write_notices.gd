extends SceneTree
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1: quit(2); return
	var output := FileAccess.open(args[0],FileAccess.WRITE)
	output.store_string(Engine.get_license_text()+"\n\nGodot third-party copyright notices:\n"+JSON.stringify(Engine.get_copyright_info(),"\t")+"\n\nThird-party license texts:\n"+JSON.stringify(Engine.get_license_info(),"\t"))
	output.close();quit(0)
