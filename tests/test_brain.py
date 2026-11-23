"""Tests for bin/chibi-brain: personality prompt, chat streaming, agent bridge."""

import importlib.machinery
import importlib.util
import json
import tempfile
import threading
import unittest
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_loader = importlib.machinery.SourceFileLoader("chibi_brain", str(ROOT / "bin" / "chibi-brain"))
_spec = importlib.util.spec_from_loader("chibi_brain", _loader)
brain = importlib.util.module_from_spec(_spec)
_loader.exec_module(brain)

PERSONA = {
    "name": "Kumo", "language": "es", "tone": "alegre", "likes": ["el té"],
    "backstory": "Vive en tu escritorio.", "catchphrases": ["¡Ánimo!"], "maxReplyWords": 20,
    "offlineLines": ["No puedo hablar ahora"], "idleLines": ["¿Pausa?"],
}


def serve(handler_cls):
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler_cls)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


class FakeOllama(BaseHTTPRequestHandler):
    last_body = None

    def do_POST(self):
        FakeOllama.last_body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.send_response(200)
        self.end_headers()
        for piece in ("¡Ho", "la!", ""):
            self.wfile.write(json.dumps({"message": {"content": piece}, "done": piece == ""}).encode() + b"\n")

    def log_message(self, *args):
        pass


class ConfigTest(unittest.TestCase):
    def test_user_file_overrides_defaults_and_merges_nested(self):
        with tempfile.TemporaryDirectory() as tmp:
            defaults, user = Path(tmp, "d"), Path(tmp, "u")
            defaults.mkdir()
            user.mkdir()
            (defaults / "chat.json").write_text(json.dumps({"backend": "ollama", "ollama": {"model": "a", "url": "u"}}))
            (user / "chat.json").write_text(json.dumps({"ollama": {"model": "b"}}))
            config = brain.load_config("chat.json", defaults, user)
        self.assertEqual(config, {"backend": "ollama", "ollama": {"model": "b", "url": "u"}})

    def test_repo_defaults_are_valid(self):
        persona = json.loads((ROOT / "config" / "personality.json").read_text())
        chat = json.loads((ROOT / "config" / "chat.json").read_text())
        for key in ("name", "language", "tone", "likes", "backstory", "catchphrases", "maxReplyWords",
                    "replies", "fallbackReplies", "home"):
            self.assertIn(key, persona)
        self.assertEqual(chat["backend"], "scripted")  # no model, no network by default
        self.assertEqual(chat["ollama"]["url"], "http://127.0.0.1:11434")
        self.assertEqual(chat["gemini"], {"model": chat["gemini"]["model"], "apiKeyEnv": "GEMINI_API_KEY"})  # key only from env


