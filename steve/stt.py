"""Распознавание речи: mlx-whisper, локально на Apple Silicon."""
import numpy as np

from . import config


def transcribe(audio: np.ndarray) -> tuple[str, str]:
    """Возвращает (текст, язык 'ru'/'en')."""
    import mlx_whisper  # ленивый импорт: долго грузится

    result = mlx_whisper.transcribe(
        audio.astype(np.float32),
        path_or_hf_repo=config.STT_MODEL,
        condition_on_previous_text=False,
    )
    text = result["text"].strip()
    lang = result.get("language", "ru")
    return text, "ru" if lang == "ru" else "en"
