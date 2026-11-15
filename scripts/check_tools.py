"""Прогон фраз без реального выполнения инструментов: считает, вызывает ли модель нужный инструмент."""
import sys

import ollama

from steve import config, style, tools

PHRASES = [
    ("поставь таймер на 5 минут", "set_timer"),
    ("таймер на 10 минут", "set_timer"),
    ("запусти секундомер", "start_stopwatch"),
    ("открой Safari", "open_app"),
    ("открой заметки", "open_app"),
    ("запиши заметку купить молоко", "create_note"),
    ("сделай потише 30 процентов", "set_volume"),
    ("сколько времени", "get_time"),
    ("сколько заряда", "battery"),
    ("добавь в календарь 23 ноября с 17 до 19 событие зал", "create_event"),
    ("привет как дела", None),
    ("set a timer for 3 minutes", "set_timer"),
]

system = config.SYSTEM_PROMPT
if len(sys.argv) > 1 and sys.argv[1] == "nostyle":
    system = config.SYSTEM_PROMPT

ok = 0
for text, want in PHRASES:
    r = ollama.chat(model=config.LLM_MODEL,
                    messages=[{"role": "system", "content": system}, {"role": "user", "content": text}],
                    tools=tools.SCHEMAS, think=False, options={"temperature": 0.3})
    got = [tc.function.name for tc in (r.message.tool_calls or [])]
    good = (want in got) if want else not got
    ok += good
    print("OK " if good else "BAD", f"{text!r:60} -> {got or r.message.content!r}")
print(f"{ok}/{len(PHRASES)}")
