[简体中文](README.md) | **English**

# Splash Local

A native Splash desktop app for Apple Silicon Macs, built with Cocoa + WKWebView and connected to a local Splash service. It runs independently of Bionic. This is a personal client, not an official Inco AI application.

## Features

- Local streaming chat, multiple conversation histories, generation cancellation, and JSON chat export.
- Native service-status panel, service start / stop controls, and log viewing.
- Output speed, output token count, and time-to-first-token statistics. Values are estimated during generation and use server statistics after completion.
- Thinking toggle, temperature / top_p / top_k / max_tokens, and system-prompt settings.
- GPU memory, context, disk-cache, and KV-precision settings.
- Shared reasoning policy with a standard model entry and aliases that force thinking off or low.

## Build and open

Requires macOS 14 or later and Xcode Command Line Tools.

```sh
bash build.sh
open "build/Splash Local.app"
```

The generated app is ad-hoc signed and has not been notarized by Apple. This repository includes only client source, icons, and local service-launch helpers. It does not include the Splash engine, model weights, or user configuration.

## Existing service dependencies

The current version was written for the author's Splash 1.1.0 + Qwen 27B setup. It is not an automatic installer. On another Mac, first configure a compatible Splash service:

- URL: `http://127.0.0.1:8000`; model name: `qwen-uncensored-splash`.
- Authentication: `auth.api_key` in `~/.omlx/settings.json`, read at runtime and not published in this repository.
- Launch helper: `~/.local/share/splash-qwen/ensure-server.py`.
- launchd: `~/Library/LaunchAgents/local.splash.qwen-uncensored.plist`.
- Service log: `~/.local/share/splash-qwen/server.log`.

`service/` contains the current launch scripts for reference. `serve.py` defaults to the runtime in `~/.local/lib/splash-1.1.0` and reads the model-bundle path from `~/.local/share/splash-qwen/vision-bundle.txt`. The bundle must contain `target`, `draft`, and `tokenizer`. Configure launchd for your actual installation paths. The repository does not download models or modify the running service.

App settings are stored in `~/Library/Application Support/Splash Local/preferences.json`. Chats are stored in WKWebView local storage. Closing the app leaves the shared service running; clicking Stop disconnects other clients using that service.

## Shared reasoning policy

API Base URL: `http://127.0.0.1:8000/v1`.

| Model alias | Behavior |
| --- | --- |
| `qwen-uncensored-splash-no-thinking` | Force none |
| `qwen-uncensored-splash-thinking` | Force low |
| `qwen-uncensored-splash` | Prefer the request setting; otherwise read the shared default |

`local_reasoning_policy.py` is a local extension. Call its `resolve(body, fallback)` from the Splash server's `_prepare_prompt`, and set `SPLASH_LOCAL_POLICY_CONFIG` to the preferences-file path above. Registering aliases alone does not enable this policy. This repository does not copy upstream frontend.py; recheck the integration point when upgrading the server.

After configuring the service, use `python3 verify-shared-thinking.py` to verify it with real requests. This script calls the locally loaded model and is not a purely offline test.

## Scope

Image input depends on the server model and frontend. This repository does not include a vision installation / conversion workflow, and image input has not been verified on a fresh machine. It currently does not include MCP, a file-execution agent, speech transcription, model download management, or project workspaces.

The upstream engine and web chat interface come from [Inco AI Splash](https://github.com/incoai/splash). Install them independently and comply with their license. Models also retain their respective licenses.

## Privacy and security

- API keys are read only from local configuration. Source code contains no embedded keys; do not commit your actual `settings.json` or `.env`.
- The service binds to `127.0.0.1` by default. Access from other devices requires your own authentication and secure transport; direct exposure to the public internet is discouraged.
- Chat histories, system prompts, preferences, and logs are local user data and are not included in this repository. Exported chat JSON may contain private content; handle it accordingly.
- `.gitignore` excludes build outputs, logs, common configuration, model weights, and old backups. It does not replace a pre-commit review. Check new files and screenshots for personal information.
- The client requests inference and token statistics from the local service. `telemetry.js` records local generation metrics; no external analytics service is configured.
