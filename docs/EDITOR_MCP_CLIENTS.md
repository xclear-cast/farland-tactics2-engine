# AI에 연결해서 확장팩 만들기 — MCP 클라이언트 안내

확장팩 제작기를 **지금 사용하는 AI 코딩 도구에 연결**하면, 말로 요청한 캐릭터·스킬·맵·이야기 수정을 제작기에서 확인할 수 있습니다. 먼저 정품 데이터를 준비하고 제작기에서 프로젝트를 저장하세요.

## 권장 순서

1. 제작기 위쪽 **AI로 만들기 → AI 연결**을 열고 사용할 클라이언트를 고릅니다.
2. **AI 연결 시작 → 연결 설정 복사**를 누릅니다.
3. 해당 AI 도구에 설정을 등록한 뒤, 제작기를 열어 둔 상태에서 MCP 도구 목록을 확인합니다.
4. AI에게 먼저 `ft2_read_project`로 열린 프로젝트를 확인하게 한 뒤 원하는 수정을 요청합니다.
5. 제작기에서 수정된 값과 **원작 기준값**, 지도·이야기 미리보기를 비교합니다.
6. 마음에 들지 않는 수치는 항목별 되돌리기 또는 **원본값으로 전체 초기화**로 복원합니다.
7. **검사 → 저장하고 테스트 → 저장** 순서로 확인하고, 완성본은 **공유 ZIP 내보내기**로 나눕니다.

사용하는 AI 도구에 로그인한 상태에서 진행합니다. 연결 설정은 그 AI가 현재 열려 있는 로컬 제작기 도구를 사용할 수 있게 합니다. API 키나 모델 계정은 사용 중인 AI 도구에서 설정합니다.

실행 테스트는 별도 게임으로 열려 제작기와 AI 연결을 유지합니다. 결과를 확인한 뒤 **테스트 중지**를 누르거나 AI에게 중지를 요청하세요. 작업을 마치면 **연결 종료**를 누릅니다.

AI에게 그대로 요청할 수 있는 예:

> FT2 MCP로 현재 확장팩을 읽어줘. 원작 캐릭터 목록에서 이름을 검색하고, 선택한 캐릭터의 편집본을 만들어 HP 기본값만 원작보다 10 높여줘. 바뀐 필드와 원작 기준값을 보여준 뒤 검사해줘. 원작 파일은 수정하지 말아줘.

> 내 주인공과 연습 상대를 8×8 전장에 배치하고, 대사 → 전투 → 승리/패배 대사 → 끝으로 이어지는 짧은 이야기를 만들어줘. 제작기에서 확인할 수 있게 수정하고 검사해줘.

> 방금 바꾼 캐릭터의 HP만 원본값으로 되돌리고, 나머지 변경은 유지해줘.

## GodotAI와 같은 AI 클라이언트 26개

