"""Диалог с локальной моделью через Ollama + вызов инструментов."""
import ollama

from . import config, tools


class Brain:
    def __init__(self) -> None:
        self.history: list[dict] = []

    def ask(self, user_text: str) -> str:
        self.history.append({"role": "user", "content": user_text})
        self.history = self.history[-config.HISTORY_TURNS * 4:]
        messages = [{"role": "system", "content": config.SYSTEM_PROMPT}, *self.history]

        for _ in range(4):  # максимум 4 раунда вызова инструментов
            resp = ollama.chat(model=config.LLM_MODEL, messages=messages,
                               tools=tools.SCHEMAS, think=False)
            msg = resp.message
            messages.append(msg)
            if not msg.tool_calls:
                break
            for tc in msg.tool_calls:
                result = tools.call(tc.function.name, dict(tc.function.arguments))
                print(f"  [tool] {tc.function.name}({dict(tc.function.arguments)}) -> {result}")
                messages.append({"role": "tool", "tool_name": tc.function.name, "content": result})

        answer = (msg.content or "").strip() or "Готово."
        self.history.append({"role": "assistant", "content": answer})
        return answer
