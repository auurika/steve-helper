"""Запись с микрофона до паузы и озвучка через macOS `say`."""
import subprocess
import time

import numpy as np
import sounddevice as sd

from . import config


def record() -> np.ndarray | None:
    """Ждёт речь, пишет до паузы. None — если никто не заговорил."""
    block = int(config.SAMPLE_RATE * 0.1)
    chunks: list[np.ndarray] = []
    started = False
    silent = 0.0
    t0 = time.time()
    with sd.InputStream(samplerate=config.SAMPLE_RATE, channels=1, dtype="float32") as stream:
        while time.time() - t0 < config.MAX_RECORD_SEC:
            data, _ = stream.read(block)
            data = data[:, 0]
            loud = float(np.sqrt(np.mean(data**2))) > config.SILENCE_RMS
            if loud:
                started, silent = True, 0.0
            elif started:
                silent += 0.1
            if started:
                chunks.append(data)
                if silent >= config.SILENCE_SEC:
                    break
            elif time.time() - t0 > 8:  # 8 с никто не говорит — сдаёмся
                return None
    return np.concatenate(chunks) if chunks else None


def speak(text: str, lang: str = "ru") -> None:
    voice = config.VOICES.get(lang, config.VOICES["en"])
    subprocess.run(["say", "-v", voice, text], check=False)