**DeepSeek Harness를 포함해 GodotAI의 26개 AI 클라이언트에 맞는 연결 설정을 제공합니다.** 목록과 순서는 [hi-godot/godot-ai의 `_registry.gd`](https://github.com/hi-godot/godot-ai/blob/main/plugin/addons/godot_ai/clients/_registry.gd)를 기준으로 맞췄습니다. 설정 방식은 [upstream client-configuration 안내](https://github.com/hi-godot/godot-ai/blob/main/docs/client-configuration.md)와 클라이언트 descriptor를 참고합니다.

여기서 26개는 **AI 클라이언트 목록**이며, 제작기가 제공하는 편집 도구는 아래의 **FT2 도구 14개**입니다. 클라이언트를 선택하고 **연결 설정 복사**로 얻은 해당 형식을 사용하세요. 앱이 개인 클라이언트 설정을 자동으로 수정하지 않습니다.

| 순서 | AI 클라이언트 | 식별자 | 설정 형식 |
|---|---|---|---|
| 1 | Claude Code | `claude_code` | 명령 / JSON |
| 2 | Claude Desktop | `claude_desktop` | JSON |
| 3 | Codex | `codex` | TOML |
| 4 | CodeBuddy | `codebuddy` | JSON |
| 5 | Grok Build | `grok` | TOML |
| 6 | Antigravity | `antigravity` | JSON |
| 7 | Cursor | `cursor` | JSON |
| 8 | Devin Desktop (Windsurf) | `windsurf` | JSON |
| 9 | VS Code | `vscode` | JSON |
| 10 | VS Code Insiders | `vscode_insiders` | JSON |
| 11 | Zed | `zed` | JSON |
| 12 | Gemini CLI | `gemini_cli` | JSON |
| 13 | Cline | `cline` | JSON |
| 14 | Kilo Code | `kilo_code` | JSON |
| 15 | Roo Code | `roo_code` | JSON |
| 16 | Zoo Code | `zoo_code` | JSON |
| 17 | Kiro | `kiro` | JSON |
| 18 | Trae | `trae` | JSON |
| 19 | OpenCode | `opencode` | JSON |
| 20 | Qwen Code | `qwen_code` | JSON |
| 21 | Kimi Code | `kimi_code` | JSON |
| 22 | Hermes Agent | `hermes` | YAML |
| 23 | Pi Agent | `pi` | JSON |
| 24 | DeepSeek Harness | `deepseek_harness` | Cordis YAML / JSON 부분집합 |
| 25 | ZCode | `zcode` | JSON |
| 26 | Oh My Pi | `omp` | JSON |

OpenCode는 같은 클라이언트 안에서 V1/V2 설정을 구분합니다. **일반 MCP** 설정은 이 26개 외의 stdio 지원 클라이언트에 직접 연결할 때 사용합니다. 설정 생성·로컬 stdio 도구 연결 검증과, 모든 AI 앱의 실제 계정으로 로그인해 검증하는 범위는 구분합니다.

## DeepSeek Harness 연결

1. 제작기의 **AI 연결**에서 **DeepSeek Harness**를 고릅니다.
2. **AI 연결 시작 → 연결 설정 복사**를 누릅니다.
3. Harness의 `~/.dsh/cordis.patch.yml`에 새 서버용 `insert` 항목을 추가합니다. `DSH_HOME`을 지정했다면 `$DSH_HOME/cordis.patch.yml`을 사용합니다.
4. 사용하는 Harness 프로필을 다시 시작하고 FT2 도구가 나타나는지 확인합니다.

Cordis 홈 패치 파일은 최상위 **배열**입니다. 새 서버를 넣을 때는 `insert`가 필요하며, 기존 항목을 덮어쓰는 단순 `id` 행과 다릅니다. 이 경로·형식은 [GodotAI DeepSeek descriptor](https://github.com/hi-godot/godot-ai/blob/main/plugin/addons/godot_ai/clients/deepseek_harness.gd)와 [DSH strategy](https://github.com/hi-godot/godot-ai/blob/main/plugin/addons/godot_ai/clients/_dsh_strategy.gd)를 기준으로 합니다.

아래는 Windows 패키지 예시입니다. 실행 파일·연결 파일은 제작기가 복사해 주는 본인의 경로로 바꾸세요.

```yaml
- insert:
    - id: mcp-ft2
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: ft2
        transport: stdio
        command: 'C:/FT2/tools/ft2-convert/ft2-convert.exe'
        args:
          - --editor-mcp
          - --connection
          - 'C:/FT2-private/editor_mcp_connection.json'
```

같은 내용의 **JSON 부분집합** 표현도 YAML 파서가 읽을 수 있습니다. 기존 파일에 추가할 때는 배열 구조와 다른 항목을 유지합니다.

```json
[
  {
    "insert": [
      {
        "id": "mcp-ft2",
        "name": "@deepseek-ai/dsh-mcp-client",
        "config": {
          "serverName": "ft2",
          "transport": "stdio",
          "command": "C:/FT2/tools/ft2-convert/ft2-convert.exe",
          "args": ["--editor-mcp", "--connection", "C:/FT2-private/editor_mcp_connection.json"]
        }
      }
    ]
  }
]
```

`serverName`, `transport`, `command`, `args`는 [DeepSeek 공식 MCP client README](https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/mcp/mcp-client/README.md)의 설정 필드입니다. `stdio` 명령에 HTTP용 `url`을 함께 넣지 않습니다. Harness에서는 도구가 `mcp__ft2__ft2_read_project`처럼 서버 이름을 붙여 나타납니다. 먼저 프로젝트 읽기를 요청한 뒤 편집·검사·테스트를 이어가세요.

FT2 서버는 현재 **legacy `initialize` 방식의 MCP**로 연결합니다. 새 SDK의 `server/discover` 탐색에는 `-32601`(method not found)을 반환하고 legacy 연결로 이어집니다. 이 탐색 뒤 같은 프로세스와 재시작한 프로세스에서 14개 도구를 읽는 로컬 stdio 회귀를 확인했습니다. 이는 2026-07-28 프로토콜 전체 구현이나 DeepSeek 실제 계정의 연결 검증을 뜻하지 않습니다. 현재 구현은 [FT2 MCP 서버](../tools/editor_mcp.py)를 참고하세요.

## 연결 설정을 직접 작성할 때

실행 패키지 사용자는 제작기가 복사해 주는 **실행 파일 경로와 인수**를 그대로 사용하면 됩니다. 아래는 개발용 소스로 연결하는 예시입니다. `C:/FT2/`는 본인의 소스 폴더로, Python 경로는 설치한 Python의 절대 경로로 바꾸세요. Mac에서는 `/Users/사용자명/FT2/` 같은 본인의 절대 경로를 사용합니다.

실행 패키지에서 복사되는 명령의 구조:

```text
<동봉된 ft2-convert 실행 파일> --editor-mcp --connection <제작기에 표시된 연결 파일>

# 개발용 소스 실행
<Python 절대 경로> <FT2 소스>/tools/editor_mcp.py --connection <제작기에 표시된 연결 파일>
```

연결 파일은 열린 제작기가 생성합니다. 이 파일이나 안의 인증값을 확장팩 ZIP·공개 저장소에 넣지 마세요. 기존 클라이언트 설정이 있으면 서버 항목을 추가합니다.

### Claude Code

```sh
claude mcp add --transport stdio ft2-editor -- "C:/Python/python.exe" "C:/FT2/tools/editor_mcp.py" --connection "C:/FT2-private/editor_mcp_connection.json"
```

프로젝트 `.mcp.json`을 쓰려면 아래 `mcpServers` 형식을 사용합니다. 연결 후 Claude Code의 `/mcp`에서 확인합니다. [공식 추가 명령·프로젝트 설정](https://code.claude.com/docs/en/mcp)

### Cursor · Claude Desktop · Cline · Cascade의 JSON 예시

```json
{
  "mcpServers": {
    "ft2-editor": {
      "command": "C:/Python/python.exe",
      "args": [
        "C:/FT2/tools/editor_mcp.py",
        "--connection",
        "C:/FT2-private/editor_mcp_connection.json"
      ]
    }
  }
}
```

Cursor에서 명시적 전송 형식이 필요한 버전은 서버 항목에 `"type": "stdio"`를 추가합니다. Cline의 추가 필드는 `"disabled": false`, `"autoApprove": []`입니다. Claude Desktop 설정은 Windows `%APPDATA%/Claude/claude_desktop_config.json`, Mac `~/Library/Application Support/Claude/claude_desktop_config.json`에서 열고, 저장 후 앱을 완전히 재시작합니다. [Cursor](https://cursor.com/docs/mcp), [Cline](https://docs.cline.bot/mcp/mcp-overview), [Claude Desktop](https://modelcontextprotocol.io/docs/2026-07-28/develop/connect-local-servers)

### OpenCode V1

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "ft2-editor": {
      "type": "local",
      "command": ["C:/Python/python.exe", "C:/FT2/tools/editor_mcp.py", "--connection", "C:/FT2-private/editor_mcp_connection.json"],
      "enabled": true
    }
  }
}
```

### OpenCode V2

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "ft2-editor": {
        "type": "local",
        "command": ["C:/Python/python.exe", "C:/FT2/tools/editor_mcp.py", "--connection", "C:/FT2-private/editor_mcp_connection.json"],
        "protocol": "legacy"
      }
    }
  }
}
```

V1과 V2는 바깥 구조가 다릅니다. V2는 `enabled` 대신 `disabled`를 사용하며, 위처럼 생략하면 연결됩니다. FT2 서버의 `initialize` 방식에 맞춰 V2의 `protocol`은 `legacy`로 둡니다. [V1 공식 설정](https://opencode.ai/docs/mcp-servers/), [V2 공식 설정·프로토콜](https://opencode.ai/v2/docs/mcp-servers)

### Codex CLI

```sh
codex mcp add ft2-editor -- "C:/Python/python.exe" "C:/FT2/tools/editor_mcp.py" --connection "C:/FT2-private/editor_mcp_connection.json"
codex mcp list
```

직접 설정하려면:

```toml
[mcp_servers.ft2-editor]
command = "C:/Python/python.exe"
args = ["C:/FT2/tools/editor_mcp.py", "--connection", "C:/FT2-private/editor_mcp_connection.json"]
```

이 형식은 [공식 Codex MCP 문서](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)와 로컬 `codex mcp add --help`에서 확인했습니다. 설정 후 도구 목록을 새로 불러오거나 새 세션을 시작하세요.

## FT2 제작기에서 AI가 할 수 있는 작업

현재 구현의 기준은 [tools/editor_mcp.py](../tools/editor_mcp.py)의 도구 목록입니다.

| 도구 | 하는 일 |
|---|---|
| `ft2_read_project` | 열린 확장팩과 원작 기준값 연결 상태 읽기 |
| `ft2_list_originals` | 정품 기준 캐릭터·스킬 검색 |
| `ft2_get_record` | 선택 항목과 원본 대비 변경 읽기 |
| `ft2_create_record` | 새 캐릭터·스킬·맵·스토리 작성 |
| `ft2_update_record` | 항목 값 수정 |
| `ft2_reset_field` | 특정 필드만 원본값 복원 |
| `ft2_reset_record` | 캐릭터·스킬 원본값 전체 복원 |
| `ft2_validate` | ID·연결·좌표·범위 검사 |
| `ft2_save` | 제작기에서 선택한 작업 폴더에 저장 |
| `ft2_open` | 작업 폴더 안의 프로젝트 열기 |
| `ft2_export` | 공유용 정의 ZIP 내보내기 |
| `ft2_play` | 저장 후 별도 게임에서 실행 테스트 요청 |
| `ft2_get_debug_output` | 테스트 실행 상태·디버그 출력 확인 |
| `ft2_stop_play` | 실행 중인 테스트 게임 종료 |

변경은 열린 제작기에 반영됩니다. 캐릭터·스킬의 원본값 복원은 로컬 ID·기반 참조·레벨을 유지하며 편집값을 되돌립니다. 정품이 연결되지 않으면 원작 검색·비교·원본 복원용 값은 사용할 수 없습니다. 원작과 개인 캐시는 편집 대상이 아닙니다.

## 연결되지 않을 때

1. 제작기 **AI로 만들기 → AI 연결**에서 **AI 연결 시작**을 눌렀는지 확인합니다.
2. 클라이언트에 등록한 실행 파일·스크립트·연결 파일이 실제로 있는지 확인합니다.
3. OpenCode는 설치 버전에 맞는 V1/V2 설정을 선택합니다.
4. 클라이언트의 MCP 목록을 새로고침한 뒤 `ft2_read_project` 하나로 확인합니다.
5. AI가 수정했는데 원하는 결과가 아니면 변경 목록을 확인하고 원본 복원 후 다시 요청합니다.

공식 문서 확인일: 2026-10-30. 각 앱 업데이트로 메뉴 위치가 바뀌면 위의 클라이언트 공식 안내를 우선 확인하세요.