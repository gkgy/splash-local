"""Local Splash model alias policy. Enabled only by the desktop service launcher."""
import json
import os
from pathlib import Path

OFF_MODEL = "qwen-uncensored-splash-no-thinking"
ON_MODEL = "qwen-uncensored-splash-thinking"
EFFORTS = ("none", "low", "medium", "xhigh")

def resolve(body, fallback):
    config = os.environ.get("SPLASH_LOCAL_POLICY_CONFIG")
    if not config:
        return body.get("reasoning_effort") if body.get("reasoning_effort") is not None else fallback
    if body.get("model") == OFF_MODEL:
        return "none"
    if body.get("model") == ON_MODEL:
        return "low"
    effort = body.get("reasoning_effort")
    if effort is not None:
        return effort
    try:
        prefs = json.loads(Path(config).read_text())
        default = prefs.get("serverThinking", "none")
        return default if default in EFFORTS else fallback
    except (OSError, ValueError, TypeError):
        return fallback
