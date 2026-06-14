import json

settings = {
    "coreTools": {
        "memory": {
            "enabled": True,
            "path": "/home/mbuser/.gemini/memory"
        }
    },
    "customInstructions": "Du bist ein AI-Assistent auf MB-OS. Lies bei jeder Session ~/.gemini/memory/Memory.md und ~/.gemini/memory/User.md. Aktualisiere die Memory-Dateien mit neuen Erkenntnissen. Der Memory Daemon laeuft auf http://localhost:8765. Sprache: Deutsch."
}

with open("/home/mbuser/.gemini/config/settings.json", "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
print("settings.json written!")
