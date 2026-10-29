# FT2 변환기 + 외부 콘텐츠 커스텀 엔진

정품 파랜드 택틱스 2 파일을 새 실행 프로그램으로 불러오고, 원하는 커스텀을
추가해서 플레이할 수 있게 만드는 프로젝트입니다. Windows 11과 Mac M1 이상을
대상으로 합니다. 사용하려면 지원 판본의 **정품 게임 폴더**가 필요합니다.

다운로드하는 프로그램에는 원작 이미지·음악·맵·대사나 게임 EXE가 들어 있지 않습니다.
처음 실행할 때 사용자가 가진 정품 폴더를 선택하면 필요한 데이터를 자동으로 준비합니다.

## 처음 사용하는 분: 다운로드부터 게임 실행까지

일반 사용자는 Python이나 명령어를 설치·입력하지 않는 **완성된 실행 패키지**를
사용합니다. [Releases](https://github.com/xclear-cast/farland-tactics2-engine/releases)에서
자신의 운영체제용 ZIP을 받으세요. `Code → Download ZIP`은 개발용 소스이므로
더블클릭 실행 패키지와 다릅니다. 해당 운영체제의 실행 ZIP이 아직 없다면 빌드 준비 중입니다.

### 1. 정품 게임 폴더를 확인하세요

게임이 설치된 폴더를 열어 `DATA`, `MAP`, `SPRITE` 폴더와 `FTO_O.EXE` 파일이
있는지 확인하세요. 나중에 앱에서 **이 네 가지가 들어 있는 상위 폴더**를 선택합니다.
`DATA` 폴더 자체를 선택하는 것이 아닙니다. Mac에서도 같은 정품 설치 파일을 사용합니다.

### 2. 받은 실행 ZIP을 별도 폴더에 전부 풀어주세요

원작 폴더에 덮어쓰지 말고 새 폴더를 만드세요. 예를 들면 다음처럼 나눕니다.

```text
내 게임/
├─ 파랜드2 정품/              ← 기존 게임 폴더
│  ├─ DATA/
│  ├─ MAP/
│  ├─ SPRITE/
│  └─ FTO_O.EXE
└─ FT2 커스텀 엔진/           ← 다운로드한 ZIP을 여기에 전부 풀기
```

실행 파일만 따로 옮기면 함께 들어 있는 변환기·라이브러리를 찾지 못합니다.
ZIP 안의 폴더와 파일을 함께 보관하세요. 원작 EXE를 Windows 95로 실행할 필요는 없습니다.

### 3. 운영체제에 맞는 시작 파일을 더블클릭하세요

- **Windows 11:** `FT2-Windows-x64.zip`을 풀고, 압축을 푼 폴더에서
  `Launch-Windows.cmd`를 더블클릭합니다.
- **Mac M1 이상:** `FT2-External-macos-arm64.zip`을 풀고, 안의
  `FT2-External-macos-arm64/FT2 External Engine.app`을 더블클릭합니다.
  Intel Mac은 지원 대상이 아닙니다.

인증서로 공증한 Mac 앱이 아닌 개발 패키지에는 macOS의 실행 경고가 나올 수 있습니다.
출처가 이 저장소의 릴리스인지 확인하고, 앱 전체를 이동해야 합니다.

### 4. 처음 한 번만 게임 데이터를 준비하세요

1. 앱의 **정품 설치 폴더** 옆 `폴더 선택`을 누릅니다.
2. 1단계에서 확인한 `DATA`·`MAP`·`SPRITE`·`FTO_O.EXE`가 들어 있는 폴더를 선택합니다.
3. **게임 준비하기**를 누르고 변환이 끝날 때까지 기다립니다.
4. 준비가 완료되면 **연결하고 실행**을 누릅니다.

변환 결과는 앱의 개인 캐시 폴더에 저장하며 원작 폴더를 덮어쓰지 않습니다.
캐시 위치나 글꼴·음원 경로를 바꾸고 싶을 때만 고급 옵션을 펼치면 됩니다.
다음 실행부터는 저장된 연결 설정으로 시작합니다. 원작 폴더를 옮겼다면 다시 연결하세요.

설정을 다시 바꾸려면 게임을 닫고, 함께 들어 있는 `Game-Setup-Windows.cmd`
(Windows) 또는 `Game-Setup-Mac.command`(Mac)를 더블클릭하면 연결 화면이 다시 열립니다.

### 예제 커스텀 켜기

기본 게임을 먼저 준비한 뒤 위 설정 파일로 연결 화면을 열고, **추가 옵션** 안의
**커스텀 모드 폴더** 목록에
압축을 푼 엔진 폴더 안의 `mods/example_balance` 폴더 경로를 한 줄 넣습니다.
`mod.json` 파일의 경로가 아니라 **그 파일이 들어 있는 폴더 경로**입니다.

- Windows 예: `D:\내 게임\FT2 커스텀 엔진\mods\example_balance`
- Mac 예: `/Users/내이름/Games/FT2 커스텀 엔진/mods/example_balance`

연결하고 실행하면 예제의 아이템 가격·마법 MP 변경이 적용됩니다. 끄려면 해당 줄을
지우고 다시 실행하세요. 여러 모드는 한 줄에 하나씩 넣으며 아래쪽 모드가 우선합니다.
모드 조합별 세이브를 따로 저장하므로 기본 게임 세이브를 덮어쓰지 않습니다.

### 소리·글꼴 안내

- 정품 설치 폴더에서 읽은 효과음은 변환합니다. 설치 폴더에 없는 CD 음악은 자동으로 생기지 않습니다.
- 배경음악도 사용하려면 고급 옵션에서 직접 준비한 CD 음원 폴더 또는 SoundFont를 연결하세요.
  둘 다 없으면 BGM만 미사용으로 안내합니다.
- 기본 한글 글꼴을 찾지 못하면 고급 옵션에서 한글 TTF/TTC 파일을 선택하세요.
  글꼴은 사용자 컴퓨터에서 변환하며 Win95와 글자 폭·픽셀까지 동일하지는 않습니다.

---

아래는 프로젝트 상태와 개발자용 사용법입니다. 프로젝트 전체의 오픈소스 라이선스는
아직 지정되지 않았습니다. [라이선스 상태](LICENSING.md)와
[제3자 고지](THIRD_PARTY_NOTICES.md)를 확인하세요.

## 검증 범위

| 대상 | 현재 기록 |
| --- | --- |
| Windows x64 | 외부 데이터·모드·UI 검사 63개 통과 |
| Linux x64 | 동일 검사 63개와 기본/커스텀/마을 화면 실행 통과 |
| macOS arm64, M1 이상 | 실제 Apple Silicon CI에서 빌드·앱 시작·내장 변환기·합성 모드 검사. 통과한 ZIP만 릴리스에 게시 |

이 검사는 전체 캠페인의 모든 조합이나 원본과의 픽셀 동등성을 보장하지 않습니다.

## 현재 구성

- 외부 데이터 연결, 모드 우선순위, JSON 패치, 바이너리/화면에 함께 반영되는 테이블 수정.
- 사용자 정품 설치 폴더에서 직접 읽는 독립 변환기와 판본 확인.
- 콘텐츠가 없는 엔진 PCK와 최초 데이터 연결 화면.
- `tools/convert_installation.py`가 BMP/SZDD·APD·FM2 맵·테이블·세이브·이벤트·PE
  리소스와 필요한 호환 테이블을 사용자 컴퓨터에서 생성합니다. 기존 `godot_port`나
  미리 추출한 데이터가 기본 변환 경로에 필요하지 않습니다.
- 지원 대상은 현재 검증 중인 한국어 `FTO_O.EXE` 판본입니다. 주소 기반 호환 테이블은
  실행 파일 해시가 일치할 때만 읽습니다. 다른 판본을 자동으로 혼합하지 않습니다.
- 글꼴은 사용자가 제공하거나 운영체제에 설치된 한글 글꼴에서 개인 마스크를 생성합니다.
  **Win95 GDI와 픽셀·글자 폭이 완전히 동일한 글꼴 재현은 아닙니다.**
- CD 음원이나 SF2 뱅크는 배포하지 않습니다. 해당 자료가 없으면 그 BGM 소스는 비활성화하며,
  정품 폴더에서 변환한 WAV 효과음은 사용할 수 있습니다.
- 지원 판본에서 원래 누락된 스프라이트 시트와 손상된 WAV 항목은 변환 보고서에 남깁니다.
  개발용 `EVENT98`의 미지원 명령은 원본 바이트를 보존하며 일반 캠페인 변환과 구분합니다.

## 개발자용: 소스에서 변환기 실행

일반 사용자용 완성 패키지에는 변환기가 포함되므로 Python 설치가 필요하지 않습니다.
여기부터는 소스에서 직접 개발·실행할 때의 설명입니다. 소스 변환기에는 Python 3.11 이상과
Pillow·Unicorn이 필요합니다. 내장 변환기가 없는 개발 실행에서는 GUI가 사용하는
Python에도 `requirements.txt`의 패키지가 설치되어 있어야 합니다.
변환 결과는 사용자 개인 데이터 폴더에 둡니다.
정품 소유 여부를 인증하는 기능은 없으며 파일 해시는 판본/캐시 일치 검사입니다.

변환기는 엔진 빌드와 별도로 실행할 수 있습니다. 가상환경 사용을 권장합니다.

```sh
python3 -m venv .venv
# macOS/Linux
source .venv/bin/activate
python -m pip install -r requirements.txt
python tools/convert_installation.py --source /path/to/FT2 --cache-parent /path/to/private-cache
```

Windows에서는 `py -3 -m venv .venv`로 만든 뒤
`.venv\Scripts\activate`를 사용합니다. 변환된 개인 캐시와 설치 폴더를 Git에 추가하지 마세요.

CLI 예시(경로는 자신의 컴퓨터에 맞게 변경):

```text
python -m pip install -r requirements.txt
python tools/convert_installation.py --source "D:\Games\FT2" --cache-parent "D:\Private\FT2-cache"
Launch-Windows.cmd --source-root="D:\Games\FT2" --content-root="D:\Private\FT2-cache" --mod="D:\Mods\example_balance"
```

변환기의 결과 JSON에 나온 `content_root`가 실제 연결할 캐시 폴더입니다.
`--font`로 한글 TTF/TTC 경로, `--cdda-dir`로 별도 CD 음원 폴더, `--soundfont`로
사용자 SF2 파일을 지정할 수 있습니다. `--full-font-charset`은 커스텀 대사 등에 필요한
CP949 전체 글자를 미리 준비하는 옵션이며 기본 글꼴 생성보다 오래 걸릴 수 있습니다.

`--setup`은 연결 화면을 다시 엽니다. `--no-mods`는 해당 실행에서 모드를 끕니다.
`--check-content`는 연결만 검사하고 종료합니다. `--engine-config=경로`로 별도
연결 설정 파일을 사용할 수 있습니다. 기본 모드는 없으며 예제 모드도 명시적으로 켭니다.

## 커스텀 데이터

각 모드 폴더에 `mod.json`을 둡니다. 모드는 설정 목록/CLI의 순서대로 적용하며
뒤쪽 모드가 우선합니다. 파일 교체와 JSON 패치는 각 모드 계층에서 순서대로 적용합니다.

```json
{
  "schema": 1,
  "id": "my_mod",
  "version": "1.0",
  "table_edits": [
    {"table": "item", "record": 1, "fields": {"price": 10}},
    {"table": "magic", "record": 1, "fields": {"mp": 3}}
  ],
  "patches": [
    {"target": "custom/settings.json", "operations": [
      {"op": "set", "path": "/difficulty", "value": "custom"}
    ]}
  ]
}
```

모드의 `files/` 아래 파일은 같은 논리 경로의 원본 캐시 파일을 대체합니다.
예: `files/assets/indexed/images/my_sprite.idx`를 추가하고,
`assets/indexed/manifest.json`에 JSON 패치로 항목을 등록하면 새 이미지가 됩니다.
새 맵/APD/이벤트도 파일과 해당 인덱스를 함께 추가해야 합니다.
변환 전 BMP를 넣는 것만으로 현재의 indexed 로더가 자동 변환하지는 않습니다.

JSON Pointer의 `/`는 `~1`, `~`는 `~0`으로 씁니다. `set`(추가/교체),
`remove`, `append`(지정한 배열 끝 추가)를 지원합니다. 빈 모드 디렉터리는 정상입니다.
경로 이탈, 심볼릭 링크, 중복 ID, 잘못된 패치, 범위를 벗어난 테이블 값은 거부합니다.
모드 코드는 실행하지 않으며 활성 모드 변경은 재시작 후 반영합니다.

`table_edits`는 item/magic/race의 기존 레코드를 변경합니다. 정수/CP949 문자열 길이를
검사하고, 실제 전투가 읽는 바이너리와 UI가 읽는 레코드를 동시에 갱신합니다.
지원 필드는 `game/scripts/content/ft2_content.gd`의 `TABLE_FIELDS`에 있습니다.
원하는 새 파일을 추가하는 기능이 새 스킬 종류/VM 명령/무제한 ID 추가까지 보장하지는
않습니다. 엔진이 지원하지 않는 기능은 엔진 코드도 확장해야 합니다.

세이브는 콘텐츠 ID와 활성 모드의 순서·설정·파일 해시에 따른 별도 프로필에 저장합니다.
정품 세이브와 기존 Godot 이식본의 사용자 세이브는 덮어쓰지 않습니다.

## 개발/배포 경계

- `game/`: 엔진 소스만. `assets/`, `fixtures/`, `runtime/`가 없습니다.
- `private/`: 개인 콘텐츠 캐시, 개발 기록, 테스트 출력. 공개 제외.
- `mods/example_balance/`: 자체 작성 예제 설정. 기본 비활성.
- `dist/FT2-External-Engine/`: 엔진 전용 빌드. `private`와 `local_setup.json`은 미포함.
- `tools/import_content.py`: 기존 변환 결과의 개인 캐시 이전/검증 도구.
- `tools/convert_installation.py`와 `tools/converters/`: 정품 설치 직접 변환의 기본 경로.
- `requirements.txt`: 사용자 측 Python 변환기 의존성. 배포물에도 함께 포함합니다.

원작 데이터 없이 실행하는 Python 합성 테스트:

```sh
python -m unittest tools.converters.test_graphics tools.converters.scenario_support.test_scenario
python tools/converters/tables_audio_support/test_conversion.py
```

네이티브 어댑터 바이너리는 소스 Git에 포함하지 않으며 각 대상에서 빌드해야 합니다.
Godot로 엔진을 실행하거나 패키징하기 전에 `game/native/bin`에 해당 플랫폼의
어댑터를 생성합니다. Mac 빌더는 아래 명령을 사용합니다. Windows/Linux 개발 빌더는
자신의 Godot 실행 파일 경로와 해당 네이티브 바이너리를 준비해야 합니다.

커밋 전 소스 공개 경계 검사:

```sh
python tools/audit_publish.py --paths-file private/publish_paths.txt --report private/publish_audit.json
git add --pathspec-from-file=private/publish_paths.txt --pathspec-file-nul
python tools/audit_publish.py --staged --report private/publish_staged_audit.json
```

이 검사는 명시적 소스 목록, 원작 데이터 확장자, 개인 경로 및 일반적인 비밀키 패턴을
확인합니다. 저작권·라이선스 검토를 완료했다는 의미는 아닙니다.

## macOS 대상: Apple Silicon M1 이상만

변환기와 커스텀 엔진 모두 **Apple Silicon M1 이상**을 대상으로 하며 Intel Mac은
제외합니다. 변환기는 arm64 Python과 Pillow·Unicorn으로 실행하도록 구성했습니다.
공통 엔진/데이터/모드 구조를 그대로 사용하고 보조 네이티브 모듈은 `macos.arm64`
전용으로 빌드합니다. macOS에서는 시작 시
Shift/Ctrl 상태를 CoreGraphics에서 한 번 읽도록 구현했습니다.

Apple Silicon Mac에 Godot 및 Xcode Command Line Tools를 설치한 뒤
`python3 tools/build_macos_arm64.py --godot /Applications/Godot.app/Contents/MacOS/Godot`
로 휴대용 작업본을 만듭니다. 결과의 `Launch-Mac.command`를 실행합니다.
Mac 빌드의 구체적인 성공 여부와 검사 결과는 저장소의 Actions 실행 기록 및
릴리스 검증 파일에서 확인하세요. 원작 캠페인 전체의 Mac 실기 동등성 검증과는
구분합니다. Developer ID 서명·공증과 로컬 ad-hoc 서명은 별개의 단계입니다.
인증서 없이 생성한 개발 패키지를 공증된 배포 앱으로 표시하지 않습니다.

일반 사용자용 Mac 패키지는 내장 변환기를 사용합니다. 소스에서 개발할 때만 arm64
Python 3.11 이상을 사용하세요. 내장 변환기가 없는 개발 앱을 Finder에서 실행하면
터미널과 PATH가 다를 수 있으므로, 가상환경에서 CLI를 실행하거나 가상환경을 활성화한
터미널에서 `Launch-Mac.command`를 실행합니다. 글꼴 자동 탐색에 실패하면 `--font`로
한글 TTF/TTC를 직접 지정할 수 있습니다.

원본 EXE에 호환 DLL을 붙여 실행하는 Windows 95 호환 런처는 이번 작업 범위에
포함하지 않습니다. 여기서는 정품 데이터를 변환해 새 엔진과 커스텀 모드로 실행합니다.
