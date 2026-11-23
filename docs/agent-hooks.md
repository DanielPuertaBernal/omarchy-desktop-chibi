# Agent reactions (Claude Code hooks)

She reacts to an AI coding agent working in your terminal:

| Agent event (Claude Code hook) | She… | Bubble |
|---|---|---|
| `UserPromptSubmit` (you sent a prompt) | thinks | "Mmm… 🤔" |
| `PreToolUse` | works on her laptop | what it is doing: "Editando Service.qml", "Ejecutando npm test", "Buscando TODO" |
| `Notification` (permission or waiting for input) | waves | "¡Te necesito! · …" |
| a tool runs right after a permission prompt (you accepted) | bows | "¡Gracias! 💜" |
| `PostToolUseFailure` or a `PostToolUse` with an error | stumbles, then back to work | "¡Ups! · …" |
| `Stop` (the agent finished) | celebrates with confetti | "¡Listo! 🎉" |

**Click her** while she waves or celebrates and the agent's terminal window
gets focused (Hyprland). Otherwise a click opens the chat.

## How it works

`bin/chibi-brain` (started by the plugin) listens on
`http://127.0.0.1:47811` (loopback only). Hooks send it the JSON Claude
Code gives them on stdin:

```sh
curl -s -m 1 -H 'X-Chibi: 1' -H "X-Agent-Pid: $PPID" --data-binary @- http://127.0.0.1:47811/hook
```

- `X-Chibi: 1` is required; browsers can't send it cross-site, so web pages
  cannot poke her.
- `X-Agent-Pid` lets a click find the agent's terminal window.
- `-m 1 … || true`: if she's off, the hook returns at once and never blocks
  the agent.

Change the port with `bridgePort` in `~/.config/danso-chibi/chat.json`
(and in the hook commands).

## Install the hooks

Merge the `hooks` block from [`hooks/claude-code-settings.json`](../hooks/claude-code-settings.json)
into `~/.claude/settings.json` (all projects) or `.claude/settings.json` in a
project. If your settings already have a `hooks` key, add these entries next
to the ones you have instead of replacing it. Then restart Claude Code (or
run `/hooks` to review them).

With `jq`, after a backup:

```sh
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq -s '.[0] * .[1]' ~/.claude/settings.json hooks/claude-code-settings.json > /tmp/settings.json \
  && mv /tmp/settings.json ~/.claude/settings.json
```

(`*` replaces arrays for the same event; if you already had hooks for these
events, merge by hand.)

## Other agents / scripts

Anything can drive her with `POST /event`:

```sh
curl -s -H 'X-Chibi: 1' -d '{"state":"working","detail":"Compilando"}' http://127.0.0.1:47811/event
```

States: `thinking`, `working`, `needs`, `oops`, `done`, `thanks`, `idle`.

## Try it by hand

```sh
hook() { echo "$1" | curl -s -H 'X-Chibi: 1' --data-binary @- http://127.0.0.1:47811/hook; }
hook '{"hook_event_name":"UserPromptSubmit"}'
hook '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"/a/Service.qml"}}'
hook '{"hook_event_name":"Notification","message":"Claude needs your permission to use Bash"}'
hook '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test"}}'
hook '{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"npm test"}}'
hook '{"hook_event_name":"Stop"}'
```
