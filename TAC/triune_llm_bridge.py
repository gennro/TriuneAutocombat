#!/usr/bin/env python3
"""
Triune LLM Bridge — External Asynchronous Daemon for MacroQuest

Connects MacroQuest's triune_test.lua to local LLMs (LM Studio, Ollama)
and cloud LLMs (Google Gemini, OpenCode, OpenRouter, OpenAI) without
ever blocking or halting eqgame.exe.

Communicates with Lua via high-speed, non-blocking mailbox file IPC.
Uses Python 3 standard library only (zero pip dependencies).
"""

import sys
import os
import json
import time
import urllib.request
import urllib.error
import argparse
import traceback
import threading

VERSION = "1.0.1"

# Default fallback URLs
DEFAULT_URLS = {
    "lmstudio": "http://localhost:1234/v1/chat/completions",
    "gemini": "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
    "opencode": "https://openrouter.ai/api/v1/chat/completions",
    "openai": "https://api.openai.com/v1/chat/completions",
}

def find_default_watch_dir():
    """Locate the best directory to use for IPC mailbox files."""
    candidates = [
        # Check relative to script
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "config")),
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "config")),
        os.path.abspath(os.path.join(os.path.dirname(__file__), "config")),
        os.path.abspath(os.path.dirname(__file__)),
        os.getcwd(),
    ]
    for c in candidates:
        if os.path.isdir(c):
            return c
    return os.getcwd()


