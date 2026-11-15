"""Диалог с локальной моделью через Ollama + вызов инструментов.

Два этапа, потому что стиль в одном промпте с инструментами ломает их вызов
(модель начинает просто «отвечать» вместо действия):
1. Действие: промпт без стиля, модель решает, какой инструмент вызвать.
2. Манера: отдельный короткий вызов переписывает итоговую фразу в стиле пользователя.
"""
import re
from datetime import datetime

import ollama

from . import config, style, tools

_REWRITE_RULES = (
    " Ты переписываешь готовый ответ ассистента в своей манере. "
    "Сохрани весь смысл, числа, время и названия, ничего не добавляй и не выдумывай. "
    "Язык оставь тот же, что в ответе. Выведи только итоговую фразу."
)


class Brain:
    def __init__(self) -> None:
        self.history: list[dict] = []

    def _restyle(self, user_text: str, raw: str) -> str:
        # Ответы с латиницей (названия приложений, английский язык) модель при переписывании
        # портит («Safari» -> «сайфари»), поэтому для них только лёгкая правка без LLM.
        if re.search(r"[A-Za-z]{3,}", raw):
            return style.finalize(raw)
        try:
            resp = ollama.chat(
                model=config.LLM_MODEL,
                messages=[
                    {"role": "system", "content": style.style_prompt() + _REWRITE_RULES},
                    {"role": "user", "content": f"Вопрос пользователя: {user_text}\nОтвет ассистента: {raw}"},
                ],
                think=False,
                options={"temperature": 0.4},
            )
            text = (resp.message.content or "").strip()
        except Exception:  # noqa: BLE001 — стиль не должен ломать ответ
            text = ""
        return style.finalize(text or raw)

    def ask(self, user_text: str) -> str:
        self.history.append({"role": "user", "content": user_text})
        self.history = self.history[-config.HISTORY_TURNS * 4:]
        now = datetime.now().strftime("%Y-%m-%d %H:%M, %A")
        system = f"{config.SYSTEM_PROMPT} Сейчас: {now}."
        messages = [{"role": "system", "content": system}, *self.history]

        msg = None
        for _ in range(4):  # максимум 4 раунда вызова инструментов
            resp = ollama.chat(model=config.LLM_MODEL, messages=messages,
                               tools=tools.SCHEMAS, think=False, options={"temperature": 0.3})
            msg = resp.message
            messages.append(msg)
            if not msg.tool_calls:
                break
            for tc in msg.tool_calls:
                result = tools.call(tc.function.name, dict(tc.function.arguments))
                print(f"  [tool] {tc.function.name}({dict(tc.function.arguments)}) -> {result}")
                messages.append({"role": "tool", "tool_name": tc.function.name, "content": result})

        raw = ((msg.content if msg else "") or "").strip() or "Готово."
        answer = self._restyle(user_text, raw)
        # В историю идёт нейтральный ответ, а не «стильный»: иначе на следующем шаге модель
        # копирует короткие ответы и перестаёт вызывать инструменты.
        self.history.append({"role": "assistant", "content": raw})
        return answer
