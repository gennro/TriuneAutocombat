#!/usr/bin/env bash
# Triune LLM Bridge Launcher Script (Linux / macOS)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v python3 &>/dev/null; then
    exec python3 "${SCRIPT_DIR}/triune_llm_bridge.py" "$@"
elif command -v python &>/dev/null; then
    exec python "${SCRIPT_DIR}/triune_llm_bridge.py" "$@"
else
    echo "[ERROR] Python 3 is required to run the Triune LLM Bridge."
    exit 1
fi
