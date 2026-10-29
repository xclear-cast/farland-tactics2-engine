# SPDX-License-Identifier: MIT
"""Synthetic MCP protocol/security tests and optional real Godot bridge integration.

python -m unittest discover -s tools/tests -p test_editor_mcp.py -v
FT2_BRIDGE_GODOT=/path/to/godot enables the actual localhost bridge host.
"""
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "tools/editor_mcp.py"
spec = importlib.util.spec_from_file_location("editor_mcp", MODULE)
mcp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mcp)


class ProtocolTests(unittest.TestCase):
    def test_negotiation_lifecycle_and_tools(self):
        for revision in mcp.VERSIONS + ("future-version",):
            server = mcp.Server(Path("not-connected"))
            self.assertEqual(server.handle({"jsonrpc": "2.0", "id": 0, "method": "ping"})["result"], {})
            self.assertEqual(server.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})["error"]["code"], -32002)
            initialized = server.handle({"jsonrpc": "2.0", "id": 2, "method": "initialize", "params": {"protocolVersion": revision}})
            self.assertEqual(initialized["result"]["protocolVersion"], revision if revision in mcp.VERSIONS else mcp.VERSIONS[0])
            self.assertIsNone(server.handle({"jsonrpc": "2.0", "method": "notifications/initialized"}))
            tools = server.handle({"jsonrpc": "2.0", "id": 3, "method": "tools/list"})["result"]["tools"]
            self.assertEqual(len(tools), 14)
            self.assertEqual(len({tool["name"] for tool in tools}), len(tools))
            self.assertIsNone(server.handle({"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": 10}}))
            self.assertEqual(server.handle({"jsonrpc": "2.0", "id": 4, "method": "shell/eval"})["error"]["code"], -32601)

    def test_strict_argument_shapes_and_connection_profile(self):
        server = mcp.Server(Path("not-connected"));server.version = mcp.VERSIONS[0];server.ready = True
        for params in ({"name": "exec"}, {"name": "ft2_get_record", "arguments": {"kind": "characters", "index": True}},
                       {"name": "ft2_read_project", "arguments": {"token": "leak"}}):
            self.assertEqual(server.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": params})["error"]["code"], -32602)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "connection.json"
            profile = {"schema": 1, "host": "remote.example", "port": 1, "token": "a" * 64}
            path.write_text(json.dumps(profile));path.chmod(0o600)
            with self.assertRaises(ValueError):mcp.connection_profile(path)
            profile["host"] = "127.0.0.1";path.write_text(json.dumps(profile))
            self.assertEqual(mcp.connection_profile(path)["host"], "127.0.0.1")
            if os.name != "nt":
                path.chmod(0o644)
                with self.assertRaises(ValueError):mcp.connection_profile(path)

    def test_real_stdio_only_emits_jsonrpc_and_exits_on_eof(self):
        messages = [b'{bad json}\n', json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-11-25"}}).encode() + b"\n",
                    b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n', b'{"jsonrpc":"2.0","id":2,"method":"tools/list"}\n']
        result = subprocess.run([sys.executable, str(MODULE)], input=b"".join(messages), capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0)
        rows = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[0]["error"]["code"], -32700)
        self.assertEqual(len(rows[2]["result"]["tools"]), 14)


@unittest.skipUnless(os.environ.get("FT2_BRIDGE_GODOT"), "Set FT2_BRIDGE_GODOT for actual Godot integration")
class BridgeIntegration(unittest.TestCase):
    def test_real_socket_authoring_reset_and_protection(self):
        with tempfile.TemporaryDirectory(prefix="ft2-mcp-") as temporary:
            directory = Path(temporary);log = (directory / "godot.log").open("wb")
            godot = subprocess.Popen([os.environ["FT2_BRIDGE_GODOT"], "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
                                      "--script", "res://tests/test_editor_bridge.gd", "--", "--bridge-fixture=" + str(directory)], stdout=log, stderr=log)
            client = None
            try:
                deadline = time.monotonic() + 20
                while not (directory / "ready.json").exists() and time.monotonic() < deadline:
                    if godot.poll() is not None:break
                    time.sleep(.05)
                self.assertTrue((directory / "ready.json").exists(), (directory / "godot.log").read_text(errors="replace"))
                self.assertTrue(json.loads((directory / "ready.json").read_text())["ok"])
                connection = directory / "connection.json"
                profile = mcp.connection_profile(connection)
                before = {str(path): path.read_bytes() for path in (directory / "protected-cache").rglob("*") if path.is_file()}
                with socket.create_connection(("127.0.0.1", profile["port"]), timeout=3) as peer:
                    peer.sendall(b'{"id":1,"token":"wrong","method":"read_project"}\n')
                    self.assertIn("Authentication failed", peer.makefile("rb").readline().decode())
                with socket.create_connection(("127.0.0.1", profile["port"]), timeout=8) as peer:
                    peer.sendall(b"x" * (mcp.MAX_BYTES + 1))
                    self.assertIn("exceeds 1 MiB", peer.makefile("rb").readline().decode())
                with socket.create_connection(("127.0.0.1", profile["port"]), timeout=8) as peer:
                    peer.sendall(b'{"partial":')
                    self.assertEqual(peer.recv(10), b"")  # Godot closes incomplete requests at 5 s.
                client = subprocess.Popen([sys.executable, str(MODULE), "--connection", str(connection)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                serial = 0
                def rpc(method, params=None, notify=False):
                    nonlocal serial
                    serial += 1;message = {"jsonrpc": "2.0", "method": method}
                    if not notify:message["id"] = serial
                    if params is not None:message["params"] = params
                    client.stdin.write(json.dumps(message).encode() + b"\n");client.stdin.flush()
                    return None if notify else json.loads(client.stdout.readline())
                rpc("initialize", {"protocolVersion": "2025-11-25", "clientInfo": {"name": "own-test", "version": "1"}, "capabilities": {}})
                rpc("notifications/initialized", notify=True)
                def call(name, **arguments):
                    response = rpc("tools/call", {"name": "ft2_" + name, "arguments": arguments})
                    self.assertNotIn(profile["token"], json.dumps(response))
                    self.assertNotIn("error", response, response)
                    return response["result"]["structuredContent"]
                self.assertTrue(call("read_project")["ok"])
                self.assertEqual(call("list_originals", kind="characters", search="자작")["total"], 1)
                created = call("create_record", kind="characters", original_id=0, record={"id": "mcp_character", "level": 23})
                self.assertTrue(created["ok"]);index = created["index"]
                self.assertTrue(call("update_record", kind="characters", index=index, patch={"stats": {"hp.initial": 999}})["ok"])
                self.assertIn("stats.hp.initial", call("get_record", kind="characters", index=index)["changed_fields"])
                self.assertTrue(call("reset_field", kind="characters", index=index, key="hp.initial")["ok"])
                self.assertEqual(call("get_record", kind="characters", index=index)["record"]["stats"], {key: value for key, value in created["record"]["stats"].items() if key != "hp.initial"})
                self.assertTrue(call("reset_record", kind="characters", index=index)["ok"])
                self.assertEqual(call("get_record", kind="characters", index=index)["record"]["level"], 23)
                self.assertTrue(call("save")["ok"])
                self.assertTrue(call("open", path=str(directory / "project"))["ok"])
                self.assertTrue(call("validate")["ok"])
                self.assertTrue(call("export", path=str(directory / "project/authored.zip"))["ok"])
                for name, path in (("save", directory / "outside"), ("open", directory / "protected-cache"), ("export", directory / "protected-original/attack.zip")):
                    self.assertFalse(call(name, path=str(path))["ok"])
                self.assertFalse((directory / "outside").exists())
                self.assertFalse(call("update_record", kind="characters", index=0, patch={"executable_script": "oops"})["ok"])
                self.assertFalse(call("update_record", kind="maps", index=0, patch={"cells": [{"x": {"bad": 1}}]})["ok"])
                self.assertEqual(call("play")["status"], "play_requested")
                self.assertFalse(call("get_debug_output")["ok"])  # Minimal fixture has no preview API.
                self.assertFalse(call("stop_play")["ok"])
                self.assertEqual(before, {str(path): path.read_bytes() for path in (directory / "protected-cache").rglob("*") if path.is_file()})
                client.stdin.close();client.wait(timeout=5)
                self.assertEqual(client.returncode, 0)
                (directory / "stop").write_text("done")
                godot.wait(timeout=10)
                self.assertFalse(connection.exists())
                self.assertGreater(json.loads((directory / "stopped.json").read_text())["refreshes"], 0)
            finally:
                if client is not None and client.poll() is None:client.kill();client.wait()
                if client is not None:
                    for stream in (client.stdin, client.stdout, client.stderr):
                        if stream is not None and not stream.closed:stream.close()
                if godot.poll() is None:godot.terminate();godot.wait(timeout=10)
                log.close()
