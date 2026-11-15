"""Точка входа: `uv run steve` (голос) или `uv run steve --text` (клавиатура)."""
import argparse
import re

from . import audio, config
from .llm import Brain


def guess_lang(text: str) -> str:
    return "ru" if re.search("[а-яё]", text.lower()) else "en"


def main() -> None:
    ap = argparse.ArgumentParser(description=config.NAME)
    ap.add_argument("--text", action="store_true", help="писать с клавиатуры вместо микрофона")
    ap.add_argument("--mute", action="store_true", help="не озвучивать ответы")
    args = ap.parse_args()

    brain = Brain()
    print(f"{config.NAME} запущен. Ctrl+C — выход.")
    while True:
        try:
            if args.text:
                text = input("Ты: ").strip()
                lang = guess_lang(text)
            else:
                print("🎙  Слушаю...")
                clip = audio.record()
                if clip is None:
                    continue
                from . import stt
                text, lang = stt.transcribe(clip)
                print(f"Ты: {text}")
            if not text:
                continue
            answer = brain.ask(text)
            print(f"{config.NAME}: {answer}")
            if not args.mute:
                audio.speak(answer, guess_lang(answer))
        except (KeyboardInterrupt, EOFError):
            print("\nПока!")
            return


if __name__ == "__main__":
    main()
