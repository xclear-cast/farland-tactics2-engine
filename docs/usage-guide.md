# 움직이는 첫 실행 안내

![ZIP 압축 풀기부터 정품 폴더 선택과 게임 준비까지](usage-guide.gif)

[MP4 동영상 보기 또는 다운로드](usage-guide.mp4)

이 28초 안내는 실제 설정 UI를 렌더한 **설명용 예시**입니다. 원작 게임 파일을
변환하거나 원작 화면을 녹화한 검증 영상이 아닙니다. 예시 폴더 이름을 사용하며,
실제 첫 변환에는 몇 분이 걸릴 수 있습니다. 원작 자료나 폰트 파일은 포함하지 않습니다.

1. ZIP을 원작과 분리된 새 폴더에 전부 풉니다.
2. Windows에서는 `Launch-Windows.cmd`, Mac M1 이상에서는 `FT2 External Engine.app`을 엽니다.
3. `DATA`·`MAP`·`SPRITE`·`FTO_O.EXE`가 함께 있는 정품 게임의 상위 폴더를 선택합니다.
4. **게임 준비하기**를 누르고 완료될 때까지 기다립니다.
5. **연결하고 실행**을 누릅니다.

설정을 바꿀 때는 함께 제공된 `Game-Setup-Windows.cmd` 또는
`Game-Setup-Mac.command`를 열면 됩니다.

## 안내 재생성

원작 파일은 필요하지 않습니다. Linux/WSL에 Godot 4.7.2, Xvfb와 ffmpeg를 설치하고,
자신의 컴퓨터에서 사용할 수 있는 한글 폰트를 입력합니다. 폰트 바이너리는 출력하지 않습니다.

```text
python3 tools/guide/render_usage_guide.py --godot /path/to/godot --font /path/to/korean-font.ttf
python3 tools/guide/encode_usage_guide.py --ffmpeg /path/to/ffmpeg
```

렌더러는 전용 Xvfb를 생성해 사용한 뒤 그 프로세스만 종료합니다. 호스트 창이나
실제 게임 데이터에 접근하지 않습니다. PNG 프레임과 작업 로그는 공개 제외 경로인
`private/usage_guide`에 저장합니다.
