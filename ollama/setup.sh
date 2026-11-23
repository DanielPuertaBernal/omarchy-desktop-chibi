#!/usr/bin/env bash
# Start the local Ollama container and pull the chibi's chat model.
# Usage: ollama/setup.sh [model]      (default: qwen2.5:1.5b)
set -euo pipefail

MODEL="${1:-qwen2.5:1.5b}"
DIR="$(cd "$(dirname "$0")" && pwd)"

docker compose -f "$DIR/compose.yml" up -d

# Wait for the API (127.0.0.1 only).
for _ in $(seq 1 30); do
  curl -fs http://127.0.0.1:11434/api/version >/dev/null && break
  sleep 1
done

docker exec danso-chibi-ollama ollama pull "$MODEL"
echo "Ready. Model: $MODEL"
echo "If you picked another model, set it in ~/.config/danso-chibi/chat.json:"
echo "  { \"ollama\": { \"model\": \"$MODEL\" } }"
echo "Stop it with: docker compose -f $DIR/compose.yml stop"
