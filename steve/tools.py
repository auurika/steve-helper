"""Действия, которые помощник умеет выполнять. Всё локально и безопасно."""
import subprocess
import threading
import time
from datetime import datetime

from . import config


def open_app(name: str) -> str:
    r = subprocess.run(["open", "-a", name], capture_output=True, text=True)
    return f"Открыл {name}" if r.returncode == 0 else f"Не нашёл приложение {name}"


def set_volume(percent: int) -> str:
    percent = max(0, min(100, int(percent)))
    subprocess.run(["osascript", "-e", f"set volume output volume {percent}"], check=False)
    return f"Громкость {percent}%"


_WEEKDAYS = ["понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"]


def get_time() -> str:
    n = datetime.now()
    return f"{n:%H:%M}, {n:%d.%m.%Y}, {_WEEKDAYS[n.weekday()]}"


def battery() -> str:
    r = subprocess.run(["pmset", "-g", "batt"], capture_output=True, text=True)
    return r.stdout.strip()


def _osa(script: str, *args: str) -> subprocess.CompletedProcess:
    """Запускает AppleScript, аргументы передаются через argv (без подстановки в текст скрипта)."""
    return subprocess.run(["osascript", "-e", script, *args], capture_output=True, text=True)


_NOTE_SCRIPT = '''on run argv
    tell application "Notes"
        make new note with properties {name:(item 1 of argv), body:(item 2 of argv)}
    end tell
    return "ok"
end run'''


def create_note(text: str) -> str:
    """Создаёт заметку в стандартном приложении «Заметки»."""
    title = text.strip().split("\n")[0][:40] or "Заметка"
    r = _osa(_NOTE_SCRIPT, title, text)
    return "Заметка создана в приложении «Заметки»" if r.returncode == 0 else f"Не получилось создать заметку: {r.stderr.strip()}"


_EVENT_SCRIPT = '''on mk(y, mo, d, h, mi)
    set dt to current date
    set day of dt to 1
    set year of dt to (y as integer)
    set month of dt to (mo as integer)
    set day of dt to (d as integer)
    set time of dt to ((h as integer) * 3600 + (mi as integer) * 60)
    return dt
end mk
on run argv
    set startD to my mk(item 2 of argv, item 3 of argv, item 4 of argv, item 5 of argv, item 6 of argv)
    set endD to my mk(item 7 of argv, item 8 of argv, item 9 of argv, item 10 of argv, item 11 of argv)
    tell application "Calendar"
        set cname to item 12 of argv
        if cname is "" then
            set theCal to first calendar whose writable is true
        else
            set theCal to first calendar whose name is cname
        end if
        tell theCal to make new event with properties {summary:(item 1 of argv), start date:startD, end date:endD}
    end tell
    return "ok"
end run'''


def create_event(title: str, start: str, end: str, calendar: str = "") -> str:
    """Добавляет событие в «Календарь». start/end в формате YYYY-MM-DD HH:MM."""
    try:
        a = datetime.strptime(start.strip(), "%Y-%m-%d %H:%M")
        b = datetime.strptime(end.strip(), "%Y-%m-%d %H:%M")
    except ValueError:
        return "Неверный формат времени, нужен YYYY-MM-DD HH:MM"
    if b <= a:
        return "Конец события раньше начала"
    r = _osa(_EVENT_SCRIPT, title, str(a.year), str(a.month), str(a.day), str(a.hour), str(a.minute),
             str(b.year), str(b.month), str(b.day), str(b.hour), str(b.minute), calendar)
    if r.returncode != 0:
        return f"Не получилось добавить событие: {r.stderr.strip()}"
    return f"Событие «{title}» добавлено в «Календарь»: {a:%d.%m %H:%M}–{b:%H:%M}"


_stopwatch_start: float | None = None


def start_stopwatch() -> str:
    global _stopwatch_start
    _stopwatch_start = time.monotonic()
    return "Секундомер запущен"


def stop_stopwatch() -> str:
    global _stopwatch_start
    if _stopwatch_start is None:
        return "Секундомер не был запущен"
    sec = int(time.monotonic() - _stopwatch_start)
    _stopwatch_start = None
    return f"Секундомер остановлен: {sec // 60} мин {sec % 60} сек"


def set_timer(seconds: int, label: str = "") -> str:
    seconds = max(1, int(seconds))

    def ring():
        subprocess.run(["osascript", "-e", f'display notification "{label or "Таймер"}" with title "{config.NAME}"'])
        subprocess.run(["say", "-v", config.VOICES["ru"], f"Таймер сработал. {label}"])

    t = threading.Timer(seconds, ring)
    t.daemon = True
    t.start()
    return f"Таймер на {seconds} сек. запущен"


FUNCS = {f.__name__: f for f in (open_app, set_volume, get_time, battery, create_note, set_timer,
                                 create_event, start_stopwatch, stop_stopwatch)}

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
        "name": "create_note", "description": "Создать заметку в приложении Заметки",
        "parameters": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}}},
    {"type": "function", "function": {
        "name": "set_timer", "description": "Поставить таймер на N секунд (минуты переведи в секунды)",
        "parameters": {"type": "object", "properties": {
            "seconds": {"type": "integer"}, "label": {"type": "string"}}, "required": ["seconds"]}}},
    {"type": "function", "function": {
        "name": "create_event", "description": "Добавить событие в приложение Календарь. Время в формате YYYY-MM-DD HH:MM. Год бери так, чтобы дата была ближайшей будущей",
        "parameters": {"type": "object", "properties": {
            "title": {"type": "string"}, "start": {"type": "string"}, "end": {"type": "string"}},
            "required": ["title", "start", "end"]}}},
    {"type": "function", "function": {
        "name": "start_stopwatch", "description": "Запустить секундомер",
        "parameters": {"type": "object", "properties": {}}}},
    {"type": "function", "function": {
        "name": "stop_stopwatch", "description": "Остановить секундомер и узнать время",
        "parameters": {"type": "object", "properties": {}}}},
]


def call(name: str, args: dict) -> str:
    fn = FUNCS.get(name)
    if not fn:
        return f"Неизвестный инструмент {name}"
    try:
        return str(fn(**args))
    except Exception as e:  # noqa: BLE001 — отдаём ошибку модели, а не падаем
        return f"Ошибка: {e}"
