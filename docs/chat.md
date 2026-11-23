# Chat and personality

Click her and a small chat panel opens next to her. Type, press Enter, and
her reply streams into a speech bubble over her head and into the panel.
**Esc** or a click outside the panel closes it. While it is open the panel
holds the keyboard.

She remembers the last `memoryTurns` exchanges in RAM (lost on restart
unless `persistHistory` is on, which saves them to
`~/.local/state/yorisou/history.json`).

## Scripted replies (default: no model, no network)

With `"backend": "scripted"` (the default) she answers from her personality
file. Each entry of `replies` has `keywords` and `lines`; the first entry
with a keyword at the start of a word in your message wins ("dulce" also
matches "dulces"; case and accents are ignored), and she says one of its
lines, never the same one twice in a row. Nothing matched: a line from
`fallbackReplies`. `{name}` is replaced by her name.

```json
"replies": [
  { "keywords": ["hola", "buenas"], "lines": ["Hola.", "Mm. Hola."] },
  { "keywords": ["dulce", "chocolate"], "lines": ["¿Dulces? Ahora sí te escucho."] }
],
"fallbackReplies": ["Ajá...", "Qué pereza."]
```

A character folder's own `personality.json` can carry its own replies (see
[sprites.md](sprites.md)).

## Desktop reactions (apps and notifications)

She comments when you open or focus an app (Hyprland's event socket,
`openwindow` / `activewindow`) and, if you turn it on, when a desktop
notification arrives. Configure it with `appReactions` in
`personality.json`:

```json
"appReactions": {
  "enabled": true,
  "minIntervalSec": 20,     // at most one line every 20 s
  "focusDwellSec": 2,       // a focused app must stay focused 2 s (quick flips are ignored)
  "focusChance": 0.4,       // not every focus gets a line
  "notifications": false,   // react to desktop notifications
  "ignore": ["quickshell"], // window classes she never reacts to
  "apps": [
    { "name": "WhatsApp", "match": ["whatsapp"],
      "open": ["¿Otra vez WhatsApp? Yo estoy aquí, ¿sabes?"],
      "focus": ["WhatsApp otra vez..."],
      "notify": ["¿Quién te escribe?"] }
  ],
  "generic": { "open": ["¿{app}? Bah."], "focus": [], "notify": ["Ding. {app}."] }
}
```

- `match` is a case-insensitive substring of the window class
  (`org.gnome.Calculator`, `zen`, `kitty`...); `hyprctl clients` shows them.
  For notifications it matches the sending app's name.
- Apps not in `apps` use `generic`; `{app}` becomes the app's `name` (or the
  class, e.g. "Nautilus"). An empty list means no line.
- She only speaks when free: not asleep, not chatting, not reacting to an agent.
- Notifications are read with `dbus-monitor` (a passive D-Bus monitor): the
  notification daemon is not replaced or touched, and only the app name is
  used, never the text. Needs `dbus-monitor` (package `dbus`).

## Where she rests

`home` picks her corner. `homePoses` is what she does there, as animation
name → weight, e.g. `{"sit": 6, "idle": 2.5, "sleep": 1.5}` (the default) or
`{"work": 1}` to always sit with her laptop. It replaces the default, it is
not merged with it. She still naps when you are away from the computer.

`nagLines` replace her idle lines once you have not clicked or chatted with
her for `nagAfterSec` seconds (default 600); idle chatter stays rate-limited by
`idleChatterMinSec`.

## Optional: a real model

Set `"backend": "ollama"` or `"gemini"` in `~/.config/yorisou/chat.json`.
If the model is unreachable she says one of her `offlineLines` ("Uy, ahora
no puedo hablar...") instead of failing.

### Local model (Ollama in Docker)

```sh
ollama/setup.sh                                   # starts the container, pulls qwen2.5:1.5b
docker compose -f ollama/compose.yml stop         # stop it (frees the RAM)
docker compose -f ollama/compose.yml start        # start it again later
```

- Image pinned to `ollama/ollama:0.40.16`, models in the `ollama-models` volume.
- Listens on `127.0.0.1:11434` only, `restart: unless-stopped` (it comes back
  after a reboot until you `stop` it).
- The model unloads after 10 minutes without chat (`OLLAMA_KEEP_ALIVE`).
- NVIDIA GPU: uncomment the `deploy` block in `ollama/compose.yml` after
  installing `nvidia-container-toolkit`. Without it, it runs on the CPU.

#### Model choice

Two ~1–1.5B models were tested on the CPU (8-core laptop, 16 GB RAM, no GPU in
Docker), same personality prompt, three Spanish questions:

| Model | RAM (container) | First token, cold | First token, warm | Full reply (warm) | Spanish |
|---|---|---|---|---|---|
| **qwen2.5:1.5b** (default) | ~1.26 GiB | 9.1 s | **0.4–0.5 s** | ~2.5 s | correct, natural, uses her catchphrases |
| gemma3:1b | ~1.04 GiB | 6.8 s | 4.5–4.7 s | 6–8 s | very playful and in character, slightly wordier |

`qwen2.5:1.5b` wins for a pet: replies start almost at once once it is loaded,
for ~220 MB more RAM. To try gemma3 instead: `ollama/setup.sh gemma3:1b` and
set `"model": "gemma3:1b"` in your `chat.json`.

### Gemini

```sh
export GEMINI_API_KEY=...        # in your shell profile / session env, never in a file in the repo
```

`~/.config/yorisou/chat.json`:

```json
{ "backend": "gemini", "gemini": { "model": "gemini-2.5-flash" } }
```

The key is read only from the environment variable named in
`gemini.apiKeyEnv` (default `GEMINI_API_KEY`) of the process that starts the
plugin.

## Personality

Copy `config/personality.json` to `~/.config/yorisou/personality.json`
and edit it; only the keys you set override the defaults. Restart the
plugin to apply.

| Key | What it does |
|---|---|
| `name` | her name |
| `character` | sprite folder: `characters/kumo` (default), `sprites` (original chibi), or the name of a folder in `~/.config/yorisou/characters/` (see [sprites.md](sprites.md)); that folder's own `personality.json`, if any, is applied on top |
| `scale` | on-screen size multiplier; `0` uses the character's own (`1` for kumo) |
| `language` | reply language (`es` default) |
| `tone`, `likes`, `backstory`, `catchphrases` | go into her system prompt |
| `home` | her corner: `bottom-right` (default), `bottom-left`, `top-right`, `top-left`, or `roam` to wander every screen |
| `homePoses` | what she does in her corner: animation → weight (see above) |
| `replies`, `fallbackReplies` | scripted chat lines (see above) |
| `nagLines`, `nagAfterSec` | lines when you ignore her for a while (see above) |
| `appReactions` | lines when you open/focus apps or get notifications (see above) |
| `maxReplyWords` | model reply length (bubble-sized; also caps the tokens) |
| `idleLines` | things she says on her own (plus the catchphrases) |
| `idleChatter`, `idleChatterMinSec` | turn idle lines off, or space them out (at most one every `idleChatterMinSec`–2× that) |
| `offlineLines` | what she says when the model is down |

`~/.config/yorisou/chat.json` overrides `config/chat.json`: `backend`
(`scripted`, `ollama`, `gemini`),
`ollama.url`, `ollama.model`, `gemini.model`, `gemini.apiKeyEnv`,
`memoryTurns`, `persistHistory`, `timeoutSec`, `bridgePort`.

With the default scripted backend nothing leaves your machine; with a model,
only to the backend you chose. There is no telemetry.
