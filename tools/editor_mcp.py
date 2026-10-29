# SPDX-License-Identifier: MIT
"""Local FT2 authoring MCP server, Python stdlib only; no provider keys or cloud.

MCP legacy stdio lifecycle revisions 2024-11-05 through 2025-11-25.
Modern server/discover probes receive method-not-found for explicit legacy
fallback; this server does not implement the modern discovery protocol.
The separate loopback bridge is private application transport, not HTTP MCP.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import socket
import stat
import sys

MAX_BYTES = 1024 * 1024
VERSIONS = ("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
KIND = {"type": "string", "enum": ["characters", "skills", "maps", "stories"]}
INDEX = {"type": "integer", "minimum": 0}
STRING = {"type": "string"}
OBJECT = {"type": "object"}


def tool(name, description, properties=None, required=(), readonly=False):
    return {"name": "ft2_" + name, "description": description,
            "inputSchema": {"type": "object", "properties": properties or {},
                            "required": list(required), "additionalProperties": False},
            "annotations": {"readOnlyHint": readonly, "destructiveHint": False,
                            "openWorldHint": False}}


TOOLS = [
    tool("read_project", "Read the open authoring project and baseline availability.", readonly=True),
    tool("list_originals", "Search local pristine original references; requires prepared original data.",
         {"kind": KIND, "search": STRING, "offset": INDEX,
          "limit": {"type": "integer", "minimum": 1, "maximum": 200}}, ("kind",), True),
    tool("get_record", "Read one project record and its differences from the original.",
         {"kind": KIND, "index": INDEX}, ("kind", "index"), True),
    tool("create_record", "Create an authored record; optionally start from an original character/skill ID.",
         {"kind": KIND, "record": OBJECT, "original_id": INDEX}, ("kind",)),
    tool("update_record", "Merge a patch into an authored record. Stats are a sparse override dictionary.",
         {"kind": KIND, "index": INDEX, "patch": OBJECT}, ("kind", "index", "patch")),
    tool("reset_field", "Restore one original field; hp.initial removes that stat override. Identity/level stay.",
         {"kind": KIND, "index": INDEX, "key": STRING}, ("kind", "index", "key")),
    tool("reset_record", "Restore original fields of a character/skill, preserving local ID, base reference and level.",
         {"kind": KIND, "index": INDEX}, ("kind", "index")),
    tool("validate", "Validate authored descriptors without running the original game.", readonly=True),
    tool("save", "Save descriptor files inside the UI-selected project workspace only.", {"path": STRING}),
    tool("open", "Open a descriptor project inside this connection's selected workspace.", {"path": STRING}, ("path",)),
    tool("export", "Export the project's descriptor-only ZIP inside the selected workspace.", {"path": STRING}),
    tool("play", "Save and request a nonblocking play test in the editor. Requires linked original data."),
    tool("get_debug_output", "Read the editor-owned preview process state and bounded debug log tail.", readonly=True),
    tool("stop_play", "Stop only the preview process launched by this editor; keep editing and MCP connected."),
]
BY_NAME = {entry["name"]: entry for entry in TOOLS}


class RpcError(Exception):
    def __init__(self, code, message):
        self.code, self.message = code, message
        super().__init__(message)


def default_connection():
    if sys.platform == "win32":
        base = Path(os.environ.get("APPDATA", Path.home() / "AppData/Roaming")) / "Godot"
    elif sys.platform == "darwin":
        base = Path.home() / "Library/Application Support/Godot"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "godot"
    return base / "app_userdata/FT2 External Engine/editor_mcp_connection.json"


def connection_profile(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError("Enable MCP in the open FT2 editor first; connection file is missing")
    metadata = path.stat()
    if metadata.st_size > 8192:
        raise ValueError("Invalid local connection profile")
    if os.name != "nt" and (metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) & 0o077):
        raise ValueError("Connection profile must be owned by this user and have mode 0600")
    profile = json.loads(path.read_text(encoding="utf-8"))
    if (not isinstance(profile, dict) or profile.get("schema") != 1
            or profile.get("host") != "127.0.0.1"
            or type(profile.get("port")) is not int or not 1 <= profile["port"] <= 65535
            or not isinstance(profile.get("token"), str)
            or not re.fullmatch(r"[0-9a-f]{64}", profile["token"])):
        raise ValueError("Invalid local connection profile")
    return profile


def bridge_call(path, method, arguments):
    profile = connection_profile(path)
    request = json.dumps({"id": 1, "token": profile["token"], "method": method,
                          "params": arguments}, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"
    if len(request) > MAX_BYTES:
        raise ValueError("Editor request exceeds 1 MiB")
    with socket.create_connection(("127.0.0.1", profile["port"]), timeout=8) as peer:
        peer.settimeout(8)
        peer.sendall(request)
        with peer.makefile("rb") as stream:
            line = stream.readline(MAX_BYTES + 1)
    if len(line) > MAX_BYTES or not line.endswith(b"\n"):
        raise ValueError("Missing or oversized editor response")
    response = json.loads(line)
    if not isinstance(response, dict):
        raise ValueError("Invalid editor response")
    if "error" in response:
        raise ValueError(response["error"].get("message", "Editor rejected request"))
    if not isinstance(response.get("result"), dict):
        raise ValueError("Invalid editor tool result")
    return response["result"]


def arguments_valid(arguments, schema):
    if not isinstance(arguments, dict):
        return False
    fields = schema["properties"]
    if set(arguments) - set(fields) or set(schema["required"]) - set(arguments):
        return False
    types = {"string": str, "object": dict, "integer": int}
    for key, value in arguments.items():
        expected = fields[key]
        if type(value) is not types[expected["type"]]:
            return False
        if "enum" in expected and value not in expected["enum"]:
            return False
        if type(value) is int and not expected.get("minimum", value) <= value <= expected.get("maximum", value):
            return False
    return True


class Server:
    def __init__(self, connection):
        self.connection = connection
        self.version = None
        self.ready = False

    def handle(self, request):
        identifier = request.get("id") if isinstance(request, dict) else None
        try:
            if (not isinstance(request, dict) or request.get("jsonrpc") != "2.0"
                    or not isinstance(request.get("method"), str)
                    or ("id" in request and type(identifier) not in (str, int))):
                raise RpcError(-32600, "Invalid JSON-RPC request")
            method = request["method"]
            params = request.get("params", {})
            if not isinstance(params, dict):
                raise RpcError(-32602, "Expected object params")
            if "id" not in request:
                if method == "notifications/initialized" and self.version:
                    self.ready = True
                return None  # Notifications, including cancellation, never receive responses.
            if method == "initialize":
                if self.version:
                    raise RpcError(-32600, "Already initialized")
                if not isinstance(params.get("protocolVersion"), str):
                    raise RpcError(-32602, "protocolVersion is required")
                requested = params["protocolVersion"]
                self.version = requested if requested in VERSIONS else VERSIONS[0]
                result = {"protocolVersion": self.version, "capabilities": {"tools": {"listChanged": False}},
                          "serverInfo": {"name": "ft2-expansion-editor", "version": "0.1.0"},
                          "instructions": "Local authoring only. Enable MCP in the editor. Writes stay in its selected project workspace; originals and caches are protected."}
            elif method == "ping":
                result = {}
            elif method == "server/discover":
                raise RpcError(-32601, "server/discover is unsupported; use legacy MCP initialize over stdio")
            elif not self.ready:
                raise RpcError(-32002, "Initialize and send notifications/initialized first")
            elif method == "tools/list":
                if params.get("cursor"):
                    raise RpcError(-32602, "This fixed tool list has no pagination cursor")
                result = {"tools": TOOLS}
            elif method == "tools/call":
                name = params.get("name")
                if not isinstance(name, str) or name not in BY_NAME:
                    raise RpcError(-32602, "Unknown FT2 tool")
                arguments = params.get("arguments", {})
                if not arguments_valid(arguments, BY_NAME[name]["inputSchema"]):
                    raise RpcError(-32602, "Arguments do not match the tool input schema")
                try:
                    value = bridge_call(self.connection, name.removeprefix("ft2_"), arguments)
                except (OSError, ValueError, KeyError, TypeError):
                    # Profile data/token are never interpolated into diagnostics.
                    value = {"ok": False, "error": "Local editor connection failed or rejected the request. Enable MCP and check the connection file/workspace."}
                result = {"content": [{"type": "text", "text": json.dumps(value, ensure_ascii=False)}],
                          "isError": not value.get("ok", False)}
                if self.version in VERSIONS[:2]:
                    result["structuredContent"] = value
            else:
                raise RpcError(-32601, "Method not found")
            return {"jsonrpc": "2.0", "id": identifier, "result": result}
        except RpcError as error:
            if isinstance(request, dict) and "id" not in request and isinstance(request.get("method"), str):
                return None
            return {"jsonrpc": "2.0", "id": identifier, "error": {"code": error.code, "message": error.message}}


def main(argv=None):
    parser = argparse.ArgumentParser(description="FT2 editor MCP stdio server (local only)")
    parser.add_argument("--connection", type=Path, default=default_connection(), help="Private connection file shown by the open editor")
    args = parser.parse_args(argv)
    server = Server(args.connection)
    source, target = sys.stdin.buffer, sys.stdout.buffer
    while True:
        line = source.readline(MAX_BYTES + 1)
        if not line:
            return 0
        if len(line) > MAX_BYTES:
            response = {"jsonrpc": "2.0", "id": None, "error": {"code": -32600, "message": "MCP message exceeds 1 MiB"}}
        else:
            try:
                request = json.loads(line)
                response = server.handle(request)
            except (ValueError, UnicodeError, RecursionError):
                response = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Invalid JSON"}}
        if response is not None:
            target.write(json.dumps(response, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n")
            target.flush()
        if len(line) > MAX_BYTES:
            return 1


if __name__ == "__main__":
    raise SystemExit(main())
