# steve-helper

Офлайн голосовой помощник для macOS (Apple Silicon).

- `mockup/index.html` — кликабельный макет интерфейса
- `steve/` — рабочий прототип на Python (Whisper → Qwen через Ollama → macOS `say`)

Запуск прототипа: `uv sync --python 3.12 && uv run steve` (или `--text` для клавиатуры).

Цель: самодостаточное `.app`, где модели и всё нужное лежат внутри пакета.
