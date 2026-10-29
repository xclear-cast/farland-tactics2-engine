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

## 어떤 AI 도구에 연결하나요?

아래는 각 클라이언트의 공식 문서로 확인한 **로컬 stdio MCP 설정 형식**입니다. 제작기에서 복사한 설정을 우선 사용하세요. 클라이언트에 서버를 추가한 뒤 도구가 보이는지 확인합니다. 모든 클라이언트의 실제 계정·버전을 여기서 함께 실행 검증했다는 뜻은 아닙니다.

| AI 클라이언트 | 설정 위치·형식 | 연결 확인 |
|---|---|---|
| Claude Code | 추가 명령 또는 프로젝트 `.mcp.json`의 `mcpServers` | `/mcp` |
| OpenCode V1 | `opencode.json` / `opencode.jsonc`의 `mcp.<이름>`, `enabled: true` | MCP 서버 목록 |
| OpenCode V2 | `mcp.servers.<이름>`, `protocol: "legacy"` | `/mcps`, `opencode mcp list` |
| Codex CLI | `codex mcp add` 또는 `~/.codex/config.toml`의 `mcp_servers` | `codex mcp list` |
| Cursor | 프로젝트 `.cursor/mcp.json` 또는 사용자 `~/.cursor/mcp.json` | MCP 설정의 서버·도구 목록 |
| Claude Desktop | 설정에서 연 `claude_desktop_config.json`의 `mcpServers` | 앱 재시작 후 도구 목록 |
| Cline | MCP Servers → Configure → `cline_mcp_settings.json` | 서버 활성 상태·도구 목록 |
| Windsurf / Cascade | MCP 설정에서 여는 `mcp_config.json`의 `mcpServers` | MCP 서버 토글·도구 목록 |

Claude Code 형식은 [공식 MCP 안내](https://code.claude.com/docs/en/mcp), OpenCode는 [V1 문서](https://opencode.ai/docs/mcp-servers/)와 [V2 문서](https://opencode.ai/v2/docs/mcp-servers), Codex는 [공식 MCP 문서](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)를 기준으로 합니다. Cursor는 [공식 MCP 설정](https://cursor.com/docs/mcp), Claude Desktop은 [MCP의 로컬 연결 안내](https://modelcontextprotocol.io/docs/2026-07-28/develop/connect-local-servers), Cline은 [공식 MCP 안내](https://docs.cline.bot/mcp/mcp-overview)를 참고하세요. Windsurf의 기존 Cascade 문서는 현재 [Devin Desktop의 Cascade 설정](https://docs.devin.ai/desktop/cascade/mcp)으로 연결되므로 설치된 앱의 **Open MCP config file**을 이용하면 해당 버전의 파일을 찾을 수 있습니다.

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

## Godot 엔진 자체를 고치는 개발자용 MCP

확장팩 작성은 위 FT2 도구를 사용합니다. Godot 장면·노드·엔진 프로젝트도 함께 수정하는 개발자는 별도로 Godot MCP를 연결할 수 있습니다.

현재 제공된 Godot 도구 14개는 [Coding-Solo/godot-mcp의 README](https://github.com/Coding-Solo/godot-mcp)에 나오는 도구명과 일치합니다. 이 저장소는 커뮤니티 MCP 서버이며 Godot 제작사의 공식 서버라는 의미는 아닙니다. upstream은 Godot, Node.js 18 이상과 npm, MCP 클라이언트를 요구하고 Claude Code·Cline·Cursor의 설정 예시를 제공합니다.

| Godot 도구 | 기능 |
|---|---|
| `get_godot_version` | 설치된 엔진 버전 확인 |
| `list_projects` | 프로젝트 검색 |
| `get_project_info` | 프로젝트 정보 읽기 |
| `launch_editor` | 에디터 열기 |
| `create_scene` | 장면 생성 |
| `add_node` | 노드 추가 |
| `load_sprite` | Sprite2D에 이미지 연결 |
| `save_scene` | 장면 저장 |
| `run_project` | 실행·출력 수집 |
| `get_debug_output` | 디버그 출력 읽기 |
| `stop_project` | 실행 종료 |
| `export_mesh_library` | MeshLibrary 내보내기 |
| `get_uid` | 리소스 UID 읽기 |
| `update_project_uids` | UID 참조 갱신 |

upstream이 안내하는 Claude Code 등록 명령:

```sh
claude mcp add godot -- npx @coding-solo/godot-mcp
```

Godot MCP 연결은 `ft2_*` 제작기 도구 연결과 별개입니다. 확장팩 JSON을 수정할 때는 FT2 MCP, 엔진의 장면·코드를 개발할 때는 Godot MCP를 고르면 됩니다. [upstream 설정 안내](https://github.com/Coding-Solo/godot-mcp#quick-start)

## 연결되지 않을 때

1. 제작기 **AI로 만들기 → AI 연결**에서 **AI 연결 시작**을 눌렀는지 확인합니다.
2. 클라이언트에 등록한 실행 파일·스크립트·연결 파일이 실제로 있는지 확인합니다.
3. OpenCode는 설치 버전에 맞는 V1/V2 설정을 선택합니다.
4. 클라이언트의 MCP 목록을 새로고침한 뒤 `ft2_read_project` 하나로 확인합니다.
5. AI가 수정했는데 원하는 결과가 아니면 변경 목록을 확인하고 원본 복원 후 다시 요청합니다.

공식 문서 확인일: 2026-10-30. 각 앱 업데이트로 메뉴 위치가 바뀌면 위의 클라이언트 공식 안내를 우선 확인하세요.