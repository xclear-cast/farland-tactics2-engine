extends SceneTree
## Self-authored instructional states over the actual setup UI. No game data.
class DemoSetup extends "res://scripts/content/ft2_content_setup.gd":
	func _ready() -> void: pass

class Highlights extends Control:
	var target := Rect2()
	var phase := 0.0
	func _draw() -> void:
		if target.size.x <= 0: return
		var color := Color(1.0,0.72,0.18,0.82+0.15*sin(phase))
		draw_rect(target.grow(7),color,false,4)
		var endpoint := target.get_center()
		var start := Vector2(625,endpoint.y)
		draw_line(start,endpoint,color,5,true)
		var direction := (endpoint-start).normalized()
		var normal := Vector2(-direction.y,direction.x)
		draw_colored_polygon(PackedVector2Array([endpoint,endpoint-direction*22+normal*11,endpoint-direction*22-normal*11]),color)
		var cursor := endpoint+Vector2(0,5)
		draw_colored_polygon(PackedVector2Array([cursor,cursor+Vector2(0,24),cursor+Vector2(6,18),cursor+Vector2(12,29),cursor+Vector2(17,26),cursor+Vector2(11,16),cursor+Vector2(22,16)]),Color.WHITE)

var output := ""
var font_path := ""
var setup
var base: Control
var title: Label
var sub: Label
var card: PanelContainer
var card_text: Label
var chapter: Label
var folder_panel: PanelContainer
var folder_text: Label
var intro: PanelContainer
var intro_text: Label
var overlay: Highlights
var theme: Theme

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		elif arg.begins_with("--font="): font_path=arg.trim_prefix("--font=")
	if output.is_empty() or font_path.is_empty(): quit(2);return
	call_deferred("run")

func label(parent: Node, text: String, rect: Rect2, size: int, color: Color=Color.WHITE) -> Label:
	var node:=Label.new();node.text=text;node.position=rect.position;node.size=rect.size
	node.add_theme_font_size_override("font_size",size);node.add_theme_color_override("font_color",color)
	node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(node);return node

func panel(rect: Rect2, color: Color) -> PanelContainer:
	var node:=PanelContainer.new();node.position=rect.position;node.size=rect.size
	var style:=StyleBoxFlat.new();style.bg_color=color;style.corner_radius_top_left=16;style.corner_radius_top_right=16;style.corner_radius_bottom_left=16;style.corner_radius_bottom_right=16
	style.content_margin_left=22;style.content_margin_right=22;style.content_margin_top=20;style.content_margin_bottom=20
	node.add_theme_stylebox_override("panel",style);base.add_child(node);return node

