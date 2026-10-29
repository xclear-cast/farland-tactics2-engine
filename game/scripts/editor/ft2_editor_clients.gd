# SPDX-License-Identifier: MIT
extends RefCounted
## Copy-only client settings; never read or modify personal client configuration.
## Client order, names and schema facts checked against hi-godot/godot-ai:
## https://github.com/hi-godot/godot-ai/blob/main/plugin/addons/godot_ai/clients/_registry.gd
## Each matching clients/<id>.gd was inspected on 2026-10-30.
## DeepSeek shape additionally checked against its official mcp-client README:
## https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/mcp/mcp-client/README.md
## These are independently rendered factual profiles, not copied upstream code.
const PROFILES := [
	{
		"id": "claude_code",
		"label": "Claude Code",
		"format": "json",
		"paths": {
			"unix": "~/.claude.json",
			"windows": "~/.claude.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": "stdio"
	},
	{
		"id": "claude_desktop",
		"label": "Claude Desktop",
		"format": "json",
		"paths": {
			"darwin": "~/Library/Application Support/Claude/claude_desktop_config.json",
			"windows": "$APPDATA/Claude/claude_desktop_config.json",
			"linux": "$XDG_CONFIG_HOME/Claude/claude_desktop_config.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": ""
	},
	{
		"id": "codex",
		"label": "Codex",
		"format": "toml",
		"paths": {
			"unix": "~/.codex/config.toml",
			"windows": "$USERPROFILE/.codex/config.toml"
		},
		"keys": [],
		"transport": ""
	},
	{
		"id": "codebuddy",
		"label": "CodeBuddy",
		"format": "json",
		"paths": {
			"unix": "~/.codebuddy/mcp.json",
			"windows": "$USERPROFILE/.codebuddy/mcp.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": "stdio"
	},
	{
		"id": "grok",
		"label": "Grok Build",
		"format": "toml",
		"paths": {
			"unix": "~/.grok/config.toml",
			"windows": "$USERPROFILE/.grok/config.toml"
		},
		"keys": [],
		"transport": ""
	},
	{
		"id": "antigravity",
		"label": "Antigravity",
		"format": "json",
		"paths": {
			"unix": "~/.gemini/config/mcp_config.json",
			"windows": "$USERPROFILE/.gemini/config/mcp_config.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": ""
	},
	{
		"id": "cursor",
		"label": "Cursor",
		"format": "json",
		"paths": {
			"unix": "~/.cursor/mcp.json",
			"windows": "$USERPROFILE/.cursor/mcp.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": "stdio"
	},
	{
		"id": "windsurf",
		"label": "Devin Desktop (Windsurf)",
		"format": "json",
		"paths": {
			"unix": "~/.codeium/windsurf/mcp_config.json",
			"windows": "$USERPROFILE/.codeium/windsurf/mcp_config.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": ""
	},
	{
		"id": "vscode",
		"label": "VS Code",
		"format": "json",
		"paths": {
			"darwin": "~/Library/Application Support/Code/User/mcp.json",
			"windows": "$APPDATA/Code/User/mcp.json",
			"linux": "$XDG_CONFIG_HOME/Code/User/mcp.json"
		},
		"keys": [
			"servers"
		],
		"transport": "stdio"
	},
	{
		"id": "vscode_insiders",
		"label": "VS Code Insiders",
		"format": "json",
		"paths": {
			"darwin": "~/Library/Application Support/Code - Insiders/User/mcp.json",
			"windows": "$APPDATA/Code - Insiders/User/mcp.json",
			"linux": "$XDG_CONFIG_HOME/Code - Insiders/User/mcp.json"
		},
		"keys": [
			"servers"
		],
		"transport": "stdio"
	},
	{
		"id": "zed",
		"label": "Zed",
		"format": "json",
		"paths": {
			"darwin": "~/.config/zed/settings.json",
			"linux": "$XDG_CONFIG_HOME/zed/settings.json",
			"windows": "$APPDATA/Zed/settings.json"
		},
		"keys": [
			"context_servers"
		],
		"transport": ""
	},
	{
		"id": "gemini_cli",
		"label": "Gemini CLI",
		"format": "json",
		"paths": {
			"unix": "~/.gemini/settings.json",
			"windows": "$USERPROFILE/.gemini/settings.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": ""
	},
	{
		"id": "cline",
		"label": "Cline",
		"format": "json",
		"paths": {
			"darwin": "~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json",
			"windows": "$APPDATA/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json",
			"linux": "$XDG_CONFIG_HOME/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": "stdio"
	},
	{
		"id": "kilo_code",
		"label": "Kilo Code",
		"format": "json",
		"paths": {
			"darwin": "~/Library/Application Support/Code/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json",
			"windows": "$APPDATA/Code/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json",
			"linux": "$XDG_CONFIG_HOME/Code/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": ""
	},
	{
		"id": "roo_code",
		"label": "Roo Code",
		"format": "json",
		"paths": {
			"darwin": "~/Library/Application Support/Code/User/globalStorage/rooveterinaryinc.roo-cline/settings/mcp_settings.json",
			"windows": "$APPDATA/Code/User/globalStorage/rooveterinaryinc.roo-cline/settings/mcp_settings.json",
			"linux": "$XDG_CONFIG_HOME/Code/User/globalStorage/rooveterinaryinc.roo-cline/settings/mcp_settings.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": "stdio"
	},
	{
		"id": "zoo_code",
		"label": "Zoo Code",
		"format": "json",
		"paths": {
			"darwin": "~/Library/Application Support/Code/User/globalStorage/zoocodeorganization.zoo-code/settings/mcp_settings.json",
			"windows": "$APPDATA/Code/User/globalStorage/zoocodeorganization.zoo-code/settings/mcp_settings.json",
			"linux": "$XDG_CONFIG_HOME/Code/User/globalStorage/zoocodeorganization.zoo-code/settings/mcp_settings.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": "stdio"
	},
	{
		"id": "kiro",
		"label": "Kiro",
		"format": "json",
		"paths": {
			"unix": "~/.kiro/settings/mcp.json",
			"windows": "$USERPROFILE/.kiro/settings/mcp.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": ""
	},
	{
		"id": "trae",
		"label": "Trae",
		"format": "json",
		"paths": {
			"darwin": "~/Library/Application Support/Trae/User/mcp.json",
			"windows": "$APPDATA/Trae/User/mcp.json",
			"linux": "$XDG_CONFIG_HOME/Trae/User/mcp.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": ""
	},
	{
		"id": "opencode",
		"label": "OpenCode",
		"format": "json",
		"paths": {
			"unix": "~/.config/opencode/opencode.json",
			"windows": "$HOME/.config/opencode/opencode.json"
		},
		"keys": [
			"mcp"
		],
		"transport": "local"
	},
	{
		"id": "qwen_code",
		"label": "Qwen Code",
		"format": "json",
		"paths": {
			"unix": "~/.qwen/settings.json",
			"windows": "$USERPROFILE/.qwen/settings.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": ""
	},
	{
		"id": "kimi_code",
		"label": "Kimi Code",
		"format": "json",
		"paths": {
			"unix": "~/.kimi-code/mcp.json",
			"windows": "~/.kimi-code/mcp.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": ""
	},
	{
		"id": "hermes",
		"label": "Hermes Agent",
		"format": "yaml",
		"paths": {
			"unix": "~/.hermes/config.yaml",
			"windows": "$LOCALAPPDATA/hermes/config.yaml"
		},
		"keys": [
			"mcp_servers"
		],
		"transport": ""
	},
	{
		"id": "pi",
		"label": "Pi Agent",
		"format": "json",
		"paths": {
			"unix": "~/.pi/agent/mcp.json",
			"windows": "$USERPROFILE/.pi/agent/mcp.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": ""
	},
	{
		"id": "deepseek_harness",
		"label": "DeepSeek Harness",
		"format": "yaml",
		"paths": {
			"unix": "~/.dsh/cordis.patch.yml",
			"windows": "~/.dsh/cordis.patch.yml"
		},
		"keys": [],
		"transport": "stdio"
	},
	{
		"id": "zcode",
		"label": "ZCode",
		"format": "json",
		"paths": {
			"unix": "~/.zcode/cli/config.json",
			"windows": "$USERPROFILE/.zcode/cli/config.json"
		},
		"keys": [
			"mcp",
			"servers"
		],
		"transport": "stdio"
	},
	{
		"id": "omp",
		"label": "Oh My Pi",
		"format": "json",
		"paths": {
			"unix": "~/.omp/agent/mcp.json",
			"windows": "$USERPROFILE/.omp/agent/mcp.json"
		},
		"keys": [
			"mcpServers"
		],
		"transport": ""
	}
]


static func all() -> Array:
	var result: Array=[]
	for profile in PROFILES:
		var paths: Dictionary=profile.paths
		var location: String
		match OS.get_name():
			"Windows":location=str(paths.get("windows",paths.get("unix","")))
			"macOS":location=str(paths.get("darwin",paths.get("unix","")))
			_:location=str(paths.get("linux",paths.get("unix","")))
		result.append({"id":profile.id,"label":profile.label,"format":profile.format,"location":location})
	return result

static func build(client_id: String,launch: Dictionary,opencode_version: int=1) -> String:
	if not launch.get("command")is String or str(launch.command).is_empty()or not launch.get("args",[])is Array:return ""
	for argument in launch.get("args",[]):
		if not argument is String:return ""
	var profile: Dictionary={}
	for candidate in PROFILES:
		if candidate.id==client_id:profile=candidate;break
	if profile.is_empty()and client_id!="generic":return ""
	var command: String=launch.command
	var args: Array=launch.get("args",[]).duplicate()
	var entry: Dictionary={"command":command,"args":args}
	if client_id in ["codex","grok"]:
		return "[mcp_servers.ft2]\ncommand = "+JSON.stringify(command)+"\nargs = "+JSON.stringify(args)+"\n"
	if client_id=="deepseek_harness":
		# Home patch files are YAML sequences. A NEW loader entry needs insert.
		return "- insert:\n    - id: mcp-ft2\n      name: \"@deepseek-ai/dsh-mcp-client\"\n      config:\n        serverName: ft2\n        transport: stdio\n        command: "+JSON.stringify(command)+"\n        args: "+JSON.stringify(args)+"\n"
	if client_id=="hermes":
		return "mcp_servers:\n  ft2:\n    command: "+JSON.stringify(command)+"\n    args: "+JSON.stringify(args)+"\n"
	if client_id=="opencode":
		var argv: Array=[command];argv.append_array(args)
		var local: Dictionary={"type":"local","command":argv}
		# Official V1 and V2 are distinct schemas; never merge their key shapes.
		# https://opencode.ai/docs/mcp-servers/
		# https://opencode.ai/v2/docs/mcp-servers
		if opencode_version==2:
			local.protocol="legacy"
			return JSON.stringify({"$schema":"https://opencode.ai/config.json","mcp":{"servers":{"ft2":local}}},"\t")
		local.enabled=true
		return JSON.stringify({"$schema":"https://opencode.ai/config.json","mcp":{"ft2":local}},"\t")
	if not profile.is_empty()and not str(profile.transport).is_empty():entry.type=str(profile.transport)
	if client_id in ["antigravity","cline","kilo_code","roo_code","zoo_code","kiro"]:entry.disabled=false
	if client_id in ["roo_code","zoo_code","kilo_code"]:entry.alwaysAllow=[]
	if client_id=="cline":entry.autoApprove=[]
	if client_id=="omp":entry.enabled=true
	var keys: Array=profile.get("keys",["mcpServers"])
	var result: Dictionary={"ft2":entry}
	for index in range(keys.size()-1,-1,-1):result={str(keys[index]):result}
	return JSON.stringify(result,"\t")