class CharacterTest(unittest.TestCase):
    def make_char(self, base: Path, name: str, preset=None) -> Path:
        d = base / name
        d.mkdir(parents=True)
        (d / "sprites.json").write_text('{"idle": {"frameWidth": 1, "frameHeight": 1, "frameCount": 1}}')
        if preset is not None:
            (d / "personality.json").write_text(json.dumps(preset))
        return d

    def test_user_character_dir_wins_and_preset_merges(self):
        with tempfile.TemporaryDirectory() as tmp:
            defaults, user = Path(tmp) / "defaults", Path(tmp) / "user"
            defaults.mkdir()
            (defaults / "personality.json").write_text(json.dumps(PERSONA))
            user.mkdir()
            (user / "personality.json").write_text('{"character": "ellen"}')
            ellen = self.make_char(user / "characters", "ellen", {"name": "Ellen", "tone": "perezosa"})
            persona = brain.load_persona(defaults, user, root=Path(tmp) / "repo")
        self.assertEqual(persona["character"], str(ellen))
        self.assertEqual(persona["name"], "Ellen")
        self.assertEqual(persona["tone"], "perezosa")
        self.assertEqual(persona["likes"], ["el té"])  # untouched keys keep the defaults

    def test_repo_relative_and_missing_characters(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo, user = Path(tmp) / "repo", Path(tmp) / "user"
            kumo = self.make_char(repo / "characters", "kumo")
            sprites = self.make_char(repo, "sprites")
            self.assertEqual(brain.resolve_character("sprites", repo, user), sprites)
            self.assertEqual(brain.resolve_character("characters/kumo", repo, user), kumo)
            self.assertEqual(brain.resolve_character("kumo", repo, user), kumo)
            self.assertEqual(brain.resolve_character(str(sprites), repo, user), sprites)
            self.assertEqual(brain.resolve_character("nobody", repo, user), kumo)


class PromptTest(unittest.TestCase):
    def test_system_prompt_uses_personality(self):
        prompt = brain.system_prompt(PERSONA)
        for fragment in ("Kumo", "alegre", "el té", "Vive en tu escritorio.", "¡Ánimo!", "20 palabras", "español"):
            self.assertIn(fragment, prompt)

    def test_english_persona_gets_english_prompt(self):
        prompt = brain.system_prompt(dict(PERSONA, language="en"))
        self.assertIn("You are Kumo", prompt)
        self.assertIn("at most 20 words", prompt)


class MemoryTest(unittest.TestCase):
    def test_keeps_last_n_turns_and_persists(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp, "h.json")
            memory = brain.Memory(2, path)
            for i in range(3):
                memory.add(f"q{i}", f"a{i}")
            self.assertEqual([m["content"] for m in memory.messages()], ["q1", "a1", "q2", "a2"])
            self.assertEqual(len(brain.Memory(2, path).turns), 2)
            memory.clear()
            self.assertFalse(path.exists())


class ChatTest(unittest.TestCase):
    def run_chat(self, chat_cfg, backends=brain.BACKENDS):
        events = []
        b = brain.Brain(PERSONA, chat_cfg, events.append, backends)
        b.ask("hola")
        return b, events

    def test_ollama_streams_tokens_and_remembers(self):
        server = serve(FakeOllama)
        try:
            url = f"http://127.0.0.1:{server.server_port}"
            b, events = self.run_chat({"backend": "ollama", "ollama": {"url": url, "model": "m"}})
        finally:
            server.shutdown()
        self.assertEqual([e["t"] for e in events], ["chat-start", "chat-token", "chat-token", "chat-end"])
        self.assertEqual("".join(e.get("text", "") for e in events), "¡Hola!")
        self.assertEqual(b.memory.messages()[-1], {"role": "assistant", "content": "¡Hola!"})
        sent = FakeOllama.last_body
        self.assertEqual(sent["model"], "m")
        self.assertEqual(sent["messages"][0]["role"], "system")
        self.assertTrue(sent["stream"])

    def test_backend_down_gives_friendly_line(self):
        b, events = self.run_chat({"backend": "ollama", "ollama": {"url": "http://127.0.0.1:9"}, "timeoutSec": 2})
        self.assertEqual(events[-1], {"t": "chat-error", "id": 1, "text": "No puedo hablar ahora"})
        self.assertEqual(b.memory.messages(), [])

    def test_gemini_without_key_is_friendly(self):
        cfg = {"backend": "gemini", "gemini": {"apiKeyEnv": "CHIBI_TEST_NO_SUCH_KEY"}}
        _, events = self.run_chat(cfg)
        self.assertEqual(events[-1]["t"], "chat-error")


class ScriptedChatTest(unittest.TestCase):
    PERSONA = dict(PERSONA, replies=[
        {"keywords": ["hola", "buenas"], "lines": ["Hola, {name}.", "Buenas, ¿qué hay?"]},
        {"keywords": ["dulce", "comida"], "lines": ["¿Trajiste dulces?"]},
    ], fallbackReplies=["Mmm.", "Ajá."])

    def ask(self, text, persona=None):
        events = []
        b = brain.Brain(persona or self.PERSONA, {"backend": "scripted"}, events.append,
                        dict(brain.BACKENDS, ollama=None, gemini=None))
        b.ask(text)
        return events

    def answer(self, events):
        return "".join(e["text"] for e in events if e["t"] == "chat-token")

    def test_keyword_reply_without_any_network(self):
        events = self.ask("¡HOLÁ! qué tal")  # case and accents do not matter
        self.assertIn(self.answer(events), ["Hola, Kumo.", "Buenas, ¿qué hay?"])
        self.assertEqual(events[0]["t"], "chat-start")
        self.assertEqual(events[-1]["t"], "chat-end")
        self.assertGreater(sum(e["t"] == "chat-token" for e in events), 1)  # streams in pieces

    def test_keyword_prefix_matches_plural(self):
        self.assertEqual(self.answer(self.ask("me das dulces")), "¿Trajiste dulces?")

    def test_unknown_text_uses_fallbacks(self):
        self.assertIn(self.answer(self.ask("xyzzy")), ["Mmm.", "Ajá."])

    def test_does_not_repeat_the_same_line_twice_in_a_row(self):
        events = []
        b = brain.Brain(self.PERSONA, {"backend": "scripted"}, events.append)
        answers = []
        for _ in range(6):
            events.clear()
            b.ask("hola")
            answers.append(self.answer(events))
        self.assertTrue(all(a != b2 for a, b2 in zip(answers, answers[1:])))

    def test_persona_without_replies_still_answers(self):
        self.assertTrue(self.answer(self.ask("hola", PERSONA)))


class AgentTest(unittest.TestCase):
    def setUp(self):
        self.tracker = brain.AgentTracker("es")

    def test_claude_code_hook_flow(self):
        t = self.tracker
        self.assertEqual(t.handle({"hook_event_name": "UserPromptSubmit"}), [("thinking", "")])
        self.assertEqual(t.handle({"hook_event_name": "PreToolUse", "tool_name": "Edit",
                                   "tool_input": {"file_path": "/x/Service.qml"}}), [("working", "Editando Service.qml")])
        self.assertEqual(t.handle({"hook_event_name": "Notification", "message": "needs permission"}),
                         [("needs", "needs permission")])
        self.assertEqual(t.handle({"hook_event_name": "PreToolUse", "tool_name": "Bash",
                                   "tool_input": {"command": "ls", "description": "List files"}}),
                         [("thanks", ""), ("working", "Ejecutando List files")])
        self.assertEqual(t.handle({"hook_event_name": "PostToolUseFailure", "tool_name": "Bash",
                                   "tool_input": {"command": "ls"}}), [("oops", "Ejecutando ls")])
        self.assertEqual(t.handle({"hook_event_name": "Stop"}), [("done", "")])

    def test_post_tool_use_error_is_oops_and_success_is_silent(self):
        ok = {"hook_event_name": "PostToolUse", "tool_name": "Read", "tool_input": {}, "tool_response": {}}
        bad = dict(ok, tool_response={"is_error": True})
        self.assertEqual(self.tracker.handle(ok), [])
        self.assertEqual(self.tracker.handle(bad)[0][0], "oops")

    def test_unknown_event_is_ignored(self):
        self.assertEqual(self.tracker.handle({"hook_event_name": "PreCompact"}), [])


class BridgeTest(unittest.TestCase):
    def setUp(self):
        self.events = []
        self.brain = brain.Brain(PERSONA, {}, self.events.append, {})
        self.server = serve(brain.make_handler(self.brain))
        self.url = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()

    def post(self, path, body, headers=None):
        request = urllib.request.Request(self.url + path, data=json.dumps(body).encode(), headers=headers or {})
        try:
            return urllib.request.urlopen(request, timeout=3).status
        except urllib.error.HTTPError as error:
            return error.code

    def test_hook_with_header_reaches_the_pet(self):
        status = self.post("/hook", {"hook_event_name": "Stop"}, {"X-Chibi": "1", "X-Agent-Pid": "42"})
        self.assertEqual(status, 204)
        self.assertEqual(self.events, [{"t": "agent", "state": "done", "detail": ""}])
        self.assertEqual(self.brain.tracker.pid, 42)

    def test_request_without_header_is_refused(self):
        self.assertEqual(self.post("/hook", {"hook_event_name": "Stop"}), 403)
        self.assertEqual(self.events, [])

    def test_generic_event_endpoint(self):
        self.assertEqual(self.post("/event", {"state": "working", "detail": "compilando"}, {"X-Chibi": "1"}), 204)
        self.assertEqual(self.post("/event", {"state": "bogus"}, {"X-Chibi": "1"}), 204)
        self.assertEqual(self.events, [{"t": "agent", "state": "working", "detail": "compilando"}])


if __name__ == "__main__":
    unittest.main()