func run() -> void:
	Engine.max_fps=20
	root.size=Vector2i(960,720);root.content_scale_size=Vector2i(960,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	Input.mouse_mode=Input.MOUSE_MODE_HIDDEN
	var font:=FontFile.new();font.data=FileAccess.get_file_as_bytes(font_path)
	theme=Theme.new();theme.default_font=font;theme.default_font_size=17
	base=Control.new();base.size=Vector2(960,720);base.theme=theme;root.add_child(base)
	var background:=ColorRect.new();background.color=Color("101827");background.size=Vector2(960,720);base.add_child(background)
	chapter=label(base,"처음 한 번만 따라 하세요",Rect2(28,20,900,35),20,Color("8edce7"))
	title=label(base,"딱 3단계면 게임을 시작해요",Rect2(28,57,910,50),34)
	sub=label(base,"압축 풀기부터 첫 실행까지",Rect2(28,111,900,35),20,Color("c5d1e4"))
	setup=DemoSetup.new();setup.theme=theme;setup.position=Vector2(20,160);setup.size=Vector2(640,480);setup.scale=Vector2(.93,.93)
	base.add_child(setup);setup._build_ui()
	card=panel(Rect2(636,165,300,440),Color("223449"))
	card_text=Label.new();card_text.add_theme_font_size_override("font_size",27);card_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;card.add_child(card_text)
	label(base,"실제 설정 화면을 바탕으로 만든 안내용 예시입니다. 원작 게임 화면·파일은 포함하지 않습니다.",Rect2(28,646,910,33),15,Color("b0c0d4"))
	label(base,"폴더 이름과 위치는 내 컴퓨터에 따라 달라요. 실제 변환은 처음에 몇 분 걸릴 수 있어요.",Rect2(28,679,910,30),15,Color("b0c0d4"))
	folder_panel=panel(Rect2(70,177,820,414),Color("eef3fa"))
	folder_text=Label.new();folder_text.add_theme_font_size_override("font_size",25);folder_text.add_theme_color_override("font_color",Color("16263d"));folder_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;folder_panel.add_child(folder_text)
	intro=panel(Rect2(34,165,892,450),Color("223449"))
	intro_text=Label.new();intro_text.add_theme_font_size_override("font_size",27);intro_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;intro.add_child(intro_text)
	overlay=Highlights.new();overlay.size=Vector2(960,720);overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;base.add_child(overlay)
	DirAccess.make_dir_recursive_absolute(output)
	await process_frame;await process_frame
	for frame in range(112):
		show_stage(frame/16,frame)
		await process_frame
		await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		if image.get_size()!=Vector2i(960,720):push_error("Guide viewport size mismatch");quit(3);return
		image.save_png(output.path_join("frame_%04d.png"%frame))
	print("FT2_GUIDE ",JSON.stringify({"frames":112,"fps":4,"seconds":28,"original_game_data_used":false,"instructional_example":true}))
	quit(0)

func show_stage(stage: int, frame: int) -> void:
	intro.visible=stage<2 or stage==6;folder_panel.visible=stage==3
	setup.visible=stage in [2,4,5];card.visible=setup.visible
	overlay.target=Rect2();overlay.phase=frame*0.6
	setup.source_field.text="" if stage<4 else "D:/Games/파랜드2 정품"
	setup.import_button.disabled=false;setup.connect_button.disabled=false
	setup.status_label.text="정품 데이터는 직접 가진 게임 폴더에서 읽습니다."
	match stage:
		0:
			chapter.text="준비 1 · ZIP 압축 풀기"
			title.text="받은 ZIP을 새 폴더에 전부 풀어요"
			sub.text="원작 게임 폴더에 덮어쓰지 마세요."
			intro_text.text="내 게임 폴더\n\n[폴더] 파랜드2 정품  ← 이미 가진 게임\n     DATA / MAP / SPRITE / FTO_O.EXE\n\n[폴더] FT2 커스텀 엔진  ← ZIP을 여기에 전부 풀기\n\n실행 파일 하나만 따로 꺼내지 마세요!"
		1:
			chapter.text="준비 2 · 시작 파일 열기"
			title.text="내 컴퓨터에 맞는 파일을 더블클릭!"
			sub.text="Windows와 Mac 중 하나만 고르면 됩니다."
			intro_text.text="Windows 11\n   Launch-Windows.cmd\n\nMac M1 이상\n   FT2 External Engine.app\n\n열면 다음 화면이 나와요 →"
		2:
			chapter.text="1 / 3 · 정품 게임 폴더 고르기"
			title.text="‘폴더 선택’을 눌러요"
			sub.text="프로그램 폴더가 아니라, 정품 게임이 있는 폴더예요."
			card_text.text="1\n\n정품 설치 폴더 옆\n‘폴더 선택’ 클릭!\n\n추가 옵션은\n지금 건드리지\n않아도 돼요."
			var row=setup.source_field.get_parent()
			overlay.target=row.get_child(1).get_global_rect()
		3:
			chapter.text="1 / 3 · 어떤 폴더가 정답일까요?"
			title.text="이 네 가지가 보이는 폴더를 골라요"
			sub.text="정품 폴더 안에 아래 네 가지가 있는지 확인하세요."
			folder_text.text="[폴더] 파랜드2 정품  ← 이 폴더를 선택!\n\n     [폴더] DATA\n     [폴더] MAP\n     [폴더] SPRITE\n     [파일] FTO_O.EXE\n\nDATA 폴더 안쪽까지 들어가지 마세요."
		4:
			chapter.text="2 / 3 · 게임 데이터 준비"
			title.text="‘게임 준비하기’를 누르고 기다려요"
			sub.text="처음에는 몇 분 걸릴 수 있어요. 창을 닫지 말고 기다려주세요."
			card_text.text="2\n\n‘게임 준비하기’\n클릭!\n\n준비 중에는\n잠깐 기다려요.\n\n영상에서는\n짧게 보여드려요."
			overlay.target=setup.import_button.get_global_rect()
			if frame%16>=5:
				setup.import_button.disabled=true
				setup.status_label.text="게임 실행을 준비하고 있습니다. 처음에는 몇 분 걸릴 수 있습니다…"
		5:
			chapter.text="3 / 3 · 준비 완료!"
			title.text="‘연결하고 실행’을 누르면 끝!"
			sub.text="원작 파일은 그대로 두고, 준비된 데이터로 게임을 실행해요."
			setup.status_label.text="변환이 완료되었습니다. 연결하고 실행을 누르세요."
			card_text.text="3\n\n준비가 끝나면\n‘연결하고 실행’\n클릭!\n\n이제 게임이\n시작됩니다."
			overlay.target=setup.connect_button.get_global_rect()
		6:
			chapter.text="완료 · 다음부터는 더 쉬워요"
			title.text="다음에는 시작 파일만 열면 돼요"
			sub.text="정품 폴더를 옮기거나 커스텀을 바꾸고 싶다면?"
			intro_text.text="평소에는\n   Windows: Launch-Windows.cmd\n   Mac: FT2 External Engine.app\n\n설정 화면을 다시 열 때는\n   Windows: Game-Setup-Windows.cmd\n   Mac: Game-Setup-Mac.command\n\n자세한 설명은 GitHub의 ‘처음 사용법’을 보세요."
	overlay.queue_redraw()
