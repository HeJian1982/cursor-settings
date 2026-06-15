# hj-gateway in Cursor

Run `hj-gateway` (local AI assistant gateway) commands from the Cursor command palette.

## Prerequisites

1. Start the gateway: `cd e:\HJ\cursor\subprojects\hj-gateway\bin && powershell -File .\gateway.ps1 start`
   (or use the command palette: `hj-gateway: start`)
2. Or install autostart: `hj-gateway: install-autostart` (runs at every login)

## Commands

| Command | Description |
|---|---|
| `hj-gateway: start` | Start the gateway in background |
| `hj-gateway: stop` | Stop the gateway |
| `hj-gateway: restart` | Restart the gateway |
| `hj-gateway: status` | Show running status (pid, port, skill count, provider) |
| `hj-gateway: chat` | Send a chat message (prompts for input) |
| `hj-gateway: repl` | Open interactive REPL in terminal |
| `hj-gateway: skill list` | List all available skills |
| `hj-gateway: skill new` | Scaffold a new skill JSON |

## Endpoints (if you want to call from your own scripts)

- `GET  /health`            - liveness probe
- `GET  /v1/skills`         - list skills
- `POST /v1/skills/run`     - run a skill by name
- `POST /v1/chat`           - send chat (JSON: `{message, provider?}`)
- `POST /v1/chat/stream`    - SSE stream chat
- `GET  /v1/memory?limit=N` - recent conversation history
- `GET  /v1/providers`      - list configured providers
- `POST /v1/memory/clear`   - clear conversation history

Base URL: `http://127.0.0.1:7799`

## Adding new skills

1. `hj-gateway: skill new myname` (or edit `e:\HJ\cursor\subprojects\hj-gateway\skills\*.json`)
2. Fill in `name`, `description`, `keywords` (Chinese/English), `kind` (literal|shell|http)
3. The gateway hot-reloads skills on every chat - no restart needed

## Files

- `bin/gateway.ps1` - PowerShell control interface
- `bin/server.py`   - Python HTTP server (stdlib only)
- `config/gateway.json` - main config (port, providers, system prompt)
- `config/.env.example` - API key template
- `skills/*.json`   - skill definitions
- `state/gateway.db` - SQLite memory (gitignored)
- `logs/server.log` - server log (gitignored)