def call_llm(endpoint_url, api_key, model, messages, temperature=0.2, timeout=60, force_json=True):
    """Make HTTP POST to OpenAI-compatible endpoint with optional JSON grammar enforcement."""
    def _do_post(include_json_format):
        payload = {
            "model": model or "default",
            "messages": messages,
            "temperature": float(temperature) if temperature is not None else 0.2,
        }
        if include_json_format:
            payload["response_format"] = {"type": "json_object"}

        data = json.dumps(payload).encode("utf-8")
        headers = {
            "Content-Type": "application/json",
            "User-Agent": f"TriuneLLMBridge/{VERSION}",
        }
        if api_key and api_key.strip():
            headers["Authorization"] = f"Bearer {api_key.strip()}"

        req = urllib.request.Request(endpoint_url, data=data, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8")
            parsed = json.loads(body)
            choices = parsed.get("choices", [])
            if choices and len(choices) > 0:
                msg = choices[0].get("message", {})
                content = msg.get("content", "")
                return {"ok": True, "content": content, "raw": parsed}
            return {"ok": True, "content": body, "raw": parsed}

    try:
        try:
            return _do_post(include_json_format=force_json)
        except urllib.error.HTTPError as he:
            # If server rejects response_format (e.g. 400 Bad Request), retry once without it
            if force_json and he.code == 400:
                return _do_post(include_json_format=False)
            raise
    except urllib.error.HTTPError as e:
        err_body = ""
        try:
            err_body = e.read().decode("utf-8")
        except Exception:
            pass
        return {"ok": False, "error": f"HTTP {e.code} {e.reason}: {err_body}"}
    except urllib.error.URLError as e:
        return {"ok": False, "error": f"Network error: {e.reason}"}
    except Exception as e:
        return {"ok": False, "error": f"Request exception: {str(e)}"}


def heartbeat_worker(heartbeat_file, stop_event):
    """Background thread that pulses heartbeat every 1 second without blocking."""
    while not stop_event.is_set():
        try:
            with open(heartbeat_file, "w") as hf:
                hf.write(f"{time.time():.3f}\n")
        except Exception:
            pass
        stop_event.wait(1.0)


def run_bridge(watch_dir):
    print(f"============================================================")
    print(f" Triune LLM Bridge v{VERSION} — Asynchronous MQ Daemon")
    print(f" Watch Directory (Mailbox IPC): {watch_dir}")
    print(f" Press Ctrl+C to stop.")
    print(f"============================================================")

    req_file = os.path.join(watch_dir, "triune_bridge_req.json")
    req_ready = os.path.join(watch_dir, "triune_bridge_req.ready")
    res_file = os.path.join(watch_dir, "triune_bridge_res.json")
    res_ready = os.path.join(watch_dir, "triune_bridge_res.ready")
    heartbeat_file = os.path.join(watch_dir, "triune_bridge_heartbeat.tmp")

    # Clean up stale IPC files from previous runs
    for f in [req_ready, res_ready]:
        try:
            if os.path.exists(f):
                os.remove(f)
        except OSError:
            pass

    stop_event = threading.Event()
    hb_thread = threading.Thread(target=heartbeat_worker, args=(heartbeat_file, stop_event), daemon=True)
    hb_thread.start()

    try:
        while True:
            # Check if a request is ready
            if os.path.exists(req_ready):
                print(f"[{time.strftime('%H:%M:%S')}] Detected incoming request from MacroQuest...")
                # Remove ready marker immediately to prevent double processing
                try:
                    os.remove(req_ready)
                except OSError:
                    pass

                req_data = None
                try:
                    with open(req_file, "r", encoding="utf-8") as rf:
                        req_data = json.load(rf)
                except Exception as e:
                    print(f"[ERR] Failed to read request JSON: {e}", file=sys.stderr)
                    err_res = {"ok": False, "error": f"Bridge failed to read req.json: {e}"}
                    with open(res_file, "w", encoding="utf-8") as out_f:
                        json.dump(err_res, out_f)
                    with open(res_ready, "w") as out_r:
                        out_r.write("1")
                    continue

                req_id = req_data.get("id", 0)
                provider = req_data.get("provider", "lmstudio").lower()
                url = req_data.get("url") or DEFAULT_URLS.get(provider, DEFAULT_URLS["lmstudio"])
                api_key = req_data.get("apiKey", "")
                model = req_data.get("model", "")
                messages = req_data.get("messages", [])
                temperature = req_data.get("temperature", 0.2)
                timeout = req_data.get("timeout", 60)

                print(f"[{time.strftime('%H:%M:%S')}] Calling {provider} ({model}) at {url} (ID: {req_id})...")
                start_t = time.time()

                res = call_llm(url, api_key, model, messages, temperature, timeout)
                elapsed = time.time() - start_t
                res["id"] = req_id
                res["elapsed"] = round(elapsed, 2)

                if res.get("ok"):
                    preview = (res.get("content") or "").strip().replace("\n", " ")[:80]
                    print(f"[{time.strftime('%H:%M:%S')}] Response received in {elapsed:.2f}s: {preview}...")
                else:
                    print(f"[{time.strftime('%H:%M:%S')}] Request failed in {elapsed:.2f}s: {res.get('error')}")

                try:
                    with open(res_file, "w", encoding="utf-8") as out_f:
                        json.dump(res, out_f)
                    with open(res_ready, "w") as out_r:
                        out_r.write("1")
                except Exception as e:
                    print(f"[ERR] Failed to write response JSON: {e}", file=sys.stderr)

            time.sleep(0.05)

    except KeyboardInterrupt:
        print("\nStopping Triune LLM Bridge...")
    finally:
        stop_event.set()
        # Cleanup
        for f in [heartbeat_file, req_ready, res_ready]:
            try:
                if os.path.exists(f):
                    os.remove(f)
            except OSError:
                pass
        print("Bridge stopped.")


def main():
    parser = argparse.ArgumentParser(description="Triune LLM External Daemon Bridge")
    parser.add_argument("--watch-dir", default=None, help="Directory to watch for IPC mailbox files")
    parser.add_argument("--test", action="store_true", help="Send a test ping to the local LM Studio server")
    parser.add_argument("--url", default=None, help="Test endpoint URL")
    parser.add_argument("--model", default="local-model", help="Test model name")
    parser.add_argument("--key", default="", help="API key for test")
    args = parser.parse_args()

    if args.test:
        test_url = args.url or DEFAULT_URLS["lmstudio"]
        print(f"Testing connection to {test_url} (model: {args.model})...")
        res = call_llm(test_url, args.key, args.model, [{"role": "user", "content": "Respond with 'PONG'"}])
        print("Result:", json.dumps(res, indent=2))
        return

    watch_dir = args.watch_dir
    if not watch_dir:
        watch_dir = find_default_watch_dir()
    os.makedirs(watch_dir, exist_ok=True)
    run_bridge(watch_dir)


if __name__ == "__main__":
    main()
