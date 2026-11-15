"""Действия, которые помощник умеет выполнять. Всё локально и безопасно."""
import subprocess
import threading
from datetime import datetime

from . import config


def open_app(name: str) -> str:
    r = subprocess.run(["open", "-a", name], capture_output=True, text=True)
    return f"Открыл {name}" if r.returncode == 0 else f"Не нашёл приложение {name}"


def set_volume(percent: int) -> str:
    percent = max(0, min(100, int(percent)))
    subprocess.run(["osascript", "-e", f"set volume output volume {percent}"], check=False)
    return f"Громкость {percent}%"


def get_time() -> str:
    return datetime.now().strftime("%H:%M, %d.%m.%Y, %A")


def battery() -> str:
    r = subprocess.run(["pmset", "-g", "batt"], capture_output=True, text=True)
    return r.stdout.strip()


def create_note(text: str) -> str:
    config.NOTES_DIR.mkdir(parents=True, exist_ok=True)
    path = config.NOTES_DIR / "notes.md"
    with path.open("a", encoding="utf-8") as f:
        f.write(f"- [{datetime.now():%Y-%m-%d %H:%M}] {text}\n")
    return "Заметка сохранена"


def set_timer(seconds: int, label: str = "") -> str:
    seconds = max(1, int(seconds))

    def ring():
        subprocess.run(["osascript", "-e", f'display notification "{label or "Таймер"}" with title "{config.NAME}"'])
        subprocess.run(["say", "-v", config.VOICES["ru"], f"Таймер сработал. {label}"])

    t = threading.Timer(seconds, ring)
    t.daemon = True
    t.start()
    return f"Таймер на {seconds} сек. запущен"


FUNCS = {f.__name__: f for f in (open_app, set_volume, get_time, battery, create_note, set_timer)}

# Описание для LLM (формат tool calling)
SCHEMAS = [
    {"type": "function", "function": {
        "name": "open_app", "description": "Открыть приложение на Mac по имени (Safari, Notes, Telegram...)",
        "parameters": {"type": "object", "properties": {"name": {"type": "string"}}, "required": ["name"]}}},
    {"type": "function", "function": {
        "name": "set_volume", "description": "Установить громкость системы, 0-100",
        "parameters": {"type": "object", "properties": {"percent": {"type": "integer"}}, "required": ["percent"]}}},
    {"type": "function", "function": {
        "name": "get_time", "description": "Текущие время и дата",
        "parameters": {"type": "object", "properties": {}}}},
    {"type": "function", "function": {
        "name": "battery", "description": "Уровень заряда батареи MacBook",
        "parameters": {"type": "object", "properties": {}}}},
    {"type": "function", "function": {
        "name": "create_note", "description": "Сохранить заметку пользователя",
        "parameters": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}}},
    {"type": "function", "function": {
        "name": "set_timer", "description": "Поставить таймер на N секунд (минуты переведи в секунды)",
        "parameters": {"type": "object", "properties": {
            "seconds": {"type": "integer"}, "label": {"type": "string"}}, "required": ["seconds"]}}},
]


def call(name: str, args: dict) -> str:
    fn = FUNCS.get(name)
    if not fn:
        return f"Неизвестный инструмент {name}"
    try:
        return str(fn(**args))
    except Exception as e:  # noqa: BLE001 — отдаём ошибку модели, а не падаем
        return f"Ошибка: {e}"
